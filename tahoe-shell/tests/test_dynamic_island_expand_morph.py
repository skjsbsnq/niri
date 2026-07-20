#!/usr/bin/env python3
"""Expand morph coordination: mask, content reveal gate, collapse width freeze.

Locks the full Task-2 fixes for media expand/collapse hand-feel:
1. Input mask follows animated painted geometry (not settled target).
2. Expanded media/timer content waits for geometry reveal progress.
3. Compact media is held during early expand (no blank mid-morph frame).
4. Collapse freezes resting_media width until settle (no remeasure retarget).
5. No parallel animation owner / staged-swap regression.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
MOTION = SHELL / "components" / "DynamicIslandMotion.js"
OVERLAY = SHELL / "components" / "DynamicIslandOverlay.qml"
CONTENT = SHELL / "components" / "DynamicIslandContent.qml"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class DynamicIslandExpandMorphTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.motion = _read(MOTION)
        cls.overlay = _read(OVERLAY)
        cls.content = _read(CONTENT)

    def test_reveal_tokens_and_helper(self) -> None:
        self.assertIn("var v2ExpandedContentRevealThreshold = 0.55", self.motion)
        self.assertIn("var v2ExpandedContentRevealMinDeltaPx = 12", self.motion)
        self.assertIn("function expandedContentRevealAllowed", self.motion)
        body = re.search(
            r"function\s+expandedContentRevealAllowed\s*\([^)]*\)\s*\{([\s\S]*?)\n\}",
            self.motion,
        )
        self.assertIsNotNone(body)
        text = body.group(1)
        self.assertIn("reducedMotion", text)
        self.assertIn("v2ExpandedContentRevealThreshold", text)
        self.assertIn("v2ExpandedContentRevealMinDeltaPx", text)

    def test_mask_uses_animated_not_target(self) -> None:
        mask = re.search(r"mask:\s*Region\s*\{([\s\S]*?)\n    \}", self.overlay)
        self.assertIsNotNone(mask)
        body = mask.group(1)
        self.assertIn("islandAnimatedWidth", body)
        self.assertIn("islandAnimatedHeight", body)
        self.assertIn("islandAnimatedRadius", body)
        self.assertNotIn("capsuleTargetWidth", body)
        self.assertNotIn("capsuleTargetHeight", body)
        self.assertNotIn("capsuleTargetLeft", body)
        # Still top-anchored.
        self.assertIn("capsuleTargetTop", body)

    def test_media_content_gated_by_geometry_reveal(self) -> None:
        self.assertIn("geometryAllowsExpandedContent", self.overlay)
        self.assertIn("geometryRevealProgress", self.overlay)
        self.assertIn("expandedContentRevealAllowed", self.overlay)
        # mediaContentVisible requires geometry gate, not state alone.
        self.assertRegex(
            self.overlay,
            r"mediaContentVisible:\s*effectiveContentState\s*===\s*\"expanded_media\"[\s\S]*?"
            r"geometryAllowsExpandedContent",
        )
        self.assertIn("mediaExpandHoldCompact", self.overlay)
        self.assertIn("mediaExpandHoldCompact", self.content)
        # Compact stays active while expand hold is on.
        self.assertIn("root.mediaExpandHoldCompact", self.content)
        self.assertIn("mediaExpandedContentVisible: root.mediaContentVisible", self.overlay)

    def test_hold_compact_actually_paints(self) -> None:
        # Critical: mediaExpandHoldCompact must keep compact chrome *visible*,
        # not only "active". compactContentVisible must OR the hold, and the
        # compact media opacity expression must honor hold as a paint path.
        self.assertRegex(
            self.overlay,
            r"compactContentVisible:\s*\(compactResting\s*\|\|\s*root\.mediaExpandHoldCompact\)\s*&&\s*capsuleShown",
        )
        self.assertIn("mediaExpandHoldCompact:", self.overlay)
        # Content opacity must not require compactContentVisible alone.
        compact_opacity = re.search(
            r"DynamicIslandCompactMediaView\s*\{[\s\S]*?opacity:\s*([^\n]+(?:\n\s+[^\n]+){0,4})",
            self.content,
        )
        self.assertIsNotNone(compact_opacity)
        expr = compact_opacity.group(1)
        self.assertIn("mediaExpandHoldCompact", expr)
        self.assertIn("compactMediaActive", expr)

    def test_timer_expanded_also_geometry_gated(self) -> None:
        self.assertIn("timerExpandedContentVisible", self.overlay)
        self.assertIn("timerExpandedContentVisible: root.timerExpandedContentVisible", self.overlay)
        self.assertIn("timerExpandedContentVisible", self.content)
        self.assertIn(
            "readonly property bool timerExpanded: islandState === \"expanded_timer\"",
            self.content,
        )
        self.assertIn("root.timerExpandedContentVisible", self.content)

    def test_collapse_width_freeze(self) -> None:
        self.assertIn("collapseWidthFrozen", self.overlay)
        self.assertIn("collapseFrozenMediaWidth", self.overlay)
        self.assertIn("function armCollapseWidthFreeze", self.overlay)
        self.assertIn("function clearCollapseWidthFreeze", self.overlay)
        self.assertIn("lastCompactMediaWidth", self.overlay)
        # requestedCapsuleWidth honors freeze for resting_media.
        req = re.search(
            r"readonly property int requestedCapsuleWidth:\s*\{([\s\S]*?)\n    \}",
            self.overlay,
        )
        self.assertIsNotNone(req)
        self.assertIn("collapseWidthFrozen", req.group(1))
        self.assertIn("collapseFrozenMediaWidth", req.group(1))
        self.assertIn("resting_media", req.group(1))

    def test_morph_base_latched_on_retarget(self) -> None:
        self.assertIn("morphBaseHeight", self.overlay)
        self.assertIn("morphBaseWidth", self.overlay)
        # retargetHeightDriver latches base before starting spring/ease.
        height = re.search(r"function retargetHeightDriver\(\)\s*\{([\s\S]*?)\n    \}", self.overlay)
        self.assertIsNotNone(height)
        self.assertIn("morphBaseHeight", height.group(1))
        width = re.search(r"function retargetWidthDriver\(\)\s*\{([\s\S]*?)\n    \}", self.overlay)
        self.assertIsNotNone(width)
        self.assertIn("morphBaseWidth", width.group(1))

    def test_no_staged_swap_regression(self) -> None:
        self.assertNotIn("id: contentSwap", self.overlay)
        self.assertNotIn("contentLayerOpacity", self.overlay)
        self.assertNotIn("pendingContentState", self.overlay)
        # Glass region still quantized / settled — R08 path intact.
        self.assertIn("protocolGeometrySettled", self.overlay)
        self.assertIn("quantizeProtocolFloor", self.overlay)
        self.assertEqual(self.overlay.count("SpringAnimation {"), 2)

    def test_no_parallel_geometry_owner(self) -> None:
        # Drivers remain on Overlay root; no second morph service.
        self.assertIn("islandDriverWidth", self.overlay)
        self.assertIn("islandDriverHeight", self.overlay)
        self.assertNotIn("IslandMorphController", self.overlay)
        self.assertNotIn("IslandMorphController", self.content)
        # Content does not own geometry springs.
        self.assertNotIn("SpringAnimation", self.content)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
