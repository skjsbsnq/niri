#!/usr/bin/env python3
"""Task 08: Weather geocode search must isolate request generations.

Root race (old code):
  1. searchLocations(A) starts geocodeProcess for A
  2. searchLocations(B) while running: geocodeProcess.running = false then
     immediately rebinds command and restarts for B
  3. A's late onExited / finishGeocodeRequest writes unconditionally:
     locationSearching=false, clears or overwrites locationSearchResults,
     emits locationSearchFailed/Finished — wiping B's loading or results

Fix contract:
  - Single geocodeProcess Process pipeline owned by Weather
  - geocodeGeneration advances on every search intent (and clear / empty query)
  - In-flight success / failure / parse error only apply when generation matches
  - generation is mandatory on finishGeocodeRequest (undefined/null never writes
    when in-flight identity already consumed)
  - geocodePending holds only the newest query while an older curl exits
  - Restart is deferred (Qt.callLater), never a second Process or debounce Timer
  - Old exit must not clear locationSearching for a newer generation
  - No safeSearch / second geocode Process / query-text-only identity

Regression strategy:
  1. Static contract extraction from Weather.qml (fails on old unconditional finish).
  2. Behavioral simulation of A success/failure/cancel late, A→B, A→B→C,
     clear during flight, empty query, deferred pending re-run.
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass, field
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
WEATHER = SHELL_ROOT / "services" / "Weather.qml"


@dataclass(frozen=True)
class GeocodeIdentityContract:
    """Wiring discovered in source. Missing edges reproduce the old race."""

    has_geocode_generation: bool
    has_in_flight_generation: bool
    has_in_flight_query: bool
    has_geocode_pending: bool
    has_pending_query: bool
    search_bumps_generation: bool
    search_sets_pending_when_running: bool
    search_does_not_restart_inline_when_running: bool
    start_geocode_exists: bool
    start_geocode_freezes_query_before_running: bool
    start_geocode_rejects_stale_generation: bool
    identity_matches_generation: bool
    finish_requires_generation_gate: bool
    finish_rejects_stale: bool
    finish_gates_searching_clear: bool
    finish_schedules_pending: bool
    deferred_pending_restart: bool
    on_exited_freezes_generation: bool
    on_exited_uses_finish_geocode: bool
    clear_bumps_generation: bool
    empty_query_bumps_generation: bool
    failed_start_uses_finish: bool
    single_geocode_process: bool
    no_safe_search: bool
    no_second_geocode_process: bool
    no_debounce_timer_for_geocode: bool
    no_query_text_only_identity: bool

    @property
    def identity_path_complete(self) -> bool:
        return all(
            getattr(self, name)
            for name in GeocodeIdentityContract.__annotations__
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
    m = re.search(rf"Process\s*\{{\s*id:\s*{re.escape(process_id)}", src)
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


def extract_contract(src: str) -> GeocodeIdentityContract:
    search_fn = _extract_function_body(src, "searchLocations")
    start_fn = _extract_function_body(src, "startGeocode")
    finish_fn = _extract_function_body(src, "finishGeocodeRequest")
    clear_fn = _extract_function_body(src, "clearLocationSearch")
    match_fn = _extract_function_body(src, "geocodeIdentityMatches")
    schedule_fn = _extract_function_body(src, "schedulePendingGeocode")
    process = _extract_process_block(src, "geocodeProcess")

    has_geocode_generation = bool(
        re.search(r"property\s+int\s+geocodeGeneration\b", src)
    )
    has_in_flight_generation = bool(
        re.search(r"property\s+int\s+geocodeInFlightGeneration\b", src)
    )
    has_in_flight_query = bool(
        re.search(r"property\s+string\s+geocodeInFlightQuery\b", src)
    )
    has_geocode_pending = bool(
        re.search(r"property\s+bool\s+geocodePending\b", src)
    )
    has_pending_query = bool(
        re.search(r"property\s+string\s+geocodePendingQuery\b", src)
    )

    search_bumps_generation = bool(
        re.search(r"geocodeGeneration\s*\+=\s*1", search_fn)
    )
    search_sets_pending_when_running = bool(
        re.search(r"geocodePending\s*=\s*true", search_fn)
        and re.search(r"geocodeProcess\.running", search_fn)
    )
    # Old bug: stop then immediately rebind command + running=true in same function
    # while handling the already-running branch (no pending / no startGeocode).
    inline_restart_while_running = bool(
        re.search(
            r"if\s*\(\s*geocodeProcess\.running\s*\)\s*\{[^}]*geocodeProcess\.running\s*=\s*false[^}]*\}"
            r"[\s\S]*geocodeProcess\.command\s*=",
            search_fn,
        )
        and not re.search(r"geocodePending\s*=\s*true", search_fn)
    )
    search_does_not_restart_inline_when_running = not inline_restart_while_running

    start_geocode_exists = bool(start_fn.strip())
    start_geocode_freezes_query_before_running = bool(
        re.search(r"geocodeInFlightQuery\s*=", start_fn)
        and re.search(r"geocodeProcess\.command\s*=", start_fn)
        and re.search(r"geocodeProcess\.running\s*=\s*true", start_fn)
    )
    start_geocode_rejects_stale_generation = bool(
        re.search(r"geocodeIdentityMatches\s*\(\s*generation\s*\)", start_fn)
        or (
            re.search(r"geocodeGeneration", start_fn)
            and re.search(r"return", start_fn)
        )
    )

    identity_matches_generation = bool(
        match_fn.strip()
        and re.search(r"geocodeGeneration", match_fn)
        and re.search(r"undefined|null", match_fn)
    )

    finish_requires_generation_gate = bool(
        re.search(r"geocodeIdentityMatches\s*\(", finish_fn)
        or (
            re.search(r"geocodeGeneration", finish_fn)
            and re.search(r"return", finish_fn)
        )
    )
    finish_rejects_stale = finish_requires_generation_gate and bool(
        re.search(r"return", finish_fn)
    )
    # searching=false must sit after identity gate, not as unconditional first line.
    finish_body_before_gate = finish_fn
    gate_m = re.search(r"geocodeIdentityMatches\s*\(", finish_fn)
    if gate_m:
        # Approximate: first locationSearching=false after a return for mismatch.
        finish_gates_searching_clear = bool(
            re.search(
                r"geocodeIdentityMatches[\s\S]*?return[\s\S]*?locationSearching\s*=\s*false",
                finish_fn,
            )
            or (
                # Gate then clear searching (stale path returns before clear)
                re.search(r"if\s*\(\s*!root\.geocodeIdentityMatches", finish_fn)
                and re.search(r"locationSearching\s*=\s*false", finish_fn)
                and finish_fn.find("locationSearching = false")
                > finish_fn.find("geocodeIdentityMatches")
            )
        )
    else:
        finish_gates_searching_clear = False

    finish_schedules_pending = bool(
        re.search(r"schedulePendingGeocode\s*\(", finish_fn)
    )
    deferred_pending_restart = bool(
        re.search(r"Qt\.callLater\s*\(", schedule_fn)
        and re.search(r"startGeocode\s*\(", schedule_fn)
    )

    on_exited = ""
    em = re.search(r"onExited\s*:\s*function\s*\([^)]*\)\s*\{", process)
    if em:
        depth = 1
        i = em.end()
        while i < len(process) and depth:
            if process[i] == "{":
                depth += 1
            elif process[i] == "}":
                depth -= 1
            i += 1
        on_exited = process[em.end() : i - 1]

    on_exited_freezes_generation = bool(
        re.search(r"geocodeInFlightGeneration", on_exited)
        and re.search(r"finishGeocodeRequest\s*\(", on_exited)
    )
    on_exited_uses_finish_geocode = bool(
        re.search(r"finishGeocodeRequest\s*\(", on_exited)
    )

    clear_bumps_generation = bool(
        re.search(r"geocodeGeneration\s*\+=\s*1", clear_fn)
    )
    # Empty-query branch is inside searchLocations before the bump for real names.
    empty_query_bumps_generation = bool(
        re.search(
            r"name\.length\s*===\s*0[\s\S]*?geocodeGeneration\s*\+=\s*1",
            search_fn,
        )
    )

    failed_start_uses_finish = bool(
        re.search(
            r"geocodeProcess\.running\s*=\s*true[\s\S]*?"
            r"if\s*\(\s*!geocodeProcess\.running\s*\)[\s\S]*?"
            r"finishGeocodeRequest\s*\(",
            start_fn,
        )
    )

    process_ids = re.findall(r"Process\s*\{\s*id:\s*(\w+)", src)
    geocode_process_count = sum(1 for p in process_ids if "geocode" in p.lower())
    single_geocode_process = geocode_process_count == 1

    no_safe_search = not bool(
        re.search(r"function\s+safeSearchLocations\s*\(", src)
    )
    no_second_geocode_process = geocode_process_count <= 1
    no_debounce_timer_for_geocode = not bool(
        re.search(
            r"Timer\s*\{[^}]*id:\s*\w*[Gg]eocode\w*[^}]*interval",
            src,
            re.DOTALL,
        )
    )
    # Identity must use generation, not only locationSearchQuery === inFlightQuery.
    no_query_text_only_identity = not bool(
        re.search(
            r"function\s+geocodeIdentityMatches[\s\S]*?"
            r"locationSearchQuery\s*===\s*geocodeInFlightQuery"
            r"(?![\s\S]*geocodeGeneration)",
            src,
        )
    ) and bool(re.search(r"geocodeGeneration", match_fn))

    return GeocodeIdentityContract(
        has_geocode_generation=has_geocode_generation,
        has_in_flight_generation=has_in_flight_generation,
        has_in_flight_query=has_in_flight_query,
        has_geocode_pending=has_geocode_pending,
        has_pending_query=has_pending_query,
        search_bumps_generation=search_bumps_generation,
        search_sets_pending_when_running=search_sets_pending_when_running,
        search_does_not_restart_inline_when_running=search_does_not_restart_inline_when_running,
        start_geocode_exists=start_geocode_exists,
        start_geocode_freezes_query_before_running=start_geocode_freezes_query_before_running,
        start_geocode_rejects_stale_generation=start_geocode_rejects_stale_generation,
        identity_matches_generation=identity_matches_generation,
        finish_requires_generation_gate=finish_requires_generation_gate,
        finish_rejects_stale=finish_rejects_stale,
        finish_gates_searching_clear=finish_gates_searching_clear,
        finish_schedules_pending=finish_schedules_pending,
        deferred_pending_restart=deferred_pending_restart,
        on_exited_freezes_generation=on_exited_freezes_generation,
        on_exited_uses_finish_geocode=on_exited_uses_finish_geocode,
        clear_bumps_generation=clear_bumps_generation,
        empty_query_bumps_generation=empty_query_bumps_generation,
        failed_start_uses_finish=failed_start_uses_finish,
        single_geocode_process=single_geocode_process,
        no_safe_search=no_safe_search,
        no_second_geocode_process=no_second_geocode_process,
        no_debounce_timer_for_geocode=no_debounce_timer_for_geocode,
        no_query_text_only_identity=no_query_text_only_identity,
    )


# ---------------------------------------------------------------------------
# Behavioral simulation
# ---------------------------------------------------------------------------


@dataclass
class GeocodeState:
    results: list = field(default_factory=list)
    query: str = ""
    searching: bool = False
    error: str = ""
    finished_signals: int = 0
    failed_signals: int = 0


class GeocodeRequestModel:
    """Simulates Weather searchLocations / finishGeocodeRequest generation semantics.

    Process timing matches Quickshell: search/clear only set running=false
    (terminate). Completion arrives later via on_exited(), which freezes
    geocodeInFlightGeneration the same way Weather.qml onExited does.

    When use_identity is False, mirrors the old path:
      - stop + immediately restart on new search while running
      - apply any completion unconditionally
      - always clear locationSearching on exit
    """

    def __init__(self, *, use_identity: bool) -> None:
        self.use_identity = use_identity
        self.generation = 0
        self.in_flight_generation = 0
        self.in_flight_query = ""
        self.pending = False
        self.pending_query = ""
        self.running = False
        self.state = GeocodeState()
        self.started_queries: list[str] = []
        self.applied_generations: list[int] = []
        self.rejected_generations: list[int] = []
        self.deferred: list = []
        self.finish_calls = 0
        self.finish_rejected = 0

    def search(self, query: str) -> None:
        name = str(query or "").strip()
        if not name:
            if self.use_identity:
                self.generation += 1
                self.pending = False
                self.pending_query = ""
                # Stop only; late on_exited still carries frozen in-flight gen.
                self.running = False
                self.state = GeocodeState(error="请输入城市名", failed_signals=1)
                return
            self.state = GeocodeState(error="请输入城市名", failed_signals=1)
            return

        if self.use_identity:
            self.generation += 1
            self.state.searching = True
            self.state.query = name
            self.state.error = ""
            if self.running:
                # Align with QML: pending + terminate, do NOT finish inline.
                self.pending = True
                self.pending_query = name
                self.running = False
                return
            self._start(self.generation, name)
            return

        # Old path: stop then immediately rebind for the new query.
        if self.running:
            self.running = False
        self.state.searching = True
        self.state.query = name
        self.state.error = ""
        self.running = True
        self.in_flight_query = name
        # Old path never tracked generation; late exits still write unconditionally.
        self.in_flight_generation = 0
        self.started_queries.append(name)

    def clear(self) -> None:
        if self.use_identity:
            self.generation += 1
            self.pending = False
            self.pending_query = ""
            self.running = False
            self.state = GeocodeState()
            return
        self.state = GeocodeState()
        self.running = False

    def _identity_ok(self, generation: int | None) -> bool:
        if generation is None:
            return False
        return generation == self.generation

    def _start(self, generation: int, query: str) -> None:
        if self.use_identity:
            if generation != self.generation:
                return
            if not query:
                return
            if self.running:
                self.pending = True
                self.pending_query = query
                return
        self.pending = False
        self.pending_query = ""
        self.in_flight_generation = generation
        self.in_flight_query = query
        self.state.searching = True
        self.state.query = query
        self.state.error = ""
        self.running = True
        self.started_queries.append(query)

    def _schedule_pending(self) -> None:
        if not self.use_identity:
            return

        def resume() -> None:
            if not self.pending:
                return
            if self.running:
                return
            query = self.pending_query
            self.pending = False
            self.pending_query = ""
            self._start(self.generation, query)

        self.deferred.append(resume)

    def flush_deferred(self) -> None:
        while self.deferred:
            jobs = list(self.deferred)
            self.deferred.clear()
            for job in jobs:
                job()

    def on_exited(self, code: int, text="", generation: int | None = None) -> None:
        """Process onExited: freeze in-flight generation then finish (QML order)."""
        if generation is None:
            generation = self.in_flight_generation
        # Capture stdout before any pending restart can repurpose the buffer.
        frozen_text = text
        frozen_gen = generation
        self.running = False
        self._finish(code, frozen_text, frozen_gen)

    def complete_success(self, results: list, generation: int | None = None) -> None:
        gen = self.in_flight_generation if generation is None else generation
        self.on_exited(0, {"results": results}, gen)

    def complete_failure(self, generation: int | None = None) -> None:
        gen = self.in_flight_generation if generation is None else generation
        self.on_exited(1, "", gen)

    def complete_parse_error(self, generation: int | None = None) -> None:
        gen = self.in_flight_generation if generation is None else generation
        self.on_exited(0, "not-json", gen)

    def complete_cancel(self, generation: int | None = None) -> None:
        """Terminate-style non-zero exit (Quickshell terminate → code != 0)."""
        gen = self.in_flight_generation if generation is None else generation
        self.on_exited(15, "", gen)

    def _finish(self, code: int, text, generation: int | None) -> None:
        self.finish_calls += 1
        # Match QML: undefined/null generation never writes (no in-flight fallback).
        if self.use_identity and generation is None:
            self.finish_rejected += 1
            self.rejected_generations.append(-1)
            self._schedule_pending()
            return

        gen = generation
        if self.use_identity:
            # Must still own the in-flight slot (double exit / foreign finish).
            if gen != self.in_flight_generation:
                self.finish_rejected += 1
                self.rejected_generations.append(-1 if gen is None else int(gen))
                self._schedule_pending()
                return
            self.in_flight_generation = 0
            self.in_flight_query = ""
            if not self._identity_ok(gen):
                self.finish_rejected += 1
                self.rejected_generations.append(int(gen))  # type: ignore[arg-type]
                self._schedule_pending()
                return
            self.applied_generations.append(int(gen))  # type: ignore[arg-type]
        else:
            self.applied_generations.append(-1)

        self.state.searching = False

        if code != 0:
            self.state.results = []
            self.state.error = "城市搜索失败"
            self.state.failed_signals += 1
            if self.use_identity:
                self._schedule_pending()
            return

        if text == "not-json" or (
            isinstance(text, str)
            and text
            and not str(text).strip().startswith("{")
            and not isinstance(text, dict)
        ):
            if not isinstance(text, dict):
                self.state.results = []
                self.state.error = "城市搜索解析失败"
                self.state.failed_signals += 1
                if self.use_identity:
                    self._schedule_pending()
                return

        if isinstance(text, dict):
            results = list(text.get("results") or [])
        else:
            results = []

        self.state.results = results
        if not results:
            self.state.error = "未找到匹配城市"
            self.state.failed_signals += 1
        else:
            self.state.error = ""
            self.state.finished_signals += 1

        if self.use_identity:
            self._schedule_pending()


class WeatherGeocodeRequestIdentityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.src = WEATHER.read_text(encoding="utf-8")
        self.contract = extract_contract(self.src)

    def test_static_contract_complete(self) -> None:
        incomplete = [
            name
            for name in GeocodeIdentityContract.__annotations__
            if not getattr(self.contract, name)
        ]
        self.assertEqual(
            incomplete,
            [],
            "Weather geocode identity contract incomplete:\n"
            + "\n".join(f"  - {n}" for n in incomplete),
        )
        self.assertTrue(self.contract.identity_path_complete)

    def test_old_unconditional_finish_absent(self) -> None:
        finish = _extract_function_body(self.src, "finishGeocodeRequest")
        # Old bug: first statement cleared searching with no generation gate.
        stripped = finish.lstrip()
        self.assertFalse(
            stripped.startswith("root.locationSearching = false")
            or stripped.startswith("locationSearching = false"),
            "finishGeocodeRequest must not clear searching before identity gate",
        )
        self.assertRegex(finish, r"geocodeIdentityMatches")

    def test_single_geocode_process_only(self) -> None:
        self.assertEqual(
            len(re.findall(r"Process\s*\{\s*id:\s*geocodeProcess", self.src)),
            1,
        )
        for forbidden in (
            "safeSearchLocations",
            "geocodeProcess2",
            "geocodeDebounce",
        ):
            self.assertNotIn(forbidden, self.src)

    def test_old_source_contract_fails_identity_path(self) -> None:
        """Frozen pre-fix snippets must not satisfy the identity contract."""
        old_src = """
        property var locationSearchResults: []
        property string locationSearchQuery: ""
        property bool locationSearching: false
        property string locationSearchError: ""

        function clearLocationSearch() {
            root.locationSearchResults = [];
            root.locationSearchQuery = "";
            root.locationSearchError = "";
            root.locationSearching = false;
        }

        function searchLocations(query) {
            var name = cleanText(query, "");
            if (name.length === 0) {
                root.locationSearchResults = [];
                root.locationSearchQuery = "";
                root.locationSearchError = "请输入城市名";
                root.locationSearching = false;
                root.locationSearchFailed(root.locationSearchError);
                return;
            }
            if (geocodeProcess.running) {
                geocodeProcess.running = false;
            }
            root.locationSearching = true;
            root.locationSearchQuery = name;
            root.locationSearchError = "";
            geocodeProcess.command = curlCommand(geocodeUrl(name));
            geocodeProcess.running = true;
        }

        function finishGeocodeRequest(code, text) {
            root.locationSearching = false;
            if (code !== 0) {
                root.locationSearchResults = [];
                root.locationSearchError = "城市搜索失败";
                root.locationSearchFailed(root.locationSearchError);
                return;
            }
            root.locationSearchResults = [];
            root.locationSearchFinished();
        }

        Process {
            id: geocodeProcess
            running: false
            onExited: function(code, exitStatus) {
                root.finishGeocodeRequest(code, geocodeOut.text);
            }
        }
        """
        old_contract = extract_contract(old_src)
        self.assertFalse(old_contract.identity_path_complete)
        self.assertFalse(old_contract.has_geocode_generation)
        self.assertFalse(old_contract.finish_requires_generation_gate)
        self.assertFalse(old_contract.search_sets_pending_when_running)

    def test_a_success_late_does_not_overwrite_b(self) -> None:
        new = GeocodeRequestModel(use_identity=True)
        old = GeocodeRequestModel(use_identity=False)

        new.search("A")
        a_gen = new.in_flight_generation
        self.assertEqual(a_gen, 1)
        new.search("B")
        # Stop only: B not started until A's async on_exited + deferred pending.
        self.assertTrue(new.pending)
        self.assertEqual(new.pending_query, "B")
        self.assertNotIn("B", new.started_queries)
        self.assertEqual(new.state.query, "B")
        self.assertTrue(new.state.searching)

        # Async terminate exit for A (nonzero), then callLater starts B.
        new.complete_cancel(generation=a_gen)
        new.flush_deferred()
        self.assertIn("B", new.started_queries)
        b_gen = new.in_flight_generation
        self.assertEqual(new.state.query, "B")
        self.assertTrue(new.state.searching)
        self.assertNotEqual(new.state.error, "城市搜索失败")
        self.assertEqual(new.state.results, [])

        # Extra late A success must still be rejected.
        new.complete_success([{"name": "CityA"}], generation=a_gen)
        new.flush_deferred()
        self.assertEqual(new.state.results, [])
        self.assertEqual(new.state.query, "B")
        self.assertTrue(new.state.searching)

        new.complete_success([{"name": "CityB"}], generation=b_gen)
        new.flush_deferred()
        self.assertEqual(new.state.results, [{"name": "CityB"}])
        self.assertFalse(new.state.searching)
        self.assertEqual(new.state.finished_signals, 1)

        # Old path: last finish wins regardless of which request it was.
        old.search("A")
        old.search("B")
        old.complete_success([{"name": "CityA"}])
        self.assertEqual(old.state.results, [{"name": "CityA"}])
        self.assertFalse(old.state.searching)

    def test_a_failure_late_does_not_clear_b_loading_or_results(self) -> None:
        new = GeocodeRequestModel(use_identity=True)
        new.search("A")
        a_gen = new.in_flight_generation
        new.search("B")
        # A async failure (stale) schedules pending B.
        new.complete_failure(generation=a_gen)
        new.flush_deferred()
        b_gen = new.in_flight_generation
        self.assertEqual(new.state.query, "B")
        self.assertTrue(new.state.searching)
        self.assertNotEqual(new.state.error, "城市搜索失败")
        self.assertEqual(new.state.results, [])

        new.complete_success([{"name": "CityB"}], generation=b_gen)
        new.flush_deferred()
        self.assertEqual(new.state.results, [{"name": "CityB"}])
        self.assertEqual(new.state.error, "")

        old = GeocodeRequestModel(use_identity=False)
        old.search("A")
        old.search("B")
        old.complete_failure()
        self.assertEqual(old.state.error, "城市搜索失败")
        self.assertFalse(old.state.searching)
        self.assertEqual(old.state.results, [])

    def test_a_cancel_late_does_not_end_b_loading(self) -> None:
        new = GeocodeRequestModel(use_identity=True)
        old = GeocodeRequestModel(use_identity=False)

        new.search("A")
        a_gen = new.in_flight_generation
        new.search("B")
        # Terminate-style nonzero exit for A — must not show failure UI for B.
        new.complete_cancel(generation=a_gen)
        new.flush_deferred()
        self.assertEqual(new.state.query, "B")
        self.assertTrue(new.state.searching)
        self.assertIn("B", new.started_queries)
        self.assertNotEqual(new.state.error, "城市搜索失败")
        self.assertEqual(new.state.results, [])

        # Old path: cancel/nonzero exit clears searching and sets failure.
        old.search("A")
        old.search("B")
        old.complete_cancel()
        self.assertEqual(old.state.error, "城市搜索失败")
        self.assertFalse(old.state.searching)

    def test_stop_exit_nonzero_stale_does_not_fail_ui(self) -> None:
        """A→B: A's terminate exit code=15 must not paint failure over B."""
        new = GeocodeRequestModel(use_identity=True)
        new.search("A")
        a_gen = new.in_flight_generation
        new.search("B")
        new.on_exited(15, "", a_gen)
        new.flush_deferred()
        self.assertEqual(new.state.query, "B")
        self.assertTrue(new.state.searching)
        self.assertEqual(new.state.error, "")
        self.assertEqual(new.state.results, [])
        self.assertIn(a_gen, new.rejected_generations)

    def test_clear_then_nonzero_exit_no_error(self) -> None:
        new = GeocodeRequestModel(use_identity=True)
        new.search("A")
        a_gen = new.in_flight_generation
        new.clear()
        new.on_exited(15, "", a_gen)
        new.flush_deferred()
        self.assertEqual(new.state.results, [])
        self.assertFalse(new.state.searching)
        self.assertEqual(new.state.error, "")
        self.assertEqual(new.state.failed_signals, 0)

    def test_a_to_b_to_c_final_is_latest(self) -> None:
        new = GeocodeRequestModel(use_identity=True)
        old = GeocodeRequestModel(use_identity=False)

        new.search("A")
        a_gen = new.in_flight_generation
        new.search("B")
        new.complete_cancel(generation=a_gen)
        new.flush_deferred()
        b_gen = new.in_flight_generation
        self.assertEqual(new.state.query, "B")
        self.assertTrue(new.state.searching)

        new.search("C")
        new.complete_cancel(generation=b_gen)
        new.flush_deferred()
        c_gen = new.in_flight_generation
        self.assertEqual(new.state.query, "C")
        self.assertTrue(new.state.searching)
        self.assertEqual(new.state.results, [])

        # Stale A/B successes must not land.
        new.complete_success([{"name": "A"}], generation=a_gen)
        new.complete_success([{"name": "B"}], generation=b_gen)
        new.flush_deferred()
        self.assertEqual(new.state.results, [])
        self.assertEqual(new.state.query, "C")
        self.assertTrue(new.state.searching)

        new.complete_success([{"name": "C"}], generation=c_gen)
        new.flush_deferred()
        self.assertEqual(new.state.results, [{"name": "C"}])
        self.assertFalse(new.state.searching)
        self.assertEqual(new.started_queries[-1], "C")

        # Old path: last unconditional finish wins with wrong payload.
        old.search("A")
        old.search("B")
        old.search("C")
        old.complete_success([{"name": "A"}])
        self.assertEqual(old.state.results, [{"name": "A"}])

    def test_clear_invalidates_in_flight(self) -> None:
        new = GeocodeRequestModel(use_identity=True)
        old = GeocodeRequestModel(use_identity=False)

        new.search("A")
        a_gen = new.in_flight_generation
        new.clear()
        new.complete_success([{"name": "A"}], generation=a_gen)
        new.flush_deferred()
        self.assertEqual(new.state.results, [])
        self.assertFalse(new.state.searching)
        self.assertEqual(new.state.error, "")

        old.search("A")
        old.clear()
        old.complete_success([{"name": "A"}])
        # Old clear does not invalidate; late success still writes.
        self.assertEqual(old.state.results, [{"name": "A"}])

    def test_empty_query_invalidates_and_does_not_leave_searching(self) -> None:
        new = GeocodeRequestModel(use_identity=True)
        new.search("A")
        a_gen = new.in_flight_generation
        new.search("")
        self.assertFalse(new.state.searching)
        self.assertEqual(new.state.error, "请输入城市名")
        # Nonzero terminate after empty-query invalidate must not overwrite error.
        new.on_exited(15, "", a_gen)
        new.flush_deferred()
        self.assertEqual(new.state.error, "请输入城市名")
        self.assertEqual(new.state.results, [])
        new.complete_success([{"name": "A"}], generation=a_gen)
        new.flush_deferred()
        self.assertEqual(new.state.results, [])
        self.assertEqual(new.state.error, "请输入城市名")

    def test_pending_runs_latest_after_exit(self) -> None:
        new = GeocodeRequestModel(use_identity=True)
        new.search("A")
        a_gen = new.in_flight_generation
        new.search("B")
        self.assertTrue(new.pending)
        self.assertEqual(new.pending_query, "B")
        self.assertNotIn("B", new.started_queries)
        new.complete_cancel(generation=a_gen)
        new.flush_deferred()
        self.assertIn("B", new.started_queries)
        self.assertEqual(new.state.query, "B")
        self.assertTrue(new.state.searching)

    def test_identical_query_still_bumps_generation(self) -> None:
        """Must not use query-text-only identity (two 'Beijing' searches)."""
        new = GeocodeRequestModel(use_identity=True)
        new.search("Beijing")
        first = new.generation
        first_inflight = new.in_flight_generation
        new.search("Beijing")
        self.assertGreater(new.generation, first)
        self.assertTrue(new.pending)
        new.complete_cancel(generation=first_inflight)
        new.flush_deferred()
        # First generation success must not apply after second intent.
        new.complete_success([{"name": "old"}], generation=first_inflight)
        new.flush_deferred()
        self.assertNotEqual(new.state.results, [{"name": "old"}])
        self.assertEqual(new.state.query, "Beijing")
        self.assertTrue(new.state.searching)

    def test_parse_error_stale_rejected(self) -> None:
        new = GeocodeRequestModel(use_identity=True)
        new.search("A")
        a_gen = new.in_flight_generation
        new.search("B")
        new.complete_parse_error(generation=a_gen)
        new.flush_deferred()
        self.assertNotEqual(new.state.error, "城市搜索解析失败")
        self.assertEqual(new.state.query, "B")
        self.assertTrue(new.state.searching)

    def test_finish_null_generation_rejected(self) -> None:
        new = GeocodeRequestModel(use_identity=True)
        new.search("A")
        new._finish(0, {"results": [{"name": "X"}]}, None)
        new.flush_deferred()
        self.assertEqual(new.state.results, [])
        self.assertTrue(new.state.searching)
        self.assertEqual(new.finish_rejected, 1)

    def test_double_finish_same_generation_second_rejected(self) -> None:
        new = GeocodeRequestModel(use_identity=True)
        new.search("A")
        a_gen = new.in_flight_generation
        new.complete_success([{"name": "CityA"}], generation=a_gen)
        new.flush_deferred()
        self.assertEqual(new.state.results, [{"name": "CityA"}])
        self.assertEqual(new.state.finished_signals, 1)
        # Second exit after in-flight consume must not rewrite results/signals.
        new.on_exited(0, {"results": [{"name": "Dup"}]}, a_gen)
        new.flush_deferred()
        self.assertEqual(new.state.results, [{"name": "CityA"}])
        self.assertEqual(new.state.finished_signals, 1)
        self.assertFalse(new.state.searching)
        self.assertEqual(new.finish_rejected, 1)


if __name__ == "__main__":
    unittest.main()
