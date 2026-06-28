pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property var windowsService
    property var appsService
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

        trigger.command = [
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
        command: [
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
