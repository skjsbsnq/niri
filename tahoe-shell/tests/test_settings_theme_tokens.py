"""T14: SettingsTheme semantic tokens + accent system governance."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME = ROOT / "components" / "settings" / "SettingsTheme.js"
DESKTOP = ROOT / "services" / "DesktopSettings.qml"
APPEARANCE = ROOT / "components" / "settings" / "pages" / "AppearancePage.qml"
FACES = [
    ROOT / "components" / "TopBar.qml",
    ROOT / "components" / "MenuRow.qml",
    ROOT / "components" / "ControlCenter.qml",
    ROOT / "components" / "LeftSidebar.qml",
]


class SettingsThemeTokenTests(unittest.TestCase):
    def test_semantic_exports_exist(self) -> None:
        text = THEME.read_text(encoding="utf-8")
        for name in (
            "label",
            "secondaryLabel",
            "tertiaryLabel",
            "separator",
            "systemBlue",
            "danger",
            "accent",
            "systemAccent",
            "normalizeAccentId",
            "accentIds",
            "cardFill",
            "controlTileFill",
        ):
            self.assertIn(f"function {name}(", text, name)
        # Still exports legacy settings names used by SettingsPanel.
        for name in ("textPrimary", "accentBlue", "panelFill", "categoryColor"):
            self.assertIn(f"function {name}(", text, name)

    def test_eight_macos_accents(self) -> None:
        text = THEME.read_text(encoding="utf-8")
        for accent in ("blue", "purple", "pink", "red", "orange", "yellow", "green", "graphite"):
            self.assertIn(f'"{accent}"', text)
        self.assertIn("ACCENT_IDS", text)

    def test_desktop_settings_accent_field(self) -> None:
        text = DESKTOP.read_text(encoding="utf-8")
        self.assertIn('property string accentColor: "blue"', text)
        self.assertIn("readonly property string accentColor", text)
        self.assertIn("function setAccentColor", text)
        self.assertIn("function normalizeAccentColor", text)
        self.assertIn("function accentColorLabel", text)
        self.assertIn("normalizeAccentColor(settingsAdapter.accentColor)", text)

    def test_appearance_page_accent_picker(self) -> None:
        text = APPEARANCE.read_text(encoding="utf-8")
        self.assertIn("强调色", text)
        self.assertIn("setAccentColor", text)
        for accent in ("blue", "purple", "pink", "red", "orange", "yellow", "green", "graphite"):
            self.assertIn(f'"{accent}"', text)

    def test_four_faces_import_theme(self) -> None:
        for path in FACES:
            text = path.read_text(encoding="utf-8")
            self.assertIn("SettingsTheme.js", text, path.name)
            self.assertIn("Theme.accent", text, path.name)

    def test_settings_panel_accent_binding(self) -> None:
        panel = (ROOT / "components" / "SettingsPanel.qml").read_text(encoding="utf-8")
        self.assertIn("accentId", panel)
        self.assertIn("SettingsTheme.accent(darkMode, accentId)", panel)
        self.assertIn("accentFillStrong(darkMode, accentId)", panel)

    def test_no_parallel_theme_file(self) -> None:
        """Rules §2.4: do not introduce a second color token file."""
        extra = list((ROOT / "components").rglob("*Theme*.js"))
        names = sorted(p.name for p in extra)
        self.assertEqual(names, ["SettingsTheme.js"])


if __name__ == "__main__":
    unittest.main()
