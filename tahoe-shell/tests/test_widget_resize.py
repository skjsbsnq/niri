"""A7 contract tests: edit-mode edge resize (three-tier switching).

Source-level guards (repo style) for roadmap A7:

1. HANDLES: Widget.qml owns 8 edge/corner hit zones (8px), gated on
   editMode && interactive (preview never enables them), with the four-state
   callback pattern (A-C2) and no DragHandler/DropArea.
2. HOST API: begin/update/commit/cancel + grid placement + one-shot
   persistence (A-C5); begin/update/cancel never write, commit writes once.
3. TIERS (G-6): tier order + span mapping live only in WidgetGrid.js;
   resizeTargetTier / resizePlacement are pure and node-tested for real.
4. P-1 / P-3: resize geometry uses Motion.elementResize NumberAnimation
   (no spring, no hardcoded duration literal).
5. CONFLICT: rejected tier switch shows visible feedback (banner + one-shot
   timer), never overlaps (canPlace gate).
6. CATALOG (A7 判据): every widget declares all three sizes so the library
   marked sizes equal the switchable tiers.
7. P-9: every asserted <id>.<fn>(...) call form is locked to its definition
   scope.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ROOT / "components"
WIDGETS = COMPONENTS / "widgets"
HOST = WIDGETS / "WidgetHost.qml"
WIDGET_BASE = WIDGETS / "Widget.qml"
GRID = WIDGETS / "WidgetGrid.js"
MOTION = COMPONENTS / "Motion.js"
PREVIEW = COMPONENTS / "WidgetPreview.qml"

NODE_RUNNER = r"""
const fs = require("fs");
let src = fs.readFileSync(process.argv[1], "utf8");
src = src.replace(/^\.pragma[^\n]*\n/, "");
const fn = new Function(src + "; return { findEmptyCell, findSlot, gridStateFromConfig, serializeEntries, sizeForSpan, validSize, snapPosition, canPlace, xPxForCell, yPxForCell, colsForSize, rowsForSize, tierIndex, sizeForTier, resizeTargetTier, resizePlacement, GRID_COLS, GRID_ROWS, LIMIT_ITEMS, GAP_PX };");
globalThis.api = fn();
const result = eval("with (api) { " + process.argv[2] + " }");
process.stdout.write(JSON.stringify(result));
"""


class WidgetResizeHandleTests(unittest.TestCase):
    def test_base_owns_eight_edge_handles_gated_on_edit_mode(self) -> None:
        text = WIDGET_BASE.read_text(encoding="utf-8")
        # A7 scope: 8px hit zones around all four edges + corners.
        self.assertEqual(text.count("component ResizeHandle"), 1)
        self.assertEqual(text.count("ResizeHandle {"), 8)
        self.assertIn("component ResizeHandle: MouseArea {", text)
        # Only active in edit mode, and never in preview (interactive gate).
        self.assertIn("enabled: root.editMode && root.interactive", text)
        # Handles sit above the move-gesture layer (z:10) but below the
        # delete button (z:20), so the top-right corner stays deletable.
        self.assertIn("z: 15", text)
        # 8px hit zone literal is the single source for all handles.
        self.assertIn("width: 8", text)
        self.assertIn("height: 8", text)

    def test_handle_four_state_callbacks_locked_to_host_api(self) -> None:
        # P-9: the calls in Widget.qml are defined in WidgetHost.qml.
        base = WIDGET_BASE.read_text(encoding="utf-8")
        host = HOST.read_text(encoding="utf-8")
        self.assertIn("root.widgetHost.beginWidgetResize(root, handle.handleId, handle.anchor, lp.x, lp.y)", base)
        self.assertIn("function beginWidgetResize(inst, handleId, anchor, localX, localY)", host)
        self.assertIn("root.widgetHost.updateWidgetResize(root, handle.handleId, lp.x, lp.y)", base)
        self.assertIn("function updateWidgetResize(inst, handleId, localX, localY)", host)
        self.assertIn("root.widgetHost.commitWidgetResize(root)", base)
        self.assertIn("function commitWidgetResize(inst)", host)
        self.assertIn("root.widgetHost.cancelWidgetResize(root)", base)
        self.assertIn("function cancelWidgetResize(inst)", host)
        # The 8px handles sit at the widget edges, so their local origin is
        # NOT the widget origin: mouse coords must first be mapped into the
        # widget's local space (mapFromItem), then the host maps widget-local
        # -> host space (A-C2, Dock.qml:948). Passing raw handle-local coords
        # would reverse direction after the first tier switch (review C1).
        self.assertEqual(base.count("root.mapFromItem(handle, mouse.x, mouse.y)"), 2)
        self.assertIn("inst.mapToItem(widgetLayer, localX, localY)", host)
        # Stale reject banner must not survive leaving edit mode.
        self.assertIn("root.resizeRejectedVisible = false;", host)
        self.assertIn("resizeRejectHide.stop();", host)

    def test_no_drag_machinery_for_resize(self) -> None:
        for path in sorted(WIDGETS.glob("*.qml")):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("DragHandler", text, msg=path.name)
            self.assertNotIn("DropArea", text, msg=path.name)
            self.assertNotIn("drag.target", text, msg=path.name)

    def test_preview_never_enables_resize(self) -> None:
        # The preview path must stay inert: no host, no editMode, and the
        # base handles are gated on root.interactive (false in previewMode).
        preview = PREVIEW.read_text(encoding="utf-8")
        self.assertNotIn("beginWidgetResize", preview)
        self.assertNotIn("editMode", preview)
        base = WIDGET_BASE.read_text(encoding="utf-8")
        self.assertIn("enabled: root.editMode && root.interactive", base)


class WidgetResizeHostTests(unittest.TestCase):
    def test_resize_state_and_api(self) -> None:
        host = HOST.read_text(encoding="utf-8")
        self.assertIn("property bool resizeActive: false", host)
        self.assertIn("property string resizeWidgetId: \"\"", host)
        self.assertIn("property var resizeStart: null", host)
        self.assertIn("function clearResize()", host)
        self.assertIn("root.resizeActive = false;", host)
        # Tier + placement math comes from WidgetGrid.js (G-6 single source).
        self.assertIn("Grid.tierIndex(entry.size)", host)
        self.assertIn("Grid.resizeTargetTier(start.tier, delta, Motion.widgetResizeThresholdPx)", host)
        self.assertIn("Grid.resizePlacement(", host)
        self.assertIn("Grid.canPlace(root.gridState.grid, start.id, placement.col, placement.row,", host)

    def test_resize_writes_only_on_commit(self) -> None:
        host = HOST.read_text(encoding="utf-8")
        begin = host.split("function beginWidgetResize(", 1)[1]
        begin = begin.split("function updateWidgetResize(", 1)[0]
        self.assertNotIn("persistConfig", begin)
        # A rejected switch must never persist: the commit gate is the
        # explicit "switched" flag, not lastTier (lastTier is also set on
        # rejection to suppress repeated feedback).
        self.assertIn('"switched": false', begin)
        self.assertIn('"rejectedTier": -1', begin)
        self.assertIn('"currentTier": Grid.tierIndex(entry.size)', begin)
        update = host.split("function updateWidgetResize(", 1)[1]
        update = update.split("function commitWidgetResize(", 1)[0]
        self.assertNotIn("persistConfig", update)
        self.assertIn("start.switched = true;", update)
        # A rejected switch never marks switched and never writes: the commit
        # gate is switched AND a net tier change (放大又缩回起点不写盘）。
        self.assertIn("start.rejectedTier = targetTier;", update)
        self.assertIn("start.rejectedTier = -1;", update)
        self.assertIn("start.currentTier = targetTier;", update)
        commit = host.split("function commitWidgetResize(", 1)[1]
        commit = commit.split("function cancelWidgetResize(", 1)[0]
        self.assertEqual(commit.count("root.persistConfig();"), 1)
        self.assertIn("if (start.switched && start.currentTier !== start.tier) {", commit)
        # Cancel rolls back without writing.
        cancel = host.split("function cancelWidgetResize(", 1)[1]
        cancel = cancel.split("function clearResize(", 1)[0]
        self.assertNotIn("persistConfig", cancel)
        self.assertIn("inst.x = start.x;", cancel)
        self.assertIn("inst.y = start.y;", cancel)
        self.assertIn("inst.width = start.width;", cancel)
        self.assertIn("inst.height = start.height;", cancel)
        self.assertIn("inst.widgetSize = start.size;", cancel)

    def test_resize_exit_and_rebuild_rollback(self) -> None:
        host = HOST.read_text(encoding="utf-8")
        # Exiting edit mode mid-resize rolls back via the host (no write).
        exit_block = host.split("function exitEditMode() {", 1)[1]
        exit_block = exit_block.split("// 宿主隐藏（移除最后一个小部件等）", 1)[0]
        self.assertIn("root.resizeActive", exit_block)
        self.assertIn("root.cancelWidgetResize(rinst)", exit_block)
        self.assertIn("root.clearResize();", exit_block)
        # Rebuild defensively clears resize state and stops resize animations.
        rebuild = host.split("function rebuildWidgets() {", 1)[1]
        rebuild = rebuild.split("var old = root.widgetInstances;", 1)[0]
        self.assertIn("root.clearResize();", rebuild)
        for anim in ("resizeXAnim.stop();", "resizeYAnim.stop();", "resizeWAnim.stop();", "resizeHAnim.stop();"):
            self.assertIn(anim, rebuild, msg=anim)

    def test_config_entry_update_is_single_path(self) -> None:
        # G-6: drag and resize share one config-entry writer; the old
        # position-only writer must not survive alongside it.
        host = HOST.read_text(encoding="utf-8")
        self.assertNotIn("updateConfigPosition", host)
        self.assertIn("function updateConfigEntry(id, col, row, size)", host)
        self.assertIn("root.updateConfigEntry(start.id, target.col, target.row);", host)
        self.assertIn("root.updateConfigEntry(start.id, start.col, start.row, start.size);", host)


class WidgetResizeGridTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("node") is None:
            raise unittest.SkipTest("node is required to execute WidgetGrid.js")

    def run_grid(self, script: str):
        completed = subprocess.run(
            ["node", "-e", NODE_RUNNER, str(GRID), script],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return json.loads(json.loads(completed.stdout))

    def test_tier_index_and_size_round_trip(self) -> None:
        out = self.run_grid(
            "JSON.stringify([tierIndex('small'), tierIndex('medium'), tierIndex('large'), "
            "tierIndex('bogus'), sizeForTier(0), sizeForTier(1), sizeForTier(2), "
            "sizeForTier(-1), sizeForTier(9)])"
        )
        self.assertEqual(out, [0, 1, 2, 0, "small", "medium", "large", "small", "large"])

    def test_resize_target_tier_threshold_steps(self) -> None:
        out = self.run_grid(
            "JSON.stringify(["
            "resizeTargetTier(0, 10, 24),"
            "resizeTargetTier(0, 25, 24),"
            "resizeTargetTier(0, 50, 24),"
            "resizeTargetTier(0, 49, 24),"
            "resizeTargetTier(2, -25, 24),"
            "resizeTargetTier(0, -25, 24),"
            "resizeTargetTier(1, 0, 24)"
            "])"
        )
        self.assertEqual(out, [0, 1, 2, 2, 1, 0, 1])

    def test_resize_placement_anchors_opposite_edge(self) -> None:
        # Anchors are SCREEN-space corners (row 0 = screen bottom; row grows
        # upward). small (2x2) at grid (1,1) -> medium:
        #  - top-left: screen top-left fixed -> col/row kept (1,1);
        #  - top-right: screen top-right fixed -> col = 1+2-4 = -1 (OOB);
        # large (4x4) at grid (0,0) (screen rows 0..3) -> medium:
        #  - bottom-right: screen bottom-right fixed -> col = 0+4-4 = 0,
        #    row = 0 (bottom edge stays, top comes down) -> (0,0);
        #  - bottom-left: screen bottom-left fixed -> (0,0).
        out = self.run_grid(
            "JSON.stringify({"
            "tl: resizePlacement({col:1,row:1,cols:2,rows:2}, 'medium', 'top-left'), "
            "tr: resizePlacement({col:1,row:1,cols:2,rows:2}, 'medium', 'top-right'), "
            "br: resizePlacement({col:0,row:0,cols:4,rows:4}, 'medium', 'bottom-right'), "
            "bl: resizePlacement({col:0,row:0,cols:4,rows:4}, 'medium', 'bottom-left'), "
            "topFixed: resizePlacement({col:2,row:5,cols:2,rows:2}, 'large', 'top-left'), "
            "bottomFixed: resizePlacement({col:2,row:5,cols:2,rows:2}, 'large', 'bottom-left')"
            "})"
        )
        self.assertEqual(out, {
            "tl": {"col": 1, "row": 1},
            "tr": {"col": -1, "row": 1},
            "br": {"col": 0, "row": 0},
            "bl": {"col": 0, "row": 0},
            # small at row 5 (rows 5..6, top boundary 7): top edge fixed
            # -> large row = 7-4 = 3 (grows down); bottom fixed at 5 ->
            # row 5 (grows up).
            "topFixed": {"col": 2, "row": 3},
            "bottomFixed": {"col": 2, "row": 5},
        })

    def test_resize_placement_validated_by_can_place(self) -> None:
        # A small at (0,0) growing to medium (4x2) overlaps a neighbor at
        # (2,0) -> canPlace rejects (conflict feedback path); a free right
        # side is accepted and the span matches colsForSize/rowsForSize.
        out = self.run_grid(
            "const g = gridStateFromConfig(["
            "{id:'a', size:'small', col:0, row:0},"
            "{id:'b', size:'small', col:2, row:0}"
            "]).grid; "
            "const blocked = resizePlacement({col:0,row:0,cols:2,rows:2}, 'medium', 'top-left'); "
            "const free = gridStateFromConfig([{id:'a', size:'small', col:0, row:2}]).grid; "
            "const p = resizePlacement({col:0,row:2,cols:2,rows:2}, 'medium', 'top-left'); "
            "JSON.stringify({"
            "blocked: canPlace(g, 'a', blocked.col, blocked.row, colsForSize('medium'), rowsForSize('medium'), 4, 6), "
            "free: canPlace(free, 'a', p.col, p.row, colsForSize('medium'), rowsForSize('medium'), 4, 6), "
            "p, mediumCols: colsForSize('medium'), mediumRows: rowsForSize('medium')"
            "})"
        )
        self.assertFalse(out["blocked"])
        self.assertTrue(out["free"])
        self.assertEqual(out["p"], {"col": 0, "row": 2})
        self.assertEqual(out["mediumCols"], 4)
        self.assertEqual(out["mediumRows"], 2)


class WidgetResizeConstraintTests(unittest.TestCase):
    def test_resize_animation_no_spring_no_hardcoded_duration(self) -> None:
        # A7 判据：换档动画无弹簧（grep 断言 + 结构测试）。
        host = HOST.read_text(encoding="utf-8")
        base = WIDGET_BASE.read_text(encoding="utf-8")
        for text, name in ((host, "WidgetHost.qml"), (base, "Widget.qml")):
            self.assertNotIn("SpringAnimation", text, msg=name)
            match = re.compile(r"duration:\s*[0-9]+").search(text)
            self.assertIsNone(match, msg=f"{name} hardcoded duration")
        # P-3: resize geometry animation consumes the Motion elementResize
        # token (never a literal) — four NumberAnimations, one per axis.
        self.assertEqual(host.count("duration: Motion.elementResize(null)"), 4)
        self.assertIn("function animateWidgetResizeTo(inst, tx, ty, tw, th)", host)

    def test_resize_threshold_token_in_motion(self) -> None:
        motion = MOTION.read_text(encoding="utf-8")
        self.assertIn("var widgetResizeThresholdPx = 24", motion)

    def test_conflict_feedback_is_visible_and_one_shot(self) -> None:
        host = HOST.read_text(encoding="utf-8")
        self.assertIn("property bool resizeRejectedVisible: false", host)
        self.assertIn("function showResizeRejected()", host)
        self.assertIn("无法调整大小：空间不足", host)
        # One-shot hide timer only (no resident polling, A-C3). Slice from
        # the timer's own id (not from the first Timer in the file, which
        # would let an unrelated repeat:false pass a vacuous guard).
        timer = host.split("id: resizeRejectHide", 1)[1]
        timer = timer.split("onTriggered: root.resizeRejectedVisible = false", 1)[0]
        self.assertIn("interval: 1200", timer)
        self.assertIn("repeat: false", timer)
        self.assertNotIn("repeat: true", timer)

    def test_catalog_all_three_tiers_match_switchable_tiers(self) -> None:
        # A7 判据：A4 库 tab 标注的可选尺寸与实际可切换档位一致 ——
        # 每个条目都声明三档，defaultSize 在三档内。
        host = HOST.read_text(encoding="utf-8")
        catalog = re.search(
            r"readonly property var widgetCatalog: \(\{(?P<body>[\s\S]*?)\n\s*\}\)",
            host,
        )
        self.assertIsNotNone(catalog)
        assert catalog
        body = catalog.group("body")
        self.assertEqual(body.count('"sizes": ["small", "medium", "large"]'), 4)
        for entry in re.finditer(
            r'"([a-z-]+)":\s*\{\s*"source":\s*"[^"]+",\s*"name":\s*"[^"]+",\s*"sizes":\s*\[(?P<sizes>[^\]]+)\],\s*"defaultSize":\s*"(?P<default>[a-z]+)"\s*\}',
            body,
        ):
            sizes = re.findall(r'"([a-z]+)"', entry.group("sizes"))
            self.assertEqual(sizes, ["small", "medium", "large"], entry.group(1))
            self.assertIn(entry.group("default"), sizes, entry.group(1))


if __name__ == "__main__":
    unittest.main()
