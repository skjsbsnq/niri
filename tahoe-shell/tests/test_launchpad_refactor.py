from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
LAUNCHPAD = SHELL_ROOT / "components" / "Launchpad.qml"
WALLPAPER = SHELL_ROOT / "components" / "Wallpaper.qml"
MOTION = SHELL_ROOT / "components" / "Motion.js"
SHELL_QML = SHELL_ROOT / "shell.qml"


def qml_block(text: str, marker: str, start: int = 0) -> str:
    marker_index = text.index(marker, start)
    brace_index = text.index("{", marker_index)
    depth = 0
    quote = ""
    escaped = False
    line_comment = False
    block_comment = False
    index = brace_index
    while index < len(text):
        char = text[index]
        following = text[index + 1] if index + 1 < len(text) else ""
        if line_comment:
            line_comment = char != "\n"
        elif block_comment:
            if char == "*" and following == "/":
                block_comment = False
                index += 1
        elif quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
        elif char == "/" and following == "/":
            line_comment = True
            index += 1
        elif char == "/" and following == "*":
            block_comment = True
            index += 1
        elif char in {'"', "'"}:
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace_index + 1 : index]
        index += 1
    raise AssertionError(f"unterminated QML block after {marker!r}")


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
        self.assertIn("StopAtBounds", text)
        # Intent paging: displacement commits first (not velocity yank-back).
        self.assertIn("launchpadPageCommitRatio", text)
        self.assertIn("launchpadPageFlickVelocity", text)
        self.assertIn("delta >= commitPx", text)

    def test_stagger_budget_tokens(self) -> None:
        text = MOTION.read_text(encoding="utf-8")
        self.assertIn("var launchpadWallpaperScale = 1.06;", text)
        self.assertIn("var launchpadWallpaperDim = 0.25;", text)
        self.assertIn("var launchpadIconEnterMs = 320;", text)
        self.assertIn("var launchpadPageSnapMs = 300;", text)
        self.assertIn("var launchpadPageCommitRatio = 0.10;", text)
        self.assertIn("var launchpadPageFlickVelocity = 220;", text)
        self.assertIn("var launchpadLayerEnterMs = 340;", text)
        self.assertIn("var launchpadLayerExitMs = 240;", text)
        self.assertIn("var launchpadLaunchPopMs = 200;", text)
        self.assertIn("function launchpadPageSnapDurationForDistance", text)
        self.assertIn("launchpadPageSnapDurationForDistance", LAUNCHPAD.read_text(encoding="utf-8"))
        lp = LAUNCHPAD.read_text(encoding="utf-8")
        self.assertIn("pagePeakVelocity", lp)
        self.assertIn("onDraggingChanged", lp)
        self.assertIn("cancelFlick", lp)
        self.assertIn("layerProgress", lp)
        self.assertIn("playLayerEnter", lp)
        self.assertIn("playLayerExit", lp)
        self.assertIn("launchPop", lp)
        self.assertIn("var launchpadGridCols = 7;", text)
        self.assertIn("var launchpadGridRows = 5;", text)
        self.assertIn("function launchpadStaggerDelay", text)
        self.assertIn("function launchpadPageSnapDuration", text)
        self.assertIn("function launchpadLayerEnterDuration", text)
        self.assertIn("function launchpadLaunchPopDuration", text)

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

    def test_query_filter_does_not_replay_full_grid_enter(self) -> None:
        text = LAUNCHPAD.read_text(encoding="utf-8")
        query_handler = qml_block(text, "onQueryChanged:")
        self.assertIn("pageFlick.contentX = 0", query_handler)
        self.assertNotIn("playGridEnter", query_handler)
        self.assertNotIn("gridEnter =", query_handler)
        self.assertNotRegex(query_handler, r"\bplay\w*Enter\s*\(")
        self.assertNotRegex(query_handler, r"\b(?:opacity|scale)\s*[:=]")

        open_handler = qml_block(text, "onOpenChanged:")
        self.assertIn("playGridEnter", open_handler)

    def test_app_icons_decode_asynchronously_with_placeholder(self) -> None:
        text = LAUNCHPAD.read_text(encoding="utf-8")
        icon_match = re.search(r"\bid:\s*appIcon\b", text)
        self.assertIsNotNone(icon_match)
        assert icon_match
        icon_id = icon_match.start()
        icon_start = text.rfind("Image {", 0, icon_id)
        self.assertGreaterEqual(icon_start, 0)
        icon_block = qml_block(text, "Image {", icon_start)
        self.assertIn("asynchronous: true", icon_block)
        self.assertNotIn("asynchronous: false", icon_block)
        self.assertIn("visible: status === Image.Ready", icon_block)
        slot_id = text.index("id: appIconSlot")
        slot_start = text.rfind("Item {", 0, slot_id)
        self.assertGreaterEqual(slot_start, 0)
        slot_block = qml_block(text, "Item {", slot_start)
        self.assertEqual(slot_block.count("visible: appIcon.status !== Image.Ready"), 2)

    def test_unified_enter_not_per_icon_cascade(self) -> None:
        text = LAUNCHPAD.read_text(encoding="utf-8")
        self.assertIn("gridEnterAnim", text)
        self.assertIn("Motion.launchpadIconEnterScaleFrom", text)
        # Icons stay opacity 1; enter is on the page surface.
        self.assertNotIn("staggerTimer", text)
        self.assertNotIn("cellScaleSpring", text)
        # Press feedback retained on cells.
        self.assertIn("Motion.pressScaleFor", text)

    def test_empty_area_and_launch_motion(self) -> None:
        text = LAUNCHPAD.read_text(encoding="utf-8")
        # Empty chrome (page + top/bottom strips) closes.
        self.assertIn("requestClose", text)
        self.assertGreaterEqual(text.count("root.requestClose()"), 3)
        # Launch pop before close.
        self.assertIn("launchCloseTimer", text)
        self.assertIn("launchpadLaunchPopScaleBoost", text)
        # Layer open/close uses explicit progress (not only Behavior on open).
        self.assertIn("layerProgressAnim", text)
        self.assertIn("playLayerExit", text)


if __name__ == "__main__":
    unittest.main()
