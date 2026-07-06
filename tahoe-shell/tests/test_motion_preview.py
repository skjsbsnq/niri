from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SHELL_ROOT.parent

NIRI_ANIMATIONS_PAGE = SHELL_ROOT / "components" / "settings" / "pages" / "NiriAnimationsPage.qml"
NIRI_CONFIG_ANIMATIONS = REPO_ROOT / "niri" / "niri-config" / "src" / "animations.rs"


def extract_bracket_block(text: str, marker: str) -> str:
    start = text.index(marker)
    start = text.index("[", start)
    depth = 0

    for index in range(start, len(text)):
        char = text[index]
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                return text[start + 1:index]

    raise AssertionError(f"unterminated bracket block after {marker}")


def parse_number(value: str) -> float:
    return float(value.strip())


def parse_qml_curve_model() -> dict[str, tuple[str, tuple[float, float, float, float] | None]]:
    text = NIRI_ANIMATIONS_PAGE.read_text(encoding="utf-8")
    block = extract_bracket_block(text, "readonly property var namedCurveModel")
    curves: dict[str, tuple[str, tuple[float, float, float, float] | None]] = {}

    for match in re.finditer(r"\{\s*name:\s*\"(?P<name>[^\"]+)\"(?P<body>[^}]*)\}", block):
        name = match.group("name")
        body = match.group("body")
        kind_match = re.search(r"kind:\s*\"(?P<kind>[^\"]+)\"", body)
        if not kind_match:
            raise AssertionError(f"missing QML curve kind for {name}")

        kind = kind_match.group("kind")
        points = None
        if kind == "cubic":
            parsed = []
            for field in ("x1", "y1", "x2", "y2"):
                point_match = re.search(
                    rf"{field}:\s*(?P<value>[-+]?(?:\d+(?:\.\d*)?|\.\d+))",
                    body,
                )
                if not point_match:
                    raise AssertionError(f"missing QML {field} for {name}")
                parsed.append(parse_number(point_match.group("value")))
            points = tuple(parsed)

        curves[name] = (kind, points)

    return curves


def parse_rust_curve_table() -> dict[str, tuple[str, tuple[float, float, float, float] | None]]:
    text = NIRI_CONFIG_ANIMATIONS.read_text(encoding="utf-8")
    table_start = text.index("let animation_curve = match animation_curve_string.as_str()")
    table_end = text.index('"cubic-bezier" =>', table_start)
    block = text[table_start:table_end]
    curves: dict[str, tuple[str, tuple[float, float, float, float] | None]] = {}

    simple_map = {
        "Linear": "linear",
        "EaseOutQuad": "ease-out-quad",
        "EaseOutCubic": "ease-out-cubic",
        "EaseOutExpo": "ease-out-expo",
    }

    for match in re.finditer(
        r"\"(?P<name>[^\"]+)\"\s*=>\s*Some\(Curve::(?P<variant>Linear|EaseOutQuad|EaseOutCubic|EaseOutExpo)\)",
        block,
    ):
        curves[match.group("name")] = (simple_map[match.group("variant")], None)

    cubic_re = re.compile(
        r"\"(?P<name>[^\"]+)\"\s*=>\s*Some\(Curve::CubicBezier\("
        r"(?P<x1>[-+]?(?:\d+(?:\.\d*)?|\.\d+)),\s*"
        r"(?P<y1>[-+]?(?:\d+(?:\.\d*)?|\.\d+)),\s*"
        r"(?P<x2>[-+]?(?:\d+(?:\.\d*)?|\.\d+)),\s*"
        r"(?P<y2>[-+]?(?:\d+(?:\.\d*)?|\.\d+))"
        r"\)\)",
        re.DOTALL,
    )
    for match in cubic_re.finditer(block):
        curves[match.group("name")] = (
            "cubic",
            tuple(parse_number(match.group(field)) for field in ("x1", "y1", "x2", "y2")),
        )

    return curves


class MotionPreviewTests(unittest.TestCase):
    def test_qml_named_curve_preview_mirrors_niri_parser_table(self) -> None:
        self.assertEqual(parse_qml_curve_model(), parse_rust_curve_table())

    def test_preview_sections_do_not_write_kdl(self) -> None:
        text = NIRI_ANIMATIONS_PAGE.read_text(encoding="utf-8")
        preview = text[text.index('title: "曲线预览"'):text.index('title: "工作区切换（workspace-switch）"')]

        self.assertIn("curveCanvas", preview)
        self.assertIn("springCanvas", preview)
        self.assertNotIn("setAnimParam", preview)
        self.assertNotIn("writeField", preview)


if __name__ == "__main__":
    unittest.main()
