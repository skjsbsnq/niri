#!/usr/bin/env python3
"""Task 19: AppMenu must not poll native-menu probe every 5 seconds.

Root waste (old code):
  - Timer { interval: 5000; running: true; repeat: true; onTriggered: refresh() }
  - Shell lifetime ≈ 720 full python3/appmenu_probe.py starts per idle hour
  - Even while no menu UI is open and focus is stable

Fix contract (demand-gated, single pipeline):
  - Primary refresh authority is demand/event-driven:
      * focused window identity change → onFocusedWindowChanged → refresh()
      * menu open → AppMenuPopup.onOpenChanged → refresh()
      * initial load → Component.onCompleted → refresh()
  - Optional low-frequency health recovery only (minutes, not 5s) for
    registrar appear/disappear and missed dependency recovery
  - Single probe Process + Task 03 generation/identity pipeline unchanged
  - No second probe service/Process; no dual write authority

Regression strategy:
  1. Static contract extraction from AppMenu.qml + AppMenuPopup.qml
  2. Behavioral sim: idle hour process budget under event vs old 5s poll
  3. Preserve Task 03 identity contract markers
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
APP_MENU = SHELL_ROOT / "services" / "AppMenu.qml"
APP_MENU_POPUP = SHELL_ROOT / "components" / "AppMenuPopup.qml"


def _timer_blocks(src: str) -> list[str]:
    blocks: list[str] = []
    for m in re.finditer(r"\bTimer\s*\{", src):
        start = m.start()
        depth = 0
        i = start
        begun = False
        while i < len(src):
            if src[i] == "{":
                depth += 1
                begun = True
            elif src[i] == "}":
                depth -= 1
                if begun and depth == 0:
                    blocks.append(src[start : i + 1])
                    break
            i += 1
    return blocks


def _process_ids(src: str) -> list[str]:
    return re.findall(r"Process\s*\{\s*id:\s*(\w+)", src)


@dataclass(frozen=True)
class AppMenuDemandProbeContract:
    no_5s_unconditional_poll: bool
    focus_change_refreshes: bool
    menu_open_refreshes: bool
    completed_refreshes: bool
    health_recovery_if_present_is_slow: bool
    single_probe_process: bool
    keeps_probe_generation: bool
    no_second_probe_service: bool
    no_safe_refresh_api: bool

    @property
    def complete(self) -> bool:
        return all(getattr(self, name) for name in self.__annotations__)


def extract_contract(app_menu_src: str, popup_src: str) -> AppMenuDemandProbeContract:
    timers = _timer_blocks(app_menu_src)
    process_ids = _process_ids(app_menu_src)

    poll_5s = False
    health_ok = True
    has_health = False
    for block in timers:
        interval_m = re.search(r"interval:\s*(\d+)", block)
        if not interval_m:
            continue
        interval = int(interval_m.group(1))
        is_repeat = bool(re.search(r"repeat:\s*true", block))
        triggers_refresh = bool(
            re.search(r"onTriggered:.*\brefresh\s*\(", block, re.DOTALL)
        )
        if not (is_repeat and triggers_refresh and interval > 0):
            continue
        is_health = bool(
            re.search(r"id:\s*healthRecoveryTimer\b", block)
            or re.search(r"health", block, re.IGNORECASE)
        )
        if is_health:
            has_health = True
            # Recovery must be multi-minute class, not near-poll.
            if interval < 60_000:
                health_ok = False
        elif interval <= 5000:
            # Standing high-rate probe poll (old bug).
            poll_5s = True

    # If no health timer at all, still OK (pure event-driven); flag remains true.
    if not has_health:
        health_ok = True

    probe_like = [
        p for p in process_ids if "probe" in p.lower() or p == "probe"
    ]

    return AppMenuDemandProbeContract(
        no_5s_unconditional_poll=not poll_5s
        and not re.search(
            r"interval:\s*5000\s*\n\s*running:\s*true\s*\n\s*repeat:\s*true",
            app_menu_src,
        ),
        focus_change_refreshes=bool(
            re.search(
                r"onFocusedWindowChanged:\s*root\.refresh\s*\(\s*\)",
                app_menu_src,
            )
        ),
        menu_open_refreshes=bool(
            re.search(r"onOpenChanged", popup_src)
            and re.search(r"\.refresh\s*\(\s*(?:true)?\s*\)", popup_src)
        ),
        completed_refreshes=bool(
            re.search(
                r"Component\.onCompleted:\s*root\.refresh\s*\(\s*\)",
                app_menu_src,
            )
        ),
        health_recovery_if_present_is_slow=health_ok,
        single_probe_process=process_ids.count("probe") == 1
        and len(probe_like) == 1,
        keeps_probe_generation=bool(
            re.search(r"property\s+int\s+probeGeneration\b", app_menu_src)
            and re.search(r"property\s+bool\s+probePending\b", app_menu_src)
            and re.search(r"function\s+startProbe\s*\(", app_menu_src)
            and re.search(r"function\s+finishProbe\s*\(", app_menu_src)
        ),
        no_second_probe_service=not bool(
            re.search(
                r"safeRefresh|newRefresh|refresh2|secondProbe|probeService2",
                app_menu_src,
            )
        ),
        no_safe_refresh_api=not bool(
            re.search(
                r"function\s+safeRefresh\s*\(|function\s+demandRefresh\s*\(",
                app_menu_src,
            )
        ),
    )


class AppMenuProbeBudgetSim:
    """Counts probe starts under event-driven vs old poll models."""

    def __init__(
        self,
        poll_interval_ms: int | None = None,
        health_ms: int | None = 300_000,
    ) -> None:
        self.poll_interval_ms = poll_interval_ms
        self.health_ms = health_ms
        self.probe_starts = 0
        self.t = 0

    def on_focus_changed(self) -> None:
        self.probe_starts += 1

    def on_menu_open(self) -> None:
        self.probe_starts += 1

    def on_initial_load(self) -> None:
        self.probe_starts += 1

    def advance_idle_ms(self, ms: int) -> None:
        end = self.t + ms
        if self.poll_interval_ms:
            while self.t + self.poll_interval_ms <= end:
                self.t += self.poll_interval_ms
                self.probe_starts += 1
            self.t = end
            return
        if self.health_ms:
            while self.t + self.health_ms <= end:
                self.t += self.health_ms
                self.probe_starts += 1
            self.t = end
        else:
            self.t = end


class AppMenuDemandProbeTests(unittest.TestCase):
    def test_source_contract_is_complete(self) -> None:
        contract = extract_contract(
            APP_MENU.read_text(encoding="utf-8"),
            APP_MENU_POPUP.read_text(encoding="utf-8"),
        )
        missing = [
            name
            for name in AppMenuDemandProbeContract.__annotations__
            if not getattr(contract, name)
        ]
        self.assertEqual(
            missing,
            [],
            f"AppMenu demand-probe contract incomplete: {missing}",
        )

    def test_old_5s_poll_budget_is_about_720_per_idle_hour(self) -> None:
        old = AppMenuProbeBudgetSim(poll_interval_ms=5000, health_ms=None)
        old.advance_idle_ms(3_600_000)
        # 3600/5 = 720
        self.assertEqual(old.probe_starts, 720)

    def test_demand_driven_idle_hour_is_far_below_old_poll(self) -> None:
        fixed = AppMenuProbeBudgetSim(poll_interval_ms=None, health_ms=300_000)
        fixed.advance_idle_ms(3_600_000)
        # 3600/300 = 12 health recoveries max; << 720
        self.assertEqual(fixed.probe_starts, 12)
        self.assertLess(fixed.probe_starts, 50)
        self.assertLess(fixed.probe_starts * 20, 720)

    def test_focus_and_menu_open_refresh_without_poll(self) -> None:
        fixed = AppMenuProbeBudgetSim(poll_interval_ms=None, health_ms=300_000)
        fixed.on_initial_load()
        fixed.on_focus_changed()  # A
        fixed.on_focus_changed()  # B
        fixed.on_menu_open()
        # No idle advance: only explicit demand events.
        self.assertEqual(fixed.probe_starts, 4)

    def test_no_interval_5000_standing_refresh_timer_in_source(self) -> None:
        src = APP_MENU.read_text(encoding="utf-8")
        self.assertIsNone(
            re.search(
                r"interval:\s*5000\s*\n\s*running:\s*true\s*\n\s*repeat:\s*true\s*\n\s*onTriggered:\s*root\.refresh\s*\(\s*\)",
                src,
            )
        )

    def test_health_recovery_timer_is_not_sub_minute(self) -> None:
        src = APP_MENU.read_text(encoding="utf-8")
        m = re.search(
            r"id:\s*healthRecoveryTimer\s*.*?interval:\s*(\d+)",
            src,
            re.DOTALL,
        )
        self.assertIsNotNone(
            m, "health recovery timer should exist for registrar recovery"
        )
        assert m is not None
        self.assertGreaterEqual(int(m.group(1)), 60_000)

    def test_task03_identity_pipeline_still_present(self) -> None:
        src = APP_MENU.read_text(encoding="utf-8")
        for token in (
            "probeGeneration",
            "probePending",
            "probeTargetIdentity",
            "startProbe",
            "finishProbe",
            "applyProbe",
        ):
            self.assertIn(token, src)

    def test_single_probe_process_only(self) -> None:
        src = APP_MENU.read_text(encoding="utf-8")
        ids = _process_ids(src)
        self.assertEqual(ids.count("probe"), 1)
        self.assertIn("trigger", ids)


if __name__ == "__main__":
    unittest.main()
