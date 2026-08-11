"""A3 logic tests: CalendarLogic.js month-grid algorithms.

CalendarLogic.js is pure JS (no QML scene graph), so the algorithms are tested
for real by executing the file in node (same pattern as test_widget_grid.py):
42-cell Monday-start grid, today highlight, weekend flags, month title, and
the red "today" header label.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CALENDAR = ROOT / "components" / "widgets" / "CalendarLogic.js"

NODE_RUNNER = r"""
// NOTE: with `node -e <code>`, argv is [node, arg1, arg2, ...] — the code
// itself does not occupy an argv slot. Path is argv[1], script is argv[2].
const fs = require("fs");
let src = fs.readFileSync(process.argv[1], "utf8");
// Strip the QML .pragma library directive (not valid JS for new Function).
src = src.replace(/^\.pragma[^\n]*\n/, "");
const fn = new Function(src + "; return { monthGrid, monthTitle, todayDayLabel, weekdayLabels, GRID_CELLS };");
globalThis.api = fn();
const result = eval("with (api) { " + process.argv[2] + " }");
process.stdout.write(JSON.stringify(result));
"""


class CalendarLogicTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("node") is None:
            raise unittest.SkipTest("node is required to execute CalendarLogic.js")

    def run_calendar(self, script: str):
        completed = subprocess.run(
            ["node", "-e", NODE_RUNNER, str(CALENDAR), script],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return json.loads(json.loads(completed.stdout))

    def test_grid_is_42_cells_monday_start(self) -> None:
        # 2026-08-01 is a Saturday; the Monday of that week is 2026-07-27,
        # which must be the first cell and belong to the previous month.
        out = self.run_calendar(
            "const g = monthGrid(2026, 7, new Date(2026, 7, 11)); "
            "JSON.stringify({n: g.length, first: g[0], firstDay: g[0].day, firstInMonth: g[0].inMonth})"
        )
        self.assertEqual(out["n"], 42)
        self.assertEqual(out["firstDay"], 27)
        self.assertFalse(out["firstInMonth"])

    def test_today_highlighted_once_when_in_month(self) -> None:
        out = self.run_calendar(
            "const g = monthGrid(2026, 7, new Date(2026, 7, 11)); "
            "const hits = g.filter(c => c.isToday); "
            "JSON.stringify({count: hits.length, day: hits.length ? hits[0].day : -1})"
        )
        self.assertEqual(out["count"], 1)
        self.assertEqual(out["day"], 11)

    def test_no_today_when_outside_month(self) -> None:
        # 2026-08-11 does not fall inside September 2026's grid cells.
        out = self.run_calendar(
            "const g = monthGrid(2026, 8, new Date(2026, 7, 11)); "
            "JSON.stringify({count: g.filter(c => c.isToday).length})"
        )
        self.assertEqual(out["count"], 0)

    def test_weekend_flags(self) -> None:
        # 2026-08-08 is a Saturday, 2026-08-09 a Sunday, 2026-08-10 a Monday.
        out = self.run_calendar(
            "const g = monthGrid(2026, 7, new Date(2026, 7, 11)); "
            "const byDay = {}; g.forEach(c => { byDay[c.day] = c }); "
            "JSON.stringify({sat: byDay[8].isWeekend, sun: byDay[9].isWeekend, mon: byDay[10].isWeekend})"
        )
        self.assertTrue(out["sat"])
        self.assertTrue(out["sun"])
        self.assertFalse(out["mon"])

    def test_leap_year_february(self) -> None:
        # 2024-02 has 29 days; the grid must cover it and 2024-02-29 inMonth.
        out = self.run_calendar(
            "const g = monthGrid(2024, 1, new Date(2024, 1, 29)); "
            "const days = g.filter(c => c.inMonth).map(c => c.day); "
            "JSON.stringify({count: days.length, has29: days.indexOf(29) >= 0})"
        )
        self.assertEqual(out["count"], 29)
        self.assertTrue(out["has29"])

    def test_month_title(self) -> None:
        out = self.run_calendar("JSON.stringify(monthTitle(2026, 7))")
        self.assertEqual(out, "2026年8月")

    def test_today_day_label(self) -> None:
        out = self.run_calendar(
            "JSON.stringify([todayDayLabel(2026, 7, new Date(2026, 7, 11)), "
            "todayDayLabel(2026, 8, new Date(2026, 7, 11))])"
        )
        self.assertEqual(out, ["11", ""])

    def test_weekday_labels_monday_first(self) -> None:
        out = self.run_calendar("JSON.stringify(weekdayLabels())")
        self.assertEqual(out, ["一", "二", "三", "四", "五", "六", "日"])

    def test_grid_cell_count_constant(self) -> None:
        out = self.run_calendar("JSON.stringify(GRID_CELLS)")
        self.assertEqual(out, 42)


if __name__ == "__main__":
    unittest.main()
