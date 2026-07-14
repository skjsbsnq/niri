#!/usr/bin/env python3
"""Task 18: ClipboardHistory must not poll cliphist list every 4 seconds.

Root waste (old code):
  - Timer { interval: 4000; running: true; repeat: true; onTriggered: refresh() }
  - Shell lifetime ≈ 900 full `cliphist list` process starts per idle hour
  - Even while wl-paste --watch cliphist store already handles clipboard writes

Fix contract:
  - Primary refresh authority is event-driven: watcher stores then emits a line;
    ClipboardHistory SplitParser schedules the existing refresh() path
  - Popup open / delete / clear / manual refresh keep using refresh/scheduleRefresh
  - Optional low-frequency health recovery only (minutes, not 4s)
  - Single watcher Process; no second watcher; no permanent dual poll authority
  - Initial load via detectTools / applyCommandRunnerTools still calls refresh

Regression strategy:
  1. Static contract extraction from ClipboardHistory.qml + CommandRunner.qml
  2. Behavioral sim: idle hour process budget under event vs old 4s poll
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import unittest
from dataclasses import dataclass
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
CLIPBOARD = SHELL_ROOT / "services" / "ClipboardHistory.qml"
COMMAND_RUNNER = SHELL_ROOT / "services" / "CommandRunner.qml"
CLIPBOARD_POPUP = SHELL_ROOT / "components" / "ClipboardPopup.qml"
QML_TEST = Path(__file__).with_name("tst_clipboard_history_event_refresh.qml")


def _extract_function_body(src: str, name: str) -> str:
    m = re.search(
        rf"function\s+{re.escape(name)}\s*\([^)]*\)\s*\{{",
        src,
    )
    if not m:
        return ""
    start = m.end()
    depth = 1
    i = start
    while i < len(src) and depth:
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return src[start : i - 1]


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


def _process_block(src: str, process_id: str) -> str:
    m = re.search(rf"Process\s*\{{\s*id:\s*{re.escape(process_id)}\b", src)
    if not m:
        return ""
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
                return src[start : i + 1]
        i += 1
    return ""


@dataclass(frozen=True)
class ClipboardEventRefreshContract:
    no_4s_unconditional_poll: bool
    watcher_emits_change_marker: bool
    watcher_has_split_parser: bool
    watcher_parser_schedules_refresh: bool
    has_schedule_refresh: bool
    health_recovery_if_present_is_slow: bool
    single_clipboard_watcher_process: bool
    command_runner_watch_emits_marker: bool
    popup_refreshes_on_open: bool
    delete_and_clear_still_schedule: bool
    no_second_watcher: bool
    has_refresh_pending: bool
    refresh_sets_pending_when_running: bool
    finish_list_probe_replays_pending: bool
    list_probe_running_changed_fallback: bool
    no_parallel_refresh_api: bool

    @property
    def complete(self) -> bool:
        return all(getattr(self, name) for name in self.__annotations__)


def extract_contract(clipboard_src: str, runner_src: str, popup_src: str) -> ClipboardEventRefreshContract:
    watcher = _process_block(clipboard_src, "clipboardWatcher")
    timers = _timer_blocks(clipboard_src)
    delete_body = _extract_function_body(clipboard_src, "deleteEntry")
    clear_body = _extract_function_body(clipboard_src, "clearHistory")
    watch_cmd_body = _extract_function_body(runner_src, "clipboardWatchCommand")

    poll_4s = False
    health_ok = True
    for block in timers:
        interval_m = re.search(r"interval:\s*(\d+)", block)
        if not interval_m:
            continue
        interval = int(interval_m.group(1))
        is_repeat = bool(re.search(r"repeat:\s*true", block))
        triggers_refresh = bool(
            re.search(r"onTriggered:.*\brefresh\s*\(", block, re.DOTALL)
        )
        if is_repeat and triggers_refresh and interval <= 4000 and interval > 0:
            # Standing high-rate list poll (old bug).
            if "healthRecovery" not in block and "health" not in block.lower():
                poll_4s = True
            # Named health recovery at <=4s is still too fast.
            if "healthRecovery" in block or re.search(r"id:\s*health", block):
                health_ok = False
        if is_repeat and triggers_refresh and "healthRecovery" in block:
            # Recovery must be multi-minute class, not near-poll.
            if interval < 60_000:
                health_ok = False

    marker_in_watcher = bool(
        re.search(r"printf|changed|echo", watcher)
        or re.search(r"cliphist store;", watcher)
    )
    marker_in_runner = bool(
        re.search(r"printf|changed", watch_cmd_body)
        and re.search(r"cliphist store", watch_cmd_body)
    )

    refresh_fn = _extract_function_body(clipboard_src, "refresh")
    finish_fn = _extract_function_body(clipboard_src, "finishListProbe")
    list_probe = _process_block(clipboard_src, "listProbe")
    has_refresh_pending = bool(
        re.search(r"property\s+bool\s+refreshPending\b", clipboard_src)
    )
    refresh_sets_pending_when_running = bool(
        re.search(r"listProbe\.running", refresh_fn)
        and re.search(r"refreshPending\s*=\s*true", refresh_fn)
    )
    finish_list_probe_replays_pending = bool(
        finish_fn
        and re.search(r"refreshPending", finish_fn)
        and re.search(r"Qt\.callLater\s*\(\s*root\.refresh", finish_fn)
    )
    list_probe_running_changed_fallback = bool(
        re.search(r"onRunningChanged\s*:", list_probe)
        and re.search(r"finishListProbe", list_probe)
    )
    no_parallel_refresh_api = not bool(
        re.search(r"function\s+(refreshNow|refreshSafe|safeRefresh)\s*\(", clipboard_src)
    )

    return ClipboardEventRefreshContract(
        no_4s_unconditional_poll=not poll_4s
        and not re.search(
            r"interval:\s*4000\s*\n\s*running:\s*true\s*\n\s*repeat:\s*true",
            clipboard_src,
        ),
        watcher_emits_change_marker=marker_in_watcher,
        watcher_has_split_parser="SplitParser" in watcher,
        watcher_parser_schedules_refresh=bool(
            re.search(r"scheduleRefresh\s*\(", watcher)
        ),
        has_schedule_refresh="function scheduleRefresh" in clipboard_src,
        health_recovery_if_present_is_slow=health_ok,
        single_clipboard_watcher_process=len(
            re.findall(r"id:\s*clipboardWatcher\b", clipboard_src)
        )
        == 1,
        command_runner_watch_emits_marker=marker_in_runner,
        popup_refreshes_on_open=bool(
            re.search(r"onOpenChanged", popup_src)
            and re.search(r"\.refresh\s*\(", popup_src)
        ),
        delete_and_clear_still_schedule=bool(
            re.search(r"scheduleRefresh", delete_body)
            and re.search(r"scheduleRefresh", clear_body)
        ),
        no_second_watcher=not re.search(
            r"clipboardWatcher2|secondWatcher|safeStartWatcher", clipboard_src
        ),
        has_refresh_pending=has_refresh_pending,
        refresh_sets_pending_when_running=refresh_sets_pending_when_running,
        finish_list_probe_replays_pending=finish_list_probe_replays_pending,
        list_probe_running_changed_fallback=list_probe_running_changed_fallback,
        no_parallel_refresh_api=no_parallel_refresh_api,
    )


class ClipboardEventSim:
    """Counts list refreshes under event-driven vs old poll models."""

    def __init__(self, poll_interval_ms: int | None = None, health_ms: int | None = 300_000) -> None:
        self.poll_interval_ms = poll_interval_ms
        self.health_ms = health_ms
        self.list_starts = 0
        self.t = 0

    def on_clipboard_changed(self) -> None:
        # Event path: watcher store marker → scheduleRefresh → refresh.
        self.list_starts += 1

    def on_popup_open(self) -> None:
        self.list_starts += 1

    def on_delete_or_clear(self) -> None:
        self.list_starts += 1

    def advance_idle_ms(self, ms: int) -> None:
        end = self.t + ms
        if self.poll_interval_ms:
            # Old unconditional poll.
            while self.t + self.poll_interval_ms <= end:
                self.t += self.poll_interval_ms
                self.list_starts += 1
            self.t = end
            return
        # Event-driven: only optional health recovery fires while idle.
        if self.health_ms:
            while self.t + self.health_ms <= end:
                self.t += self.health_ms
                self.list_starts += 1
            self.t = end
        else:
            self.t = end


class ClipboardHistoryEventRefreshTests(unittest.TestCase):
    def test_source_contract_is_complete(self) -> None:
        contract = extract_contract(
            CLIPBOARD.read_text(encoding="utf-8"),
            COMMAND_RUNNER.read_text(encoding="utf-8"),
            CLIPBOARD_POPUP.read_text(encoding="utf-8"),
        )
        missing = [
            name
            for name in ClipboardEventRefreshContract.__annotations__
            if not getattr(contract, name)
        ]
        self.assertEqual(missing, [], f"clipboard event-refresh contract incomplete: {missing}")

    def test_old_4s_poll_budget_is_about_900_per_idle_hour(self) -> None:
        old = ClipboardEventSim(poll_interval_ms=4000, health_ms=None)
        old.advance_idle_ms(3_600_000)
        # 3600/4 = 900
        self.assertEqual(old.list_starts, 900)

    def test_event_driven_idle_hour_is_far_below_old_poll(self) -> None:
        fixed = ClipboardEventSim(poll_interval_ms=None, health_ms=300_000)
        fixed.advance_idle_ms(3_600_000)
        # 3600/300 = 12 health recoveries max; << 900
        self.assertEqual(fixed.list_starts, 12)
        self.assertLess(fixed.list_starts, 50)
        self.assertLess(fixed.list_starts * 20, 900)

    def test_copy_events_refresh_without_poll(self) -> None:
        fixed = ClipboardEventSim(poll_interval_ms=None, health_ms=300_000)
        for _ in range(5):
            fixed.on_clipboard_changed()
        fixed.on_popup_open()
        fixed.on_delete_or_clear()
        # No idle advance: only explicit events.
        self.assertEqual(fixed.list_starts, 7)

    def test_no_interval_4000_standing_refresh_timer_in_source(self) -> None:
        src = CLIPBOARD.read_text(encoding="utf-8")
        # Explicit negative: the historical unconditional block must be gone.
        self.assertIsNone(
            re.search(
                r"interval:\s*4000\s*\n\s*running:\s*true\s*\n\s*repeat:\s*true\s*\n\s*onTriggered:\s*root\.refresh\s*\(\s*\)",
                src,
            )
        )

    def test_health_recovery_timer_is_not_sub_minute(self) -> None:
        src = CLIPBOARD.read_text(encoding="utf-8")
        m = re.search(
            r"id:\s*healthRecoveryTimer\s*.*?interval:\s*(\d+)",
            src,
            re.DOTALL,
        )
        self.assertIsNotNone(m, "health recovery timer should exist for missed events")
        assert m is not None
        self.assertGreaterEqual(int(m.group(1)), 60_000)

    def test_watcher_command_still_stores_via_cliphist(self) -> None:
        runner = COMMAND_RUNNER.read_text(encoding="utf-8")
        body = _extract_function_body(runner, "clipboardWatchCommand")
        self.assertIn("cliphist store", body)
        self.assertIn("wl-paste", body)
        self.assertRegex(body, r"printf|echo")


    def test_source_has_refresh_pending_coalesce(self) -> None:
        contract = extract_contract(
            CLIPBOARD.read_text(encoding="utf-8"),
            COMMAND_RUNNER.read_text(encoding="utf-8"),
            CLIPBOARD_POPUP.read_text(encoding="utf-8"),
        )
        self.assertTrue(contract.has_refresh_pending)
        self.assertTrue(contract.refresh_sets_pending_when_running)
        self.assertTrue(contract.finish_list_probe_replays_pending)
        self.assertTrue(contract.list_probe_running_changed_fallback)
        self.assertTrue(contract.no_parallel_refresh_api)

    def test_real_qml_lossless_refresh(self) -> None:
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(runner, "Qt 6 qmltestrunner is required for ClipboardHistory coverage")
        env = os.environ.copy()
        env.setdefault("QT_QPA_PLATFORM", "offscreen")
        local_qml = Path.home() / ".local" / "lib" / "qt6" / "qml"
        test_qml = SHELL_ROOT / "tests" / "qml_imports"
        existing = env.get("QML2_IMPORT_PATH", "")
        paths = [str(test_qml), str(local_qml)]
        if existing:
            paths.append(existing)
        env["QML2_IMPORT_PATH"] = ":".join(paths)
        result = subprocess.run(
            [runner, "-input", str(QML_TEST)],
            cwd=SHELL_ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    unittest.main()
