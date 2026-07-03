from __future__ import annotations

import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SEARCH_QML = ROOT / "services" / "Search.qml"
SEARCH_DIR = ROOT / "services" / "search"


NODE_RUNNER = r"""
const fs = require("fs");
const vm = require("vm");

const modulePath = process.argv[1];
const snippet = process.argv[2];
const source = fs.readFileSync(modulePath, "utf8").replace(/^\s*\.pragma library\s*\n/, "");
const context = {
  Array,
  Boolean,
  Date,
  JSON,
  Math,
  Number,
  Object,
  RegExp,
  String,
  console,
  isFinite,
};

vm.createContext(context);
vm.runInContext(source, context, { filename: modulePath });
const result = vm.runInContext(snippet, context, { filename: "snippet.js" });
process.stdout.write(JSON.stringify(result));
"""


class SearchProviderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("node") is None:
            raise unittest.SkipTest("node is required to execute search provider fixtures")

    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def run_module(self, name: str, snippet: str) -> dict:
        completed = subprocess.run(
            ["node", "-e", NODE_RUNNER, str(SEARCH_DIR / name), snippet],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return json.loads(completed.stdout)

    def test_search_qml_delegates_phase5_providers_without_reordering(self) -> None:
        text = SEARCH_QML.read_text(encoding="utf-8")

        for module_name, alias in (
            ("AppProvider.js", "AppProvider"),
            ("CalculatorProvider.js", "CalculatorProvider"),
            ("ClipboardProvider.js", "ClipboardProvider"),
            ("CommandProvider.js", "CommandProvider"),
            ("ScreenshotProvider.js", "ScreenshotProvider"),
            ("SettingsProvider.js", "SettingsProvider"),
            ("SystemActionProvider.js", "SystemActionProvider"),
            ("TaskIndexProvider.js", "TaskIndexProvider"),
            ("WindowProvider.js", "WindowProvider"),
        ):
            self.assertIn(f'import "search/{module_name}" as {alias}', text)

        provider_order = re.findall(r"results = results\.concat\((\w+Results)\(normalized", text)
        self.assertEqual(
            provider_order,
            [
                "commandResults",
                "calculatorResults",
                "screenshotResults",
                "settingsResults",
                "systemActionResults",
                "windowResults",
                "pinnedClipboardResults",
                "appResults",
                "taskIndexResults",
            ],
        )

        self.assertIn("return CommandProvider.commandText(query);", text)
        self.assertIn("return TaskIndexProvider.shouldRun(query);", text)
        self.assertIn("return TaskIndexProvider.pythonSource();", text)
        self.assertIn("exec timeout 1s python3 -c", text)
        self.assertNotIn("function parseExpression(", text)
        self.assertNotIn("deadline = time.monotonic() + 0.82", text)

    def test_shell_command_guardrails_stay_prefix_only_and_activation_scoped(self) -> None:
        command = self.run_module(
            "CommandProvider.js",
            r"""
            var ctx = {
              makeResult: function(fields) { return fields; },
              iconPath: function(setName, fileName) { return setName + "/" + fileName; }
            };
            ({
              plain: commandText("ls -la"),
              gt: commandText("> ls -la"),
              bang: commandText("! systemctl suspend"),
              empty: commandText(">   "),
              plainCount: results("ls -la", ctx).length,
              commandResult: results("> echo hi", ctx)[0]
            })
            """,
        )

        self.assertEqual(command["plain"], "")
        self.assertEqual(command["gt"], "ls -la")
        self.assertEqual(command["bang"], "systemctl suspend")
        self.assertEqual(command["empty"], "")
        self.assertEqual(command["plainCount"], 0)
        self.assertEqual(command["commandResult"]["kind"], "command")
        self.assertEqual(command["commandResult"]["provider"], "command")
        self.assertEqual(command["commandResult"]["command"], "echo hi")

        text = SEARCH_QML.read_text(encoding="utf-8")
        self.assertIn('if (result.kind === "command") {', text)
        self.assertIn("runShellCommand(result.command);", text)
        self.assertEqual(text.count("runShellCommand(result.command);"), 1)

    def test_calculator_provider_preserves_parser_edges(self) -> None:
        result = self.run_module(
            "CalculatorProvider.js",
            r"""
            var ctx = {
              makeResult: function(fields) { return fields; },
              iconPath: function(setName, fileName) { return setName + "/" + fileName; }
            };
            ({
              expression: parseQuery("1 + 2 * 3").expression,
              value: parseQuery("1 + 2 * 3").value,
              explicit: results("=2^3", ctx)[0],
              implicitPlainNumber: parseQuery("42"),
              isoDate: parseQuery("2026-07-03"),
              formatted: formatNumber(1 / 4)
            })
            """,
        )

        self.assertEqual(result["expression"], "1 + 2 * 3")
        self.assertEqual(result["value"], 7)
        self.assertEqual(result["explicit"]["title"], "8")
        self.assertEqual(result["explicit"]["kind"], "calculator")
        self.assertIsNone(result["implicitPlainNumber"])
        self.assertIsNone(result["isoDate"])
        self.assertEqual(result["formatted"], "0.25")

    def test_task_index_provider_keeps_timeout_script_and_nonblocking_prefix_rules(self) -> None:
        result = self.run_module(
            "TaskIndexProvider.js",
            r"""
            var ctx = {
              defaultLimit: 6,
              cachedTaskQuery: "report",
              cachedTaskEntries: [
                { kind: "recent-file", path: "/home/test/report.txt", title: "Report", subtitle: "最近文件 · ~/report.txt" },
                { kind: "folder", path: "/home/test/Reports", title: "Reports", subtitle: "文件夹 · ~/Reports" }
              ],
              pathBasename: function(path) { return String(path).split("/").pop(); },
              compactPath: function(path) { return String(path).replace("/home/test", "~"); },
              iconPath: function(setName, fileName) { return setName + "/" + fileName; },
              scoreText: function(title, subtitle, keywords, query, base) { return base + 1; },
              makeResult: function(fields) { return fields; }
            };
            ({
              shortQuery: shouldRun("a"),
              normalQuery: shouldRun("ab"),
              commandQuery: shouldRun("> ls"),
              bangQuery: shouldRun("! reboot"),
              calculatorQuery: shouldRun("=1+1"),
              parsed: parseOutput(JSON.stringify([
                { kind: "recent-file", path: "/home/test/a.txt", title: "", subtitle: "", mtime: 5 },
                { kind: "ignored", path: "/home/test/b.txt" },
                { kind: "folder", path: "/home/test/docs", mtime: 3 },
                { kind: "tracker-file", path: "/home/test/tracker.txt", mtime: 9 },
                { kind: "tracker-folder", path: "/home/test/Tracker", mtime: 7 }
              ]), ctx),
              results: results("report", 6, ctx),
              trackerResults: (function() {
                ctx.cachedTaskQuery = "tracker";
                ctx.cachedTaskEntries = [
                  { kind: "tracker-file", path: "/home/test/tracker.txt", title: "Tracker", subtitle: "Tracker 文件 · ~/tracker.txt" },
                  { kind: "tracker-folder", path: "/home/test/Tracker", title: "Tracker", subtitle: "Tracker 文件夹 · ~/Tracker" }
                ];
                return results("tracker", 6, ctx);
              })(),
              python: pythonSource()
            })
            """,
        )

        self.assertFalse(result["shortQuery"])
        self.assertTrue(result["normalQuery"])
        self.assertFalse(result["commandQuery"])
        self.assertFalse(result["bangQuery"])
        self.assertFalse(result["calculatorQuery"])
        self.assertEqual(len(result["parsed"]), 4)
        self.assertEqual(result["parsed"][0]["title"], "a.txt")
        self.assertEqual(result["parsed"][1]["subtitle"], "~/docs")
        self.assertEqual([item["provider"] for item in result["results"]], ["recent-files", "folders"])
        self.assertEqual([item["kind"] for item in result["trackerResults"]], ["recent-file", "folder"])
        self.assertEqual([item["provider"] for item in result["trackerResults"]], ["tracker", "tracker"])
        self.assertIn("deadline = time.monotonic() + 0.82", result["python"])
        self.assertIn("shutil.which('tracker3')", result["python"])
        self.assertIn("add_tracker_results()", result["python"])
        self.assertIn("results[:80]", result["python"])

    def test_interactive_provider_samples_keep_result_shapes(self) -> None:
        app = self.run_module(
            "AppProvider.js",
            r"""
            var requestedLimit = 0;
            var appObject = { id: "org.example.Code", genericName: "Editor", startupClass: "Code", execString: "code" };
            var ctx = {
              defaultLimit: 6,
              appsService: {
                spotlightResults: function(query, limit) { requestedLimit = limit; return [appObject]; },
                appLabel: function(app) { return "Code"; },
                appStableId: function(app) { return app.id; },
                iconForApp: function(app) { return "code.png"; }
              },
              scoreText: function(title, subtitle, keywords, query, base) { return base + 80; },
              makeResult: function(fields) { return fields; }
            };
            var out = results("code", 6, ctx);
            ({ requestedLimit: requestedLimit, results: out })
            """,
        )
        self.assertEqual(app["requestedLimit"], 12)
        self.assertEqual(app["results"][0]["id"], "app:org.example.Code")
        self.assertEqual(app["results"][0]["kind"], "application")

        window = self.run_module(
            "WindowProvider.js",
            r"""
            var win = {
              id: 42,
              modelKey: "niri:42",
              title: "Terminal",
              appId: "org.example.Terminal",
              output: "eDP-1",
              isFocused: true,
              isMinimized: true,
              workspace: { name: "1" }
            };
            var ctx = {
              defaultLimit: 6,
              windowsService: { recentWindowList: [win] },
              appsService: {
                windowAppLabel: function(window) { return "Terminal"; },
                appForWindow: function(window) { return null; },
                iconForAppId: function(appId) { return appId + ".png"; }
              },
              iconPath: function(setName, fileName) { return setName + "/" + fileName; },
              scoreText: function(title, subtitle, keywords, query, base) { return base; },
              makeResult: function(fields) { return fields; }
            };
            ({ title: title(win, ctx), subtitle: subtitle(win, ctx), result: results("term", 6, ctx)[0] })
            """,
        )
        self.assertEqual(window["title"], "Terminal")
        self.assertIn("工作区 1", window["subtitle"])
        self.assertIn("已最小化", window["subtitle"])
        self.assertEqual(window["result"]["score"], 848)

        clipboard = self.run_module(
            "ClipboardProvider.js",
            r"""
            var ctx = {
              defaultLimit: 6,
              clipboardService: {
                pinnedEntries: [{ text: "hello world", preview: "" }],
                previewForText: function(text) { return text.substring(0, 5); }
              },
              iconPath: function(setName, fileName) { return setName + "/" + fileName; },
              scoreText: function(title, subtitle, keywords, query, base) { return base + 1; },
              makeResult: function(fields) { return fields; }
            };
            ({ result: results("hello", 6, ctx)[0] })
            """,
        )
        self.assertEqual(clipboard["result"]["title"], "hello")
        self.assertEqual(clipboard["result"]["kind"], "clipboard-pin")

        screenshot = self.run_module(
            "ScreenshotProvider.js",
            r"""
            var ctx = {
              screenshotService: {
                matchesQuery: function(query) { return query === "shot"; },
                spotlightResult: function() { return { id: "selection", title: "截图", score: 860 }; }
              },
              iconPath: function(setName, fileName) { return setName + "/" + fileName; },
              makeResult: function(fields) { return fields; }
            };
            ({ miss: results("photo", ctx).length, hit: results("shot", ctx)[0] })
            """,
        )
        self.assertEqual(screenshot["miss"], 0)
        self.assertEqual(screenshot["hit"]["provider"], "screenshot")


if __name__ == "__main__":
    unittest.main()
