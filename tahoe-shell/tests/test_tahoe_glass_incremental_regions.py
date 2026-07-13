#!/usr/bin/env python3
"""Regression checks for Task 14: incremental Tahoe glass region updates.

Models the protocol traffic of the old clear+resend path versus the new
id-diff path, and locks the source implementation to a single send path.
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SURFACE_CPP = REPO / "quickshell/src/wayland/tahoe_glass/surface.cpp"
QML_CPP = REPO / "quickshell/src/wayland/tahoe_glass/qml.cpp"
PROTOCOL_XML = REPO / "quickshell/src/wayland/tahoe_glass/tahoe-glass-v1.xml"


@dataclass(frozen=True)
class Region:
    id: int
    x: int = 0
    y: int = 0
    w: int = 10
    h: int = 10
    alpha: float = 1.0


def old_path_requests(old: list[Region], new: list[Region]) -> tuple[int, int]:
    """Legacy surface.cpp: always clear_regions + set_region for every item.

    Returns (request_count, commit_needed_as_int 0/1).
    """
    if old == new:
        return 0, 0
    # sameRegions was order-sensitive; treat list equality as no-op.
    if len(old) == len(new) and all(a == b for a, b in zip(old, new)):
        return 0, 0
    # Always clear + N sets when anything differs (including pure reorder).
    return 1 + len(new), 1


def new_path_requests(old: list[Region], new: list[Region]) -> tuple[int, int]:
    """Id-diff path: set only changed, remove only missing, clear only full empty."""
    old_by = {r.id: r for r in old}
    new_by = {r.id: r for r in new}

    # Order-independent content equality.
    if set(old_by) == set(new_by) and all(old_by[i] == new_by[i] for i in old_by):
        return 0, 0

    if not new:
        return (1, 1) if old else (0, 0)  # single clear_regions

    requests = 0
    for rid in old_by:
        if rid not in new_by:
            requests += 1  # remove_region
    for rid, region in new_by.items():
        if rid not in old_by or old_by[rid] != region:
            requests += 1  # set_region
    return requests, (1 if requests else 0)


class TestIncrementalRequestCounts(unittest.TestCase):
    def test_single_field_change_is_one_set(self):
        old = [Region(1), Region(2), Region(3)]
        new = [Region(1), Region(2, alpha=0.5), Region(3)]
        old_n, old_c = old_path_requests(old, new)
        new_n, new_c = new_path_requests(old, new)
        self.assertEqual(old_n, 1 + 3)  # clear + 3 sets
        self.assertEqual(new_n, 1)  # one set_region
        self.assertEqual(old_c, 1)
        self.assertEqual(new_c, 1)
        self.assertLess(new_n, old_n)

    def test_noop_is_zero_requests(self):
        regions = [Region(1), Region(2)]
        self.assertEqual(new_path_requests(regions, regions), (0, 0))
        self.assertEqual(old_path_requests(regions, regions), (0, 0))

    def test_pure_reorder_is_zero_requests(self):
        old = [Region(1), Region(2), Region(3)]
        new = [Region(3), Region(1), Region(2)]
        # Old path treated reorder as full rewrite (order-sensitive equality).
        old_n, old_c = old_path_requests(old, new)
        new_n, new_c = new_path_requests(old, new)
        self.assertGreater(old_n, 0)
        self.assertEqual(new_n, 0)
        self.assertEqual(new_c, 0)

    def test_add_region_one_set(self):
        old = [Region(1)]
        new = [Region(1), Region(2)]
        self.assertEqual(new_path_requests(old, new), (1, 1))

    def test_remove_region_one_remove(self):
        old = [Region(1), Region(2)]
        new = [Region(1)]
        self.assertEqual(new_path_requests(old, new), (1, 1))

    def test_clear_all_one_clear(self):
        old = [Region(1), Region(2), Region(3)]
        new: list[Region] = []
        self.assertEqual(new_path_requests(old, new), (1, 1))
        # Old path: clear + 0 sets = 1 request as well for empty, but
        # for N regions changing one field old was 1+N.
        self.assertEqual(old_path_requests(old, new), (1, 1))

    def test_id_change_is_remove_plus_set(self):
        old = [Region(1, x=0)]
        new = [Region(2, x=0)]  # different id, same geometry
        self.assertEqual(new_path_requests(old, new), (2, 1))

    def test_animation_endpoint_not_swallowed(self):
        # Exact 0.0 and 1.0 must produce updates (no coarse epsilon swallow).
        old = [Region(1, alpha=0.0)]
        mid = [Region(1, alpha=0.5)]
        end = [Region(1, alpha=1.0)]
        self.assertEqual(new_path_requests(old, mid)[0], 1)
        self.assertEqual(new_path_requests(mid, end)[0], 1)
        self.assertEqual(new_path_requests(end, end)[0], 0)


class TestSourceIncrementalPath(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.surface = SURFACE_CPP.read_text(encoding="utf-8")
        cls.qml = QML_CPP.read_text(encoding="utf-8")
        cls.xml = PROTOCOL_XML.read_text(encoding="utf-8")

    def test_protocol_has_remove_region(self):
        self.assertIn('request name="remove_region"', self.xml)
        self.assertIn('request name="set_region"', self.xml)
        self.assertIn('request name="clear_regions"', self.xml)

    def test_uses_remove_region_and_id_diff(self):
        self.assertIn("remove_region", self.surface)
        self.assertIn("sameRegionsById", self.surface)
        self.assertIn("oldById", self.surface)
        self.assertIn("newById", self.surface)

    def test_clear_regions_only_for_full_empty(self):
        # clear_regions must not be the unconditional first step of every update.
        self.assertNotRegex(
            self.surface,
            r"if \(sameRegions\([^)]*\)\) return false;\s*"
            r"this->clear_regions\(\);",
        )
        # Full-empty path still uses clear_regions.
        self.assertIn("clear_regions", self.surface)
        self.assertRegex(
            self.surface,
            r"if \(regions\.isEmpty\(\)\)[\s\S]*?clear_regions\(\)",
        )

    def test_single_send_path_no_parallel_api(self):
        # Only one setRegions entry on the surface owner.
        self.assertEqual(self.surface.count("bool TahoeGlassSurface::setRegions"), 1)
        self.assertNotIn("safeSetRegions", self.surface)
        self.assertNotIn("setRegionsIncremental", self.surface)
        self.assertNotIn("setRegionsFull", self.surface)
        # qml still has a single call site.
        self.assertEqual(len(re.findall(r"setRegions\(", self.qml)), 1)

    def test_no_coarse_epsilon_on_geometry(self):
        # Rect comparison must remain exact (sameRegion uses == on QRect).
        self.assertIn("lhs.rect == rhs.rect", self.surface)
        # Fuzzy only for interaction/materialAlpha scalars already quantized upstream.
        self.assertIn("fuzzyEqual(lhs.interaction", self.surface)
        self.assertIn("fuzzyEqual(lhs.materialAlpha", self.surface)


if __name__ == "__main__":
    unittest.main()
