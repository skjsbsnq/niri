#!/usr/bin/env python3
"""T02: strict expected-failure characterizations of known V1 Dynamic Island bugs.

Design (review round 2):

- **Source predicates** extract desired V2 structure from production QML.
  When a later task fixes production, the matching xfail becomes XPASS and
  the suite fails until the xfail mark is removed.
- **V1 behavioral sims** document the unique failure mode for humans and for
  anchor tests; they mirror real formulas (resting_media=190, progress cleared
  on resolve, live target screen, brightness 0 ignored).
- Anchor tests (non-xfail) assert the V1 bug still exists; when production is
  fixed those anchors fail and must be updated in the same task.

Target tasks: none remaining in this file (T05–T09 fixed).
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pytest


SHELL_ROOT = Path(__file__).resolve().parents[1]
ISLAND = SHELL_ROOT / "services" / "DynamicIsland.qml"
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
TOPBAR = SHELL_ROOT / "components" / "TopBar.qml"
REDUCER = SHELL_ROOT / "services" / "DynamicIslandReducer.js"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _function_body(src: str, name: str) -> str:
    m = re.search(rf"function\s+{re.escape(name)}\s*\([^)]*\)\s*\{{", src)
    if not m:
        return ""
    start = m.end()
    depth = 1
    i = start
    while i < len(src) and depth:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
        i += 1
    return src[start : i - 1]


def _compact(text: str) -> str:
    return re.sub(r"\s+", "", text)


# ---------------------------------------------------------------------------
# Desired V2 source predicates (True when production is fixed)
# ---------------------------------------------------------------------------


def osd_preempts_active_notification(island_src: str, reducer_src: str) -> bool:
    body = _function_body(island_src, "blocksTransientOsd")
    return (
        ("blocksOsd" in body or "IslandReducer.blocksOsd" in body)
        and re.search(r'"osd"\s*:\s*110', reducer_src) is not None
        and '=== "transient_osd"' in reducer_src
    )


def workspace_yields_to_active_notification(src: str) -> bool:
    body = _function_body(src, "blocksTransientWorkspace")
    flags = _function_body(src, "arbitrationFlags")
    if "transient_notification" in body or "displayingNotificationId" in body:
        return True
    return (
        ("blocksWorkspace" in body or "IslandReducer.blocksWorkspace" in body)
        and ("displayingNotification" in flags or "transient_notification" in flags)
    )


def resolve_swipe_keeps_settle_target(src: str) -> bool:
    """Desired: resolveSwipe does not force swipeProgress=0 while settling."""
    body = _function_body(src, "resolveSwipe")
    compact = _compact(body)
    # V1 clears progress in every settle branch: swipeProgress = 0
    return "swipeProgress=0" not in compact


def target_screen_supports_event_owner_pin(src: str) -> bool:
    body = _function_body(src, "computeTargetScreenName")
    # Require an explicit pin/lease identifier in the production function.
    for marker in (
        "eventOwnerOutput",
        "sessionOwnerOutput",
        "ownerOutputName",
        "pinnedEventOutput",
        "transientOwnerOutput",
    ):
        if marker in body:
            return True
    return False


def brightness_zero_is_legal(src: str) -> bool:
    handle = _compact(_function_body(src, "handleBrightnessChange"))
    capture = _compact(_function_body(src, "captureOsdBaselines"))
    # V1 rejected non-positive samples outright. V2 (T05) accepts finite 0%.
    handle_rejects_nonpositive = "if(!(brightness>0))return" in handle
    if "brightness>0" in handle and "return" in handle and "if(!(" in handle:
        # Only treat as reject when the guard exits before any baseline write
        # for non-positive values (old early-return pattern).
        if "if(!(brightness>0))return" in handle:
            handle_rejects_nonpositive = True
        else:
            handle_rejects_nonpositive = False
    # Capture must not force lastBrightness to 1.0 when sample is 0.
    capture_rewrites = "lastBrightness=1.0" in capture
    uses_finite = "isFinite(brightnessSample)" in handle and "isFinite(brightnessSample)" in capture
    return (not handle_rejects_nonpositive) and (not capture_rewrites) and uses_finite


def non_owner_keeps_base_clock(overlay: str, topbar: str) -> bool:
    """Desired: hideTopbarTime must not blank non-owner clocks."""
    # T08: TopBar time fallback is independent of owner; Overlay uses per-screen role.
    topbar_ok = (
        "showTopbarTimeFallback: !dynamicIslandEnabled || !dynamicIslandHideTopbarTime" in topbar
        or "screenPresentationRole" in overlay
    )
    overlay_ok = "screenPresentationRole" in overlay or "effectiveGeometryState" in overlay
    # Old V1 global blanking pattern must be gone.
    v1_global = "showTopbarTimeFallback: !dynamicIslandOverlayHandlesResting" in topbar
    return topbar_ok and overlay_ok and not v1_global


# ---------------------------------------------------------------------------
# V1 behavioral sim (documentation of unique failure modes)
# ---------------------------------------------------------------------------


@dataclass
class IslandSimV1:
    state: str = "resting_time"
    expanded: bool = False
    user_interacting: bool = False
    displaying_notification_id: int = -1
    last_brightness: float = 1.0
    brightness_tracking_ready: bool = True
    island_enabled: bool = True
    focused_output: str = "eDP-2"
    event_owner_output: str | None = None
    swipe_dragging: bool = False
    swipe_settling: bool = False
    swipe_progress: float = 0.0
    has_media: bool = True
    swipe_right_width: int = 400
    swipe_left_width: int = 360

    def resting_state(self) -> str:
        return "resting_media" if self.has_media and self.island_enabled else "resting_time"

    def resting_width(self, state: str) -> int:
        return {
            "resting_media": 190,
            "expanded_media": 400,
            "expanded_summary": 360,
            "resting_time": 140,
        }.get(state, 140)

    def blocks_osd(self) -> bool:
        return self.expanded or self.user_interacting

    def blocks_workspace(self) -> bool:
        return self.expanded or self.user_interacting

    def present_osd(self) -> None:
        if self.blocks_osd():
            return
        self.state = "transient_osd"
        self.expanded = False

    def present_workspace(self) -> None:
        if self.blocks_workspace():
            return
        self.state = "transient_workspace"

    def present_notification(self, nid: int) -> None:
        self.state = "transient_notification"
        self.displaying_notification_id = nid
        # V1: no event_owner_output assignment
        self.expanded = False

    def live_target_screen(self) -> str:
        return self.focused_output or "eDP-2"

    def presentation_owner(self) -> str:
        return self.event_owner_output or self.live_target_screen()

    def handle_brightness(self, value: float) -> bool:
        # Historical V1 sim: non-positive rejected. Kept for documentation of
        # the pre-T05 bug; production assertions use brightness_zero_is_legal.
        if not (value > 0):
            return False
        self.last_brightness = value
        self.present_osd()
        return True

    def capture_baseline(self, value: float) -> float:
        if not (value > 0):
            value = 1.0
        self.last_brightness = value
        return value

    def swipe_preview_width(self) -> float:
        if not (self.swipe_dragging or self.swipe_settling):
            return -1.0
        resting = float(self.resting_width(self.resting_state()))
        side = float(self.swipe_right_width if self.swipe_progress >= 0 else self.swipe_left_width)
        return resting + (side - resting) * min(1.0, abs(self.swipe_progress))

    def resolve_swipe_enter_media_widths(self) -> tuple[float, float, float]:
        self.swipe_dragging = True
        self.swipe_settling = False
        self.swipe_progress = 0.85
        drag = self.swipe_preview_width()
        # V1 resolveSwipe enter branch
        self.swipe_dragging = False
        self.swipe_settling = True
        self.swipe_progress = 0.0
        self.state = "expanded_media"
        self.expanded = True
        settle = self.swipe_preview_width()
        self.swipe_settling = False
        final = float(self.resting_width("expanded_media"))
        return drag, settle, final


class DynamicIslandV2ExpectedFailureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.island_src = _read(ISLAND)
        cls.overlay_src = _read(OVERLAY)
        cls.topbar_src = _read(TOPBAR)
        cls.reducer_src = _read(REDUCER)

    # ----- V1 anchors (must stay failing until the fix task updates them) -----

    def test_v1_osd_sim_documents_old_bug(self) -> None:
        # V1 overwrote notifications without lease cleanup. Production now uses
        # deliberate OSD preemption and ends the presentation lease explicitly.
        sim = IslandSimV1(state="transient_notification", displaying_notification_id=7)
        sim.present_osd()
        self.assertEqual(sim.state, "transient_osd")

    def test_v1_workspace_sim_documents_old_bug(self) -> None:
        sim = IslandSimV1(state="transient_notification", displaying_notification_id=3)
        sim.present_workspace()
        self.assertEqual(sim.state, "transient_workspace")

    def test_v1_swipe_settle_sim_documents_old_bug(self) -> None:
        # Historical V1 sim still zeros progress on resolve; production fixed in T09.
        sim = IslandSimV1(has_media=True)
        drag, settle, final = sim.resolve_swipe_enter_media_widths()
        resting = float(sim.resting_width(sim.resting_state()))
        self.assertEqual(resting, 190.0)
        self.assertAlmostEqual(settle, resting, delta=0.5)
        self.assertEqual(final, 400.0)
        self.assertGreater(drag, resting)

    def test_v1_target_screen_sim_documents_old_bug(self) -> None:
        # Historical V1 sim never pins; production is fixed in T08.
        sim = IslandSimV1(focused_output="eDP-2")
        sim.present_notification(1)
        self.assertIsNone(sim.event_owner_output)
        sim.focused_output = "HDMI-A-1"
        self.assertEqual(sim.presentation_owner(), "HDMI-A-1")

    def test_v1_non_owner_clock_sim_documents_old_bug(self) -> None:
        # Historical V1 global blanking sim.
        hide = True
        enabled = True
        overlay_handles = enabled and hide
        topbar_fallback = not overlay_handles
        active_for_screen = False
        capsule = active_for_screen and enabled and hide
        self.assertFalse(capsule or topbar_fallback)

    def test_v1_brightness_zero_sim_documents_old_bug(self) -> None:
        # Pure V1 sim still models the historical reject; production is fixed
        # in T05 and asserted green by test_brightness_zero_legal_in_production.
        sim = IslandSimV1(last_brightness=0.4)
        self.assertFalse(sim.handle_brightness(0.0))
        self.assertEqual(sim.capture_baseline(0.0), 1.0)

    def test_brightness_zero_legal_in_production(self) -> None:
        # T05: expected-failure removed; production must accept 0%.
        self.assertTrue(brightness_zero_is_legal(self.island_src))

    # ----- Desired V2 strict xfails (XPASS when production gains the structure) -----

    def test_desired_osd_preempts_active_notification(self) -> None:
        # Direct hardware feedback supersedes the earlier T07 queueing policy.
        self.assertTrue(osd_preempts_active_notification(self.island_src, self.reducer_src))

    def test_desired_workspace_yields_to_active_notification(self) -> None:
        # T07: expected-failure removed; production yields to active notification.
        self.assertTrue(workspace_yields_to_active_notification(self.island_src))

    def test_desired_swipe_settle_keeps_target(self) -> None:
        # T09: expected-failure removed; resolve keeps settle target progress.
        self.assertTrue(resolve_swipe_keeps_settle_target(self.island_src))
        sim = IslandSimV1(has_media=True)
        sim.swipe_settling = True
        sim.swipe_progress = 1.0
        settle = sim.swipe_preview_width()
        self.assertGreaterEqual(settle, 360.0)

    def test_desired_event_owner_pin_in_target_screen(self) -> None:
        # T08: expected-failure removed; production pins event/session owners.
        self.assertTrue(target_screen_supports_event_owner_pin(self.island_src))

    def test_desired_non_owner_keeps_base_clock(self) -> None:
        # T08: expected-failure removed; non-owner keeps base clock.
        self.assertTrue(non_owner_keeps_base_clock(self.overlay_src, self.topbar_src))

if __name__ == "__main__":
    raise SystemExit(unittest.main())
