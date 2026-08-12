from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
GLASS_STYLE = SHELL_ROOT / "components" / "TahoeGlass.js"
WIDGET = SHELL_ROOT / "components" / "widgets" / "Widget.qml"
DOCK = SHELL_ROOT / "components" / "Dock.qml"


def qml_argb(source: str, name: str) -> tuple[int, int, int, int]:
    match = re.search(
        rf'^var\s+{re.escape(name)}\s*=\s*"#([0-9a-fA-F]{{8}})";',
        source,
        re.MULTILINE,
    )
    if not match:
        raise AssertionError(f"missing QML color token {name}")
    encoded = match.group(1)
    return tuple(int(encoded[index:index + 2], 16) for index in (0, 2, 4, 6))


def widget_glass_pair(source: str, function: str) -> tuple[tuple[int, int, int, int], tuple[int, int, int, int]]:
    """Parse `function <fn>(darkMode) { return darkMode ? "#DDDDDDDD" : "#LLLLLLLL"; }`
    and return (dark, light) ARGB tuples."""
    match = re.search(
        rf'function\s+{re.escape(function)}\(darkMode\)\s*{{\s*'
        rf'return\s+darkMode\s+\?\s*"#([0-9a-fA-F]{{8}})"\s*:\s*"#([0-9a-fA-F]{{8}})";\s*}}',
        source,
        re.DOTALL,
    )
    if not match:
        raise AssertionError(f"missing adaptive glass function {function}")
    return (
        tuple(int(match.group(1)[i:i + 2], 16) for i in (0, 2, 4, 6)),
        tuple(int(match.group(2)[i:i + 2], 16) for i in (0, 2, 4, 6)),
    )


class WidgetDockVisualContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.glass = GLASS_STYLE.read_text(encoding="utf-8")
        cls.widget = WIDGET.read_text(encoding="utf-8")
        cls.dock = DOCK.read_text(encoding="utf-8")

    def test_widget_uses_adaptive_macos_glass(self) -> None:
        # A8: desktop widgets are macOS Sonoma/Sequoia adaptive glass — the
        # base must carry darkMode and feed fill/stroke/radius from
        # TahoeGlass.js single-source functions (no static plate tokens).
        self.assertIn("property bool darkMode: false", self.widget)
        self.assertIn(
            "property string material: GlassStyle.MaterialPanel",
            self.widget,
        )
        self.assertIn("fillColor: GlassStyle.widgetFill(root.darkMode)", self.widget)
        self.assertIn("strokeColor: GlassStyle.widgetStroke(root.darkMode)", self.widget)
        self.assertIn("radius: root.widgetRadius", self.widget)
        self.assertIn("regionRadius: root.widgetRadius", self.widget)
        self.assertIn("pressInteractionEnabled: false", self.widget)
        self.assertIn("GlassStyle.widgetRadius(root.widgetSize, Math.min(root.width, root.height))", self.widget)
        # G-6: old static dark-plate tokens must not survive alongside the
        # adaptive functions (single path).
        self.assertNotIn("FillWidget", self.glass)
        self.assertNotIn("StrokeWidget", self.glass)

    def test_widget_adaptive_fill_dark_is_glass_light_is_near_white(self) -> None:
        dark, light = widget_glass_pair(self.glass, "widgetFill")
        # Dark mode: translucent white glass (16–32%), not an opaque gray plate.
        self.assertGreaterEqual(dark[0], 0x26, "dark widget glass too transparent")
        self.assertLessEqual(dark[0], 0x50, "dark widget glass became opaque")
        self.assertEqual((dark[1], dark[2], dark[3]), (0xFF, 0xFF, 0xFF))
        # Light mode: near-white frosted card (macOS light appearance).
        self.assertGreaterEqual(light[0], 0xE0, "light widget glass too transparent")
        self.assertEqual((light[1], light[2], light[3]), (0xFF, 0xFF, 0xFF))

    def test_widget_hairline_adapts_to_appearance(self) -> None:
        dark, light = widget_glass_pair(self.glass, "widgetStroke")
        # Dark mode: subtle white hairline.
        self.assertGreaterEqual(dark[0], 0x20)
        self.assertLessEqual(dark[0], 0x50)
        self.assertEqual((dark[1], dark[2], dark[3]), (0xFF, 0xFF, 0xFF))
        # Light mode: subtle dark hairline.
        self.assertGreaterEqual(light[0], 0x1A)
        self.assertLessEqual(light[0], 0x40)
        self.assertLessEqual(max(light[1], light[2], light[3]), 0x10)

    def test_widget_radius_macos_curvature(self) -> None:
        # macOS small/medium cards: ~24% of the short edge, capped 40px;
        # large: ~14%, capped 48px.
        self.assertIn("function widgetRadius(size, minDim)", self.glass)
        self.assertIn('String(size || "") === "large"', self.glass)
        self.assertIn("Math.min(48, Math.round(m * 0.14))", self.glass)
        self.assertIn("Math.min(40, Math.round(m * 0.24))", self.glass)

    def test_widget_base_exposes_macos_text_scale(self) -> None:
        # Widgets must read the adaptive text palette from the base instead of
        # hardcoding white text (light appearance would be unreadable).
        self.assertIn("readonly property color textPrimary:", self.widget)
        self.assertIn('root.darkMode ? "#f5f7fb" : "#1d1d1f"', self.widget)
        self.assertIn("readonly property color textSecondary:", self.widget)
        self.assertIn("readonly property color textTertiary:", self.widget)

    def test_dock_hover_does_not_boost_whole_surface_material(self) -> None:
        self.assertNotIn("dockGlassInteraction", self.dock)
        dock_surface = re.search(
            r"GlassPanel\s*\{\s*id:\s*dockSurface(?P<body>.*?)\n\s*\}",
            self.dock,
            re.DOTALL,
        )
        self.assertIsNotNone(dock_surface)
        assert dock_surface
        self.assertIn("interaction: 0.0", dock_surface.group("body"))

    def test_dock_pointer_features_remain_connected(self) -> None:
        self.assertIn("property bool dockHovered: false", self.dock)
        self.assertIn("id: dockSurfaceHover", self.dock)
        self.assertIn("root.seedWaveFromSurfaceHover()", self.dock)
        self.assertIn("!root.pointerDragActive && iconMouse.containsMouse", self.dock)


if __name__ == "__main__":
    unittest.main()
