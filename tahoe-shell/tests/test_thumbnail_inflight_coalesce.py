#!/usr/bin/env python3
"""Task 17: ThumbnailProvider must coalesce equivalent in-flight captures.

Root waste (old code):
  1. Consumer A requestThumbnail(W, 320, 220) starts capture → state.loading
  2. Consumer B requestThumbnail(W, 320, 220) while loading unconditionally
     sets state.refreshPending = true
  3. finishActiveJob always re-queues when refreshPending → second capture
  4. Two identical consumers produce 2 niri window-thumbnail processes

Fix contract:
  - Single per-window state/queue owner (no second capture queue)
  - While loading, same-or-smaller non-force requests do NOT set refreshPending
  - Larger desired size upgrades still schedule one follow-up capture
  - force is never swallowed (force while loading sets refreshPending)
  - Multiple consumers share final state via the existing cache key
  - Failure still allows retry; window cleanup still drops pending work

Regression strategy:
  1. Static contract extraction from ThumbnailProvider.qml
  2. Behavioral simulation counting capture starts under duplicate consumers
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass, field
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
PROVIDER = SHELL_ROOT / "services" / "ThumbnailProvider.qml"


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


@dataclass(frozen=True)
class ThumbnailCoalesceContract:
    has_loading_job_needs_upgrade: bool
    loading_branch_not_unconditional_refresh: bool
    loading_branch_gates_on_force_or_upgrade: bool
    upgrade_compares_desired_to_active_job: bool
    force_still_sets_refresh_pending: bool
    finish_still_honors_refresh_pending: bool
    single_thumbnail_process: bool
    no_second_capture_queue: bool
    no_safe_request_api: bool

    @property
    def complete(self) -> bool:
        return all(getattr(self, name) for name in self.__annotations__)


def extract_contract(src: str) -> ThumbnailCoalesceContract:
    request = _extract_function_body(src, "requestThumbnail")
    upgrade = _extract_function_body(src, "loadingJobNeedsUpgrade")
    finish = _extract_function_body(src, "finishActiveJob")
    loading_block = ""
    m = re.search(r"if\s*\(\s*state\.loading\s*\)\s*\{", request)
    if m:
        start = m.end()
        depth = 1
        i = start
        while i < len(request) and depth:
            if request[i] == "{":
                depth += 1
            elif request[i] == "}":
                depth -= 1
            i += 1
        loading_block = request[start : i - 1]

    unconditional = bool(
        re.search(
            r"if\s*\(\s*state\.loading\s*\)\s*\{\s*"
            r"state\.refreshPending\s*=\s*true\s*;",
            request,
            re.DOTALL,
        )
    )

    return ThumbnailCoalesceContract(
        has_loading_job_needs_upgrade="loadingJobNeedsUpgrade" in src
        and len(upgrade) > 0,
        loading_branch_not_unconditional_refresh=not unconditional,
        loading_branch_gates_on_force_or_upgrade=bool(
            re.search(
                r"force\s*\|\|\s*loadingJobNeedsUpgrade\s*\(",
                loading_block,
            )
            or re.search(
                r"if\s*\(\s*force\s*\|\|\s*loadingJobNeedsUpgrade",
                loading_block,
            )
        ),
        upgrade_compares_desired_to_active_job=bool(
            re.search(r"desiredWidth|desiredW", upgrade)
            and re.search(r"job\.maxWidth", upgrade)
            and re.search(r"desiredHeight|desiredH", upgrade)
            and re.search(r"job\.maxHeight", upgrade)
        ),
        force_still_sets_refresh_pending=bool(
            re.search(r"force", loading_block)
            and re.search(r"refreshPending\s*=\s*true", loading_block)
        ),
        finish_still_honors_refresh_pending=bool(
            re.search(r"refreshPending", finish)
            and re.search(r"queueKey", finish)
        ),
        single_thumbnail_process=len(re.findall(r"\bProcess\s*\{", src)) == 1,
        no_second_capture_queue="secondCapture" not in src
        and "safeRequestThumbnail" not in src
        and "captureQueue2" not in src,
        no_safe_request_api=not re.search(
            r"function\s+safeRequestThumbnail\b", src
        ),
    )


@dataclass
class ThumbState:
    key: str
    ready: bool = False
    failed: bool = False
    queued: bool = False
    loading: bool = False
    generation: int = 0
    max_width: int = 0
    max_height: int = 0
    desired_width: int = 0
    desired_height: int = 0
    updated_at: int = 0
    status: str = "idle"
    refresh_pending: bool = False
    error: str = ""


@dataclass
class ActiveJob:
    key: str
    max_width: int
    max_height: int
    cancelled: bool = False


class ThumbnailProviderSim:
    """Mirrors the fixed coalesce semantics for deterministic capture counts."""

    def __init__(self, max_cache_age_ms: int = 30000) -> None:
        self.cache: dict[str, ThumbState] = {}
        self.queue: list[str] = []
        self.queued_keys: set[str] = set()
        self.active_job: ActiveJob | None = None
        self.capture_starts: int = 0
        self.success_count: int = 0
        self.failure_count: int = 0
        self.max_cache_age_ms = max_cache_age_ms
        self.now_ms: int = 1_000_000

    def state_for(self, key: str, create: bool = True) -> ThumbState | None:
        key = str(key or "")
        if not key:
            return None
        state = self.cache.get(key)
        if not state and create:
            state = ThumbState(key=key)
            self.cache[key] = state
        return state

    def clamp(self, value: int | float, fallback: int) -> int:
        try:
            number = int(round(float(value)))
        except (TypeError, ValueError):
            number = fallback
        if number <= 0:
            number = fallback
        return max(1, min(4096, number))

    def loading_job_needs_upgrade(self, key: str, state: ThumbState) -> bool:
        job = self.active_job
        if not job or str(job.key) != str(key):
            return True
        return (
            state.desired_width > job.max_width
            or state.desired_height > job.max_height
        )

    def queue_key(self, key: str) -> bool:
        state = self.state_for(key, True)
        assert state is not None
        if key in self.queued_keys:
            state.queued = True
            return True
        self.queued_keys.add(key)
        self.queue.append(key)
        state.queued = True
        state.status = "queued"
        return True

    def request(
        self,
        key: str,
        max_width: int = 320,
        max_height: int = 220,
        force: bool = False,
    ) -> bool:
        state = self.state_for(key, True)
        assert state is not None
        width = self.clamp(max_width, 320)
        height = self.clamp(max_height, 220)
        state.desired_width = max(state.desired_width or 0, width)
        state.desired_height = max(state.desired_height or 0, height)

        age = (
            self.now_ms - state.updated_at
            if state.updated_at > 0
            else 999999999999
        )
        has_enough = state.max_width >= width and state.max_height >= height
        cache_fresh = (
            state.ready
            and not state.failed
            and has_enough
            and age < self.max_cache_age_ms
        )
        if not force and cache_fresh:
            return True

        if state.loading:
            if force or self.loading_job_needs_upgrade(key, state):
                state.refresh_pending = True
            return True

        state.failed = False
        state.error = ""
        state.status = "queued"
        return self.queue_key(key)

    def pump(self) -> bool:
        if self.active_job is not None:
            return False
        while self.queue:
            key = self.queue.pop(0)
            self.queued_keys.discard(key)
            state = self.state_for(key, False)
            if not state:
                continue
            state.queued = False
            state.loading = True
            state.failed = False
            state.error = ""
            state.status = "loading"
            width = self.clamp(state.desired_width, 320)
            height = self.clamp(state.desired_height, 220)
            self.active_job = ActiveJob(
                key=key, max_width=width, max_height=height
            )
            self.capture_starts += 1
            return True
        return False

    def finish(self, code: int = 0) -> None:
        job = self.active_job
        if not job:
            return
        state = self.state_for(job.key, False)
        if job.cancelled:
            self.active_job = None
            return
        if state:
            state.loading = False
            state.queued = False
            if code == 0:
                state.ready = True
                state.failed = False
                state.generation += 1
                state.max_width = job.max_width
                state.max_height = job.max_height
                state.updated_at = self.now_ms
                state.error = ""
                state.status = "ready"
                self.success_count += 1
            else:
                state.ready = False
                state.failed = True
                state.error = f"exit {code}"
                state.status = "failed"
                self.failure_count += 1
            if state.refresh_pending:
                state.refresh_pending = False
                self.queue_key(job.key)
        self.active_job = None

    def request_and_pump(
        self,
        key: str,
        max_width: int = 320,
        max_height: int = 220,
        force: bool = False,
    ) -> bool:
        ok = self.request(key, max_width, max_height, force)
        self.pump()
        return ok


class OldThumbnailProviderSim(ThumbnailProviderSim):
    """Old unconditional refreshPending while loading — wastes a capture."""

    def request(
        self,
        key: str,
        max_width: int = 320,
        max_height: int = 220,
        force: bool = False,
    ) -> bool:
        state = self.state_for(key, True)
        assert state is not None
        width = self.clamp(max_width, 320)
        height = self.clamp(max_height, 220)
        state.desired_width = max(state.desired_width or 0, width)
        state.desired_height = max(state.desired_height or 0, height)

        age = (
            self.now_ms - state.updated_at
            if state.updated_at > 0
            else 999999999999
        )
        has_enough = state.max_width >= width and state.max_height >= height
        cache_fresh = (
            state.ready
            and not state.failed
            and has_enough
            and age < self.max_cache_age_ms
        )
        if not force and cache_fresh:
            return True

        if state.loading:
            # Old root waste: always re-capture after current job.
            state.refresh_pending = True
            return True

        state.failed = False
        state.error = ""
        state.status = "queued"
        return self.queue_key(key)


class ThumbnailInflightCoalesceTests(unittest.TestCase):
    def test_source_contract_is_complete(self) -> None:
        src = PROVIDER.read_text(encoding="utf-8")
        contract = extract_contract(src)
        missing = [
            name
            for name in ThumbnailCoalesceContract.__annotations__
            if not getattr(contract, name)
        ]
        self.assertEqual(
            missing,
            [],
            f"Thumbnail coalesce contract incomplete: {missing}",
        )

    def test_equivalent_duplicate_consumers_capture_once(self) -> None:
        fixed = ThumbnailProviderSim()
        fixed.request_and_pump("42", 320, 220)
        self.assertEqual(fixed.capture_starts, 1)
        # Second consumer, same size, non-force, while first still loading.
        fixed.request("42", 320, 220, force=False)
        self.assertFalse(fixed.cache["42"].refresh_pending)
        fixed.finish(0)
        fixed.pump()
        self.assertEqual(
            fixed.capture_starts,
            1,
            "equivalent in-flight request must not start a second capture",
        )
        self.assertTrue(fixed.cache["42"].ready)

        old = OldThumbnailProviderSim()
        old.request_and_pump("42", 320, 220)
        old.request("42", 320, 220, force=False)
        self.assertTrue(old.cache["42"].refresh_pending)
        old.finish(0)
        old.pump()
        self.assertEqual(
            old.capture_starts,
            2,
            "old path must demonstrate the double-capture waste",
        )

    def test_smaller_request_while_loading_does_not_upgrade(self) -> None:
        sim = ThumbnailProviderSim()
        sim.request_and_pump("7", 400, 300)
        sim.request("7", 200, 150, force=False)
        self.assertFalse(sim.cache["7"].refresh_pending)
        sim.finish(0)
        sim.pump()
        self.assertEqual(sim.capture_starts, 1)
        self.assertGreaterEqual(sim.cache["7"].max_width, 200)
        self.assertGreaterEqual(sim.cache["7"].max_height, 150)

    def test_larger_size_while_loading_schedules_one_upgrade(self) -> None:
        sim = ThumbnailProviderSim()
        sim.request_and_pump("9", 200, 150)
        self.assertEqual(sim.capture_starts, 1)
        sim.request("9", 640, 480, force=False)
        self.assertTrue(sim.cache["9"].refresh_pending)
        sim.finish(0)
        # First job produced 200x150; upgrade must re-queue once.
        self.assertTrue(sim.pump())
        self.assertEqual(sim.capture_starts, 2)
        sim.finish(0)
        sim.pump()
        self.assertEqual(sim.capture_starts, 2)
        self.assertEqual(sim.cache["9"].max_width, 640)
        self.assertEqual(sim.cache["9"].max_height, 480)

    def test_force_while_loading_is_not_swallowed(self) -> None:
        sim = ThumbnailProviderSim()
        sim.request_and_pump("3", 320, 220)
        sim.request("3", 320, 220, force=True)
        self.assertTrue(sim.cache["3"].refresh_pending)
        sim.finish(0)
        self.assertTrue(sim.pump())
        self.assertEqual(sim.capture_starts, 2)
        sim.finish(0)
        self.assertEqual(sim.cache["3"].generation, 2)

    def test_multiple_consumers_share_final_ready_state(self) -> None:
        sim = ThumbnailProviderSim()
        sim.request_and_pump("11", 320, 220)
        # Three consumers pile on while loading.
        for _ in range(3):
            sim.request("11", 320, 220, force=False)
        self.assertFalse(sim.cache["11"].refresh_pending)
        sim.finish(0)
        sim.pump()
        self.assertEqual(sim.capture_starts, 1)
        state = sim.cache["11"]
        self.assertTrue(state.ready)
        self.assertEqual(state.status, "ready")
        # All consumers would read the same state object by key.
        self.assertIs(sim.state_for("11"), state)

    def test_failure_allows_retry(self) -> None:
        sim = ThumbnailProviderSim()
        sim.request_and_pump("5", 320, 220)
        sim.finish(1)
        self.assertTrue(sim.cache["5"].failed)
        sim.request_and_pump("5", 320, 220)
        self.assertEqual(sim.capture_starts, 2)
        sim.finish(0)
        self.assertTrue(sim.cache["5"].ready)

    def test_cache_fresh_skips_capture_without_force(self) -> None:
        sim = ThumbnailProviderSim()
        sim.request_and_pump("1", 320, 220)
        sim.finish(0)
        self.assertEqual(sim.capture_starts, 1)
        sim.request("1", 320, 220, force=False)
        sim.pump()
        self.assertEqual(sim.capture_starts, 1)
        sim.request_and_pump("1", 320, 220, force=True)
        self.assertEqual(sim.capture_starts, 2)

    def test_old_path_double_capture_count_is_two(self) -> None:
        """Performance evidence: old 2 captures → fixed 1 for same consumers."""
        old = OldThumbnailProviderSim()
        fixed = ThumbnailProviderSim()
        for sim in (old, fixed):
            sim.request_and_pump("99", 320, 220)
            sim.request("99", 320, 220)
            sim.request("99", 200, 150)
            sim.finish(0)
            sim.pump()
            if sim.active_job:
                sim.finish(0)
                sim.pump()
        self.assertEqual(old.capture_starts, 2)
        self.assertEqual(fixed.capture_starts, 1)


if __name__ == "__main__":
    unittest.main()
