pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property var windowsService
    property var appsService
    property var commandRunner
    property bool registrarAvailable: false
    property string registrarOwner: ""
    property bool probing: false
    property var nativeMenuItems: []
    property string nativeMenuService: ""
    property string nativeMenuPath: ""
    property string nativeMenuStatus: "尚未检测"
    property string nativeMenuDetail: ""
    // Monotonic request generation for the single probe pipeline.
    // probeGeneration: latest refresh intent; probeInFlightGeneration: running Process.
    // probePending: newest intent arrived while Process was still running.
    // probeStdout* caches the collector output for the in-flight generation only.
    property int probeGeneration: 0
    property int probeInFlightGeneration: 0
    property string probeTargetIdentity: ""
    property string probeInFlightIdentity: ""
    property string menuOwnerIdentity: ""
    property bool probePending: false
    property string probeStdoutText: ""
    property int probeStdoutGeneration: 0
    readonly property var focusedWindow: windowsService ? windowsService.focusedWindow : null
    readonly property string activeTitle: appsService ? appsService.windowAppLabel(focusedWindow) : "桌面"
    readonly property string activeWindowTitle: appsService ? appsService.toplevelLabel(focusedWindow) : "桌面"
    readonly property string activeAppId: focusedWindow ? String(focusedWindow.appId || "") : ""
    readonly property string activePid: focusedWindow && focusedWindow.pid !== undefined && focusedWindow.pid !== null ? String(focusedWindow.pid) : ""
    readonly property string activeWindowId: focusedWindow && focusedWindow.id !== undefined && focusedWindow.id !== null ? String(focusedWindow.id) : ""
    readonly property bool hasFocusedWindow: !!focusedWindow
    readonly property bool nativeMenuAvailable: menuOwnerIdentity === probeTargetIdentity
        && nativeMenuItems && nativeMenuItems.length > 0
    readonly property string menuTitle: hasFocusedWindow ? "应用菜单" : "桌面"
    readonly property string menuStatusText: nativeMenuAvailable
        ? nativeMenuDetail
        : nativeMenuStatus

    function refresh() {
        var targetIdentity = JSON.stringify([activeWindowId, activePid, activeAppId]);
        var targetChanged = targetIdentity !== probeTargetIdentity;
        if (targetChanged) {
            probeTargetIdentity = targetIdentity;
            if (menuOwnerIdentity !== targetIdentity) {
                menuOwnerIdentity = "";
                nativeMenuService = "";
                nativeMenuPath = "";
                nativeMenuItems = [];
                nativeMenuStatus = "正在检测";
                nativeMenuDetail = "";
            }
        }

        if (commandRunner && commandRunner.revision === 0)
            commandRunner.refreshDependencies();

        if (commandRunner && commandRunner.revision > 0 && commandRunner.dependency) {
            var appmenuDependency = commandRunner.dependency("appmenu");
            var appmenuState = appmenuDependency ? String(appmenuDependency.state || "") : "";
            if (appmenuState === "missing" || appmenuState === "broken") {
                // Bump generation so any in-flight probe cannot overwrite this sync result.
                probeGeneration += 1;
                probePending = false;
                probing = false;
                if (probe.running)
                    probe.running = false;
                applyProbe(JSON.stringify({
                    "status": "应用菜单不可用",
                    "detail": String(appmenuDependency.detail || "") + (appmenuDependency.action ? "；" + String(appmenuDependency.action) : "")
                }), probeGeneration, targetIdentity);
                return;
            }
        }

        if (commandRunner && commandRunner.revision > 0 && commandRunner.missingCommands) {
            var missing = commandRunner.missingCommands(["python3", "busctl"]);
            if (missing.length > 0) {
                probeGeneration += 1;
                probePending = false;
                probing = false;
                if (probe.running)
                    probe.running = false;
                applyProbe("{\"status\":\"应用菜单不可用\",\"detail\":\"缺少 " + missing.join(" ") + "\"}", probeGeneration, targetIdentity);
                return;
            }
        }

        if (probe.running) {
            // The in-flight result is still current for the same stable target.  Coalesce
            // periodic/manual refreshes so a slow probe cannot be starved indefinitely.
            if (targetChanged) {
                probeGeneration += 1;
                probePending = true;
            }
            return;
        }

        probeGeneration += 1;
        startProbe(probeGeneration, targetIdentity);
    }

    function startProbe(generation, identity) {
        // Never start a superseded generation; keep pending so a later exit can re-run latest.
        if (Number(generation) !== Number(probeGeneration))
            return;
        if (String(identity) !== probeTargetIdentity)
            return;
        if (probe.running) {
            probePending = true;
            return;
        }

        probePending = false;
        probeInFlightGeneration = generation;
        probeInFlightIdentity = identity;
        probeStdoutText = "";
        probeStdoutGeneration = 0;
        // Capture command args at start so a later focus change cannot rebind identity mid-flight.
        probe.command = root.commandRunner && root.commandRunner.appMenuProbeCommand
            ? root.commandRunner.appMenuProbeCommand(
                root.activeWindowId,
                root.activePid,
                root.activeAppId,
                root.activeWindowTitle
            )
            : [
                "python3",
                Quickshell.shellPath("services/appmenu_probe.py"),
                root.activeWindowId,
                root.activePid,
                root.activeAppId,
                root.activeWindowTitle
            ];
        probing = true;
        probe.running = true;
    }

    function applyProbe(text, generation, identity) {
        // Generation is mandatory: missing or stale generations never write menu state.
        if (generation === undefined || generation === null)
            return;
        if (Number(generation) !== Number(probeGeneration))
            return;
        if (String(identity) !== probeTargetIdentity)
            return;

        var fallback = {
            "registrarAvailable": false,
            "registrarOwner": "",
            "menuService": "",
            "menuPath": "",
            "items": [],
            "status": "应用菜单检测失败",
            "detail": ""
        };
        var parsed = fallback;

        try {
            var raw = String(text || "").trim();
            if (raw.length > 0)
                parsed = JSON.parse(raw);
        } catch (error) {
            parsed = fallback;
            parsed.detail = String(error);
        }

        registrarOwner = String(parsed.registrarOwner || "");
        registrarAvailable = !!parsed.registrarAvailable || registrarOwner.length > 0;
        nativeMenuService = String(parsed.menuService || "");
        nativeMenuPath = String(parsed.menuPath || "");
        nativeMenuItems = Array.isArray(parsed.items) ? parsed.items : [];
        nativeMenuStatus = String(parsed.status || "");
        nativeMenuDetail = String(parsed.detail || "");
        menuOwnerIdentity = identity;
    }

    function schedulePendingProbe() {
        // Defer restart until after Process exit handling settles (same pattern as Search.qml).
        Qt.callLater(function() {
            if (!root.probePending)
                return;
            if (probe.running)
                return;
            root.startProbe(root.probeGeneration, root.probeTargetIdentity);
        });
    }

    function finishProbe(code, generation, identity, text) {
        // Apply success/error with the generation frozen at exit entry.
        var gen = Number(generation);
        // onRunningChanged is the failed-to-start fallback.  Ignore duplicate or
        // obsolete completion signals after onExited has already consumed this run.
        if (gen <= 0 || gen !== Number(probeInFlightGeneration))
            return;
        probeInFlightGeneration = 0;
        probeInFlightIdentity = "";
        if (code !== 0)
            applyProbe("{\"status\":\"应用菜单检测失败\",\"detail\":\"helper exit " + String(code) + "\"}", gen, identity);
        else
            applyProbe(text, gen, identity);

        // Only the latest generation may clear loading; keep probing while a newer intent is pending.
        if (gen === Number(probeGeneration) && !probePending)
            probing = false;

        // Unified pending re-run for both stale and latest exits (deferred; never re-enter Process here).
        if (probePending)
            schedulePendingProbe();
    }

    function activateNativeItem(item) {
        if (!item || !nativeMenuAvailable || nativeMenuService.length === 0 || nativeMenuPath.length === 0)
            return;
        if (item.kind !== "item" || !item.enabled)
            return;
        if (trigger.running)
            return;

        if (commandRunner && commandRunner.revision > 0 && commandRunner.missingCommands) {
            var missing = commandRunner.missingCommands(["busctl"]);
            if (missing.length > 0) {
                nativeMenuStatus = "应用菜单动作不可用";
                nativeMenuDetail = "缺少 " + missing.join(" ");
                return;
            }
        }

        trigger.command = commandRunner && commandRunner.appMenuTriggerCommand
            ? commandRunner.appMenuTriggerCommand(nativeMenuService, nativeMenuPath, item.id)
            : [
                "busctl",
                "--user",
                "call",
                nativeMenuService,
                nativeMenuPath,
                "com.canonical.dbusmenu",
                "Event",
                "isvu",
                String(item.id),
                "clicked",
                "i",
                "0",
                "0"
            ];
        trigger.running = true;
    }

    function pinFocusedApp() {
        if (appsService && focusedWindow)
            appsService.pinWindow(focusedWindow);
    }

    function minimizeFocusedWindow() {
        if (windowsService && focusedWindow)
            windowsService.minimize(focusedWindow);
    }

    function activateFocusedWindow() {
        if (windowsService && focusedWindow)
            windowsService.activate(focusedWindow);
    }

    Process {
        id: probe
        running: false
        // command is assigned in startProbe() so identity is frozen for this generation.
        command: []
        stdout: StdioCollector {
            id: probeOut
            onStreamFinished: {
                // Cache stdout against the in-flight generation before exit reordering.
                root.probeStdoutText = probeOut.text;
                root.probeStdoutGeneration = root.probeInFlightGeneration;
            }
        }
        onExited: function(code, exitStatus) {
            // Freeze identity and payload at exit entry; never start the next probe in this stack.
            var gen = root.probeInFlightGeneration;
            var identity = root.probeInFlightIdentity;
            var text = root.probeStdoutGeneration === gen
                ? root.probeStdoutText
                : probeOut.text;
            root.finishProbe(code, gen, identity, text);
        }
        onRunningChanged: {
            // QuickShell Process does not emit exited when QProcess fails to start.
            // In that path runningChanged is the only completion signal.
            if (!probe.running && root.probeInFlightGeneration > 0)
                root.finishProbe(-1, root.probeInFlightGeneration, root.probeInFlightIdentity, "");
        }
    }

    Process {
        id: trigger
        running: false
    }

    // Recovery-only probe: catch registrar appear/disappear or dependency
    // recovery while idle. Must not be a high-rate authority path (old 5s
    // poll ≈ 720 Python/D-Bus starts per idle hour). Primary drivers remain
    // focused-window identity, menu open (AppMenuPopup), and initial load —
    // all still call the single Task-03 refresh()/probe generation pipeline.
    Timer {
        id: healthRecoveryTimer
        interval: 300000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    onFocusedWindowChanged: root.refresh()

    Component.onCompleted: root.refresh()
}
