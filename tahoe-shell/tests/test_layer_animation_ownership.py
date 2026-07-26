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
        settings = self.read(COMPONENTS / "SettingsPanel.qml")
        launchpad = self.read(COMPONENTS / "Launchpad.qml")

        for name, text in (
            ("sidebar", sidebar),
            ("spotlight", spotlight),
            ("toast", toast),
            ("settings", settings),
            ("launchpad", launchpad),
        ):
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

        # P04: settings maps/unmaps immediately; scrim, panel opacity and the
        # 0.985 scale settle are compositor-owned (layer-rule tahoe-settings).
        self.assertIn("visible: open", settings)
        self.assertNotIn("panel.opacity > 0.01", settings)
        self.assertNotIn("scale: root.open", settings)
        self.assertNotIn("opacity: root.open", settings)
        self.assertNotIn("regionEnabled: root.open", settings)
        self.assertNotIn("Behavior on scale", settings)

    def test_launchpad_is_compositor_owned(self) -> None:
        # P04 batch 2: the dormant QML dual path (compositorLayerAnimations
        # flag + layerProgress fade/scale + delayed unmap) is retired; niri's
        # layer-animation launchpad rule owns the outer open/close. Content
        # animations (grid enter, launch pop, paging) stay in QML.
        launchpad = self.read(COMPONENTS / "Launchpad.qml")
        self.assertIn("visible: open", launchpad)
        self.assertNotIn("property real layerProgress", launchpad)
        self.assertNotIn("playLayerEnter", launchpad)
        self.assertNotIn("playLayerExit", launchpad)
        self.assertNotIn("exitCleanupTimer", launchpad)
        self.assertNotIn("glassEnabled: root.open", launchpad)
        self.assertIn("playGridEnter", launchpad)
        self.assertIn("launchPopAnim", launchpad)

        motion = self.read(COMPONENTS / "Motion.js")
        self.assertNotIn("launchpadLayerEnterMs", motion)
        self.assertNotIn("launchpadLayerExitMs", motion)
        self.assertNotIn("launchpadLayerScaleFrom", motion)

    def test_window_overview_close_tail_is_compositor_owned(self) -> None:
        # P04 batch 3: the overview unmaps as soon as the leave flight lands
        # (visible tracks the flight phases; no backdrop-opacity unmap tail).
        # niri's layer-close fade plays the final snapshot out. The veil is
        # content-side: it fades backdrop+panel in under the enter flight and
        # resets after unmap, never delaying map/unmap.
        overview = self.read(COMPONENTS / "WindowOverview.qml")
        self.assertIn("visible: surfaceVisible", overview)
        self.assertNotIn("backdrop.opacity > 0.01", overview)
        self.assertIn("property real veil", overview)
        self.assertIn("playVeilEnter", overview)
        self.assertNotIn("regionEnabled: root.surfaceVisible", overview)
        # The backdrop/panel fade is driven by the veil animation, not by
        # Behaviors racing the unmap.
        backdrop_start = overview.index("id: backdrop")
        backdrop_end = overview.index("}", overview.index("opacity:", backdrop_start))
        self.assertNotIn("Behavior", overview[backdrop_start:backdrop_end])
        panel_start = overview.index("id: overview")
        panel_end = overview.index("MouseArea {", panel_start)
        self.assertNotIn("Behavior", overview[panel_start:panel_end])

    def test_wallpaper_launchpad_overlay_is_compositor_owned(self) -> None:
        # P04 batch 4: the live-wallpaper launchpad dim overlay maps/unmaps
        # with launchpadOpen; the 400ms dim fade is the compositor's
        # (layer-animation wallpaper_overlay). The dim rectangle is a static
        # commit at launchpadWallpaperDim.
        wallpaper = self.read(COMPONENTS / "Wallpaper.qml")
        overlay_start = wallpaper.index("id: liveWallpaperLaunchpadOverlay")
        overlay_end = wallpaper.index("Process {", overlay_start)
        overlay = wallpaper[overlay_start:overlay_end]
        self.assertIn("visible: root.liveWallpaperVisible && root.launchpadOpen", overlay)
        self.assertNotIn("liveWallpaperDim.opacity > 0.01", overlay)
        self.assertNotIn("Behavior", overlay)
        self.assertIn("opacity: Motion.launchpadWallpaperDim", overlay)

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
