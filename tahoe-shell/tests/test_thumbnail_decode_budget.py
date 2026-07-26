"""P01: window thumbnail / static wallpaper Image decode budgets.

Contract:
- Window screenshot Images declare sourceSize at display × screen scale.
- cache stays enabled (generation query on thumbnailSource handles bust).
- cache: false is not reintroduced on those screenshot Images.
- Static wallpaper decodes via panelImageDecodeSize / staticWallpaperDecodeSize.
- Spotlight row/preview icons keep an explicit sourceSize budget.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]



class ThumbnailDecodeBudgetTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def _assert_thumbnail_image_budget(self, relative: str, image_id: str = "thumbnailImage") -> str:
        text = self.read(relative)
        # Prefer a tight extract around the thumbnail Image id.
        start = text.find(f"id: {image_id}")
        self.assertGreaterEqual(start, 0, relative)
        # Walk backward to the Image { opener.
        image_start = text.rfind("Image {", 0, start)
        self.assertGreaterEqual(image_start, 0, relative)
        # End at the matching close roughly: next "WindowPreviewFallback" or 40 lines.
        window = text[image_start : image_start + 1200]
        block = window.split("WindowPreviewFallback", 1)[0]
        self.assertIn("sourceSize:", block, relative)
        self.assertIn("thumbnailSourceSize", block, relative)
        self.assertIn("cache: true", block, relative)
        self.assertNotIn("cache: false", block, relative)
        return text

    def test_window_overview_thumbnail_decodes_at_display_scale(self) -> None:
        text = self._assert_thumbnail_image_budget("components/WindowOverview.qml")
        self.assertIn("function thumbnailSourceSize(", text)
        self.assertIn("readonly property real screenScale:", text)
        self.assertIn("thumbnailCaptureWidth", text)
        self.assertIn("root.thumbnailCaptureWidth", text)
        # No hard-coded full-res capture leftovers without scale.
        self.assertNotIn('requestThumbnail(window, 480, 300, "window-overview"', text)

    def test_task_switcher_thumbnail_decodes_at_display_scale(self) -> None:
        text = self._assert_thumbnail_image_budget("components/TaskSwitcher.qml")
        self.assertIn("function thumbnailSourceSize(", text)
        self.assertIn("thumbnailCaptureWidth", text)
        self.assertNotIn('requestThumbnail(window, 360, 220, "task-switcher"', text)

    def test_dock_minimized_thumbnail_decodes_at_display_scale(self) -> None:
        text = self._assert_thumbnail_image_budget("components/DockMinimizedWindow.qml")
        self.assertIn("function thumbnailSourceSize(", text)
        self.assertIn("thumbnailCaptureWidth", text)
        self.assertIn("root.thumbnailCaptureWidth", text)
        self.assertNotIn("root.thumbnailMaxWidth,\n            root.thumbnailMaxHeight,", text)

    def test_wallpaper_static_image_has_panel_decode_budget(self) -> None:
        text = self.read("components/Wallpaper.qml")
        self.assertIn("function panelImageDecodeSize(", text)
        self.assertIn("function staticWallpaperDecodeSize(", text)
        self.assertIn("function coverCaptureDecodeSize(", text)
        self.assertIn("sourceSize: root.staticWallpaperDecodeSize()", text)
        self.assertIn("sourceSize: root.coverCaptureDecodeSize()", text)
        # staticImage block must not load full-res without sourceSize.
        start = text.find("id: staticImage")
        self.assertGreaterEqual(start, 0)
        block = text[text.rfind("Image {", 0, start) : start + 900]
        self.assertIn("sourceSize: root.staticWallpaperDecodeSize()", block)
        self.assertIn("cache: true", block)

    def test_spotlight_icons_keep_source_size_budget(self) -> None:
        text = self.read("components/Spotlight.qml")
        # No window-screenshot path in Spotlight; icons must still budget sourceSize.
        self.assertGreaterEqual(text.count("sourceSize.width:"), 2)
        self.assertGreaterEqual(text.count("sourceSize.height:"), 2)
        self.assertIn("devicePixelRatio", text)

    def test_no_window_screenshot_image_reintroduces_cache_false(self) -> None:
        offenders: list[str] = []
        for relative in (
            "components/WindowOverview.qml",
            "components/TaskSwitcher.qml",
            "components/DockMinimizedWindow.qml",
        ):
            text = self.read(relative)
            start = text.find("id: thumbnailImage")
            self.assertGreaterEqual(start, 0, relative)
            block = text[text.rfind("Image {", 0, start) : start + 900]
            if "cache: false" in block:
                offenders.append(relative)
        self.assertEqual(offenders, [])


if __name__ == "__main__":
    unittest.main()
