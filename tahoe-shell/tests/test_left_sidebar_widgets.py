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

    def test_system_process_rows_use_stable_pid_model_and_transitions(self) -> None:
        view = SYSTEM.read_text(encoding="utf-8")
        service = SYSTEM_STATS.read_text(encoding="utf-8")

        # R11 service contract: one long-lived QObject per live PID, with
        # fields updated in place and retired after the remove transition.
        for marker in (
            "id: processState",
            "id: processEntryFactory",
            "readonly property var processes: processState.entries",
            "function mergeProcessSnapshot(value)",
            "var cache = processState.cache || Object.create(null)",
            '"modelKey": String(pid) + ":"',
            "property string startTime",
            "processState.entries = next",
            "removedEntry.destroy(1000)",
            "mergeProcessSnapshot(packet.processes)",
        ):
            self.assertIn(marker, service)
        self.assertNotIn('setValue("processes"', service)

        # The view may rebuild its ordered array, but ScriptModel must preserve
        # surviving process-instance delegates and surface structural changes
        # as motion. PID remains the display/operation field; /proc starttime
        # prevents an intervening PID reuse from inheriting the old delegate.
        self.assertIn('objectProp: "modelKey"', view)
        self.assertIn("values: root.visibleProcessList", view)
        self.assertIn("add: Transition", view)
        self.assertIn("remove: Transition", view)
        self.assertIn("move: Transition", view)
        self.assertIn("displaced: Transition", view)
        self.assertIn("Motion.elementMove(root.settingsService)", view)
        self.assertIn("Motion.fadeFast(root.settingsService)", view)
        self.assertIn("return Number(a.pid) - Number(b.pid);", view)
        self.assertIn('"startTime": String(proc.startTime || "")', view)
        self.assertIn("root.openProcessMenu(menuProc, anchorRect)", view)
        self.assertNotIn("model: root.visibleProcessList", view)

        fast_handler = re.search(
            r"function onFastDataChanged\(\) \{(?P<body>[\s\S]*?)\n        \}",
            view,
        )
        self.assertIsNotNone(fast_handler)
        assert fast_handler
        self.assertNotIn("refreshProcessLists", fast_handler.group("body"))

        medium_handler = re.search(
            r"function onMediumDataChanged\(\) \{(?P<body>[\s\S]*?)\n        \}",
            view,
        )
        self.assertIsNotNone(medium_handler)
        assert medium_handler
        self.assertIn("root.refreshProcessLists();", medium_handler.group("body"))
        self.assertNotIn("processMenuOpen", medium_handler.group("body"))

    def test_system_motion_polish_is_reduced_safe_and_eased(self) -> None:
        text = SYSTEM.read_text(encoding="utf-8")

        # Activity arcs interpolate their display value; Canvas repaint follows
        # the animated value rather than the raw 1-2 second sample.
        ring = re.search(
            r"component ActivityRing: Item \{(?P<body>[\s\S]*?)"
            r"\n    component StatCell:",
            text,
        )
        self.assertIsNotNone(ring)
        assert ring
        ring_body = ring.group("body")
        for marker in (
            "property real displayProgress: progressTarget",
            "Behavior on displayProgress",
            "enabled: !Motion.reducedMotion(root.settingsService)",
            "SmoothedAnimation",
            "duration: 500",
            "property real p: ring.displayProgress",
            "ringCanvas.p",
            "onRingColorChanged: ringCanvas.requestPaint()",
        ):
            self.assertIn(marker, ring_body)
        self.assertNotIn("SpringAnimation", ring_body)

        # Expanded process chrome/list and the card geometry share ccMorph;
        # reduced profile collapses the duration to zero.
        process_block = re.search(
            r"id: procCard(?P<body>[\s\S]*?)\n    // --- components ---",
            text,
        )
        self.assertIsNotNone(process_block)
        assert process_block
        process_body = process_block.group("body")
        for marker in (
            "processChromeProgress",
            "8 * root.processChromeProgress",
            "Behavior on height",
            'objectProp: "modelKey"',
            "Behavior on color",
        ):
            self.assertIn(marker, process_body)
        self.assertIn("Motion.ccMorphDurationMs", text)
        self.assertIn("Motion.reducedMotion(settingsService) ? 0", text)
        self.assertIn("Behavior on processChromeProgress", text)

        tabs_block = text.split("// Expanded chrome: tabs + search", 1)[1].split(
            "// Sort headers when expanded", 1
        )[0]
        self.assertIn("height: 26 * root.processChromeProgress", tabs_block)
        self.assertIn("opacity: root.processChromeProgress", tabs_block)
        self.assertIn("enabled: root.processesExpanded", tabs_block)

        sort_block = text.split("// Sort headers when expanded", 1)[1].split(
            "id: procListHost", 1
        )[0]
        self.assertIn("height: 22 * root.processChromeProgress", sort_block)
        self.assertIn("opacity: root.processChromeProgress", sort_block)
        self.assertIn("enabled: root.processesExpanded", sort_block)

        list_host = text.split("id: procListHost", 1)[1].split(
            "ListView {", 1
        )[0]
        self.assertIn("processList.contentHeight", list_host)
        self.assertIn("Behavior on height", list_host)
        self.assertIn("duration: root.processMorphDuration", list_host)

        # Disk/battery fill and interactive colors use eased/tokenized paths.
        disk = text.split("// Disk", 1)[1].split("// Battery", 1)[0]
        battery = text.split("// Battery", 1)[1].split("// --- Processes", 1)[0]
        for block in (disk, battery):
            self.assertIn("Behavior on width", block)
            self.assertIn("Motion.elementResize(root.settingsService)", block)
            self.assertNotIn("SpringAnimation", block)

        seg_tab = text.split("component SegTab: Rectangle", 1)[1].split(
            "component SortHeader: Rectangle", 1
        )[0]
        sort_header = text.split("component SortHeader: Rectangle", 1)[1]
        self.assertGreaterEqual(seg_tab.count("ColorAnimation"), 2)
        self.assertGreaterEqual(sort_header.count("ColorAnimation"), 2)
        self.assertIn("root.rowActive", sort_header)

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
