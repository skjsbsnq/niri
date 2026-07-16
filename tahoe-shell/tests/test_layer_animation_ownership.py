from __future__ import annotations

import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = SHELL_ROOT / "components"
SERVICES = SHELL_ROOT / "services"
PAGES = COMPONENTS / "settings" / "pages"
SHELL_QML = SHELL_ROOT / "shell.qml"


class LayerAnimationOwnershipTests(unittest.TestCase):
    def read(self, path: Path) -> str:
        return path.read_text(encoding="utf-8")

    def test_migrated_surfaces_have_no_qml_outer_fallback(self) -> None:
        sidebar = self.read(COMPONENTS / "LeftSidebar.qml")
        spotlight = self.read(COMPONENTS / "Spotlight.qml")
        toast = self.read(COMPONENTS / "NotificationToast.qml")

        for name, text in (("sidebar", sidebar), ("spotlight", spotlight), ("toast", toast)):
            with self.subTest(component=name):
                self.assertNotIn("compositorLayerAnimations", text)

        self.assertIn("visible: open", sidebar)
        self.assertNotIn("slideTransform", sidebar)
        self.assertNotIn("qmlSlideActive", sidebar)
        self.assertNotIn("regionEnabled: root.open", sidebar)

        self.assertIn("visible: open", spotlight)
        panel_start = spotlight.index("id: spotlightPanel")
        panel_end = spotlight.index("MouseArea {", panel_start)
        panel_outer = spotlight[panel_start:panel_end]
        self.assertNotIn("opacity:", panel_outer)
        self.assertNotIn("scale:", panel_outer)
        self.assertNotIn("glassEnabled: root.open", spotlight)

        self.assertIn("visible: shouldShowToast", toast)
        self.assertNotIn("toastMaterialAlpha", toast)
        self.assertNotIn("toastGlassActive", toast)

    def test_launchpad_remains_explicit_qml_outer_owner(self) -> None:
        launchpad = self.read(COMPONENTS / "Launchpad.qml")
        self.assertIn("readonly property bool compositorLayerAnimations: false", launchpad)

    def test_layer_toggle_uses_only_niri_settings_writer(self) -> None:
        desktop = self.read(SERVICES / "DesktopSettings.qml")
        niri = self.read(SERVICES / "NiriSettings.qml")
        page = self.read(PAGES / "NiriAnimationsPage.qml")

        self.assertNotIn("compositorLayerAnimations", desktop)
        self.assertIn("property bool layerAnimationsEnabled: true", niri)
        self.assertIn('root.writeField("animations.layer_animations_enabled", next)', niri)
        self.assertIn("checked: page.svc && page.svc.layerAnimationsEnabled", page)
        self.assertIn("page.svc.setLayerAnimationsEnabled(checked)", page)
        self.assertNotIn("setCompositorLayerAnimations", page)

    def test_reduced_motion_keeps_internal_qml_gate_and_profile_bridge(self) -> None:
        sidebar = self.read(COMPONENTS / "LeftSidebar.qml")
        spotlight = self.read(COMPONENTS / "Spotlight.qml")
        toast = self.read(COMPONENTS / "NotificationToast.qml")
        shell = self.read(SHELL_QML)

        self.assertIn("Motion.reducedMotion(root.settingsService)", sidebar)
        self.assertIn("Motion.reducedMotion(root.settingsService)", spotlight)
        self.assertIn("Motion.reducedMotion(root.settingsService)", toast)
        self.assertIn("desktopSettings.setMotionProfile(niriSettings.motionProfile)", shell)


if __name__ == "__main__":
    unittest.main()
