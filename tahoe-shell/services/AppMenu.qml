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
    readonly property var focusedWindow: windowsService ? windowsService.focusedWindow : null
    readonly property string activeTitle: appsService ? appsService.toplevelLabel(focusedWindow) : "桌面"
    readonly property string activeAppId: focusedWindow ? String(focusedWindow.appId || "") : ""
    readonly property bool hasFocusedWindow: !!focusedWindow
    readonly property string menuTitle: hasFocusedWindow ? "应用菜单" : "桌面"

    function refresh() {
        if (!probe.running)
            probe.running = true;
    }

    function applyProbe(text) {
        var owner = String(text || "").trim();
        registrarOwner = owner;
        registrarAvailable = owner.length > 0;
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
            "sh",
            "-lc",
            "busctl --user list 2>/dev/null | awk '$1 == \"com.canonical.AppMenu.Registrar\" { print $1; exit }'"
        ]
        stdout: StdioCollector {
            id: probeOut
            onStreamFinished: root.applyProbe(probeOut.text)
        }
        onExited: function(code, exitStatus) {
            if (code !== 0)
                root.applyProbe("");
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
