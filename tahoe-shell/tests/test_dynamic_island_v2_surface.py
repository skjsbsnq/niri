#!/usr/bin/env python3
"""T11: V2 unified surface geometry, material recipe, and Loader scene host."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
CONTENT = SHELL_ROOT / "components" / "DynamicIslandContent.qml"
ISLAND = SHELL_ROOT / "services" / "DynamicIsland.qml"
MOTION = SHELL_ROOT / "components" / "DynamicIslandMotion.js"
THEME = SHELL_ROOT / "components" / "settings" / "SettingsTheme.js"
GOVERNANCE = SHELL_ROOT / "docs" / "tahoe-material-governance.md"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _function_body(src: str, name: str) -> str:
    m = re.search(rf"function\s+{re.escape(name)}\s*\([^)]*\)\s*\{{", src)
    if not m:
        return ""
    start = m.end()
    depth = 1
    i = start
    while i < len(src) and depth:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
        i += 1
    return src[start : i - 1]


def _parse_motion_int(name: str, text: str) -> int:
    m = re.search(rf"var\s+{re.escape(name)}\s*=\s*(\d+)\s*;", text)
    if not m:
        raise AssertionError(f"missing motion int {name}")
    return int(m.group(1))


def _mid(a: int, b: int) -> int:
    return round((a + b) / 2)


class DynamicIslandV2SurfaceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.overlay = _read(OVERLAY)
        cls.content = _read(CONTENT)
        cls.island = _read(ISLAND)
        cls.motion = _read(MOTION)
        cls.theme = _read(THEME)
        cls.gov = _read(GOVERNANCE)

        cls.clock_w = _mid(
            _parse_motion_int("v2ClockWidthMin", cls.motion),
            _parse_motion_int("v2ClockWidthMax", cls.motion),
        )
        cls.clock_h = _parse_motion_int("v2ClockHeight", cls.motion)
        cls.media_compact_w = _mid(
            _parse_motion_int("v2CompactMediaWidthMin", cls.motion),
            _parse_motion_int("v2CompactMediaWidthMax", cls.motion),
        )
        cls.media_compact_h = _parse_motion_int("v2CompactMediaHeight", cls.motion)
        cls.osd_w = _mid(
            _parse_motion_int("v2OsdWidthMin", cls.motion),
            _parse_motion_int("v2OsdWidthMax", cls.motion),
        )
        cls.osd_h = _parse_motion_int("v2OsdHeight", cls.motion)
        cls.workspace_w = _mid(
            _parse_motion_int("v2WorkspaceWidthMin", cls.motion),
            _parse_motion_int("v2WorkspaceWidthMax", cls.motion),
        )
        cls.workspace_h = _parse_motion_int("v2WorkspaceHeight", cls.motion)
        cls.notif_w = _mid(
            _parse_motion_int("v2NotificationCompactWidthMin", cls.motion),
            _parse_motion_int("v2NotificationCompactWidthMax", cls.motion),
        )
        cls.notif_h = _mid(
            _parse_motion_int("v2NotificationCompactHeightMin", cls.motion),
            _parse_motion_int("v2NotificationCompactHeightMax", cls.motion),
        )
        cls.media_exp_w = _mid(
            _parse_motion_int("v2MediaExpandedWidthMin", cls.motion),
            _parse_motion_int("v2MediaExpandedWidthMax", cls.motion),
        )
        cls.media_exp_h = _mid(
            _parse_motion_int("v2MediaExpandedHeightMin", cls.motion),
            _parse_motion_int("v2MediaExpandedHeightMax", cls.motion),
        )
        cls.radius_exp_min = _parse_motion_int("v2RadiusExpandedMin", cls.motion)
        cls.radius_exp_max = _parse_motion_int("v2RadiusExpandedMax", cls.motion)
        cls.top_inset = _parse_motion_int("v2CompactTopInset", cls.motion)
        cls.screen_margin = _parse_motion_int("v2ScreenMargin", cls.motion)

    def test_expected_midband_geometry_constants(self) -> None:
        self.assertEqual(self.clock_w, 124)
        self.assertEqual(self.clock_h, 32)
        self.assertEqual(self.media_compact_w, 212)
        self.assertEqual(self.media_compact_h, 36)
        self.assertEqual(self.osd_w, 230)
        self.assertEqual(self.osd_h, 44)
        self.assertEqual(self.workspace_w, 154)
        self.assertEqual(self.workspace_h, 36)
        self.assertEqual(self.notif_w, 360)
        self.assertEqual(self.notif_h, 70)
        self.assertEqual(self.media_exp_w, 418)
        self.assertEqual(self.media_exp_h, 166)
        self.assertEqual(self.top_inset, 4)
        self.assertEqual(self.screen_margin, 16)

    def test_overlay_width_height_use_v2_tokens(self) -> None:
        width_body = _function_body(self.overlay, "widthForState")
        height_body = _function_body(self.overlay, "heightForState")
        for token in (
            "v2MediaExpandedWidthMin",
            "v2MediaExpandedWidthMax",
            "v2CompactMediaWidthMin",
            "v2OsdWidthMin",
            "v2WorkspaceWidthMin",
        ):
            self.assertIn(token, width_body)
        # T12: resting_time width is content-driven via restingClockTargetWidth.
        self.assertIn("restingClockTargetWidth", width_body)
        clock_width = _function_body(self.overlay, "restingClockTargetWidth")
        self.assertIn("v2ClockWidthMin", clock_width)
        self.assertIn("v2ClockWidthMax", clock_width)
        # T14: notification compact size is content/overflow-driven.
        self.assertIn("notificationCompactTargetWidth", width_body)
        notif_width = _function_body(self.overlay, "notificationCompactTargetWidth")
        self.assertIn("v2NotificationCompactWidthMin", notif_width)
        self.assertIn("v2NotificationCompactWidthMax", notif_width)
        for token in (
            "v2MediaExpandedHeightMin",
            "v2ClockHeight",
            "v2CompactMediaHeight",
            "v2OsdHeight",
            "v2WorkspaceHeight",
        ):
            self.assertIn(token, height_body)
        self.assertIn("notificationCompactTargetHeight", height_body)
        notif_height = _function_body(self.overlay, "notificationCompactTargetHeight")
        self.assertIn("v2NotificationCompactHeightMin", notif_height)
        self.assertIn("v2NotificationCompactHeightMax", notif_height)
        # Legacy V1 hardcodes must be gone from geometry helpers.
        self.assertNotIn("return 400;", width_body)
        self.assertNotIn("return 140;", width_body)
        self.assertNotIn("return 190;", width_body)
        self.assertNotIn("return 165;", height_body)
        self.assertNotIn("return 38;", height_body)

    def test_service_widths_match_overlay_midband(self) -> None:
        body = _function_body(self.island, "restingWidthForState")
        for token in (
            "v2MediaExpandedWidthMin",
            "v2CompactMediaWidthMin",
            "v2ClockWidthMin",
            "v2OsdWidthMin",
            "v2NotificationCompactWidthMin",
            "v2WorkspaceWidthMin",
        ):
            self.assertIn(token, body)
        self.assertIn("v2MediaExpandedWidthMin", self.island)
        self.assertIn("v2MediaExpandedWidthMax", self.island)
        # swipeRightWidth is mid-band expanded media.
        self.assertRegex(
            self.island,
            r"swipeRightWidth:\s*Math\.round\(\s*\(IslandMotion\.v2MediaExpandedWidthMin",
        )

    def test_radius_cap_not_half_height_ellipse(self) -> None:
        body = _function_body(self.overlay, "radiusForState")
        self.assertIn("v2RadiusExpandedMax", body)
        self.assertIn("v2RadiusExpandedMin", body)
        self.assertIn("v2RadiusOsd", body)
        self.assertIn("v2RadiusCompactClock", body)
        self.assertNotIn("return h / 2", body)
        # Expanded media at 166px must never claim radius 83.
        self.assertLess(self.radius_exp_max, self.media_exp_h / 2)
        self.assertGreaterEqual(self.radius_exp_min, 28)
        self.assertLessEqual(self.radius_exp_max, 32)

    def test_compact_top_inset_and_screen_clamp(self) -> None:
        self.assertIn("v2CompactTopInset", self.overlay)
        self.assertIn("v2ScreenMargin", self.overlay)
        self.assertIn("screenWidth - (IslandMotion.v2ScreenMargin * 2)", self.overlay)
        self.assertIn("screenHeight", self.overlay)
        self.assertIn("screenHeight - IslandMotion.v2CompactTopInset - IslandMotion.v2ScreenMargin", self.overlay)
        self.assertRegex(
            self.overlay,
            r"capsuleTargetTop:\s*IslandMotion\.v2CompactTopInset",
        )
        # max width must not be bare screenWidth without margin.
        self.assertNotRegex(
            self.overlay,
            r"maxCapsuleWidth:\s*Math\.max\(1,\s*screenWidth\)\s*$",
            msg="maxCapsuleWidth must subtract screen margins",
        )

    def test_fill_stroke_from_settings_theme(self) -> None:
        self.assertIn('import "settings/SettingsTheme.js" as Theme', self.overlay)
        self.assertIn("Theme.islandSurfaceFill", self.overlay)
        self.assertIn("Theme.islandSurfaceStroke", self.overlay)
        self.assertIn("Theme.islandTextPrimary", self.overlay)
        self.assertIn("Theme.islandTextSecondary", self.overlay)
        self.assertIn("fillRoleForState", self.overlay)
        self.assertIn("strokeWidth: 1", self.overlay)
        # Legacy near-opaque hardcodes removed.
        self.assertNotIn('"#f00b0c10"', self.overlay)
        self.assertNotIn('"#f2131419"', self.overlay)
        # Theme still owns the tokens.
        self.assertIn('return "#cc10141a"', self.theme)
        self.assertIn('return "#df10141a"', self.theme)

    def test_single_pill_region_no_second_overlay(self) -> None:
        self.assertEqual(self.overlay.count("GlassPanel {"), 1)
        self.assertIn("id: islandSurface", self.overlay)
        self.assertIn("TahoeGlass.regions: [islandSurface.region]", self.overlay)
        self.assertIn("MaterialPill", self.overlay)
        self.assertEqual(self.overlay.count("PanelWindow {"), 1)
        self.assertNotIn("DynamicIslandV2", self.overlay)
        self.assertNotIn("MaterialIsland", self.overlay)

    def test_mask_follows_surface(self) -> None:
        self.assertIn("mask: Region", self.overlay)
        self.assertIn("width: root.capsuleShown ? Math.round(islandSurface.width) : 0", self.overlay)
        self.assertIn("height: root.capsuleShown ? Math.round(islandSurface.height) : 0", self.overlay)
        self.assertIn("x: Math.round(islandSurface.x)", self.overlay)
        self.assertIn("y: Math.round(islandSurface.y)", self.overlay)

    def test_glass_geometry_no_spring(self) -> None:
        # Only contentScale may spring; region geometry is NumberAnimation.
        self.assertEqual(self.overlay.count("SpringAnimation {"), 1)
        self.assertIn('property: "contentScale"', self.overlay)
        self.assertIn("Geometry → TahoeGlassRegion", self.overlay)
        self.assertIn("eased NumberAnimation only", self.overlay)
        # Behaviors on islandSurface geometry channels.
        for prop in ("x", "y", "width", "height", "radius"):
            self.assertRegex(
                self.overlay,
                rf"Behavior on {prop}\s*\{{\s*\n\s*NumberAnimation",
            )

    def test_content_loader_scene_host(self) -> None:
        self.assertIn("id: mediaLoader", self.content)
        self.assertIn("id: summaryLoader", self.content)
        self.assertIn("active: root.mediaLoaderActive", self.content)
        self.assertIn("active: root.summaryLoaderActive", self.content)
        self.assertIn("mediaUnloadHold", self.content)
        self.assertIn("summaryUnloadHold", self.content)
        self.assertIn("sourceComponent: mediaSceneComponent", self.content)
        self.assertIn("sourceComponent: summarySceneComponent", self.content)
        # No always-on expanded media/summary instances outside Loader.
        self.assertNotRegex(
            self.content,
            r"DynamicIslandMediaView\s*\{\s*\n\s*id:\s*mediaView",
        )
        self.assertNotRegex(
            self.content,
            r"DynamicIslandSummaryView\s*\{\s*\n\s*id:\s*summaryView",
        )
        # Loader activates only when content becomes visible / exit hold.
        self.assertIn("mediaLoaderActive = true", self.content)
        self.assertIn("mediaLoaderActive = false", self.content)
        self.assertIn("summaryLoaderActive = true", self.content)
        self.assertIn("summaryLoaderActive = false", self.content)
        self.assertIn("property bool mediaLoaderActive: false", self.content)
        self.assertIn("property bool summaryLoaderActive: false", self.content)

    def test_no_dual_render_of_expanded_scenes(self) -> None:
        # Expanded scenes appear only as Component source for Loader.
        media_hits = len(re.findall(r"DynamicIslandMediaView\s*\{", self.content))
        summary_hits = len(re.findall(r"DynamicIslandSummaryView\s*\{", self.content))
        self.assertEqual(media_hits, 1)
        self.assertEqual(summary_hits, 1)
        self.assertIn("id: mediaSceneComponent", self.content)
        self.assertIn("id: summarySceneComponent", self.content)

    def test_governance_documents_island_recipe(self) -> None:
        self.assertIn("DynamicIsland", self.gov)
        self.assertRegex(self.gov, r"DynamicIsland\s*\|\s*1\s*\|\s*`pill`")
        self.assertIn("禁止 Spring", self.gov)
        self.assertIn("SettingsTheme island tokens", self.gov)
        self.assertIn("Loader", self.gov)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
