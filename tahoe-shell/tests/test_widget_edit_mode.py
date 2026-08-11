"""A6 contract tests: long-press edit mode + drag repositioning.

Source-level guards (repo style) for roadmap A6:

1. GESTURE PATTERN (A-C2): Widget.qml owns the four-state MouseArea
   (onPressed / onPositionChanged with threshold + suppressNextClick /
   onReleased / onCanceled full rollback), mirroring Dock.qml:1396-1470.
   No DragHandler / Drag / DropArea anywhere in widgets/.
2. HOST DRAG API: WidgetHost owns begin/update/commit/cancel + grid
   placement + one-shot persistence (A-C5) — update/begin never write.
3. EDIT VISUALS (A-C3 / P-1 / P-3): wobble gated on editMode, NumberAnimation
   only (no Spring), durations from Motion.js tokens only, glass region
   untouched by the wobble (GlassPanel parented to root, wobble targets
   contentArea).
4. DELETE: object-tree destruction via host.removeWidget (single path).
5. EXIT: done button + empty-desktop click + host-hide auto-exit.
6. P-9: every asserted <id>.<fn>(...) form is locked to its definition scope.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ROOT / "components"
WIDGETS = COMPONENTS / "widgets"
HOST = WIDGETS / "WidgetHost.qml"
WIDGET_BASE = WIDGETS / "Widget.qml"
GRID = WIDGETS / "WidgetGrid.js"
PREVIEW = COMPONENTS / "WidgetPreview.qml"
MOTION = COMPONENTS / "Motion.js"


def all_widget_sources() -> list[Path]:
    return sorted(WIDGETS.glob("*.qml"))


class WidgetGestureContractTests(unittest.TestCase):
    def test_widget_base_owns_four_state_gesture(self) -> None:
        text = WIDGET_BASE.read_text(encoding="utf-8")
        # A-C2: the four callbacks live on one MouseArea (Dock pattern).
        gesture = text.split("MouseArea {", 1)[1]
        gesture = gesture.split("// 删除按钮", 1)[0]
        for needle in ("onPressed:", "onPositionChanged:", "onReleased:", "onCanceled:"):
            self.assertIn(needle, gesture, msg=needle)
        # Gesture is active only for interactive desktop instances.
        self.assertIn("enabled: root.interactive && !!root.widgetHost", gesture)
        # Threshold + suppressNextClick are part of the pattern.
        self.assertIn("gestureThreshold", gesture)
        self.assertIn("suppressNextClick", gesture)

    def test_no_drag_handler_or_drop_area_in_widgets(self) -> None:
        # A-C2: internal repositioning must never use DragHandler/Drag/DropArea.
        for path in all_widget_sources():
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("DragHandler", text, msg=path.name)
            self.assertNotIn("DropArea", text, msg=path.name)
            self.assertNotIn("drag.target", text, msg=path.name)

    def test_long_press_enters_edit_mode(self) -> None:
        text = WIDGET_BASE.read_text(encoding="utf-8")
        # Long-press timer is one-shot, token duration, enters edit mode.
        self.assertIn("Timer {", text)
        self.assertIn("interval: Motion.widgetLongPressMs", text)
        self.assertIn("repeat: false", text)
        self.assertIn("root.widgetHost.enterEditMode()", text)
        # Movement beyond threshold cancels the long-press (判为拖动而非长按).
        self.assertIn("longPressTimer.stop()", text)

    def test_host_api_and_gesture_call_forms_locked(self) -> None:
        # P-9: the calls in Widget.qml are defined in WidgetHost.qml.
        base = WIDGET_BASE.read_text(encoding="utf-8")
        host = HOST.read_text(encoding="utf-8")
        self.assertIn("root.widgetHost.beginWidgetDrag(root, gesture.pressX, gesture.pressY)", base)
        self.assertIn("function beginWidgetDrag(inst, localX, localY)", host)
        self.assertIn("root.widgetHost.updateWidgetDrag(root, mouse.x, mouse.y)", base)
        self.assertIn("function updateWidgetDrag(inst, localX, localY)", host)
        self.assertIn("root.widgetHost.commitWidgetDrag(root)", base)
        self.assertIn("function commitWidgetDrag(inst)", host)
        self.assertIn("root.widgetHost.cancelWidgetDrag(root)", base)
        self.assertIn("function cancelWidgetDrag(inst)", host)
        # Coordinates are mapped into host space (A-C2, Dock.qml:948).
        self.assertIn("inst.mapToItem(root, localX, localY)", host)


class WidgetEditModeContractTests(unittest.TestCase):
    def test_host_edit_mode_state_and_bindings(self) -> None:
        host = HOST.read_text(encoding="utf-8")
        base = WIDGET_BASE.read_text(encoding="utf-8")
        self.assertIn("property bool editMode: false", host)
        self.assertIn("function enterEditMode()", host)
        self.assertIn("function exitEditMode()", host)
        self.assertIn("property bool editMode: false", base)
        # Edit mode is injected as a live binding, not a one-time value.
        self.assertIn('"widgetId": String(entry.id || "")', host)
        self.assertIn('"widgetHost": root', host)
        self.assertIn("obj.editMode = Qt.binding(function() { return root.editMode; });", host)
        # Exiting mid-drag must roll back (host restores the grid position and
        # clears drag state; the widget gesture resets via the editMode binding).
        exit_block = host.split("function exitEditMode() {", 1)[1]
        exit_block = exit_block.split("// 宿主隐藏（移除最后一个小部件等）", 1)[0]
        self.assertIn("root.clearDrag()", exit_block)
        self.assertIn("inst.x = start.x;", exit_block)
        self.assertIn("inst.y = start.y;", exit_block)
        self.assertIn("root.settleWidgets();", exit_block)
        self.assertIn("onEditModeChanged: {", base)
        self.assertIn("if (!root.editMode && (gesture.dragActive || gesture.dragPressed))", base)
        self.assertIn("root.resetGesture();", base)
        self.assertIn("function resetGesture()", base)

    def test_wobble_gated_and_no_spring_no_hardcoded_duration(self) -> None:
        base = WIDGET_BASE.read_text(encoding="utf-8")
        # A-C3: wobble runs only in edit mode (no resident animation).
        self.assertIn("running: root.editMode && root.interactive", base)
        self.assertIn("loops: Animation.Infinite", base)
        # P-1: no SpringAnimation in widget code.
        for path in all_widget_sources():
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("SpringAnimation", text, msg=path.name)
        # P-3: no hardcoded duration literals; wobble uses Motion tokens.
        match = re.compile(r"duration:\s*[0-9]+").search(base)
        self.assertIsNone(match, "Widget.qml hardcoded duration")
        self.assertIn("duration: Motion.widgetWobbleDurationMs", base)
        # P-1: the wobble must not transform the glass region — glass is
        # parented to root (untouched) and only contentArea rotates.
        self.assertIn("GlassPanel {\n        parent: root", base)
        self.assertIn("property: \"rotation\"", base)
        self.assertIn("target: contentArea", base)
        self.assertIn("transformOrigin: Item.Center", base)

    def test_delete_button_destroys_via_host(self) -> None:
        base = WIDGET_BASE.read_text(encoding="utf-8")
        host = HOST.read_text(encoding="utf-8")
        self.assertIn("visible: root.editMode && root.interactive", base)
        self.assertIn("root.widgetHost.removeWidget(root.widgetId)", base)
        # Single removal path already persists once (A-C5).
        self.assertIn("function removeWidget(id)", host)
        self.assertIn("root.rebuildWidgets();", host)
        self.assertIn("root.persistConfig();", host)

    def test_drag_writes_only_on_commit(self) -> None:
        # A-C5: no persistence while dragging; exactly the release-side
        # commit writes once.
        host = HOST.read_text(encoding="utf-8")
        begin = host.split("function beginWidgetDrag(", 1)[1]
        begin = begin.split("function updateWidgetDrag(", 1)[0]
        self.assertNotIn("persistConfig", begin)
        # Begin settles any mid-flight settle animation and snapshots from the
        # config grid position (never an animation intermediate frame).
        self.assertIn("root.settleWidgets();", begin)
        self.assertIn("function settleWidgets()", host)
        self.assertIn('"x": startX,', begin)
        self.assertIn('"y": startY,', begin)
        # y-clamp consistency: settle/begin/animate must not place instances at
        # negative pixels (short-screen top rows), same as createWidgetInstance.
        settle = host.split("function settleWidgets() {", 1)[1]
        settle = settle.split("function beginWidgetDrag(", 1)[0]
        self.assertIn("Math.max(0, Grid.xPxForCell(entry.col, root.cellSize));", settle)
        self.assertIn("Math.max(0, Grid.yPxForCell(entry.row, Grid.rowsForSize(entry.size),", settle)
        self.assertIn("Math.max(0, Grid.xPxForCell(entry.col, root.cellSize));", begin)
        self.assertIn("Math.max(0, Grid.yPxForCell(entry.row, Grid.rowsForSize(entry.size),", begin)
        self.assertIn("tx = Math.max(0, Number(tx) || 0);", host)
        self.assertIn("ty = Math.max(0, Number(ty) || 0);", host)
        update = host.split("function updateWidgetDrag(", 1)[1]
        update = update.split("function commitWidgetDrag(", 1)[0]
        self.assertNotIn("persistConfig", update)
        commit = host.split("function commitWidgetDrag(", 1)[1]
        commit = commit.split("function cancelWidgetDrag(", 1)[0]
        self.assertEqual(commit.count("root.persistConfig();"), 1)
        # Cancel rolls back without writing.
        cancel = host.split("function cancelWidgetDrag(", 1)[1]
        cancel = cancel.split("function clearDrag(", 1)[0]
        self.assertNotIn("persistConfig", cancel)
        self.assertIn("inst.x = root.dragStart.x;", cancel)
        self.assertIn("inst.y = root.dragStart.y;", cancel)

    def test_edit_mask_and_exit_paths(self) -> None:
        host = HOST.read_text(encoding="utf-8")
        # Edit mode: full-screen input mask (empty-desktop click exits).
        self.assertIn('"widgetsEditMask"', host)
        self.assertIn("editExitCatcher", host)
        self.assertIn("enabled: root.editMode && !root.popupActive", host)
        self.assertIn("onClicked: root.exitEditMode()", host)
        # Done button.
        self.assertIn("text: \"完成\"", host)
        self.assertIn("visible: root.editMode", host)
        # Mask rebuild + auto-exit on host hide.
        self.assertIn("onEditModeChanged: root.updateMask()", host)
        self.assertIn("onVisibleChanged: if (!root.visible) root.exitEditMode()", host)

    def test_rebuild_defensively_clears_drag(self) -> None:
        host = HOST.read_text(encoding="utf-8")
        rebuild = host.split("function rebuildWidgets() {", 1)[1]
        rebuild = rebuild.split("var old = root.widgetInstances;", 1)[0]
        self.assertIn("root.clearDrag();", rebuild)
        # Rebuild also stops settle animations so they cannot point at a
        # destroyed instance.
        self.assertIn("dragXAnim.stop();", rebuild)
        self.assertIn("dragYAnim.stop();", rebuild)

    def test_preview_instances_never_get_edit_interaction(self) -> None:
        # A5 preview path must stay inert: no host, no editMode, no gesture.
        preview = PREVIEW.read_text(encoding="utf-8")
        self.assertNotIn("widgetHost", preview)
        self.assertNotIn("editMode", preview)
        self.assertNotIn("Timer {", preview)
        self.assertNotIn("MouseArea {", preview)

    def test_grid_placement_functions_exist_in_single_source(self) -> None:
        grid = GRID.read_text(encoding="utf-8")
        host = HOST.read_text(encoding="utf-8")
        for fn in ("function snapPosition(", "function canPlace(", "function xPxForCell(", "function yPxForCell("):
            self.assertIn(fn, grid, msg=fn)
        self.assertIn("Grid.snapPosition(", host)
        self.assertIn("Grid.canPlace(", host)
        self.assertIn("Grid.xPxForCell(", host)
        self.assertIn("Grid.yPxForCell(", host)

    def test_motion_tokens_exist(self) -> None:
        motion = MOTION.read_text(encoding="utf-8")
        for token in ("widgetLongPressMs", "widgetSuppressClickMs", "widgetWobbleDurationMs"):
            self.assertIn(f"var {token}", motion, msg=token)

    def test_no_hardcoded_duration_in_host_or_motion_literals_in_widgets(self) -> None:
        host = HOST.read_text(encoding="utf-8")
        match = re.compile(r"duration:\s*[0-9]+").search(host)
        self.assertIsNone(match, "WidgetHost hardcoded duration")


if __name__ == "__main__":
    unittest.main()
