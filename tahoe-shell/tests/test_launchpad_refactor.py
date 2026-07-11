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
        self.assertIn("MaterialBackdrop", text)
        self.assertIn("compositorLayerAnimations: false", text)
        self.assertIn("pageFlick", text)
        self.assertIn("snapToNearestPage", text)
        self.assertIn("finishPageGesture", text)
        self.assertIn("pageDragStartPage", text)
        self.assertIn("moveSelection", text)
        self.assertIn("Keys.onLeftPressed", text)
        self.assertIn("gridEnter", text)
        self.assertIn("playGridEnter", text)
        # Custom inverted drag (not native Flickable interactive).
        self.assertIn("interactive: false", text)
        self.assertIn("pageDragArea", text)
        self.assertIn("Motion.launchpadResolvePage", text)
        self.assertIn("contentXForPage", text)
        self.assertIn("pageFromContentX", text)
        # Standard LTR strip (not reversed layout).
        self.assertIn("logicalPage: pageDelegate.index", text)
        self.assertNotIn("pageCount - 1 - pageDelegate.index", text)

    def test_stagger_budget_tokens(self) -> None:
        text = MOTION.read_text(encoding="utf-8")
        self.assertIn("var launchpadWallpaperScale = 1.06;", text)
        self.assertIn("var launchpadWallpaperDim = 0.25;", text)
        self.assertIn("var launchpadIconEnterMs = 280;", text)
        self.assertIn("var launchpadPageSnapMs = 340;", text)
        self.assertIn("var launchpadPageCommitRatio = 0.10;", text)
        self.assertIn("var launchpadPageFlickVelocity = 120;", text)
        self.assertIn("function launchpadStaggerDelay", text)
        self.assertIn("function launchpadPageSnapDuration", text)
        self.assertIn("function launchpadResolvePage", text)
        lp = LAUNCHPAD.read_text(encoding="utf-8")
        self.assertIn("pagePeakFingerVelocity", lp)
        self.assertIn("clampContentXWithRubber", lp)
        self.assertIn("launchAtPoint", lp)

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
        self.assertIn("Motion.pressScaleFor", text)

    def test_unified_enter_not_per_icon_cascade(self) -> None:
        text = LAUNCHPAD.read_text(encoding="utf-8")
        self.assertIn("gridEnterAnim", text)
        self.assertIn("Motion.launchpadIconEnterScaleFrom", text)
        self.assertNotIn("staggerTimer", text)
        self.assertNotIn("cellScaleSpring", text)
        self.assertIn("Motion.pressScaleFor", text)

    def test_inverted_drag_maps_finger_right_to_content_increase(self) -> None:
        text = LAUNCHPAD.read_text(encoding="utf-8")
        # fingerTravel positive → contentX = start + fingerTravel
        self.assertIn("root.pageDragStartContentX + fingerTravel", text)
        self.assertIn("Motion.emphasizedDecel", text)


class LaunchpadPageDirectionTests(unittest.TestCase):
    """Finger right = next, finger left = prev. content slides opposite the finger."""

    def _resolve(self):
        text = MOTION.read_text(encoding="utf-8")
        ratio = float(re.search(r"var launchpadPageCommitRatio = ([0-9.]+);", text).group(1))
        min_px = float(re.search(r"var launchpadPageCommitMinPx = ([0-9.]+);", text).group(1))
        flick_v = float(re.search(r"var launchpadPageFlickVelocity = ([0-9.]+);", text).group(1))

        def resolve(start_page, page_count, drag_delta, velocity, page_width):
            n = max(1, int(page_count))
            page = max(0, min(n - 1, int(round(start_page))))
            w = max(1.0, float(page_width))
            d = float(drag_delta)
            v = float(velocity)
            commit = max(min_px, w * ratio)
            # Finger-space: right positive → next.
            if abs(v) >= flick_v:
                nxt = page + 1 if v > 0 else page - 1
            elif d > commit:
                nxt = page + 1
            elif d < -commit:
                nxt = page - 1
            else:
                nxt = page
            return max(0, min(n - 1, nxt))

        return resolve

    def test_first_page_finger_right_goes_next(self) -> None:
        resolve = self._resolve()
        # commit threshold at 800px width = max(36, 80) = 80; need strictly greater.
        self.assertEqual(resolve(0, 3, 100, 0, 800), 1)
        self.assertEqual(resolve(0, 3, -100, 0, 800), 0)
        self.assertEqual(resolve(0, 3, 5, 200, 800), 1)
        self.assertEqual(resolve(0, 3, -5, -200, 800), 0)

    def test_middle_page_both_directions(self) -> None:
        resolve = self._resolve()
        self.assertEqual(resolve(1, 3, 100, 0, 800), 2)
        self.assertEqual(resolve(1, 3, -100, 0, 800), 0)

    def test_last_page_finger_left_goes_prev(self) -> None:
        resolve = self._resolve()
        self.assertEqual(resolve(2, 3, -100, 0, 800), 1)
        self.assertEqual(resolve(2, 3, 100, 0, 800), 2)


if __name__ == "__main__":
    unittest.main()
