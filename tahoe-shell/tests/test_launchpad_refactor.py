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
        # Intent paging via Motion.launchpadResolvePage (not 50% Math.round only).
        self.assertIn("Motion.launchpadResolvePage", text)
        self.assertIn("pagePeakVelocity", text)

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


class LaunchpadPageDirectionTests(unittest.TestCase):
    """macOS/iOS LTR: left = next, right = prev. First page right-drag stays."""

    def _resolve(self):
        # Minimal eval of Motion.launchpadResolvePage via regex + exec of body.
        text = MOTION.read_text(encoding="utf-8")
        # Pull the numeric thresholds used by the resolver.
        ratio = float(re.search(r"var launchpadPageCommitRatio = ([0-9.]+);", text).group(1))
        min_px = float(re.search(r"var launchpadPageCommitMinPx = ([0-9.]+);", text).group(1))
        flick_v = float(re.search(r"var launchpadPageFlickVelocity = ([0-9.]+);", text).group(1))

        def resolve(start_page, page_count, delta, velocity, page_width):
            n = max(1, int(page_count))
            page = max(0, min(n - 1, int(round(start_page))))
            w = max(1.0, float(page_width))
            d = float(delta)
            v = float(velocity)
            commit = max(min_px, w * ratio)
            if abs(v) >= flick_v:
                nxt = page + 1 if v < 0 else page - 1
            elif d > commit:
                nxt = page + 1
            elif d < -commit:
                nxt = page - 1
            else:
                nxt = page
            return max(0, min(n - 1, nxt))

        return resolve

    def test_first_page_left_goes_next_right_stays(self) -> None:
        resolve = self._resolve()
        # contentX up (finger left) → next
        self.assertEqual(resolve(0, 3, 80, 0, 800), 1)
        # contentX down (finger right) → prev but clamped to 0
        self.assertEqual(resolve(0, 3, -80, 0, 800), 0)
        # flick left (vel < 0) → next
        self.assertEqual(resolve(0, 3, 5, -200, 800), 1)
        # flick right (vel > 0) → stay on first
        self.assertEqual(resolve(0, 3, -5, 200, 800), 0)

    def test_middle_page_both_directions(self) -> None:
        resolve = self._resolve()
        self.assertEqual(resolve(1, 3, 80, 0, 800), 2)
        self.assertEqual(resolve(1, 3, -80, 0, 800), 0)

    def test_last_page_right_goes_prev_left_stays(self) -> None:
        resolve = self._resolve()
        self.assertEqual(resolve(2, 3, -80, 0, 800), 1)
        self.assertEqual(resolve(2, 3, 80, 0, 800), 2)


if __name__ == "__main__":
    unittest.main()
