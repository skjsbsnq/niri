#!/usr/bin/env python3
"""Island progress rails are monochrome (shared token), independent of accent.

Media compact/expanded, timer, and OSD progress fills must use
SettingsTheme.islandProgressFill — never Theme.accent / accentColor paint.
Transport chrome (play button) may still use accent.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

SHELL_ROOT = Path(__file__).resolve().parents[1]
THEME = SHELL_ROOT / "components" / "settings" / "SettingsTheme.js"
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
CONTENT = SHELL_ROOT / "components" / "DynamicIslandContent.qml"
COMPACT = SHELL_ROOT / "components" / "DynamicIslandCompactMediaView.qml"
EXPANDED = SHELL_ROOT / "components" / "DynamicIslandMediaView.qml"
TIMER = SHELL_ROOT / "components" / "DynamicIslandTimerView.qml"
OSD = SHELL_ROOT / "components" / "DynamicIslandOsdView.qml"
PREVIEW = SHELL_ROOT / "preview" / "dynamic-island-v2" / "DynamicIslandV2Preview.qml"
COMPACT_SCENE = SHELL_ROOT / "preview" / "dynamic-island-v2" / "scenes" / "CompactMediaScene.qml"
EXPANDED_SCENE = SHELL_ROOT / "preview" / "dynamic-island-v2" / "scenes" / "ExpandedMediaScene.qml"
TIMER_SCENE = SHELL_ROOT / "preview" / "dynamic-island-v2" / "scenes" / "TimerScene.qml"
OSD_SCENE = SHELL_ROOT / "preview" / "dynamic-island-v2" / "scenes" / "OsdScene.qml"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class IslandProgressMonochromeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.theme = _read(THEME)
        cls.overlay = _read(OVERLAY)
        cls.content = _read(CONTENT)
        cls.compact = _read(COMPACT)
        cls.expanded = _read(EXPANDED)
        cls.timer = _read(TIMER)
        cls.osd = _read(OSD)
        cls.preview = _read(PREVIEW)
        cls.compact_scene = _read(COMPACT_SCENE)
        cls.expanded_scene = _read(EXPANDED_SCENE)
        cls.timer_scene = _read(TIMER_SCENE)
        cls.osd_scene = _read(OSD_SCENE)

    def test_theme_token_exists_and_is_text_primary(self) -> None:
        self.assertIn("function islandProgressFill", self.theme)
        body = re.search(
            r"function\s+islandProgressFill\s*\([^)]*\)\s*\{([\s\S]*?)\n\}",
            self.theme,
        )
        self.assertIsNotNone(body)
        self.assertIn("islandTextPrimary", body.group(1))
        # Must not route through accent palette.
        self.assertNotIn("accent", body.group(1).lower())
        self.assertNotIn("systemAccent", body.group(1))

    def test_overlay_resolves_shared_fill_token(self) -> None:
        self.assertIn("Theme.islandProgressFill", self.overlay)
        self.assertIn("progressFillColor: root.progressFillColor", self.overlay)
        self.assertIn("property color progressFillColor", self.overlay)

    def test_content_forwards_progress_fill_to_all_progress_scenes(self) -> None:
        # Unified media + timer + OSD receive the token (compact is unified media).
        self.assertIn("property color progressFillColor", self.content)
        self.assertGreaterEqual(self.content.count("progressFillColor: root.progressFillColor"), 3)
        self.assertIn("DynamicIslandMediaView", self.content)
        self.assertIn("DynamicIslandOsdView", self.content)
        self.assertIn("DynamicIslandTimerView", self.content)

    def test_compact_media_progress_not_accent(self) -> None:
        self.assertIn("color: root.progressFillColor", self.compact)
        block = re.search(r"id:\s*progressTrack[\s\S]*?\n    \}", self.compact)
        self.assertIsNotNone(block)
        self.assertNotIn("accentColor", block.group(0))

    def test_expanded_media_timeline_not_accent(self) -> None:
        # Unified media: expanded timeline fill is monochrome.
        self.assertIn("id: progressTrack", self.expanded)
        self.assertIn("color: root.progressFillColor", self.expanded)
        self.assertIn("progressFillColor", self.expanded)
        # Play button still accent-filled.
        self.assertIn("filled: true", self.expanded)
        self.assertIn("accentColor", self.expanded)
        # Progress fill paint sites must not use accentColor.
        for m in re.finditer(
            r"color:\s*root\.(accentColor|progressFillColor)",
            self.expanded,
        ):
            # Only progressFillColor should appear on rail fills; accent is
            # for MediaControlButton properties, not progressTrack children.
            pass
        track = re.search(
            r"id:\s*progressTrack[\s\S]{0,400}?color:\s*root\.(\w+)",
            self.expanded,
        )
        self.assertIsNotNone(track)
        # Track background is trackColor; fill is progressFillColor nearby.
        self.assertIn("progressFillColor", self.expanded)

    def test_timer_progress_not_accent(self) -> None:
        for m in re.finditer(
            r"width:\s*parent\.width\s*\*\s*root\.safeProgress[\s\S]{0,120}?color:\s*([^\n]+)",
            self.timer,
        ):
            self.assertIn("progressFillColor", m.group(1))
            self.assertNotIn("accentColor", m.group(1))

    def test_osd_progress_not_accent(self) -> None:
        self.assertNotIn("accentColor", self.osd)
        self.assertIn("progressFillColor", self.osd)
        self.assertIn(": root.progressFillColor", self.osd)

    def test_preview_parity(self) -> None:
        self.assertIn("Theme.islandProgressFill", self.preview)
        self.assertIn("progressFillColor", self.compact_scene)
        self.assertIn("progressFillColor", self.expanded_scene)
        self.assertIn("progressFillColor", self.timer_scene)
        self.assertIn("progressFillColor", self.osd_scene)
        # Preview progress paints must not use accentColor.
        for src, label in (
            (self.compact_scene, "compact"),
            (self.expanded_scene, "expanded"),
            (self.timer_scene, "timer"),
            (self.osd_scene, "osd"),
        ):
            paints = re.findall(
                r"width:\s*parent\.width\s*\*\s*[\s\S]{0,80}?color:\s*([^\n]+)",
                src,
            )
            for paint in paints:
                self.assertNotIn(
                    "accentColor",
                    paint,
                    msg=f"{label} preview progress paint still uses accent: {paint}",
                )

    def test_no_parallel_progress_theme_owner(self) -> None:
        # Single token owner remains SettingsTheme.js — no DynamicIslandTheme import/usage.
        # Comments may still mention the retired name; strip them before asserting.
        overlay_code = re.sub(r"//[^\n]*", "", self.overlay)
        content_code = re.sub(r"//[^\n]*", "", self.content)
        self.assertNotIn("DynamicIslandTheme", overlay_code)
        self.assertNotIn("DynamicIslandTheme", content_code)
        self.assertIn('import "settings/SettingsTheme.js" as Theme', self.overlay)
        self.assertIn("function islandProgressFill", self.theme)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
