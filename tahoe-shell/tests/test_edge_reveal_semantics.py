#!/usr/bin/env python3
"""Source-level checks for Tahoe animation regression semantics."""

from pathlib import Path
import re
import unittest


REPO = Path(__file__).resolve().parents[2]
CONFIG = REPO / "config/niri/tahoe-phase0.kdl"
SETTINGS_PAGE = REPO / "tahoe-shell/components/settings/pages/NiriAnimationsPage.qml"
LAYER_TESTS = REPO / "niri/src/tests/layer_shell.rs"
WINDOW_BUTTON = REPO / "tahoe-shell/components/WindowButton.qml"
DOCK_MINIMIZED_WINDOW = REPO / "tahoe-shell/components/DockMinimizedWindow.qml"

# Status popups keep full-surface top edge-reveal (T04-fix2). Menus moved to
# pop-slide in T21 and are checked separately.
TOPBAR_STATUS_POPUP_NAMESPACES = {
    "tahoe-battery-popup",
    "tahoe-wifi-popup",
    "tahoe-fan-popup",
    "tahoe-clipboard-popup",
}

TOPBAR_MENU_NAMESPACES = {
    "tahoe-menu-popup",
    "tahoe-application-menu",
    "tahoe-tray-menu",
}

DOCK_MENU_NAMESPACES = {
    "tahoe-dock-app-menu",
    "tahoe-dock-window-menu",
}

PROCESS_MENU_NAMESPACE = "tahoe-process-menu"


def extract_blocks(text: str, start_pattern: str) -> list[str]:
    """Return brace-balanced block bodies while ignoring strings/comments."""
    blocks: list[str] = []

    for match in re.finditer(start_pattern, text, re.MULTILINE):
        opening = text.find("{", match.start(), match.end())
        if opening == -1:
            raise AssertionError(f"block pattern does not include '{{': {start_pattern}")

        depth = 1
        index = opening + 1
        quote = ""
        raw_closer = ""
        line_comment = False
        block_comment = False
        escaped = False

        while index < len(text):
            if line_comment:
                if text[index] == "\n":
                    line_comment = False
                index += 1
                continue

            if block_comment:
                if text.startswith("*/", index):
                    block_comment = False
                    index += 2
                else:
                    index += 1
                continue

            if raw_closer:
                if text.startswith(raw_closer, index):
                    index += len(raw_closer)
                    raw_closer = ""
                else:
                    index += 1
                continue

            if quote:
                char = text[index]
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == quote:
                    quote = ""
                index += 1
                continue

            if text.startswith("//", index):
                line_comment = True
                index += 2
                continue
            if text.startswith("/*", index):
                block_comment = True
                index += 2
                continue

            raw_match = re.match(r'r(?P<hashes>#+)"', text[index:])
            if raw_match:
                hashes = raw_match.group("hashes")
                raw_closer = f'"{hashes}'
                index += raw_match.end()
                continue

            char = text[index]
            if char in ('"', "'", "`"):
                quote = char
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    blocks.append(text[opening + 1:index])
                    break
            index += 1
        else:
            raise AssertionError(f"unterminated block: {start_pattern}")

    return blocks


def extract_one_block(text: str, start_pattern: str) -> str:
    blocks = extract_blocks(text, start_pattern)
    if len(blocks) != 1:
        raise AssertionError(
            f"expected exactly one block for {start_pattern}, found {len(blocks)}"
        )
    return blocks[0]


def layer_rule_namespaces(rule: str) -> set[str]:
    return set(
        re.findall(
            r'(?m)^\s*match\s+namespace="\^(?P<namespace>[A-Za-z0-9-]+)\$"\s*$',
            rule,
        )
    )


def assert_in_order(test: unittest.TestCase, text: str, *needles: str) -> None:
    positions = [text.find(needle) for needle in needles]
    test.assertNotIn(-1, positions, f"missing ordered token in {needles!r}")
    test.assertEqual(positions, sorted(positions), f"tokens are out of order: {needles!r}")


class EdgeRevealSemanticsTests(unittest.TestCase):
    def test_settings_page_explains_edge_reveal_distance(self) -> None:
        text = SETTINGS_PAGE.read_text(encoding="utf-8")

        self.assertIn("edge-reveal", text)
        self.assertIn("KDL distance", text)
        self.assertIn("不是短滑动距离调参", text)

    def test_active_config_comments_edge_reveal_distance(self) -> None:
        text = CONFIG.read_text(encoding="utf-8")

        self.assertNotIn("short top-edge", text)
        self.assertIn("edge-reveal uses the layer surface extent", text)
        self.assertIn("not a short-travel knob", text)

    def test_runtime_full_surface_edge_reveal_regression_test_remains(self) -> None:
        text = LAYER_TESTS.read_text(encoding="utf-8")

        self.assertIn("layer_close_edge_reveal_moves_full_surface_extent", text)
        self.assertIn("should fully retract that surface", text)

    def test_topbar_status_popups_share_top_edge_reveal_rule(self) -> None:
        text = CONFIG.read_text(encoding="utf-8")
        layer_rules = extract_blocks(text, r"(?m)^\s*layer-rule\s*\{")
        popup_animation_rules = [
            rule
            for rule in layer_rules
            if layer_rule_namespaces(rule) & TOPBAR_STATUS_POPUP_NAMESPACES
            and extract_blocks(rule, r"(?m)^\s*animations\s*\{")
        ]

        self.assertEqual(len(popup_animation_rules), 1)
        rule = popup_animation_rules[0]
        self.assertEqual(layer_rule_namespaces(rule), TOPBAR_STATUS_POPUP_NAMESPACES)

        animations = extract_one_block(rule, r"(?m)^\s*animations\s*\{")
        layer_open = extract_one_block(animations, r"(?m)^\s*layer-open\s*\{")
        layer_close = extract_one_block(animations, r"(?m)^\s*layer-close\s*\{")

        for phase, block in (("open", layer_open), ("close", layer_close)):
            with self.subTest(phase=phase):
                self.assertRegex(block, r'(?m)^\s*style\s+"edge-reveal"\s*$')
                self.assertRegex(block, r'(?m)^\s*edge\s+"top"\s*$')
                for forbidden in ("pop-slide", "scale-from", "scale-to", "origin"):
                    self.assertNotIn(forbidden, block)

    def test_menus_use_pop_slide_with_pointer_origin(self) -> None:
        """T21/T22: all menus share pop-slide + origin pointer + 4px drop."""
        text = CONFIG.read_text(encoding="utf-8")
        layer_rules = extract_blocks(text, r"(?m)^\s*layer-rule\s*\{")
        expected = TOPBAR_MENU_NAMESPACES | DOCK_MENU_NAMESPACES | {PROCESS_MENU_NAMESPACE}

        menu_rules = [
            rule
            for rule in layer_rules
            if layer_rule_namespaces(rule) & expected
            and extract_blocks(rule, r"(?m)^\s*animations\s*\{")
        ]
        self.assertEqual(len(menu_rules), 1)
        rule = menu_rules[0]
        self.assertEqual(layer_rule_namespaces(rule), expected)

        animations = extract_one_block(rule, r"(?m)^\s*animations\s*\{")
        layer_open = extract_one_block(animations, r"(?m)^\s*layer-open\s*\{")
        layer_close = extract_one_block(animations, r"(?m)^\s*layer-close\s*\{")
        for phase, block in (("open", layer_open), ("close", layer_close)):
            with self.subTest(phase=phase):
                self.assertRegex(block, r'(?m)^\s*style\s+"pop-slide"\s*$')
                self.assertRegex(block, r'(?m)^\s*edge\s+"top"\s*$')
                self.assertRegex(block, r"(?m)^\s*distance\s+4\s*$")
                self.assertRegex(block, r'(?m)^\s*origin\s+"pointer"\s*$')

    def test_spring_open_transform_channels_still_inherit_main_animation(self) -> None:
        text = CONFIG.read_text(encoding="utf-8")
        layer_opens = extract_blocks(text, r"(?m)^\s*layer-open\s*\{")
        spring_opens = [block for block in layer_opens if re.search(r"(?m)^\s*spring\b", block)]

        # CC / NC / sidebar / spotlight / status popup / menu / toast = 7.
        self.assertGreaterEqual(len(spring_opens), 7)
        for block in spring_opens:
            # Main spring must not be overridden by easing transform-duration/curve.
            # transform-spring (T21) is allowed and still a spring channel.
            self.assertNotRegex(block, r"(?m)^\s*transform-duration-ms\b")
            self.assertNotRegex(block, r"(?m)^\s*transform-curve\b")


class WindowLifecycleAnimationTests(unittest.TestCase):
    def test_window_open_close_and_restore_use_bounded_native_timing(self) -> None:
        text = CONFIG.read_text(encoding="utf-8")
        window_open = extract_one_block(text, r"(?m)^\s*window-open\s*\{")
        window_close = extract_one_block(text, r"(?m)^\s*window-close\s*\{")
        window_restore = extract_one_block(text, r"(?m)^\s*window-restore\s*\{")

        for block, expected_lines in (
            (
                window_open,
                (r"duration-ms\s+220", r'curve\s+"ease-out-cubic"', r"scale-from\s+0\.97"),
            ),
            (
                window_close,
                (r"duration-ms\s+180", r'curve\s+"ease-out-cubic"', r"scale-to\s+0\.97"),
            ),
            (window_restore, (r"duration-ms\s+300", r'curve\s+"linear"')),
        ):
            for expected in expected_lines:
                self.assertRegex(block, rf"(?m)^\s*{expected}\s*$")

        for phase, block in (("open", window_open), ("close", window_close)):
            with self.subTest(phase=phase):
                self.assertNotRegex(block, r"(?m)^\s*custom-shader(?:\s|$)")


class DockRestoreRectangleTests(unittest.TestCase):
    def test_window_button_reports_visual_icon_before_restore_and_bounce(self) -> None:
        text = WINDOW_BUTTON.read_text(encoding="utf-8")
        rectangle = extract_one_block(
            text,
            r"(?m)^\s*function\s+updateDockRectangle\s*\([^)]*\)\s*\{",
        )
        restore = extract_one_block(
            text,
            r"(?m)^\s*function\s+restoreOrActivate\s*\([^)]*\)\s*\{",
        )
        clicked = extract_one_block(
            text,
            r"(?m)^\s*onClicked:\s*function\s*\([^)]*\)\s*\{",
        )

        self.assertRegex(rectangle, r"topLeft\s*=\s*icon\.mapToItem\(null,\s*0,\s*0\)")
        self.assertRegex(
            rectangle,
            r"bottomRight\s*=\s*icon\.mapToItem\(null,\s*icon\.width,\s*icon\.height\)",
        )
        self.assertRegex(rectangle, r"targetWidth\s*=\s*Math\.max\(1,\s*right\s*-\s*left\)")
        self.assertRegex(rectangle, r"targetHeight\s*=\s*Math\.max\(1,\s*bottom\s*-\s*top\)")
        self.assertRegex(
            rectangle,
            r"top\s*=\s*Math\.floor\([^;\n]*-\s*root\.dockSlideOffset[^;\n]*\)",
        )
        self.assertRegex(
            rectangle,
            r"bottom\s*=\s*Math\.ceil\([^;\n]*-\s*root\.dockSlideOffset[^;\n]*\)",
        )
        self.assertNotIn("root.mapToItem(null, 0, 0)", rectangle)

        assert_in_order(self, restore, "updateDockRectangle()", "windowsService.restore")
        self.assertEqual(clicked.count("root.restoreOrActivate()"), 1)
        self.assertLess(clicked.index("root.restoreOrActivate()"), clicked.rfind("root.bounce()"))

    def test_minimized_preview_reports_visual_bounds_before_restore_and_bounce(self) -> None:
        text = DOCK_MINIMIZED_WINDOW.read_text(encoding="utf-8")
        rectangle = extract_one_block(
            text,
            r"(?m)^\s*function\s+updateDockRectangle\s*\([^)]*\)\s*\{",
        )
        restore = extract_one_block(
            text,
            r"(?m)^\s*function\s+restoreWindow\s*\([^)]*\)\s*\{",
        )
        clicked = extract_one_block(
            text,
            r"(?m)^\s*onClicked:\s*function\s*\([^)]*\)\s*\{",
        )

        self.assertRegex(
            rectangle,
            r"topLeft\s*=\s*previewFrame\.mapToItem\(null,\s*0,\s*0\)",
        )
        self.assertRegex(
            rectangle,
            r"bottomRight\s*=\s*previewFrame\.mapToItem"
            r"\(null,\s*previewFrame\.width,\s*previewFrame\.height\)",
        )
        self.assertRegex(rectangle, r"Math\.max\(1,\s*right\s*-\s*left\)")
        self.assertRegex(rectangle, r"Math\.max\(1,\s*bottom\s*-\s*top\)")
        self.assertRegex(
            rectangle,
            r"top\s*=\s*Math\.floor\([^;\n]*-\s*root\.dockSlideOffset[^;\n]*\)",
        )
        self.assertRegex(
            rectangle,
            r"bottom\s*=\s*Math\.ceil\([^;\n]*-\s*root\.dockSlideOffset[^;\n]*\)",
        )
        self.assertNotIn("root.mapToItem(null, 0, 0)", rectangle)

        assert_in_order(self, restore, "root.updateDockRectangle()", "root.windowsService.restore")
        self.assertEqual(clicked.count("root.restoreWindow()"), 1)
        self.assertLess(clicked.index("root.restoreWindow()"), clicked.rfind("root.bounce()"))


if __name__ == "__main__":
    unittest.main()
