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
    property bool fullscreenActive: false
    property bool onBattery: false

    readonly property bool settingsReady: settingsService && settingsService.loaded
    // Idle state for the next safe wallpaperengine start (or optional pause), short of lock timeout.
    readonly property int wallpaperIdleSeconds: settingsService
        ? Math.max(15, Number(settingsService.wallpaperEngineIdleSeconds) || 60)
        : 60
    readonly property int wallpaperActiveFps: settingsService
        ? Math.max(1, Math.min(20, Number(settingsService.wallpaperEngineFps) || 15))
        : 15
    readonly property int wallpaperIdleFps: settingsService
        ? Math.max(1, Math.min(wallpaperActiveFps, Number(settingsService.wallpaperEngineIdleFps) || 8))
        : 8
    readonly property bool wallpaperPauseWhenIdle: !!(settingsService && settingsService.wallpaperPauseWhenIdle)
    property bool sessionIdle: false
    readonly property int effectiveWallpaperFps: (sessionIdle || onBattery)
        ? wallpaperIdleFps
        : wallpaperActiveFps
    // --fps is a process-start option. Keep the running budget stable so an idle transition does
    // not tear down and recreate the wallpaper layer on the first pointer event.
    property int appliedWallpaperFps: 15
    readonly property bool liveWallpaperAllowed: !fullscreenActive
        && (!sessionIdle || !wallpaperPauseWhenIdle)

    readonly property bool dynamicDesired: settingsReady
        && settingsService.wallpaperMode === "dynamic"
        && settingsService.effectiveDynamicWallpaperCommand.length > 0
        && liveWallpaperAllowed
    readonly property string dynamicCommand: dynamicDesired
        ? applyWallpaperFpsBudget(resolveDynamicCommand(settingsService.effectiveDynamicWallpaperCommand), appliedWallpaperFps)
        : ""
    readonly property bool externalDesired: settingsReady
        && settingsService.wallpaperMode === "external"
        && liveWallpaperAllowed
    readonly property bool dynamicSuppressesStatic: settingsReady
        && settingsService.wallpaperMode === "dynamic"
        && settingsService.effectiveDynamicWallpaperCommand.length > 0
        && liveWallpaperAllowed
        && !dynamicLaunchFailed
    readonly property bool externalSuppressesStatic: settingsReady
        && settingsService.wallpaperMode === "external"
        && liveWallpaperAllowed
        && (!externalStateLoaded || (externalCommand.length > 0 && !externalLaunchFailed))
    readonly property bool showStaticWallpaper: settingsReady
        && !dynamicActive
        && !dynamicSuppressesStatic
        && !externalSuppressesStatic
    readonly property bool liveWallpaperVisible: settingsReady && !showStaticWallpaper
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

        // Budget from DesktopSettings (active/idle). Hard cap 20 for background.
        var fps = Math.max(1, Math.min(20, Math.round(numberValue(entry.fps, root.wallpaperActiveFps))));
        fps = Math.min(fps, root.appliedWallpaperFps);
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
        // Prefer quieter defaults for compositor cost unless UX explicitly enables them.
        if (entry.disableParallax || entry.disableParallax === undefined)
            parts.push("--disable-parallax");
        if (entry.disableParticles || entry.disableParticles === undefined)
            parts.push("--disable-particles");
        var assetsDir = wallpaperEngineAssetsDir();
        if (assetsDir.length > 0)
            parts.push("--assets-dir", shellQuote(assetsDir));

        return parts.join(" ");
    }

    // Rewrite or inject --fps so idle/active budget always wins over UX JSON.
    function applyWallpaperFpsBudget(command, fps) {
        var text = String(command || "").trim();
        if (text.length === 0)
            return "";
        var n = Math.max(1, Math.min(20, Math.round(Number(fps) || 15)));
        if (/(^|\s)--fps(\s|=)/.test(text))
            return text.replace(/(^|\s)--fps(\s+|=)\d+/g, "$1--fps$2" + String(n));
        return text + " --fps " + String(n);
    }

    function restoreCommandFromUxState() {
        if (!settingsReady || settingsService.wallpaperMode !== "external")
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
        externalCommand = (settingsReady && settingsService.wallpaperMode === "external" && liveWallpaperAllowed)
            ? restoreCommandFromUxState()
            : "";
    }

    function prepareWallpaperProcessStart() {
        var next = Math.max(1, Math.min(20, root.effectiveWallpaperFps));
        if (root.appliedWallpaperFps === next)
            return false;

        root.appliedWallpaperFps = next;
        refreshExternalCommand();
        return true;
    }

    function stopPrestartedWallpaper() {
        Quickshell.execDetached({
            command: [
                "sh",
                "-lc",
                "pidfile=\"$1\"; [ -f \"$pidfile\" ] || exit 0; " +
                "pids=''; " +
                "while IFS= read -r pid; do " +
                "case \"$pid\" in ''|*[!0-9]*) continue ;; esac; " +
                "pids=\"$pids $pid\"; " +
                "kill -TERM -- -\"$pid\" 2>/dev/null || kill \"$pid\" 2>/dev/null || true; " +
                "done < \"$pidfile\"; " +
                "i=0; while [ \"$i\" -lt 20 ]; do alive=0; " +
                "for pid in $pids; do kill -0 \"$pid\" 2>/dev/null && alive=1; done; " +
                "[ \"$alive\" -eq 0 ] && break; sleep 0.05; i=$((i + 1)); done; " +
                "for pid in $pids; do if kill -0 \"$pid\" 2>/dev/null; then " +
                "kill -KILL -- -\"$pid\" 2>/dev/null || kill -KILL \"$pid\" 2>/dev/null || true; " +
                "fi; done; rm -f \"$pidfile\"",
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
        // A prestarted process only bridges shell startup. Start a managed process on the next
        // event-loop turn, then clean up the bridge after the managed surface has settled.
        dynamicActive = false;
        prestartedWallpaperTakeoverTimer.restart();
        return true;
    }

    function releasePrestartedWallpaper() {
        if (!prestartedWallpaperAdopted)
            return;

        prestartedWallpaperTakeoverTimer.stop();
        prestartedWallpaperAdopted = false;
        prestartedWallpaperReleased = true;
        prestartedWallpaperMode = "";
        adoptedDynamicCommand = "";
        stopPrestartedWallpaper();
    }

    function takeOverPrestartedWallpaper() {
        if (!prestartedWallpaperAdopted)
            return;

        prestartedWallpaperAdopted = false;
        prestartedWallpaperReleased = true;
        prestartedWallpaperMode = "";
        adoptedDynamicCommand = "";
        syncDynamicProcess();
        syncExternalProcess();
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

        if (!dynamicProcess.running
                && !prestartedWallpaperAdopted
                && prepareWallpaperProcessStart())
            return;

        if (prestartedWallpaperMode === "dynamic"
                && prestartedWallpaperAdopted
                && adoptedDynamicCommand !== dynamicCommand)
            releasePrestartedWallpaper();

        if (tryAdoptPrestartedWallpaper("dynamic")) {
            dynamicLaunchFailed = false;
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

        if (!externalProcess.running
                && !prestartedWallpaperAdopted
                && prepareWallpaperProcessStart())
            return;

        if (tryAdoptPrestartedWallpaper("external")) {
            externalLaunchFailed = false;
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
    onLiveWallpaperAllowedChanged: {
        if (!root.completed)
            return;
        root.refreshExternalCommand();
        root.syncDynamicProcess();
        root.syncExternalProcess();
    }
    Component.onCompleted: {
        appliedWallpaperFps = effectiveWallpaperFps;
        completed = true;
        prestartedWallpaperFile.reload();
        activeWallpaperFile.reload();
        syncDynamicProcess();
        syncExternalProcess();
    }

    // Separate from lock IdleMonitor: tracks the lower next-start budget or optional pause before
    // the session locks, without restarting a running wallpaper surface.
    IdleMonitor {
        id: wallpaperIdleMonitor
        enabled: root.settingsReady
            && (root.settingsService.wallpaperMode === "dynamic"
                || root.settingsService.wallpaperMode === "external")
        timeout: root.wallpaperIdleSeconds
        respectInhibitors: true
        onIsIdleChanged: root.sessionIdle = isIdle
    }

    Item {
        id: staticLayer
        anchors.fill: parent
        visible: root.settingsReady
        opacity: root.showStaticWallpaper ? 1.0 : 0.0
        clip: true

        Behavior on opacity {
            NumberAnimation {
                duration: 160
                easing.type: Motion.emphasizedDecel
            }
        }

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

    // Live wallpapers render in an independent background-layer process, so
    // they cannot be transformed by staticLayer. A short-lived bottom-layer
    // surface supplies the same launchpad dim above either dynamic backend
    // without restarting or pausing the wallpaper process.
    PanelWindow {
        id: liveWallpaperLaunchpadOverlay
        screen: root.screen
        visible: root.liveWallpaperVisible && (root.launchpadOpen || liveWallpaperDim.opacity > 0.01)
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "tahoe-wallpaper-launchpad-overlay"

        anchors {
            left: true
            right: true
            top: true
            bottom: true
        }

        Rectangle {
            id: liveWallpaperDim
            anchors.fill: parent
            color: "#000000"
            opacity: root.launchpadOpen ? Motion.launchpadWallpaperDim : 0

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
            root.dynamicLaunchFailed = false;
            liveWallpaperReadyTimer.restart();
            root.schedulePrestartedWallpaperCleanup();
        }
        onRunningChanged: {
            if (!running && root.dynamicRestartPending)
                dynamicRestartTimer.restart();
        }
        onExited: function(code, exitStatus) {
            if (root.dynamicDesired && root.dynamicCommand.length > 0 && !root.dynamicRestartPending)
                root.dynamicLaunchFailed = true;
            if (!externalProcess.running) {
                liveWallpaperReadyTimer.stop();
                root.dynamicActive = false;
            }
        }
    }

    Process {
        id: externalProcess
        running: false
        command: ["sh", "-lc", root.externalCommand]
        onStarted: {
            root.externalLaunchFailed = false;
            liveWallpaperReadyTimer.restart();
            root.schedulePrestartedWallpaperCleanup();
        }
        onRunningChanged: {
            if (!running && root.externalRestartPending)
                externalRestartTimer.restart();
        }
        onExited: function(code, exitStatus) {
            if (root.externalDesired && root.externalCommand.length > 0 && !root.externalRestartPending)
                root.externalLaunchFailed = true;
            if (!dynamicProcess.running) {
                liveWallpaperReadyTimer.stop();
                root.dynamicActive = false;
            }
        }
    }

    Timer {
        id: liveWallpaperReadyTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (dynamicProcess.running || externalProcess.running)
                root.dynamicActive = true;
        }
    }

    Timer {
        id: prestartedWallpaperTakeoverTimer
        interval: 50
        repeat: false
        onTriggered: root.takeOverPrestartedWallpaper()
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
