from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
SPOTLIGHT = SHELL_ROOT / "components" / "Spotlight.qml"


def extract_function(source: str, name: str) -> str:
    match = re.search(rf"^    function {re.escape(name)}\([^\n]*\) \{{", source, re.M)
    if match is None:
        raise AssertionError(f"missing Spotlight function: {name}")

    depth = 0
    started = False
    for index in range(match.start(), len(source)):
        char = source[index]
        if char == "{":
            depth += 1
            started = True
        elif char == "}":
            depth -= 1
            if started and depth == 0:
                return source[match.start() : index + 1]
    raise AssertionError(f"unterminated Spotlight function: {name}")


class SpotlightStableRowsTests(unittest.TestCase):
    def test_real_script_model_preserves_existing_delegates(self) -> None:
        local_runner = Path.home() / ".local" / "bin" / "qs"
        runner = str(local_runner) if local_runner.is_file() else shutil.which("qs")
        self.assertIsNotNone(runner, "Tahoe Quickshell runtime is required")

        source = SPOTLIGHT.read_text(encoding="utf-8")
        function_names = (
            "resultLabel",
            "resultSubtitle",
            "resultIcon",
            "refreshResults",
            "providerKey",
            "groupTitleForProvider",
            "stableResultKey",
            "currentResultForModelKey",
            "selectableIndexForModelKey",
            "resultFingerprint",
            "sameResultSequence",
            "pruneCache",
            "buildSections",
            "flattenRows",
        )
        functions = "\n\n".join(extract_function(source, name) for name in function_names)
        qml = """pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

ShellRoot {
    id: root

    property string query: ""
    property int resultLimit: 6
    property int selectedIndex: 0
    property var _sectionCache: ({})
    property var _flatRowCache: ({})
    property var sourceResults: []
    property var results: []
    property int resultsForQueryCalls: 0
    readonly property var resultSections: root.buildSections(root.results)
    readonly property var flatRows: root.flattenRows(root.resultSections)
    property int createdCount: 0
    property int destroyedCount: 0
    property int lastActivatedScore: -1
    property var headerDelegate: null
    property var alphaDelegate: null
    property var betaDelegate: null
    property var gammaDelegate: null
    property var alphaRow: null
    property string alphaKey: ""
    property string betaKey: ""
    property string gammaKey: ""

    QtObject {
        id: fakeSearch
        property int providerRevision: 0
        function resultsForQuery(query, limit) {
            root.resultsForQueryCalls += 1;
            return root.sourceResults;
        }
        function resultTitle(result) { return String(result && result.title || ""); }
        function resultSubtitle(result) { return String(result && result.subtitle || ""); }
        function resultIcon(result) { return String(result && result.icon || ""); }
    }

    property var searchService: fakeSearch

    onQueryChanged: {
        selectedIndex = 0;
        root.refreshResults();
    }

    Connections {
        target: root.searchService
        function onProviderRevisionChanged() { root.refreshResults(); }
    }

__FUNCTIONS__

    function makeResult(id, title, score, subtitle, icon) {
        return {
            id: "app:" + id,
            title: title,
            subtitle: subtitle || "Application",
            icon: icon || id + ".png",
            kind: "application",
            provider: "apps",
            score: score,
            app: { id: id },
            activate: function() { root.lastActivatedScore = score; }
        };
    }

    function delegateForKey(key) {
        for (var i = 0; i < rowRepeater.count; i++) {
            var item = rowRepeater.itemAt(i);
            if (item && item.modelData.modelKey === key)
                return item;
        }
        return null;
    }

    Item {
        Repeater {
            id: rowRepeater
            model: ScriptModel {
                id: stableModel
                objectProp: "modelKey"
                values: root.flatRows
            }
            delegate: Item {
                required property var modelData
                objectName: modelData.modelKey
                readonly property var resolvedResult: root.currentResultForModelKey(
                    modelData.modelKey, modelData.result)
                readonly property int resolvedSelectableIndex: root.selectableIndexForModelKey(
                    modelData.modelKey)
                Component.onCompleted: root.createdCount += 1
                Component.onDestruction: root.destroyedCount += 1
            }
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
        console.error("SPOTLIGHT_STABLE_ROWS_FAIL: " + message);
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
        var first = [makeResult("a", "Alpha", 1), makeResult("b", "Beta", 1)];
        alphaKey = stableResultKey(first[0]);
        betaKey = stableResultKey(first[1]);
        sourceResults = first;
        selectedIndex = 2;
        query = "initial";
        afterModelSettles(checkInitialRows);
    }

    function checkInitialRows() {
        if (!require(rowRepeater.count === 3, "initial row count")
                || !require(createdCount === 3, "initial delegate count")
                || !require(destroyedCount === 0, "initial destruction count")
                || !require(selectedIndex === 0, "query did not reset selection")
                || !require(resultsForQueryCalls === 1, "initial query refresh count"))
            return;

        headerDelegate = rowRepeater.itemAt(0);
        alphaDelegate = delegateForKey(alphaKey);
        betaDelegate = delegateForKey(betaKey);
        alphaRow = _flatRowCache[alphaKey];
        if (!require(headerDelegate !== null && alphaDelegate !== null && betaDelegate !== null,
                "initial delegates missing")
                || !require(alphaRow !== null, "initial cached row missing"))
            return;

        sourceResults = [makeResult("a", "Alpha", 2), makeResult("b", "Beta", 2)];
        query = "same";
        afterModelSettles(checkUnchangedRows);
    }

    function checkUnchangedRows() {
        if (!require(createdCount === 3 && destroyedCount === 0, "unchanged rows recreated")
                || !require(rowRepeater.itemAt(0) === headerDelegate, "header identity changed")
                || !require(delegateForKey(alphaKey) === alphaDelegate, "alpha identity changed")
                || !require(delegateForKey(betaKey) === betaDelegate, "beta identity changed")
                || !require(_flatRowCache[alphaKey] === alphaRow, "unchanged row object changed")
                || !require(resultsForQueryCalls === 2, "second query refresh count"))
            return;
        alphaDelegate.resolvedResult.activate();
        if (!require(lastActivatedScore === 2, "latest activation payload was not synchronized"))
            return;

        sourceResults = [
            makeResult("a", "Alpha Prime", 3, "Updated application", "alpha-prime.png"),
            makeResult("b", "Beta", 3)
        ];
        fakeSearch.providerRevision += 1;
        afterModelSettles(checkChangedPayload);
    }

    function checkChangedPayload() {
        if (!require(createdCount === 3 && destroyedCount === 0, "same-key payload recreated delegate")
                || !require(delegateForKey(alphaKey) === alphaDelegate, "same-key delegate identity changed")
                || !require(_flatRowCache[alphaKey] === alphaRow, "changed row wrapper was replaced")
                || !require(alphaDelegate.resolvedResult.title === "Alpha Prime", "title did not update")
                || !require(alphaDelegate.resolvedResult.subtitle === "Updated application",
                    "subtitle did not update")
                || !require(alphaDelegate.resolvedResult.icon === "alpha-prime.png", "icon did not update")
                || !require(resultsForQueryCalls === 3, "provider revision refresh count"))
            return;
        alphaDelegate.resolvedResult.activate();
        if (!require(lastActivatedScore === 3, "changed activation payload did not update"))
            return;

        var third = makeResult("c", "Gamma", 4);
        gammaKey = stableResultKey(third);
        sourceResults = [makeResult("a", "Alpha Prime", 4), makeResult("b", "Beta", 4), third];
        query = "added";
        afterModelSettles(checkAddedRow);
    }

    function checkAddedRow() {
        gammaDelegate = delegateForKey(gammaKey);
        if (!require(createdCount === 4 && destroyedCount === 0, "new row was not incremental")
                || !require(rowRepeater.itemAt(0) === headerDelegate, "header recreated on add/remove")
                || !require(delegateForKey(alphaKey) === alphaDelegate, "surviving result recreated")
                || !require(delegateForKey(betaKey) === betaDelegate, "existing result recreated")
                || !require(gammaDelegate !== null, "new result missing")
                || !require(_flatRowCache[alphaKey] === alphaRow, "cached row changed on add"))
            return;

        sourceResults = [makeResult("b", "Beta", 5), makeResult("a", "Alpha Prime", 5),
            makeResult("c", "Gamma", 5)];
        query = "reordered";
        afterModelSettles(checkReorderedRows);
    }

    function checkReorderedRows() {
        if (!require(createdCount === 4 && destroyedCount === 0, "reorder recreated delegates")
                || !require(rowRepeater.itemAt(0) === headerDelegate, "header recreated on reorder")
                || !require(delegateForKey(alphaKey) === alphaDelegate, "alpha recreated on reorder")
                || !require(delegateForKey(betaKey) === betaDelegate, "beta recreated on reorder")
                || !require(delegateForKey(gammaKey) === gammaDelegate, "gamma recreated on reorder")
                || !require(rowRepeater.itemAt(1) === betaDelegate
                    && rowRepeater.itemAt(2) === alphaDelegate
                    && rowRepeater.itemAt(3) === gammaDelegate, "delegate order is stale")
                || !require(betaDelegate.resolvedSelectableIndex === 0
                    && alphaDelegate.resolvedSelectableIndex === 1
                    && gammaDelegate.resolvedSelectableIndex === 2, "selectable indices are stale")
                || !require(alphaDelegate.resolvedResult.score === 5, "reordered payload is stale")
                || !require(_flatRowCache[alphaKey] === alphaRow, "cached row changed on reorder"))
            return;
        alphaDelegate.resolvedResult.activate();
        if (!require(lastActivatedScore === 5, "reordered activation payload is stale"))
            return;

        sourceResults = [makeResult("a", "Alpha Prime", 6), makeResult("c", "Gamma", 6)];
        query = "narrowed";
        afterModelSettles(checkRemovedRow);
    }

    function checkRemovedRow() {
        if (!require(createdCount === 4 && destroyedCount === 1, "removed row did not destroy one delegate")
                || !require(rowRepeater.itemAt(0) === headerDelegate, "header recreated on remove")
                || !require(delegateForKey(alphaKey) === alphaDelegate, "alpha recreated on remove")
                || !require(delegateForKey(betaKey) === null, "removed result still present")
                || !require(delegateForKey(gammaKey) === gammaDelegate, "gamma recreated on remove")
                || !require(alphaDelegate.resolvedSelectableIndex === 0
                    && gammaDelegate.resolvedSelectableIndex === 1, "narrowed indices are stale")
                || !require(alphaDelegate.resolvedResult.score === 6, "narrowed payload is stale")
                || !require(_flatRowCache[alphaKey] === alphaRow, "cached row changed on remove"))
            return;

        sourceResults = [];
        query = "";
        afterModelSettles(checkPrunedCaches);
    }

    function checkPrunedCaches() {
        if (!require(destroyedCount === 4, "final delegates were not removed")
                || !require(Object.keys(_sectionCache).length === 0, "section cache was not pruned")
                || !require(Object.keys(_flatRowCache).length === 0, "row cache was not pruned"))
            return;
        console.log("SPOTLIGHT_STABLE_ROWS_PASS created=" + createdCount
            + " destroyed=" + destroyedCount);
        Qt.quit();
    }

    Component.onCompleted: Qt.callLater(startProbe)
}
""".replace("__FUNCTIONS__", functions)

        with tempfile.TemporaryDirectory() as tmp:
            qml_test = Path(tmp) / "tst_spotlight_stable_rows.qml"
            qml_test.write_text(qml, encoding="utf-8")
            env = os.environ.copy()
            env.setdefault("QT_QPA_PLATFORM", "offscreen")
            env["QS_DISABLE_FILE_WATCHER"] = "1"
            env["QS_NO_RELOAD_POPUP"] = "1"
            result = subprocess.run(
                [runner, "--no-color", "--path", str(qml_test)],
                cwd=SHELL_ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=30,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("SPOTLIGHT_STABLE_ROWS_PASS created=4 destroyed=4", result.stdout)
        self.assertNotIn("SPOTLIGHT_STABLE_ROWS_FAIL", result.stdout)
        self.assertNotIn("binding loop", result.stdout.lower())


if __name__ == "__main__":
    unittest.main()
