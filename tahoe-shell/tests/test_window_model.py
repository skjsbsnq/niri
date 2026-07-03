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
            "findMatchingToplevel",
            "buildWindowModel",
            "filteredMinimizedWindows",
            "sortedWorkspaceList",
        ):
            self.assertIn(f"function {function}(", text)

    def test_windows_qml_keeps_public_window_api_and_delegates_merge_logic(self) -> None:
        text = WINDOWS_QML.read_text(encoding="utf-8")

        self.assertIn('import "windows/WindowModel.js" as WindowModel', text)
        for property_name in (
            "windowList",
            "minimizedWindowList",
            "recentWindowList",
            "focusedWindow",
        ):
            self.assertIn(f"readonly property var {property_name}", text)

        for function_name in (
            "activate",
            "minimize",
            "restore",
            "closeWindow",
            "mergeWindowModels",
            "normalizeIpcWindow",
        ):
            self.assertIn(f"function {function_name}(", text)

        self.assertIn("WindowModel.mergeWindowModels", text)
        self.assertIn("WindowModel.normalizeIpcWindow", text)
        self.assertIn('action(["focus-window", "--id", String(window.id)])', text)
        self.assertIn('action(["minimize-window", "--id", String(window.id)])', text)
        self.assertIn('action(["restore-window", "--id", String(window.id)])', text)

    def test_window_fixture_names_cover_phase2_edges(self) -> None:
        fixture_names = {path.name for path in FIXTURES.glob("*.json")}
        expected = {
            "same-app-multi-window.json",
            "identical-title.json",
            "title-change-fallback.json",
            "toplevel-only-no-ipc-id.json",
            "ipc-only-minimized-urgent.json",
            "workspace-missing-transient.json",
        }
        self.assertTrue(expected.issubset(fixture_names))

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
