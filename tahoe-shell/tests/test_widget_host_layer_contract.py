"""A2 contract tests: desktop widget host layer.

Source-level guards (same style as test_updates_enabled_gate.py) for the
desktop-widget host introduced by A2. Four things must hold:

1. LAYER CONTRACT (A-C1 / P-6): the host is a Bottom-layer PanelWindow with
   ExclusionMode.Ignore, KeyboardInteractivity.None, no focusable, namespace
   "tahoe-widgets", and the P02 updatesEnabled mirror.
2. MASK POLICY (A-0 #5): popup open -> mask null (clicks reach the dismiss
   layer); otherwise the mask is the union of widget items. No parallel
   mask-building path (G-6).
3. WIDGET BASE (P-1 / P-3 / P-5 / A-C4 / A-C6): exactly one glass region per
   widget, no springs on region geometry, no hardcoded durations, no
   layer.enabled, no unbudgeted images, no self-built polling.
4. PERSISTENCE (A-C5): write happens once per completed operation, never
   during drag/resize.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ROOT / "components"
WIDGETS = COMPONENTS / "widgets"
HOST = WIDGETS / "WidgetHost.qml"
WIDGET_BASE = WIDGETS / "Widget.qml"
GRID = WIDGETS / "WidgetGrid.js"


def all_widget_sources() -> list[Path]:
    return sorted(WIDGETS.glob("*.qml"))


class WidgetHostLayerContractTests(unittest.TestCase):
    def test_host_is_bottom_layer_with_input_policy(self) -> None:
        text = HOST.read_text(encoding="utf-8")
        self.assertIn("PanelWindow {", text)
        self.assertIn("WlrLayershell.layer: WlrLayer.Bottom", text)
        self.assertIn("WlrLayershell.namespace: \"tahoe-widgets\"", text)
        self.assertIn("exclusionMode: ExclusionMode.Ignore", text)
        self.assertIn("WlrKeyboardFocus.None", text)
        self.assertIn("focusable: false", text)
        # P-6: must not be set focusable anywhere in the host.
        self.assertNotIn("focusable: true", text)

    def test_host_updates_enabled_mirrors_visible(self) -> None:
        self.assertRegex(
            HOST.read_text(encoding="utf-8"),
            r"(?m)^[ \t]*updatesEnabled:\s*visible\b",
        )

    def test_host_mask_policy_no_parallel_path(self) -> None:
        text = HOST.read_text(encoding="utf-8")
        # Popup open -> mask null.
        self.assertIn("root.mask = null", text)
        self.assertIn("root.popupActive", text)
        # Union built by one function only.
        self.assertIn("function buildUnionRegion(", text)
        # No invented second API (G-6): no addRegion/add/subtract helpers.
        for forbidden in ("addRegion", ".add(", "maskRegion"):
            self.assertNotIn(forbidden, text)
        # The mask is never authored as an inline QML Region element
        # (single builder owns the union; Region is only assembled inside
        # buildUnionRegion's string).
        self.assertNotRegex(text, r"(?m)^[ \t]*mask: Region")
        self.assertNotRegex(text, r"(?m)^[ \t]*Region \{")
        # Region union must use nested Combine children (Intersect root).
        self.assertIn("Intersection.Intersect", text)

    def test_host_popup_active_wired_in_shell(self) -> None:
        shell = (COMPONENTS.parent / "shell.qml").read_text(encoding="utf-8")
        self.assertIn("WidgetHost {", shell)
        self.assertIn("popupActive:", shell)
        self.assertIn("batteryService: battery", shell)
        self.assertIn("screen: modelData", shell)
        # QML directory imports are non-recursive: the host lives in
        # components/widgets/, so shell.qml MUST import that subdir or the
        # whole document fails to load (WidgetHost not a type).
        self.assertIn("import \"components/widgets\"", shell)

    def test_shell_import_header_no_brace_in_comments(self) -> None:
        # quickshell QmlScanner scans the import header line-by-line and
        # stops at ANY line containing '{' — even a comment. A literal
        # "WidgetHost {" in the A2 comment silently truncates the header,
        # so `import "components/widgets"` and `import "services"` are never
        # scanned, their qmldirs are never synthesized, and the shell fails
        # with random "X is not a type" (live incident 2026-08-10, twice).
        shell = (COMPONENTS.parent / "shell.qml").read_text(encoding="utf-8")
        # The header is everything up to AND INCLUDING the LAST import line.
        # (Earlier guard split at the FIRST import, missing the A2 comment
        # that sits AFTER "import \"components\"" — a false guard.)
        import_lines = [i for i, l in enumerate(shell.split("\n")) if l.startswith("import ")]
        self.assertTrue(import_lines, "shell.qml must have imports")
        last_import = import_lines[-1]
        header = "\n".join(shell.split("\n")[: last_import + 1])
        # No brace anywhere in the import region — not even inside comments
        # or quoted like '{'. QmlScanner uses line.contains('{').
        self.assertNotIn("{", header)
        self.assertNotIn("}", header)
        # The three directory imports must all be present.
        for imp in ("import \"components\"", "import \"components/widgets\"", "import \"services\""):
            self.assertIn(imp, shell)


class WidgetBaseContractTests(unittest.TestCase):
    def test_widget_base_single_glass_region(self) -> None:
        text = WIDGET_BASE.read_text(encoding="utf-8")
        # Exactly one glass region per widget (P-5: 1 region per widget).
        self.assertEqual(text.count("GlassPanel {"), 1)
        self.assertIn("regionItem: root", text)
        self.assertIn("useItemRegion: true", text)

    def test_widget_base_size_spec(self) -> None:
        text = WIDGET_BASE.read_text(encoding="utf-8")
        self.assertIn("widgetSize", text)
        self.assertIn("small", text)
        self.assertIn("medium", text)
        self.assertIn("large", text)
        # G-6: the size->span mapping has a single source (WidgetGrid.js);
        # the base class must not maintain a parallel copy.
        self.assertNotIn("sizeCols", text)
        self.assertNotIn("sizeRows", text)
        grid = GRID.read_text(encoding="utf-8")
        self.assertIn("function colsForSize(", grid)
        self.assertIn("function rowsForSize(", grid)
        self.assertIn("function validSize(", grid)

    def test_widget_js_imports_direct(self) -> None:
        # D2: JS imported via a directory import (`import ".." as C`) yields
        # an EMPTY module (only QML types resolve). Widgets must import the
        # TahoeGlass.js / WidgetGrid.js files directly.
        for path in all_widget_sources():
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("import \"..\" as C", text, msg=path.name)
        widget = WIDGET_BASE.read_text(encoding="utf-8")
        self.assertIn("import \"../TahoeGlass.js\" as GlassStyle", widget)
        host = HOST.read_text(encoding="utf-8")
        self.assertIn("import \"../TahoeGlass.js\" as GlassStyle", host)
        self.assertIn("import \"WidgetGrid.js\" as Grid", host)

    def test_widget_files_import_parent_types(self) -> None:
        # Subdirectory QML files need `import ".."` to resolve parent-dir
        # QML types (TahoeSymbol/GlassPanel/Widget). Without it the widget
        # fails to instantiate with "TahoeSymbol is not a type".
        for path in all_widget_sources():
            text = path.read_text(encoding="utf-8")
            self.assertIn("import \"..\"", text, msg=path.name)

    def test_mask_region_imports_quickshell_module(self) -> None:
        # buildUnionRegion's Qt.createQmlObject string imports the Region
        # type — which lives in the Quickshell module (region.hpp QML_ELEMENT),
        # NOT Quickshell.Wayland. Importing the wrong module yields
        # "Region is not a type" at runtime.
        text = HOST.read_text(encoding="utf-8")
        self.assertIn("import Quickshell; ", text)
        self.assertIn("Intersection.Intersect", text)
        # The old wrong module must not be referenced in the mask string.
        self.assertNotIn("import Quickshell.Wayland; ", text)

    def test_widget_base_host_visible_gate(self) -> None:
        text = WIDGET_BASE.read_text(encoding="utf-8")
        self.assertIn("hostVisible", text)
        self.assertIn("dataRefreshActive", text)
        self.assertIn("previewMode", text)

    def test_no_springs_no_hardcoded_durations_no_layer_no_timers(self) -> None:
        # P-1: no SpringAnimation in widget code.
        for path in all_widget_sources():
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("SpringAnimation", text, msg=path.name)
            # P-3: no hardcoded duration literals.
            match = re.compile(r"duration:\s*[0-9]+").search(text)
            self.assertIsNone(match, msg=f"{path.name} hardcoded duration")
            # A-C4: no layer.enabled.
            self.assertNotIn("layer.enabled", text, msg=path.name)

    def test_no_unbudgeted_images(self) -> None:
        # A-C6: any Image must set sourceSize (A2 ships none at all).
        for path in all_widget_sources():
            text = path.read_text(encoding="utf-8")
            if "Image {" in text:
                self.assertIn("sourceSize", text, msg=path.name)
                self.assertIn("cache: false", text, msg=path.name)

    def test_no_self_built_polling_in_widget_base_and_battery(self) -> None:
        # A-C3: widgets must not own polling timers. Host may own only its
        # one-shot overflow banner timers (bounded, visible feedback).
        for path in (WIDGET_BASE, WIDGETS / "BatteryWidget.qml"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("Timer {", text, msg=path.name)
            self.assertNotIn("repeat: true", text, msg=path.name)

    def test_host_overflow_banner_timers_are_one_shot_gated(self) -> None:
        text = HOST.read_text(encoding="utf-8")
        # The only timers in the host are the overflow banner pair.
        self.assertEqual(text.count("Timer {"), 2)
        self.assertIn("repeat: false", text)
        self.assertIn("overflowBannerTimer", text)
        self.assertIn("overflowBannerHide", text)
        # Banner is the visible P-5 feedback (not silent).
        self.assertIn("overflowBannerVisible", text)
        self.assertIn("小部件配置超限", text)

    def test_mask_replaces_old_region_tree(self) -> None:
        text = HOST.read_text(encoding="utf-8")
        # Old mask region tree is destroyed on replacement (no QObject leak).
        self.assertIn("oldMask.destroy()", text)
        self.assertIn("function updateMask()", text)

    def test_persist_only_on_completed_operations(self) -> None:
        text = HOST.read_text(encoding="utf-8")
        # A-C5: write once per completed operation; no writes during drag.
        self.assertIn("function persistConfig()", text)
        # P-7 early-exit gate: no writes before initial load completes.
        self.assertIn("if (!root.loadingComplete)", text)
        self.assertIn("return;", text)
        self.assertNotIn("onPressed", text)
        self.assertNotIn("onPositionChanged", text)


class WidgetGridContractTests(unittest.TestCase):
    def test_grid_limits_aligned_with_region_cap(self) -> None:
        # P-5: region cap 32; one region per widget, per-screen grid ≤ 16.
        text = GRID.read_text(encoding="utf-8")
        self.assertIn("LIMIT_ITEMS = 24", text)
        self.assertIn("GRID_COLS = 4", text)
        self.assertIn("GRID_ROWS = 6", text)
        # The grid must not define its own region-limit constant (the single
        # cap source lives in niri tahoe_glass; a parallel constant would
        # drift). A comment mention is fine — it documents the shared cap.
        self.assertNotIn("var LIMIT_REGIONS", text)


class WidgetA3ContractTests(unittest.TestCase):
    """A3 contract guards: first widget batch (weather/calendar/system-monitor),
    real host-visible gate, and SystemStats gated on host visibility."""

    def test_catalog_ships_first_batch(self) -> None:
        text = HOST.read_text(encoding="utf-8")
        for key, source in (
            ("battery", "BatteryWidget.qml"),
            ("weather", "WeatherWidget.qml"),
            ("calendar", "CalendarWidget.qml"),
            ("system-monitor", "SystemMonitorWidget.qml"),
        ):
            self.assertIn(f'"{key}": {{ "source": "{source}"', text, msg=key)
            self.assertTrue((WIDGETS / source).is_file(), msg=source)

    def test_host_visible_gate_is_real(self) -> None:
        # A3 判据「宿主隐藏时所有小部件刷新停止」：基类门控 =
        # hostVisible && !previewMode；宿主以绑定（非一次性初值）注入
        # root.visible，隐藏后门控实时跟随。
        base = WIDGET_BASE.read_text(encoding="utf-8")
        self.assertIn("dataRefreshActive: root.hostVisible && !root.previewMode", base)
        host = HOST.read_text(encoding="utf-8")
        self.assertIn("readonly property bool hostVisible: root.visible", host)
        self.assertIn(
            "obj.hostVisible = Qt.binding(function() { return root.hostVisible; });",
            host,
        )

    def test_system_stats_gated_on_host_visibility(self) -> None:
        # A3 前置：SystemStats 门控于宿主可见性（roadmap 明示），`active`
        # 仍是唯一开关，无平行路径。
        # 门控开关的单一属主是 shell.qml（active 绑定所在处）；服务本身
        # 只暴露 active 属性，不新增第二套开关（G-6）。
        shell = (ROOT / "shell.qml").read_text(encoding="utf-8")
        self.assertIn("active: shell.leftSidebarOpen || systemStats.widgetDemand", shell)
        self.assertIn("function setWidgetDemand(", shell)
        self.assertIn("systemStats.widgetDemandScreens", shell)
        stats = (ROOT / "services" / "SystemStats.qml").read_text(encoding="utf-8")
        self.assertIn("property bool active", stats)
        self.assertEqual(stats.count("property bool active"), 1)
        host = HOST.read_text(encoding="utf-8")
        self.assertIn("property bool systemStatsDemand", host)
        self.assertIn('widgetInstances["system-monitor"]', host)
        self.assertIn("onSystemStatsDemandChanged: systemStats.setWidgetDemand(", shell)
        self.assertIn("Component.onDestruction: {", shell)
        self.assertIn("systemStats.setWidgetDemand(widgetHost.screenKey, false);", shell)

    def test_services_injected_into_widgets(self) -> None:
        shell = (ROOT / "shell.qml").read_text(encoding="utf-8")
        self.assertIn("weatherService: weather", shell)
        self.assertIn("systemStatsService: systemStats", shell)
        host = HOST.read_text(encoding="utf-8")
        self.assertIn("props.weatherService = root.weatherService", host)
        self.assertIn("props.systemStatsService = root.systemStatsService", host)
        for source, prop in (
            ("WeatherWidget.qml", "weatherService"),
            ("SystemMonitorWidget.qml", "systemStatsService"),
        ):
            text = (WIDGETS / source).read_text(encoding="utf-8")
            self.assertIn(f"property var {prop}", text, msg=source)

    def test_weather_and_system_monitor_no_self_built_polling(self) -> None:
        # A-C3: 天气/系统监控无 Timer（数据源只读注入）。
        for name in ("WeatherWidget.qml", "SystemMonitorWidget.qml"):
            text = (WIDGETS / name).read_text(encoding="utf-8")
            self.assertNotIn("Timer {", text, msg=name)
            self.assertNotIn("repeat: true", text, msg=name)

    def test_calendar_single_minute_aligned_gated_timer(self) -> None:
        # A-C3 / roadmap A3：日历唯一 Timer 为分钟对齐刷新（借鉴
        # DynamicIsland msecsToNextMinute），门控于 dataRefreshActive。
        text = (WIDGETS / "CalendarWidget.qml").read_text(encoding="utf-8")
        self.assertEqual(text.count("Timer {"), 1)
        self.assertEqual(text.count("repeat: true"), 1)
        self.assertIn("running: root.dataRefreshActive", text)
        self.assertIn("msecsToNextMinute", text)

    def test_live_snapshot_gate_in_new_widgets(self) -> None:
        # 宿主隐藏 → 锁存快照（与 BatteryWidget 同模式），不直接追服务事件。
        for name in ("WeatherWidget.qml", "SystemMonitorWidget.qml"):
            text = (WIDGETS / name).read_text(encoding="utf-8")
            self.assertIn("readonly property bool live: root.dataRefreshActive", text, msg=name)
            self.assertIn("onLiveChanged", text, msg=name)
            self.assertIn("function latchSnapshot()", text, msg=name)

    def test_calendar_uses_pure_js_logic(self) -> None:
        text = (WIDGETS / "CalendarWidget.qml").read_text(encoding="utf-8")
        self.assertIn('import "CalendarLogic.js" as CalendarLogic', text)
        self.assertIn("CalendarLogic.monthGrid", text)
        self.assertIn("CalendarLogic.todayDayLabel", text)

    def test_host_visible_follows_widget_count(self) -> None:
        # A3 判据「宿主隐藏时刷新停止」的真实触发路径：宿主 visible 跟随
        # 实例数（无小部件 → 隐藏 → hostVisible=false → 门控生效）。
        text = HOST.read_text(encoding="utf-8")
        self.assertIn("visible: root.widgetInstancesCount > 0", text)
        self.assertIn("property int widgetInstancesCount: 0", text)
        self.assertIn("root.widgetInstancesCount = Object.keys(root.widgetInstances).length;", text)
        self.assertIn("onHostVisibleChanged: root.refreshSystemStatsDemand()", text)

    def test_overflow_count_is_per_screen_removed(self) -> None:
        # P-5 横幅数学：未显示数 = 本屏清洗剔除（越界/重叠/重复）。
        # 禁止把全文件条目数与每屏 LIMIT 混算（单屏双计 + 多屏假阳性）。
        text = HOST.read_text(encoding="utf-8")
        self.assertIn("root.overflowCount = state.removed.length;", text)
        self.assertNotIn("totalEntryCount", text)
        self.assertIn("小部件配置超限", text)

    def test_catalog_default_size(self) -> None:
        # addWidget / A4 库 tab 的默认规格：天气/日历为 medium（按 small
        # 创建会挤压布局），电池/系统监控 small。
        text = HOST.read_text(encoding="utf-8")
        for key, size in (
            ("battery", "small"),
            ("weather", "medium"),
            ("calendar", "medium"),
            ("system-monitor", "small"),
        ):
            self.assertIn(f'"{key}": {{ "source": ', text, msg=key)
            self.assertIn(f'"defaultSize": "{size}"', text, msg=key)
        self.assertIn('var size = String(catalog.defaultSize || "small");', text)

    def test_widget_size_derived_from_span(self) -> None:
        # G-6 / 正确性：实例的 widgetSize 必须从跨度经 WidgetGrid.js 唯一
        # 来源推导；gridState 条目不带 size 字段，直接读 entry.size 会恒为
        # small（实测 medium 小部件被报成 small）。
        text = HOST.read_text(encoding="utf-8")
        self.assertIn('"widgetSize": Grid.sizeForSpan(entry.cols, entry.rows)', text)
        self.assertNotIn('"widgetSize": String(entry.size', text)

    def test_weather_reuses_weather_codes(self) -> None:
        text = (WIDGETS / "WeatherWidget.qml").read_text(encoding="utf-8")
        self.assertIn('import "../WeatherCodes.js" as WeatherCodes', text)
        self.assertIn("WeatherCodes.materialIcon", text)
        self.assertIn("MeteoIcon", text)
