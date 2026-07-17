from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
CONTROLS = SHELL_ROOT / "services" / "Controls.qml"
WIFI_POPUP = SHELL_ROOT / "components" / "WifiPopup.qml"


def extract_function(source: str, name: str) -> str:
    match = re.search(rf"^    function {re.escape(name)}\([^\n]*\) \{{", source, re.M)
    if match is None:
        raise AssertionError(f"missing Controls function: {name}")

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
    raise AssertionError(f"unterminated Controls function: {name}")


class WifiStableRowsTests(unittest.TestCase):
    def test_real_script_model_preserves_ssid_delegates(self) -> None:
        local_runner = Path.home() / ".local" / "bin" / "qs"
        runner = str(local_runner) if local_runner.is_file() else shutil.which("qs")
        self.assertIsNotNone(runner, "Tahoe Quickshell runtime is required")

        controls = CONTROLS.read_text(encoding="utf-8")
        merge_function = extract_function(controls, "mergeWifiNetworkCandidates")
        qml = """pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

ShellRoot {
    id: root

    QtObject {
        id: wifiNetworkState
        property var entries: []
        property var cache: Object.create(null)
    }

    Component {
        id: wifiNetworkEntryFactory
        QtObject {
            property var network
            property string name: ""
            property int signalPercent: 0
            property var security
            property bool secured: false
            property bool pskSupported: false
            property bool known: false
            property bool connected: false
            property bool stateChanging: false
        }
    }

    property int createdCount: 0
    property int destroyedCount: 0
    property var alphaDelegate: null
    property var betaDelegate: null
    property var gammaDelegate: null
    property var alphaEntry: null

__MERGE_FUNCTION__

    function candidate(name, signalPercent, connected, known, revision) {
        return {
            network: { revision: revision },
            name: name,
            signalPercent: signalPercent,
            security: 1,
            secured: revision !== 3,
            pskSupported: revision !== 3,
            known: known,
            connected: connected,
            stateChanging: revision === 2
        };
    }

    function delegateForName(name) {
        for (var i = 0; i < rows.count; i++) {
            var item = rows.itemAt(i);
            if (item && item.modelData.name === name)
                return item;
        }
        return null;
    }

    Repeater {
        id: rows
        model: ScriptModel {
            objectProp: "name"
            values: wifiNetworkState.entries
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
        console.error("WIFI_STABLE_ROWS_FAIL: " + message);
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
        mergeWifiNetworkCandidates([
            candidate("Alpha", 30, false, false, 1),
            candidate("Beta", 50, false, false, 1)
        ], false);
        afterModelSettles(checkInitialRows);
    }

    function checkInitialRows() {
        alphaDelegate = delegateForName("Alpha");
        betaDelegate = delegateForName("Beta");
        alphaEntry = wifiNetworkState.cache["Alpha"];
        if (!require(rows.count === 2, "initial row count")
                || !require(createdCount === 2 && destroyedCount === 0,
                    "initial delegate lifecycle")
                || !require(rows.itemAt(0).modelData.name === "Beta",
                    "initial signal sort")
                || !require(alphaDelegate !== null && betaDelegate !== null,
                    "initial delegates missing"))
            return;

        mergeWifiNetworkCandidates([
            candidate("Alpha", 80, true, false, 2),
            candidate("Beta", 55, false, true, 2),
            candidate("Gamma", 99, false, false, 1)
        ], false);
        afterModelSettles(checkUpdatedRows);
    }

    function checkUpdatedRows() {
        gammaDelegate = delegateForName("Gamma");
        var alpha = delegateForName("Alpha");
        var beta = delegateForName("Beta");
        if (!require(rows.count === 3, "updated row count")
                || !require(createdCount === 3 && destroyedCount === 0,
                    "stable rows recreated during update")
                || !require(alpha === alphaDelegate && beta === betaDelegate,
                    "same-SSID delegate identity changed")
                || !require(wifiNetworkState.cache["Alpha"] === alphaEntry,
                    "same-SSID entry object changed")
                || !require(rows.itemAt(0) === alphaDelegate,
                    "connected row did not move in place")
                || !require(rows.itemAt(1) === betaDelegate
                    && rows.itemAt(2) === gammaDelegate,
                    "known network did not outrank stronger unknown network")
                || !require(alpha.modelData.signalPercent === 80,
                    "signal field did not update in place")
                || !require(alpha.modelData.network.revision === 2,
                    "latest backend network was not published")
                || !require(alpha.modelData.stateChanging,
                    "stateChanging field did not update")
                || !require(gammaDelegate !== null, "new delegate missing"))
            return;

        mergeWifiNetworkCandidates([], true);
        afterModelSettles(checkRetainedRows);
    }

    function checkRetainedRows() {
        if (!require(rows.count === 3, "scan toggle emptied retained rows")
                || !require(createdCount === 3 && destroyedCount === 0,
                    "scan toggle rebuilt retained rows")
                || !require(delegateForName("Alpha") === alphaDelegate
                    && delegateForName("Beta") === betaDelegate
                    && delegateForName("Gamma") === gammaDelegate,
                    "retained delegate identity changed"))
            return;

        mergeWifiNetworkCandidates([
            candidate("Alpha", 79, true, false, 3),
            candidate("Gamma", 25, false, false, 2),
            candidate("Delta", 25, false, false, 1),
            candidate("__proto__", 10, false, false, 1)
        ], false);
        afterModelSettles(checkFinalRows);
    }

    function checkFinalRows() {
        if (!require(rows.count === 4, "final row count")
                || !require(createdCount === 5 && destroyedCount === 1,
                    "final merge did not incrementally add/remove")
                || !require(delegateForName("Alpha") === alphaDelegate
                    && delegateForName("Gamma") === gammaDelegate,
                    "surviving delegates changed on final merge")
                || !require(wifiNetworkState.cache["Beta"] === undefined,
                    "removed SSID was not pruned")
                || !require(wifiNetworkState.cache["__proto__"] !== undefined,
                    "prototype-like SSID collided with cache")
                || !require(rows.itemAt(1).modelData.name === "Delta"
                    && rows.itemAt(2) === gammaDelegate,
                    "equal-signal SSIDs were not name-sorted")
                || !require(!alphaDelegate.modelData.secured
                    && !alphaDelegate.modelData.pskSupported
                    && !alphaDelegate.modelData.stateChanging,
                    "security/state fields did not publish latest values"))
            return;
        console.log("WIFI_STABLE_ROWS_OK");
        Qt.quit();
    }

    Component.onCompleted: startProbe()
}
""".replace("__MERGE_FUNCTION__", merge_function)

        with tempfile.TemporaryDirectory(prefix="tahoe-wifi-stable-") as temp_dir:
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
        self.assertIn("WIFI_STABLE_ROWS_OK", output, output)
        self.assertNotIn("WIFI_STABLE_ROWS_FAIL", output, output)

    def test_popup_uses_stable_model_and_eased_transitions(self) -> None:
        popup = WIFI_POPUP.read_text(encoding="utf-8")
        self.assertIn('objectProp: "name"', popup)
        self.assertIn("values: root.networks", popup)
        self.assertIn("add: Transition", popup)
        self.assertIn("remove: Transition", popup)
        self.assertIn("displaced: Transition", popup)
        self.assertIn("Motion.fadeFast(root.settingsService)", popup)
        self.assertIn("Motion.elementMove(root.settingsService)", popup)
        self.assertGreaterEqual(popup.count("Motion.elementResize(root.settingsService)"), 3)
        self.assertIn("Behavior on height", popup)
        self.assertIn("Behavior on Layout.preferredHeight", popup)
        self.assertNotIn("SpringAnimation", popup)

    def test_scan_placeholder_and_incremental_service_contract(self) -> None:
        controls = CONTROLS.read_text(encoding="utf-8")
        popup = WIFI_POPUP.read_text(encoding="utf-8")
        for marker in (
            "readonly property var wifiNetworks: wifiNetworkState.entries",
            "readonly property bool wifiScanning: wifiNetworkState.scanning",
            "function wifiNetworkCandidates()",
            "function mergeWifiNetworkCandidates(candidates, retainMissing)",
            "root.mergeWifiNetworkCandidates(candidates, root.wifiScanning)",
            "function onValuesChanged() { root.handleWifiNetworkChange(); }",
            "wifiScanFallbackTimer.restart()",
            "root.wifiDevice === scanDevice",
        ):
            self.assertIn(marker, controls)
        self.assertIn("root.wifiDevice.networks.values : []", controls)
        self.assertIn("Object.create(null)", controls)
        refresh_timer = re.search(
            r"id: wifiRefreshTimer(?P<body>[\s\S]{0,180})onTriggered:", controls
        )
        self.assertIsNotNone(refresh_timer)
        assert refresh_timer
        self.assertIn("interval: 30000", refresh_timer.group("body"))
        self.assertIn('root.scanning ? "正在扫描…" : "未发现网络"', popup)

    def test_psk_expansion_animates_height_and_opacity(self) -> None:
        popup = WIFI_POPUP.read_text(encoding="utf-8")
        psk = re.search(
            r"Layout\.preferredHeight: row\.expanded \? 42 : 0(?P<body>[\s\S]*?)RowLayout \{",
            popup,
        )
        self.assertIsNotNone(psk)
        assert psk
        block = psk.group("body")
        self.assertIn("opacity: row.expanded ? 1 : 0", block)
        self.assertIn("row.expanded || opacity > 0.01", block)
        self.assertIn("Behavior on Layout.preferredHeight", block)
        self.assertIn("Behavior on opacity", block)
        self.assertNotIn("SpringAnimation", block)


if __name__ == "__main__":
    unittest.main()
