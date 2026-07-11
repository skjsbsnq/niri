pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Motion.js" as Motion

PanelWindow {
    id: root

    property var appsService
    property var settingsService
    // T18: Launchpad open drives static wallpaper zoom + dim (content-side only).
    property bool launchpadOpen: false

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
    readonly property bool yieldToDynamicWallpaper: !settingsReady
        || dynamicActive
        || dynamicSuppressesStatic
        || externalSuppressesStatic
    property string externalCommand: ""
    property bool dynamicActive: false
    property bool dynamicRestartPending: false
    property bool externalRestartPending: false
    property bool dynamicLaunchFailed: false
    property bool externalLaunchFailed: false
    property bool externalStateLoaded: false
    property bool completed: false
    property bool prestartedWallpaperAdopted: false
    property bool prestartedWallpaperReleased: false
    property string prestartedWallpaperMode: ""
    property string adoptedDynamicCommand: ""
    readonly property string prestartedWallpaperPidFile: Quickshell.stateDir + "/wallpaper-prestart.pids"

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "tahoe-wallpaper"
    color: yieldToDynamicWallpaper ? "transparent" : "#1c1d20"

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

        // Default 15fps; cap 20 for background layer (session: 30fps wallpaper
        // ~25% CPU + full-screen damage that keeps glass sampling hot).
        var fps = Math.max(1, Math.min(20, Math.round(numberValue(entry.fps, 15))));
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

    function stopPrestartedWallpaper() {
        Quickshell.execDetached({
            command: [
                "sh",
                "-lc",
                "pidfile=\"$1\"; [ -f \"$pidfile\" ] || exit 0; " +
                "while IFS= read -r pid; do " +
                "case \"$pid\" in ''|*[!0-9]*) continue ;; esac; " +
                "kill -TERM -- -\"$pid\" 2>/dev/null || kill \"$pid\" 2>/dev/null || true; " +
                "done < \"$pidfile\"; rm -f \"$pidfile\"",
                "sh",
                prestartedWallpaperPidFile
            ],
            workingDirectory: ""
        });
    }

    function schedulePrestartedWallpaperCleanup() {
        prestartedWallpaperCleanupTimer.restart();
    }

    function hasPrestartedWallpaper() {
        var text = "";
        try {
            text = prestartedWallpaperFile.text();
        } catch (e) {
            return false;
        }

        var lines = String(text || "").split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            if (/^[0-9]+$/.test(String(lines[i]).trim()))
                return true;
        }

        return false;
    }

    function tryAdoptPrestartedWallpaper(mode) {
        if (prestartedWallpaperAdopted)
            return prestartedWallpaperMode === mode;

        if (prestartedWallpaperReleased)
            return false;

        if (!hasPrestartedWallpaper())
            return false;

        prestartedWallpaperAdopted = true;
        prestartedWallpaperMode = mode;
        adoptedDynamicCommand = mode === "dynamic" ? dynamicCommand : "";
        dynamicActive = true;
        return true;
    }

    function releasePrestartedWallpaper() {
        if (!prestartedWallpaperAdopted)
            return;

        prestartedWallpaperAdopted = false;
        prestartedWallpaperReleased = true;
        prestartedWallpaperMode = "";
        adoptedDynamicCommand = "";
        stopPrestartedWallpaper();
    }

    function syncDynamicProcess() {
        if (!completed)
            return;

        if (!dynamicDesired || dynamicCommand.length === 0) {
            if (prestartedWallpaperMode === "dynamic")
                releasePrestartedWallpaper();
            dynamicRestartPending = false;
            dynamicLaunchFailed = false;
            dynamicProcess.running = false;
            if (!externalProcess.running && !prestartedWallpaperAdopted)
                dynamicActive = false;
            return;
        }

        if (prestartedWallpaperMode === "dynamic"
                && prestartedWallpaperAdopted
                && adoptedDynamicCommand !== dynamicCommand)
            releasePrestartedWallpaper();

        if (tryAdoptPrestartedWallpaper("dynamic")) {
            dynamicLaunchFailed = false;
            dynamicActive = true;
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
            if (prestartedWallpaperMode === "external")
                releasePrestartedWallpaper();
            externalRestartPending = false;
            externalLaunchFailed = false;
            externalProcess.running = false;
            if (!dynamicProcess.running && !prestartedWallpaperAdopted)
                dynamicActive = false;
            return;
        }

        if (tryAdoptPrestartedWallpaper("external")) {
            externalLaunchFailed = false;
            dynamicActive = true;
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
        prestartedWallpaperFile.reload();
        activeWallpaperFile.reload();
        syncDynamicProcess();
        syncExternalProcess();
    }

    Item {
        id: staticLayer
        anchors.fill: parent
        visible: root.showStaticWallpaper
        clip: true

        readonly property real zoom: root.launchpadOpen ? Motion.launchpadWallpaperScale : 1.0
        readonly property real dimOpacity: root.launchpadOpen ? Motion.launchpadWallpaperDim : 0.0

        Image {
            id: staticImage
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            source: root.staticWallpaperSource()
            fillMode: Image.PreserveAspectCrop
            smooth: true
            asynchronous: true
            scale: staticLayer.zoom
            transformOrigin: Item.Center

            Behavior on scale {
                NumberAnimation {
                    duration: Motion.launchpadWallpaperDuration(root.settingsService)
                    easing.type: Motion.emphasizedDecel
                }
            }
        }

        // Base vignette (existing subtle darken) + Launchpad extra dim.
        Rectangle {
            anchors.fill: parent
            color: "#18000000"
        }

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: staticLayer.dimOpacity

            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.launchpadWallpaperDuration(root.settingsService)
                    easing.type: Motion.emphasizedDecel
                }
            }
        }
    }

    Process {
        id: dynamicProcess
        running: false
        command: ["sh", "-lc", root.dynamicCommand]
        onStarted: {
            root.dynamicActive = true;
            root.dynamicLaunchFailed = false;
            root.schedulePrestartedWallpaperCleanup();
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
            root.schedulePrestartedWallpaperCleanup();
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

    Timer {
        id: prestartedWallpaperCleanupTimer
        interval: 2500
        repeat: false
        onTriggered: root.stopPrestartedWallpaper()
    }

    FileView {
        id: prestartedWallpaperFile
        path: root.prestartedWallpaperPidFile
        blockLoading: true
        printErrors: false
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
