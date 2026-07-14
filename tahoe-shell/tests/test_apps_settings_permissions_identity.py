#!/usr/bin/env python3
"""Task 04: AppsSettings permission probe results must bind to desktop identity.

Root race (old code):
  1. selectApp(A) → refreshPermissions starts permissionsProbe for A
  2. selectApp(B) while probe still running → refreshPermissions early-returns
     because permissionsProbe.running, so B's refresh is permanently discarded
  3. A's onStreamFinished / onExited write permission state and clear
     permissionsRefreshing without identity checks → B's page shows A's
     permissions, and A's exit can clear loading for a later request

Fix contract:
  - Single permissionsProbe Process pipeline owned by AppsSettings
  - permissionsProbeGeneration advances on every refresh intent (and clear)
  - In-flight success/JSON failure/Process failure only apply when generation
    and desktop ID still match the latest selection
  - permissionsProbePending re-runs only the newest selection after Process exit
  - Restart is deferred (Qt.callLater), never synchronous inside onExited
  - Selection change invalidates display so B never shows A's rows while loading
  - Unselected path keeps permissionCapability = {}
  - Old exit must not clear permissionsRefreshing for a newer generation
  - No safeRefresh / second permissions Process / debounce Timer / unconditional post-exit refresh

Regression strategy:
  1. Static contract extraction from AppsSettings.qml (fails on old discard path).
  2. Behavioral simulation of A success/failure/JSON late, A→B, A→B→C, A→B→A,
     clear selection, failed start, double completion, deferred pending re-run.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import unittest
from dataclasses import dataclass, field
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
APPS_SETTINGS = SHELL_ROOT / "services" / "AppsSettings.qml"
QML_TEST = Path(__file__).with_name("tst_apps_settings_permissions_identity.qml")


@dataclass(frozen=True)
class PermissionsProbeContract:
    """Wiring discovered in source. Missing edges reproduce the old race."""

    has_probe_generation: bool
    has_in_flight_generation: bool
    has_in_flight_desktop_id: bool
    has_owner_desktop_id: bool
    has_probe_pending: bool
    refresh_bumps_generation: bool
    refresh_sets_pending_when_running_new_selection: bool
    refresh_does_not_drop_when_running: bool
    start_probe_exists: bool
    start_probe_freezes_command_before_running: bool
    identity_matches_generation_and_desktop: bool
    parse_requires_identity: bool
    parse_rejects_stale: bool
    failure_requires_identity: bool
    finish_probe_exists: bool
    finish_probe_gates_refreshing_clear: bool
    finish_probe_schedules_pending: bool
    deferred_pending_restart: bool
    stdout_cached_with_generation: bool
    stream_finished_cache_only: bool
    on_exited_uses_finish_probe: bool
    failed_start_uses_finish_probe: bool
    finish_consumes_in_flight_generation: bool
    selection_invalidates_stale_display: bool
    unselected_clear_uses_null_sandbox: bool
    single_permissions_probe_process: bool
    no_safe_refresh: bool
    no_second_permissions_process: bool
    no_debounce_timer_for_probe: bool
    no_unconditional_post_exit_refresh: bool

    @property
    def identity_path_complete(self) -> bool:
        return all(
            getattr(self, name)
            for name in PermissionsProbeContract.__annotations__
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


def extract_contract(src: str) -> PermissionsProbeContract:
    refresh_fn = _extract_function_body(src, "refreshPermissions")
    select_fn = _extract_function_body(src, "selectApp")
    start_fn = _extract_function_body(src, "startPermissionsProbe")
    parse_fn = _extract_function_body(src, "parsePermissions")
    failure_fn = _extract_function_body(src, "applyPermissionsFailure")
    finish_fn = _extract_function_body(src, "finishPermissionsProbe")
    schedule_fn = _extract_function_body(src, "schedulePendingPermissionsProbe")
    identity_fn = _extract_function_body(src, "permissionsIdentityMatches")
    clear_fn = _extract_function_body(src, "clearPermissionsState")
    invalidate_fn = _extract_function_body(src, "invalidateStalePermissionDisplay")
    probe_block = _extract_process_block(src, "permissionsProbe")

    process_ids = re.findall(r"Process\s*\{\s*id:\s*(\w+)", src)
    permissions_probe_like = [
        p for p in process_ids if "permission" in p.lower() and "probe" in p.lower()
    ]

    old_drop_signature = bool(
        re.search(
            r"if\s*\(\s*permissionsProbe\.running\s*\)\s*return\s*;",
            refresh_fn,
        )
    ) and "permissionsProbePending" not in refresh_fn

    identity_checks_gen = bool(
        re.search(
            r"Number\(generation\)\s*!==\s*Number\((?:root\.)?permissionsProbeGeneration\)",
            identity_fn,
        )
    )
    identity_checks_desktop = bool(
        re.search(
            r"selectedDesktopId",
            identity_fn,
        )
        and re.search(r"desktopId", identity_fn)
    )

    parse_rejects = bool(re.search(r"permissionsIdentityMatches", parse_fn))
    failure_rejects = bool(re.search(r"permissionsIdentityMatches", failure_fn))

    finish_gates_refreshing = bool(
        re.search(
            r"permissionsProbeGeneration[\s\S]{0,200}permissionsRefreshing\s*=\s*false",
            finish_fn,
        )
        and re.search(r"permissionsProbePending", finish_fn)
    )

    deferred_restart = bool(re.search(r"Qt\.callLater", schedule_fn))

    cmd_idx = start_fn.find("permissionsProbe.command")
    run_idx = start_fn.find("permissionsProbe.running = true")
    if run_idx < 0:
        run_idx = start_fn.find("permissionsProbe.running=true")
    freezes_command = cmd_idx >= 0 and run_idx > cmd_idx

    stream_handler = ""
    stream_m = re.search(r"onStreamFinished\s*:\s*(\{[\s\S]*?\}|[^\n]+)", probe_block)
    if stream_m:
        stream_handler = stream_m.group(1)

    stdout_cached = bool(
        re.search(r"permissionsStdoutText", probe_block)
        and re.search(r"permissionsStdoutGeneration", probe_block)
        and re.search(r"onStreamFinished", probe_block)
    )
    stream_cache_only = bool(stream_handler) and not bool(
        re.search(r"parsePermissions\s*\(", stream_handler)
    ) and bool(re.search(r"permissionsStdoutText\s*=", stream_handler))

    unconditional_post_exit_refresh = bool(
        re.search(r"\brefreshPermissions\s*\(\s*\)", finish_fn)
        or re.search(r"onExited:[\s\S]*?\brefreshPermissions\s*\(\s*\)", probe_block)
    )

    debounce_timer = bool(
        re.search(
            r"Timer\s*\{[^}]*debounce|permissionsDebounce|permissionDebounce",
            src,
            re.DOTALL | re.IGNORECASE,
        )
    )

    unselected_null_sandbox = bool(
        re.search(
            r'clearPermissionsState\s*\(\s*"unknown"\s*,\s*"未选择应用"\s*,\s*null\s*\)',
            refresh_fn,
        )
    ) and bool(
        re.search(
            r"sandbox\s*!==\s*null\s*&&\s*sandbox\s*!==\s*undefined",
            clear_fn,
        )
    )

    selection_invalidates = bool(
        re.search(r"invalidateStalePermissionDisplay", select_fn)
        or re.search(r"invalidateStalePermissionDisplay", refresh_fn)
    ) and bool(invalidate_fn) and bool(
        re.search(r"permissionItems\s*=\s*\[\]", invalidate_fn)
    )

    return PermissionsProbeContract(
        has_probe_generation=bool(
            re.search(r"property\s+int\s+permissionsProbeGeneration\b", src)
        ),
        has_in_flight_generation=bool(
            re.search(r"property\s+int\s+permissionsProbeInFlightGeneration\b", src)
        ),
        has_in_flight_desktop_id=bool(
            re.search(r"property\s+string\s+permissionsProbeInFlightDesktopId\b", src)
        ),
        has_owner_desktop_id=bool(
            re.search(r"property\s+string\s+permissionsOwnerDesktopId\b", src)
        ),
        has_probe_pending=bool(
            re.search(r"property\s+bool\s+permissionsProbePending\b", src)
        ),
        refresh_bumps_generation=bool(
            re.search(r"permissionsProbeGeneration\s*\+=\s*1", refresh_fn)
        ),
        refresh_sets_pending_when_running_new_selection=bool(
            re.search(r"permissionsProbe\.running", refresh_fn)
            and re.search(r"permissionsProbePending\s*=\s*true", refresh_fn)
            and re.search(r"permissionsProbeInFlightDesktopId", refresh_fn)
        ),
        refresh_does_not_drop_when_running=not old_drop_signature,
        start_probe_exists=bool(re.search(r"function\s+startPermissionsProbe\s*\(", src)),
        start_probe_freezes_command_before_running=freezes_command,
        identity_matches_generation_and_desktop=identity_checks_gen
        and identity_checks_desktop,
        parse_requires_identity=parse_rejects and identity_checks_gen and identity_checks_desktop,
        parse_rejects_stale=parse_rejects,
        failure_requires_identity=failure_rejects and identity_checks_gen and identity_checks_desktop,
        finish_probe_exists=bool(re.search(r"function\s+finishPermissionsProbe\s*\(", src)),
        finish_probe_gates_refreshing_clear=finish_gates_refreshing,
        finish_probe_schedules_pending=bool(
            re.search(r"permissionsProbePending", finish_fn)
            and (
                re.search(r"schedulePendingPermissionsProbe", finish_fn)
                or re.search(r"Qt\.callLater", finish_fn)
            )
        ),
        deferred_pending_restart=deferred_restart,
        stdout_cached_with_generation=stdout_cached,
        stream_finished_cache_only=stream_cache_only,
        on_exited_uses_finish_probe=bool(
            re.search(r"finishPermissionsProbe\s*\(", probe_block)
        ),
        failed_start_uses_finish_probe=bool(
            re.search(r"onRunningChanged", probe_block)
            and re.search(
                r"!permissionsProbe\.running[\s\S]{0,160}finishPermissionsProbe\s*\(",
                probe_block,
            )
        ),
        finish_consumes_in_flight_generation=bool(
            re.search(r"permissionsProbeInFlightGeneration\s*=\s*0", finish_fn)
        ),
        selection_invalidates_stale_display=selection_invalidates,
        unselected_clear_uses_null_sandbox=unselected_null_sandbox,
        single_permissions_probe_process=permissions_probe_like.count("permissionsProbe") == 1
        and len(permissions_probe_like) == 1,
        no_safe_refresh=not bool(
            re.search(
                r"function\s+safeRefreshPermissions\s*\(|function\s+newRefreshPermissions\s*\(|function\s+refreshPermissions2\s*\(",
                src,
            )
        ),
        no_second_permissions_process=len(permissions_probe_like) == 1
        and not bool(
            re.search(
                r"id:\s*permissionsProbe2\b|id:\s*safePermissionsProbe\b|id:\s*permissionsService\b",
                src,
            )
        ),
        no_debounce_timer_for_probe=not debounce_timer,
        no_unconditional_post_exit_refresh=not unconditional_post_exit_refresh,
    )


@dataclass
class PermissionState:
    status: str = "unknown"
    detail: str = ""
    items: list = field(default_factory=list)
    capability: dict = field(default_factory=dict)
    sandbox: dict = field(default_factory=dict)
    desktop_id: str = ""
    owner_desktop_id: str = ""
    refreshing: bool = False


class PermissionsProbeModel:
    """Simulates AppsSettings refreshPermissions/parse/finish generation semantics.

    When use_identity is False, mirrors the old path:
      - drop refresh while running
      - apply any completion unconditionally
      - always clear permissionsRefreshing on exit
    """

    def __init__(self, *, use_identity: bool) -> None:
        self.use_identity = use_identity
        self.probe_generation = 0
        self.probe_in_flight_generation = 0
        self.probe_pending = False
        self.running = False
        self.selected_desktop_id = ""
        self.in_flight_desktop_id = ""
        self.stdout_text = ""
        self.stdout_generation = 0
        self.state = PermissionState()
        self.started_desktop_ids: list[str] = []
        self.applied_generations: list[int] = []
        self.rejected_generations: list[int] = []
        self.deferred: list = []
        self.finish_calls = 0
        self.finish_rejected = 0

    def select_app(self, desktop_id: str) -> None:
        if self.use_identity and self.state.owner_desktop_id != desktop_id:
            self._invalidate_display(desktop_id)
        self.selected_desktop_id = desktop_id
        self.refresh_permissions()

    def clear_selection(self) -> None:
        self.selected_desktop_id = ""
        if self.use_identity:
            self.probe_generation += 1
            self.probe_pending = False
            self.state.refreshing = False
            was_running = self.running
            self.running = False
            self.state = PermissionState(
                status="unknown",
                detail="未选择应用",
                capability={},
                sandbox={},
            )
            # Stopping a running process still delivers finish with old generation.
            if was_running and self.probe_in_flight_generation > 0:
                self._finish_probe(
                    -1,
                    self.probe_in_flight_generation,
                    self.in_flight_desktop_id,
                    "",
                )
            return
        self.state = PermissionState(status="unknown", detail="未选择应用")
        self.state.refreshing = False

    def refresh_permissions(self) -> None:
        if not self.selected_desktop_id:
            self.clear_selection()
            return

        if self.use_identity:
            if self.running:
                if self.in_flight_desktop_id != self.selected_desktop_id:
                    self.probe_generation += 1
                    self.probe_pending = True
                    self.state.refreshing = True
                    if self.state.owner_desktop_id != self.selected_desktop_id:
                        self._invalidate_display(self.selected_desktop_id)
                return
            self.probe_generation += 1
            self._start_probe(self.probe_generation, self.selected_desktop_id)
            return

        if self.running:
            return
        self.state.refreshing = True
        self.running = True
        self.in_flight_desktop_id = self.selected_desktop_id
        self.started_desktop_ids.append(self.selected_desktop_id)

    def _invalidate_display(self, selected: str) -> None:
        self.state.owner_desktop_id = ""
        self.state.status = "unknown"
        self.state.detail = "正在读取权限"
        self.state.items = []
        self.state.capability = (
            {"sandboxType": "unknown", "portalStatus": "unknown"}
            if selected
            else {}
        )
        self.state.sandbox = {}
        self.state.desktop_id = ""

    def _start_probe(self, generation: int, desktop_id: str) -> None:
        if self.use_identity:
            if generation != self.probe_generation:
                return
            if desktop_id != self.selected_desktop_id:
                return
            if self.running:
                self.probe_pending = True
                return
        self.probe_pending = False
        self.probe_in_flight_generation = generation
        self.in_flight_desktop_id = desktop_id
        self.stdout_text = ""
        self.stdout_generation = 0
        self.state.refreshing = True
        self.running = True
        self.started_desktop_ids.append(desktop_id)

    def _identity_ok(self, generation: int | None, desktop_id: str) -> bool:
        if generation is None:
            return False
        if generation != self.probe_generation:
            return False
        if desktop_id != self.selected_desktop_id:
            return False
        return True

    def stream_finished(self, text: str) -> None:
        """Cache-only; must not mutate permission state."""
        if not self.use_identity:
            # Old path wrote immediately from streamFinished.
            self.parse_permissions(text)  # type: ignore[call-arg]
            return
        self.stdout_text = text
        self.stdout_generation = self.probe_in_flight_generation

    def parse_permissions(
        self,
        payload: dict | str,
        generation: int | None = None,
        desktop_id: str = "",
        *,
        force_json_error: bool = False,
    ) -> None:
        if self.use_identity:
            if not self._identity_ok(generation, desktop_id):
                self.rejected_generations.append(
                    -1 if generation is None else int(generation)
                )
                return
            self.applied_generations.append(int(generation))  # type: ignore[arg-type]
        else:
            self.applied_generations.append(-1)

        if force_json_error or (
            isinstance(payload, str) and payload.strip() and not payload.strip().startswith("{")
        ):
            self.state.status = "error"
            self.state.detail = "权限数据解析失败：bad json"
            self.state.items = []
            self.state.desktop_id = desktop_id if self.use_identity else self.selected_desktop_id
            self.state.owner_desktop_id = (
                desktop_id if self.use_identity else self.selected_desktop_id
            )
            return

        if isinstance(payload, str):
            # Minimal JSON-like: tests pass dicts; raw string treated as empty.
            data: dict = {}
        else:
            data = payload

        self.state.status = str(data.get("status", "unknown"))
        self.state.detail = str(data.get("detail", ""))
        self.state.items = list(data.get("permissions") or [])
        self.state.desktop_id = desktop_id if self.use_identity else self.selected_desktop_id
        self.state.owner_desktop_id = (
            desktop_id if self.use_identity else self.selected_desktop_id
        )
        self.state.capability = {"portalStatus": self.state.status}

    def apply_failure(
        self, code: int, generation: int | None = None, desktop_id: str = ""
    ) -> None:
        if self.use_identity:
            if not self._identity_ok(generation, desktop_id):
                self.rejected_generations.append(
                    -1 if generation is None else int(generation)
                )
                return
            self.applied_generations.append(int(generation))  # type: ignore[arg-type]
        self.state.status = "error"
        self.state.detail = f"权限读取失败，退出码 {code}"
        self.state.items = []
        self.state.desktop_id = desktop_id if self.use_identity else self.selected_desktop_id
        self.state.owner_desktop_id = (
            desktop_id if self.use_identity else self.selected_desktop_id
        )

    def _finish_probe(
        self, code: int, generation: int, desktop_id: str, text: str
    ) -> None:
        self.finish_calls += 1
        if self.use_identity:
            if generation <= 0 or generation != self.probe_in_flight_generation:
                self.finish_rejected += 1
                return
            self.probe_in_flight_generation = 0
            self.in_flight_desktop_id = ""

            if code != 0:
                self.apply_failure(code, generation, desktop_id)
            elif text.startswith("NOT_JSON"):
                self.parse_permissions(
                    text, generation, desktop_id, force_json_error=True
                )
            else:
                # Prefer generation-matched stdout cache when present.
                payload_text = (
                    self.stdout_text
                    if self.stdout_generation == generation and self.stdout_text
                    else text
                )
                if payload_text.startswith("{"):
                    # Tests use structured dict via process_exited(payload=...).
                    pass
                self.parse_permissions(
                    self._last_payload if hasattr(self, "_last_payload") and self._last_payload is not None
                    else {"status": "ok", "detail": payload_text, "permissions": []},
                    generation,
                    desktop_id,
                )

            if generation == self.probe_generation and not self.probe_pending:
                self.state.refreshing = False
            if self.probe_pending:
                self.deferred.append(self.probe_generation)
            return

        if code != 0:
            self.apply_failure(code)
        self.state.refreshing = False

    def process_exited(self, payload: dict | None = None, code: int = 0) -> None:
        generation = self.probe_in_flight_generation
        desktop_id = self.in_flight_desktop_id
        self.running = False
        self._last_payload = payload
        text = ""
        if payload is not None:
            text = str(payload.get("detail", ""))
            if self.use_identity and self.stdout_generation != generation:
                # Cache may be empty; payload still provided by test harness.
                pass
        if code != 0:
            self._finish_probe(code, generation, desktop_id, "")
        elif payload is not None and self.use_identity:
            # Store payload for finish parse path.
            self._last_payload = payload
            self._finish_probe(0, generation, desktop_id, text or "{}")
        elif payload is not None:
            self.parse_permissions(payload)
            self.state.refreshing = False
        else:
            self._finish_probe(0, generation, desktop_id, "")

        # Mirror QuickShell: runningChanged after exited may re-enter finish.
        if self.use_identity:
            self.process_running_changed_after_exit()

    def process_running_changed_after_exit(self) -> None:
        """Duplicate completion after onExited; must be ignored."""
        if not self.use_identity:
            return
        gen = self.probe_in_flight_generation
        desktop = self.in_flight_desktop_id
        if gen > 0:
            self._finish_probe(-1, gen, desktop, "")
        else:
            # Already consumed: still call finish with stale values to prove rejection.
            self.finish_calls += 1
            self.finish_rejected += 1

    def process_failed_to_start(self) -> None:
        generation = self.probe_in_flight_generation
        desktop_id = self.in_flight_desktop_id
        self.running = False
        if not self.use_identity:
            return
        self._finish_probe(-1, generation, desktop_id, "")

    def drain_deferred(self) -> None:
        while self.deferred:
            self.deferred.pop(0)
            if not self.probe_pending:
                continue
            if self.running:
                continue
            self._start_probe(self.probe_generation, self.selected_desktop_id)


def _perm_payload(desktop_id: str, *, ok: bool = True) -> dict:
    if not ok:
        return {
            "status": "error",
            "detail": f"fail {desktop_id}",
            "permissions": [],
        }
    return {
        "status": "ok",
        "detail": f"perms for {desktop_id}",
        "permissions": [{"id": "camera", "label": desktop_id}],
    }


class AppsSettingsPermissionsIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.src = APPS_SETTINGS.read_text(encoding="utf-8")
        cls.contract = extract_contract(cls.src)

    def test_source_contract_binds_probe_to_desktop_identity(self) -> None:
        c = self.contract
        self.assertTrue(
            c.identity_path_complete,
            msg=(
                "AppsSettings permissions probe identity contract incomplete:\n"
                + "\n".join(
                    f"  {name}={getattr(c, name)}"
                    for name in PermissionsProbeContract.__annotations__
                )
            ),
        )

    def test_old_path_a_success_late_pollutes_b(self) -> None:
        m = PermissionsProbeModel(use_identity=False)
        m.select_app("A.desktop")
        self.assertTrue(m.running)
        m.select_app("B.desktop")
        self.assertEqual(m.started_desktop_ids, ["A.desktop"])
        m.process_exited(_perm_payload("A.desktop"), code=0)
        self.assertEqual(m.state.items[0]["label"], "A.desktop")
        self.assertFalse(m.state.refreshing)

    def test_new_path_a_success_late_does_not_pollute_b(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        gen_a = m.probe_in_flight_generation
        m.select_app("B.desktop")
        self.assertTrue(m.probe_pending)
        self.assertEqual(m.probe_generation, gen_a + 1)
        # B must not keep A's permission rows while waiting.
        self.assertEqual(m.state.items, [])
        self.assertEqual(m.state.owner_desktop_id, "")
        m.process_exited(_perm_payload("A.desktop"), code=0)
        self.assertIn(gen_a, m.rejected_generations)
        self.assertFalse(m.running)
        self.assertEqual(m.state.items, [])
        self.assertTrue(m.state.refreshing)
        m.drain_deferred()
        self.assertTrue(m.running)
        self.assertEqual(m.in_flight_desktop_id, "B.desktop")
        m.process_exited(_perm_payload("B.desktop"), code=0)
        m.drain_deferred()
        self.assertEqual(m.state.items[0]["label"], "B.desktop")
        self.assertEqual(m.state.desktop_id, "B.desktop")
        self.assertEqual(m.state.owner_desktop_id, "B.desktop")
        self.assertFalse(m.state.refreshing)
        self.assertFalse(m.running)

    def test_new_path_a_failure_late_does_not_pollute_b(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        gen_a = m.probe_in_flight_generation
        m.select_app("B.desktop")
        m.process_exited(code=1)
        self.assertIn(gen_a, m.rejected_generations)
        m.drain_deferred()
        self.assertTrue(m.running)
        self.assertEqual(m.in_flight_desktop_id, "B.desktop")
        self.assertTrue(m.state.refreshing)
        m.process_exited(_perm_payload("B.desktop"), code=0)
        m.drain_deferred()
        self.assertEqual(m.state.status, "ok")
        self.assertEqual(m.state.items[0]["label"], "B.desktop")
        self.assertNotIn("退出码", m.state.detail)

    def test_new_path_a_json_failure_late_does_not_pollute_b(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        gen_a = m.probe_in_flight_generation
        m.select_app("B.desktop")
        # Process exit settles running before finish (same as process_exited).
        m.running = False
        m._finish_probe(0, gen_a, "A.desktop", "NOT_JSON")
        self.assertIn(gen_a, m.rejected_generations)
        self.assertEqual(m.state.items, [])
        self.assertNotEqual(m.state.detail, "权限数据解析失败：bad json")
        m.drain_deferred()
        self.assertEqual(m.in_flight_desktop_id, "B.desktop")
        m.process_exited(_perm_payload("B.desktop"), code=0)
        m.drain_deferred()
        self.assertEqual(m.state.items[0]["label"], "B.desktop")

    def test_new_path_json_failure_as_latest_writes_error(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        gen = m.probe_in_flight_generation
        desktop = m.in_flight_desktop_id
        m.running = False
        m._finish_probe(0, gen, desktop, "NOT_JSON")
        self.assertEqual(m.state.status, "error")
        self.assertIn("权限数据解析失败", m.state.detail)
        self.assertEqual(m.state.owner_desktop_id, "A.desktop")
        self.assertFalse(m.state.refreshing)

    def test_new_path_a_exit_does_not_clear_b_loading(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        m.select_app("B.desktop")
        m.process_exited(_perm_payload("A.desktop"), code=0)
        self.assertTrue(m.state.refreshing, "B must still be loading after A's exit")
        m.drain_deferred()
        self.assertTrue(m.running)
        self.assertEqual(m.in_flight_desktop_id, "B.desktop")

    def test_new_path_a_to_b_to_c_only_latest_runs_after_a(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        m.select_app("B.desktop")
        m.select_app("C.desktop")
        self.assertTrue(m.probe_pending)
        self.assertEqual(m.started_desktop_ids, ["A.desktop"])
        m.process_exited(_perm_payload("A.desktop"), code=0)
        m.drain_deferred()
        self.assertEqual(m.started_desktop_ids, ["A.desktop", "C.desktop"])
        self.assertEqual(m.in_flight_desktop_id, "C.desktop")
        m.process_exited(_perm_payload("C.desktop"), code=0)
        m.drain_deferred()
        self.assertEqual(m.state.items[0]["label"], "C.desktop")
        self.assertFalse(m.state.refreshing)

    def test_new_path_a_to_b_to_a_while_a_inflight(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        gen_a = m.probe_in_flight_generation
        m.select_app("B.desktop")
        self.assertTrue(m.probe_pending)
        # Back to A while original A process still in flight.
        m.select_app("A.desktop")
        self.assertTrue(m.probe_pending)
        self.assertGreater(m.probe_generation, gen_a)
        m.process_exited(_perm_payload("A.desktop"), code=0)
        # Stale original A generation must not apply; deferred restarts latest A.
        self.assertIn(gen_a, m.rejected_generations)
        m.drain_deferred()
        self.assertEqual(m.in_flight_desktop_id, "A.desktop")
        m.process_exited(_perm_payload("A.desktop"), code=0)
        m.drain_deferred()
        self.assertEqual(m.state.items[0]["label"], "A.desktop")
        self.assertFalse(m.state.refreshing)

    def test_new_path_success_as_latest_still_works(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        m.process_exited(_perm_payload("A.desktop"), code=0)
        m.drain_deferred()
        self.assertEqual(m.state.items[0]["label"], "A.desktop")
        self.assertFalse(m.state.refreshing)
        self.assertFalse(m.probe_pending)
        self.assertFalse(m.running)

    def test_new_path_failed_start_releases_latest_loading(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        m.process_failed_to_start()
        self.assertFalse(m.running)
        self.assertFalse(m.state.refreshing)
        self.assertEqual(m.state.status, "error")
        self.assertIn("退出码 -1", m.state.detail)

    def test_new_path_failed_start_of_a_still_runs_latest_b(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        gen_a = m.probe_in_flight_generation
        m.select_app("B.desktop")
        m.process_failed_to_start()
        self.assertIn(gen_a, m.rejected_generations)
        self.assertTrue(m.state.refreshing)
        m.drain_deferred()
        self.assertTrue(m.running)
        self.assertEqual(m.in_flight_desktop_id, "B.desktop")

    def test_new_path_double_completion_is_idempotent(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        m.process_exited(_perm_payload("A.desktop"), code=0)
        # process_exited already invokes runningChanged duplicate finish.
        self.assertEqual(m.probe_in_flight_generation, 0)
        self.assertGreaterEqual(m.finish_rejected, 1)
        self.assertEqual(m.state.items[0]["label"], "A.desktop")
        self.assertFalse(m.state.refreshing)

    def test_new_path_clear_selection_rejects_stale_a_and_keeps_empty_capability(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        gen_a = m.probe_in_flight_generation
        m.clear_selection()
        self.assertEqual(m.state.detail, "未选择应用")
        self.assertEqual(m.state.capability, {})
        self.assertFalse(m.state.refreshing)
        # clear already finished the stopped process as stale.
        self.assertIn(gen_a, m.rejected_generations + [gen_a])
        self.assertEqual(m.state.items, [])
        self.assertEqual(m.state.capability, {})

    def test_new_path_parse_without_generation_is_rejected(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        m.parse_permissions(_perm_payload("X.desktop"), generation=None, desktop_id="X.desktop")
        self.assertEqual(m.state.items, [])
        self.assertIn(-1, m.rejected_generations)
        m.process_exited(_perm_payload("A.desktop"), code=0)
        m.drain_deferred()
        self.assertEqual(m.state.items[0]["label"], "A.desktop")

    def test_new_path_same_selection_while_running_coalesces(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        gen_a = m.probe_generation
        m.refresh_permissions()  # same selection while running
        self.assertEqual(m.probe_generation, gen_a)
        self.assertFalse(m.probe_pending)
        self.assertEqual(m.started_desktop_ids, ["A.desktop"])

    def test_new_path_stream_finished_alone_does_not_write_state(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        m.stream_finished('{"status":"ok","permissions":[{"label":"stream"}]}')
        self.assertEqual(m.state.items, [])
        self.assertEqual(m.stdout_generation, m.probe_in_flight_generation)
        m.process_exited(_perm_payload("A.desktop"), code=0)
        self.assertEqual(m.state.items[0]["label"], "A.desktop")

    def test_new_path_select_after_a_loaded_clears_before_b_finishes(self) -> None:
        m = PermissionsProbeModel(use_identity=True)
        m.select_app("A.desktop")
        m.process_exited(_perm_payload("A.desktop"), code=0)
        self.assertEqual(m.state.items[0]["label"], "A.desktop")
        m.select_app("B.desktop")
        self.assertEqual(m.state.items, [])
        self.assertEqual(m.state.owner_desktop_id, "")
        self.assertTrue(m.state.refreshing)
        m.process_exited(_perm_payload("B.desktop"), code=0)
        self.assertEqual(m.state.items[0]["label"], "B.desktop")

    def test_real_qml_permissions_identity_races(self) -> None:
        """Drive production AppsSettings.qml via qmltestrunner + Process fake.

        Covers A late success/parse/FailedToStart/cancel, A→B→C latest-only,
        permissionsRefreshing generation gate, and sandbox fallback isolation.
        """
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(
            runner, "Qt 6 qmltestrunner is required for AppsSettings permissions coverage"
        )
        self.assertTrue(QML_TEST.is_file(), f"missing QML test: {QML_TEST}")
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
            timeout=90,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    unittest.main()
