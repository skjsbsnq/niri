from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
SIDEBAR = SHELL_ROOT / "components" / "LeftSidebar.qml"
WEATHER = SHELL_ROOT / "components" / "LeftSidebarWeather.qml"
SYSTEM = SHELL_ROOT / "components" / "LeftSidebarSystem.qml"
MOTION = SHELL_ROOT / "components" / "Motion.js"
SHELL_QML = SHELL_ROOT / "shell.qml"
SYSTEM_STATS = SHELL_ROOT / "services" / "SystemStats.qml"


class LeftSidebarWidgetTests(unittest.TestCase):
    def test_chrome_removed_segmented_tabs(self) -> None:
        text = SIDEBAR.read_text(encoding="utf-8")
        self.assertNotIn("左侧边栏", text)
        self.assertNotIn("closeMouse", text)
        self.assertIn("segmentBar", text)
        self.assertIn("SegmentLabel", text)
        self.assertIn("openProcessMenuRequested", text)
        self.assertIn("cardsEnter", text)

    def test_weather_animated_hero_no_stroke_cards(self) -> None:
        text = WEATHER.read_text(encoding="utf-8")
        # Medium intensity: particles only inside hero; rest is SoftCard over glass.
        self.assertIn("WeatherBackground", text)
        self.assertIn("heroCard", text)
        self.assertIn("animate: root.sidebarOpen && root.active", text)
        self.assertIn("heroSecondaryLine", text)
        self.assertIn("heroFallbackColor", text)
        self.assertIn("updatedText()", text)
        # Must NOT full-bleed the scene (that produced the grey wallpaper look).
        self.assertNotIn("Full-bleed animated scene", text)
        # Update stamp must not be the hero detail under metric pills.
        self.assertNotIn("return root.updatedText();", text)
        # Large temp is non-mono (no monoFontFamily on hero temp).
        self.assertIn("font.pixelSize: 56", text)
        self.assertNotIn("font.family: root.monoFontFamily", text.split("font.pixelSize: 56")[1][:200])
        self.assertIn("WidgetCard", text)
        self.assertIn("逐时", text)
        # No 1px card stroke pattern on widget cards.
        self.assertNotIn("border.width: 1", text)

    def test_weather_background_frame_animation(self) -> None:
        bg = (SHELL_ROOT / "components" / "WeatherBackground.qml").read_text(encoding="utf-8")
        self.assertIn("FrameAnimation", bg)
        self.assertIn("running: root.animate", bg)
        # Must not reintroduce <100ms Timer animation polls.
        for match in re.finditer(r"Timer\s*\{[^}]*interval:\s*(\d+)", bg, re.S):
            self.assertGreaterEqual(int(match.group(1)), 1000)

    def test_system_rings_top3_process_menu(self) -> None:
        text = SYSTEM.read_text(encoding="utf-8")
        self.assertIn("ActivityRing", text)
        self.assertIn("processesExpanded", text)
        self.assertIn("topProcesses", text)
        self.assertIn("requestProcessMenu", text)
        self.assertIn("openProcessMenu", text)
        self.assertIn("onFastDataChanged", text)
        self.assertIn("onMediumDataChanged", text)
        # Placeholders until first medium/slow sample (no flash of 0 RPM / 0 tasks).
        self.assertIn("hasSlow()", text)
        self.assertIn("hasMedium()", text)
        # No card stroke.
        self.assertNotIn("border.width: 1", text)

    def test_process_menu_shell_path_untouched(self) -> None:
        text = SHELL_QML.read_text(encoding="utf-8")
        self.assertIn("prepareProcessMenu", text)
        self.assertIn("ProcessMenu {", text)
        self.assertIn("PopupDismissLayer", text)
        # Signal wiring still present.
        self.assertIn("onOpenProcessMenuRequested", text)

    def test_left_sidebar_click_outside_dismiss(self) -> None:
        text = SHELL_QML.read_text(encoding="utf-8")
        # Full-screen dismiss layer paired with LeftSidebar (not only ProcessMenu).
        self.assertIn("Click-outside dismiss for left sidebar", text)
        self.assertIn("onCloseRequested: shell.closeLeftSidebar()", text)
        self.assertIn("popupWidth: leftSidebar.panelWidth", text)

    def test_motion_sidebar_stagger_tokens(self) -> None:
        text = MOTION.read_text(encoding="utf-8")
        self.assertIn("var sidebarCardStaggerMs = 24;", text)
        self.assertIn("var sidebarCardEnterOffsetPx = 10;", text)
        self.assertIn("function sidebarCardStaggerDelay", text)
        self.assertIn("function sidebarCardEnterDuration", text)

    def test_system_stats_refresh_not_tightened(self) -> None:
        # Guard: steady-state SystemStats poll cadence stays second-scale.
        text = SYSTEM_STATS.read_text(encoding="utf-8")
        # Historical intervals used by service (document presence of second-scale timers).
        self.assertRegex(text, r"interval:\s*(1000|2000|5000|10000)")
        # No sub-100ms animation poll introduced in SystemStats.
        for match in re.finditer(r"interval:\s*(\d+)", text):
            value = int(match.group(1))
            self.assertGreaterEqual(value, 1000, f"SystemStats interval too aggressive: {value}")
        # Idle desktop must not keep the stats process always running.
        self.assertIn("property bool active:", text)
        self.assertIn("running: false", text)
        # First open must bootstrap medium/slow (fan/tasks/uptime) without waiting 2s/5s.
        self.assertIn("emit_medium", text)
        self.assertIn("emit_slow", text)
        self.assertIn("emit_fast_snapshot", text)
        self.assertIn("hasMediumData", text)
        self.assertIn("hasSlowData", text)
        # Steady cadence markers preserved.
        self.assertIn("tick % 2", text)
        self.assertIn("tick % 5", text)

    def test_shell_gates_system_stats_on_left_sidebar(self) -> None:
        text = SHELL_QML.read_text(encoding="utf-8")
        self.assertIn("SystemStats {", text)
        self.assertIn("active: shell.leftSidebarOpen", text)


if __name__ == "__main__":
    unittest.main()
