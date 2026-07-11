"""T15: Settings shell redesign — opaque fill, sidebar, page transition, back nav."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PANEL = ROOT / "components" / "SettingsPanel.qml"
SIDEBAR = ROOT / "components" / "settings" / "SettingsSidebar.qml"
SIDEBAR_BTN = ROOT / "components" / "settings" / "controls" / "TahoeSidebarButton.qml"
THEME = ROOT / "components" / "settings" / "SettingsTheme.js"
MOTION = ROOT / "components" / "Motion.js"
MODEL = ROOT / "components" / "settings" / "SettingsModel.js"


class SettingsShellRedesignTests(unittest.TestCase):
    def test_panel_fill_near_opaque(self) -> None:
        text = THEME.read_text(encoding="utf-8")
        # ~0.92 alpha → 0xEB prefix on ARGB hex
        self.assertIn("#eb1d1f24", text)
        self.assertIn("#ebf5f6f8", text)

    def test_sidebar_width_230(self) -> None:
        text = SIDEBAR.read_text(encoding="utf-8")
        self.assertIn("Layout.preferredWidth: 230", text)
        self.assertNotIn("Layout.preferredWidth: 210", text)

    def test_sidebar_uses_category_icon(self) -> None:
        btn = SIDEBAR_BTN.read_text(encoding="utf-8")
        self.assertIn("TahoeCategoryIcon", btn)
        self.assertIn("categoryColor", btn)
        # Selected = solid accent capsule + white label
        self.assertIn("btn.active ? btn.accentBlue", btn)
        self.assertIn('btn.active ? "#ffffff"', btn)

        sidebar = SIDEBAR.read_text(encoding="utf-8")
        self.assertIn("categoryColorFor", sidebar)
        self.assertIn("categoryColor:", sidebar)

    def test_page_host_replaces_stack_layout(self) -> None:
        panel = PANEL.read_text(encoding="utf-8")
        self.assertNotIn("StackLayout", panel)
        self.assertIn("id: pageHost", panel)
        self.assertIn("function navigateTo", panel)
        self.assertIn("function snapTo", panel)
        self.assertIn("Motion.settingsPageTransition", panel)
        self.assertIn("settingsPageEnterOffsetPx", panel)
        self.assertIn("settingsPageExitOffsetPx", panel)
        # Slide must use Translate so anchors.fill does not fight x.
        self.assertIn("transform: Translate", panel)
        # No top-level `x:` property on layers (only inside Translate {}).
        self.assertIsNone(re.search(r"(?m)^\s+x:\s*pageHost\.layerX\(", panel))

    def test_motion_page_transition_tokens(self) -> None:
        motion = MOTION.read_text(encoding="utf-8")
        self.assertIn("settingsPageTransitionMs = 280", motion)
        self.assertIn("settingsPageEnterOffsetPx = 24", motion)
        self.assertIn("settingsPageExitOffsetPx = 12", motion)
        self.assertIn("function settingsPageTransition(", motion)

    def test_back_chevron_uses_parent_id(self) -> None:
        panel = PANEL.read_text(encoding="utf-8")
        self.assertIn("function parentPageId", panel)
        self.assertIn("function canGoBack", panel)
        self.assertIn("function goBack", panel)
        self.assertIn("SettingsModel.parentId", panel)
        self.assertIn("root.canGoBack()", panel)
        self.assertIn("root.goBack()", panel)

    def test_all_model_pages_have_layers(self) -> None:
        model = MODEL.read_text(encoding="utf-8")
        start = model.index("var panels = [")
        end = model.index("];", start)
        block = model[start:end]
        ids = re.findall(r'(?m)^\s+"id":\s+"([^"]+)"', block)
        self.assertEqual(len(ids), 36, ids)

        panel = PANEL.read_text(encoding="utf-8")
        for pid in ids:
            self.assertIn(f'layerX("{pid}")', panel, pid)
            self.assertIn(f'layerOpacity("{pid}")', panel, pid)

    def test_no_spring_on_settings_page_geometry(self) -> None:
        panel = PANEL.read_text(encoding="utf-8")
        # Page transition must use NumberAnimation / emphasized, not SpringAnimation.
        host = panel[panel.index("id: pageHost") : panel.index("Component.onCompleted: snapTo")]
        self.assertIn("NumberAnimation", host)
        self.assertNotIn("SpringAnimation", host)
        self.assertIn("emphasizedDecel", host)


if __name__ == "__main__":
    unittest.main()
