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

    def test_result_rows_use_stable_identity_and_pruned_caches(self) -> None:
        text = SPOTLIGHT.read_text(encoding="utf-8")
        self.assertIn('objectProp: "modelKey"', text)
        self.assertIn("function stableResultKey(result)", text)
        self.assertIn("JSON.stringify([provider, resultId, kind])", text)
        self.assertIn("property var _sectionCache: ({})", text)
        self.assertIn("property var _flatRowCache: ({})", text)
        self.assertIn("sameResultSequence(cached.items, candidate.items)", text)
        self.assertIn("function currentResultForModelKey(modelKey, fallback)", text)
        self.assertIn("function selectableIndexForModelKey(modelKey)", text)
        self.assertIn("row.result = result", text)
        self.assertIn("pruneCache(cache, activeKeys)", text)

    def test_results_refresh_is_imperative_and_provider_revision_driven(self) -> None:
        text = SPOTLIGHT.read_text(encoding="utf-8")
        self.assertIn("property var results: []", text)
        self.assertNotRegex(
            text,
            r"readonly property var results\s*:[\s\S]{0,180}resultsForQuery\(",
        )
        self.assertIn("function refreshResults()", text)
        self.assertIn("onSearchServiceChanged: root.refreshResults()", text)
        self.assertIn("function onProviderRevisionChanged() { root.refreshResults(); }", text)
        query_handler = re.search(r"onQueryChanged:\s*\{(.*?)\n    \}", text, re.S)
        self.assertIsNotNone(query_handler)
        assert query_handler
        self.assertIn("selectedIndex = 0", query_handler.group(1))
        self.assertIn("root.refreshResults()", query_handler.group(1))

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
