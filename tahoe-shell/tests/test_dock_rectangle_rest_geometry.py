#!/usr/bin/env python3
"""T-19 contract tests: genie target REST geometry + shelf scene-offset + predicted slot.

Source-level guards (same style as test_dock_rectangle_publisher.py) for the
S-H2 / S-M3 / S-M8 remediation: the foreign-toplevel rectangle reported by the
Dock delegates must be REST geometry (no hover-wave magnification/pushX, no
lifecycle/press scale, no click bounce), the minimized shelf must forward a
scene-offset dependency so reflow/scroll republishes, and Dock must expose the
predicted appended shelf slot for an initial minimize into an open shelf.
"""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WINDOW_BUTTON = ROOT / "components" / "WindowButton.qml"
DOCK_MINIMIZED = ROOT / "components" / "DockMinimizedWindow.qml"
DOCK_MINIMIZED_SHELF = ROOT / "components" / "DockMinimizedShelf.qml"
DOCK = ROOT / "components" / "Dock.qml"


def slice_between(text: str, start: str, end: str) -> str:
    i = text.index(start)
    j = text.index(end)
    assert i < j, f"{start!r} must precede {end!r}"
    return text[i:j]


def code_only(text: str) -> str:
    # Strip `//` line comments so the remediation comments (which name the very
    # tokens we forbid) do not false-positive. Mirrors the r16 source guard.
    return "\n".join(line.split("//", 1)[0] for line in text.splitlines())


def slice_code(text: str, start: str, end: str) -> str:
    return code_only(slice_between(text, start, end))


def assert_in_order(testcase: unittest.TestCase, text: str, first: str, second: str) -> None:
    i = text.find(first)
    j = text.find(second)
    testcase.assertGreaterEqual(i, 0, f"{first!r} not found")
    testcase.assertGreaterEqual(j, 0, f"{second!r} not found")
    testcase.assertLess(i, j, f"{first!r} must precede {second!r}")


class WindowButtonRestGeometryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = WINDOW_BUTTON.read_text(encoding="utf-8")
        self.update = slice_code(
            self.text,
            "function updateDockRectangle",
            "function scheduleDockRectangleUpdate",
        )

    def test_update_signature_takes_override_rect(self) -> None:
        self.assertIn("function updateDockRectangle(forcePublish, overrideRect)", self.text)

    def test_report_maps_from_root_not_icon(self) -> None:
        # REST geometry maps from the delegate Item (no scale), not the icon
        # (which carries magnification*pressScale + pushX Translate).
        self.assertIn("root.mapToItem(null, icon.x", self.update)
        self.assertIn("restIconY", self.update)
        self.assertNotIn("icon.mapToItem(null", self.update)

    def test_report_excludes_wave_press_and_bounce(self) -> None:
        # The hover wave, press scale and click bounce are visual-only and must
        # not appear in the rectangle math.
        self.assertNotIn("magnification", self.update)
        self.assertNotIn("pushX", self.update)
        self.assertNotIn("pressScale", self.update)
        self.assertNotIn("bounceOffset", self.update)

    def test_override_rect_branch_present(self) -> None:
        self.assertIn("overrideRect", self.update)

    def test_minimize_uses_predicted_shelf_slot(self) -> None:
        self.assertIn("predictedMinimizeSlotSceneRect", self.text)
        self.assertIn("hasMinimizedWindows", self.text)

    def test_wave_bounce_change_handlers_removed(self) -> None:
        # These handlers existed only to refresh a hint that included the wave;
        # with REST geometry they are gone (slot/layout/scene-offset remain).
        # Match the real-code call form (with parens), as test_edge_reveal does.
        self.assertNotIn("onMagnificationChanged: scheduleDockRectangleUpdate()", self.text)
        self.assertNotIn("onPushXChanged: scheduleDockRectangleUpdate()", self.text)
        self.assertNotIn("onBounceOffsetChanged: scheduleDockRectangleUpdate()", self.text)

    def test_minimize_publishes_predicted_before_request(self) -> None:
        # Every minimize branch must publish the predicted shelf slot (or button
        # rest fallback) before sending the Wayland minimize request, so the
        # genie has its target before niri reads the cached anchor.
        minimize_fn = slice_between(self.text, "function minimize(", "onXChanged:")
        restore_fn = slice_between(
            self.text, "function restoreOrActivate(", "function minimize("
        )
        assert_in_order(
            self,
            minimize_fn,
            "updateDockRectangle(true, root.minimizeTargetRect())",
            "windowsService.minimize",
        )
        # restoreOrActivate's isFocused (left-click) minimize branch uses the
        # predicted slot too, ahead of the minimize request.
        assert_in_order(
            self,
            restore_fn,
            "updateDockRectangle(true, root.minimizeTargetRect())",
            "windowsService.minimize",
        )


class DockMinimizedWindowRestGeometryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = DOCK_MINIMIZED.read_text(encoding="utf-8")
        self.update = slice_code(
            self.text,
            "function updateDockRectangle",
            "function scheduleDockRectangleUpdate",
        )

    def test_report_maps_from_parent_not_preview_frame(self) -> None:
        # Map from root.parent (ListView contentItem, no scale) so the reported
        # rect is not shrunk by lifecycleScale*pressScale (S-M8).
        self.assertIn("root.parent", self.update)
        self.assertIn("mapToItem(null, restX, restY)", self.update)
        self.assertNotIn("previewFrame.mapToItem", self.update)

    def test_report_excludes_scale_and_bounce(self) -> None:
        self.assertNotIn("bounceOffset", self.update)
        self.assertNotIn("root.scale", self.update)
        self.assertNotIn("lifecycleScale", self.update)

    def test_scene_offset_props_and_handlers(self) -> None:
        self.assertIn("property real dockSceneOffsetX: 0", self.text)
        self.assertIn("property real dockSceneOffsetY: 0", self.text)
        self.assertIn("onDockSceneOffsetXChanged: scheduleDockRectangleUpdate()", self.text)
        self.assertIn("onDockSceneOffsetYChanged: scheduleDockRectangleUpdate()", self.text)

    def test_bounce_change_handler_removed(self) -> None:
        self.assertNotIn("onBounceOffsetChanged: scheduleDockRectangleUpdate()", self.text)

    def test_fullscreen_parity_props_and_block(self) -> None:
        # Mirror WindowButton: undo the dockRow fullscreen slide and suppress
        # republish while the Dock layer is unmapped for fullscreen (niri wipes
        # rects on unmap; without this the shelf hint is stale after fullscreen).
        self.assertIn("property real dockFullscreenOffset: 0", self.text)
        self.assertIn("property bool dockFullscreenActive: false", self.text)
        self.assertIn("function dockRectanglePublishBlocked()", self.text)
        self.assertIn("return root.dockFullscreenActive", self.text)

    def test_fullscreen_offset_undone_in_rect(self) -> None:
        # The hint must report the revealed position, so the fullscreen slide is
        # subtracted alongside the autohide slide.
        self.assertIn("root.dockFullscreenOffset", self.update)
        self.assertIn("- root.dockSlideOffset - root.dockFullscreenOffset", self.update)

    def test_fullscreen_change_handlers(self) -> None:
        self.assertIn("onDockFullscreenOffsetChanged: scheduleDockRectangleUpdate()", self.text)
        self.assertIn("onDockFullscreenActiveChanged:", self.text)
        # Republish only once fullscreen clears (not while still active).
        self.assertIn("if (!root.dockFullscreenActive)", self.text)


class DockShelfOffsetAndPredictionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.dock = DOCK.read_text(encoding="utf-8")
        self.shelf = DOCK_MINIMIZED_SHELF.read_text(encoding="utf-8")

    def test_minimized_section_scene_offset_properties(self) -> None:
        self.assertIn("readonly property real minimizedSectionSceneOffsetX", self.dock)
        self.assertIn("readonly property real minimizedSectionSceneOffsetY", self.dock)
        # Drives off the shelf's viewport content so scroll republishes.
        self.assertIn("minimizedShelf.viewportContentX", self.dock)

    def test_predicted_slot_function(self) -> None:
        self.assertIn("function predictedMinimizeSlotSceneRect", self.dock)
        body = slice_code(
            self.dock,
            "function predictedMinimizeSlotSceneRect",
            "// Glass must never grow with the wave",
        )
        # Derives from the single-source constants, not literals.
        self.assertIn("dockMinimizedThumbnailWidth", body)
        self.assertIn("minimizedShelf.shelfSpacing", body)
        self.assertIn("minimizedShelf.thumbnailHeight", body)
        self.assertIn("minimizedWindowButtonCount", body)
        self.assertIn("minimizedSectionSceneOffsetX", body)
        # T19 finding 2: the shelf preserves niri's spatial column/tile order
        # (filteredMinimized is filtered, not re-sorted), so the new thumbnail
        # lands at an unknowable position among the already-minimized windows —
        # not appended at the end. Predict the shelf-content CENTER as a neutral
        # initial target (T-20 retargets to the real thumbnail regardless).
        self.assertIn("count + 1", body)
        self.assertIn("contentWidth", body)
        self.assertIn("centerX", body)
        self.assertNotIn("count * (tw + spacing)", body)

    def test_shelf_instance_binds_scene_offset(self) -> None:
        self.assertIn("id: minimizedShelf", self.dock)
        self.assertIn("dockSceneOffsetX: root.minimizedSectionSceneOffsetX", self.dock)
        self.assertIn("dockSceneOffsetY: root.minimizedSectionSceneOffsetY", self.dock)

    def test_dock_passes_fullscreen_to_shelf(self) -> None:
        # Dock mirrors the WindowButton wiring so the shelf undoes the fullscreen
        # slide and suppresses republish while the Dock layer is unmapped.
        self.assertIn(
            "dockFullscreenOffset: root.fullscreenTransition * root.dockSurfaceHeight",
            self.dock,
        )
        self.assertIn("dockFullscreenActive: root.fullscreenActive", self.dock)

    def test_shelf_forwards_fullscreen_to_delegate(self) -> None:
        self.assertIn("property real dockFullscreenOffset: 0", self.shelf)
        self.assertIn("property bool dockFullscreenActive: false", self.shelf)
        self.assertIn("dockFullscreenOffset: root.dockFullscreenOffset", self.shelf)
        self.assertIn("dockFullscreenActive: root.dockFullscreenActive", self.shelf)

    def test_shelf_single_source_constants_and_forwarding(self) -> None:
        self.assertIn("property int shelfSpacing: 8", self.shelf)
        self.assertIn("property int thumbnailHeight: 62", self.shelf)
        self.assertIn("readonly property real viewportContentX: viewport.contentX", self.shelf)
        self.assertIn("readonly property real viewportContentY: viewport.contentY", self.shelf)
        self.assertIn("property real dockSceneOffsetX: 0", self.shelf)
        self.assertIn("property real dockSceneOffsetY: 0", self.shelf)
        # ListView consumes the single-source spacing.
        self.assertIn("spacing: root.shelfSpacing", self.shelf)
        # Delegate consumes the single-source height + scene offset.
        self.assertIn("height: root.thumbnailHeight", self.shelf)
        self.assertIn("dockSceneOffsetX: root.dockSceneOffsetX", self.shelf)
        self.assertIn("dockSceneOffsetY: root.dockSceneOffsetY", self.shelf)

    def test_constants_aligned_with_existing_width(self) -> None:
        # Guard against silent drift of the thumbnail width used by the shelf.
        self.assertIn("readonly property int dockMinimizedThumbnailWidth: 112", self.dock)


if __name__ == "__main__":
    unittest.main()
