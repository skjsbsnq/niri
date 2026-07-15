#!/usr/bin/env python3
"""T09: swipe settle holds target geometry without collapse-expand jump."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ISLAND = ROOT / "services" / "DynamicIsland.qml"
OWNERSHIP = ROOT / "components" / "DynamicIslandOwnership.js"
EXPECTED = ROOT / "tests" / "test_dynamic_island_v2_expected_failures.py"


NODE_HELPER = r"""
const fs = require("fs");
const vm = require("vm");
const modulePath = process.argv[1];
const request = JSON.parse(process.argv[2]);
const source = fs.readFileSync(modulePath, "utf8").replace(/^\s*\.pragma library\s*\n/, "");
const context = {
  Array, Boolean, Date, JSON, Math, Number, Object, String, console, isFinite,
};
vm.createContext(context);
vm.runInContext(source, context, { filename: modulePath });
const op = request.op;
let result;
if (op === "settle") {
  result = context.resolveSwipeSettle(
    request.progress, request.start, request.hasMedia,
    request.enter, request.ret);
} else if (op === "width") {
  result = {
    width: context.swipePreviewWidthFor(
      request.progress, request.resting, request.left, request.right),
  };
} else {
  throw new Error("unknown op");
}
process.stdout.write(JSON.stringify(result));
"""


def run_node(request: dict) -> dict:
    if shutil.which("node") is None:
        raise unittest.SkipTest("node required")
    completed = subprocess.run(
        ["node", "-e", NODE_HELPER, str(OWNERSHIP), json.dumps(request)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return json.loads(completed.stdout)


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


def _compact(text: str) -> str:
    return re.sub(r"\s+", "", text)


class SwipeSettleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.island = ISLAND.read_text(encoding="utf-8")
        cls.expected = EXPECTED.read_text(encoding="utf-8")

    def test_enter_media_keeps_progress_at_one(self) -> None:
        d = run_node({
            "op": "settle",
            "progress": 0.85,
            "start": 0,
            "hasMedia": True,
            "enter": 0.56,
            "ret": 0.44,
        })
        self.assertEqual(d["swipeProgress"], 1)
        self.assertEqual(d["forcedState"], "expanded_media")
        self.assertTrue(d["entered"])
        # T11 mid-band: compact media 212, expanded media 418, summary 360.
        width = run_node({
            "op": "width",
            "progress": d["swipeProgress"],
            "resting": 212,
            "left": 360,
            "right": 418,
        })["width"]
        self.assertAlmostEqual(width, 418.0, places=3)
        # V1 bug: progress 0 during settle → width == resting.
        v1 = run_node({
            "op": "width",
            "progress": 0,
            "resting": 212,
            "left": 360,
            "right": 418,
        })["width"]
        self.assertAlmostEqual(v1, 212.0, places=3)
        self.assertGreater(width, v1)

    def test_left_swipe_no_longer_opens_summary(self) -> None:
        d = run_node({
            "op": "settle",
            "progress": -0.85,
            "start": 0,
            "hasMedia": True,
            "enter": 0.56,
            "ret": 0.44,
        })
        self.assertEqual(d["swipeProgress"], 0)
        self.assertEqual(d["forcedState"], "")
        self.assertFalse(d["entered"])
        self.assertTrue(d["collapsed"])

    def test_right_swipe_without_media_collapses(self) -> None:
        d = run_node({
            "op": "settle",
            "progress": 0.85,
            "start": 0,
            "hasMedia": False,
            "enter": 0.56,
            "ret": 0.44,
        })
        self.assertEqual(d["swipeProgress"], 0)
        self.assertEqual(d["forcedState"], "")
        self.assertFalse(d["entered"])


    def test_production_resolve_does_not_zero_progress(self) -> None:
        body = _function_body(self.island, "resolveSwipe")
        compact = _compact(body)
        # Must not assign swipeProgress = 0 in settle branches (V1 bug).
        self.assertNotIn("swipeProgress=0", compact)
        self.assertIn("resolveSwipeSettle", body)
        self.assertIn("swipeProgress", body)
        # Production preview width uses the pure helper (no formula drift).
        self.assertIn("swipePreviewWidthFor", self.island)

    def test_begin_records_start_presentation(self) -> None:
        body = _function_body(self.island, "beginSwipe")
        self.assertIn("swipeStartForcedState", body)
        cancel = _function_body(self.island, "cancelSwipe")
        self.assertIn("swipeStartForcedState", cancel)
        self.assertIn("swipeStartProgress", cancel)

    def test_t02_swipe_xfail_removed(self) -> None:
        self.assertNotRegex(
            self.expected,
            r"@pytest\.mark\.xfail\([\s\S]*?target T09",
        )


if __name__ == "__main__":
    raise SystemExit(unittest.main())
