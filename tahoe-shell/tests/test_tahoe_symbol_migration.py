"""T13: Material Icons → TahoeSymbol migration governance."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ROOT / "components"
ASSETS_SYMBOLS = ROOT / "assets" / "icons" / "symbols"
SHELL_QML = ROOT / "shell.qml"
SYMBOL_QML = COMPONENTS / "TahoeSymbol.qml"
SYMBOLS_JS = COMPONENTS / "TahoeSymbols.js"


class TahoeSymbolMigrationTests(unittest.TestCase):
    def test_no_material_icons_font_references_in_shell(self) -> None:
        """Acceptance: grep Material Icons over shell runtime sources is empty."""
        offenders: list[str] = []
        for path in ROOT.rglob("*"):
            if path.suffix not in {".qml", ".js"}:
                continue
            if "docs" in path.parts or "tests" in path.parts:
                continue
            # Registry comment may mention the source font; that's documentation only.
            if path.name == "TahoeSymbols.js":
                text = path.read_text(encoding="utf-8")
                # No live FontLoader / family string.
                self.assertNotIn('font.family: "Material Icons"', text)
                self.assertNotIn("FontLoader", text)
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            if "Material Icons" in text or "MaterialIcons" in text:
                offenders.append(str(path.relative_to(ROOT)))
            if "iconFont" in text:
                offenders.append(f"{path.relative_to(ROOT)}:iconFont")
        self.assertEqual(offenders, [], f"Material Icons residual: {offenders}")

    def test_fontloader_and_ttf_removed(self) -> None:
        shell = SHELL_QML.read_text(encoding="utf-8")
        self.assertNotIn("FontLoader", shell)
        self.assertNotIn("MaterialIconsRound", shell)
        fonts_dir = ROOT / "assets" / "fonts"
        self.assertFalse(
            (fonts_dir / "MaterialIconsRound.ttf").exists(),
            "Material Icons TTF must be removed after migration",
        )

    def test_tahoe_symbol_component_exists_with_discipline(self) -> None:
        text = SYMBOL_QML.read_text(encoding="utf-8")
        self.assertIn("ColorOverlay", text)
        self.assertIn("sourceSize", text)
        self.assertIn("asynchronous", text)
        self.assertIn("iconPath", text)
        self.assertIn("TahoeSymbols.js", text)
        # sourceSize budget ≤128
        self.assertIn("Math.min(128", text)

    def test_symbol_png_assets_and_registry(self) -> None:
        self.assertTrue(ASSETS_SYMBOLS.is_dir())
        pngs = list(ASSETS_SYMBOLS.glob("*.png"))
        self.assertGreaterEqual(len(pngs), 150, f"expected ≥150 symbol PNGs, got {len(pngs)}")
        js = SYMBOLS_JS.read_text(encoding="utf-8")
        self.assertIn("CodepointToName", js)
        self.assertIn("fileName", js)
        self.assertIn("resolveName", js)
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

    def test_no_font_family_material_in_qml(self) -> None:
        pattern = re.compile(r'font\.family:\s*["\']Material')
        offenders = []
        for path in ROOT.rglob("*.qml"):
            if "docs" in path.parts:
                continue
            if pattern.search(path.read_text(encoding="utf-8", errors="replace")):
                offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual(offenders, [])


if __name__ == "__main__":
    unittest.main()
