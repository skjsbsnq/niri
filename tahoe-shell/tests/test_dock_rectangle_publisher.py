#!/usr/bin/env python3
"""Unit tests for DockRectanglePublisher ownership (R04 / F05–F06)."""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PUBLISHER = ROOT / "services" / "windows" / "DockRectanglePublisher.js"
WINDOWS_QML = ROOT / "services" / "Windows.qml"
WINDOW_BUTTON = ROOT / "components" / "WindowButton.qml"
DOCK_MINIMIZED = ROOT / "components" / "DockMinimizedWindow.qml"

NODE_RUNNER = r"""
const fs = require("fs");
const vm = require("vm");

const modulePath = process.argv[1];
const source = fs.readFileSync(modulePath, "utf8").replace(/^\s*\.pragma library\s*\n/, "");
const context = {
  Array, Boolean, Date, JSON, Math, Number, Object, String, console, isFinite,
};
vm.createContext(context);
vm.runInContext(source, context, { filename: modulePath });

function screen(name) { return { name: name }; }

const dockA = screen("eDP-1");
const dockB = screen("HDMI-A-1");
const handleA = { screens: [dockA], key: "handle-a" };
const handleB = { screens: [dockB], key: "handle-b" };
const handleNone = { screens: [], key: "handle-none" };
const handleMulti = { screens: [dockA, dockB], key: "handle-multi" };
// Same app/title "wrong merge": IPC thinks HDMI, but handle is on eDP.
const wrongIpcPaired = { screens: [dockA], key: "paired-wrong-ipc" };

const cases = [];

function record(name, value) { cases.push({ name, value }); }

// Current-screen owner accepts.
record("owner_accept", context.evaluateCandidate(null, {
  toplevel: handleA,
  sourceWindow: { id: "dock-a" },
  dockScreen: dockA,
  rect: { x: 10, y: 20, width: 48, height: 48 },
  force: false,
}));

// Non-owner dock rejects (F05 dual Dock).
record("non_owner_reject", context.evaluateCandidate(null, {
  toplevel: handleA,
  sourceWindow: { id: "dock-b" },
  dockScreen: dockB,
  rect: { x: 100, y: 20, width: 48, height: 48 },
  force: false,
}));

// Multi-screen fail closed.
record("multi_reject", context.evaluateCandidate(null, {
  toplevel: handleMulti,
  sourceWindow: { id: "dock-a" },
  dockScreen: dockA,
  rect: { x: 1, y: 2, width: 3, height: 4 },
}));

// No screens fail closed.
record("none_reject", context.evaluateCandidate(null, {
  toplevel: handleNone,
  sourceWindow: { id: "dock-a" },
  dockScreen: dockA,
  rect: { x: 1, y: 2, width: 3, height: 4 },
}));

// Wrong IPC merge must still use handle.screens (eDP), not invent HDMI publish.
record("wrong_ipc_still_handle_screens", context.evaluateCandidate(null, {
  toplevel: wrongIpcPaired,
  sourceWindow: { id: "dock-a" },
  dockScreen: dockA,
  rect: { x: 5, y: 6, width: 7, height: 8 },
}));
record("wrong_ipc_hdmi_dock_rejects", context.evaluateCandidate(null, {
  toplevel: wrongIpcPaired,
  sourceWindow: { id: "dock-b" },
  dockScreen: dockB,
  rect: { x: 5, y: 6, width: 7, height: 8 },
}));

// Frame coalescing: second candidate replaces first for same handle.
const first = context.evaluateCandidate(null, {
  toplevel: handleA,
  sourceWindow: { id: "dock-a" },
  dockScreen: dockA,
  rect: { x: 1, y: 1, width: 10, height: 10 },
});
const second = context.evaluateCandidate(first.entry, {
  toplevel: handleA,
  sourceWindow: { id: "dock-a" },
  dockScreen: dockA,
  rect: { x: 9, y: 9, width: 20, height: 20 },
});
record("coalesce_last_wins", {
  firstAccept: first.accept,
  secondAccept: second.accept,
  x: second.entry.rect.x,
  y: second.entry.rect.y,
  w: second.entry.rect.width,
});

// Non-owner must not clobber an existing pending owner entry.
const ownerPending = context.evaluateCandidate(null, {
  toplevel: handleA,
  sourceWindow: { id: "dock-a" },
  dockScreen: dockA,
  rect: { x: 1, y: 1, width: 10, height: 10 },
}).entry;
const nonOwner = context.evaluateCandidate(ownerPending, {
  toplevel: handleA,
  sourceWindow: { id: "dock-b" },
  dockScreen: dockB,
  rect: { x: 99, y: 99, width: 1, height: 1 },
});
record("non_owner_keeps_pending", {
  accept: nonOwner.accept,
  reason: nonOwner.reason,
  pendingX: nonOwner.entry.rect.x,
});

console.log(JSON.stringify(cases));
"""


class DockRectanglePublisherTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        proc = subprocess.run(
            ["node", "-e", NODE_RUNNER, str(PUBLISHER)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.cases = {item["name"]: item["value"] for item in __import__("json").loads(proc.stdout)}

    def test_current_screen_owner_accepted(self) -> None:
        result = self.cases["owner_accept"]
        self.assertTrue(result["accept"])
        self.assertEqual(result["reason"], "accepted")
        self.assertEqual(result["entry"]["rect"]["width"], 48)

    def test_non_owner_dock_rejected(self) -> None:
        result = self.cases["non_owner_reject"]
        self.assertFalse(result["accept"])
        self.assertEqual(result["reason"], "screen-mismatch")

    def test_multi_and_none_screens_fail_closed(self) -> None:
        self.assertFalse(self.cases["multi_reject"]["accept"])
        self.assertEqual(self.cases["multi_reject"]["reason"], "multi-screen")
        self.assertFalse(self.cases["none_reject"]["accept"])
        self.assertEqual(self.cases["none_reject"]["reason"], "no-screens")

    def test_wrong_ipc_merge_still_uses_handle_screens(self) -> None:
        self.assertTrue(self.cases["wrong_ipc_still_handle_screens"]["accept"])
        self.assertFalse(self.cases["wrong_ipc_hdmi_dock_rejects"]["accept"])

    def test_frame_coalesce_last_candidate_wins(self) -> None:
        c = self.cases["coalesce_last_wins"]
        self.assertTrue(c["firstAccept"])
        self.assertTrue(c["secondAccept"])
        self.assertEqual(c["x"], 9)
        self.assertEqual(c["w"], 20)

    def test_non_owner_does_not_clobber_owner_pending(self) -> None:
        c = self.cases["non_owner_keeps_pending"]
        self.assertFalse(c["accept"])
        self.assertEqual(c["pendingX"], 1)

    def test_windows_service_owns_publisher_path(self) -> None:
        text = WINDOWS_QML.read_text(encoding="utf-8")
        self.assertIn("DockRectanglePublisher", text)
        self.assertIn("function submitDockRectangle", text)
        self.assertIn("function flushDockRectanglePending", text)
        self.assertIn("function scheduleDockRectangleFlush", text)
        # setRectangle must route through publisher, not wire setRectangle first.
        set_start = text.index("function setRectangle")
        set_rect = text[set_start : set_start + 1600]
        self.assertIn("submitDockRectangle", set_rect)
        self.assertNotIn("toplevel.setRectangle(", set_rect)

    def test_delegates_do_not_wire_setrectangle_directly(self) -> None:
        button = WINDOW_BUTTON.read_text(encoding="utf-8")
        minimized = DOCK_MINIMIZED.read_text(encoding="utf-8")
        self.assertIn("submitDockRectangle", button)
        self.assertIn("submitDockRectangle", minimized)
        # No direct toplevel.setRectangle in production update path.
        update_btn = button[button.index("function updateDockRectangle") : button.index("function scheduleDockRectangleUpdate")]
        self.assertNotIn("toplevel.setRectangle", update_btn)
        update_min = minimized[minimized.index("function updateDockRectangle") : minimized.index("function scheduleDockRectangleUpdate")]
        self.assertNotIn("setRectangle(", update_min.replace("submitDockRectangle", "SUBMIT"))


if __name__ == "__main__":
    unittest.main()
