pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    property var appsService
    property var settingsService

    readonly property bool dynamicDesired: settingsService
        && settingsService.wallpaperMode === "dynamic"
        && settingsService.effectiveDynamicWallpaperCommand.length > 0
    readonly property string dynamicCommand: dynamicDesired
        ? resolveDynamicCommand(settingsService.effectiveDynamicWallpaperCommand)
        : ""
    property bool dynamicActive: false
    property bool dynamicRestartPending: false
    property bool completed: false

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "tahoe-wallpaper"
    color: dynamicActive ? "transparent" : "#1c1d20"

    function screenName() {
        if (!root.screen)
            return "";
        return String(root.screen.name || "").trim();
    }

    function shellQuote(value) {
        return "'" + String(value || "").replace(/'/g, "'\\''") + "'";
    }

    function resolveDynamicCommand(command) {
        var output = screenName();
        var quotedOutput = shellQuote(output);
        var resolved = String(command || "");
        resolved = resolved.replace(/\{output\}/g, quotedOutput);
        resolved = resolved.replace(/\{screen\}/g, quotedOutput);
        return resolved;
    }

    function staticWallpaperSource() {
        var configured = settingsService ? settingsService.effectiveStaticWallpaper : "";
        if (configured.length > 0)
            return configured;
        return appsService ? appsService.wallpaper : "";
    }

    function syncDynamicProcess() {
        if (!completed)
            return;

        if (!dynamicDesired || dynamicCommand.length === 0) {
            dynamicRestartPending = false;
            dynamicProcess.running = false;
            dynamicActive = false;
            return;
        }

        if (dynamicProcess.running) {
            dynamicRestartPending = true;
            dynamicProcess.running = false;
            return;
        }

        dynamicActive = false;
        dynamicProcess.running = true;
    }

    onDynamicDesiredChanged: syncDynamicProcess()
    onDynamicCommandChanged: syncDynamicProcess()
    Component.onCompleted: {
        completed = true;
        syncDynamicProcess();
    }

    Image {
        anchors.fill: parent
        source: root.staticWallpaperSource()
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
        visible: !root.dynamicActive
    }

    Rectangle {
        anchors.fill: parent
        color: "#18000000"
        visible: !root.dynamicActive
    }

    Process {
        id: dynamicProcess
        running: false
        command: ["sh", "-lc", root.dynamicCommand]
        onStarted: {
            root.dynamicActive = true;
        }
        onRunningChanged: {
            if (!running && root.dynamicRestartPending)
                dynamicRestartTimer.restart();
        }
        onExited: function(code, exitStatus) {
            root.dynamicActive = false;
        }
    }

    Timer {
        id: dynamicRestartTimer
        interval: 120
        repeat: false
        onTriggered: {
            root.dynamicRestartPending = false;
            if (root.dynamicDesired && root.dynamicCommand.length > 0)
                dynamicProcess.running = true;
        }
    }
}
