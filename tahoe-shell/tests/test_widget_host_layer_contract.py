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
        self.assertIn("LIMIT_ITEMS = 16", text)
        self.assertIn("GRID_COLS = 4", text)
        self.assertIn("GRID_ROWS = 4", text)
        # The grid must not define its own region-limit constant (the single
        # cap source lives in niri tahoe_glass; a parallel constant would
        # drift). A comment mention is fine — it documents the shared cap.
        self.assertNotIn("var LIMIT_REGIONS", text)
