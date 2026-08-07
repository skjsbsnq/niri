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
        # Union-hold plumbing: fallback is the animated footprint; matching
        # compositor terminal feedback ends the hold.
        self.assertIn(
            "readonly property real maskWidth: morphMaskHeld\n"
            "        ? Math.max(root.morphMaskHoldWidth, root.islandAnimatedWidth)\n"
            "        : root.islandAnimatedWidth",
            self.overlay,
        )
        self.assertIn(
            "readonly property real maskHeight: morphMaskHeld\n"
            "        ? Math.max(root.morphMaskHoldHeight, root.islandAnimatedHeight)\n"
            "        : root.islandAnimatedHeight",
            self.overlay,
        )
        self.assertNotIn("v2CompositorMorphMaskHoldMs", self.motion)
        self.assertNotIn("morphMaskHoldTimer", self.overlay)
        # holdMorphMask() must capture the pre-snap footprint and the serial
        # allocated by the successful queue request.
        hold_fn = re.search(
            r"function\s+holdMorphMask\(\)\s*\{([\s\S]*?)\n    \}",
            self.overlay,
        )
        self.assertIsNotNone(hold_fn)
        hold_body = hold_fn.group(1)
        self.assertIn("root.morphMaskHoldWidth", hold_body)
        self.assertIn("root.morphMaskHoldHeight", hold_body)
        self.assertIn("root.morphMaskHeld = true", hold_body)
        self.assertIn("root.TahoeGlass.activeTransformSerial", hold_body)
        self.assertIn("function onTransformFinished(serial, status)", self.overlay)
        # S-L4: the mask hold is armed only after a morph request succeeds —
        # arming unconditionally swallowed clicks for the full hold window
        # when the queue failed (no surface / bad region). It still runs
        # inside queueCompositorMorph, which returns before the drivers snap,
        # so the captured footprint is the pre-snap (old) value.
        queue_fn = re.search(
            r"function\s+queueCompositorMorph\(\)\s*\{([\s\S]*?)\n    \}",
            self.overlay,
        )
        self.assertIsNotNone(queue_fn)
        queue_body = queue_fn.group(1)
        self.assertIn("var ok", queue_body)
        self.assertIn("if (ok)", queue_body)
        hold_call = queue_body.find("root.holdMorphMask();")
        first_request = queue_body.find("root.TahoeGlass.queueRegionMorph")
        self.assertGreater(hold_call, -1)
        self.assertGreater(first_request, -1)
        # Hold is conditional on success AND runs after the morph request.
        self.assertGreater(hold_call, first_request)
        # Both geometry drivers must queue the morph (capturing the pre-snap
        # footprint) before snapping to the target; a snap-first reorder
        # loses the old footprint from the union (historical hit-gap bug).
        for fn_name, snap_stmt in (
            ("retargetWidthDriver", "root.islandDriverWidth = root.capsuleTargetWidth;"),
            ("retargetHeightDriver", "root.islandDriverHeight = root.capsuleTargetHeight;"),
            # S-L4: radius now reads the queue result too (no independent snap
            # that desyncs from width/height on a failed queue).
            ("retargetRadiusDriver", "root.islandDriverRadius = root.capsuleTargetRadius;"),
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
        # client eased/spring driver instead.
        #
        # The bypass is evaluated INLINE inside each retarget*Driver — NOT as a
        # shared readonly property binding. A sibling binding on
        # effectiveGeometryState is not guaranteed to flush before
        # capsuleTarget*'s change-signal fires (Qt does not promise binding
        # evaluation order), so reading it in the change-signal handler could
        # return the stale previous-frame value: collapse-to-clock would still
        # ride the compositor morph (first-frame scale-up) and expand would
        # skip it (content snapping, no smooth scale). Reading
        # effectiveGeometryState directly in the driver body is fresh because
        # by the time capsuleTarget* changed enough to emit, EGS has already
        # settled. All three drivers share the inline condition so width/
        # height/radius route together (radius does not snap ahead of the
        # still-easing width/height). There must be no leftover
        # compositorMorphAllowed binding either — that is the stale-read trap.
        #
        # T25 EXTENSION: the same inline gate now ALSO excludes the media states
        # (resting_media / expanded_media). Media expand/collapse (and enter/exit
        # media resting_time<->resting_media) bypasses the compositor's
        # whole-surface affine scale and rides the client driver instead, so the
        # content's own staged morph is the SINGLE transform on text/buttons/cover
        # — no double-amplify (compositor scale + content morph stacked on the
        # same elements). Same inline-state rationale; all three drivers exclude
        # the same three states so width/height/radius route together.
        self.assertNotIn("compositorMorphAllowed", self.overlay)
        for fn_name in ("retargetWidthDriver", "retargetHeightDriver", "retargetRadiusDriver"):
            with self.subTest(driver=fn_name):
                body = _function_body(self.overlay, fn_name)
                self.assertTrue(body, f"{fn_name} body not found")
                self.assertIn("root.compositorMorph", body)
                self.assertIn("root.effectiveGeometryState", body)
                self.assertIn('"resting_time"', body)
                # Lock the exclusion direction: collapse-to-clock must be
                # excluded (!==), never only-included (=== would snap it).
                self.assertIn('!== "resting_time"', body)
                # T25: media states are excluded the same way.
                self.assertIn('!== "resting_media"', body)
                self.assertIn('!== "expanded_media"', body)
                # The compositor-availability flag must be gated by the
                # resting_time exclusion in the same condition — never the
                # raw flag alone (that would snap collapse-to-clock).
                cm = body.index("root.compositorMorph")
                rt = body.index('"resting_time"')
                self.assertLess(cm, rt, f"{fn_name}: resting_time guard must follow compositorMorph")
                # All three exclusions must appear after compositorMorph in the
                # same condition (they all guard the same if).
                rm = body.index('"resting_media"', rt)
                em = body.index('"expanded_media"', rm)
                self.assertLess(cm, rm, f"{fn_name}: resting_media guard must follow compositorMorph")
                self.assertLess(cm, em, f"{fn_name}: expanded_media guard must follow compositorMorph")

    def test_t25_media_morph_bypasses_compositor_no_double_amplify(self) -> None:
        # T25: the T24 fix decoupled mediaExpandProgress to an independent
        # client clock (compositor snaps geometry, content morph rides its own
        # timeline). That stacked TWO transforms on the same elements — the
        # compositor's whole-surface proportional scale AND the content's staged
        # morph (font scaled twice, buttons translated twice, cover moved twice)
        # — the "font flashes / controls pop in / cover snaps / buttons jump on
        # collapse" double-amplify symptom. T25 REVERSES that: the media path
        # (resting_media<->expanded_media, plus enter/exit media
        # resting_time<->resting_media) BYPASSES the compositor morph entirely
        # (see test_t23_* for the shared inline gate) and rides the client
        # eased/spring driver, so the geometry is continuous and the height IS the
        # content clock. mediaExpandProgress goes back to a readonly height-binding
        # (the legacyMediaExpandProgress formula, preserved verbatim). The content
        # staged morph is now the SINGLE transform — what reads as smooth.
        # The T24 independent-clock machinery (claim/arm/release + spring/ease
        # animations + the gate property) is fully retired.
        # mediaExpandProgress is a readonly binding onto legacyMediaExpandProgress
        # again (NOT a writable animation target).
        self.assertIn("readonly property real mediaExpandProgress: root.legacyMediaExpandProgress", self.overlay)
        # No writable (animation-driven) declaration of mediaExpandProgress —
        # only the readonly binding above. (Substring-safe: match the writable
        # form at line start, which the readonly prefix excludes.)
        self.assertNotRegex(self.overlay, r"(?<!readonly )property real mediaExpandProgress\b")
        # The legacy height-bound formula is preserved verbatim.
        self.assertIn("readonly property real legacyMediaExpandProgress", self.overlay)
        # The full T24 independent-clock machinery is gone.
        for gone in (
            "mediaProgressDrivenByAnimation",
            "claimMediaContentMorph",
            "armMediaContentMorph",
            "releaseMediaContentMorph",
            "id: mediaContentMorphSpring",
            "id: mediaContentMorphEase",
            "onLegacyMediaExpandProgressChanged",
            "onMediaProgressDrivenByAnimationChanged",
        ):
            self.assertNotIn(gone, self.overlay, f"stale T24 reference: {gone}")
        # Motion.js epsilon for the retired content-progress spring is gone.
        self.assertNotIn("v2ContentProgressSpringEpsilon", self.motion)
        self.assertNotIn("var v2ContentProgressSpringEpsilon", self.motion)
        # The height driver's compositor branch no longer claims/arms the
        # independent clock — it only snaps geometry (and media states never
        # reach this branch anyway, since the gate excludes them).
        h = _function_body(self.overlay, "retargetHeightDriver")
        self.assertTrue(h)
        self.assertNotIn("claimMediaContentMorph", h)
        self.assertNotIn("armMediaContentMorph", h)
        self.assertNotIn("releaseMediaContentMorph", h)
        # syncGeometryDriversImmediately no longer releases content ownership.
        sync = _function_body(self.overlay, "syncGeometryDriversImmediately")
        self.assertTrue(sync)
        self.assertNotIn("releaseMediaContentMorph", sync)
        # onSwipeInteractiveChanged no longer releases content ownership
        # (it still cancels any in-flight compositor transform for non-media
        # paths). mediaExpandProgress follows the live height 1:1 via the
        # readonly binding — no independent clock to release.
        self.assertIn("onSwipeInteractiveChanged", self.overlay)
        self.assertNotIn("releaseMediaContentMorph()", self.overlay)
        # No mediaExpandProgress is driven by any animation now (the spring
        # count test in test_glass_geometry_spring_is_clamped_driver_only
        # asserts the count is back to 2 and no animation targets it).

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
        # T25: only the two GEOMETRY-driver springs (width/height) remain —
        # the media content-progress spring (T24 mediaContentMorphSpring) is
        # gone now that the media path bypasses the compositor morph and
        # mediaExpandProgress is back to a readonly height-binding. The R08
        # region-leave guard therefore still holds at 2 geometry springs.
        self.assertEqual(self.overlay.count("SpringAnimation {"), 2)
        self.assertEqual(
            self.overlay.count("property: \"mediaExpandProgress\""), 0,
            "mediaExpandProgress is a readonly height-binding again (T25), "
            "not driven by any SpringAnimation/NumberAnimation",
        )
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
