from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
SPOTLIGHT = SHELL_ROOT / "components" / "Spotlight.qml"
MOTION = SHELL_ROOT / "components" / "Motion.js"
SHELL_QML = SHELL_ROOT / "shell.qml"


class SpotlightRefactorTests(unittest.TestCase):
    def test_single_glass_panel_no_shortcut_row(self) -> None:
        text = SPOTLIGHT.read_text(encoding="utf-8")
        # One GlassPanel for the unified surface.
        self.assertEqual(text.count("GlassPanel {"), 1)
        # Shortcut chips removed from the search row.
        self.assertNotIn("shortcutRow", text)
        self.assertNotIn("AppStore-Symbol.png", text)
        self.assertNotIn("launchShortcut(shortcutButton", text)

    def test_keyboard_selection_and_preview(self) -> None:
        text = SPOTLIGHT.read_text(encoding="utf-8")
        self.assertIn("Keys.onDownPressed", text)
        self.assertIn("Keys.onUpPressed", text)
        self.assertIn("activateSelected", text)
        self.assertIn("selectionHighlight", text)
        self.assertIn("previewPane", text)
        self.assertIn("groupTitleForProvider", text)
        self.assertIn("buildSections", text)

    def test_height_uses_eased_not_spring_on_glass(self) -> None:
        text = SPOTLIGHT.read_text(encoding="utf-8")
        self.assertIn("Motion.spotlightHeightDuration", text)
        self.assertIn("emphasizedDecel", text)
        # Glass panel height Behavior must not be SpringAnimation.
        height_block = re.search(
            r"Behavior on height \{\s*NumberAnimation",
            text,
            re.S,
        )
        self.assertIsNotNone(height_block)
        # Spring only on selection highlight y (content).
        self.assertIn("SpringAnimation", text)
        self.assertIn("useSpring", text)

    def test_motion_tokens_present(self) -> None:
        text = MOTION.read_text(encoding="utf-8")
        self.assertIn("var spotlightHeightMs = 250;", text)
        self.assertIn("var spotlightPreviewFadeMs = 150;", text)
        self.assertIn("var spotlightPreviewWidth = 220;", text)
        self.assertIn("function spotlightHeightDuration", text)

    def test_shell_wires_use_spring_and_dark_mode(self) -> None:
        text = SHELL_QML.read_text(encoding="utf-8")
        self.assertIn("useSpring: shell.useSpring", text)
        # Spotlight block includes darkMode.
        spotlight = re.search(r"Spotlight \{.*?onCloseRequested", text, re.S)
        self.assertIsNotNone(spotlight)
        assert spotlight
        self.assertIn("darkMode: shell.darkMode", spotlight.group(0))


if __name__ == "__main__":
    unittest.main()
