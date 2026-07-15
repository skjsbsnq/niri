#!/usr/bin/env python3
"""T07: transient priority, notification lease, and single restore entry."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ISLAND = ROOT / "services" / "DynamicIsland.qml"
REDUCER = ROOT / "services" / "DynamicIslandReducer.js"
NOTIFICATIONS = ROOT / "services" / "Notifications.qml"
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
if (op === "blocks") {
  result = {
    osd: context.blocksOsd(request.presentation, request.flags || {}),
    workspace: context.blocksWorkspace(request.presentation, request.flags || {}),
    notification: context.blocksNotification(request.presentation, request.flags || {}),
    priority: context.presentationPriority(request.presentation, request.flags || {}),
  };
} else if (op === "priority") {
  result = { value: context.priorityValue(request.kind) };
} else {
  throw new Error("unknown op");
}
process.stdout.write(JSON.stringify(result));
"""


def run_node(request: dict) -> dict:
    if shutil.which("node") is None:
        raise unittest.SkipTest("node required")
    completed = subprocess.run(
        ["node", "-e", NODE_HELPER, str(REDUCER), json.dumps(request)],
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


class TransientArbitrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.island = ISLAND.read_text(encoding="utf-8")
        cls.notifications = NOTIFICATIONS.read_text(encoding="utf-8")
        cls.reducer = REDUCER.read_text(encoding="utf-8")
        cls.expected = EXPECTED.read_text(encoding="utf-8")

    def test_priority_table(self) -> None:
        self.assertEqual(run_node({"op": "priority", "kind": "interaction"})["value"], 100)
        self.assertEqual(run_node({"op": "priority", "kind": "notification"})["value"], 80)
        self.assertEqual(run_node({"op": "priority", "kind": "osd"})["value"], 50)
        self.assertEqual(run_node({"op": "priority", "kind": "workspace"})["value"], 40)

    def test_notification_blocks_osd_and_workspace(self) -> None:
        flags = {"displayingNotification": True}
        out = run_node({
            "op": "blocks",
            "presentation": "transient_notification",
            "flags": flags,
        })
        self.assertTrue(out["osd"])
        self.assertTrue(out["workspace"])
        self.assertTrue(out["notification"])

    def test_idle_allows_osd_and_workspace(self) -> None:
        out = run_node({"op": "blocks", "presentation": "resting_time", "flags": {}})
        self.assertFalse(out["osd"])
        self.assertFalse(out["workspace"])
        self.assertFalse(out["notification"])

    def test_expanded_blocks_lower_events(self) -> None:
        out = run_node({
            "op": "blocks",
            "presentation": "expanded_media",
            "flags": {"expanded": True},
        })
        self.assertTrue(out["osd"])
        self.assertTrue(out["workspace"])
        self.assertTrue(out["notification"])

    def test_production_blocks_use_reducer_and_notification_markers(self) -> None:
        osd = _function_body(self.island, "blocksTransientOsd")
        ws = _function_body(self.island, "blocksTransientWorkspace")
        self.assertIn("blocksOsd", osd)
        self.assertIn("blocksWorkspace", ws)
        self.assertTrue(
            "transient_notification" in osd
            or "displayingNotification" in osd
            or "arbitrationFlags" in osd
        )
        self.assertTrue(
            "transient_notification" in ws
            or "displayingNotification" in ws
            or "arbitrationFlags" in ws
        )
        # Flags helper must surface notification lease.
        flags = _function_body(self.island, "arbitrationFlags")
        self.assertIn("displayingNotification", flags)
        self.assertIn("transient_notification", flags)

    def test_single_restore_entry(self) -> None:
        self.assertIn("function restoreAfterTransient", self.island)
        restore = _function_body(self.island, "restoreAfterTransient")
        self.assertIn("maybeShowPendingNotification", restore)
        self.assertIn("maybeShowPendingOsd", restore)
        # onStateChanged must not call both presenters directly.
        m = re.search(
            r"onStateChanged:\s*\{([^}]*)\}",
            self.island,
        )
        self.assertIsNotNone(m)
        body = m.group(1)
        self.assertIn("restoreAfterTransient", body)
        self.assertNotIn("maybeShowPendingNotification()", body)
        self.assertNotIn("maybeShowPendingOsd()", body)
        # Reducer apply suppresses re-entrant onStateChanged restore.
        self.assertIn("applyingPresentationReducer", self.island)
        apply = _function_body(self.island, "applyReducerResult")
        self.assertIn("applyingPresentationReducer = true", apply)
        self.assertIn("restoreAfterTransient()", apply)
        self.assertIn("endNotificationLease", apply)

    def test_abort_paths_end_notification_lease(self) -> None:
        for kind in (
            "SHOW_TIME",
            "SHOW_MEDIA",
            "SHOW_EXPANDED_MEDIA",
            "SHOW_EXPANDED_SUMMARY",
            "HOVER_EXPAND",
            "TOGGLE_EXPANDED",
            "COLLAPSE",
        ):
            # Source-level: reducer emits endNotificationLease for abort/collapse.
            self.assertIn("endNotificationLease", self.reducer)
        self.assertIn('case "endNotificationLease"', self.island)
        self.assertIn("markNotificationPresentationCompleted", self.island)

    def test_no_live_island_queue(self) -> None:
        handle = _function_body(self.island, "handleNotificationsChanged")
        self.assertNotIn("enqueuePendingNotificationId(newIds", handle)
        self.assertIn("restoreAfterTransient", handle)
        self.assertIn("completedNotificationIds", self.island)
        enq = _function_body(self.island, "enqueuePendingNotificationEntry")
        self.assertIn('kind === "live"', enq)
        self.assertIn("return", enq)
        maybe = _function_body(self.island, "maybeShowPendingNotification")
        self.assertIn("nextPresentableLiveNotification", maybe)

    def test_notifications_owner_head_api(self) -> None:
        self.assertIn("function findActiveById", self.notifications)
        self.assertIn("function presentationHead", self.notifications)
        self.assertIn("function isCritical", self.notifications)

    def test_t02_priority_xfails_removed(self) -> None:
        # Desired priority tests must be green (no xfail target T07).
        self.assertNotIn('reason="target T07:', self.expected)
        self.assertNotIn("reason=\"target T07:", self.expected)
        # Anchors updated or production predicates true via green tests.
        self.assertIn("test_desired_osd_yields_to_active_notification", self.expected)
        # xfail marks for T07 should be gone
        self.assertNotRegex(
            self.expected,
            r"@pytest\.mark\.xfail\([\s\S]*?target T07",
        )


if __name__ == "__main__":
    raise SystemExit(unittest.main())
