from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class SettingsCapabilityRegistryTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def settings_model(self) -> str:
        return self.read("components/settings/SettingsModel.js")

    def registry_text(self) -> str:
        text = self.settings_model()
        start = text.index("var panelCapabilities = {")
        end = text.index("var aliases = {")
        return text[start:end]

    def panel_ids(self) -> list[str]:
        text = self.settings_model()
        panels_text = text[: text.index("var panelCapabilities = {")]
        return re.findall(r'\n    \{\n        "id": "([^"]+)"', panels_text)

    def capability_block(self, panel_id: str) -> str:
        registry = self.registry_text()
        marker = f'    "{panel_id}": {{'
        start = registry.index(marker)
        end = registry.index("\n    }", start)
        return registry[start:end]

    def test_every_settings_panel_has_phase4_capability_metadata(self) -> None:
        registry = self.registry_text()
        registered = set(re.findall(r'^    "([^"]+)": \{', registry, flags=re.MULTILINE))
        panel_ids = set(self.panel_ids())

        self.assertEqual(panel_ids - registered, set())
        for panel_id in sorted(panel_ids):
            block = self.capability_block(panel_id)
            for field in ('"capability"', '"backend"', '"externalPanel"', '"writeScope"'):
                self.assertIn(field, block, panel_id)

    def test_feature_domains_are_explicitly_non_native(self) -> None:
        expected = {
            "search": ("CAPABILITY_PROBE", '"featureIds": ["search-index"]'),
            "online-accounts": ("CAPABILITY_EXTERNAL", '"featureIds": ["online-accounts", "gnome-control-center"]'),
            "sharing": ("CAPABILITY_PROBE", '"featureIds": ["remote-login", "discovery", "file-sharing", "media-sharing"]'),
            "wellbeing": ("CAPABILITY_READONLY", "no screen-time backend"),
            "color": ("CAPABILITY_EXTERNAL", '"featureIds": ["color"]'),
            "printers": ("CAPABILITY_EXTERNAL", '"featureIds": ["printers"]'),
            "accessibility": ("CAPABILITY_EXTERNAL", '"featureIds": ["accessibility"]'),
            "privacy": ("CAPABILITY_READONLY", '"featureIds": ["portal-permissions", "desktop-portal"]'),
        }

        for panel_id, (capability, detail) in expected.items():
            block = self.capability_block(panel_id)
            self.assertIn(capability, block, panel_id)
            self.assertNotIn("CAPABILITY_NATIVE", block, panel_id)
            self.assertIn(detail, block, panel_id)

    def test_feature_probe_page_reads_registry_instead_of_hardcoding_feature_ids(self) -> None:
        text = self.read("components/settings/pages/FeatureProbePage.qml")

        self.assertIn("SettingsModel.featureIds(page.panelId)", text)
        self.assertIn("page.capabilityLabel +", text)
        self.assertIn("page.writeScope.length", text)
        self.assertIn("page.externalPanelId", text)
        self.assertNotIn('return ["search-index"]', text)
        self.assertNotIn('return ["online-accounts", "gnome-control-center"]', text)
        self.assertNotIn("function externalPanel()", text)

    def test_settings_panel_uses_semantic_capability_pages(self) -> None:
        text = self.read("components/SettingsPanel.qml")

        self.assertNotIn("Pages.FeaturePage", text)
        for needle in (
            "Pages.FeatureProbePage",
            "Pages.ExternalSettingsPage",
            "Pages.ReadOnlyCapabilityPage",
        ):
            self.assertIn(needle, text)

        feature_page = self.read("components/settings/pages/FeaturePage.qml")
        self.assertIn("FeatureProbePage", feature_page)

    def test_startup_panel_is_native_autostart_manager(self) -> None:
        model = self.settings_model()
        startup = self.capability_block("startup")
        page = self.read("components/settings/pages/StartupPage.qml")
        panel = self.read("components/SettingsPanel.qml")
        service = self.read("services/DesktopSettings.qml")

        self.assertIn("XDG autostart manager", startup)
        self.assertIn("列出、添加、启用、停用和移除", startup)
        self.assertNotIn("不编辑 .desktop 启用状态", model)
        self.assertIn("autostart_manager.py", service)
        self.assertIn("setAutostartEnabled", page)
        self.assertIn("addAutostartApp", page)
        self.assertIn("removeAutostartEntry", page)
        self.assertIn("validationDetail", page)
        self.assertIn("appsService: root.appsService", panel)


if __name__ == "__main__":
    unittest.main()
