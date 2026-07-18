from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
SYSTEM_STATS = SHELL_ROOT / "services" / "SystemStats.qml"


def extract_function(source: str, name: str) -> str:
    match = re.search(rf"^    function {re.escape(name)}\([^\n]*\) \{{", source, re.M)
    if match is None:
        raise AssertionError(f"missing SystemStats function: {name}")

    depth = 0
    quote = ""
    escaped = False
    line_comment = False
    block_comment = False
    for index in range(match.start(), len(source)):
        char = source[index]
        next_char = source[index + 1] if index + 1 < len(source) else ""
        if line_comment:
            if char == "\n":
                line_comment = False
            continue
        if block_comment:
            if char == "*" and next_char == "/":
                block_comment = False
            continue
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            continue
        if char == "/" and next_char == "/":
            line_comment = True
            continue
        if char == "/" and next_char == "*":
            block_comment = True
            continue
        if char in ('"', "'"):
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[match.start() : index + 1]
    raise AssertionError(f"unterminated SystemStats function: {name}")


class SystemProcessStableRowsTests(unittest.TestCase):
    def test_real_script_model_preserves_pid_delegates(self) -> None:
        local_runner = Path.home() / ".local" / "bin" / "qs"
        runner = str(local_runner) if local_runner.is_file() else shutil.which("qs")
        self.assertIsNotNone(runner, "Tahoe Quickshell runtime is required")

        source = SYSTEM_STATS.read_text(encoding="utf-8")
        functions = "\n\n".join(
            extract_function(source, name)
            for name in (
                "finiteNumber",
                "finiteInt",
                "textValue",
                "sanitizeProcesses",
                "mergeProcessSnapshot",
            )
        )
        qml = """pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

ShellRoot {
    id: root

    QtObject {
        id: processState
        property var entries: []
        property var cache: Object.create(null)
    }

    Component {
        id: processEntryFactory
        QtObject {
            property string modelKey: ""
            property int pid: 0
            property string startTime: ""
            property string user: ""
            property int uid: -1
            property string name: "process"
            property real cpuPercent: 0
            property int memKB: 0
            property string cmdline: "process"
        }
    }

    property int createdCount: 0
    property int destroyedCount: 0
    property var firstDelegate: null
    property var secondDelegate: null
    property var thirdDelegate: null
    property var fourthDelegate: null
    property var firstEntry: null

__FUNCTIONS__

    function sample(pid, startTime, name, cpu, mem, revision) {
        return {
            pid: pid,
            startTime: startTime,
            user: "user" + revision,
            uid: 1000,
            name: name,
            cpuPercent: cpu,
            memKB: mem,
            cmdline: name + " --revision=" + revision
        };
    }

    function delegateForPid(pid) {
        for (var i = 0; i < rows.count; i++) {
            var item = rows.itemAt(i);
            if (item && Number(item.modelData.pid) === Number(pid))
                return item;
        }
        return null;
    }

    Repeater {
        id: rows
        model: ScriptModel {
            objectProp: "modelKey"
            values: processState.entries
        }
        delegate: Item {
            required property var modelData
            Component.onCompleted: root.createdCount += 1
            Component.onDestruction: root.destroyedCount += 1
        }
    }

    Timer {
        id: settleTimer
        interval: 5
        repeat: false
        property var callback: null
        onTriggered: callback()
    }

    function afterModelSettles(callback) {
        settleTimer.callback = callback;
        settleTimer.restart();
    }

    function fail(message) {
        console.error("SYSTEM_PROCESS_STABLE_ROWS_FAIL: " + message);
        Qt.quit();
    }

    function require(condition, message) {
        if (!condition) {
            fail(message);
            return false;
        }
        return true;
    }

    function startProbe() {
        mergeProcessSnapshot([
            sample(101, "10001", "alpha", 30, 1000, 1),
            sample(202, "20002", "beta", 20, 2000, 1)
        ]);
        afterModelSettles(checkInitialRows);
    }

    function checkInitialRows() {
        firstDelegate = delegateForPid(101);
        secondDelegate = delegateForPid(202);
        firstEntry = processState.cache["101:10001"];
        if (!require(rows.count === 2, "initial row count")
                || !require(createdCount === 2 && destroyedCount === 0,
                    "initial delegate lifecycle")
                || !require(firstDelegate !== null && secondDelegate !== null,
                    "initial delegates missing"))
            return;

        mergeProcessSnapshot([
            sample(202, "20002", "beta", 55, 2500, 2),
            sample(101, "10001", "alpha", 10, 1500, 2),
            sample(303, "30003", "gamma", 5, 3000, 1)
        ]);
        afterModelSettles(checkUpdatedRows);
    }

    function checkUpdatedRows() {
        thirdDelegate = delegateForPid(303);
        var first = delegateForPid(101);
        var second = delegateForPid(202);
        if (!require(rows.count === 3, "updated row count")
                || !require(createdCount === 3 && destroyedCount === 0,
                    "stable rows recreated during update")
                || !require(first === firstDelegate && second === secondDelegate,
                    "same-PID delegate identity changed")
                || !require(processState.cache["101:10001"] === firstEntry,
                    "same-PID entry object changed")
                || !require(rows.itemAt(0) === secondDelegate
                    && rows.itemAt(1) === firstDelegate,
                    "surviving delegates did not move in place")
                || !require(second.modelData.cpuPercent === 55
                    && second.modelData.memKB === 2500,
                    "numeric fields did not update in place")
                || !require(second.modelData.cmdline.indexOf("revision=2") >= 0,
                    "text field did not publish latest value")
                || !require(thirdDelegate !== null, "new delegate missing"))
            return;

        mergeProcessSnapshot([
            sample(101, "10001", "alpha", 11, 1600, 3),
            sample(303, "30003", "gamma", 9, 3100, 2),
            sample(404, "40004", "delta", 7, 4000, 1),
            sample(101, "99999", "duplicate", 99, 9999, 9)
        ]);
        afterModelSettles(checkFinalRows);
    }

    function checkFinalRows() {
        if (!require(rows.count === 3, "final row count")
                || !require(createdCount === 4 && destroyedCount === 1,
                    "final merge did not incrementally add/remove")
                || !require(delegateForPid(101) === firstDelegate
                    && delegateForPid(303) === thirdDelegate,
                    "surviving delegates changed on final merge")
                || !require(processState.cache["202:20002"] === undefined,
                    "retired process instance was not pruned")
                || !require(processState.cache["404:40004"] !== undefined,
                    "new PID was not cached")
                || !require(delegateForPid(101).modelData.name === "alpha",
                    "duplicate PID was not ignored"))
            return;
        fourthDelegate = delegateForPid(404);
        mergeProcessSnapshot([
            sample(101, "77777", "alpha-new", 80, 1700, 4),
            sample(303, "30003", "gamma", 8, 3200, 3),
            sample(404, "40004", "delta", 6, 4100, 2)
        ]);
        afterModelSettles(checkPidReuse);
    }

    function checkPidReuse() {
        var reusedPidDelegate = delegateForPid(101);
        if (!require(rows.count === 3, "PID reuse row count")
                || !require(createdCount === 5 && destroyedCount === 2,
                    "PID reuse did not replace exactly one delegate")
                || !require(reusedPidDelegate !== firstDelegate,
                    "new process instance inherited the old PID delegate")
                || !require(delegateForPid(303) === thirdDelegate
                    && delegateForPid(404) === fourthDelegate,
                    "unrelated delegates changed during PID reuse")
                || !require(processState.cache["101:10001"] === undefined
                    && processState.cache["101:77777"] !== undefined,
                    "PID reuse cache identity was not replaced")
                || !require(reusedPidDelegate.modelData.name === "alpha-new",
                    "new process instance fields were not published"))
            return;
        console.log("SYSTEM_PROCESS_STABLE_ROWS_OK");
        Qt.quit();
    }

    Component.onCompleted: startProbe()
}
""".replace("__FUNCTIONS__", functions)

        with tempfile.TemporaryDirectory(prefix="tahoe-system-process-stable-") as temp_dir:
            config = Path(temp_dir) / "shell.qml"
            config.write_text(qml, encoding="utf-8")
            completed = subprocess.run(
                [runner, "-p", str(config)],
                text=True,
                capture_output=True,
                timeout=20,
                check=False,
            )

        output = completed.stdout + completed.stderr
        self.assertEqual(completed.returncode, 0, output)
        self.assertIn("SYSTEM_PROCESS_STABLE_ROWS_OK", output, output)
        self.assertNotIn("SYSTEM_PROCESS_STABLE_ROWS_FAIL", output, output)


if __name__ == "__main__":
    unittest.main()
