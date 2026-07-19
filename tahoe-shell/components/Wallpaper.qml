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
    readonly property bool nestedSession: String(Quickshell.env("TAHOE_NESTED_SESSION") || "") === "1"

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
    readonly property bool wallpaperPauseWhenFullscreen: !settingsService
        || settingsService.wallpaperPauseWhenFullscreen === undefined
        || !!settingsService.wallpaperPauseWhenFullscreen
    property bool sessionIdle: false
    readonly property int effectiveWallpaperFps: (sessionIdle || onBattery)
        ? wallpaperIdleFps
        : wallpaperActiveFps
    // --fps is a process-start option. Keep the running budget stable so an idle transition does
    // not tear down and recreate the wallpaper layer on the first pointer event.
    property int appliedWallpaperFps: 15
    // Fullscreen does not own the live process lifecycle. Wallpaper Engine handles the pause in-place
    // when enabled, while the renderer and its layer surface remain alive either way.
    readonly property bool liveWallpaperAllowed: !sessionIdle || !wallpaperPauseWhenIdle

    readonly property bool dynamicDesired: settingsReady
        && !nestedSession
        && settingsService.wallpaperMode === "dynamic"
        && settingsService.effectiveDynamicWallpaperCommand.length > 0
        && liveWallpaperAllowed
    readonly property string dynamicCommand: dynamicDesired
        ? preparedDynamicCommand(settingsService.effectiveDynamicWallpaperCommand)
        : ""
    readonly property bool externalDesired: settingsReady
        && !nestedSession
        && settingsService.wallpaperMode === "external"
        && liveWallpaperAllowed
    readonly property bool dynamicSuppressesStatic: dynamicDesired
        && !dynamicLaunchFailed
    readonly property bool externalSuppressesStatic: externalDesired
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
    property bool restartCoverVisible: false
    property bool prestartStateLoaded: false
    property bool prestartedWallpaperStopPending: false
    property var prestartedWallpaperRecord: null
    property bool prestartedWallpaperAdopted: false
    property bool prestartedWallpaperReleased: false
    property string prestartedWallpaperMode: ""
    property string adoptedWallpaperCommand: ""
    readonly property string prestartedWallpaperRecordDir: Quickshell.stateDir + "/wallpaper-prestart"
    readonly property string prestartedWallpaperRecordPath: nestedSession ? ""
        : prestartedWallpaperRecordDir + "/" + safeOutputName(screenName()) + ".json"
    readonly property string lockWallpaperCaptureDir: Quickshell.stateDir + "/lock-wallpaper"
    readonly property int availableScreenCount: Quickshell.screens
        ? Quickshell.screens.length : 0

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

    function safeOutputName(value) {
        var safe = String(value || "").trim().replace(/[^A-Za-z0-9_.-]/g, "_");
        return safe.length > 0 ? safe : "default";
    }

    function lockWallpaperCapturePath(output) {
        return lockWallpaperCaptureDir + "/" + safeOutputName(output) + ".png";
    }

    function isDirectWallpaperEngineCommand(command) {
        var text = String(command || "").trim();
        var match = text.match(/^("[^"]+"|'[^']+'|[^\s]+)/);
        if (!match)
            return false;
        var executable = String(match[1]);
        if ((executable.charAt(0) === "'" && executable.charAt(executable.length - 1) === "'")
                || (executable.charAt(0) === "\"" && executable.charAt(executable.length - 1) === "\""))
            executable = executable.substring(1, executable.length - 1);
        var slash = executable.lastIndexOf("/");
        if (slash >= 0)
            executable = executable.substring(slash + 1);
        return executable === "linux-wallpaperengine";
    }

    function applyWallpaperFullscreenPause(command, pauseWhenFullscreen) {
        var text = String(command || "").trim();
        if (!isDirectWallpaperEngineCommand(text))
            return text;
        text = text.replace(/(^|\s)--no-fullscreen-pause(?=\s|$)/g, "$1");
        text = text.replace(/\s+/g, " ").trim();
        return pauseWhenFullscreen ? text : text + " --no-fullscreen-pause";
    }

    function applyLockWallpaperCapture(command, output) {
        var text = String(command || "").trim();
        if (!isDirectWallpaperEngineCommand(text))
            return text;
        text = text.replace(/(^|\s)--screenshot(?:\s+|=)(?:"[^"]*"|'[^']*'|[^\s]+)/g, "$1");
        text = text.replace(/(^|\s)--screenshot-delay(?:\s+|=)\d+/g, "$1");
        text = text.replace(/\s+/g, " ").trim();
        return text
            + " --screenshot " + shellQuote(lockWallpaperCapturePath(output))
            + " --screenshot-delay 5";
    }

    function wrapWallpaperCommand(command) {
        var text = String(command || "").trim();
        if (text.length === 0)
            return "";
        return "mkdir -p " + shellQuote(lockWallpaperCaptureDir) + " && exec " + text;
    }

    function preparedDynamicCommand(command) {
        var output = screenName();
        var text = resolveDynamicCommand(command);
        text = applyWallpaperFullscreenPause(text, wallpaperPauseWhenFullscreen);
        text = applyLockWallpaperCapture(text, output);
        text = applyWallpaperFpsBudget(text, appliedWallpaperFps);
        return wrapWallpaperCommand(text);
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
            "--screen-root", screen,
            "--bg", backgroundId,
            "--layer", "background"
        ];

        var scaling = String(entry.scaling || "").trim();
        if (scaling.length > 0)
            parts.push("--scaling", scaling);

        var clamp = String(entry.clamp || "").trim();
        if (clamp.length > 0)
            parts.push("--clamp", clamp);

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
        if (!root.wallpaperPauseWhenFullscreen)
            parts.push("--no-fullscreen-pause");
        parts.push(
            "--screenshot", lockWallpaperCapturePath(screen),
            "--screenshot-delay", "5"
        );
        var assetsDir = wallpaperEngineAssetsDir();
        if (assetsDir.length > 0)
            parts.push("--assets-dir", assetsDir);

        return wrapWallpaperCommand(parts.map(function(part) {
            return shellQuote(part);
        }).join(" "));
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
            if (!entry && root.availableScreenCount === 1) {
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

    function showRestartCover() {
        restartCoverVisible = true;
    }

    function prestartedRecordProcessMatches(record) {
        if (!record)
            return false;
        var pid = Number(record.pid);
        var expectedStart = String(record.startTime || "");
        if (!isFinite(pid) || pid <= 0 || !/^[0-9]+$/.test(expectedStart))
            return false;
        prestartedWallpaperProcessFile.path = "/proc/" + String(Math.round(pid)) + "/stat";
        try {
            prestartedWallpaperProcessFile.reload();
            prestartedWallpaperProcessFile.waitForJob();
            var text = String(prestartedWallpaperProcessFile.text() || "").trim();
            var close = text.lastIndexOf(")");
            if (close < 0)
                return false;
            var fields = text.substring(close + 1).trim().split(/\s+/);
            return fields.length > 19 && String(fields[19]) === expectedStart;
        } catch (e) {
            return false;
        }
    }

    function stopPrestartedWallpaper() {
        var record = prestartedWallpaperRecord;
        if (!record)
            return;

        var pid = Number(record.pid);
        if (!isFinite(pid) || pid <= 0 || !prestartedRecordProcessMatches(record)) {
            Quickshell.execDetached({
                command: ["rm", "-f", "--", prestartedWallpaperRecordPath],
                workingDirectory: ""
            });
            return;
        }

        Quickshell.execDetached({
            command: [
                "sh",
                "-lc",
                "pid=\"$1\"; record=\"$2\"; " +
                "kill -TERM -- -\"$pid\" 2>/dev/null || kill -TERM \"$pid\" 2>/dev/null || true; " +
                "i=0; while [ \"$i\" -lt 20 ] && kill -0 \"$pid\" 2>/dev/null; do " +
                "sleep 0.05; i=$((i + 1)); done; " +
                "if kill -0 \"$pid\" 2>/dev/null; then " +
                "kill -KILL -- -\"$pid\" 2>/dev/null || kill -KILL \"$pid\" 2>/dev/null || true; fi; " +
                "rm -f -- \"$record\"",
                "sh",
                String(Math.round(pid)),
                prestartedWallpaperRecordPath
            ],
            workingDirectory: ""
        });
    }

    function reloadPrestartedWallpaperState() {
        var wasAdopted = prestartedWallpaperAdopted;
        var wasStopPending = prestartedWallpaperStopPending;
        var shouldResync = false;
        prestartStateLoaded = false;
        prestartedWallpaperRecord = null;
        try {
            prestartedWallpaperFile.reload();
            prestartedWallpaperFile.waitForJob();
            var parsed = JSON.parse(prestartedWallpaperFile.text());
            if (parsed && Number(parsed.pid) > 0
                    && String(parsed.output || "") === screenName()
                    && prestartedRecordProcessMatches(parsed)) {
                prestartedWallpaperRecord = parsed;
            } else if (parsed && prestartedWallpaperRecordPath.length > 0) {
                Quickshell.execDetached({
                    command: ["rm", "-f", "--", prestartedWallpaperRecordPath],
                    workingDirectory: ""
                });
            }
        } catch (e) {
            prestartedWallpaperRecord = null;
        }
        prestartStateLoaded = true;

        if (prestartedWallpaperStopPending && !prestartedWallpaperRecord) {
            prestartedWallpaperStopPending = false;
            shouldResync = wasStopPending;
        }

        if (wasAdopted && !prestartedRecordMatches(prestartedWallpaperMode)) {
            prestartedWallpaperAdopted = false;
            prestartedWallpaperMode = "";
            adoptedWallpaperCommand = "";
            root.dynamicActive = false;
            shouldResync = true;
        }
        if (root.completed && !prestartedWallpaperStopPending)
            prestartStopTimer.stop();
        if (root.completed && shouldResync) {
            Qt.callLater(function() {
                root.syncDynamicProcess();
                root.syncExternalProcess();
            });
        }
    }

    function prestartedRecordMatches(mode) {
        if (!prestartStateLoaded || !prestartedWallpaperRecord)
            return false;
        if (String(prestartedWallpaperRecord.mode || "") !== mode)
            return false;
        if (String(prestartedWallpaperRecord.output || "") !== screenName())
            return false;
        var expected = mode === "dynamic" ? dynamicCommand : externalCommand;
        return expected.length > 0
            && String(prestartedWallpaperRecord.command || "") === expected;
    }

    function tryAdoptPrestartedWallpaper(mode) {
        if (prestartedWallpaperAdopted)
            return prestartedWallpaperMode === mode;

        if (prestartedWallpaperReleased || !prestartStateLoaded
                || !prestartedRecordMatches(mode))
            return false;

        prestartedWallpaperAdopted = true;
        prestartedWallpaperMode = mode;
        adoptedWallpaperCommand = mode === "dynamic" ? dynamicCommand : externalCommand;
        // The serialized launcher started this exact renderer before Quickshell. Keep that
        // surface for the session instead of creating a second background surface to take over.
        dynamicActive = true;
        restartCoverVisible = true;
        prestartedWallpaperReadyTimer.restart();
        return true;
    }

    function releasePrestartedWallpaper() {
        if (!prestartedWallpaperAdopted && !prestartedWallpaperRecord)
            return;

        prestartedWallpaperStopPending = true;
        prestartedWallpaperAdopted = false;
        prestartedWallpaperReleased = true;
        prestartedWallpaperMode = "";
        adoptedWallpaperCommand = "";
        stopPrestartedWallpaper();
        prestartedWallpaperRecord = null;
        prestartStopTimer.restart();
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
            if (!externalDesired && !externalProcess.running
                    && !prestartedWallpaperAdopted)
                restartCoverVisible = false;
            if (!externalProcess.running && !prestartedWallpaperAdopted)
                dynamicActive = false;
            return;
        }

        if (dynamicRestartPending)
            return;

        if (!dynamicProcess.running
                && !prestartedWallpaperAdopted
                && prepareWallpaperProcessStart())
            return;

        if (prestartedWallpaperMode === "dynamic"
                && prestartedWallpaperAdopted
                && adoptedWallpaperCommand !== dynamicCommand) {
            showRestartCover();
            releasePrestartedWallpaper();
        }

        if (prestartStateLoaded && prestartedWallpaperRecord
                && !prestartedRecordMatches("dynamic")) {
            showRestartCover();
            releasePrestartedWallpaper();
        }

        if (prestartedWallpaperRecord && !prestartedWallpaperAdopted
                && (dynamicProcess.running || externalProcess.running)) {
            showRestartCover();
            releasePrestartedWallpaper();
        }

        if (prestartedWallpaperStopPending)
            return;

        if (tryAdoptPrestartedWallpaper("dynamic")) {
            dynamicLaunchFailed = false;
            return;
        }

        if (dynamicProcess.running) {
            showRestartCover();
            dynamicRestartPending = true;
            dynamicProcess.running = false;
            return;
        }

        dynamicActive = false;
        dynamicLaunchFailed = false;
        showRestartCover();
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
            if (!dynamicDesired && !dynamicProcess.running
                    && !prestartedWallpaperAdopted)
                restartCoverVisible = false;
            if (!dynamicProcess.running && !prestartedWallpaperAdopted)
                dynamicActive = false;
            return;
        }

        if (externalRestartPending)
            return;

        if (!externalProcess.running
                && !prestartedWallpaperAdopted
                && prepareWallpaperProcessStart())
            return;

        if (prestartedWallpaperMode === "external"
                && prestartedWallpaperAdopted
                && adoptedWallpaperCommand !== externalCommand) {
            showRestartCover();
            releasePrestartedWallpaper();
        }

        if (prestartStateLoaded && prestartedWallpaperRecord
                && !prestartedRecordMatches("external")) {
            showRestartCover();
            releasePrestartedWallpaper();
        }

        if (prestartedWallpaperRecord && !prestartedWallpaperAdopted
                && (dynamicProcess.running || externalProcess.running)) {
            showRestartCover();
            releasePrestartedWallpaper();
        }

        if (prestartedWallpaperStopPending)
            return;

        if (tryAdoptPrestartedWallpaper("external")) {
            externalLaunchFailed = false;
            return;
        }

        if (externalProcess.running) {
            showRestartCover();
            externalRestartPending = true;
            externalProcess.running = false;
            return;
        }

        dynamicActive = false;
        externalLaunchFailed = false;
        showRestartCover();
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
    onAvailableScreenCountChanged: {
        if (root.completed && root.externalDesired) {
            root.refreshExternalCommand();
            root.syncExternalProcess();
        }
    }
    onScreenChanged: {
        if (root.completed) {
            root.reloadPrestartedWallpaperState();
            root.refreshExternalCommand();
            root.syncDynamicProcess();
            root.syncExternalProcess();
        }
    }
    onLiveWallpaperAllowedChanged: {
        if (!root.completed)
            return;
        root.refreshExternalCommand();
        root.syncDynamicProcess();
        root.syncExternalProcess();
    }
    onWallpaperPauseWhenFullscreenChanged: {
        if (root.completed) {
            root.refreshExternalCommand();
            root.syncDynamicProcess();
            root.syncExternalProcess();
        }
    }
    Component.onCompleted: {
        appliedWallpaperFps = effectiveWallpaperFps;
        completed = true;
        reloadPrestartedWallpaperState();
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

    // Intentional command changes (including the fullscreen-pause setting) require a
    // renderer restart. Hold the renderer's own full-size captured frame over the gap
    // so the desktop never falls through to a default image or an empty background.
    Item {
        id: restartCover
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: root.restartCoverVisible ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 120
                easing.type: Motion.emphasizedDecel
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#1c1d20"
        }

        Image {
            anchors.fill: parent
            source: root.staticWallpaperSource()
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
        }

        Image {
            id: restartCoverCapture
            anchors.fill: parent
            source: root.restartCoverVisible || restartCover.opacity > 0.01
                ? root.lockWallpaperCapturePath(root.screenName()) : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            smooth: true
            mipmap: false
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
        interval: 1600
        repeat: false
        onTriggered: {
            if (dynamicProcess.running || externalProcess.running) {
                root.dynamicActive = true;
                root.restartCoverVisible = false;
            }
        }
    }

    Timer {
        id: prestartedWallpaperReadyTimer
        interval: 1600
        repeat: false
        onTriggered: {
            if (root.prestartedWallpaperAdopted) {
                root.dynamicActive = true;
                root.restartCoverVisible = false;
            }
        }
    }

    Timer {
        id: prestartedWallpaperHealthTimer
        interval: 5000
        repeat: true
        running: root.prestartedWallpaperAdopted
        onTriggered: {
            if (!root.prestartedWallpaperAdopted
                    || root.prestartedRecordProcessMatches(root.prestartedWallpaperRecord))
                return;
            Quickshell.execDetached({
                command: ["rm", "-f", "--", root.prestartedWallpaperRecordPath],
                workingDirectory: ""
            });
            root.prestartedWallpaperRecord = null;
            root.prestartedWallpaperAdopted = false;
            root.prestartedWallpaperReleased = true;
            root.prestartedWallpaperMode = "";
            root.adoptedWallpaperCommand = "";
            root.dynamicActive = false;
            root.showRestartCover();
            Qt.callLater(function() {
                root.syncDynamicProcess();
                root.syncExternalProcess();
            });
        }
    }

    Timer {
        id: prestartStopTimer
        interval: 80
        repeat: false
        onTriggered: {
            if (!root.prestartedWallpaperStopPending)
                return;
            root.reloadPrestartedWallpaperState();
            if (root.prestartedWallpaperStopPending) {
                restart();
                return;
            }
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
        id: prestartedWallpaperFile
        path: root.prestartedWallpaperRecordPath
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: root.reloadPrestartedWallpaperState()
        onPathChanged: {
            if (root.completed)
                root.reloadPrestartedWallpaperState();
        }
    }

    FileView {
        id: prestartedWallpaperProcessFile
        path: ""
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: activeWallpaperFile
        path: !root.nestedSession && root.settingsService && root.settingsService.homeDir.length > 0
            ? root.settingsService.homeDir + "/.config/Linux Wallpaper Engine/active-wallpapers.json"
            : ""
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
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
