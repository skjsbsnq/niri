pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    property var appsService
    property var settingsService

    readonly property bool settingsReady: settingsService && settingsService.loaded
    readonly property bool dynamicDesired: settingsReady
        && settingsService.wallpaperMode === "dynamic"
        && settingsService.effectiveDynamicWallpaperCommand.length > 0
    readonly property string dynamicCommand: dynamicDesired
        ? resolveDynamicCommand(settingsService.effectiveDynamicWallpaperCommand)
        : ""
    readonly property bool externalDesired: settingsReady
        && settingsService.wallpaperMode === "external"
    readonly property bool dynamicSuppressesStatic: dynamicDesired && !dynamicLaunchFailed
    readonly property bool externalSuppressesStatic: externalDesired
        && (!externalStateLoaded || (externalCommand.length > 0 && !externalLaunchFailed))
    readonly property bool showStaticWallpaper: settingsReady
        && !dynamicActive
        && !dynamicSuppressesStatic
        && !externalSuppressesStatic
    property string externalCommand: ""
    property bool dynamicActive: false
    property bool dynamicRestartPending: false
    property bool externalRestartPending: false
    property bool dynamicLaunchFailed: false
    property bool externalLaunchFailed: false
    property bool externalStateLoaded: false
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

    function numberValue(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
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

    function wallpaperEngineAssetsDir() {
        var home = settingsService ? settingsService.homeDir : Quickshell.env("HOME");
        home = home === undefined || home === null ? "" : String(home);
        if (home.length === 0)
            return "";
        return home + "/.local/share/Steam/steamapps/common/wallpaper_engine/assets";
    }

    function commandForUxWallpaper(entry, fallbackScreen) {
        if (!entry)
            return "";

        var backgroundId = String(entry.backgroundId || entry.id || "").trim();
        if (backgroundId.length === 0)
            return "";

        var screen = String(fallbackScreen || entry.screen || "").trim();
        if (screen.length === 0)
            return "";

        var parts = [
            "linux-wallpaperengine",
            "--screen-root", shellQuote(screen),
            "--bg", shellQuote(backgroundId),
            "--layer", "background"
        ];

        var scaling = String(entry.scaling || "").trim();
        if (scaling.length > 0)
            parts.push("--scaling", shellQuote(scaling));

        var clamp = String(entry.clamp || "").trim();
        if (clamp.length > 0)
            parts.push("--clamp", shellQuote(clamp));

        var fps = Math.max(1, Math.round(numberValue(entry.fps, 30)));
        parts.push("--fps", String(fps));

        if (entry.silent) {
            parts.push("--silent");
        } else {
            var volume = Math.max(0, Math.round(numberValue(entry.volume, 15)));
            parts.push("--volume", String(volume));
        }

        if (entry.noAutomute)
            parts.push("--noautomute");
        if (entry.noAudioProcessing)
            parts.push("--no-audio-processing");
        if (entry.disableMouse)
            parts.push("--disable-mouse");
        if (entry.disableParallax)
            parts.push("--disable-parallax");
        if (entry.disableParticles)
            parts.push("--disable-particles");
        if (entry.noFullscreenPause)
            parts.push("--no-fullscreen-pause");

        var assetsDir = wallpaperEngineAssetsDir();
        if (assetsDir.length > 0)
            parts.push("--assets-dir", shellQuote(assetsDir));

        return parts.join(" ");
    }

    function restoreCommandFromUxState() {
        if (!externalDesired)
            return "";

        var text = "";
        try {
            text = activeWallpaperFile.text();
        } catch (e) {
            return "";
        }

        if (String(text || "").trim().length === 0)
            return "";

        try {
            var state = JSON.parse(text);
            var active = state && state.activeWallpapers ? state.activeWallpapers : {};
            var output = screenName();
            var entry = active[output] || null;
            if (!entry) {
                var keys = Object.keys(active);
                if (keys.length === 1)
                    entry = active[keys[0]];
            }
            return commandForUxWallpaper(entry, output);
        } catch (e) {
            return "";
        }
    }

    function refreshExternalCommand() {
        externalCommand = externalDesired ? restoreCommandFromUxState() : "";
    }

    function syncDynamicProcess() {
        if (!completed)
            return;

        if (!dynamicDesired || dynamicCommand.length === 0) {
            dynamicRestartPending = false;
            dynamicLaunchFailed = false;
            dynamicProcess.running = false;
            if (!externalProcess.running)
                dynamicActive = false;
            return;
        }

        if (dynamicProcess.running) {
            dynamicRestartPending = true;
            dynamicProcess.running = false;
            return;
        }

        dynamicActive = false;
        dynamicLaunchFailed = false;
        dynamicProcess.running = true;
    }

    function syncExternalProcess() {
        if (!completed)
            return;

        if (!externalDesired || externalCommand.length === 0) {
            externalRestartPending = false;
            externalLaunchFailed = false;
            externalProcess.running = false;
            if (!dynamicProcess.running)
                dynamicActive = false;
            return;
        }

        if (externalProcess.running) {
            externalRestartPending = true;
            externalProcess.running = false;
            return;
        }

        dynamicActive = false;
        externalLaunchFailed = false;
        externalProcess.running = true;
    }

    onDynamicDesiredChanged: {
        dynamicLaunchFailed = false;
        syncDynamicProcess();
    }
    onDynamicCommandChanged: {
        dynamicLaunchFailed = false;
        syncDynamicProcess();
    }
    onExternalDesiredChanged: {
        externalLaunchFailed = false;
        refreshExternalCommand();
        syncExternalProcess();
    }
    onExternalCommandChanged: {
        externalLaunchFailed = false;
        syncExternalProcess();
    }
    Component.onCompleted: {
        completed = true;
        activeWallpaperFile.reload();
        syncDynamicProcess();
        syncExternalProcess();
    }

    Image {
        anchors.fill: parent
        source: root.staticWallpaperSource()
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
        visible: root.showStaticWallpaper
    }

    Rectangle {
        anchors.fill: parent
        color: "#18000000"
        visible: root.showStaticWallpaper
    }

    Process {
        id: dynamicProcess
        running: false
        command: ["sh", "-lc", root.dynamicCommand]
        onStarted: {
            root.dynamicActive = true;
            root.dynamicLaunchFailed = false;
        }
        onRunningChanged: {
            if (!running && root.dynamicRestartPending)
                dynamicRestartTimer.restart();
        }
        onExited: function(code, exitStatus) {
            if (root.dynamicDesired && root.dynamicCommand.length > 0 && !root.dynamicRestartPending)
                root.dynamicLaunchFailed = true;
            if (!externalProcess.running)
                root.dynamicActive = false;
        }
    }

    Process {
        id: externalProcess
        running: false
        command: ["sh", "-lc", root.externalCommand]
        onStarted: {
            root.dynamicActive = true;
            root.externalLaunchFailed = false;
        }
        onRunningChanged: {
            if (!running && root.externalRestartPending)
                externalRestartTimer.restart();
        }
        onExited: function(code, exitStatus) {
            if (root.externalDesired && root.externalCommand.length > 0 && !root.externalRestartPending)
                root.externalLaunchFailed = true;
            if (!dynamicProcess.running)
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

    Timer {
        id: externalRestartTimer
        interval: 120
        repeat: false
        onTriggered: {
            root.externalRestartPending = false;
            if (root.externalDesired && root.externalCommand.length > 0)
                externalProcess.running = true;
        }
    }

    FileView {
        id: activeWallpaperFile
        path: root.settingsService && root.settingsService.homeDir.length > 0
            ? root.settingsService.homeDir + "/.config/Linux Wallpaper Engine/active-wallpapers.json"
            : ""
        blockLoading: true
        printErrors: false
        onLoaded: {
            root.externalStateLoaded = true;
            root.refreshExternalCommand();
            root.syncExternalProcess();
        }
        onLoadFailed: {
            root.externalStateLoaded = true;
            root.refreshExternalCommand();
            root.syncExternalProcess();
        }
    }
}
