"""A5 contract tests: widget library live preview gallery.

Source-level guards (repo style) for upgrading the A4 text list into a
gallery of real widget previews:

1. PREVIEW INSTANCE (A-C3 / A-0 #1): WidgetPreview.qml instantiates the real
   widget component with previewMode=true, so data refresh is disabled
   (Widget.qml dataRefreshActive = hostVisible && !previewMode) — no timers,
   no spawned processes, no hardcoded durations, no springs.
2. SINGLE SOURCE (G-6): the preview consumes source/widgetSize/cellSize from
   the host catalog (via the library entries); it never maintains a second
   registry or a second size->span table (WidgetGrid.js stays the only
   mapping owner).
3. SIZE FLOW: gallery card selection -> addRequested(id, size) ->
   addWidgetRequested(id, size) -> WidgetHost.addWidget(id, size), which
   validates the size against catalog.sizes (A7 tier contract).
4. P-9: every asserted <id>.<fn>(...) call form is locked to its definition
   scope.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ROOT / "components"
LIBRARY = COMPONENTS / "LeftSidebarWidgetLibrary.qml"
PREVIEW = COMPONENTS / "WidgetPreview.qml"
SIDEBAR = COMPONENTS / "LeftSidebar.qml"
HOST = COMPONENTS / "widgets" / "WidgetHost.qml"
SHELL_QML = ROOT / "shell.qml"


class WidgetPreviewContractTests(unittest.TestCase):
    def test_preview_component_exists_and_creates_real_widget(self) -> None:
        self.assertTrue(PREVIEW.is_file(), "WidgetPreview.qml must exist")
        text = PREVIEW.read_text(encoding="utf-8")
        self.assertIn("import QtQuick", text)
        # It instantiates the widget source from the host catalog path.
        self.assertIn('Qt.createComponent("widgets/" + root.source, root)', text)
        # previewMode=true is the A-C3 gate: data refresh stays off.
        self.assertIn('"previewMode": true', text)
        # Geometry/specs follow the preview host via bindings (size switching
        # must not rebuild the instance).
        self.assertIn("obj.width = Qt.binding", text)
        self.assertIn("obj.height = Qt.binding", text)
        self.assertIn("obj.widgetSize = Qt.binding", text)
        self.assertIn("obj.cellSize = Qt.binding", text)
        # P-9: the load() call form is defined in this scope.
        self.assertIn("Component.onCompleted: root.load()", text)
        self.assertIn("function load()", text)
        # P1 (adversarial review): initialization fires both onSourceChanged
        # and onCompleted -> load() must be guarded by loadedSource so each
        # preview instantiates exactly once (no create/destroy churn).
        self.assertIn("property string loadedSource: """, text)
        self.assertIn("if (root.loadedSource === src)", text)
        self.assertIn("root.loadedSource = src;", text)

    def test_preview_injects_services_by_widget_id(self) -> None:
        text = PREVIEW.read_text(encoding="utf-8")
        # Same singleton batch as desktop instances; only the needed one is
        # injected (creating with a foreign property would fail).
        self.assertIn('if (sid === "battery")', text)
        self.assertIn("props.batteryService = root.batteryService", text)
        self.assertIn('else if (sid === "weather")', text)
        self.assertIn("props.weatherService = root.weatherService", text)
        self.assertIn('else if (sid === "system-monitor")', text)
        self.assertIn("props.systemStatsService = root.systemStatsService", text)

    def test_preview_no_polling_no_process_no_springs_no_durations(self) -> None:
        # A-C3 / P-1 / P-3: the preview path must not add refresh machinery.
        text = PREVIEW.read_text(encoding="utf-8")
        self.assertNotIn("Timer {", text)
        self.assertNotIn("repeat: true", text)
        self.assertNotIn("Process {", text)
        self.assertNotIn("SpringAnimation", text)
        self.assertNotIn("DragHandler", text)
        self.assertNotIn("DropArea", text)
        match = re.compile(r"duration:\s*[0-9]+").search(text)
        self.assertIsNone(match, "WidgetPreview hardcoded duration")
        # No second registry or size table inside the preview container.
        self.assertNotIn("widgetCatalog", text)
        self.assertNotIn("colsForSize", text)
        self.assertNotIn("rowsForSize", text)

    def test_preview_source_is_relative_to_widgets_dir(self) -> None:
        # WidgetHost catalog sources are relative to components/widgets/;
        # the preview component lives in components/ and must prepend the
        # widgets/ path (a bare source would resolve to components/<source>).
        text = PREVIEW.read_text(encoding="utf-8")
        self.assertIn('"widgets/" + root.source', text)


class WidgetLibraryGalleryContractTests(unittest.TestCase):
    def test_gallery_renders_preview_per_entry(self) -> None:
        lib = LIBRARY.read_text(encoding="utf-8")
        # One real preview per catalog entry (source carried from catalog).
        self.assertIn('"source": String(entry.source || "")', lib)
        self.assertIn("WidgetPreview {", lib)
        self.assertIn("widgetId: String(modelData.id || \"\")", lib)
        self.assertIn("source: String(modelData.source || \"\")", lib)
        self.assertIn("widgetSize: selectedSize", lib)
        self.assertIn("cellSize: root.previewCell", lib)
        # The library injects the same services the sidebar received.
        self.assertIn("batteryService: root.batteryService", lib)
        self.assertIn("weatherService: root.weatherService", lib)
        self.assertIn("systemStatsService: root.systemStatsService", lib)

    def test_gallery_sizes_use_widget_grid_single_source(self) -> None:
        lib = LIBRARY.read_text(encoding="utf-8")
        # Size -> span mapping must come from WidgetGrid.js (G-6), not a
        # second copy inside the gallery.
        self.assertIn('import "widgets/WidgetGrid.js" as Grid', lib)
        self.assertIn("Grid.colsForSize(selectedSize)", lib)
        self.assertIn("Grid.rowsForSize(selectedSize)", lib)

    def test_selected_size_survives_qml_model_array_wrapping(self) -> None:
        # Live probe found: Repeater modelData wraps JS arrays, so
        # Array.isArray(modelData.sizes) is false and a plain initializer
        # falls back to "small". The gallery must normalize via sizeList and
        # compute the initial size as a binding (modelData is injected after
        # property initialization).
        lib = LIBRARY.read_text(encoding="utf-8")
        self.assertIn("function sizeList(sizes)", lib)
        self.assertIn('typeof sizes.length === "number"', lib)
        self.assertIn("property string selectedSize: root.initialSize(modelData)", lib)
        self.assertIn("function initialSize(entry)", lib)
        self.assertIn("root.sizeList(modelData.sizes).length > 1", lib)
        self.assertIn("var sizes = root.sizeList(modelData.sizes);", lib)

    def test_size_flow_reaches_host_add_path(self) -> None:
        # Signal chain: library -> sidebar -> shell -> host, all carrying size.
        lib = LIBRARY.read_text(encoding="utf-8")
        sidebar = SIDEBAR.read_text(encoding="utf-8")
        shell = SHELL_QML.read_text(encoding="utf-8")
        host = HOST.read_text(encoding="utf-8")
        self.assertIn("signal addRequested(string id, string size)", lib)
        self.assertIn("root.addRequested(String(modelData.id || \"\"), selectedSize)", lib)
        self.assertIn("signal addWidgetRequested(string id, string size)", sidebar)
        self.assertIn("root.addWidgetRequested(id, size)", sidebar)
        self.assertIn("onAddWidgetRequested: function(id, size)", shell)
        self.assertIn("widgetHost.addWidget(id, size)", shell)
        # P-9: definitions locked to their scopes.
        self.assertIn("function addWidget(id, size)", host)
        self.assertIn("signal addRequested(string id, string size)", lib)
        self.assertIn("signal addWidgetRequested(string id, string size)", sidebar)

    def test_gallery_keeps_present_and_failure_feedback(self) -> None:
        lib = LIBRARY.read_text(encoding="utf-8")
        # A4 behavior preserved: present widgets are marked and not clickable,
        # failure feedback remains visible.
        self.assertIn("已添加", lib)
        self.assertIn("enabled: !present", lib)
        self.assertIn("无法添加小部件", lib)
        self.assertIn("property bool bannerVisible", lib)
        # Chips are disabled for present widgets too.
        self.assertIn("enabled: !present", lib)


if __name__ == "__main__":
    unittest.main()
