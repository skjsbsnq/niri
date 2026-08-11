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
const fn = new Function(src + "; return { findEmptyCell, findSlot, gridStateFromConfig, serializeEntries, sizeForSpan, validSize, GRID_COLS, GRID_ROWS, LIMIT_ITEMS };");
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


if __name__ == "__main__":
    unittest.main()
