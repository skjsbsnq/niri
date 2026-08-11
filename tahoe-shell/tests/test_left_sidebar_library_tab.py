"""A4 contract tests: sidebar third tab (widget library).

Source-level guards (repo style, same as test_left_sidebar_widgets.py) for
the A4 third-tab addition path:

1. SEGMENT (A-C7): the segmented control is a three-way split; thumb targets
   align to thirds; existing two tabs keep their labels and the
   currentTabChangeRequested round-trip.
2. LIBRARY TAB: a LeftSidebarWidgetLibrary page exists with name + sizes
   entries and an addRequested signal.
3. REGISTRY (G-6): widgetCatalog in WidgetHost.qml is the single registry;
   every entry declares sizes (containing defaultSize); the sidebar receives
   it by injection, never a second copy.
4. ADD PATH (roadmap A4): click -> onAddWidgetRequested -> widgetHost.addWidget;
   success closes the sidebar; no empty slot -> widgetAddFailed feedback.
5. CONSTRAINTS: no polling timers, no hardcoded animation durations (P-3),
   no drag/drop machinery (A-C2 does not apply here but must not creep in),
   no SpringAnimation on the new page.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SIDEBAR = ROOT / "components" / "LeftSidebar.qml"
LIBRARY = ROOT / "components" / "LeftSidebarWidgetLibrary.qml"
HOST = ROOT / "components" / "widgets" / "WidgetHost.qml"
SHELL_QML = ROOT / "shell.qml"


class LeftSidebarLibraryTabTests(unittest.TestCase):
    def test_segment_control_is_three_way(self) -> None:
        text = SIDEBAR.read_text(encoding="utf-8")
        # Thumb geometry: one third each (margins 2px each side).
        self.assertIn("width: (parent.width - 4) / 3", text)
        # Three labels with the new third tab.
        self.assertGreaterEqual(text.count("SegmentLabel {"), 3)
        self.assertIn('label: "系统"', text)
        self.assertIn('label: "天气"', text)
        self.assertIn('label: "小部件"', text)
        # Thumb positions: system/weather/widgets at 0/1/2 widths.
        target = re.search(
            r"function targetXFor\(tab\) \{(?P<body>[\s\S]*?)\n\s*\}",
            text,
        )
        self.assertIsNotNone(target)
        assert target
        self.assertIn('tab === "widgets" ? width * 2', target.group("body"))
        self.assertIn('tab === "weather" ? width', target.group("body"))
        # Click partition: three equal zones.
        click = re.search(
            r"onClicked: function\(mouse\) \{(?P<body>[\s\S]*?)\n\s*\}",
            text,
        )
        self.assertIsNotNone(click)
        assert click
        self.assertIn("mouse.x < width / 3", click.group("body"))
        self.assertIn("mouse.x < width * 2 / 3", click.group("body"))
        self.assertIn('"widgets"', click.group("body"))
        # Tab round-trip to shell is preserved.
        self.assertIn("root.currentTabChangeRequested(tab)", text)

    def test_library_page_present_with_add_signal(self) -> None:
        self.assertTrue(LIBRARY.is_file(), "LeftSidebarWidgetLibrary.qml must exist")
        lib = LIBRARY.read_text(encoding="utf-8")
        self.assertIn("signal addRequested(string id, string size)", lib)
        self.assertIn("property var widgetCatalog", lib)
        self.assertIn("property bool addFailed", lib)
        # Already-present widgets are marked and not re-clickable (duplicate ids
        # are rejected by the host grid; without the marker a re-click would
        # misreport "桌面已满").
        self.assertIn("property var presentWidgets", lib)
        self.assertIn("已添加", lib)
        self.assertIn("enabled: !present", lib)
        self.assertIn("function refreshPresent", lib)
        # Installed as the third tab in the sidebar.
        sidebar = SIDEBAR.read_text(encoding="utf-8")
        self.assertIn("LeftSidebarWidgetLibrary {", sidebar)
        self.assertIn('root.currentTab === "widgets"', sidebar)
        self.assertIn("signal addWidgetRequested(string id, string size)", sidebar)
        # A5 gallery: each entry renders a real WidgetPreview with a selectable
        # size; the size flows through addRequested -> addWidgetRequested.
        self.assertIn("WidgetPreview {", lib)
        self.assertIn('source: String(modelData.source || "")', lib)
        self.assertIn("widgetSize: selectedSize", lib)
        self.assertIn("SizeChip {", lib)
        self.assertIn("onClicked: selectedSize = \"small\"", lib)
        self.assertIn("onClicked: selectedSize = \"medium\"", lib)
        self.assertIn("onClicked: selectedSize = \"large\"", lib)

    def test_registry_single_source_with_sizes(self) -> None:
        host = HOST.read_text(encoding="utf-8")
        # Exactly one catalog definition (G-6): the host owns it, the sidebar
        # injects it. ("widgetCatalog" also appears in createWidgetInstance /
        # addWidget lookups, so assert on the definition form, not the word.)
        self.assertEqual(host.count("property var widgetCatalog"), 1)
        catalog = re.search(
            r"readonly property var widgetCatalog: \(\{(?P<body>[\s\S]*?)\n\s*\}\)",
            host,
        )
        self.assertIsNotNone(catalog)
        assert catalog
        body = catalog.group("body")
        # A7: 每个条目都声明三档（small/medium/large），库 tab 标注的
        # 可选尺寸与实际可切换档位一致（roadmap A7 完成判据）。
        self.assertEqual(body.count('"sizes": ["small", "medium", "large"]'), 4)
        # Every entry has sizes and defaultSize is inside sizes.
        for entry in re.finditer(
            r'"([a-z-]+)":\s*\{\s*"source":\s*"[^"]+",\s*"name":\s*"[^"]+",\s*"sizes":\s*\[(?P<sizes>[^\]]+)\],\s*"defaultSize":\s*"(?P<default>[a-z]+)"\s*\}',
            body,
        ):
            sizes = re.findall(r'"([a-z]+)"', entry.group("sizes"))
            self.assertIn(entry.group("default"), sizes, entry.group(1))
        # A5: library entries must carry source + defaultSize from the host
        # catalog (the gallery previews are created from those, never from a
        # second registry).
        lib = LIBRARY.read_text(encoding="utf-8")
        self.assertIn('"source": String(entry.source || "")', lib)
        self.assertIn('"defaultSize": String(entry.defaultSize || "small")', lib)
        # Sidebar must consume the host catalog/instances, not define its own.
        shell = SHELL_QML.read_text(encoding="utf-8")
        self.assertIn("widgetCatalog: widgetHost.widgetCatalog", shell)
        self.assertIn("widgetInstances: widgetHost.widgetInstances", shell)
        sidebar = SIDEBAR.read_text(encoding="utf-8")
        self.assertNotIn("readonly property var widgetCatalog", sidebar)
        self.assertIn("property var widgetInstances: ({})", sidebar)

    def test_config_persistence_single_owner_and_add_gate(self) -> None:
        """A4 review fixes: C1 startup race gate + C2 single owner for
        widgets.json (multi-screen stale-cache overwrite)."""
        host = HOST.read_text(encoding="utf-8")
        shell = SHELL_QML.read_text(encoding="utf-8")
        # C1: addWidget must not fake-success before the initial load.
        add = host.split("function addWidget(id, size) {", 1)[1]
        add = add.split("function removeWidget", 1)[0]
        self.assertIn("!root.loadingComplete", add)
        self.assertIn("return false", add)
        # C2: exactly one FileView owns widgets.json (shell root), hosts inject
        # it; the host no longer declares its own FileView (stale caches).
        self.assertEqual(shell.count("FileView {"), 1)
        self.assertIn("id: widgetConfigFile", shell)
        self.assertIn('path: Quickshell.stateDir + "/widgets.json"', shell)
        self.assertIn("property string widgetConfigText", shell)
        self.assertIn("property bool widgetConfigLoaded", shell)
        self.assertIn("configFile: widgetConfigFile", shell)
        self.assertIn("configLoaded: shell.widgetConfigLoaded", shell)
        self.assertIn("onPersistConfigRequested:", shell)
        self.assertIn("widgetConfigFile.setText(next)", shell)
        self.assertNotIn("FileView {", host)
        self.assertIn("property var configFile: null", host)
        self.assertIn("property bool configLoaded: false", host)
        self.assertIn("onConfigLoadedChanged", host)
        self.assertIn("signal persistConfigRequested(string screenKey, var configs)", host)

    def test_shell_add_path_closes_on_success_feedback_on_full(self) -> None:
        shell = SHELL_QML.read_text(encoding="utf-8")
        # Handler is wired on the sidebar instance; the selected preview size
        # is forwarded to the host.
        self.assertIn("onAddWidgetRequested: function(id, size)", shell)
        self.assertIn("widgetHost.addWidget(id, size)", shell)
        self.assertIn("shell.closeLeftSidebar()", shell)
        self.assertIn("leftSidebar.widgetAddFailed = true", shell)
        # P-9: the asserted call form must be defined in its scope.
        host = HOST.read_text(encoding="utf-8")
        self.assertIn("function addWidget(id, size)", host)

    def test_library_page_constraints(self) -> None:
        lib = LIBRARY.read_text(encoding="utf-8")
        # No polling: any Timer must be a single-shot feedback timer ≥ 1s.
        for match in re.finditer(r"Timer\s*\{[^}]*?interval:\s*(\d+)[^}]*?repeat:\s*(true|false)", lib, re.S):
            value = int(match.group(1))
            self.assertGreaterEqual(value, 1000)
            self.assertEqual(match.group(2), "false")
        # P-3: no hardcoded animation duration literals.
        self.assertNotRegex(lib, r"duration:\s*[0-9]+")
        # P-1: no springs anywhere on the new page.
        self.assertNotIn("SpringAnimation", lib)
        # No drag/drop machinery and no self-spawned processes.
        for forbidden in ("DragHandler", "DropArea", "Drag.active", "Process {"):
            self.assertNotIn(forbidden, lib)
        # Failure feedback is real, visible, and not misleading about the
        # reason (no-space / config-not-ready / unknown entry all show it).
        self.assertIn("无法添加小部件", lib)
        self.assertIn("property bool bannerVisible", lib)
        # Sizes shown as text next to the name for single-size entries
        # (A4 list item content kept); multi-size entries expose size chips.
        self.assertIn("尺寸：", lib)
        self.assertIn("readonly property bool multiSize", lib)
        self.assertIn("property string selectedSize", lib)
        # Chips only render declared catalog sizes (no invented third path).
        self.assertIn("visible: hasSize(\"small\")", lib)
        self.assertIn("visible: hasSize(\"medium\")", lib)
        self.assertIn("visible: hasSize(\"large\")", lib)
        # Null-injected catalog is tolerated (standalone preview / tests).
        self.assertIn("Object.keys(root.widgetCatalog || {})", lib)

    def test_existing_tab_wiring_intact(self) -> None:
        sidebar = SIDEBAR.read_text(encoding="utf-8")
        # System/weather pages still installed with their original bindings.
        self.assertIn('root.currentTab === "system"', sidebar)
        self.assertIn('root.currentTab === "weather"', sidebar)
        self.assertIn("openProcessMenuRequested", sidebar)
        self.assertIn("onOpenWeatherSettingsRequested", sidebar)


if __name__ == "__main__":
    unittest.main()
