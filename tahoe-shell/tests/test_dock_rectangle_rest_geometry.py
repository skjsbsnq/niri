#!/usr/bin/env python3
"""T-19 + T-21 contract tests: genie target REST geometry + shelf scene-offset +
predicted slot + frame-synced settle republish.

Source-level guards (same style as test_dock_rectangle_publisher.py) for the
S-H2 / S-M3 / S-M8 remediation: the foreign-toplevel rectangle reported by the
Dock delegates must be REST geometry (no hover-wave magnification/pushX, no
lifecycle/press scale, no click bounce), the minimized shelf must forward a
scene-offset dependency so reflow/scroll republishes, and Dock must expose the
predicted appended shelf slot for an initial minimize into an open shelf.

T-21 adds the frame-sync contract: a debounced ``dockRectangleSettle`` Timer
(interval = the layout-Behavior duration ``Motion.elementResize``) force-reports
REST geometry once the slot/ancestor Behavior ends, so the settled rect reaches
niri for a T-20 in-flight genie retarget.
"""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WINDOW_BUTTON = ROOT / "components" / "WindowButton.qml"
DOCK_MINIMIZED = ROOT / "components" / "DockMinimizedWindow.qml"
DOCK_MINIMIZED_SHELF = ROOT / "components" / "DockMinimizedShelf.qml"
DOCK = ROOT / "components" / "Dock.qml"
DOCK_WINDOW_MENU = ROOT / "components" / "DockWindowMenu.qml"
SHELL = ROOT / "shell.qml"


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
            "function dockWaveSurfaceBias",
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


class DockRectangleFrameSyncTests(unittest.TestCase):
    """T-21 contract: a debounced dockRectangleSettle Timer force-reports REST
    geometry once the slot/ancestor Behavior (duration Motion.elementResize)
    ends, so the settled rect reaches niri for a T-20 in-flight genie retarget.

    The interval-0 dockRectangleRefresh still handles the immediate per-frame
    report; the settle Timer only adds the post-Behavior force. Source-contract
    style — a live Behavior cannot be simulated headlessly.
    """

    def setUp(self) -> None:
        self.window_button = WINDOW_BUTTON.read_text(encoding="utf-8")
        self.dock_minimized = DOCK_MINIMIZED.read_text(encoding="utf-8")

    def _settle_block(self, text: str) -> str:
        # The dockRectangleSettle Timer body, between its id and its force onTriggered.
        return code_only(
            slice_between(
                text,
                "id: dockRectangleSettle",
                "onTriggered: root.updateDockRectangle(true)",
            )
        )

    def test_window_button_settle_timer_uses_behavior_duration(self) -> None:
        # interval is the layout-Behavior duration (not a literal), so
        # reduced-motion (elementResize == 0) collapses it to fire immediately.
        block = self._settle_block(self.window_button)
        self.assertIn("interval: Motion.elementResize(root.settingsService)", block)
        self.assertIn("repeat: false", block)
        self.assertNotIn("interval: 0", block)

    def test_dock_minimized_settle_timer_uses_behavior_duration(self) -> None:
        block = self._settle_block(self.dock_minimized)
        self.assertIn("interval: Motion.elementResize(root.settingsService)", block)
        self.assertIn("repeat: false", block)
        self.assertNotIn("interval: 0", block)

    def test_settle_timer_force_publishes(self) -> None:
        # onTriggered must force-publish (true) so the settled value bypasses the
        # publisher's Qt.callLater coalescing and reaches niri synchronously.
        for text in (self.window_button, self.dock_minimized):
            self.assertIn("onTriggered: root.updateDockRectangle(true)", text)

    def test_schedule_restarts_both_timers_in_order(self) -> None:
        # scheduleDockRectangleUpdate debounces: restart the per-frame refresh,
        # then the settle Timer (continuous changes keep pushing the settle out
        # until elementResize ms after the last change).
        for text in (self.window_button, self.dock_minimized):
            assert_in_order(
                self,
                text,
                "dockRectangleRefresh.restart()",
                "dockRectangleSettle.restart()",
            )

    def test_settle_augments_not_replaces_per_frame_refresh(self) -> None:
        # Both Timers coexist: the interval-0 refresh reports per-frame, the
        # settle Timer adds the post-Behavior force.
        for text in (self.window_button, self.dock_minimized):
            self.assertIn("id: dockRectangleRefresh", text)
            self.assertIn("id: dockRectangleSettle", text)

    def test_settle_force_suppressed_while_fullscreen(self) -> None:
        # The settle's force onTriggered must not publish into an unmapped dock
        # (a settle armed just before fullscreen activated can still fire). The
        # force path guards on dockFullscreenActive, not only scheduleDockRectangleUpdate.
        for text in (self.window_button, self.dock_minimized):
            update = slice_code(
                text,
                "function updateDockRectangle",
                "function scheduleDockRectangleUpdate",
            )
            self.assertIn("if (forcePublish && root.dockFullscreenActive)", update)

    def test_minimize_stops_settle_after_predicted_slot(self) -> None:
        # T21 review finding: a settle armed by an earlier layout change can
        # fire after minimize() force-published the predicted shelf slot and
        # override it with this dying button's rest rect (wrong genie target).
        # Every minimize path must stop the timers right after the predicted-slot
        # publish so the predicted slot is the last word from this button.
        helper = slice_between(
            self.window_button,
            "function stopDockRectangleTimers()",
            "function minimizeTargetRect()",
        )
        self.assertIn("dockRectangleRefresh.stop()", helper)
        self.assertIn("dockRectangleSettle.stop()", helper)

        minimize_fn = slice_between(
            self.window_button, "function minimize(", "onXChanged:"
        )
        assert_in_order(
            self,
            minimize_fn,
            "updateDockRectangle(true, root.minimizeTargetRect())",
            "stopDockRectangleTimers()",
        )
        self.assertEqual(minimize_fn.count("stopDockRectangleTimers()"), 1)

        # restoreOrActivate has two minimize branches (isFocused + toplevel
        # activated); each stops the timers after its predicted-slot publish.
        restore_fn = slice_between(
            self.window_button, "function restoreOrActivate(", "function minimize("
        )
        self.assertEqual(restore_fn.count("stopDockRectangleTimers()"), 2)
        self.assertEqual(restore_fn.count("updateDockRectangle(true, root.minimizeTargetRect())"), 2)


class ContextMenuMinimizeRoutingTests(unittest.TestCase):
    """T-21 blocker fix: the context-menu "最小化" must route through
    WindowButton.minimize() so it runs the publish-predicted-slot →
    stopDockRectangleTimers invariant, not a bare windowsService.minimize that
    (a) never publishes the predicted shelf slot and (b) lets a settle armed by
    an earlier layout change retarget the Genie back at the vanishing icon.
    """

    def setUp(self) -> None:
        self.dock_menu = DOCK_WINDOW_MENU.read_text(encoding="utf-8")
        self.dock = DOCK.read_text(encoding="utf-8")
        self.window_button = WINDOW_BUTTON.read_text(encoding="utf-8")
        self.shell = SHELL.read_text(encoding="utf-8")

    def test_menu_emits_signal_instead_of_direct_minimize(self) -> None:
        # The minimize row emits minimizeRequested(window) and must NOT call
        # windowsService.minimize directly (that bypasses the invariant).
        minimize_fn = slice_between(
            self.dock_menu,
            "root.windowMinimized ? \"已最小化\" : \"最小化\"",
            "windowPinned ? \"从 Dock 移除\"",
        )
        self.assertIn("root.minimizeRequested(root.window)", minimize_fn)
        self.assertNotIn("windowsService.minimize", minimize_fn)
        self.assertIn("signal minimizeRequested(var window)", self.dock_menu)

    def test_dock_declares_request_minimize_signal(self) -> None:
        self.assertIn("signal requestMinimizeWindowButton(var window)", self.dock)

    def test_window_button_handles_request_signal(self) -> None:
        # WindowButton must connect to dockWindow's requestMinimizeWindowButton,
        # match the source window to itself by STABLE id (not reference — the
        # service layer rebuilds model objects on layout churn), and call
        # root.minimize() (the invariant path).
        conn = slice_code(
            self.window_button,
            "// T21: route the context-menu",
            "// Mag/push are bound to targets",
        )
        self.assertIn("target: root.dockWindow", conn)
        self.assertIn("function onRequestMinimizeWindowButton(window)", conn)
        # id-based match (survives model rebuilds), with a ref fallback for the
        # no-id case (mirrors onOpenWindowMenu's wasSameWindow fallback).
        self.assertIn("svc.windowIdString(window)", conn)
        self.assertIn("svc.windowIdString(self)", conn)
        self.assertIn("a === b", conn)
        self.assertIn("window === self", conn)
        self.assertIn("root.minimize()", conn)
        # Must NOT match by bare reference alone (that no-ops on model rebuild).
        self.assertNotIn("window === root.windowModel", conn)

    def test_shell_routes_menu_signal_to_dock(self) -> None:
        # The DockWindowMenu instance handles onMinimizeRequested by calling the
        # same-scope Dock instance's requestMinimizeWindowButton and closing the
        # menu (the menu dismissed right after minimize, matching direct-minimize
        # behavior where the menu also closes).
        menu_instance = slice_between(self.shell, "id: dockWindowMenu", "onCloseRequested: shell.closeDockMenus()")
        self.assertIn("onMinimizeRequested: function(window)", menu_instance)
        self.assertIn("dock.requestMinimizeWindowButton(window)", menu_instance)
        self.assertIn("shell.closeDockWindowMenu()", menu_instance)
        # The Dock instance must have an id so the sibling DockWindowMenu can
        # address it.
        dock_instance = slice_between(self.shell, "Dock {", "DockAppMenu {")
        self.assertIn("id: dock", dock_instance)


if __name__ == "__main__":
    unittest.main()
