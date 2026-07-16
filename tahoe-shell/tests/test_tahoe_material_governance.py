from __future__ import annotations

import importlib.util
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
GOVERNANCE_DOC = SHELL_ROOT / "docs" / "tahoe-material-governance.md"

MATERIALS = ["panel", "pill", "launcher", "dock", "menu", "toast", "backdrop"]
SAMPLING_STRATEGIES = {
    "panel": "xray true",
    "pill": "xray false",
    "launcher": "xray true",
    "dock": "xray true",
    "menu": "xray false",
    "toast": "xray false",
    "backdrop": "xray true",
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
        r"(?:live_)?material_profile\((?P<args>[^)]*)\),\s*\);",
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


def parse_qml_settings_defaults() -> dict[str, dict[str, float]]:
    text = NIRI_SETTINGS_QML.read_text(encoding="utf-8")
    defaults_block = extract_block(text, r"(?m)^\s*property\s+var\s+glassMaterials:\s*\(\s*\{")
    materials: dict[str, dict[str, float]] = {}
    for match in re.finditer(r'"(?P<name>[^"]+)":\s*\{(?P<body>[^}]*)\}', defaults_block):
        fields: dict[str, float] = {}
        for key, value in re.findall(r"(edge_highlight|refraction|inner_shadow|chromatic|lens_depth):\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))", match.group("body")):
            fields[key.replace("_", "-")] = float(value)
        materials[match.group("name")] = fields
    return materials


def load_niri_settings_tool():
    spec = importlib.util.spec_from_file_location("niri_settings_tool", NIRI_SETTINGS_TOOL)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TahoeMaterialGovernanceTests(unittest.TestCase):
    def test_shell_kdl_rust_and_settings_material_profiles_do_not_drift(self) -> None:
        js_text = TAHOE_GLASS_JS.read_text(encoding="utf-8")
        js_materials = re.findall(r'(?m)^\s*var\s+Material[A-Za-z0-9]+\s*=\s*"([^"]+)";', js_text)
        self.assertEqual(js_materials, MATERIALS)

        kdl = parse_kdl_materials()
        rust = parse_rust_material_defaults()
        self.assertEqual(kdl, rust)

        settings_qml = parse_qml_settings_defaults()
        self.assertEqual(list(settings_qml), MATERIALS)
        for material in MATERIALS:
            with self.subTest(material=material):
                self.assertEqual(settings_qml[material], {field: kdl[material][field] for field in SETTINGS_FIELDS})

        settings_tool = load_niri_settings_tool()
        self.assertEqual(settings_tool.GLASS_MATERIAL_NAMES, MATERIALS)
        self.assertEqual(settings_tool.GLASS_MATERIAL_FIELDS, SETTINGS_FIELDS)
        self.assertEqual(settings_tool.GLASS_MATERIAL_DEFAULTS, {
            material: {field: kdl[material][field] for field in SETTINGS_FIELDS}
            for material in MATERIALS
        })

    def test_material_sampling_strategy_is_explicit_and_bounded(self) -> None:
        text = NIRI_CONFIG.read_text(encoding="utf-8")
        glass = extract_block(text, r"(?m)^\s*tahoe-glass\s*\{")

        for material, expected in SAMPLING_STRATEGIES.items():
            with self.subTest(material=material):
                block = extract_block(
                    glass,
                    rf'(?m)^\s*material\s+"{re.escape(material)}"\s*\{{',
                )
                self.assertIn(expected, block)

        top_bar = (SHELL_ROOT / "components" / "TopBar.qml").read_text(encoding="utf-8")
        dock = (SHELL_ROOT / "components" / "Dock.qml").read_text(encoding="utf-8")
        self.assertIn("material: GlassStyle.MaterialPanel", top_bar)
        self.assertIn("material: GlassStyle.MaterialDock", dock)

        window_rule = extract_block(text, r"(?m)^window-rule\s*\{")
        window_effect = extract_block(window_rule, r"(?m)^\s*background-effect\s*\{")
        self.assertIn("xray false", window_effect)

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
                self.assertIn(SAMPLING_STRATEGIES[material], block)
                self.assertIn("blur true", block)
                self.assertIn('tint-color "#ffffff"', block)
                self.assertEqual(values, kdl[material])

        self.assertEqual(fallback_counts, {"panel": 2, "menu": 1, "toast": 1})

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
