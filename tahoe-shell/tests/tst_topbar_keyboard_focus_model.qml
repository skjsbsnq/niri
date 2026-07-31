pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// T-29 / F-10: the TopBar keyboard focus model. The bar is click-focusable;
// Tab/Backtab/arrows walk the visible interactive entries in visual order and
// Return/Enter/Space activate the current one.
//
// Phase A runs with no services (only the always-visible entries exist) and
// verifies traversal, wrap-around and activation. Phase B injects fakes so the
// service-gated entries (app menu, clipboard, fan, battery, wifi, island chip,
// workspaces) participate in the chain in visual order.
ShellRoot {
    id: probe

    property string panelSource: ""
    property var panel: null
    property int stage: 0
    property int sidebarActivations: 0
    property int chipClicks: 0
    property int chipButton: -1
    property var workspaceActivations: []

    QtObject {
        id: settings
        property string motionProfile: "balanced"
        property string accentColor: "blue"
        property bool dynamicIslandEnabled: true
        property bool dynamicIslandHideTopbarTime: false
    }

    QtObject {
        id: niriFake
        property var visibleWindowsets: [
            { canActivate: true, active: true, urgent: false },
            { canActivate: true, active: false, urgent: false }
        ]
        property var focusedWindow: null
        property var activeToplevel: null
        function workspaceLabel(modelData, index) { return "ws"; }
        function activateWorkspace(modelData) { probe.workspaceActivations.push(modelData); }
    }

    QtObject {
        id: islandFake
        property string presentation: "resting_time"
        property string fallbackTimeText: "12:34"
        function handleChipClick(button, screenName) {
            probe.chipClicks += 1;
            probe.chipButton = button;
        }
        function requestHoverExpand() {}
        function requestHoverCollapse() {}
    }

    QtObject {
        id: appMenuFake
    }

    QtObject {
        id: clipboardFake
    }

    QtObject {
        id: fanFake
    }

    QtObject {
        id: batteryFake
        property bool available: true
        property int roundedPercentage: 50
        property bool onBattery: false
    }

    QtObject {
        id: controlsFake
        property bool wifiEnabled: true
    }

    Timer {
        id: stepTimer
        interval: 20
        repeat: false
        onTriggered: probe.advance()
    }

    function require(condition, message) {
        if (condition)
            return true;
        console.error("TOPBAR_KEYBOARD_FAIL: " + message);
        cleanup();
        Qt.exit(1);
        return false;
    }

    function schedule(nextStage, delayMs) {
        stage = nextStage;
        stepTimer.interval = Math.max(1, delayMs);
        stepTimer.restart();
    }

    function namesOf(entries) {
        var names = [];
        for (var i = 0; i < entries.length; i++) {
            // Tray icons only exist when the live session has tray items;
            // their position is asserted structurally, not by count.
            var name = entries[i] && entries[i].objectName ? entries[i].objectName : "";
            if (name !== "topbarEntryTrayItem")
                names.push(name);
        }
        return names;
    }

    function arraysEqual(a, b) {
        if (a.length !== b.length)
            return false;
        for (var i = 0; i < a.length; i++) {
            if (a[i] !== b[i])
                return false;
        }
        return true;
    }

    function currentName() {
        return panel.keyboardCurrent ? panel.keyboardCurrent.objectName : "";
    }

    function walkTo(targetName) {
        // Step forward until the current entry is the target; fail if we wrap
        // around without finding it.
        var guard = 0;
        while (guard++ < 40) {
            if (currentName() === targetName)
                return true;
            panel.keyboardStep(1);
        }
        return false;
    }

    function cleanup() {
        stepTimer.stop();
        if (panel) {
            panel.destroy();
            panel = null;
        }
    }

    function finish() {
        console.log("TOPBAR_KEYBOARD_OK");
        cleanup();
        Qt.quit();
    }

    function advance() {
        if (stage === 0) {
            if (!require(panelSource.length > 0, "panelSource was not injected"))
                return;
            var component = Qt.createComponent("file://" + panelSource);
            if (!require(component.status === Component.Ready,
                    "TopBar compile: " + component.errorString()))
                return;
            // No services: only the always-visible entries exist (chip is
            // not interactive because the Overlay owns resting by default).
            panel = component.createObject(null, {});
            if (!require(panel !== null, "TopBar creation"))
                return;
            if (!require(panel.focusable === true,
                    "TopBar must be click-focusable for keyboard traversal, got focusable="
                    + panel.focusable))
                return;
            schedule(1, 150);
            return;
        }

        // ---- Phase A: no services → only always-visible entries ----
        if (stage === 1) {
            var base = namesOf(panel.keyboardEntryList());
            var expectedBase = [
                "topbarEntryNiriMenu",
                "topbarEntryLeftSidebar",
                "topbarEntryNotifications",
                "topbarEntrySpotlight",
                "topbarEntryStatus"
            ];
            if (!require(arraysEqual(base, expectedBase),
                    "phase A entry order: expected " + JSON.stringify(expectedBase)
                    + " got " + JSON.stringify(base)))
                return;
            // Start from scratch and walk the full chain. The live session may
            // have real tray icons in the chain, so traversal is checked by
            // walking forward to each expected entry in order (tray items are
            // stepped over, never landed on).
            panel.keyboardCurrent = null;
            panel.keyboardStep(1);
            if (!require(currentName() === expectedBase[0],
                    "first Tab lands on '" + expectedBase[0] + "', got '"
                    + currentName() + "'"))
                return;
            for (var i = 1; i < expectedBase.length; i++) {
                if (!require(walkTo(expectedBase[i]),
                        "Tab walk " + i + ": could not reach '" + expectedBase[i]
                        + "', stuck at '" + currentName() + "'"))
                    return;
            }
            // Tab wraps forward from the last entry back to the first.
            if (!require(walkTo(expectedBase[0]),
                    "Tab wraps forward to first entry, got '" + currentName() + "'"))
                return;
            // Backtab wraps backward from the first entry to the last fixed
            // entry (status; tray icons never become the tail of the chain).
            panel.keyboardStep(-1);
            if (!require(currentName() === "topbarEntryStatus",
                    "Backtab wraps backward to status, got '" + currentName() + "'"))
                return;
            // Activation through the shared signal path.
            panel.toggleLeftSidebar.connect(function() { probe.sidebarActivations += 1; });
            if (!require(walkTo("topbarEntryLeftSidebar"), "could not walk to left sidebar"))
                return;
            panel.activateKeyboardCurrent();
            if (!require(probe.sidebarActivations === 1,
                    "Enter on left sidebar fires toggleLeftSidebar, got "
                    + probe.sidebarActivations + " activations"))
                return;
            schedule(2, 80);
            return;
        }

        // ---- Phase B: service-gated entries join the chain ----
        if (stage === 2) {
            panel.destroy();
            panel = null;
            var componentB = Qt.createComponent("file://" + panelSource);
            if (!require(componentB.status === Component.Ready,
                    "TopBar phase B compile: " + componentB.errorString()))
                return;
            panel = componentB.createObject(null, {
                "settingsService": settings,
                "niriService": niriFake,
                "dynamicIslandService": islandFake,
                "appMenuService": appMenuFake,
                "clipboardService": clipboardFake,
                "fanService": fanFake,
                "batteryService": batteryFake,
                "controlsService": controlsFake
            });
            if (!require(panel !== null, "TopBar phase B creation"))
                return;
            schedule(3, 150);
            return;
        }

        if (stage === 3) {
            var full = namesOf(panel.keyboardEntryList());
            var expectedFull = [
                "topbarEntryNiriMenu",
                "topbarEntryLeftSidebar",
                "topbarEntryAppMenu",
                "topbarEntryWorkspace",
                "topbarEntryWorkspace",
                "topbarEntryIslandChip",
                "topbarEntryNotifications",
                "topbarEntryClipboard",
                "topbarEntryFan",
                "topbarEntryBattery",
                "topbarEntryWifi",
                "topbarEntrySpotlight",
                "topbarEntryStatus"
            ];
            if (!require(arraysEqual(full, expectedFull),
                    "phase B entry order: expected " + JSON.stringify(expectedFull)
                    + " got " + JSON.stringify(full)))
                return;
            // Workspace activation through the shared service path.
            if (!require(walkTo("topbarEntryWorkspace"),
                    "could not walk to first workspace"))
                return;
            panel.activateKeyboardCurrent();
            if (!require(probe.workspaceActivations.length === 1,
                    "Enter on workspace activates it, got "
                    + probe.workspaceActivations.length + " activations"))
                return;
            // Island chip activation uses the left-click path.
            if (!require(walkTo("topbarEntryIslandChip"),
                    "could not walk to island chip"))
                return;
            panel.activateKeyboardCurrent();
            if (!require(probe.chipClicks === 1 && probe.chipButton === Qt.LeftButton,
                    "Enter on island chip clicks it with left button, got clicks="
                    + probe.chipClicks + " button=" + probe.chipButton))
                return;
            // Mouse engagement seeds the next Tab.
            panel.keyboardCurrent = null;
            panel.engageKeyboardEntry(panel.keyboardEntryList()[0]);
            if (!require(panel.keyboardCurrent !== null
                    && currentName() === "topbarEntryNiriMenu",
                    "engageKeyboardEntry seeds keyboardCurrent"))
                return;
            panel.keyboardStep(1);
            if (!require(currentName() === "topbarEntryLeftSidebar",
                    "Tab after engage continues from engaged entry, got '"
                    + currentName() + "'"))
                return;
            finish();
            return;
        }
    }

    Component.onCompleted: schedule(0, 40)
}
