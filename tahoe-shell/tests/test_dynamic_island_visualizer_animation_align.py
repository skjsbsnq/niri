#!/usr/bin/env python3
"""T17 supersedes Task 21 fake visualizer: expanded media must not animate bars.

Historical Task 21 aligned a sine visualizer timer to motion tokens and gated
it on activeForScreen. T17 deletes the fake spectrum entirely; this file now
locks that product decision and keeps multi-screen media visibility gates.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
MEDIA_VIEW = SHELL_ROOT / "components" / "DynamicIslandMediaView.qml"
MOTION = SHELL_ROOT / "components" / "DynamicIslandMotion.js"
CONTENT = SHELL_ROOT / "components" / "DynamicIslandContent.qml"
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"


class DynamicIslandNoFakeVisualizerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.media = MEDIA_VIEW.read_text(encoding="utf-8")
        cls.motion = MOTION.read_text(encoding="utf-8")
        cls.content = CONTENT.read_text(encoding="utf-8")
        cls.overlay = OVERLAY.read_text(encoding="utf-8")

    def test_no_visualizer_timer_or_sine(self) -> None:
        code = re.sub(r"//[^\n]*", "", self.media)
        self.assertNotIn("visualizerTimer", code)
        self.assertNotIn("visualizerPhase", code)
        self.assertNotIn("visualizerLevel", code)
        self.assertNotIn("pausedLevel", code)
        self.assertNotIn("visualizerBox", code)
        self.assertNotIn("Math.sin", code)
        self.assertNotIn("Timer {", code)
        self.assertNotIn("Canvas", code)

    def test_expanded_media_still_uses_tahoesymbol_controls(self) -> None:
        self.assertIn("TahoeSymbol", self.media)
        self.assertIn("MediaControlButton", self.media)
        self.assertIn("artSizeExpanded: 64", self.media)

    def test_media_content_gated_by_active_for_screen(self) -> None:
        # Unified media scene: owner + (expanded_media | resting_media) + capsule.
        self.assertIn("mediaContentVisible", self.overlay)
        self.assertIn("activeForScreen", self.overlay)
        self.assertIn("capsuleShown", self.overlay)
        self.assertIn("resting_media", self.overlay)
        self.assertIn("expanded_media", self.overlay)
        self.assertIn("mediaExpandProgress", self.overlay)
        self.assertNotRegex(
            self.overlay,
            r"property\s+bool\s+(mediaVisibleForScreen|visualizerScreenActive|secondMediaVisible)\b",
        )

    def test_settings_still_wired_for_reduced_motion(self) -> None:
        self.assertIn("property var settingsService", self.media)
        self.assertIn("Motion.reducedMotion", self.media)
        self.assertIn("settingsService: root.settingsService", self.content)
        self.assertIn("settingsService: root.settingsService", self.overlay)

    def test_motion_tokens_may_remain_unused_by_media(self) -> None:
        # Tokens can stay in Motion.js for history/T19 cleanup; media must not
        # reintroduce a production consumer.
        self.assertNotIn("visualizerUpdateMs", self.media)
        self.assertNotIn("visualizerPlayingDuration", self.media)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
