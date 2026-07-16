#!/usr/bin/env python3
"""T19: V2 motion token convergence and reduced mode."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
MOTION = SHELL / "components" / "DynamicIslandMotion.js"
OVERLAY = SHELL / "components" / "DynamicIslandOverlay.qml"
CONTENT = SHELL / "components" / "DynamicIslandContent.qml"
MEDIA = SHELL / "components" / "DynamicIslandMediaView.qml"
COMPONENTS = SHELL / "components"


def _read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


class DynamicIslandV2MotionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.motion = _read(MOTION)
        cls.overlay = _read(OVERLAY)
        cls.content = _read(CONTENT)
        cls.media = _read(MEDIA)

    def test_geometry_tokens_in_v2_band(self) -> None:
        self.assertIn("var v2CompactToTransientMs = 240", self.motion)
        self.assertIn("var v2CompactToExpandedMs = 280", self.motion)
        self.assertIn("var v2ExpandedToCompactMs = 240", self.motion)
        self.assertIn("var v2ContentExitMs = 110", self.motion)
        self.assertIn("var v2ContentEnterMs = 170", self.motion)
        self.assertIn("var v2ContentMaxTravelPx = 6", self.motion)
        self.assertIn("var v2ReducedGeometryMs = 80", self.motion)
        self.assertIn("var v2ReducedContentMs = 80", self.motion)
        # Legacy 380 morph and whole-content scale 0.9 removed.
        self.assertNotIn("var overlayMorphDuration = 380", self.motion)
        self.assertNotIn("overlayMorphDuration", self.motion)
        self.assertNotIn("overlayMorphEasing", self.motion)
        self.assertNotIn("overlayContentDuration", self.motion)
        self.assertNotIn("overlayExpandedExitFadeMs", self.motion)
        self.assertNotIn("overlayExpandedEnterFadeMs", self.motion)
        self.assertNotIn("overlayContentEnterScale = 0.9", self.motion)
        self.assertNotIn("overlayExpandedExitHoldMs", self.motion)
        self.assertNotIn("visualizerUpdateMs", self.motion)
        self.assertNotIn("overlayContentSpring", self.motion)

    def test_helpers_for_reduced_motion(self) -> None:
        self.assertIn("function geometryDurationMs", self.motion)
        self.assertIn("function contentExitMs", self.motion)
        self.assertIn("function contentEnterMs", self.motion)
        self.assertIn("function contentTravelPx", self.motion)
        self.assertIn("Motion.reducedMotion", self.motion)

    def test_overlay_geometry_uses_v2_not_legacy_380(self) -> None:
        self.assertIn("geometryDurationMs", self.overlay)
        self.assertIn("geometryMorphMsRoot", self.overlay)
        self.assertIn("geometryMorphKind", self.overlay)
        # No SpringAnimation instances on glass geometry (comments may mention ban).
        self.assertEqual(self.overlay.count("SpringAnimation {"), 0)
        self.assertIn("scale: 1.0", self.overlay)

    def test_content_uses_v2_content_tokens(self) -> None:
        self.assertIn("contentEnterMs", self.content)
        self.assertIn("contentExitMs", self.content)
        self.assertIn("contentTravelPx", self.content)
        # No hardcoded 280/140 notification fades.
        self.assertNotIn("notificationFadeInDuration: 280", self.content)
        self.assertNotIn("notificationFadeOutDuration: 140", self.content)

    def test_overlay_coordinates_scene_swap_with_geometry(self) -> None:
        self.assertIn("id: contentSwap", self.overlay)
        self.assertIn('property: "contentLayerOpacity"', self.overlay)
        self.assertIn("contentExitMs(root.settingsService)", self.overlay)
        self.assertIn("root.contentState = root.pendingContentState", self.overlay)
        self.assertIn("root.renderedNotificationExpanded = root.pendingNotificationExpanded", self.overlay)
        self.assertIn("contentEnterMs(root.settingsService)", self.overlay)
        self.assertIn("sceneTransitionExternallyOwned", self.overlay)
        self.assertIn("sceneTransitionExternallyOwned", self.content)
        # OSD remains immediate instead of joining the staged scene swap.
        self.assertIn('if (next === "transient_osd")', self.overlay)
        # Same-presentation notification expand/collapse also uses the swap.
        self.assertIn("onContentNotificationExpandedChanged", self.overlay)
        self.assertIn("root.syncContentTransition(true)", self.overlay)

    def test_no_inline_out_cubic_in_island_scenes(self) -> None:
        offenders = []
        for path in COMPONENTS.glob("DynamicIsland*.qml"):
            text = path.read_text(encoding="utf-8")
            if "Easing.OutCubic" in text or "Easing.InOutQuad" in text:
                offenders.append(path.name)
        self.assertEqual(offenders, [])


    def test_geometry_axes_share_duration_owner(self) -> None:
        self.assertIn("geometryMorphMsRoot", self.overlay)
        self.assertIn("geometryDurationMs", self.overlay)
        self.assertIn("swipeWidthDuration", self.overlay)
        # Non-swipe width/x use geometryMorphMsRoot (not bare v2CompactToExpandedMs).
        self.assertIn("root.geometryMorphMsRoot", self.overlay)
        self.assertIn("geometryMorphMs: root.geometryMorphMsRoot", self.overlay)

    def test_workspace_travel_uses_content_travel_helper(self) -> None:
        self.assertIn("contentTravelPx", self.content)
        self.assertIn("contentExitMs", self.content)
        self.assertIn("contentEnterMs", self.content)
        # Workspace scene uses helper for travel magnitude.
        block = self.content
        self.assertIn("IslandMotion.contentTravelPx(root.settingsService)", block)

    def test_swipe_still_uses_target_settle(self) -> None:
        self.assertIn("swipeSettleDuration", self.overlay)
        self.assertIn("swipeSettling", self.overlay)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
