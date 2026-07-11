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

    def test_weather_gradient_no_stroke_cards(self) -> None:
        text = WEATHER.read_text(encoding="utf-8")
        self.assertIn("heroGradientColors", text)
        self.assertIn("WeatherCodes.slug", text)
        # Large temp is non-mono (no monoFontFamily on hero temp).
        self.assertIn("font.pixelSize: 56", text)
        self.assertNotIn("font.family: root.monoFontFamily", text.split("font.pixelSize: 56")[1][:200])
        self.assertIn("WidgetCard", text)
        self.assertIn("逐时", text)
        # No 1px card stroke pattern on widget cards.
        self.assertNotIn("border.width: 1", text)

    def test_system_rings_top3_process_menu(self) -> None:
        text = SYSTEM.read_text(encoding="utf-8")
        self.assertIn("ActivityRing", text)
        self.assertIn("processesExpanded", text)
        self.assertIn("topProcesses", text)
        self.assertIn("requestProcessMenu", text)
        self.assertIn("openProcessMenu", text)
        self.assertIn("onFastDataChanged", text)
        self.assertIn("onMediumDataChanged", text)
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
        # Guard: T19 must not encrypt SystemStats poll cadence.
        text = SYSTEM_STATS.read_text(encoding="utf-8")
        # Historical intervals used by service (document presence of second-scale timers).
        self.assertRegex(text, r"interval:\s*(1000|2000|5000|10000)")
        # No sub-100ms animation poll introduced in SystemStats.
        for match in re.finditer(r"interval:\s*(\d+)", text):
            value = int(match.group(1))
            self.assertGreaterEqual(value, 1000, f"SystemStats interval too aggressive: {value}")


if __name__ == "__main__":
    unittest.main()
