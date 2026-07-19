#!/usr/bin/env python3
"""R18 peripheral motion contracts."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ROOT / "components"


class R18PeripheralMotionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.topbar = (COMPONENTS / "TopBar.qml").read_text(encoding="utf-8")
        cls.settings = (COMPONENTS / "SettingsPanel.qml").read_text(encoding="utf-8")
        cls.sidebar = (COMPONENTS / "LeftSidebar.qml").read_text(encoding="utf-8")
        cls.weather = (COMPONENTS / "LeftSidebarWeather.qml").read_text(encoding="utf-8")
        cls.background = (COMPONENTS / "WeatherBackground.qml").read_text(encoding="utf-8")
        cls.meteo = (COMPONENTS / "MeteoIcon.qml").read_text(encoding="utf-8")
        cls.tray = (COMPONENTS / "Tray.qml").read_text(encoding="utf-8")
        cls.spotlight = (COMPONENTS / "Spotlight.qml").read_text(encoding="utf-8")
        cls.wallpaper = (COMPONENTS / "Wallpaper.qml").read_text(encoding="utf-8")
        cls.icon_button = (COMPONENTS / "controls" / "IconButton.qml").read_text(encoding="utf-8")

    def test_topbar_badges_buttons_and_battery_are_tokenized(self) -> None:
        for badge_id in ("notificationBadge", "clipboardBadge"):
            block = re.search(rf"id:\s*{badge_id}.*?Text\s*\{{", self.topbar, re.S)
            self.assertIsNotNone(block, badge_id)
            assert block
            self.assertIn("hasBadge", block.group(0))
            self.assertIn("visible: hasBadge || opacity > 0.01", block.group(0))
            self.assertIn("Behavior on opacity", block.group(0))
            self.assertIn("Behavior on scale", block.group(0))

        self.assertGreaterEqual(self.topbar.count("Behavior on color"), 11)
        self.assertIn("hoverEnabled: true", self.topbar)
        battery = re.search(r"id:\s*batteryFill.*?Rectangle\s*\{", self.topbar, re.S)
        self.assertIsNotNone(battery)
        assert battery
        self.assertIn("Behavior on width", battery.group(0))
        self.assertIn("Behavior on color", battery.group(0))

    def test_settings_header_and_controls_follow_page_host(self) -> None:
        self.assertIn("id: outgoingHeader", self.settings)
        self.assertIn("id: incomingHeader", self.settings)
        self.assertIn("pageHost.fromId", self.settings)
        self.assertIn("pageHost.toId", self.settings)
        self.assertIn("fromOpacityStart", self.settings)
        self.assertIn("toOpacityStart", self.settings)
        self.assertIn("oldFromOpacity", self.settings)
        self.assertIn("root.pageTitle(outgoingHeader.pageId)", self.settings)
        self.assertIn("root.pageSubtitle(incomingHeader.pageId)", self.settings)
        for host in ("backButtonHost", "refreshButtonHost"):
            block = re.search(rf"id:\s*{host}.*?Controls\.TahoeButton", self.settings, re.S)
            self.assertIsNotNone(block, host)
            assert block
            self.assertIn("visible: shown || opacity > 0.01", block.group(0))
            self.assertIn("Behavior on opacity", block.group(0))

    def test_sidebar_tabs_crossfade_without_touching_segment_driver(self) -> None:
        self.assertIn('opacity: root.currentTab === "system" ? 1 : 0', self.sidebar)
        self.assertIn('opacity: root.currentTab === "weather" ? 1 : 0', self.sidebar)
        self.assertIn("visible: root.currentTab === \"system\" || opacity > 0.01", self.sidebar)
        self.assertIn("visible: root.currentTab === \"weather\" || opacity > 0.01", self.sidebar)
        self.assertIn("Behavior on color", self.sidebar)
        segment = self.sidebar[self.sidebar.index("id: segmentThumb") : self.sidebar.index("component SegmentLabel")]
        self.assertEqual(segment.count('property: "x"'), 1)
        self.assertIn("segmentSpring.stop()", segment)

    def test_weather_refresh_states_and_content_lifecycle(self) -> None:
        self.assertIn("iconSpinning: root.updating", self.weather)
        self.assertIn("settingsService: root.settingsService", self.weather)
        self.assertIn("visible: root.showContent || opacity > 0.01", self.weather)
        self.assertIn("visible: root.showEmptyState || opacity > 0.01", self.weather)
        self.assertIn("shown: root.showStatusBanner", self.weather)
        self.assertIn("Behavior on x", self.weather)
        self.assertIn("Behavior on width", self.weather)
        self.assertIn("property bool shown: false", self.weather)
        self.assertIn("height: shown ? 52 : 0", self.weather)
        self.assertIn("iconSpinning", self.icon_button)

    def test_weather_palette_and_icon_use_crossfade(self) -> None:
        self.assertIn("property var settingsService", self.background)
        self.assertGreaterEqual(self.background.count("ColorAnimation"), 6)
        self.assertIn("property string displayedGlyph", self.meteo)
        self.assertIn("property string outgoingGlyph", self.meteo)
        self.assertIn("transitionToGlyph", self.meteo)
        self.assertIn("outgoingStartOpacity", self.meteo)
        self.assertIn("incomingStartOpacity", self.meteo)
        self.assertIn("Motion.reducedMotion", self.meteo)
        self.assertIn("NumberAnimation", self.meteo)

    def test_tray_has_stable_identity_and_list_lifecycle(self) -> None:
        self.assertIn("function trayItemKey", self.tray)
        self.assertIn('objectProp: "modelKey"', self.tray)
        self.assertIn("readonly property var orderedEntries", self.tray)
        self.assertIn("ListView {", self.tray)
        for transition in ("add", "remove", "move", "displaced"):
            self.assertIn(f"{transition}: Transition", self.tray)
        self.assertIn("lifecycleOpacity", self.tray)
        self.assertIn("lifecycleScale", self.tray)
        self.assertIn("property real animatedWidth", self.tray)
        self.assertIn("visible: animatedWidth > 0.01 || opacity > 0.01", self.tray)
        self.assertIn("Behavior on color", self.tray)

    def test_spotlight_keeps_compositor_close_and_polishes_rows(self) -> None:
        self.assertIn("visible: open", self.spotlight)
        panel_start = self.spotlight.index("id: spotlightPanel")
        panel_end = self.spotlight.index("MouseArea {", panel_start)
        self.assertNotIn("opacity:", self.spotlight[panel_start:panel_end])
        self.assertNotIn("scale:", self.spotlight[panel_start:panel_end])
        self.assertIn("move: Transition", self.spotlight)
        self.assertIn("Behavior on color", self.spotlight)
        self.assertIn('objectProp: "modelKey"', self.spotlight)

    def test_wallpaper_keeps_static_zoom_and_dims_live_surface(self) -> None:
        self.assertIn("readonly property bool liveWallpaperVisible", self.wallpaper)
        self.assertIn("tahoe-wallpaper-launchpad-overlay", self.wallpaper)
        self.assertIn("WlrLayershell.layer: WlrLayer.Bottom", self.wallpaper)
        self.assertIn("Motion.launchpadWallpaperDim", self.wallpaper)

        static_layer = re.search(r"id: staticLayer.*?// Live wallpapers", self.wallpaper, re.S)
        self.assertIsNotNone(static_layer)
        assert static_layer
        self.assertIn("scale: staticLayer.zoom", static_layer.group(0))
        self.assertIn("Motion.launchpadWallpaperScale", static_layer.group(0))

        live_overlay = re.search(r"id: liveWallpaperLaunchpadOverlay.*?Process \{", self.wallpaper, re.S)
        self.assertIsNotNone(live_overlay)
        assert live_overlay
        self.assertIn("opacity: root.launchpadOpen ? Motion.launchpadWallpaperDim : 0", live_overlay.group(0))
        self.assertNotIn("Motion.launchpadWallpaperScale", live_overlay.group(0))
        self.assertIn("cannot be transformed by staticLayer", self.wallpaper)
        self.assertIn("without restarting or pausing the wallpaper process", self.wallpaper)


if __name__ == "__main__":
    unittest.main()
