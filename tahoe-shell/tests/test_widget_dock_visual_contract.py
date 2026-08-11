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


class WidgetDockVisualContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.glass = GLASS_STYLE.read_text(encoding="utf-8")
        cls.widget = WIDGET.read_text(encoding="utf-8")
        cls.dock = DOCK.read_text(encoding="utf-8")

    def test_widget_uses_dense_static_macos_plate(self) -> None:
        self.assertIn(
            "property string material: GlassStyle.MaterialPanel",
            self.widget,
        )
        self.assertIn("fillColor: GlassStyle.FillWidget", self.widget)
        self.assertIn("strokeColor: GlassStyle.StrokeWidget", self.widget)
        self.assertIn("pressInteractionEnabled: false", self.widget)

        alpha, red, green, blue = qml_argb(self.glass, "FillWidget")
        self.assertGreaterEqual(alpha, 0xA6, "widget plate is too transparent")
        self.assertLessEqual(alpha, 0xCC, "widget plate became opaque")
        self.assertLessEqual(max(red, green, blue), 0x36)
        self.assertLessEqual(max(red, green, blue) - min(red, green, blue), 4)

    def test_widget_hairline_is_subtle_but_visible(self) -> None:
        alpha, red, green, blue = qml_argb(self.glass, "StrokeWidget")
        self.assertGreaterEqual(alpha, 0x20)
        self.assertLessEqual(alpha, 0x40)
        self.assertEqual((red, green, blue), (0xFF, 0xFF, 0xFF))

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
