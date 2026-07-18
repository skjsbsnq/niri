from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
CONTROL_CENTER = SHELL_ROOT / "components" / "ControlCenter.qml"


def extract_function(source: str, name: str) -> str:
    match = re.search(rf"^    function {re.escape(name)}\([^\n]*\) \{{", source, re.M)
    if match is None:
        raise AssertionError(f"missing ControlCenter function: {name}")

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
    raise AssertionError(f"unterminated ControlCenter function: {name}")


class ControlCenterStableModuleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = CONTROL_CENTER.read_text(encoding="utf-8")

    def test_module_list_uses_stable_models_and_full_transitions(self) -> None:
        source = self.source
        for marker in (
            "function bluetoothModuleRows(entries)",
            "function bluetoothModuleRowForKey(rows, key)",
            "id: wifiModuleModel",
            'objectProp: "name"',
            "id: bluetoothModuleModel",
            'objectProp: "modelKey"',
            "values: mp.bluetoothRows",
            "model: mp.isWifi ? wifiModuleModel",
        ):
            self.assertIn(marker, source)

        module_list = source.split("id: moduleList", 1)[1].split("delegate: Item {", 1)[0]
        for marker in (
            "visible: mp.showList",
            "add: Transition",
            "remove: Transition",
            "move: Transition",
            "displaced: Transition",
            "Motion.fadeFast(root.settingsService)",
            "Motion.elementMove(root.settingsService)",
        ):
            self.assertIn(marker, module_list)
        self.assertIn("property bool listRetiring", source)
        self.assertIn("previous > 0 && (mp.isWifi || mp.isBluetooth)", source)
        self.assertIn("Motion.fadeFast(root.settingsService) + 16", source)
        self.assertIn("visible: !mp.showList", source)

        delegate = source.split("delegate: Item {", 1)[1].split(
            "// Footer actions for wifi rescan / bt scan.", 1
        )[0]
        self.assertIn("readonly property var stableKey", delegate)
        self.assertIn("root.bluetoothModuleRowForKey(mp.bluetoothRows, row.stableKey)", delegate)
        self.assertIn("readonly property var entry", delegate)
        self.assertNotIn("connectBluetoothDevice(row.modelData)", delegate)
        self.assertNotIn("pairBluetoothDevice(row.modelData)", delegate)

    def test_psk_expansion_and_module_hover_are_animated(self) -> None:
        source = self.source
        psk = re.search(
            r"Layout\.preferredHeight: row\.showPsk \? 36 : 0"
            r"(?P<body>[\s\S]*?)\n\s+RowLayout \{",
            source,
        )
        self.assertIsNotNone(psk)
        assert psk
        psk_body = psk.group("body")
        for marker in (
            "opacity: row.showPsk ? 1 : 0",
            "row.showPsk || opacity > 0.01 || Layout.preferredHeight > 0.5",
            "Behavior on Layout.preferredHeight",
            "Motion.elementResize(root.settingsService)",
            "Behavior on opacity",
            "Motion.fadeFast(root.settingsService)",
        ):
            self.assertIn(marker, psk_body)
        self.assertNotIn("SpringAnimation", psk_body)

        row_frame = source.split("id: rowFrame", 1)[1].split("id: rowContent", 1)[0]
        self.assertIn("root.tileFillHover", row_frame)
        self.assertIn("root.tileFillActive", row_frame)
        self.assertIn("Behavior on color", row_frame)
        self.assertIn("ColorAnimation", row_frame)
        self.assertIn("Motion.fadeFast(root.settingsService)", row_frame)

    def test_real_script_model_keeps_bluetooth_rows_current_after_moves(self) -> None:
        local_runner = Path.home() / ".local" / "bin" / "qs"
        runner = str(local_runner) if local_runner.is_file() else shutil.which("qs")
        self.assertIsNotNone(runner, "Tahoe Quickshell runtime is required")

        functions = "\n\n".join(
            extract_function(self.source, name)
            for name in ("bluetoothModuleRows", "bluetoothModuleRowForKey")
        )
        qml = """pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

ShellRoot {
    id: root

    QtObject { id: keylessDevice }

    property var sourceEntries: []
    property var bluetoothRows: bluetoothModuleRows(sourceEntries)
    property int createdCount: 0
    property int destroyedCount: 0
    property var alphaDelegate: null
    property var betaDelegate: null
    property var gammaDelegate: null
    property var keylessDelegate: null

__FUNCTIONS__

    function sample(name, address, dbusPath, connected, battery, device) {
        return {
            device: device || null,
            name: name,
            address: address,
            dbusPath: dbusPath,
            icon: "audio-card",
            connected: connected,
            paired: !connected,
            bonded: !connected,
            pairing: false,
            trusted: false,
            blocked: false,
            wakeAllowed: false,
            batteryAvailable: true,
            batteryPercent: battery,
            state: connected ? 1 : 0,
            stateChanging: false
        };
    }

    function delegateForKey(key) {
        for (var i = 0; i < rows.count; i++) {
            var item = rows.itemAt(i);
            if (item && item.stableKey === key)
                return item;
        }
        return null;
    }

    Repeater {
        id: rows
        model: ScriptModel {
            objectProp: "modelKey"
            values: root.bluetoothRows
        }
        delegate: Item {
            required property var modelData
            readonly property var stableKey: modelData.modelKey
            readonly property var currentEntry:
                root.bluetoothModuleRowForKey(root.bluetoothRows, stableKey) || modelData
            Component.onCompleted: root.createdCount += 1
            Component.onDestruction: root.destroyedCount += 1
        }
    }

    Timer {
        id: settleTimer
        interval: 5
        repeat: true
        property var predicate: null
        property var callback: null
        property double deadline: 0
        onTriggered: {
            if (predicate && predicate()) {
                stop();
                callback();
            } else if (Date.now() >= deadline) {
                stop();
                root.fail("model settle timeout");
            }
        }
    }

    function afterModelSettles(predicate, callback) {
        settleTimer.predicate = predicate;
        settleTimer.callback = callback;
        settleTimer.deadline = Date.now() + 1000;
        settleTimer.restart();
    }

    function fail(message) {
        console.error("CONTROL_CENTER_STABLE_MODULES_FAIL: " + message);
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
        sourceEntries = [
            sample("Beta", "", "/device/beta", true, 60, null),
            sample("Alpha", "AA:AA", "", false, 20, null)
        ];
        afterModelSettles(function() {
            return rows.count === 2 && createdCount === 2;
        }, checkInitialRows);
    }

    function checkInitialRows() {
        betaDelegate = delegateForKey("bluetooth-path:/device/beta");
        alphaDelegate = delegateForKey("bluetooth-address:AA:AA");
        if (!require(rows.count === 2, "initial row count")
                || !require(createdCount === 2 && destroyedCount === 0,
                    "initial delegate lifecycle")
                || !require(alphaDelegate !== null && betaDelegate !== null,
                    "initial delegates missing"))
            return;

        sourceEntries = [
            sample("Alpha", "AA:AA", "", true, 85, null),
            sample("Beta", "", "/device/beta", false, 55, null),
            sample("Gamma", "CC:CC", "", false, 40, null)
        ];
        afterModelSettles(function() {
            return rows.count === 3 && createdCount === 3;
        }, checkMovedRows);
    }

    function checkMovedRows() {
        gammaDelegate = delegateForKey("bluetooth-address:CC:CC");
        if (!require(rows.count === 3, "moved row count")
                || !require(createdCount === 3 && destroyedCount === 0,
                    "move recreated surviving delegates")
                || !require(delegateForKey("bluetooth-address:AA:AA") === alphaDelegate
                    && delegateForKey("bluetooth-path:/device/beta") === betaDelegate,
                    "stable-key delegate identity changed")
                || !require(rows.itemAt(0) === alphaDelegate
                    && rows.itemAt(1) === betaDelegate,
                    "delegates did not move to the new order")
                || !require(alphaDelegate.currentEntry.connected
                    && alphaDelegate.currentEntry.batteryPercent === 85,
                    "moved delegate did not resolve latest map")
                || !require(!betaDelegate.currentEntry.connected
                    && betaDelegate.currentEntry.batteryPercent === 55,
                    "second moved delegate kept stale fields")
                || !require(gammaDelegate !== null, "new delegate missing"))
            return;

        sourceEntries = [
            sample("Gamma", "CC:CC", "", true, 42, null),
            sample("Keyless", "", "", false, 10, keylessDevice),
            sample("Alpha", "AA:AA", "", false, 80, null),
            sample("Alpha duplicate", "AA:AA", "", true, 99, null)
        ];
        afterModelSettles(function() {
            return rows.count === 3
                && createdCount === 4
                && destroyedCount === 1
                && delegateForKey(keylessDevice) !== null;
        }, checkFinalRows);
    }

    function checkFinalRows() {
        keylessDelegate = delegateForKey(keylessDevice);
        if (!require(rows.count === 3, "final row count or duplicate pruning")
                || !require(createdCount === 4 && destroyedCount === 1,
                    "final add/remove lifecycle")
                || !require(delegateForKey("bluetooth-address:AA:AA") === alphaDelegate
                    && delegateForKey("bluetooth-address:CC:CC") === gammaDelegate,
                    "surviving delegates changed on final update")
                || !require(delegateForKey("bluetooth-path:/device/beta") === null,
                    "removed delegate still present")
                || !require(keylessDelegate !== null,
                    "device-object fallback key was not usable")
                || !require(gammaDelegate.currentEntry.connected
                    && gammaDelegate.currentEntry.batteryPercent === 42,
                    "survivor did not expose latest fields"))
            return;
        console.log("CONTROL_CENTER_STABLE_MODULES_OK");
        Qt.quit();
    }

    Component.onCompleted: startProbe()
}
""".replace("__FUNCTIONS__", functions)

        with tempfile.TemporaryDirectory(prefix="tahoe-control-center-modules-") as temp_dir:
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
        self.assertIn("CONTROL_CENTER_STABLE_MODULES_OK", output, output)
        self.assertNotIn("CONTROL_CENTER_STABLE_MODULES_FAIL", output, output)


if __name__ == "__main__":
    unittest.main()
