#!/usr/bin/env python3
"""Source-level checks for GOAL-6 edge-reveal tuning semantics."""

from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
