from __future__ import annotations

import importlib.util
import json
import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SHELL_ROOT.parent

TAHOE_GLASS_JS = SHELL_ROOT / "components" / "TahoeGlass.js"
NIRI_SETTINGS_QML = SHELL_ROOT / "services" / "NiriSettings.qml"
NIRI_SETTINGS_TOOL = SHELL_ROOT / "services" / "niri_settings_tool.py"
NIRI_CONFIG = REPO_ROOT / "config" / "niri" / "tahoe-phase0.kdl"
NIRI_CONFIG_TAHOE_GLASS = REPO_ROOT / "niri" / "niri-config" / "src" / "tahoe_glass.rs"
GLASS_SCHEMA_ARTIFACT = (
    REPO_ROOT / "niri" / "niri-config" / "generated" / "glass_schema_defaults.json"
)
GOVERNANCE_DOC = SHELL_ROOT / "docs" / "tahoe-material-governance.md"

MATERIALS = ["panel", "pill", "launcher", "dock", "menu", "toast", "backdrop"]
LIVE_SAMPLING = "xray false"
PRODUCTION_GLASS_SURFACES = {
    "AppMenuPopup.qml": "MaterialMenu",
    "BatteryPopup.qml": "MaterialPanel",
    "ClipboardPopup.qml": "MaterialPanel",
    "ControlCenter.qml": "MaterialPanel",
    "Dock.qml": "MaterialDock",
    "DockAppMenu.qml": "MaterialMenu",
    "DockWindowMenu.qml": "MaterialMenu",
    "DynamicIslandOverlay.qml": "MaterialPill",
    "FanPopup.qml": "MaterialPanel",
    "Launchpad.qml": "MaterialBackdrop",
    "LeftSidebar.qml": "MaterialPanel",
    "MenuPopup.qml": "MaterialMenu",
    "NotificationCenter.qml": "MaterialPanel",
    "NotificationToast.qml": "MaterialToast",
    "ProcessMenu.qml": "MaterialMenu",
    "SettingsPanel.qml": "MaterialPanel",
    "Spotlight.qml": "MaterialPanel",
    "TaskSwitcher.qml": "MaterialMenu",
    "TopBar.qml": "MaterialPanel",
    "TrayMenu.qml": "MaterialMenu",
    "WifiPopup.qml": "MaterialPanel",
    "WindowOverview.qml": "MaterialPanel",
}
PROFILE_FIELDS = [
    "noise",
    "saturation",
    "contrast",
    "tint-amount",
    "edge-highlight",
    "refraction",
    "inner-shadow",
    "chromatic",
    "lens-depth",
]
SETTINGS_FIELDS = ["edge-highlight", "refraction", "inner-shadow", "chromatic", "lens-depth"]
SURFACE_RECIPES = [
    "TopBar",
    "Dock",
    "ControlCenter",
    "NotificationToast",
    "Launchpad",
    "Spotlight",
    "MenuPopup",
    "SettingsPanel",
    "DynamicIsland",
]


def extract_block(text: str, start_pattern: str) -> str:
    match = re.search(start_pattern, text, re.MULTILINE)
    if not match:
        raise AssertionError(f"missing block: {start_pattern}")

    start = match.end()
    depth = 1
    index = start
    while index < len(text):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start:index]
        index += 1

    raise AssertionError(f"unterminated block: {start_pattern}")


def parse_kdl_numeric_fields(block: str) -> dict[str, float]:
    values: dict[str, float] = {}
    for field in PROFILE_FIELDS:
        match = re.search(rf"(?m)^\s*{re.escape(field)}\s+([-+]?(?:\d+(?:\.\d*)?|\.\d+))\s*$", block)
        if match:
            values[field] = float(match.group(1))
    return values


def parse_kdl_materials() -> dict[str, dict[str, float]]:
    text = NIRI_CONFIG.read_text(encoding="utf-8")
    glass = extract_block(text, r"(?m)^\s*tahoe-glass\s*\{")
    return {
        material: parse_kdl_numeric_fields(
            extract_block(glass, rf'(?m)^\s*material\s+"{re.escape(material)}"\s*\{{')
        )
        for material in MATERIALS
    }


def parse_rust_material_defaults() -> dict[str, dict[str, float]]:
    text = NIRI_CONFIG_TAHOE_GLASS.read_text(encoding="utf-8")
    materials: dict[str, dict[str, float]] = {}

    insert_re = re.compile(
        r'materials\.insert\(\s*"(?P<name>[^"]+)"\.to_owned\(\),\s*'
        r"material_profile\((?P<args>[^)]*)\),\s*\);",
        re.DOTALL,
    )
    for match in insert_re.finditer(text):
        args = [float(value.strip()) for value in match.group("args").split(",")]
        materials[match.group("name")] = dict(zip(PROFILE_FIELDS, args, strict=True))

    backdrop = re.search(r"let\s+mut\s+backdrop\s*=\s*material_profile\((?P<args>[^)]*)\);", text)
    if not backdrop:
        raise AssertionError("missing Rust backdrop material_profile")
    args = [float(value.strip()) for value in backdrop.group("args").split(",")]
    materials["backdrop"] = dict(zip(PROFILE_FIELDS, args, strict=True))
    return materials


def parse_schema_artifact_settings() -> dict[str, dict[str, float]]:
    payload = json.loads(GLASS_SCHEMA_ARTIFACT.read_text(encoding="utf-8"))
    materials: dict[str, dict[str, float]] = {}
    for name in MATERIALS:
        entry = payload["materials"][name]
        materials[name] = {
            field: float(entry[field.replace("-", "_")]) for field in SETTINGS_FIELDS
        }
    return materials


def load_niri_settings_tool():
    spec = importlib.util.spec_from_file_location("niri_settings_tool", NIRI_SETTINGS_TOOL)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TahoeMaterialGovernanceTests(unittest.TestCase):
    def test_shell_kdl_rust_and_schema_artifact_do_not_drift(self) -> None:
        js_text = TAHOE_GLASS_JS.read_text(encoding="utf-8")
        js_materials = re.findall(r'(?m)^\s*var\s+Material[A-Za-z0-9]+\s*=\s*"([^"]+)";', js_text)
        self.assertEqual(js_materials, MATERIALS)

        kdl = parse_kdl_materials()
        rust = parse_rust_material_defaults()
        self.assertEqual(kdl, rust)

        schema = parse_schema_artifact_settings()
        self.assertEqual(list(schema), MATERIALS)
        for material in MATERIALS:
            with self.subTest(material=material):
                self.assertEqual(
                    schema[material],
                    {field: kdl[material][field] for field in SETTINGS_FIELDS},
                )

        settings_tool = load_niri_settings_tool()
        settings_tool.refresh_glass_schema_constants()
        self.assertEqual(settings_tool.GLASS_MATERIAL_NAMES, MATERIALS)
        self.assertEqual(settings_tool.GLASS_MATERIAL_FIELDS, SETTINGS_FIELDS)
        # R13: no hand-written GLASS_MATERIAL_DEFAULTS table.
        self.assertFalse(hasattr(settings_tool, "GLASS_MATERIAL_DEFAULTS"))
        self.assertEqual(
            settings_tool._schema_material_defaults(),
            {
                material: {field: kdl[material][field] for field in SETTINGS_FIELDS}
                for material in MATERIALS
            },
        )

        # QML must not embed seven editable default material objects.
        qml = NIRI_SETTINGS_QML.read_text(encoding="utf-8")
        self.assertIn("property var glassMaterials: ({})", qml)
        self.assertNotRegex(
            qml,
            r'property\s+var\s+glassMaterials:\s*\(\s*\{\s*"panel"',
        )

    def test_all_materials_sample_the_live_composed_framebuffer(self) -> None:
        text = NIRI_CONFIG.read_text(encoding="utf-8")
        glass = extract_block(text, r"(?m)^\s*tahoe-glass\s*\{")

        for material in MATERIALS:
            with self.subTest(material=material):
                block = extract_block(
                    glass,
                    rf'(?m)^\s*material\s+"{re.escape(material)}"\s*\{{',
                )
                self.assertIn(LIVE_SAMPLING, block)

        components = SHELL_ROOT / "components"
        discovered = {
            path.name
            for path in components.glob("*.qml")
            if re.search(r"\bGlassPanel\s*\{", path.read_text(encoding="utf-8"))
        }
        self.assertEqual(discovered, set(PRODUCTION_GLASS_SURFACES))
        self.assertEqual(len(discovered), 22)

        for filename, material_constant in PRODUCTION_GLASS_SURFACES.items():
            with self.subTest(surface=filename):
                surface = (components / filename).read_text(encoding="utf-8")
                self.assertIn(f"material: GlassStyle.{material_constant}", surface)

        window_rule = extract_block(text, r"(?m)^window-rule\s*\{")
        window_effect = extract_block(window_rule, r"(?m)^\s*background-effect\s*\{")
        self.assertIn(LIVE_SAMPLING, window_effect)

    def test_kdl_fallback_background_effects_match_material_profiles(self) -> None:
        text = NIRI_CONFIG.read_text(encoding="utf-8")
        kdl = parse_kdl_materials()
        fallback_counts = {"panel": 0, "menu": 0, "toast": 0}

        marker_re = re.compile(
            r'Keep in sync with(?: the)?\s*(?://\s*)?tahoe-glass\s+"(?P<material>panel|menu|toast)"\s+material',
            re.MULTILINE,
        )
        for marker in marker_re.finditer(text):
            material = marker.group("material")
            block = extract_block(text[marker.end():], r"(?m)^\s*background-effect\s*\{")
            values = parse_kdl_numeric_fields(block)
            fallback_counts[material] += 1

            with self.subTest(material=material, fallback=fallback_counts[material]):
                self.assertIn(LIVE_SAMPLING, block)
                self.assertIn("blur true", block)
                self.assertIn('tint-color "#ffffff"', block)
                self.assertEqual(values, kdl[material])

        self.assertEqual(fallback_counts, {"panel": 2, "menu": 1, "toast": 1})

    def test_read_glass_marks_absent_fields_inherited(self) -> None:
        settings_tool = load_niri_settings_tool()
        settings_tool.refresh_glass_schema_constants()
        # Empty config: every settings field is inherited (null), not forged.
        payload = settings_tool.read_glass_text("")
        self.assertIn("schema", payload)
        for material in MATERIALS:
            entry = payload["materials"][material]
            for field in SETTINGS_FIELDS:
                key = field.replace("-", "_")
                self.assertIsNone(entry[key], f"{material}.{key}")
                self.assertTrue(entry[f"{key}_inherited"], f"{material}.{key}_inherited")
            # Schema still carries compositor defaults for display.
            schema_entry = payload["schema"]["materials"][material]
            self.assertAlmostEqual(schema_entry["edge_highlight"], parse_kdl_materials()[material]["edge-highlight"])

    def test_material_governance_doc_covers_phase9_scope(self) -> None:
        text = GOVERNANCE_DOC.read_text(encoding="utf-8")

        for material in MATERIALS:
            with self.subTest(material=material):
                self.assertIn(f"`{material}`", text)

        for surface in SURFACE_RECIPES:
            with self.subTest(surface=surface):
                self.assertIn(surface, text)

        self.assertIn("TahoeGlass.js", text)
        self.assertIn("config/niri/tahoe-phase0.kdl", text)
        self.assertIn("niri/niri-config/src/tahoe_glass.rs", text)
        self.assertIn("不做 GPU/渲染能力自适应", text)
        self.assertIn("PointHandler", text)
        self.assertIn("max(baseline, 1)", text)

        # T11: Dynamic Island is an explicit 1-region pill recipe, not an
        # implied Spotlight-style dual region.
        self.assertIn("DynamicIsland", text)
        self.assertRegex(
            text,
            r"DynamicIsland\s*\|\s*1\s*\|\s*`pill`",
        )
        self.assertIn("禁止 Spring", text)
        self.assertIn("SettingsTheme island tokens", text)


if __name__ == "__main__":
    unittest.main()
