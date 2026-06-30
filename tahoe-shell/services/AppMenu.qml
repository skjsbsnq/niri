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
    readonly property var focusedWindow: windowsService ? windowsService.focusedWindow : null
    readonly property string activeTitle: appsService ? appsService.windowAppLabel(focusedWindow) : "桌面"
    readonly property string activeWindowTitle: appsService ? appsService.toplevelLabel(focusedWindow) : "桌面"
    readonly property string activeAppId: focusedWindow ? String(focusedWindow.appId || "") : ""
    readonly property string activePid: focusedWindow && focusedWindow.pid !== undefined && focusedWindow.pid !== null ? String(focusedWindow.pid) : ""
    readonly property string activeWindowId: focusedWindow && focusedWindow.id !== undefined && focusedWindow.id !== null ? String(focusedWindow.id) : ""
    readonly property bool hasFocusedWindow: !!focusedWindow
    readonly property bool nativeMenuAvailable: nativeMenuItems && nativeMenuItems.length > 0
    readonly property string menuTitle: hasFocusedWindow ? "应用菜单" : "桌面"
    readonly property string menuStatusText: nativeMenuAvailable
        ? nativeMenuDetail
        : nativeMenuStatus

    function refresh() {
        if (commandRunner && commandRunner.revision === 0)
            commandRunner.refreshDependencies();

        if (commandRunner && commandRunner.revision > 0 && commandRunner.dependency) {
            var appmenuDependency = commandRunner.dependency("appmenu");
            var appmenuState = appmenuDependency ? String(appmenuDependency.state || "") : "";
            if (appmenuState === "missing" || appmenuState === "broken") {
                probing = false;
                applyProbe(JSON.stringify({
                    "status": "应用菜单不可用",
                    "detail": String(appmenuDependency.detail || "") + (appmenuDependency.action ? "；" + String(appmenuDependency.action) : "")
                }));
                return;
            }
        }

        if (commandRunner && commandRunner.revision > 0 && commandRunner.missingCommands) {
            var missing = commandRunner.missingCommands(["python3", "busctl"]);
            if (missing.length > 0) {
                probing = false;
                applyProbe("{\"status\":\"应用菜单不可用\",\"detail\":\"缺少 " + missing.join(" ") + "\"}");
                return;
            }
        }

        if (!probe.running) {
            probing = true;
            probe.running = true;
        }
    }

    function applyProbe(text) {
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
        command: root.commandRunner && root.commandRunner.appMenuProbeCommand
            ? root.commandRunner.appMenuProbeCommand(root.activeWindowId, root.activePid, root.activeAppId, root.activeWindowTitle)
            : [
                "python3",
                Quickshell.shellPath("services/appmenu_probe.py"),
                root.activeWindowId,
                root.activePid,
                root.activeAppId,
                root.activeWindowTitle
            ]
        stdout: StdioCollector {
            id: probeOut
            onStreamFinished: root.applyProbe(probeOut.text)
        }
        onExited: function(code, exitStatus) {
            root.probing = false;
            if (code !== 0)
                root.applyProbe("{\"status\":\"应用菜单检测失败\",\"detail\":\"helper exit " + String(code) + "\"}");
        }
    }

    Process {
        id: trigger
        running: false
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    onFocusedWindowChanged: root.refresh()

    Component.onCompleted: root.refresh()
}
