from __future__ import annotations

import json
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WINDOW_MODEL = ROOT / "services" / "windows" / "WindowModel.js"
WINDOWS_QML = ROOT / "services" / "Windows.qml"


NODE_HELPER = r"""
const fs = require("fs");
const vm = require("vm");
const modulePath = process.argv[1];
const source = fs.readFileSync(modulePath, "utf8").replace(/^\s*\.pragma library\s*\n/, "");
const context = {
  Array, Boolean, Date, JSON, Math, Number, Object, String, console, isFinite,
};
vm.createContext(context);
vm.runInContext(source, context, { filename: modulePath });

const request = JSON.parse(process.argv[2]);
const workspaces = (request.workspaces || []).map((raw) => context.normalizeWorkspace(raw));
let result = { workspaces };

function compact(list) {
  if (list === null || list === undefined)
    return null;
  return list.map((ws) => ({
    id: ws.id,
    idx: ws.idx,
    output: ws.output,
    isActive: !!ws.isActive,
    isFocused: !!ws.isFocused,
    isUrgent: !!ws.isUrgent,
    activeWindowId: ws.activeWindowId === undefined ? null : ws.activeWindowId,
  }));
}

switch (request.op) {
  case "normalize":
    result = { workspaces: compact(workspaces) };
    break;
  case "activated":
    result = {
      workspaces: compact(context.applyWorkspaceActivated(
        workspaces, request.id, !!request.focused
      )),
    };
    break;
  case "urgency":
    result = {
      workspaces: compact(context.applyWorkspaceUrgencyChanged(
        workspaces, request.id, !!request.urgent
      )),
    };
    break;
  case "activeWindow":
    result = {
      workspaces: compact(context.applyWorkspaceActiveWindowChanged(
        workspaces, request.workspaceId, request.activeWindowId
      )),
    };
    break;
  case "queries":
    result = {
      focusedOutputName: context.focusedOutputName(workspaces),
      activeForA: compact([context.activeWorkspaceForOutput(workspaces, "A")].filter(Boolean))[0] || null,
      activeForB: compact([context.activeWorkspaceForOutput(workspaces, "B")].filter(Boolean))[0] || null,
      indexA: context.activeWorkspaceIndexForOutput(workspaces, "A"),
      indexB: context.activeWorkspaceIndexForOutput(workspaces, "B"),
      focused: compact([context.findFocusedWorkspace(workspaces)].filter(Boolean))[0] || null,
    };
    break;
  case "prune":
    result = {
      workspaces: compact(context.pruneWorkspacesForOutputs(
        workspaces, request.connectedOutputs || []
      )),
    };
    break;
  case "sequence": {
    let current = workspaces;
    for (const step of request.steps || []) {
      if (step.op === "workspacesChanged") {
        current = (step.workspaces || []).map((raw) => context.normalizeWorkspace(raw));
      } else if (step.op === "activated") {
        const next = context.applyWorkspaceActivated(current, step.id, !!step.focused);
        if (next) current = next;
      } else if (step.op === "urgency") {
        const next = context.applyWorkspaceUrgencyChanged(current, step.id, !!step.urgent);
        if (next) current = next;
      } else if (step.op === "activeWindow") {
        const next = context.applyWorkspaceActiveWindowChanged(
          current, step.workspaceId, step.activeWindowId
        );
        if (next) current = next;
      } else if (step.op === "prune") {
        current = context.pruneWorkspacesForOutputs(current, step.connectedOutputs || []);
      }
    }
    result = {
      workspaces: compact(current),
      focusedOutputName: context.focusedOutputName(current),
      indexA: context.activeWorkspaceIndexForOutput(current, "A"),
      indexB: context.activeWorkspaceIndexForOutput(current, "B"),
      sortedIds: context.sortedWorkspaceList(current).map((ws) => ws.id),
    };
    break;
  }
  default:
    throw new Error("unknown op " + request.op);
}

process.stdout.write(JSON.stringify(result));
"""


def run_node(request: dict) -> dict:
    if shutil.which("node") is None:
        raise unittest.SkipTest("node is required to execute WindowModel.js")
    completed = subprocess.run(
        ["node", "-e", NODE_HELPER, str(WINDOW_MODEL), json.dumps(request)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return json.loads(completed.stdout)


def ws(
    workspace_id: int,
    idx: int,
    output: str,
    *,
    active: bool = False,
    focused: bool = False,
    urgent: bool = False,
    active_window_id=None,
) -> dict:
    return {
        "id": workspace_id,
        "idx": idx,
        "name": None,
        "output": output,
        "is_urgent": urgent,
        "is_active": active,
        "is_focused": focused,
        "active_window_id": active_window_id,
    }


class WindowsWorkspaceEventTests(unittest.TestCase):
    def test_window_model_exports_workspace_event_helpers(self) -> None:
        text = WINDOW_MODEL.read_text(encoding="utf-8")
        for name in (
            "applyWorkspaceActivated",
            "applyWorkspaceUrgencyChanged",
            "applyWorkspaceActiveWindowChanged",
            "focusedOutputName",
            "activeWorkspaceForOutput",
            "activeWorkspaceIndexForOutput",
            "findFocusedWorkspace",
            "pruneWorkspacesForOutputs",
        ):
            self.assertIn(f"function {name}(", text)

    def test_windows_qml_handles_incremental_workspace_events(self) -> None:
        text = WINDOWS_QML.read_text(encoding="utf-8")
        self.assertIn("WorkspaceActivated", text)
        self.assertIn("WorkspaceUrgencyChanged", text)
        self.assertIn("WorkspaceActiveWindowChanged", text)
        self.assertIn("function activeWorkspaceForOutput(", text)
        self.assertIn("function activeWorkspaceIndexForOutput(", text)
        self.assertIn("readonly property string focusedOutputName", text)
        self.assertIn("WindowModel.applyWorkspaceActivated", text)
        self.assertIn("findIpcFocusedWorkspace", text)
        self.assertIn("function clearIpcWorkspaceBaseline(", text)
        self.assertIn("root.clearIpcWorkspaceBaseline()", text)
        # Single event stream owner — no second niri socket.
        self.assertEqual(text.count('command: ["niri", "msg", "--json", "event-stream"]'), 1)
        self.assertNotIn("CompositorBackend", text)
        self.assertNotIn("NIRI_SOCKET", text)

    def test_workspace_label_prefers_idx_over_stable_id(self) -> None:
        """activeWorkspaceName must show user-visible idx, never raw entity id."""
        text = WINDOWS_QML.read_text(encoding="utf-8")
        # Extract workspaceLabel body roughly and assert idx-first policy.
        start = text.index("function workspaceLabel(workspace, fallbackIndex)")
        end = text.index("function workspaceDisplayLabel", start)
        body = text[start:end]
        self.assertIn("workspaceSortIndex(workspace, fallbackIndex)", body)
        # Must not return stable id as the primary unnamed label.
        self.assertNotIn("var id = String(workspace.id", body)
        self.assertNotRegex(body, r"return id;")

        # Pure sort index: id 99 with idx 2 is still ordinal 2.
        result = run_node({
            "op": "queries",
            "workspaces": [
                {
                    "id": 99,
                    "idx": 2,
                    "name": None,
                    "output": "A",
                    "is_urgent": False,
                    "is_active": True,
                    "is_focused": True,
                    "active_window_id": None,
                },
                {
                    "id": 1,
                    "idx": 1,
                    "name": None,
                    "output": "A",
                    "is_urgent": False,
                    "is_active": False,
                    "is_focused": False,
                    "active_window_id": None,
                },
            ],
        })
        self.assertEqual(result["indexA"], 2)
        self.assertEqual(result["focused"]["id"], 99)
        self.assertEqual(result["focused"]["idx"], 2)

    def test_reconnect_clears_stale_ipc_before_baseline(self) -> None:
        text = WINDOWS_QML.read_text(encoding="utf-8")
        self.assertIn("clearIpcWorkspaceBaseline", text)
        # Both exit and start drop the IPC snapshot so WindowManager can win
        # the activeWorkspace fallback until WorkspacesChanged arrives.
        self.assertGreaterEqual(text.count("root.clearIpcWorkspaceBaseline()"), 2)

    def test_full_workspaces_changed_baseline(self) -> None:
        result = run_node({
            "op": "sequence",
            "steps": [{
                "op": "workspacesChanged",
                "workspaces": [
                    ws(1, 1, "A", active=True, focused=True, active_window_id=10),
                    ws(2, 2, "A"),
                    ws(3, 1, "B", active=True),
                ],
            }],
        })
        self.assertEqual(result["focusedOutputName"], "A")
        self.assertEqual(result["indexA"], 1)
        self.assertEqual(result["indexB"], 1)
        active = {item["id"]: item for item in result["workspaces"] if item["isActive"]}
        self.assertEqual(set(active), {1, 3})
        self.assertTrue(any(item["id"] == 1 and item["isFocused"] for item in result["workspaces"]))

    def test_single_workspace_activated_focused(self) -> None:
        baseline = [
            ws(1, 1, "A", active=True, focused=True),
            ws(2, 2, "A"),
            ws(3, 1, "B", active=True),
        ]
        result = run_node({
            "op": "sequence",
            "workspaces": baseline,
            "steps": [
                {"op": "activated", "id": 2, "focused": True},
            ],
        })
        by_id = {item["id"]: item for item in result["workspaces"]}
        self.assertTrue(by_id[2]["isActive"])
        self.assertTrue(by_id[2]["isFocused"])
        self.assertFalse(by_id[1]["isActive"])
        self.assertFalse(by_id[1]["isFocused"])
        # Other output remains active and is not focused.
        self.assertTrue(by_id[3]["isActive"])
        self.assertFalse(by_id[3]["isFocused"])
        self.assertEqual(result["focusedOutputName"], "A")
        self.assertEqual(result["indexA"], 2)

    def test_workspace_activated_unfocused_does_not_steal_focus(self) -> None:
        # focused=false: active on that output only; global focus unchanged.
        baseline = [
            ws(1, 1, "A", active=True, focused=True),
            ws(2, 2, "A"),
            ws(3, 1, "B", active=True),
            ws(4, 2, "B"),
        ]
        result = run_node({
            "op": "sequence",
            "workspaces": baseline,
            "steps": [
                {"op": "activated", "id": 4, "focused": False},
            ],
        })
        by_id = {item["id"]: item for item in result["workspaces"]}
        self.assertTrue(by_id[1]["isActive"])
        self.assertTrue(by_id[1]["isFocused"])
        self.assertTrue(by_id[4]["isActive"])
        self.assertFalse(by_id[4]["isFocused"])
        self.assertFalse(by_id[3]["isActive"])
        self.assertEqual(result["focusedOutputName"], "A")
        self.assertEqual(result["indexB"], 2)

    def test_multi_output_queries(self) -> None:
        result = run_node({
            "op": "queries",
            "workspaces": [
                ws(1, 1, "A", active=True, focused=True),
                ws(2, 2, "A"),
                ws(3, 1, "B"),
                ws(4, 3, "B", active=True),
            ],
        })
        self.assertEqual(result["focusedOutputName"], "A")
        self.assertEqual(result["activeForA"]["id"], 1)
        self.assertEqual(result["activeForB"]["id"], 4)
        self.assertEqual(result["indexA"], 1)
        self.assertEqual(result["indexB"], 3)
        self.assertEqual(result["focused"]["id"], 1)

    def test_activation_missing_id_is_noop(self) -> None:
        baseline = [ws(1, 1, "A", active=True, focused=True)]
        result = run_node({
            "op": "activated",
            "workspaces": baseline,
            "id": 99,
            "focused": True,
        })
        self.assertIsNone(result["workspaces"])

    def test_urgency_and_active_window(self) -> None:
        baseline = [
            ws(1, 1, "A", active=True, focused=True, active_window_id=10),
            ws(2, 2, "A"),
        ]
        result = run_node({
            "op": "sequence",
            "workspaces": baseline,
            "steps": [
                {"op": "urgency", "id": 2, "urgent": True},
                {"op": "activeWindow", "workspaceId": 1, "activeWindowId": 42},
                {"op": "activeWindow", "workspaceId": 1, "activeWindowId": None},
            ],
        })
        by_id = {item["id"]: item for item in result["workspaces"]}
        self.assertTrue(by_id[2]["isUrgent"])
        self.assertIsNone(by_id[1]["activeWindowId"])

    def test_reorder_updates_idx_keeps_id(self) -> None:
        # WorkspacesChanged after move/reorder: ids stable, idx updated.
        result = run_node({
            "op": "sequence",
            "steps": [
                {
                    "op": "workspacesChanged",
                    "workspaces": [
                        ws(10, 1, "A", active=True, focused=True),
                        ws(20, 2, "A"),
                    ],
                },
                {
                    "op": "workspacesChanged",
                    "workspaces": [
                        ws(20, 1, "A", active=True, focused=True),
                        ws(10, 2, "A"),
                    ],
                },
            ],
        })
        by_id = {item["id"]: item for item in result["workspaces"]}
        self.assertEqual(by_id[20]["idx"], 1)
        self.assertEqual(by_id[10]["idx"], 2)
        self.assertEqual(result["indexA"], 1)
        self.assertTrue(by_id[20]["isActive"])
        self.assertTrue(by_id[20]["isFocused"])

    def test_output_remove_prunes_stale_workspaces(self) -> None:
        result = run_node({
            "op": "sequence",
            "workspaces": [
                ws(1, 1, "A", active=True, focused=True),
                ws(2, 1, "B", active=True),
                ws(3, 2, "B"),
            ],
            "steps": [
                {"op": "prune", "connectedOutputs": ["A"]},
            ],
        })
        ids = [item["id"] for item in result["workspaces"]]
        self.assertEqual(ids, [1])
        self.assertEqual(result["focusedOutputName"], "A")

    def test_empty_workspace_list(self) -> None:
        result = run_node({
            "op": "sequence",
            "steps": [{"op": "workspacesChanged", "workspaces": []}],
        })
        self.assertEqual(result["workspaces"], [])
        self.assertEqual(result["focusedOutputName"], "")
        self.assertIsNone(result["indexA"])

    def test_reconnect_baseline_replaces_stale_activation(self) -> None:
        # After disconnect, first WorkspacesChanged is the authority again.
        result = run_node({
            "op": "sequence",
            "steps": [
                {
                    "op": "workspacesChanged",
                    "workspaces": [
                        ws(1, 1, "A", active=True, focused=True),
                        ws(2, 2, "A"),
                    ],
                },
                {"op": "activated", "id": 2, "focused": True},
                {
                    "op": "workspacesChanged",
                    "workspaces": [
                        ws(1, 1, "A", active=True, focused=True),
                        ws(2, 2, "A"),
                    ],
                },
            ],
        })
        by_id = {item["id"]: item for item in result["workspaces"]}
        self.assertTrue(by_id[1]["isActive"])
        self.assertTrue(by_id[1]["isFocused"])
        self.assertFalse(by_id[2]["isActive"])
        self.assertFalse(by_id[2]["isFocused"])

    def test_malformed_event_helpers_do_not_throw(self) -> None:
        # Missing id / empty list should return null or empty without raising.
        result = run_node({
            "op": "urgency",
            "workspaces": [ws(1, 1, "A", active=True, focused=True)],
            "id": 999,
            "urgent": True,
        })
        self.assertIsNone(result["workspaces"])

        result = run_node({
            "op": "activeWindow",
            "workspaces": [ws(1, 1, "A", active=True, focused=True)],
            "workspaceId": 999,
            "activeWindowId": 1,
        })
        self.assertIsNone(result["workspaces"])

        # Windows.qml must ignore unknown / non-workspace events without crash
        # path; verify parser structure still catches JSON errors only.
        text = WINDOWS_QML.read_text(encoding="utf-8")
        self.assertIn("JSON.parse(text)", text)
        self.assertIn('root.setValue("lastError", String(error))', text)


if __name__ == "__main__":
    unittest.main()
