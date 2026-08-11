"""A2 logic tests: WidgetGrid.js grid algorithms.

WidgetGrid.js is pure JS (no QML scene graph), so the algorithms are tested
for real by executing the file in node (same pattern as test_window_model.py
running WindowModel.js fixtures): findEmptyCell / findSlot / cleaning /
serialize round-trip. These guard the "find first empty slot" requirement
and the P-5 capacity behavior.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GRID = ROOT / "components" / "widgets" / "WidgetGrid.js"

NODE_RUNNER = r"""
// NOTE: with `node -e <code>`, argv is [node, arg1, arg2, ...] — the code
// itself does not occupy an argv slot. Path is argv[1], script is argv[2].
const fs = require("fs");
let src = fs.readFileSync(process.argv[1], "utf8");
// Strip the QML .pragma library directive (not valid JS for new Function).
src = src.replace(/^\.pragma[^\n]*\n/, "");
const fn = new Function(src + "; return { findEmptyCell, findSlot, gridStateFromConfig, serializeEntries, sizeForSpan, validSize, snapPosition, canPlace, xPxForCell, yPxForCell, GRID_COLS, GRID_ROWS, LIMIT_ITEMS };");
globalThis.api = fn();
const result = eval("with (api) { " + process.argv[2] + " }");
process.stdout.write(JSON.stringify(result));
"""


class WidgetGridTests(unittest.TestCase):
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
        # stdout is JSON.stringify(result) of a string — unwrap once.
        return json.loads(json.loads(completed.stdout))

    def test_find_empty_cell_first_fit(self) -> None:
        # Empty grid -> (0,0). One small at (0,0) -> next free is (2,0).
        out = self.run_grid(
            "const empty = gridStateFromConfig([]); "
            "const a = findEmptyCell(empty, 2, 2); "
            "const occ = gridStateFromConfig([{id:'a', size:'small', col:0, row:0}]); "
            "const b = findEmptyCell(occ, 2, 2); "
            "JSON.stringify({a, b})"
        )
        self.assertEqual(out["a"], {"col": 0, "row": 0})
        self.assertEqual(out["b"], {"col": 2, "row": 0})

    def test_find_slot_respects_capacity_and_bounds(self) -> None:
        # A 4×6 grid fits at most 6 small (2×2) widgets. When full, no slot.
        full = [
            {"id": f"w{i}", "size": "small", "col": (i % 2) * 2, "row": (i // 2) * 2}
            for i in range(6)
        ]
        out = self.run_grid(
            "const st = gridStateFromConfig(" + json.dumps(full) + "); "
            "const slot = findSlot(st, 2, 2); "
            "JSON.stringify({slot, len: st.grid.length})"
        )
        self.assertIsNone(out["slot"])
        self.assertEqual(out["len"], 6)

    def test_find_slot_capacity_guard(self) -> None:
        # Defensive capacity path: with ≥ LIMIT_ITEMS entries the function
        # returns null even if a physical slot were free (unreachable in
        # practice because physical space fills first, but the guard must
        # exist and be first). Construct the state directly to bypass
        # overlap cleaning.
        out = self.run_grid(
            "const fake = { grid: Array(24).fill({gridX: 0, gridY: 0, cols: 2, rows: 2}) }; "
            "const slot = findSlot(fake, 2, 2); "
            "JSON.stringify({slot})"
        )
        self.assertIsNone(out["slot"])

    def test_grid_state_cleans_invalid_and_overlapping(self) -> None:
        out = self.run_grid(
            "const st = gridStateFromConfig(["
            "{id:'a', size:'small', col:0, row:0},"
            "{id:'b', size:'small', col:0, row:0},"
            "{id:'c', size:'medium', col:0, row:0},"
            "{id:'d', size:'small', col:6, row:0},"
            "{id:'e', size:'large', col:0, row:3},"
            "{id:'f', size:'xlarge', col:0, row:0}"
            "]); "
            "JSON.stringify({n: st.grid.length, removed: st.removed.length, ids: st.grid.map(w=>w.id)})"
        )
        # a valid; b overlaps a -> removed; c overlaps a -> removed;
        # d out of bounds (col 6) -> removed; e out of bounds (row 3+4>4) -> removed;
        # f invalid size -> coerced small, overlaps a -> removed.
        self.assertEqual(out["n"], 1)
        self.assertEqual(out["removed"], 5)
        self.assertEqual(out["ids"], ["a"])

    def test_serialize_round_trip(self) -> None:
        out = self.run_grid(
            "const cfg = [{id:'battery', size:'small', col:2, row:2}]; "
            "const st = gridStateFromConfig(cfg); "
            "JSON.stringify(serializeEntries(st))"
        )
        self.assertEqual(out, [{"id": "battery", "size": "small", "col": 2, "row": 2}])

    def test_size_span_mapping(self) -> None:
        out = self.run_grid(
            "JSON.stringify([sizeForSpan(2,2), sizeForSpan(4,2), sizeForSpan(4,4), sizeForSpan(3,2)])"
        )
        self.assertEqual(out, ["small", "medium", "large", "small"])

    def test_capacity_constants(self) -> None:
        out = self.run_grid(
            "JSON.stringify([api.GRID_COLS, api.GRID_ROWS, api.LIMIT_ITEMS])"
        )
        self.assertEqual(out, [4, 6, 24])

class WidgetGridA6DragTests(unittest.TestCase):
    """A6 drag placement pure functions: snapPosition / canPlace / px helpers.

    The host's drag commit reads only these results (G-6 single source), so
    the grid math is testable without a scene graph, same as the A2 suite.
    """

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

    def test_px_helpers_match_layout_formula(self) -> None:
        # y is screen coords (top-down); row is bottom-origin (A2 semantics).
        out = self.run_grid(
            "JSON.stringify(["
            "xPxForCell(2, 90),"
            "yPxForCell(0, 2, 90, 900),"
            "yPxForCell(2, 2, 90, 900)"
            "])"
        )
        self.assertEqual(out, [180, 720, 540])

    def test_snap_position_nearest_cell_and_clamp(self) -> None:
        # cellSize 90, screen 900: a small (2x2) widget at x=350,y=540 →
        # col=round(3.89)=4→clamp 2; row=round((900-540)/90-2)=round(2)=2.
        out = self.run_grid(
            "JSON.stringify(snapPosition(2, 2, 350, 540, 90, 900))"
        )
        self.assertEqual(out, {"col": 2, "row": 2})
        # Far right / top pointer snaps to the last legal cell
        # (row 0 is the bottom-origin first row; y=0 is the screen top).
        out = self.run_grid(
            "JSON.stringify(snapPosition(2, 2, 900, 0, 90, 900))"
        )
        self.assertEqual(out, {"col": 2, "row": 4})
        # Negative pointer clamps to 0 (bottom-left first legal cell:
        # row = round((900-(-50))/90 - 2) = round(8.56) -> clamped to 4).
        out = self.run_grid(
            "JSON.stringify(snapPosition(2, 2, -50, -50, 90, 900))"
        )
        self.assertEqual(out, {"col": 0, "row": 4})

    def test_snap_position_round_trip_equals_layout(self) -> None:
        # A widget currently at row 1 bottom-origin snaps back to itself.
        out = self.run_grid(
            "const x = xPxForCell(1, 90); "
            "const y = yPxForCell(1, 2, 90, 900); "
            "JSON.stringify(snapPosition(2, 2, x, y, 90, 900))"
        )
        self.assertEqual(out, {"col": 1, "row": 1})

    def test_can_place_bounds_and_overlap(self) -> None:
        grid = [{"id": "a", "gridX": 0, "gridY": 0, "cols": 2, "rows": 2}]
        # Free cell.
        out = self.run_grid(
            "const g = " + json.dumps(grid) + "; "
            "JSON.stringify({free: canPlace(g, 'b', 2, 0, 2, 2), "
            "overlap: canPlace(g, 'b', 0, 0, 2, 2), "
            "same: canPlace(g, 'a', 0, 0, 2, 2), "
            "bounds: canPlace(g, 'b', 3, 0, 2, 2)})"
        )
        self.assertEqual(out, {"free": True, "overlap": False, "same": True, "bounds": False})

    def test_can_place_partial_overlap(self) -> None:
        grid = [{"id": "a", "gridX": 2, "gridY": 2, "cols": 2, "rows": 2}]
        out = self.run_grid(
            "const g = " + json.dumps(grid) + "; "
            "JSON.stringify({free: canPlace(g, 'b', 0, 0, 2, 2), "
            "partial: canPlace(g, 'b', 0, 1, 4, 2)})"
        )
        # (0,1)+4x2 covers row 1-2, col 0-3 → overlaps a at (2,2) → false.
        self.assertEqual(out, {"free": True, "partial": False})


if __name__ == "__main__":
    unittest.main()
