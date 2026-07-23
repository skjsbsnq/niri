from __future__ import annotations

import json
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WINDOW_MODEL = ROOT / "services" / "windows" / "WindowModel.js"
WINDOWS_QML = ROOT / "services" / "Windows.qml"
FIXTURES = ROOT / "tests" / "fixtures" / "windows"


NODE_RUNNER = r"""
const fs = require("fs");
const vm = require("vm");

const modulePath = process.argv[1];
const fixturePath = process.argv[2];
const source = fs.readFileSync(modulePath, "utf8").replace(/^\s*\.pragma library\s*\n/, "");
const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
const context = {
  Array,
  Boolean,
  Date,
  JSON,
  Math,
  Number,
  Object,
  String,
  console,
  isFinite,
};

vm.createContext(context);
vm.runInContext(source, context, { filename: modulePath });

function windowKey(window) {
  if (!window)
    return null;
  return window.id === undefined || window.id === null ? window.modelKey : window.id;
}

function compactGeometry(geometry) {
  if (!geometry)
    return null;
  return {
    x: geometry.x,
    y: geometry.y,
    w: geometry.w,
    h: geometry.h,
    width: geometry.width,
    height: geometry.height,
  };
}

function compactModel(model) {
  return {
    id: model.id,
    modelKey: model.modelKey,
    title: model.title,
    appId: model.appId,
    toplevelKey: model.toplevel ? model.toplevel.key : null,
    workspace: model.workspace,
    workspaceId: model.workspaceId,
    output: model.output,
    pid: model.pid,
    isFocused: model.isFocused,
    isMinimized: model.isMinimized,
    isFloating: model.isFloating,
    isUrgent: model.isUrgent,
    urgent: model.urgent,
    geometry: compactGeometry(model.geometry),
  };
}

const workspacesById = {};
for (const rawWorkspace of fixture.workspaces || []) {
  const workspace = context.normalizeWorkspace(rawWorkspace);
  if (workspace)
    workspacesById[String(workspace.id)] = workspace;
}

const snapshot = context.normalizedWindowSnapshot(fixture.ipcWindows || [], workspacesById);
const models = context.mergeWindowModels(fixture.toplevels || [], snapshot.windows, workspacesById);
const result = {
  snapshotOrder: snapshot.order,
  models: models.map(compactModel),
  focusedKey: windowKey(context.findFocusedWindow(models)),
  minimizedKeys: context.filteredMinimizedWindows(models, true).map(windowKey),
  recentKeys: context.sortedRecentWindows(models).map(windowKey),
  workspaceOrder: context.sortedWorkspaceList(Object.values(workspacesById)).map((workspace) => workspace.id),
};

process.stdout.write(JSON.stringify(result));
"""


class WindowModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("node") is None:
            raise unittest.SkipTest("node is required to execute WindowModel.js fixtures")

    def run_fixture(self, fixture_name: str) -> dict:
        fixture_path = FIXTURES / fixture_name
        completed = subprocess.run(
            ["node", "-e", NODE_RUNNER, str(WINDOW_MODEL), str(fixture_path)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return json.loads(completed.stdout)

    def assert_model_subset(self, actual: dict, expected: dict, fixture_name: str, index: int) -> None:
        for key, value in expected.items():
            self.assertEqual(
                actual.get(key),
                value,
                f"{fixture_name} model {index} field {key}",
            )

    def test_window_model_exports_phase2_helpers(self) -> None:
        text = WINDOW_MODEL.read_text(encoding="utf-8")

        for function in (
            "normalizeIpcWindow",
            "mergeWindowModels",
            "findToplevelByIdentifier",
            "indexToplevelsByIdentifier",
            "identityKey",
            "buildWindowModel",
            "filteredMinimizedWindows",
            "sortedWorkspaceList",
            "sameLayout",
            "sameGeometry",
            "sameFocusTimestamp",
            "applyWorkspaceActivated",
            "applyWorkspaceUrgencyChanged",
            "applyWorkspaceActiveWindowChanged",
            "focusedOutputName",
            "activeWorkspaceForOutput",
            "activeWorkspaceIndexForOutput",
        ):
            self.assertIn(f"function {function}(", text)

        # R11 deletion: no fuzzy matcher on niri-managed merge path.
        self.assertNotIn("function findMatchingToplevel(", text)
        self.assertNotIn("normalizeIdentity(toplevel.appId", text)
        self.assertNotIn("normalizeTitle(toplevel.title", text)

    def test_same_layout_detects_geometry_changes_without_stringify(self) -> None:
        if shutil.which("node") is None:
            raise unittest.SkipTest("node is required to execute WindowModel.js fixtures")

        runner = r"""
const fs = require("fs");
const vm = require("vm");
const modulePath = process.argv[1];
const source = fs.readFileSync(modulePath, "utf8").replace(/^\s*\.pragma library\s*\n/, "");
const context = { Array, Boolean, Date, JSON, Math, Number, Object, String, console, isFinite };
vm.createContext(context);
vm.runInContext(source, context, { filename: modulePath });
const left = {
  tile_pos_in_workspace_view: [10, 20],
  tile_size: [100, 200],
  window_size: [96, 196],
  window_offset_in_tile: [2, 2],
  pos_in_scrolling_layout: [1, 1],
};
const same = {
  tile_pos_in_workspace_view: [10, 20],
  tile_size: [100, 200],
  window_size: [96, 196],
  window_offset_in_tile: [2, 2],
  pos_in_scrolling_layout: [1, 1],
};
const moved = {
  tile_pos_in_workspace_view: [11, 20],
  tile_size: [100, 200],
  window_size: [96, 196],
  window_offset_in_tile: [2, 2],
  pos_in_scrolling_layout: [1, 1],
};
const offsetOnly = {
  tile_pos_in_workspace_view: [10, 20],
  tile_size: [100, 200],
  window_size: [96, 196],
  window_offset_in_tile: [12, 2],
  pos_in_scrolling_layout: [1, 1],
};
const scrollOnly = {
  tile_pos_in_workspace_view: [10, 20],
  tile_size: [100, 200],
  window_size: [96, 196],
  window_offset_in_tile: [2, 2],
  pos_in_scrolling_layout: [2, 1],
};
process.stdout.write(JSON.stringify({
  same: context.sameLayout(left, same),
  moved: context.sameLayout(left, moved),
  offsetOnly: context.sameLayout(left, offsetOnly),
  scrollOnly: context.sameLayout(left, scrollOnly),
  bothNullScroll: context.sameLayout(
    Object.assign({}, left, { pos_in_scrolling_layout: null }),
    Object.assign({}, same, { pos_in_scrolling_layout: null })
  ),
  geoSame: context.sameGeometry(context.geometryFromLayout(left), context.geometryFromLayout(same)),
  geoMoved: context.sameGeometry(context.geometryFromLayout(left), context.geometryFromLayout(moved)),
}));
"""
        completed = subprocess.run(
            ["node", "-e", runner, str(WINDOW_MODEL)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        result = json.loads(completed.stdout)
        self.assertTrue(result["same"])
        self.assertFalse(result["moved"])
        self.assertFalse(result["offsetOnly"])
        self.assertFalse(result["scrollOnly"])
        self.assertTrue(result["bothNullScroll"])
        self.assertTrue(result["geoSame"])
        self.assertFalse(result["geoMoved"])

    def test_windows_qml_keeps_public_window_api_and_delegates_merge_logic(self) -> None:
        text = WINDOWS_QML.read_text(encoding="utf-8")

        self.assertIn('import "windows/WindowModel.js" as WindowModel', text)
        for property_name in (
            "windowList",
            "minimizedWindowList",
            "recentWindowList",
            "focusedWindow",
        ):
            # Cached writable properties (layout events must not re-merge every frame).
            self.assertIn(f"property var {property_name}", text)
        self.assertIn("function rebuildMergedWindows()", text)
        self.assertIn("function patchMergedWindowLayouts()", text)
        self.assertIn('applyLayoutChanges', text)
        self.assertIn('mode": "layout"', text)

        for function_name in (
            "activate",
            "minimize",
            "restore",
            "closeWindow",
            "mergeWindowModels",
            "normalizeIpcWindow",
            "activeWorkspaceForOutput",
            "activeWorkspaceIndexForOutput",
            "publishWorkspaces",
        ):
            self.assertIn(f"function {function_name}(", text)

        self.assertIn("WindowModel.mergeWindowModels", text)
        self.assertIn("WindowModel.normalizeIpcWindow", text)
        self.assertIn("WindowModel.applyWorkspaceActivated", text)
        self.assertIn("readonly property string focusedOutputName", text)
        self.assertIn("function windowIdString(window)", text)
        self.assertIn('action(["focus-window", "--id", focusId])', text)
        self.assertIn('action(["minimize-window", "--id", minimizeId])', text)
        self.assertIn('action(["restore-window", "--id", restoreId])', text)

    def test_window_fixture_names_cover_phase2_edges(self) -> None:
        fixture_names = {path.name for path in FIXTURES.glob("*.json")}
        expected = {
            "same-app-multi-window.json",
            "identical-title.json",
            "title-change-fallback.json",
            "toplevel-only-no-ipc-id.json",
            "ipc-only-minimized-urgent.json",
            "workspace-missing-transient.json",
            "wrong-title-no-fuzzy.json",
        }
        self.assertTrue(expected.issubset(fixture_names))

    def test_identity_key_rejects_unsafe_integer_and_keeps_string(self) -> None:
        if shutil.which("node") is None:
            raise unittest.SkipTest("node is required to execute WindowModel.js fixtures")

        runner = r"""
const fs = require("fs");
const vm = require("vm");
const modulePath = process.argv[1];
const source = fs.readFileSync(modulePath, "utf8").replace(/^\s*\.pragma library\s*\n/, "");
const context = { Array, Boolean, Date, JSON, Math, Number, Object, String, console, isFinite, BigInt };
vm.createContext(context);
vm.runInContext(source, context, { filename: modulePath });
process.stdout.write(JSON.stringify({
  num: context.identityKey(42),
  str: context.identityKey("42"),
  bigSafe: context.identityKey(Number.MAX_SAFE_INTEGER),
  unsafe: context.identityKey(Number.MAX_SAFE_INTEGER + 1),
  leadingZero: context.identityKey("01"),
  empty: context.identityKey(""),
  bigint: context.identityKey(typeof BigInt === "function" ? BigInt("9007199254740993") : null),
}));
"""
        completed = subprocess.run(
            ["node", "-e", runner, str(WINDOW_MODEL)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        result = json.loads(completed.stdout)
        self.assertEqual(result["num"], "42")
        self.assertEqual(result["str"], "42")
        self.assertEqual(result["bigSafe"], str(2**53 - 1))
        self.assertIsNone(result["unsafe"])
        self.assertIsNone(result["leadingZero"])
        self.assertIsNone(result["empty"])
        self.assertEqual(result["bigint"], "9007199254740993")

    def test_merge_is_linear_via_identifier_map_for_many_windows(self) -> None:
        """Build 100 same-app windows; merge must bind each id exactly once."""
        if shutil.which("node") is None:
            raise unittest.SkipTest("node is required to execute WindowModel.js fixtures")

        n = 100
        toplevels = []
        ipc_windows = []
        for i in range(1, n + 1):
            toplevels.append({
                "key": f"w{i}",
                "identifier": str(i),
                "appId": "org.same.App",
                "title": "Same",
                "activated": False,
                "minimized": False,
            })
            ipc_windows.append({
                "id": i,
                "app_id": "org.same.App",
                "title": "Same",
                "workspace_id": 1,
                "is_focused": False,
                "is_minimized": False,
                "is_urgent": False,
                "layout": {
                    "tile_pos_in_workspace_view": [i, 0],
                    "tile_size": [100, 100],
                },
            })
        fixture = {
            "workspaces": [{"id": 1, "idx": 1, "output": "eDP-1", "coordinates": [0]}],
            "toplevels": toplevels,
            "ipcWindows": ipc_windows,
        }
        fixture_path = FIXTURES / "_generated_100.json"
        try:
            fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
            # Use runner without expect; assert via node inline.
            runner = r"""
const fs = require("fs");
const vm = require("vm");
const modulePath = process.argv[1];
const fixturePath = process.argv[2];
const source = fs.readFileSync(modulePath, "utf8").replace(/^\s*\.pragma library\s*\n/, "");
const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
const context = { Array, Boolean, Date, JSON, Math, Number, Object, String, console, isFinite };
vm.createContext(context);
vm.runInContext(source, context, { filename: modulePath });
const workspacesById = {};
for (const raw of fixture.workspaces || []) {
  const w = context.normalizeWorkspace(raw);
  if (w) workspacesById[String(w.id)] = w;
}
const snapshot = context.normalizedWindowSnapshot(fixture.ipcWindows || [], workspacesById);
const models = context.mergeWindowModels(fixture.toplevels || [], snapshot.windows, workspacesById);
let ok = models.length === fixture.ipcWindows.length;
for (let i = 0; i < models.length; i++) {
  const m = models[i];
  if (!m.toplevel || m.toplevel.key !== ("w" + m.id)) ok = false;
}
process.stdout.write(JSON.stringify({ ok, count: models.length }));
"""
            completed = subprocess.run(
                ["node", "-e", runner, str(WINDOW_MODEL), str(fixture_path)],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            result = json.loads(completed.stdout)
            self.assertTrue(result["ok"], result)
            self.assertEqual(result["count"], n)
        finally:
            if fixture_path.exists():
                fixture_path.unlink()

    def test_window_model_fixture_expectations(self) -> None:
        for fixture_path in sorted(FIXTURES.glob("*.json")):
            with self.subTest(fixture=fixture_path.name):
                fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
                actual = self.run_fixture(fixture_path.name)
                expected = fixture["expect"]

                self.assertEqual(len(actual["models"]), len(expected["models"]), fixture_path.name)
                for index, expected_model in enumerate(expected["models"]):
                    self.assert_model_subset(actual["models"][index], expected_model, fixture_path.name, index)

                for key in ("focusedKey", "minimizedKeys", "recentKeys", "workspaceOrder"):
                    self.assertEqual(actual[key], expected[key], f"{fixture_path.name} {key}")


if __name__ == "__main__":
    unittest.main()
