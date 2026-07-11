from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
LAUNCHPAD = SHELL_ROOT / "components" / "Launchpad.qml"
WALLPAPER = SHELL_ROOT / "components" / "Wallpaper.qml"
MOTION = SHELL_ROOT / "components" / "Motion.js"
SHELL_QML = SHELL_ROOT / "shell.qml"


class LaunchpadRefactorTests(unittest.TestCase):
    def test_fullscreen_no_category_chips(self) -> None:
        text = LAUNCHPAD.read_text(encoding="utf-8")
        self.assertNotIn("categoryStrip", text)
        self.assertNotIn("categories:", text)
        self.assertNotIn('category: "all"', text)
        # Full-screen backdrop material.
        self.assertIn("MaterialBackdrop", text)
        self.assertIn("compositorLayerAnimations: false", text)
        # Paging + dots + keyboard.
        self.assertIn("pageFlick", text)
        self.assertIn("snapToNearestPage", text)
        self.assertIn("finishPageGesture", text)
        self.assertIn("pageDragStartPage", text)
        self.assertIn("moveSelection", text)
        self.assertIn("Keys.onLeftPressed", text)
        # Unified grid enter (no per-icon opacity cascade).
        self.assertIn("gridEnter", text)
        self.assertIn("playGridEnter", text)
        self.assertIn("DragAndOvershootBounds", text)
        # Intent paging: short drag/flick commits (not 50% Math.round only).
        self.assertIn("launchpadPageCommitRatio", text)
        self.assertIn("launchpadPageFlickVelocity", text)

    def test_stagger_budget_tokens(self) -> None:
        text = MOTION.read_text(encoding="utf-8")
        self.assertIn("var launchpadWallpaperScale = 1.06;", text)
        self.assertIn("var launchpadWallpaperDim = 0.25;", text)
        self.assertIn("var launchpadIconEnterMs = 280;", text)
        self.assertIn("var launchpadPageSnapMs = 240;", text)
        self.assertIn("var launchpadPageCommitRatio = 0.08;", text)
        self.assertIn("var launchpadPageFlickVelocity = 80;", text)
        self.assertIn("pagePeakVelocity", LAUNCHPAD.read_text(encoding="utf-8"))
        self.assertIn("onDraggingChanged", LAUNCHPAD.read_text(encoding="utf-8"))
        self.assertIn("cancelFlick", LAUNCHPAD.read_text(encoding="utf-8"))
        self.assertIn("var launchpadGridCols = 7;", text)
        self.assertIn("var launchpadGridRows = 5;", text)
        self.assertIn("function launchpadStaggerDelay", text)
        self.assertIn("function launchpadPageSnapDuration", text)

    def test_wallpaper_zoom_driven_by_launchpad(self) -> None:
        wp = WALLPAPER.read_text(encoding="utf-8")
        self.assertIn("property bool launchpadOpen", wp)
        self.assertIn("Motion.launchpadWallpaperScale", wp)
        self.assertIn("Motion.launchpadWallpaperDim", wp)
        shell = SHELL_QML.read_text(encoding="utf-8")
        block = re.search(r"Wallpaper \{.*?\}", shell, re.S)
        self.assertIsNotNone(block)
        assert block
        self.assertIn("launchpadOpen: shell.launchpadOpen", block.group(0))

    def test_search_filter_still_uses_apps_service(self) -> None:
        text = LAUNCHPAD.read_text(encoding="utf-8")
        self.assertIn("filteredLaunchpadApps(root.query, \"all\")", text)
        self.assertIn("launchApp", text)
        # Press feedback retained.
        self.assertIn("Motion.pressScaleFor", text)

    def test_unified_enter_not_per_icon_cascade(self) -> None:
        text = LAUNCHPAD.read_text(encoding="utf-8")
        self.assertIn("gridEnterAnim", text)
        self.assertIn("Motion.launchpadIconEnterScaleFrom", text)
        # Icons stay opacity 1; enter is on the page surface.
        self.assertNotIn("staggerTimer", text)
        self.assertNotIn("cellScaleSpring", text)
        # Press feedback retained on cells.
        self.assertIn("Motion.pressScaleFor", text)


if __name__ == "__main__":
    unittest.main()
