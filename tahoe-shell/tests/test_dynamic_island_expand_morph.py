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

    def test_media_content_uses_continuous_expand_progress(self) -> None:
        # Unified media scene for resting_media + expanded_media on owner.
        self.assertIn("mediaExpandProgress", self.overlay)
        self.assertIn("mediaExpandProgress", self.content)
        self.assertIn("expandProgress", self.content)
        self.assertIn("resting_media", self.overlay)
        self.assertIn("expanded_media", self.overlay)
        self.assertIn("mediaExpandedContentVisible: root.mediaContentVisible", self.overlay)
        # MediaView morphs art/timeline/controls from expandProgress.
        media = (SHELL / "components" / "DynamicIslandMediaView.qml").read_text(encoding="utf-8")
        self.assertIn("property real expandProgress", media)
        self.assertIn("pArt", media)
        self.assertIn("pTimeline", media)
        self.assertIn("pControls", media)
        self.assertIn("artSizeCompact", media)
        self.assertIn("artSizeExpanded", media)

    def test_unified_media_scene_not_dual_crossfade(self) -> None:
        # Production Content must not host a second CompactMediaView for morph.
        self.assertNotRegex(self.content, r"DynamicIslandCompactMediaView\s*\{")
        self.assertIn("DynamicIslandMediaView", self.content)
        self.assertIn("resolvedMediaExpandProgress", self.content)
        # Timer still uses geometry reveal gate (not continuous media morph).
        self.assertIn("geometryAllowsExpandedContent", self.overlay)
        self.assertIn("timerExpandedContentVisible", self.overlay)

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
