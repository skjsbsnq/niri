"""TahoeSymbol rendering and icon-system regression coverage."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ROOT / "components"
ASSETS_SYMBOLS = ROOT / "assets" / "icons" / "symbols"
SYMBOL_QML = COMPONENTS / "TahoeSymbol.qml"
SYMBOLS_JS = COMPONENTS / "TahoeSymbols.js"


class TahoeSymbolMigrationTests(unittest.TestCase):
    def test_bundled_font_is_restored(self) -> None:
        fonts_dir = ROOT / "assets" / "fonts"
        font = fonts_dir / "MaterialIconsRound.ttf"
        self.assertTrue(font.exists(), "the icon font must ship with the shell")
        self.assertGreater(font.stat().st_size, 300_000)

    def test_tahoe_symbol_component_exists_with_discipline(self) -> None:
        text = SYMBOL_QML.read_text(encoding="utf-8")
        self.assertIn("FontLoader", text)
        self.assertIn("MaterialIconsRound.ttf", text)
        self.assertIn("Symbols.glyph(root.name)", text)
        self.assertIn("Text.QtRendering", text)
        self.assertIn("horizontalAlignment: Text.AlignHCenter", text)
        self.assertIn("verticalAlignment: Text.AlignVCenter", text)
        self.assertIn("property real opticalOffsetY: 1", text)
        self.assertIn("anchors.verticalCenterOffset: root.opticalOffsetY", text)
        self.assertIn('source: root.usesFontGlyph ? "" : root.resolvedSource', text)
        self.assertIn("sourceSize", text)
        self.assertIn("asynchronous", text)
        self.assertIn("iconPath", text)
        self.assertIn("TahoeSymbols.js", text)
        # sourceSize budget ≤128; decode ≥4× display (min 64) for sharp small icons
        self.assertIn("Math.min(128", text)
        self.assertIn("Math.ceil(display * 4)", text)
        self.assertIn("property bool mipmap: false", text)
        self.assertIn("blurEnabled: false", text)

    def test_symbol_png_assets_and_registry(self) -> None:
        self.assertTrue(ASSETS_SYMBOLS.is_dir())
        pngs = list(ASSETS_SYMBOLS.glob("*.png"))
        self.assertGreaterEqual(len(pngs), 150, f"expected ≥150 symbol PNGs, got {len(pngs)}")
        js = SYMBOLS_JS.read_text(encoding="utf-8")
        self.assertIn("CodepointToName", js)
        self.assertIn("fileName", js)
        self.assertIn("resolveName", js)
        self.assertIn("function glyph(value)", js)
        # Spot-check critical UI symbols exist on disk
        for name in ("wifi", "search", "notifications", "close", "check", "settings", "cloud"):
            self.assertTrue((ASSETS_SYMBOLS / f"{name}.png").exists(), name)
            self.assertIn(f'"{name}"', js)

    def test_runtime_qml_uses_tahoe_symbol(self) -> None:
        hits = 0
        for path in COMPONENTS.rglob("*.qml"):
            text = path.read_text(encoding="utf-8", errors="replace")
            hits += text.count("TahoeSymbol")
        self.assertGreaterEqual(hits, 40, f"expected widespread TahoeSymbol usage, got {hits}")

    def test_all_runtime_material_codepoints_exist_in_bundled_font(self) -> None:
        font_path = ROOT / "assets" / "fonts" / "MaterialIconsRound.ttf"
        font = TTFont(font_path)
        cmap = font.getBestCmap()
        referenced: set[int] = set()
        for path in COMPONENTS.rglob("*.qml"):
            text = path.read_text(encoding="utf-8", errors="replace")
            referenced.update(
                int(value, 16)
                for value in re.findall(r"\\u([ef][0-9a-fA-F]{3})", text)
            )
        missing = sorted(codepoint for codepoint in referenced if codepoint not in cmap)
        self.assertGreater(len(referenced), 100)
        self.assertEqual(missing, [], f"missing icon codepoints: {[hex(value) for value in missing]}")

    def test_no_direct_material_font_rendering_outside_symbol_component(self) -> None:
        pattern = re.compile(r'font\.family:\s*["\']Material')
        offenders = []
        for path in ROOT.rglob("*.qml"):
            if "docs" in path.parts:
                continue
            if path == SYMBOL_QML:
                continue
            if pattern.search(path.read_text(encoding="utf-8", errors="replace")):
                offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual(offenders, [])

    def test_dynamic_island_osd_uses_symbol_in_v2_scene(self) -> None:
        # T13: ring layout removed; OSD lives in DynamicIslandOsdView with TahoeSymbol.
        content = (COMPONENTS / "DynamicIslandContent.qml").read_text(encoding="utf-8")
        osd = (COMPONENTS / "DynamicIslandOsdView.qml").read_text(encoding="utf-8")
        self.assertIn("DynamicIslandOsdView", content)
        self.assertIn("TahoeSymbol", osd)
        self.assertIn("size: 20", osd)
        self.assertNotIn("id: osdRing", content)
        self.assertNotIn("Canvas", osd)

    def test_popup_icon_alignment_and_topbar_battery_scale(self) -> None:
        clipboard = (COMPONENTS / "ClipboardPopup.qml").read_text(encoding="utf-8")
        topbar = (COMPONENTS / "TopBar.qml").read_text(encoding="utf-8")
        self.assertIn("Layout.topMargin: 2", clipboard)
        self.assertIn("Layout.preferredWidth: 24", topbar)
        self.assertIn("width: 20", topbar)
        self.assertIn("height: 11", topbar)

    def test_fan_is_bitmap_only_not_toys_car_glyph(self) -> None:
        """Fan UI must use a real fan.png; e332 is Material toys (car), not a fan."""
        js = SYMBOLS_JS.read_text(encoding="utf-8")
        self.assertIn("BitmapOnlyNames", js)
        self.assertIn('"fan": true', js)
        self.assertIn("function isBitmapOnly", js)
        # Must not reintroduce the toys/car codepoint as fan.
        self.assertNotRegex(js, r'"e332"\s*:\s*"fan"')

        fan_png = ASSETS_SYMBOLS / "fan.png"
        self.assertTrue(fan_png.exists())

        # Pixel-level guard: the historical bug shipped toys/car as fan.png.
        # A car silhouette is bottom-heavy (body + wheels); a mode_fan glyph is
        # center-heavy with blades around a hub. Reject car-like mass distribution.
        try:
            from PIL import Image
        except ImportError as exc:  # pragma: no cover
            self.skipTest(f"Pillow required for fan asset check: {exc}")

        im = Image.open(fan_png).convert("RGBA")
        self.assertEqual(im.size, (128, 128))
        w, h = im.size
        opaque = [
            (x, y)
            for y in range(h)
            for x in range(w)
            if im.getpixel((x, y))[3] > 160
        ]
        self.assertGreater(len(opaque), 800, "fan.png looks empty")
        # Pure white silhouette (MultiEffect colorization contract).
        sample = opaque[:: max(1, len(opaque) // 40)]
        for x, y in sample:
            r, g, b, a = im.getpixel((x, y))
            self.assertGreaterEqual(r, 240)
            self.assertGreaterEqual(g, 240)
            self.assertGreaterEqual(b, 240)

        bottom = sum(1 for x, y in opaque if y >= int(h * 0.70))
        center = sum(1 for x, y in opaque if int(h * 0.30) <= y < int(h * 0.70))
        # Car assets put most mass in the lower body; fan blades concentrate mid-frame.
        self.assertGreater(center, bottom * 1.5, "fan.png mass looks car-like (bottom-heavy)")

        topbar = (COMPONENTS / "TopBar.qml").read_text(encoding="utf-8")
        fan_popup = (COMPONENTS / "FanPopup.qml").read_text(encoding="utf-8")
        # Actual glyph escapes only — comments may still mention e332 as the
        # toys/car pitfall we deliberately avoid.
        codepoint_use = re.compile(r'\\ue332|"e332"')
        for text, label in ((topbar, "TopBar"), (fan_popup, "FanPopup")):
            self.assertIn('name: "fan"', text, label)
            self.assertIsNone(codepoint_use.search(text), f"{label} still uses e332 glyph")


if __name__ == "__main__":
    unittest.main()
