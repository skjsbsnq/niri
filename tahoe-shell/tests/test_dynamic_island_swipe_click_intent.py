#!/usr/bin/env python3
"""Task 11: Dynamic Island swipe must separate click vs drag intent.

Root cause: capsule MouseArea called beginSwipe() on any position change,
so micro-jitter and vertical/diagonal drags started settle animations or
mis-fired chip clicks. Fix: IslandMotion arm/reject tokens + phase machine
with horizontal-only begin and ambiguous-intent reject.
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal


SHELL_ROOT = Path(__file__).resolve().parents[1]
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
MOTION = SHELL_ROOT / "components" / "DynamicIslandMotion.js"
SERVICE = SHELL_ROOT / "services" / "DynamicIsland.qml"

Decision = Literal["click_eligible", "begin_swipe", "reject"]


@dataclass(frozen=True)
class SourceContract:
    """Intent policy extracted from QML/JS sources (not a hand-copied mirror)."""

    arm_px: float
    vertical_reject_px: float
    has_both_axes_jitter_gate: bool
    has_ambiguous_reject: bool
    always_suppress_after_swipe_session: bool
    wheel_ignores_pointer_pressed: bool
    press_cancels_inflight_swipe: bool
    uses_motion_arm_token: bool
    uses_motion_vertical_token: bool


def extract_capsule_mousearea(overlay: str) -> str:
    match = re.search(
        r"MouseArea\s*\{(?P<body>[\s\S]*?handleChipClick[\s\S]*?)\n       \}",
        overlay,
    )
    if not match:
        raise AssertionError("capsule MouseArea not found")
    return match.group(0)


def extract_motion_number(motion: str, name: str) -> float:
    match = re.search(rf"var\s+{re.escape(name)}\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*;", motion)
    if not match:
        raise AssertionError(f"motion token missing: {name}")
    return float(match.group(1))


def extract_position_changed_body(capsule: str) -> str:
    pos = re.search(r"onPositionChanged: function\(mouse\) \{([\s\S]*?)\n           \}", capsule)
    if not pos:
        raise AssertionError("onPositionChanged body not found")
    return pos.group(1)


def decision_order_markers(pos_body: str) -> list[tuple[str, int]]:
    """Locate decision gates by source index so reordering fails tests.

    Required order for the arming path (after swipeDragging early-return):
      vertical_reject → both_axes_jitter → horizontal_commit_or_ambiguous → beginSwipe
    """
    markers: list[tuple[str, int]] = []
    patterns = [
        (
            "vertical_reject",
            r"absY\s*>=\s*IslandMotion\.swipeVerticalRejectPx\s*&&\s*absY\s*>\s*absX",
        ),
        (
            "both_axes_jitter",
            r"absX\s*<\s*IslandMotion\.swipeArmThresholdPx\s*\n\s*&&\s*absY\s*<\s*IslandMotion\.swipeArmThresholdPx",
        ),
        (
            "horizontal_commit_predicate",
            r"absX\s*>\s*absY\s*&&\s*absX\s*>=\s*IslandMotion\.swipeArmThresholdPx",
        ),
        ("begin_swipe_call", r"beginSwipe\s*\(\s*\)"),
    ]
    for name, pattern in patterns:
        match = re.search(pattern, pos_body)
        if not match:
            raise AssertionError(f"decision marker missing in onPositionChanged: {name}")
        markers.append((name, match.start()))
    return markers


def extract_source_contract(overlay: str, motion: str) -> SourceContract:
    capsule = extract_capsule_mousearea(overlay)
    pos_body = extract_position_changed_body(capsule)
    # Fail fast if decision order is wrong (begin-first reordering must not pass).
    order = decision_order_markers(pos_body)
    names = [name for name, _ in order]
    indices = [idx for _, idx in order]
    if names != [
        "vertical_reject",
        "both_axes_jitter",
        "horizontal_commit_predicate",
        "begin_swipe_call",
    ]:
        raise AssertionError(f"unexpected decision markers: {names}")
    if indices != sorted(indices):
        raise AssertionError(
            "onPositionChanged decision order violated: "
            + ", ".join(f"{n}@{i}" for n, i in order)
        )

    released = re.search(r"onReleased: function\(mouse\) \{([\s\S]*?)\n           \}", capsule)
    if not released:
        raise AssertionError("onReleased body not found")
    rel_body = released.group(1)
    pressed = re.search(r"onPressed: function\(mouse\) \{([\s\S]*?)\n           \}", capsule)
    if not pressed:
        raise AssertionError("onPressed body not found")
    press_body = pressed.group(1)
    wheel = re.search(r"onWheel: function\(wheel\) \{([\s\S]*?)\n           \}", capsule)
    if not wheel:
        raise AssertionError("onWheel body not found")
    wheel_body = wheel.group(1)

    # Ambiguous reject must appear as the negation of horizontal commit before begin.
    commit_at = order[2][1]
    begin_at = order[3][1]
    between = pos_body[commit_at:begin_at]
    has_ambiguous = (
        "gestureRejected = true" in between
        and "!" in between
        and "absX > absY && absX >= IslandMotion.swipeArmThresholdPx" in between
    )

    return SourceContract(
        arm_px=extract_motion_number(motion, "swipeArmThresholdPx"),
        vertical_reject_px=extract_motion_number(motion, "swipeVerticalRejectPx"),
        has_both_axes_jitter_gate=(
            "absX < IslandMotion.swipeArmThresholdPx" in pos_body
            and "absY < IslandMotion.swipeArmThresholdPx" in pos_body
        ),
        has_ambiguous_reject=has_ambiguous and pos_body.count("gestureRejected = true") >= 2,
        always_suppress_after_swipe_session=(
            "swipeDragging" in rel_body
            and "suppressClickTemporarily()" in rel_body
            and "if (moved)" not in rel_body
        ),
        wheel_ignores_pointer_pressed=(
            "if (pressed || armingSwipe || gestureRejected)" in wheel_body
        ),
        press_cancels_inflight_swipe=(
            "cancelSwipe()" in press_body and "wheelSwipeSettle.stop()" in press_body
        ),
        uses_motion_arm_token="IslandMotion.swipeArmThresholdPx" in pos_body,
        uses_motion_vertical_token="IslandMotion.swipeVerticalRejectPx" in pos_body,
    )


def decide_intent(abs_x: float, abs_y: float, *, arm: float, vertical_reject: float) -> Decision:
    """Independent policy oracle matching Task 11 acceptance prose.

    Not a line-by-line port of QML: encodes the product contract so a
    regression in source order/tokens fails even if a Python mirror is updated.
    """
    if abs_y >= vertical_reject and abs_y > abs_x:
        return "reject"
    if abs_x < arm and abs_y < arm:
        return "click_eligible"
    if abs_x > abs_y and abs_x >= arm:
        return "begin_swipe"
    return "reject"


@dataclass
class FakeIslandService:
    can_swipe: bool = True
    swipe_dragging: bool = False
    swipe_moved: bool = False
    user_interacting: bool = False
    begin_calls: int = 0
    advance_calls: list[tuple[float, float]] = field(default_factory=list)
    resolve_calls: int = 0
    cancel_calls: int = 0
    chip_clicks: list[int] = field(default_factory=list)
    interacting_log: list[bool] = field(default_factory=list)

    def canSwipe(self) -> bool:
        return self.can_swipe

    def setUserInteracting(self, active: bool) -> None:
        self.user_interacting = bool(active)
        self.interacting_log.append(self.user_interacting)

    def beginSwipe(self) -> bool:
        if not self.can_swipe:
            return False
        self.begin_calls += 1
        self.swipe_dragging = True
        self.swipe_moved = False
        return True

    def advanceSwipe(self, delta_x: float, delta_y: float) -> None:
        if not self.swipe_dragging:
            return
        self.advance_calls.append((float(delta_x), float(delta_y)))
        if abs(float(delta_x)) > 0.01:
            self.swipe_moved = True

    def resolveSwipe(self) -> None:
        if not self.swipe_dragging:
            return
        self.resolve_calls += 1
        self.swipe_dragging = False

    def cancelSwipe(self) -> None:
        if not self.swipe_dragging:
            return
        self.cancel_calls += 1
        self.swipe_dragging = False
        self.swipe_moved = False

    def consumeSwipeMoved(self) -> bool:
        moved = self.swipe_moved
        self.swipe_moved = False
        return moved

    def handleChipClick(self, button: int) -> None:
        self.chip_clicks.append(int(button))


class CapsuleGestureModel:
    """Driver that consults the independent oracle + service APIs."""

    LEFT = 1
    RIGHT = 2

    def __init__(self, service: FakeIslandService, contract: SourceContract) -> None:
        self.service = service
        self.contract = contract
        self.swipe_start_x = 0.0
        self.swipe_start_y = 0.0
        self.swipe_last_x = 0.0
        self.arming_swipe = False
        self.gesture_rejected = False
        self.suppress_click = False
        self.pressed = False

    def reset_phase(self) -> None:
        self.arming_swipe = False
        self.gesture_rejected = False

    def on_pressed(self, x: float, y: float, button: int = LEFT) -> None:
        if self.service.swipe_dragging:
            self.service.cancelSwipe()
        self.pressed = True
        self.service.setUserInteracting(True)
        self.swipe_start_x = x
        self.swipe_start_y = y
        self.swipe_last_x = x
        self.gesture_rejected = False
        self.arming_swipe = button == self.LEFT and self.service.canSwipe()

    def on_position_changed(self, x: float, y: float) -> None:
        if not self.pressed:
            return
        if self.service.swipe_dragging:
            self.service.advanceSwipe(x - self.swipe_last_x, abs(y - self.swipe_start_y))
            self.swipe_last_x = x
            return
        if not self.arming_swipe or self.gesture_rejected:
            return

        total_dx = x - self.swipe_start_x
        total_dy = y - self.swipe_start_y
        abs_x = abs(total_dx)
        abs_y = abs(total_dy)
        decision = decide_intent(
            abs_x,
            abs_y,
            arm=self.contract.arm_px,
            vertical_reject=self.contract.vertical_reject_px,
        )
        if decision == "click_eligible":
            return
        if decision == "reject":
            self.gesture_rejected = True
            self.arming_swipe = False
            self.suppress_click = True
            return
        if not self.service.beginSwipe():
            self.arming_swipe = False
            return
        self.swipe_last_x = x
        self.service.advanceSwipe(total_dx, abs_y)

    def on_released(self) -> None:
        if self.service.swipe_dragging:
            self.service.consumeSwipeMoved()
            self.service.resolveSwipe()
            self.suppress_click = True
        elif self.gesture_rejected:
            self.suppress_click = True
        self.service.setUserInteracting(False)
        self.pressed = False
        self.reset_phase()

    def on_canceled(self) -> None:
        if self.service.swipe_dragging:
            self.service.cancelSwipe()
        self.service.setUserInteracting(False)
        self.pressed = False
        self.reset_phase()

    def on_clicked(self, button: int = LEFT) -> None:
        if self.suppress_click:
            return
        self.service.handleChipClick(button)

    def on_wheel(self, delta: float) -> bool:
        if self.pressed or self.arming_swipe or self.gesture_rejected:
            return False
        if not self.service.canSwipe():
            return False
        if delta == 0:
            return False
        if not self.service.swipe_dragging:
            self.service.beginSwipe()
        self.service.advanceSwipe(delta * 0.8, 0)
        return True


class TestSourceContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.overlay = OVERLAY.read_text(encoding="utf-8")
        cls.motion = MOTION.read_text(encoding="utf-8")
        cls.service_src = SERVICE.read_text(encoding="utf-8")
        cls.capsule = extract_capsule_mousearea(cls.overlay)
        cls.contract = extract_source_contract(cls.overlay, cls.motion)

    def test_motion_tokens_exported_and_referenced(self) -> None:
        c = self.contract
        self.assertGreater(c.arm_px, 0)
        self.assertGreater(c.vertical_reject_px, c.arm_px)
        self.assertTrue(c.uses_motion_arm_token)
        self.assertTrue(c.uses_motion_vertical_token)
        # Progress thresholds must stay untouched (Task 11 is intent only).
        self.assertIn("var swipeEnterThreshold = 0.56", self.motion)
        self.assertIn("var swipeReturnThreshold = 0.44", self.motion)

    def test_source_implements_required_gates(self) -> None:
        c = self.contract
        self.assertTrue(c.has_both_axes_jitter_gate)
        self.assertTrue(c.has_ambiguous_reject)
        self.assertTrue(c.always_suppress_after_swipe_session)
        self.assertTrue(c.wheel_ignores_pointer_pressed)
        self.assertTrue(c.press_cancels_inflight_swipe)

    def test_position_changed_decision_order_is_enforced(self) -> None:
        pos_body = extract_position_changed_body(self.capsule)
        order = decision_order_markers(pos_body)
        self.assertEqual(
            [name for name, _ in order],
            [
                "vertical_reject",
                "both_axes_jitter",
                "horizontal_commit_predicate",
                "begin_swipe_call",
            ],
        )
        indices = [idx for _, idx in order]
        self.assertEqual(indices, sorted(indices))
        # beginSwipe must not appear before the horizontal commit predicate.
        self.assertLess(order[2][1], order[3][1])

    def test_begin_first_reordering_would_fail_order_check(self) -> None:
        """Prove that moving beginSwipe before gates breaks the order contract."""
        pos_body = extract_position_changed_body(self.capsule)
        # Hoist beginSwipe to the top of the handler body.
        corrupted = "if (!root.dynamicIslandService.beginSwipe()) return;\n" + pos_body
        markers = decision_order_markers(corrupted)
        indices = [idx for _, idx in markers]
        self.assertNotEqual(
            indices,
            sorted(indices),
            "begin-first reordering must violate decision_order_markers sort check",
        )

    def test_no_inline_magic_pixel_thresholds(self) -> None:
        self.assertNotRegex(
            self.capsule,
            r"absX\s*[<>=]+\s*[0-9]+|absY\s*[<>=]+\s*[0-9]+",
        )

    def test_service_apis_unchanged_surface(self) -> None:
        for name in ("beginSwipe", "advanceSwipe", "resolveSwipe", "cancelSwipe", "handleChipClick"):
            self.assertIn(f"function {name}", self.service_src)
            self.assertIn(name, self.capsule)

    def test_no_parallel_overlay_or_hit_hacks(self) -> None:
        self.assertNotIn("mapToItem", self.capsule)
        self.assertNotIn("childAt(", self.capsule)
        self.assertNotIn("safeBeginSwipe", self.overlay)
        self.assertIn("resetGesturePhase", self.capsule)


class TestIndependentOracle(unittest.TestCase):
    """Oracle table: product contract independent of QML control flow text."""

    def setUp(self) -> None:
        self.contract = extract_source_contract(
            OVERLAY.read_text(encoding="utf-8"),
            MOTION.read_text(encoding="utf-8"),
        )
        self.arm = self.contract.arm_px
        self.vert = self.contract.vertical_reject_px

    def test_oracle_table(self) -> None:
        cases = [
            (0, 0, "click_eligible"),
            (self.arm - 1, 2, "click_eligible"),
            (2, self.arm - 1, "click_eligible"),
            (self.arm, self.arm - 1, "begin_swipe"),
            (self.arm + 5, 2, "begin_swipe"),
            (self.arm, self.arm, "reject"),  # diagonal dead-band
            (self.arm + 5, self.arm + 6, "reject"),
            (8, self.vert + 5, "reject"),
            (3, self.vert, "reject"),
            (3, self.arm + 5, "reject"),  # mid-band vertical: past arm Y, below reject
            (self.vert + 5, self.vert + 10, "reject"),
        ]
        for abs_x, abs_y, expected in cases:
            with self.subTest(abs_x=abs_x, abs_y=abs_y, expected=expected):
                self.assertEqual(
                    decide_intent(abs_x, abs_y, arm=self.arm, vertical_reject=self.vert),
                    expected,
                )


class TestSwipeClickIntentBehavior(unittest.TestCase):
    def setUp(self) -> None:
        self.contract = extract_source_contract(
            OVERLAY.read_text(encoding="utf-8"),
            MOTION.read_text(encoding="utf-8"),
        )
        self.service = FakeIslandService()
        self.g = CapsuleGestureModel(self.service, self.contract)
        self.arm = self.contract.arm_px
        self.vert = self.contract.vertical_reject_px

    def test_stable_press_release_is_click(self) -> None:
        self.g.on_pressed(100, 50)
        self.g.on_released()
        self.g.on_clicked()
        self.assertEqual(self.service.begin_calls, 0)
        self.assertEqual(self.service.chip_clicks, [1])
        self.assertFalse(self.service.user_interacting)

    def test_light_jitter_below_arm_is_click(self) -> None:
        self.g.on_pressed(100, 50)
        self.g.on_position_changed(100 + self.arm - 1, 50 + 2)
        self.g.on_released()
        self.g.on_clicked()
        self.assertEqual(self.service.begin_calls, 0)
        self.assertEqual(self.service.chip_clicks, [1])

    def test_horizontal_drag_begins_swipe_and_never_clicks(self) -> None:
        self.g.on_pressed(100, 50)
        self.g.on_position_changed(100 + self.arm + 5, 50 + 2)
        self.assertEqual(self.service.begin_calls, 1)
        self.g.on_position_changed(100 + self.arm + 40, 50 + 3)
        self.g.on_released()
        self.g.on_clicked()
        self.assertEqual(self.service.resolve_calls, 1)
        self.assertEqual(self.service.chip_clicks, [])

    def test_swipe_session_without_moved_flag_still_suppresses_click(self) -> None:
        self.g.on_pressed(100, 50)
        self.g.on_position_changed(100 + self.arm + 1, 50)
        # Force "no moved" after begin to simulate near-zero progress advance.
        self.service.swipe_moved = False
        self.g.on_released()
        self.g.on_clicked()
        self.assertEqual(self.service.begin_calls, 1)
        self.assertEqual(self.service.chip_clicks, [])

    def test_vertical_drag_rejects_without_begin(self) -> None:
        self.g.on_pressed(100, 50)
        self.g.on_position_changed(100 + 3, 50 + self.vert + 5)
        self.assertEqual(self.service.begin_calls, 0)
        self.g.on_released()
        self.g.on_clicked()
        self.assertEqual(self.service.chip_clicks, [])

    def test_diagonal_past_arm_rejects_click(self) -> None:
        self.g.on_pressed(100, 50)
        self.g.on_position_changed(100 + self.arm + 5, 50 + self.arm + 6)
        self.assertEqual(self.service.begin_calls, 0)
        self.assertTrue(self.g.suppress_click)
        self.g.on_released()
        self.g.on_clicked()
        self.assertEqual(self.service.chip_clicks, [])

    def test_equal_diagonal_at_arm_rejects(self) -> None:
        self.g.on_pressed(100, 50)
        self.g.on_position_changed(100 + self.arm, 50 + self.arm)
        self.assertEqual(self.service.begin_calls, 0)
        self.g.on_released()
        self.g.on_clicked()
        self.assertEqual(self.service.chip_clicks, [])

    def test_interleaved_small_h_then_large_v_rejects(self) -> None:
        self.g.on_pressed(100, 50)
        self.g.on_position_changed(100 + 3, 50 + 5)
        self.g.on_position_changed(100 + 4, 50 + self.vert + 2)
        self.assertEqual(self.service.begin_calls, 0)
        self.g.on_released()
        self.g.on_clicked()
        self.assertEqual(self.service.chip_clicks, [])

    def test_cancel_armed_and_dragging(self) -> None:
        self.g.on_pressed(100, 50)
        self.g.on_position_changed(100 + 2, 50)
        self.g.on_canceled()
        self.assertEqual(self.service.begin_calls, 0)
        self.assertFalse(self.service.user_interacting)

        self.service = FakeIslandService()
        self.g = CapsuleGestureModel(self.service, self.contract)
        self.g.on_pressed(100, 50)
        self.g.on_position_changed(100 + self.arm + 20, 50)
        self.g.on_canceled()
        self.assertEqual(self.service.cancel_calls, 1)
        self.assertFalse(self.service.user_interacting)

    def test_right_button_click_without_arming(self) -> None:
        self.g.on_pressed(100, 50, button=CapsuleGestureModel.RIGHT)
        self.g.on_position_changed(100 + 50, 50)
        self.assertEqual(self.service.begin_calls, 0)
        self.g.on_released()
        self.g.on_clicked(button=CapsuleGestureModel.RIGHT)
        self.assertEqual(self.service.chip_clicks, [2])

    def test_cannot_swipe_allows_click(self) -> None:
        self.service.can_swipe = False
        self.g.on_pressed(100, 50)
        self.g.on_position_changed(100 + 50, 50)
        self.g.on_released()
        self.g.on_clicked()
        self.assertEqual(self.service.begin_calls, 0)
        self.assertEqual(self.service.chip_clicks, [1])

    def test_seed_advance_uses_total_displacement(self) -> None:
        self.g.on_pressed(100, 50)
        target_x = 100 + self.arm + 12
        self.g.on_position_changed(target_x, 52)
        self.assertEqual(self.service.advance_calls[0][0], target_x - 100)

    def test_wheel_ignored_while_pointer_pressed(self) -> None:
        self.g.on_pressed(100, 50)
        accepted = self.g.on_wheel(40)
        self.assertFalse(accepted)
        self.assertEqual(self.service.begin_calls, 0)

    def test_wheel_works_when_idle(self) -> None:
        accepted = self.g.on_wheel(40)
        self.assertTrue(accepted)
        self.assertEqual(self.service.begin_calls, 1)

    def test_press_cancels_inflight_wheel_swipe(self) -> None:
        self.g.on_wheel(40)
        self.assertTrue(self.service.swipe_dragging)
        self.g.on_pressed(100, 50)
        self.assertEqual(self.service.cancel_calls, 1)
        self.assertFalse(self.service.swipe_dragging)


class TestOldBugWouldFail(unittest.TestCase):
    def test_old_policy_begins_on_jitter_new_does_not(self) -> None:
        old = FakeIslandService()
        # Pre-Task-11: any move while arming → beginSwipe.
        if not old.swipe_dragging:
            old.beginSwipe()
        old.advanceSwipe(3, 1)
        self.assertEqual(old.begin_calls, 1)

        contract = extract_source_contract(
            OVERLAY.read_text(encoding="utf-8"),
            MOTION.read_text(encoding="utf-8"),
        )
        new = FakeIslandService()
        g = CapsuleGestureModel(new, contract)
        g.on_pressed(100, 50)
        g.on_position_changed(103, 51)
        self.assertEqual(new.begin_calls, 0)
        self.assertEqual(
            decide_intent(3, 1, arm=contract.arm_px, vertical_reject=contract.vertical_reject_px),
            "click_eligible",
        )

    def test_old_diagonal_clicked_new_rejects(self) -> None:
        contract = extract_source_contract(
            OVERLAY.read_text(encoding="utf-8"),
            MOTION.read_text(encoding="utf-8"),
        )
        # Old dead-band: past arm, absX <= absY, absY < vertical reject → click.
        abs_x = contract.arm_px + 5
        abs_y = contract.arm_px + 6
        self.assertEqual(
            decide_intent(abs_x, abs_y, arm=contract.arm_px, vertical_reject=contract.vertical_reject_px),
            "reject",
        )
        # Confirm source has ambiguous reject gate so this is not oracle-only.
        self.assertTrue(contract.has_ambiguous_reject)


if __name__ == "__main__":
    unittest.main()
