#!/usr/bin/env python3
"""Task 03: AppMenu probe results must bind to request generation.

Root race (old code):
  1. Focus window A → refresh starts probe.running for A
  2. Focus switches to B while probe still running → refresh() early-returns
     because probe.running, so B's refresh is permanently discarded
  3. A's onStreamFinished / onExited write registrar/menu/probing without
     identity checks → B's menu shows A's items, and A's exit can clear
     probing for a later request

Fix contract:
  - Single Process pipeline owned by AppMenu
  - probeGeneration advances on every refresh intent
  - In-flight results/errors only apply when generation still matches latest
  - generation is mandatory on applyProbe (undefined/null never writes)
  - probePending re-runs only the newest intent after Process exit settles
  - Restart is deferred (Qt.callLater), never synchronous inside onExited
  - Old exit must not clear probing for a newer generation
  - No safeRefresh / second Process / debounce Timer / unconditional post-exit refresh
  - No unused parallel identity fields (window/pid/app must not be dead decoration)

Regression strategy:
  1. Static contract extraction from AppMenu.qml (fails on old discard path).
  2. Behavioral simulation of A success/failure late, A→B, A→B→C, sync
     dependency paths, and deferred pending re-run.
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass, field
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
APP_MENU = SHELL_ROOT / "services" / "AppMenu.qml"


@dataclass(frozen=True)
class AppMenuProbeContract:
    """Wiring discovered in source. Missing edges reproduce the old race."""

    has_probe_generation: bool
    has_in_flight_generation: bool
    has_probe_pending: bool
    refresh_bumps_generation: bool
    refresh_sets_pending_when_running: bool
    refresh_does_not_drop_when_running: bool
    start_probe_exists: bool
    start_probe_freezes_command_before_running: bool
    apply_probe_requires_generation: bool
    apply_probe_rejects_stale: bool
    finish_probe_exists: bool
    finish_probe_gates_probing_clear: bool
    finish_probe_schedules_pending: bool
    deferred_pending_restart: bool
    stdout_cached_with_generation: bool
    on_exited_uses_finish_probe: bool
    failed_start_uses_finish_probe: bool
    finish_consumes_in_flight_generation: bool
    single_probe_process: bool
    no_safe_refresh: bool
    no_second_process_for_probe: bool
    no_debounce_timer_for_probe: bool
    no_dead_inflight_identity_fields: bool

    @property
    def identity_path_complete(self) -> bool:
        return all(
            getattr(self, name)
            for name in AppMenuProbeContract.__annotations__
        )


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


def _extract_process_block(src: str, process_id: str) -> str:
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


def extract_contract(src: str) -> AppMenuProbeContract:
    refresh_fn = _extract_function_body(src, "refresh")
    start_fn = _extract_function_body(src, "startProbe")
    apply_fn = _extract_function_body(src, "applyProbe")
    finish_fn = _extract_function_body(src, "finishProbe")
    schedule_fn = _extract_function_body(src, "schedulePendingProbe")
    probe_block = _extract_process_block(src, "probe")

    process_ids = re.findall(r"Process\s*\{\s*id:\s*(\w+)", src)
    probe_like = [p for p in process_ids if "probe" in p.lower() or p == "probe"]

    old_drop_signature = bool(
        re.search(
            r"if\s*\(\s*!probe\.running\s*\)\s*\{\s*probing\s*=\s*true\s*;\s*probe\.running\s*=\s*true\s*;\s*\}",
            refresh_fn,
            re.DOTALL,
        )
    ) or (
        "probe.running" in refresh_fn
        and "probePending" not in refresh_fn
        and "pending" not in refresh_fn.lower()
    )

    # Mandatory generation: reject undefined/null, then compare.
    apply_requires_generation = bool(
        re.search(r"generation\s*===\s*undefined|generation\s*===\s*null", apply_fn)
        and re.search(r"return", apply_fn)
    )
    apply_rejects_stale = bool(
        re.search(
            r"Number\(generation\)\s*!==\s*Number\(probeGeneration\)",
            apply_fn,
        )
    )
    # Must NOT keep the optional-gate pattern that skips when generation is missing.
    apply_optional_bypass = bool(
        re.search(
            r"generation\s*!==\s*undefined\s*&&\s*generation\s*!==\s*null\s*&&",
            apply_fn,
        )
    )

    # probing=false only when gen matches latest.
    finish_gates_probing = bool(
        re.search(
            r"gen\s*===\s*Number\(probeGeneration\)[\s\S]{0,80}probing\s*=\s*false",
            finish_fn,
        )
        or re.search(
            r"if\s*\(\s*gen\s*===\s*Number\(probeGeneration\)\s*\)\s*probing\s*=\s*false",
            finish_fn,
        )
    )

    deferred_restart = bool(
        re.search(r"Qt\.callLater", schedule_fn)
        or re.search(r"Qt\.callLater", finish_fn)
    ) and bool(
        re.search(r"function\s+schedulePendingProbe", src)
        or re.search(r"Qt\.callLater", finish_fn)
    )

    # startProbe must assign command before running=true.
    cmd_idx = start_fn.find("probe.command")
    run_idx = start_fn.find("probe.running = true")
    if run_idx < 0:
        run_idx = start_fn.find("probe.running=true")
    freezes_command = cmd_idx >= 0 and run_idx > cmd_idx

    stdout_cached = bool(
        re.search(r"probeStdoutText", probe_block)
        and re.search(r"probeStdoutGeneration", probe_block)
        and re.search(r"onStreamFinished", probe_block)
    )

    unconditional_post_exit_refresh = bool(
        re.search(r"\brefresh\s*\(\s*\)", finish_fn)
        or re.search(r"onExited:[\s\S]*?\brefresh\s*\(\s*\)", probe_block)
    )

    debounce_timer = bool(
        re.search(
            r"Timer\s*\{[^}]*debounce|probeDebounce|refreshDebounce",
            src,
            re.DOTALL | re.IGNORECASE,
        )
    )

    dead_inflight_fields = bool(
        re.search(r"property\s+string\s+probeInFlightWindowId\b", src)
        or re.search(r"property\s+string\s+probeInFlightPid\b", src)
        or re.search(r"property\s+string\s+probeInFlightAppId\b", src)
    )

    return AppMenuProbeContract(
        has_probe_generation=bool(
            re.search(r"property\s+int\s+probeGeneration\b", src)
        ),
        has_in_flight_generation=bool(
            re.search(r"property\s+int\s+probeInFlightGeneration\b", src)
        ),
        has_probe_pending=bool(
            re.search(r"property\s+bool\s+probePending\b", src)
        ),
        refresh_bumps_generation=bool(
            re.search(r"probeGeneration\s*\+=\s*1", refresh_fn)
        ),
        refresh_sets_pending_when_running=bool(
            re.search(r"probe\.running", refresh_fn)
            and re.search(r"probePending\s*=\s*true", refresh_fn)
        ),
        refresh_does_not_drop_when_running=not old_drop_signature,
        start_probe_exists=bool(re.search(r"function\s+startProbe\s*\(", src)),
        start_probe_freezes_command_before_running=freezes_command,
        apply_probe_requires_generation=apply_requires_generation
        and not apply_optional_bypass,
        apply_probe_rejects_stale=apply_rejects_stale,
        finish_probe_exists=bool(re.search(r"function\s+finishProbe\s*\(", src)),
        finish_probe_gates_probing_clear=finish_gates_probing,
        finish_probe_schedules_pending=bool(
            re.search(r"probePending", finish_fn)
            and (
                re.search(r"schedulePendingProbe", finish_fn)
                or re.search(r"Qt\.callLater", finish_fn)
            )
        ),
        deferred_pending_restart=deferred_restart,
        stdout_cached_with_generation=stdout_cached,
        on_exited_uses_finish_probe=bool(
            re.search(r"finishProbe\s*\(", probe_block)
        ),
        failed_start_uses_finish_probe=bool(
            re.search(r"onRunningChanged", probe_block)
            and re.search(
                r"!probe\.running[\s\S]{0,160}finishProbe\s*\(",
                probe_block,
            )
        ),
        finish_consumes_in_flight_generation=bool(
            re.search(
                r"probeInFlightGeneration\s*=\s*0",
                finish_fn,
            )
        ),
        single_probe_process=process_ids.count("probe") == 1
        and "trigger" in process_ids,
        no_safe_refresh=not bool(
            re.search(
                r"function\s+safeRefresh\s*\(|function\s+newRefresh\s*\(|function\s+refresh2\s*\(",
                src,
            )
        ),
        no_second_process_for_probe=len(probe_like) == 1
        and not bool(
            re.search(r"id:\s*probe2\b|id:\s*safeProbe\b|id:\s*menuProbe\b", src)
        ),
        no_debounce_timer_for_probe=not debounce_timer
        and not unconditional_post_exit_refresh,
        no_dead_inflight_identity_fields=not dead_inflight_fields,
    )


@dataclass
class MenuState:
    service: str = ""
    path: str = ""
    items: list = field(default_factory=list)
    status: str = ""
    detail: str = ""
    probing: bool = False


class AppMenuProbeModel:
    """Simulates AppMenu refresh/apply/finish generation semantics.

    When use_identity is False, mirrors the old path:
      - drop refresh while running
      - apply any completion unconditionally
      - always clear probing on exit
    """

    def __init__(self, *, use_identity: bool) -> None:
        self.use_identity = use_identity
        self.probe_generation = 0
        self.probe_in_flight_generation = 0
        self.probe_pending = False
        self.running = False
        self.focus_window_id = ""
        self.in_flight_window_id = ""
        self.state = MenuState()
        self.started_window_ids: list[str] = []
        self.applied_generations: list[int] = []
        self.rejected_generations: list[int] = []
        self.deferred: list = []

    def set_focus(self, window_id: str) -> None:
        self.focus_window_id = window_id
        self.refresh()

    def refresh(self) -> None:
        if self.use_identity:
            self.probe_generation += 1
            if self.running:
                self.probe_pending = True
                return
            self._start_probe(self.probe_generation)
            return

        if self.running:
            return
        self.state.probing = True
        self.running = True
        self.in_flight_window_id = self.focus_window_id
        self.started_window_ids.append(self.focus_window_id)

    def refresh_dependency_missing(self, detail: str = "missing bridge") -> None:
        """Sync dependency/missing path: bump gen, clear pending/probing, stop process, apply."""
        if not self.use_identity:
            self.state.probing = False
            self.running = False
            self.apply_probe(
                {
                    "status": "应用菜单不可用",
                    "detail": detail,
                    "items": [],
                }
            )
            return
        self.probe_generation += 1
        self.probe_pending = False
        self.state.probing = False
        # Mirror QML: stop in-flight Process; its later exit is stale by generation.
        was_running = self.running
        self.running = False
        self.apply_probe(
            {
                "status": "应用菜单不可用",
                "detail": detail,
                "items": [],
            },
            self.probe_generation,
        )
        # If a Process was stopped, a deferred exit may still arrive with old generation.
        if was_running:
            pass  # caller may still invoke process_exited for the cancelled A

    def _start_probe(self, generation: int) -> None:
        if self.use_identity:
            if generation != self.probe_generation:
                return
            if self.running:
                self.probe_pending = True
                return
        self.probe_pending = False
        self.probe_in_flight_generation = generation
        self.in_flight_window_id = self.focus_window_id
        self.state.probing = True
        self.running = True
        self.started_window_ids.append(self.focus_window_id)

    def apply_probe(self, payload: dict, generation: int | None = None) -> None:
        if self.use_identity:
            if generation is None:
                self.rejected_generations.append(-1)
                return
            if generation != self.probe_generation:
                self.rejected_generations.append(int(generation))
                return
            self.applied_generations.append(int(generation))
        else:
            self.applied_generations.append(-1)

        self.state.service = str(payload.get("menuService", ""))
        self.state.path = str(payload.get("menuPath", ""))
        self.state.items = list(payload.get("items") or [])
        self.state.status = str(payload.get("status", ""))
        self.state.detail = str(payload.get("detail", ""))

    def process_exited(self, payload: dict | None = None, code: int = 0) -> None:
        """Mirror finishProbe + deferred schedulePendingProbe."""
        generation = self.probe_in_flight_generation
        self.running = False

        if self.use_identity:
            if code != 0:
                self.apply_probe(
                    {
                        "status": "应用菜单检测失败",
                        "detail": f"helper exit {code}",
                        "items": [],
                    },
                    generation,
                )
            elif payload is not None:
                self.apply_probe(payload, generation)

            if generation == self.probe_generation:
                self.state.probing = False

            if self.probe_pending:
                # Defer like Qt.callLater — not same-stack start.
                self.deferred.append(self.probe_generation)
            return

        if code != 0:
            self.apply_probe(
                {
                    "status": "应用菜单检测失败",
                    "detail": f"helper exit {code}",
                    "items": [],
                }
            )
        elif payload is not None:
            self.apply_probe(payload)
        self.state.probing = False

    def process_failed_to_start(self) -> None:
        """Mirror Process::onErrorOccurred(FailedToStart): no exited signal."""
        generation = self.probe_in_flight_generation
        self.running = False
        if not self.use_identity:
            # The old QML has no runningChanged fallback and remains loading.
            return
        self.probe_in_flight_generation = 0
        self.apply_probe(
            {
                "status": "应用菜单检测失败",
                "detail": "helper exit -1",
                "items": [],
            },
            generation,
        )
        if generation == self.probe_generation and not self.probe_pending:
            self.state.probing = False
        if self.probe_pending:
            self.deferred.append(self.probe_generation)

    def drain_deferred(self) -> None:
        """Run deferred pending starts (callLater queue)."""
        while self.deferred:
            gen = self.deferred.pop(0)
            if not self.probe_pending:
                continue
            if self.running:
                continue
            self._start_probe(self.probe_generation if self.use_identity else gen)


def _menu_payload(window_id: str, *, ok: bool = True) -> dict:
    if not ok:
        return {
            "status": "应用菜单检测失败",
            "detail": f"helper exit 1 for {window_id}",
            "menuService": "",
            "menuPath": "",
            "items": [],
        }
    return {
        "status": f"menu for {window_id}",
        "detail": f"detail {window_id}",
        "menuService": f"svc.{window_id}",
        "menuPath": f"/Menu/{window_id}",
        "items": [{"id": 1, "label": window_id, "kind": "item", "enabled": True}],
    }


class AppMenuProbeIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.src = APP_MENU.read_text(encoding="utf-8")
        cls.contract = extract_contract(cls.src)

    def test_source_contract_binds_probe_to_request_generation(self) -> None:
        c = self.contract
        self.assertTrue(
            c.identity_path_complete,
            msg=(
                "AppMenu probe identity contract incomplete:\n"
                + "\n".join(
                    f"  {name}={getattr(c, name)}"
                    for name in AppMenuProbeContract.__annotations__
                )
            ),
        )

    def test_old_path_a_success_late_pollutes_b(self) -> None:
        m = AppMenuProbeModel(use_identity=False)
        m.set_focus("A")
        self.assertTrue(m.running)
        m.set_focus("B")
        self.assertEqual(m.started_window_ids, ["A"])
        m.process_exited(_menu_payload("A"), code=0)
        self.assertEqual(m.state.service, "svc.A")
        self.assertEqual(m.state.items[0]["label"], "A")
        self.assertFalse(m.state.probing)

    def test_new_path_a_success_late_does_not_pollute_b(self) -> None:
        m = AppMenuProbeModel(use_identity=True)
        m.set_focus("A")
        gen_a = m.probe_in_flight_generation
        m.set_focus("B")
        self.assertTrue(m.probe_pending)
        self.assertEqual(m.probe_generation, gen_a + 1)
        m.process_exited(_menu_payload("A"), code=0)
        self.assertIn(gen_a, m.rejected_generations)
        # Pending restart is deferred — not same-stack.
        self.assertFalse(m.running)
        self.assertEqual(m.state.items, [])
        self.assertTrue(m.state.probing)  # B intent still loading until B completes
        m.drain_deferred()
        self.assertTrue(m.running)
        self.assertEqual(m.in_flight_window_id, "B")
        m.process_exited(_menu_payload("B"), code=0)
        m.drain_deferred()
        self.assertEqual(m.state.service, "svc.B")
        self.assertEqual(m.state.items[0]["label"], "B")
        self.assertFalse(m.state.probing)
        self.assertFalse(m.running)

    def test_new_path_a_failure_late_does_not_pollute_b(self) -> None:
        m = AppMenuProbeModel(use_identity=True)
        m.set_focus("A")
        gen_a = m.probe_in_flight_generation
        m.set_focus("B")
        m.process_exited(code=1)
        self.assertIn(gen_a, m.rejected_generations)
        m.drain_deferred()
        self.assertTrue(m.running)
        self.assertEqual(m.in_flight_window_id, "B")
        self.assertTrue(m.state.probing)
        m.process_exited(_menu_payload("B"), code=0)
        m.drain_deferred()
        self.assertEqual(m.state.service, "svc.B")
        self.assertNotIn("helper exit", m.state.detail)

    def test_new_path_failed_start_releases_latest_loading(self) -> None:
        m = AppMenuProbeModel(use_identity=True)
        m.set_focus("A")
        m.process_failed_to_start()
        self.assertFalse(m.running)
        self.assertFalse(m.state.probing)
        self.assertEqual(m.state.status, "应用菜单检测失败")
        self.assertIn("helper exit -1", m.state.detail)

    def test_new_path_failed_start_of_a_still_runs_latest_b(self) -> None:
        m = AppMenuProbeModel(use_identity=True)
        m.set_focus("A")
        gen_a = m.probe_in_flight_generation
        m.set_focus("B")
        m.process_failed_to_start()
        self.assertIn(gen_a, m.rejected_generations)
        self.assertTrue(m.state.probing)
        m.drain_deferred()
        self.assertTrue(m.running)
        self.assertEqual(m.in_flight_window_id, "B")

    def test_new_path_a_exit_does_not_clear_b_loading(self) -> None:
        m = AppMenuProbeModel(use_identity=True)
        m.set_focus("A")
        m.set_focus("B")
        m.process_exited(_menu_payload("A"), code=0)
        # Before deferred start, probing must still reflect latest intent.
        self.assertTrue(m.state.probing, "B must still be loading after A's exit")
        m.drain_deferred()
        self.assertTrue(m.running)
        self.assertEqual(m.in_flight_window_id, "B")

    def test_new_path_a_to_b_to_c_only_latest_runs_after_a(self) -> None:
        m = AppMenuProbeModel(use_identity=True)
        m.set_focus("A")
        m.set_focus("B")
        m.set_focus("C")
        self.assertTrue(m.probe_pending)
        self.assertEqual(m.started_window_ids, ["A"])
        m.process_exited(_menu_payload("A"), code=0)
        m.drain_deferred()
        self.assertEqual(m.started_window_ids, ["A", "C"])
        self.assertEqual(m.in_flight_window_id, "C")
        m.process_exited(_menu_payload("C"), code=0)
        m.drain_deferred()
        self.assertEqual(m.state.service, "svc.C")
        self.assertEqual(m.state.items[0]["label"], "C")
        self.assertFalse(m.state.probing)

    def test_new_path_success_as_latest_still_works(self) -> None:
        m = AppMenuProbeModel(use_identity=True)
        m.set_focus("A")
        m.process_exited(_menu_payload("A"), code=0)
        m.drain_deferred()
        self.assertEqual(m.state.service, "svc.A")
        self.assertFalse(m.state.probing)
        self.assertFalse(m.probe_pending)
        self.assertFalse(m.running)

    def test_new_path_apply_without_generation_is_rejected(self) -> None:
        m = AppMenuProbeModel(use_identity=True)
        m.set_focus("A")
        m.apply_probe(_menu_payload("X"), generation=None)
        self.assertEqual(m.state.items, [])
        self.assertIn(-1, m.rejected_generations)
        # Live A result still applies with generation.
        m.process_exited(_menu_payload("A"), code=0)
        m.drain_deferred()
        self.assertEqual(m.state.items[0]["label"], "A")

    def test_new_path_sync_missing_during_a_then_a_exit_does_not_overwrite(self) -> None:
        m = AppMenuProbeModel(use_identity=True)
        m.set_focus("A")
        gen_a = m.probe_in_flight_generation
        m.refresh_dependency_missing("bridge gone")
        self.assertEqual(m.state.status, "应用菜单不可用")
        self.assertFalse(m.state.probing)
        self.assertFalse(m.probe_pending)
        # A exit late — must not overwrite sync unavailable state.
        m.process_exited(_menu_payload("A"), code=0)
        m.drain_deferred()
        self.assertIn(gen_a, m.rejected_generations)
        self.assertEqual(m.state.status, "应用菜单不可用")
        self.assertEqual(m.state.items, [])
        self.assertFalse(m.running)

    def test_new_path_sync_missing_then_focus_b_still_probes(self) -> None:
        m = AppMenuProbeModel(use_identity=True)
        m.set_focus("A")
        m.refresh_dependency_missing("bridge gone")
        # Dependency path recovered in model terms: just focus B and probe again.
        m.set_focus("B")
        self.assertTrue(m.running)
        self.assertEqual(m.in_flight_window_id, "B")
        m.process_exited(_menu_payload("B"), code=0)
        m.drain_deferred()
        self.assertEqual(m.state.service, "svc.B")

    def test_new_path_supersede_as_cancel_keeps_b_loading(self) -> None:
        """A is superseded (cancelled by newer intent): no A menu, B stays loading."""
        m = AppMenuProbeModel(use_identity=True)
        m.set_focus("A")
        m.set_focus("B")
        m.process_exited(_menu_payload("A"), code=0)
        self.assertNotEqual(m.state.service, "svc.A")
        self.assertTrue(m.state.probing)
        m.drain_deferred()
        self.assertEqual(m.in_flight_window_id, "B")

    def test_old_path_loses_b_refresh_forever(self) -> None:
        m = AppMenuProbeModel(use_identity=False)
        m.set_focus("A")
        m.set_focus("B")
        m.process_exited(_menu_payload("A"), code=0)
        self.assertEqual(m.started_window_ids, ["A"])
        self.assertEqual(m.state.items[0]["label"], "A")

    def test_source_forbids_parallel_refresh_api(self) -> None:
        src = self.src
        self.assertNotRegex(src, r"function\s+safeRefresh\s*\(")
        self.assertNotRegex(src, r"function\s+fixedRefresh\s*\(")
        self.assertNotRegex(src, r"id:\s*probe2\b")
        self.assertNotRegex(src, r"probeInFlightWindowId")
        ids = re.findall(r"Process\s*\{\s*id:\s*(\w+)", src)
        self.assertEqual(sorted(ids), ["probe", "trigger"])

    def test_source_finish_probe_does_not_start_inline(self) -> None:
        finish = _extract_function_body(self.src, "finishProbe")
        self.assertNotRegex(finish, r"startProbe\s*\(")
        self.assertRegex(finish, r"schedulePendingProbe|Qt\.callLater")


if __name__ == "__main__":
    unittest.main()
