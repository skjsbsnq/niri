#!/usr/bin/env python3
"""Regression checks for Task 15: fallback blur honors materialAlpha.

BackgroundEffect only supports binary blurRegion. Fallback must:
- include regions with blur flag and quantized materialAlpha > 0
- exclude regions with materialAlpha == 0 (no residual full-strength blur)
- clear blur when no region qualifies, in the same update path
- not claim continuous intensity animation
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
QML_CPP = REPO / "quickshell/src/wayland/tahoe_glass/qml.cpp"


@dataclass(frozen=True)
class Region:
    blur: bool
    material_alpha: float


def qualifies_for_fallback(region: Region) -> bool:
    """Mirror of updateFallback inclusion rule after Task 15."""
    return region.blur and region.material_alpha > 0.0


def fallback_active(regions: list[Region]) -> bool:
    return any(qualifies_for_fallback(r) for r in regions)


class TestBinaryFallbackRule(unittest.TestCase):
    def test_alpha_zero_excludes(self):
        self.assertFalse(qualifies_for_fallback(Region(blur=True, material_alpha=0.0)))
        self.assertFalse(fallback_active([Region(True, 0.0)]))

    def test_min_positive_step_includes(self):
        # Quantized step is 1/50 = 0.02.
        self.assertTrue(qualifies_for_fallback(Region(blur=True, material_alpha=0.02)))
        self.assertTrue(fallback_active([Region(True, 0.02)]))

    def test_half_and_one_include(self):
        self.assertTrue(qualifies_for_fallback(Region(blur=True, material_alpha=0.5)))
        self.assertTrue(qualifies_for_fallback(Region(blur=True, material_alpha=1.0)))

    def test_blur_flag_required(self):
        self.assertFalse(qualifies_for_fallback(Region(blur=False, material_alpha=1.0)))

    def test_multi_region_any_positive_keeps_blur(self):
        regions = [
            Region(True, 0.0),
            Region(True, 0.5),
            Region(False, 1.0),
        ]
        self.assertTrue(fallback_active(regions))

    def test_all_zero_clears(self):
        regions = [Region(True, 0.0), Region(True, 0.0)]
        self.assertFalse(fallback_active(regions))

    def test_exit_to_zero_clears_same_update(self):
        # Sequence: visible → exact 0 must clear (no residual).
        before = [Region(True, 1.0)]
        after = [Region(True, 0.0)]
        self.assertTrue(fallback_active(before))
        self.assertFalse(fallback_active(after))


class TestSourceFallbackAlpha(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = QML_CPP.read_text(encoding="utf-8")

    def test_update_fallback_checks_material_alpha(self):
        # Must gate on materialAlpha, not only blur flag.
        self.assertIn("materialAlpha", self.cpp)
        self.assertRegex(
            self.cpp,
            r"updateFallback[\s\S]*?materialAlpha\s*<=\s*0\.0",
        )

    def test_binary_visibility_documented(self):
        self.assertIn("BackgroundEffect blurRegion is binary", self.cpp)
        self.assertIn("materialAlpha > 0", self.cpp)
        # Must not claim continuous strength.
        self.assertNotRegex(
            self.cpp,
            r"updateFallback[\s\S]{0,800}smooth\s+strength|continuous\s+intensity",
            re.IGNORECASE,
        )

    def test_no_new_shader_or_parallel_effect(self):
        # Task forbids new blur shader / parallel effect API.
        self.assertNotIn("safeUpdateFallback", self.cpp)
        self.assertNotIn("fallbackStrength", self.cpp)
        self.assertNotIn("blurOpacity", self.cpp)
        # Still uses existing BackgroundEffect + PendingRegion path.
        self.assertIn("setBlurRegion", self.cpp)
        self.assertIn("BackgroundEffect", self.cpp)

    def test_blur_flag_still_required(self):
        # Both blur flag and alpha > 0.
        self.assertRegex(
            self.cpp,
            r"const bool blur\s*=\s*\(region\.flags\s*&\s*1\)\s*!=\s*0\s*;",
        )
        self.assertRegex(
            self.cpp,
            r"if\s*\(\s*!blur\s*\|\|\s*region\.materialAlpha\s*<=\s*0\.0\s*\)\s*continue\s*;",
        )

    def test_protocol_path_untouched_in_fallback(self):
        # Protocol path still clears fallback when surface is available.
        self.assertIn("this->clearFallback();", self.cpp)
        # setRegions path remains separate from updateFallback.
        self.assertIn("setRegions", self.cpp)
        self.assertIn("updateFallback", self.cpp)


if __name__ == "__main__":
    unittest.main()
