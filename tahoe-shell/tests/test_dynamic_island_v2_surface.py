#!/usr/bin/env python3
"""T11: V2 unified surface geometry, material recipe, and Loader scene host."""

from __future__ import annotations

import math
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
        # T16: resting_media width is content-driven via compactMediaTargetWidth.
        self.assertIn("compactMediaTargetWidth", width_body)
        media_width = _function_body(self.overlay, "compactMediaTargetWidth")
        self.assertIn("v2CompactMediaWidthMin", media_width)
        self.assertIn("v2CompactMediaWidthMax", media_width)
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

    def test_mask_follows_animated_painted_geometry(self) -> None:
        # Input mask tracks the painted footprint, never the raw settled
        # target — a target-sized mask desynced hit testing mid-morph. On the
        # legacy pipeline that is islandAnimated* per frame; under P05
        # compositor morph the drivers snap, so the mask holds the old∪new
        # union (morphMaskHold* ∨ islandAnimated*) for the morph window
        # before settling.
        self.assertIn("mask: Region", self.overlay)
        self.assertIn("islandAnimatedWidth", self.overlay)
        self.assertIn("islandAnimatedHeight", self.overlay)
        self.assertIn("islandAnimatedRadius", self.overlay)
        self.assertIn("width: root.capsuleShown ? Math.round(root.maskWidth) : 0", self.overlay)
        self.assertIn("height: root.capsuleShown ? Math.round(root.maskHeight) : 0", self.overlay)
        self.assertIn("y: root.capsuleTargetTop", self.overlay)
        # Union-hold plumbing: fallback is the animated footprint; the hold
        # is bounded by the motion token (covers spring/eased settle).
        self.assertIn(
            "readonly property real maskWidth: morphMaskHoldTimer.running\n"
            "        ? Math.max(root.morphMaskHoldWidth, root.islandAnimatedWidth)\n"
            "        : root.islandAnimatedWidth",
            self.overlay,
        )
        self.assertIn(
            "readonly property real maskHeight: morphMaskHoldTimer.running\n"
            "        ? Math.max(root.morphMaskHoldHeight, root.islandAnimatedHeight)\n"
            "        : root.islandAnimatedHeight",
            self.overlay,
        )
        self.assertIn("var v2CompositorMorphMaskHoldMs = 560", self.motion)
        # The hold interval belongs to the hold timer specifically.
        hold_timer = re.search(
            r"Timer\s*\{\s*\n\s*id: morphMaskHoldTimer([\s\S]*?)\n    \}",
            self.overlay,
        )
        self.assertIsNotNone(hold_timer)
        self.assertIn(
            "interval: IslandMotion.v2CompositorMorphMaskHoldMs",
            hold_timer.group(1),
        )
        # One-shot: a repeating hold timer would never release the union,
        # leaving the oversized mask (and its dead ring) armed forever.
        self.assertIn("repeat: false", hold_timer.group(1))
        # holdMorphMask() must capture the pre-snap footprint AND arm the
        # hold timer — without restart() the union hold silently never runs.
        hold_fn = re.search(
            r"function\s+holdMorphMask\(\)\s*\{([\s\S]*?)\n    \}",
            self.overlay,
        )
        self.assertIsNotNone(hold_fn)
        hold_body = hold_fn.group(1)
        self.assertIn("root.morphMaskHoldWidth", hold_body)
        self.assertIn("root.morphMaskHoldHeight", hold_body)
        self.assertIn("morphMaskHoldTimer.restart();", hold_body)
        # The capture runs at the top of queueCompositorMorph, before any
        # morph request is issued (and thus before the drivers snap).
        queue_fn = re.search(
            r"function\s+queueCompositorMorph\(\)\s*\{([\s\S]*?)\n    \}",
            self.overlay,
        )
        self.assertIsNotNone(queue_fn)
        queue_body = queue_fn.group(1)
        hold_call = queue_body.find("root.holdMorphMask();")
        first_request = queue_body.find("root.TahoeGlass.queueRegionMorph")
        self.assertGreater(hold_call, -1)
        self.assertGreater(first_request, hold_call)
        # Both geometry drivers must queue the morph (capturing the pre-snap
        # footprint) before snapping to the target; a snap-first reorder
        # loses the old footprint from the union (historical hit-gap bug).
        for fn_name, snap_stmt in (
            ("retargetWidthDriver", "root.islandDriverWidth = root.capsuleTargetWidth;"),
            ("retargetHeightDriver", "root.islandDriverHeight = root.capsuleTargetHeight;"),
        ):
            with self.subTest(driver=fn_name):
                driver = re.search(
                    r"function\s+" + fn_name + r"\(\)\s*\{([\s\S]*?)\n    \}",
                    self.overlay,
                )
                self.assertIsNotNone(driver)
                driver_body = driver.group(1)
                # Compositor morph stays gated on protocol availability.
                self.assertIn("root.compositorMorph", driver_body)
                anchor = driver_body.find("swipeSettling")
                self.assertGreater(anchor, -1)
                queue_call = driver_body.find("root.queueCompositorMorph()")
                snap_assign = driver_body.find(snap_stmt, anchor)
                self.assertGreater(queue_call, -1)
                self.assertGreater(snap_assign, queue_call)
        # Must not bind mask size to settled capsuleTarget* (historical bug).
        mask = re.search(r"mask:\s*Region\s*\{([\s\S]*?)\n    \}", self.overlay)
        self.assertIsNotNone(mask)
        mask_body = mask.group(1)
        self.assertNotIn("capsuleTargetWidth", mask_body)
        self.assertNotIn("capsuleTargetHeight", mask_body)
        self.assertNotIn("capsuleTargetLeft", mask_body)
        self.assertIn("useItemRegion: false", self.overlay)
        self.assertIn("protocolCapsuleWidth", self.overlay)
        # R08 #22: 2px quantum with floor semantics for size (region never
        # overhangs the painted capsule) and ceil for radius (glass corners
        # recede inside the painted corner).
        self.assertIn("var v2ProtocolSizeQuantumPx = 2", self.motion)
        self.assertIn("var v2ProtocolRadiusQuantumPx = 2", self.motion)
        self.assertIn(
            "quantizeProtocolFloor(islandSurface.width, IslandMotion.v2ProtocolSizeQuantumPx)",
            self.overlay,
        )
        self.assertIn(
            "quantizeProtocolFloor(islandSurface.height, IslandMotion.v2ProtocolSizeQuantumPx)",
            self.overlay,
        )
        self.assertIn(
            "quantizeProtocolCeil(islandSurface.radius, IslandMotion.v2ProtocolRadiusQuantumPx)",
            self.overlay,
        )
        self.assertNotIn("quantizeProtocolGeometry", self.overlay)
        self.assertIn("protocolGeometrySettled", self.overlay)

    def _quantize_floor(self, value: float, quantum: int) -> int:
        return max(0, math.floor(value / quantum) * quantum)

    def test_t23_collapse_to_clock_bypasses_compositor_morph(self) -> None:
        # T23: the P05 compositor region morph's first frame maps the
        # target-committed (small) clock onto the previous (larger) footprint,
        # scaling it up before shrinking back — the "magnified clock then
        # recovers" symptom. Collapsing into resting_time must fall back to the
        # client eased/spring driver instead. The bypass is one shared gate
        # (compositorMorphAllowed) read by all three geometry drivers, so the
        # radius does not snap ahead of the still-easing width/height.
        self.assertIn("readonly property bool compositorMorphAllowed", self.overlay)
        gate = re.search(
            r"readonly property bool compositorMorphAllowed:\s*([^\n]+(?:\n[ \t]+[^\n]+)*)",
            self.overlay,
        )
        self.assertIsNotNone(gate)
        gate_text = gate.group(1)
        self.assertIn("root.compositorMorph", gate_text)
        self.assertIn('"resting_time"', gate_text)
        # All three geometry drivers route on the shared gate, not the raw
        # protocol-availability flag — collapse-to-clock must not snap.
        for fn_name in ("retargetWidthDriver", "retargetHeightDriver", "retargetRadiusDriver"):
            with self.subTest(driver=fn_name):
                body = _function_body(self.overlay, fn_name)
                self.assertTrue(body, f"{fn_name} body not found")
                self.assertIn("root.compositorMorphAllowed", body)
                self.assertNotIn("root.compositorMorph ", body)
                self.assertNotIn("root.compositorMorph&&", body)

    def _quantize_ceil(self, value: float, quantum: int) -> int:
        return max(0, math.ceil(value / quantum) * quantum)

    def test_floor_quantization_never_overhangs_painted_capsule(self) -> None:
        # The white-bar regression (R08 / user report): collapsing to compact
        # media (height 36) with round-to-nearest-8 held the region at 40 for
        # the whole animation tail — a 4px band of raw glass under the painted
        # bottom edge, snapping away at settle. Floor quantization keeps the
        # region inside the painted rect at every animated height.
        legacy_round8 = round(36.01 / 8) * 8
        self.assertEqual(legacy_round8, 40)  # the old overhang
        for height in (36.01, 39.9, 44.0, 165.9, 76.3):
            proto = self._quantize_floor(height, 2)
            self.assertLessEqual(proto, height)
        # Radius ceils but is re-clamped to the submitted size.
        for radius, proto_w, proto_h in ((17.2, 200, 34), (29.8, 416, 164)):
            proto_r = min(
                self._quantize_ceil(radius, 2), proto_w // 2, proto_h // 2
            )
            self.assertGreaterEqual(proto_r, 0)
            self.assertLessEqual(proto_r, proto_h / 2)

    def test_protocol_geometry_quantization_reduces_240hz_commits(self) -> None:
        # Deceleration tail is where 240Hz commit spam lived: sub-quantum
        # movement per frame must dedupe. Simulate an OutCubic morph.
        samples = 54
        raw = []
        quantized = []
        for index in range(samples):
            t = index / (samples - 1)
            progress = 1 - (1 - t) ** 3
            width = 224 + (440 - 224) * progress
            height = 40 + (176 - 40) * progress
            radius = 20 + (32 - 20) * progress
            raw.append((round(width), round(height), round(radius)))
            if index == samples - 1:
                quantized.append((440, 176, 32))
            else:
                quantized.append(
                    (
                        self._quantize_floor(width, 2),
                        self._quantize_floor(height, 2),
                        self._quantize_ceil(radius, 2),
                    )
                )

        def commit_count(values: list[tuple[int, int, int]]) -> int:
            return 1 + sum(before != after for before, after in zip(values, values[1:]))

        self.assertLess(commit_count(quantized), commit_count(raw))

    def test_glass_geometry_spring_is_clamped_driver_only(self) -> None:
        # R08: springs drive island driver values only; the surface binds
        # clamp(driver, min, max) and the region submits quantized clamped
        # values, so the region cannot leave the layer surface at overshoot.
        self.assertEqual(self.overlay.count("SpringAnimation {"), 2)
        self.assertIn("property real islandDriverWidth", self.overlay)
        self.assertIn("property real islandDriverHeight", self.overlay)
        self.assertIn("property real islandDriverRadius", self.overlay)
        self.assertIn(
            "Math.min(root.islandDriverWidth, root.maxCapsuleWidth)", self.overlay
        )
        self.assertIn(
            "Math.min(root.islandDriverHeight, root.driverHeightMax)", self.overlay
        )
        # Height clamp is bounded by the layer surface below the top inset.
        self.assertIn("root.capsuleTargetTop))", self.overlay)
        self.assertIn("width: root.islandAnimatedWidth", self.overlay)
        self.assertIn("height: root.islandAnimatedHeight", self.overlay)
        self.assertIn("root.islandAnimatedRadius", self.overlay)
        # x derives from the live width (centered under spring and swipe alike).
        self.assertIn("x: (root.screenWidth - width) / 2", self.overlay)
        # No Behavior may animate the surface geometry channels themselves.
        for prop in ("x", "y", "width", "height", "radius"):
            self.assertNotRegex(self.overlay, rf"Behavior on {prop}\b")
        self.assertIn("Behavior on fillColor", self.overlay)
        self.assertIn("Behavior on opacity", self.overlay)
        # Region submission marker.
        self.assertIn("clamped + floor-quantized", self.overlay)
        self.assertIn("scale: 1.0", self.overlay)
        # No contentScale spring revival.
        self.assertNotIn("contentScaleSpring", self.overlay)

    def test_content_loader_scene_host(self) -> None:
        self.assertIn("id: mediaLoader", self.content)
        self.assertIn("active: root.mediaLoaderActive", self.content)
        self.assertIn("mediaUnloadHold", self.content)
        self.assertIn("sourceComponent: mediaSceneComponent", self.content)
        # T18: summary Loader retired; workspace is a dedicated lightweight scene.
        self.assertNotIn("id: summaryLoader", self.content)
        self.assertNotIn("summaryLoaderActive", self.content)
        self.assertIn("DynamicIslandWorkspaceView", self.content)
        # No always-on expanded media instances outside Loader.
        self.assertNotRegex(
            self.content,
            r"DynamicIslandMediaView\s*\{\s*\n\s*id:\s*mediaView",
        )
        self.assertNotIn("DynamicIslandSummaryView", self.content)
        # Loader activates only when content becomes visible / exit hold.
        self.assertIn("mediaLoaderActive = true", self.content)
        self.assertIn("mediaLoaderActive = false", self.content)
        self.assertIn("property bool mediaLoaderActive: false", self.content)
        self.assertIn("id: notificationLoader", self.content)
        self.assertIn("active: root.notificationLoaderActive", self.content)
        self.assertIn("sourceComponent: notificationSceneComponent", self.content)
        self.assertNotIn("id: notificationView", self.content)
        self.assertNotIn("id: detailRow", self.content)
        self.assertNotIn("id: progressTrack", self.content)

    def test_no_dual_render_of_expanded_scenes(self) -> None:
        # Expanded media appears only as Component source for Loader.
        media_hits = len(re.findall(r"DynamicIslandMediaView\s*\{", self.content))
        self.assertEqual(media_hits, 1)
        self.assertEqual(self.content.count("DynamicIslandSummaryView"), 0)
        self.assertIn("id: mediaSceneComponent", self.content)

    def test_governance_documents_island_recipe(self) -> None:
        self.assertIn("DynamicIsland", self.gov)
        self.assertRegex(self.gov, r"DynamicIsland\s*\|\s*1\s*\|\s*`pill`")
        self.assertIn("禁止 Spring 直接驱动 region 通道", self.gov)
        self.assertIn("islandDriver*", self.gov)
        self.assertIn("SettingsTheme island tokens", self.gov)
        self.assertIn("Loader", self.gov)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
