#!/usr/bin/env python3
"""Source-level checks for GOAL-6 edge-reveal tuning semantics."""

from pathlib import Path
import re
import unittest


REPO = Path(__file__).resolve().parents[2]
CONFIG = REPO / "config/niri/tahoe-phase0.kdl"
SETTINGS_PAGE = REPO / "tahoe-shell/components/settings/pages/NiriAnimationsPage.qml"
LAYER_TESTS = REPO / "niri/src/tests/layer_shell.rs"


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

    def test_layer_open_spring_main_channel_has_no_transform_override(self) -> None:
        # T03: menus/popovers pop out of their anchor on a main-channel spring,
        # panels ride edge-reveal springs. The open transform override channel
        # must stay absent wherever a spring line exists, or the easing
        # override would silently replace the spring.
        text = CONFIG.read_text(encoding="utf-8")

        self.assertIn('origin "anchor"', text)
        self.assertIn("scale-from 0.94", text)
        self.assertIn("spring damping-ratio=0.88 stiffness=500 epsilon=0.001", text)

        open_blocks = re.findall(r"layer-open \{[^}]*\}", text)
        spring_opens = [block for block in open_blocks if "spring damping-ratio" in block]
        self.assertGreaterEqual(len(spring_opens), 8)
        for block in spring_opens:
            self.assertNotIn("transform-duration-ms", block)
            self.assertNotIn("transform-curve", block)


if __name__ == "__main__":
    unittest.main()
