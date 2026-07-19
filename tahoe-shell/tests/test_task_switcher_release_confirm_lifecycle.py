#!/usr/bin/env python3
"""Task 10: TaskSwitcher release Timer must not confirm across sessions.

Root race (old code):
  1. Keyboard session A: modifier released → releaseConfirmTimer.restart() (40ms)
  2. Within 40ms session A closes (Escape / mouse cancel / external close)
  3. Session B reopens (open=true, keyboardMode may become true again)
  4. Stale Timer fires → if (open && keyboardMode) confirm() → activates B's
     selection without a real modifier release in session B

Fix contract:
  - Single releaseConfirmTimer (no second confirm Timer)
  - Session boundary (onOpenChanged) stops the Timer for BOTH open and close edges
    (stop before if (open), or explicit stop in each branch)
  - confirm() and cancel() stop the Timer before closing
  - onTriggered still gates on open && keyboardMode (defense in depth)
  - No session-epoch second state machine unless lifecycle stop is insufficient

Regression strategy:
  1. Static contract extraction from TaskSwitcher.qml (fails on old close path).
  2. Behavioral simulation driven by extract_contract flags, including
     extract_contract(OLD_SNIPPET) → sim race (static+behavior linked).
  3. Negative contracts: open-only stop / close-only stop must not pass.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from dataclasses import dataclass, field
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
TASK_SWITCHER = SHELL_ROOT / "components" / "TaskSwitcher.qml"
QML_TEST = Path(__file__).with_name("tst_task_switcher_release_confirm_lifecycle.qml")


@dataclass(frozen=True)
class ReleaseConfirmLifecycleContract:
    """Wiring discovered in source. Missing edges reproduce the old race."""

    has_release_confirm_timer: bool
    single_release_confirm_timer: bool
    timer_interval_40ms: bool
    timer_on_triggered_gates_open_and_keyboard: bool
    timer_on_triggered_calls_confirm: bool
    # True only when BOTH open-edge and close-edge stop are proven.
    on_open_changed_stops_timer: bool
    on_open_changed_stops_on_open: bool
    on_open_changed_stops_on_close: bool
    confirm_stops_timer: bool
    cancel_stops_timer: bool
    keys_on_released_restarts_timer: bool
    keys_on_released_requires_keyboard_mode: bool
    no_second_confirm_timer: bool
    no_parallel_confirm_state: bool
    no_safe_confirm_api: bool

    @property
    def lifecycle_path_complete(self) -> bool:
        return all(
            getattr(self, name)
            for name in ReleaseConfirmLifecycleContract.__annotations__
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


def _extract_handler_body(src: str, name: str) -> str:
    """Extract onXxxChanged / Keys.onXxx handler body (brace-balanced)."""
    m = re.search(rf"{re.escape(name)}\s*:\s*(?:function\s*\([^)]*\)\s*)?\{{", src)
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


def _extract_timer_block(src: str, timer_id: str) -> str:
    m = re.search(rf"Timer\s*\{{\s*id:\s*{re.escape(timer_id)}", src)
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


def _brace_block_after(src: str, open_brace_index: int) -> str:
    """Return interior of `{...}` starting at open_brace_index."""
    if open_brace_index < 0 or open_brace_index >= len(src) or src[open_brace_index] != "{":
        return ""
    depth = 0
    i = open_brace_index
    while i < len(src):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[open_brace_index + 1 : i]
        i += 1
    return ""


def _split_open_close_branches(on_open: str) -> tuple[str, str]:
    """Brace-parse `if (open) { ... } else { ... }` inside onOpenChanged."""
    m_if = re.search(r"if\s*\(\s*open\s*\)\s*\{", on_open)
    if not m_if:
        return "", ""
    open_brace = on_open.find("{", m_if.start())
    open_branch = _brace_block_after(on_open, open_brace)
    if not open_branch and open_branch != "":
        return "", ""
    # Find matching close of the if-block, then optional else.
    depth = 0
    i = open_brace
    if_end = -1
    while i < len(on_open):
        if on_open[i] == "{":
            depth += 1
        elif on_open[i] == "}":
            depth -= 1
            if depth == 0:
                if_end = i
                break
        i += 1
    if if_end < 0:
        return open_branch, ""
    rest = on_open[if_end + 1 :]
    m_else = re.match(r"\s*else\s*\{", rest)
    if not m_else:
        return open_branch, ""
    else_brace = rest.find("{")
    close_branch = _brace_block_after(rest, else_brace)
    return open_branch, close_branch


def _strip_qml_comments(text: str) -> str:
    """Remove // line and /* */ block comments for structural checks."""
    without_block = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    without_line = re.sub(r"//[^\n]*", "", without_block)
    return without_line


def _stop_before_if_open(on_open: str) -> bool:
    """True when releaseConfirmTimer.stop() runs before if (open) at handler entry.

    Allows whitespace and comments between stop and if; rejects stop that only
    appears inside a branch after if (open).
    """
    cleaned = _strip_qml_comments(on_open)
    m = re.search(
        r"releaseConfirmTimer\.stop\s*\(\s*\)\s*;[\s\S]*?if\s*\(\s*open\s*\)",
        cleaned,
    )
    if not m:
        return False
    # The matched stop must be the first structural statement region before if.
    prefix = cleaned[: m.start()]
    # Reject if another if (open) appears before this stop (shouldn't for entry).
    if re.search(r"if\s*\(\s*open\s*\)", prefix):
        return False
    return True


def extract_contract(src: str) -> ReleaseConfirmLifecycleContract:
    on_open = _extract_handler_body(src, "onOpenChanged")
    confirm_body = _extract_function_body(src, "confirm")
    cancel_body = _extract_function_body(src, "cancel")
    keys_released = _extract_handler_body(src, "Keys.onReleased")
    timer_block = _extract_timer_block(src, "releaseConfirmTimer")
    timer_triggered = ""
    if timer_block:
        timer_triggered = _extract_handler_body(timer_block, "onTriggered")

    timer_ids = re.findall(r"Timer\s*\{\s*id:\s*(\w+)", src)
    release_confirm_count = len(re.findall(r"id:\s*releaseConfirmTimer", src))

    stop_before = _stop_before_if_open(on_open)
    open_branch, close_branch = _split_open_close_branches(on_open)
    stop_in_open_branch = "releaseConfirmTimer.stop()" in open_branch
    stop_in_close_branch = "releaseConfirmTimer.stop()" in close_branch

    # Open edge covered by entry-level stop OR explicit stop inside open branch.
    stops_on_open = stop_before or stop_in_open_branch
    # Close edge covered by entry-level stop OR explicit stop inside else branch.
    stops_on_close = stop_before or stop_in_close_branch
    stops_both_edges = stops_on_open and stops_on_close

    no_safe = not re.search(r"\bsafeConfirm\b|\bnewConfirm\b|\bconfirm2\b", src)
    no_parallel = "pendingConfirm" not in src and "confirmEpoch" not in src

    other_timers_confirm = False
    for tid in timer_ids:
        if tid == "releaseConfirmTimer":
            continue
        block = _extract_timer_block(src, tid)
        if "confirm()" in block or "root.confirm()" in block:
            other_timers_confirm = True

    return ReleaseConfirmLifecycleContract(
        has_release_confirm_timer="id: releaseConfirmTimer" in src,
        single_release_confirm_timer=release_confirm_count == 1,
        timer_interval_40ms=bool(
            re.search(r"id:\s*releaseConfirmTimer[\s\S]*?interval:\s*40", timer_block)
        ),
        timer_on_triggered_gates_open_and_keyboard=bool(
            re.search(
                r"root\.open\s*&&\s*root\.keyboardMode",
                timer_triggered,
            )
            or re.search(
                r"root\.keyboardMode\s*&&\s*root\.open",
                timer_triggered,
            )
        ),
        timer_on_triggered_calls_confirm="confirm()" in timer_triggered,
        on_open_changed_stops_timer=stops_both_edges,
        on_open_changed_stops_on_open=stops_on_open,
        on_open_changed_stops_on_close=stops_on_close,
        confirm_stops_timer="releaseConfirmTimer.stop()" in confirm_body,
        cancel_stops_timer="releaseConfirmTimer.stop()" in cancel_body,
        keys_on_released_restarts_timer="releaseConfirmTimer.restart()" in keys_released,
        keys_on_released_requires_keyboard_mode="keyboardMode" in keys_released,
        no_second_confirm_timer=not other_timers_confirm and release_confirm_count == 1,
        no_parallel_confirm_state=no_parallel,
        no_safe_confirm_api=no_safe,
    )


# ---------------------------------------------------------------------------
# Behavioral simulation: proves old path fails, fixed path passes.
# ---------------------------------------------------------------------------


@dataclass
class SimulatedTimer:
    """Minimal one-shot Timer model matching QML restart/stop/trigger."""

    interval: int = 40
    running: bool = False
    fire_at: int | None = None
    trigger_count: int = 0
    last_fire_ms: int | None = None

    def stop(self) -> None:
        self.running = False
        self.fire_at = None

    def restart(self, now_ms: int) -> None:
        self.running = True
        self.fire_at = now_ms + self.interval

    def tick(self, now_ms: int) -> bool:
        """Return True if the timer fired at this instant."""
        if not self.running or self.fire_at is None:
            return False
        if now_ms >= self.fire_at:
            self.running = False
            self.fire_at = None
            self.trigger_count += 1
            self.last_fire_ms = now_ms
            return True
        return False


@dataclass
class SimulatedSwitcher:
    """Mirrors TaskSwitcher open/keyboardMode/confirm lifecycle for race tests.

    set_open only runs session-boundary stop when the value actually changes,
    matching QML onOpenChanged semantics.
    """

    open: bool = False
    keyboardMode: bool = False
    selected_index: int = 0
    activated: list[int] = field(default_factory=list)
    confirm_count: int = 0
    close_count: int = 0
    timer: SimulatedTimer = field(default_factory=SimulatedTimer)
    # Edge-specific session boundary stops (from extract_contract).
    stop_on_open_edge: bool = False
    stop_on_close_edge: bool = False
    stop_on_confirm: bool = False
    stop_on_cancel: bool = False
    gate_open_and_keyboard: bool = True

    def set_open(self, value: bool) -> None:
        if value == self.open:
            # QML does not fire onOpenChanged for true→true / false→false.
            return
        if value and self.stop_on_open_edge:
            self.timer.stop()
        if (not value) and self.stop_on_close_edge:
            self.timer.stop()
        self.open = value
        if not value:
            self.keyboardMode = False

    def cycle_from_keyboard(self, direction: int = 1) -> None:
        self.keyboardMode = True
        if not self.open:
            self.set_open(True)
            self.selected_index = 1 if direction > 0 else 0
        else:
            self.selected_index += 1 if direction > 0 else -1

    def on_modifier_released(self, now_ms: int) -> None:
        # Product also requires !hasSwitcherModifier; sim models keyboardMode gate.
        if self.keyboardMode:
            self.timer.restart(now_ms)

    def confirm(self) -> None:
        if self.stop_on_confirm:
            self.timer.stop()
        if self.open:
            self.activated.append(self.selected_index)
            self.confirm_count += 1
        self.set_open(False)
        self.close_count += 1

    def cancel(self) -> None:
        if self.stop_on_cancel:
            self.timer.stop()
        self.set_open(False)
        self.close_count += 1

    def on_timer_triggered(self) -> None:
        if self.gate_open_and_keyboard:
            if self.open and self.keyboardMode:
                self.confirm()
        else:
            self.confirm()

    def advance(self, now_ms: int) -> None:
        if self.timer.tick(now_ms):
            self.on_timer_triggered()


def switcher_from_contract(contract: ReleaseConfirmLifecycleContract) -> SimulatedSwitcher:
    return SimulatedSwitcher(
        stop_on_open_edge=contract.on_open_changed_stops_on_open,
        stop_on_close_edge=contract.on_open_changed_stops_on_close,
        stop_on_confirm=contract.confirm_stops_timer,
        stop_on_cancel=contract.cancel_stops_timer,
        gate_open_and_keyboard=contract.timer_on_triggered_gates_open_and_keyboard,
    )


def old_switcher() -> SimulatedSwitcher:
    """Pre-fix model: Timer not stopped on session boundary / confirm / cancel."""
    return SimulatedSwitcher(
        stop_on_open_edge=False,
        stop_on_close_edge=False,
        stop_on_confirm=False,
        stop_on_cancel=False,
        gate_open_and_keyboard=True,
    )


# Shared old-source snippet used for static + behavioral linkage.
OLD_SNIPPET = """
    onOpenChanged: {
        if (open) {
            selectedIndex = focusedIndex();
        } else {
            keyboardMode = false;
        }
    }
    function confirm() {
        var window = currentWindow();
        closeRequested();
    }
    function cancel() {
        closeRequested();
    }
    Timer {
        id: releaseConfirmTimer
        interval: 40
        repeat: false
        onTriggered: {
            if (root.open && root.keyboardMode)
                root.confirm();
        }
    }
    Keys.onReleased: function(event) {
        if (root.keyboardMode && root.isSwitcherModifierRelease(event)) {
            releaseConfirmTimer.restart();
        }
    }
"""

PARTIAL_OPEN_ONLY_STOP = """
    onOpenChanged: {
        if (open) {
            releaseConfirmTimer.stop();
            selectedIndex = focusedIndex();
        } else {
            keyboardMode = false;
        }
    }
    function confirm() {
        releaseConfirmTimer.stop();
        closeRequested();
    }
    function cancel() {
        releaseConfirmTimer.stop();
        closeRequested();
    }
    Timer {
        id: releaseConfirmTimer
        interval: 40
        repeat: false
        onTriggered: {
            if (root.open && root.keyboardMode)
                root.confirm();
        }
    }
    Keys.onReleased: function(event) {
        if (root.keyboardMode) {
            releaseConfirmTimer.restart();
        }
    }
"""

PARTIAL_CLOSE_ONLY_STOP = """
    onOpenChanged: {
        if (open) {
            selectedIndex = focusedIndex();
        } else {
            releaseConfirmTimer.stop();
            keyboardMode = false;
        }
    }
    function confirm() {
        releaseConfirmTimer.stop();
        closeRequested();
    }
    function cancel() {
        releaseConfirmTimer.stop();
        closeRequested();
    }
    Timer {
        id: releaseConfirmTimer
        interval: 40
        repeat: false
        onTriggered: {
            if (root.open && root.keyboardMode)
                root.confirm();
        }
    }
    Keys.onReleased: function(event) {
        if (root.keyboardMode) {
            releaseConfirmTimer.restart();
        }
    }
"""


def _race_release_close_reopen(s: SimulatedSwitcher) -> int:
    """Run release→close→reopen within 40ms; return confirm_count after fire time."""
    s.cycle_from_keyboard(1)
    s.selected_index = 2
    s.on_modifier_released(now_ms=0)
    s.cancel()
    s.cycle_from_keyboard(1)
    s.selected_index = 0
    s.advance(now_ms=40)
    return s.confirm_count


class ContractExtractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.src = TASK_SWITCHER.read_text(encoding="utf-8")
        cls.contract = extract_contract(cls.src)

    def test_lifecycle_path_complete(self) -> None:
        c = self.contract
        missing = [
            name
            for name in ReleaseConfirmLifecycleContract.__annotations__
            if not getattr(c, name)
        ]
        self.assertEqual(
            missing,
            [],
            f"Release-confirm lifecycle incomplete: {missing}",
        )

    def test_session_boundary_stops_before_open_branch(self) -> None:
        on_open = _extract_handler_body(self.src, "onOpenChanged")
        self.assertTrue(
            _stop_before_if_open(on_open),
            "Timer must stop at session boundary before open/close branches",
        )
        stop_idx = on_open.find("releaseConfirmTimer.stop()")
        if_idx = on_open.find("if (open)")
        if if_idx < 0:
            if_idx = on_open.find("if(open)")
        self.assertGreaterEqual(stop_idx, 0)
        self.assertGreaterEqual(if_idx, 0)
        self.assertLess(stop_idx, if_idx)

    def test_branch_split_does_not_treat_whole_handler_as_both(self) -> None:
        on_open = _extract_handler_body(self.src, "onOpenChanged")
        open_branch, close_branch = _split_open_close_branches(on_open)
        self.assertIn("windowChoices", open_branch)
        self.assertIn("keyboardMode", close_branch)
        # Entry-level stop is outside both branches.
        self.assertNotIn("releaseConfirmTimer.stop()", open_branch)
        self.assertNotIn("releaseConfirmTimer.stop()", close_branch)

    def test_single_timer_no_parallel_api(self) -> None:
        c = self.contract
        self.assertTrue(c.single_release_confirm_timer)
        self.assertTrue(c.no_second_confirm_timer)
        self.assertTrue(c.no_parallel_confirm_state)
        self.assertTrue(c.no_safe_confirm_api)

    def test_keys_release_still_restarts_same_timer(self) -> None:
        keys = _extract_handler_body(self.src, "Keys.onReleased")
        self.assertIn("releaseConfirmTimer.restart()", keys)
        self.assertIn("keyboardMode", keys)
        self.assertIn("isSwitcherModifierRelease", keys)
        self.assertIn("hasSwitcherModifier", keys)


class NegativeContractTests(unittest.TestCase):
    """Partial fixes must not satisfy lifecycle_path_complete or race-free sim."""

    def test_old_snippet_fails_static_and_behavioral(self) -> None:
        c = extract_contract(OLD_SNIPPET)
        self.assertFalse(c.on_open_changed_stops_timer)
        self.assertFalse(c.on_open_changed_stops_on_open)
        self.assertFalse(c.on_open_changed_stops_on_close)
        self.assertFalse(c.confirm_stops_timer)
        self.assertFalse(c.cancel_stops_timer)
        self.assertFalse(c.lifecycle_path_complete)
        # Static → behavior linkage: extract drives sim that still races.
        s = switcher_from_contract(c)
        self.assertEqual(_race_release_close_reopen(s), 1)

    def test_open_only_stop_fails_close_edge_contract(self) -> None:
        """Stop only inside if (open) must not count as close-edge coverage.

        Note: reopen's false→true still hits the open-branch stop, so the classic
        race may still be mitigated — but lifecycle_path_complete must reject the
        partial fix so close-edge is not falsely reported as covered.
        """
        c = extract_contract(PARTIAL_OPEN_ONLY_STOP)
        self.assertTrue(c.on_open_changed_stops_on_open)
        self.assertFalse(c.on_open_changed_stops_on_close)
        self.assertFalse(c.on_open_changed_stops_timer)
        self.assertFalse(c.lifecycle_path_complete)
        # External close with cancel/confirm stops disabled: close edge lacks stop.
        s = switcher_from_contract(c)
        s.stop_on_cancel = False
        s.stop_on_confirm = False
        s.cycle_from_keyboard(1)
        s.on_modifier_released(now_ms=0)
        s.set_open(False)  # true→false only; open-only branch does not run
        self.assertTrue(
            s.timer.running,
            "open-only stop must leave timer armed across close edge",
        )

    def test_close_only_stop_covers_close_but_not_lifecycle_complete_without_open(self) -> None:
        c = extract_contract(PARTIAL_CLOSE_ONLY_STOP)
        self.assertFalse(c.on_open_changed_stops_on_open)
        self.assertTrue(c.on_open_changed_stops_on_close)
        self.assertFalse(c.on_open_changed_stops_timer)
        self.assertFalse(c.lifecycle_path_complete)
        # Close edge alone is enough for the primary race when cancel/confirm also stop.
        s = switcher_from_contract(c)
        self.assertEqual(_race_release_close_reopen(s), 0)


class BehavioralSimulationTests(unittest.TestCase):
    """Deterministic race order: release → close → reopen within 40ms."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.src = TASK_SWITCHER.read_text(encoding="utf-8")
        cls.contract = extract_contract(cls.src)

    def test_old_path_confirms_new_session(self) -> None:
        s = old_switcher()
        s.cycle_from_keyboard(1)
        self.assertTrue(s.open and s.keyboardMode)
        s.selected_index = 2
        s.on_modifier_released(now_ms=0)
        self.assertTrue(s.timer.running)
        s.cancel()
        self.assertFalse(s.open)
        self.assertFalse(s.keyboardMode)
        self.assertTrue(s.timer.running)
        s.cycle_from_keyboard(1)
        s.selected_index = 0
        s.advance(now_ms=40)
        self.assertEqual(s.confirm_count, 1)
        self.assertEqual(s.activated, [0])
        self.assertFalse(s.open)

    def test_fixed_path_release_close_reopen_no_stale_confirm(self) -> None:
        s = switcher_from_contract(self.contract)
        self.assertTrue(
            self.contract.lifecycle_path_complete,
            "cannot simulate fix without complete contract",
        )
        s.cycle_from_keyboard(1)
        s.selected_index = 2
        s.on_modifier_released(now_ms=0)
        self.assertTrue(s.timer.running)
        s.cancel()
        self.assertFalse(s.timer.running)
        s.cycle_from_keyboard(1)
        s.selected_index = 0
        s.advance(now_ms=40)
        self.assertEqual(s.confirm_count, 0)
        self.assertEqual(s.activated, [])
        self.assertTrue(s.open)

    def test_fixed_path_release_close_reopen_via_set_open_false(self) -> None:
        """External closeTaskSwitcher sets open=false without cancel()."""
        s = switcher_from_contract(self.contract)
        s.cycle_from_keyboard(1)
        s.on_modifier_released(now_ms=0)
        s.set_open(False)  # shell closeTaskSwitcher path
        self.assertFalse(s.timer.running)
        s.cycle_from_keyboard(1)
        s.selected_index = 3
        s.advance(now_ms=40)
        self.assertEqual(s.confirm_count, 0)
        self.assertTrue(s.open)

    def test_normal_modifier_release_still_confirms(self) -> None:
        s = switcher_from_contract(self.contract)
        s.cycle_from_keyboard(1)
        s.selected_index = 1
        s.on_modifier_released(now_ms=100)
        s.advance(now_ms=140)
        self.assertEqual(s.confirm_count, 1)
        self.assertEqual(s.activated, [1])
        self.assertFalse(s.open)
        self.assertFalse(s.timer.running)

    def test_cancel_does_not_activate(self) -> None:
        s = switcher_from_contract(self.contract)
        s.cycle_from_keyboard(1)
        s.selected_index = 1
        s.on_modifier_released(now_ms=0)
        s.cancel()
        s.advance(now_ms=40)
        self.assertEqual(s.confirm_count, 0)
        self.assertEqual(s.activated, [])
        self.assertFalse(s.timer.running)

    def test_mouse_choose_stops_pending_release(self) -> None:
        s = switcher_from_contract(self.contract)
        s.cycle_from_keyboard(1)
        s.on_modifier_released(now_ms=0)
        s.selected_index = 4
        s.confirm()
        self.assertEqual(s.activated, [4])
        s.cycle_from_keyboard(1)
        s.selected_index = 0
        s.advance(now_ms=40)
        self.assertEqual(s.confirm_count, 1)
        self.assertTrue(s.open)

    def test_reopen_then_real_release_confirms_only_once(self) -> None:
        s = switcher_from_contract(self.contract)
        s.cycle_from_keyboard(1)
        s.on_modifier_released(now_ms=0)
        s.cancel()
        s.cycle_from_keyboard(1)
        s.selected_index = 2
        s.on_modifier_released(now_ms=50)
        s.advance(now_ms=90)
        self.assertEqual(s.confirm_count, 1)
        self.assertEqual(s.activated, [2])

    def test_double_release_restart_is_idempotent_single_confirm(self) -> None:
        s = switcher_from_contract(self.contract)
        s.cycle_from_keyboard(1)
        s.selected_index = 1
        s.on_modifier_released(now_ms=0)
        s.on_modifier_released(now_ms=10)
        s.advance(now_ms=40)
        self.assertEqual(s.confirm_count, 0)
        s.advance(now_ms=50)
        self.assertEqual(s.confirm_count, 1)
        self.assertEqual(s.activated, [1])

    def test_false_to_true_open_edge_stops_armed_timer(self) -> None:
        """false→true fires onOpenChanged and must disarm a stale armed timer."""
        s = switcher_from_contract(self.contract)
        # Manually arm without going through a clean session end.
        s.open = False
        s.keyboardMode = False
        s.timer.restart(now_ms=0)
        self.assertTrue(s.timer.running)
        s.set_open(True)  # false→true boundary
        self.assertFalse(s.timer.running)
        s.keyboardMode = True
        s.advance(now_ms=40)
        self.assertEqual(s.confirm_count, 0)

    def test_true_to_true_does_not_fire_session_boundary(self) -> None:
        """QML: open stays true → onOpenChanged does not run; pending release kept."""
        s = switcher_from_contract(self.contract)
        s.cycle_from_keyboard(1)
        s.on_modifier_released(now_ms=0)
        self.assertTrue(s.timer.running)
        s.set_open(True)  # no-op edge
        self.assertTrue(s.timer.running, "true→true must not stop an in-session timer")
        s.advance(now_ms=40)
        self.assertEqual(s.confirm_count, 1)

    def test_keyboard_mode_false_does_not_arm_timer(self) -> None:
        s = switcher_from_contract(self.contract)
        s.set_open(True)
        s.keyboardMode = False
        s.on_modifier_released(now_ms=0)
        self.assertFalse(s.timer.running)
        s.advance(now_ms=40)
        self.assertEqual(s.confirm_count, 0)
        self.assertTrue(s.open)

    def test_timer_confirm_is_single_and_disarms(self) -> None:
        s = switcher_from_contract(self.contract)
        s.cycle_from_keyboard(1)
        s.selected_index = 1
        s.on_modifier_released(now_ms=0)
        s.advance(now_ms=40)
        self.assertEqual(s.confirm_count, 1)
        self.assertFalse(s.timer.running)
        # Late tick must not double-confirm.
        s.advance(now_ms=80)
        self.assertEqual(s.confirm_count, 1)


class BranchParserUnitTests(unittest.TestCase):
    def test_split_open_close_branches(self) -> None:
        body = """
        releaseConfirmTimer.stop();
        if (open) {
            selectedIndex = 1;
        } else {
            keyboardMode = false;
        }
        """
        open_b, close_b = _split_open_close_branches(body)
        self.assertIn("selectedIndex", open_b)
        self.assertIn("keyboardMode", close_b)
        self.assertNotIn("releaseConfirmTimer", open_b)
        self.assertNotIn("releaseConfirmTimer", close_b)

    def test_stop_before_if_allows_block_comment(self) -> None:
        body = """
        releaseConfirmTimer.stop();
        /* session boundary */
        if (open) {
            selectedIndex = 1;
        } else {
            keyboardMode = false;
        }
        """
        self.assertTrue(_stop_before_if_open(body))


class TaskSwitcherReleaseConfirmQmlTests(unittest.TestCase):
    """Real Qt Timer + production TaskSwitcher session boundary via qmltestrunner."""

    def _rewrite_switcher_shell_for_tests(self, dest: Path) -> None:
        """Rewrite only PanelWindow / Wayland shell so Timer/Keys stay production."""
        src = TASK_SWITCHER.read_text(encoding="utf-8")
        src = src.replace("import Quickshell.Wayland\n", "")
        src = src.replace("import Quickshell\n", "")
        src = src.replace("PanelWindow {", "Window {", 1)
        if "import QtQuick.Window" not in src:
            src = src.replace(
                "import QtQuick\n",
                "import QtQuick\nimport QtQuick.Window\n",
                1,
            )

        out_lines = []
        drop_props = (
            "aboveWindows",
            "exclusionMode",
            "exclusiveZone",
            "focusable",
            "implicitWidth",
            "implicitHeight",
        )
        for line in src.splitlines(True):
            if re.search(r"\bWlrLayershell\.", line):
                continue
            if re.search(r"\bTahoeGlass\.regions\b", line):
                continue
            if any(re.search(rf"\b{prop}\s*:", line) for prop in drop_props):
                continue
            out_lines.append(line)
        src = "".join(out_lines)

        def remove_block(text: str, pattern: str) -> str:
            m = re.search(pattern, text)
            if not m:
                return text
            start = m.start()
            brace = text.find("{", m.start())
            depth = 0
            i = brace
            while i < len(text):
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
                i += 1
            while start > 0 and text[start - 1] in " \t":
                start -= 1
            if start > 0 and text[start - 1] == "\n":
                start -= 1
            return text[:start] + text[i:]

        src = remove_block(src, r"anchors\s*\{\s*\n\s*left:\s*true")
        # GlassPanel / ScriptModel / WindowPreviewFallback are heavy for Timer-only tests.
        # Replace GlassPanel block with empty Item; keep ListView model as plain array binding.
        src = remove_block(src, r"GlassPanel\s*\{")
        src = re.sub(
            r"model:\s*ScriptModel\s*\{\s*(?:objectProp:\s*\"modelKey\"\s*)?"
            r"values:\s*root\.windowChoices\s*\}",
            "model: root.windowChoices",
            src,
            count=1,
        )
        # WindowPreviewFallback may reference unavailable types; keep if present in components.
        src = src.replace(
            "readonly property int screenWidth: Math.max(1, numberOr(root.screen && root.screen.width, root.width))",
            "readonly property int screenWidth: Math.max(1, numberOr(root.width, 800))",
        )
        src = src.replace(
            "readonly property int screenHeight: Math.max(1, numberOr(root.screen && root.screen.height, root.height))",
            "readonly property int screenHeight: Math.max(1, numberOr(root.height, 600))",
        )
        dest.write_text(src, encoding="utf-8")

    def test_real_qml_release_timer_session_race(self) -> None:
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(runner, "Qt 6 qmltestrunner is required")
        self.assertTrue(QML_TEST.is_file(), f"missing {QML_TEST}")

        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp) / "components"
            work.mkdir()
            rewritten = work / "TaskSwitcher.qml"
            self._rewrite_switcher_shell_for_tests(rewritten)
            body = rewritten.read_text(encoding="utf-8")
            # Keep rewrite checks structural so the same harness can RED on the
            # pre-fix baseline (no session-boundary stop) via real Timer races.
            self.assertIn("releaseConfirmTimer", body)
            self.assertIn("onOpenChanged", body)
            self.assertIn("interval: 40", body)
            self.assertNotIn("PanelWindow", body)
            self.assertNotIn("WlrLayershell", body)

            for entry in (SHELL_ROOT / "components").iterdir():
                if entry.name == "TaskSwitcher.qml":
                    continue
                # Prefer symlink so Motion.js / WindowPreviewFallback stay real.
                try:
                    os.symlink(entry, work / entry.name)
                except OSError:
                    if entry.is_file():
                        shutil.copy2(entry, work / entry.name)

            qml_test = Path(tmp) / "tst_task_switcher.qml"
            base = QML_TEST.read_text(encoding="utf-8")
            base = base.replace(
                'property string switcherSource: ""',
                f'property string switcherSource: "{rewritten.as_posix()}"',
            )
            qml_test.write_text(base, encoding="utf-8")

            env = os.environ.copy()
            env.setdefault("QT_QPA_PLATFORM", "offscreen")
            local_qml = Path.home() / ".local" / "lib" / "qt6" / "qml"
            test_qml = SHELL_ROOT / "tests" / "qml_imports"
            existing = env.get("QML2_IMPORT_PATH", "")
            paths = [str(test_qml), str(local_qml), str(work)]
            if existing:
                paths.append(existing)
            env["QML2_IMPORT_PATH"] = ":".join(paths)
            # Import path for relative "Motion.js" / sibling components.
            env["QML_IMPORT_PATH"] = env.get("QML_IMPORT_PATH", "")
            result = subprocess.run(
                [runner, "-input", str(qml_test)],
                cwd=str(work),
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
