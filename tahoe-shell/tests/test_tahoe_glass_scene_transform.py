#!/usr/bin/env python3
"""Regression checks for Task 13: Tahoe glass item scene-transform tracking.

Validates:
1. Region geometry maps all four local corners (not a diagonal pair).
2. Source tracks scale/rotation/transformOrigin and the parent chain.
3. Pure AABB math for a 45° rotation matches the four-corner contract.
"""

from __future__ import annotations

import math
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
QML_CPP = REPO / "quickshell/src/wayland/tahoe_glass/qml.cpp"
QML_HPP = REPO / "quickshell/src/wayland/tahoe_glass/qml.hpp"


def item_scene_bounds_four_corners(
    map_to_scene,
    width: float,
    height: float,
) -> tuple[float, float, float, float]:
    """Mirror of TahoeGlassRegion::itemSceneBounds AABB construction."""
    corners = [
        map_to_scene(0.0, 0.0),
        map_to_scene(width, 0.0),
        map_to_scene(0.0, height),
        map_to_scene(width, height),
    ]
    xs = [p[0] for p in corners]
    ys = [p[1] for p in corners]
    return min(xs), min(ys), max(xs), max(ys)


def diagonal_only_bounds(map_to_scene, width: float, height: float):
    """Old buggy path: only origin and opposite corner."""
    origin = map_to_scene(0.0, 0.0)
    extent = map_to_scene(width, height)
    left, right = sorted([origin[0], extent[0]])
    top, bottom = sorted([origin[1], extent[1]])
    return left, top, right, bottom


def rotate_around(point, origin, degrees: float):
    rad = math.radians(degrees)
    cos_a, sin_a = math.cos(rad), math.sin(rad)
    dx, dy = point[0] - origin[0], point[1] - origin[1]
    return (
        origin[0] + dx * cos_a - dy * sin_a,
        origin[1] + dx * sin_a + dy * cos_a,
    )


class TestFourCornerAabb(unittest.TestCase):
    def test_45_degree_rotation_diagonal_underestimates_width(self):
        # Item size 100x40, rotated 45° around center.
        # Diagonal-only (origin + opposite corner) underestimates width for
        # non-square rotation; four-corner AABB is the correct contract.
        width, height = 100.0, 40.0
        center = (width / 2.0, height / 2.0)

        def map_to_scene(x: float, y: float):
            return rotate_around((x, y), center, 45.0)

        four = item_scene_bounds_four_corners(map_to_scene, width, height)
        diag = diagonal_only_bounds(map_to_scene, width, height)

        four_w = four[2] - four[0]
        four_h = four[3] - four[1]
        diag_w = diag[2] - diag[0]
        diag_h = diag[3] - diag[1]

        # Four-corner AABB is a superset: never smaller than diagonal-only.
        self.assertGreaterEqual(four_w + 1e-9, diag_w)
        self.assertGreaterEqual(four_h + 1e-9, diag_h)
        # For this 45° non-square case the missing corners expand width a lot.
        self.assertGreater(four_w, diag_w + 20.0)

        expected_w = abs(width * math.cos(math.radians(45))) + abs(
            height * math.sin(math.radians(45))
        )
        expected_h = abs(width * math.sin(math.radians(45))) + abs(
            height * math.cos(math.radians(45))
        )
        self.assertAlmostEqual(four_w, expected_w, places=5)
        self.assertAlmostEqual(four_h, expected_h, places=5)

    def test_no_rotation_matches_local_rect(self):
        def map_to_scene(x: float, y: float):
            return (10.0 + x, 20.0 + y)

        left, top, right, bottom = item_scene_bounds_four_corners(map_to_scene, 50, 30)
        self.assertEqual((left, top, right, bottom), (10.0, 20.0, 60.0, 50.0))


class TestSourceTracksFullSceneTransform(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = QML_CPP.read_text(encoding="utf-8")
        cls.hpp = QML_HPP.read_text(encoding="utf-8")

    def test_item_scene_bounds_helper_exists(self):
        self.assertIn("itemSceneBounds", self.hpp)
        self.assertIn("itemSceneBounds", self.cpp)

    def test_four_corners_mapped(self):
        # Must map all four corners, not only (0,0) and (w,h).
        self.assertIsNotNone(
            re.search(
                r"mapToScene\(QPointF\(0,\s*0\)\).*?"
                r"mapToScene\(QPointF\(width,\s*0\)\).*?"
                r"mapToScene\(QPointF\(0,\s*height\)\).*?"
                r"mapToScene\(QPointF\(width,\s*height\)\)",
                self.cpp,
                re.DOTALL,
            )
        )
        # Diagonal-only construction must not remain as the sole path.
        self.assertIsNone(
            re.search(
                r"mapToScene\(QPointF\(0,\s*0\)\);\s*"
                r"auto extent = this->mItem->mapToScene\(QPointF\(this->mItem->width\(\),\s*"
                r"this->mItem->height\(\)\)\);",
                self.cpp,
            )
        )

    def test_tracks_scale_rotation_origin(self):
        for signal in (
            "scaleChanged",
            "rotationChanged",
            "transformOriginChanged",
            "parentChanged",
            "windowChanged",
            "visibleChanged",
        ):
            self.assertIn(signal, self.cpp, f"missing signal connection: {signal}")

    def test_tracks_transform_list_matrix_changes(self):
        # QML `transform: Translate { ... }` has no public NOTIFY; Matrix
        # change listener is required for full scene transform tracking.
        self.assertIn("QQuickItemChangeListener", self.hpp)
        self.assertIn("QQuickItemPrivate::Matrix", self.cpp)
        self.assertIn("itemTransformChanged", self.cpp)
        self.assertIn("addItemChangeListener", self.cpp)
        self.assertIn("removeItemChangeListener", self.cpp)

    def test_parent_chain_tracked_without_polling(self):
        self.assertIn("parentItem()", self.cpp)
        self.assertIn("linkTrackedItems", self.cpp)
        self.assertIn("unlinkTrackedItems", self.cpp)
        # No per-frame polling Timer for transform tracking.
        self.assertNotIn("QTimer", self.cpp)

    def test_destroy_and_reparent_lifecycle(self):
        self.assertIn("onTrackedItemDestroyed", self.cpp)
        self.assertIn("onItemAncestryChanged", self.cpp)
        self.assertIn("unlinkTrackedItems", self.cpp)
        # Destroyed items must not be re-linked while QObject::destroyed runs.
        self.assertIn("skipItem", self.cpp)
        self.assertIn("~TahoeGlassRegion", self.cpp)
        # Identity via sender() only — qobject_cast fails after ~QQuickItem.
        self.assertIn("this->sender()", self.cpp)
        self.assertNotRegex(
            self.cpp,
            r"onTrackedItemDestroyed[\s\S]*?qobject_cast\s*<\s*QQuickItem\s*\*>",
        )
        # Single destroy authority: no ChangeListener Destroyed dual path.
        self.assertNotRegex(
            self.cpp,
            r"void TahoeGlassRegion::itemDestroyed\s*\(",
        )
        self.assertNotIn("itemDestroyed(QQuickItem*", self.hpp)


if __name__ == "__main__":
    unittest.main()
