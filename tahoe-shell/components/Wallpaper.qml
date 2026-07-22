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

    // Explicit mode string used by visibility policy. Empty while settings are
    // still loading so we never treat the JsonAdapter default ("static") as a
    // committed choice and flash iridescence before desktop-settings.json applies.
    readonly property string configuredWallpaperMode: settingsReady
        ? String(settingsService.wallpaperMode || "static")
        : ""
    readonly property bool liveModeConfigured: configuredWallpaperMode === "dynamic"
        || configuredWallpaperMode === "external"
    readonly property bool dynamicDesired: settingsReady
        && !nestedSession
        && configuredWallpaperMode === "dynamic"
        && settingsService.effectiveDynamicWallpaperCommand.length > 0
        && liveWallpaperAllowed
    readonly property string dynamicCommand: dynamicDesired
        ? preparedDynamicCommand(settingsService.effectiveDynamicWallpaperCommand)
        : ""
    readonly property bool externalDesired: settingsReady
        && !nestedSession
        && configuredWallpaperMode === "external"
        && liveWallpaperAllowed
    readonly property bool dynamicSuppressesStatic: dynamicDesired
        && !dynamicLaunchFailed
        // settingsReady→dynamicDesired can evaluate before the first sync runs.
        // Keep static suppressed until syncDynamicProcess has settled a decision.
        && (!dynamicSyncSettled || dynamicCommand.length > 0
            || dynamicProcess.running || dynamicRestartPending
            || prestartedWallpaperAdopted || prestartedWallpaperStopPending
            || !!prestartedWallpaperRecord || screenName().length === 0)
    // Keep static suppressed for the whole live boot path: prestart may already
    // be painting while screen/UX command/prestart records are still resolving.
    // Critical race: when settingsReady flips wallpaperMode to external, QML
    // re-evaluates showStaticWallpaper BEFORE onExternalDesiredChanged can call
    // refreshExternalCommand(). With prestart/UX already "loaded" empty from
    // Component.onCompleted, every previous guard was false for one frame and
    // the default static image (iridescence) painted over the desktop.
    readonly property bool externalSuppressesStatic: externalDesired
        && !externalLaunchFailed
        && (
            !externalSyncSettled
            || !externalStateLoaded
            || !prestartStateLoaded
            || screenName().length === 0
            || externalCommand.length > 0
            || prestartedWallpaperAdopted
            || prestartedWallpaperStopPending
            || !!prestartedWallpaperRecord
            || externalProcess.running
            || externalRestartPending
        )
    // Live modes that are still starting also suppress static even before
    // dynamicDesired/externalDesired fully evaluate (settings mid-load).
    readonly property bool liveModePending: settingsReady
        && !nestedSession
        && liveWallpaperAllowed
        && !dynamicActive
        && !restartCoverVisible
        && (
            (configuredWallpaperMode === "external" && !externalLaunchFailed
                && (!externalSyncSettled || !externalStateLoaded || !prestartStateLoaded
                    || screenName().length === 0 || !!prestartedWallpaperRecord
                    || prestartedWallpaperAdopted || prestartedWallpaperStopPending
                    || externalCommand.length > 0
                    || externalProcess.running || externalRestartPending))
            || (configuredWallpaperMode === "dynamic" && !dynamicLaunchFailed
                && (!dynamicSyncSettled || screenName().length === 0
                    || dynamicCommand.length > 0
                    || !!prestartedWallpaperRecord || prestartedWallpaperAdopted
                    || prestartedWallpaperStopPending
                    || dynamicProcess.running || dynamicRestartPending))
        )
    // Hard policy: the apps default iridescence plate is only for explicit
    // static mode, intentional live-idle pause, or a live mode that has fully
    // failed. While settings are unknown / live is starting / live is running,
    // never mount staticLayer.
    readonly property bool liveLaunchFailed: (configuredWallpaperMode === "dynamic" && dynamicLaunchFailed)
        || (configuredWallpaperMode === "external" && externalLaunchFailed)
    // Prestart owns an independent background surface under tahoe-wallpaper.
    // Treat a validated prestart record as live paint even before adopt settles,
    // so we stay transparent and never plate an opaque cover over it forever.
    readonly property bool prestartLivePainting: !!prestartedWallpaperRecord
        && !prestartedWallpaperReleased
        && !prestartedWallpaperStopPending
    // Cover is ONLY the sticky latch set by showRestartCover() during intentional
    // restarts. Do NOT auto-bind a permanent boot cover: tahoe-wallpaper stacks
    // ABOVE linux-wallpaperengine in the Background layer, so a stuck opaque
    // plate permanently blacks out the live engine (the 5f75b23 regression).
    readonly property bool coverPlateVisible: restartCoverVisible
    readonly property bool showStaticWallpaper: settingsReady
        && !dynamicActive
        && !coverPlateVisible
        && !prestartedWallpaperAdopted
        && !prestartLivePainting
        && !dynamicProcess.running
        && !externalProcess.running
        && !liveModePending
        && !dynamicSuppressesStatic
        && !externalSuppressesStatic
        && (
            configuredWallpaperMode === "static"
            || liveLaunchFailed
            || (liveModeConfigured && !liveWallpaperAllowed)
        )
    readonly property bool liveWallpaperVisible: liveModeConfigured
        || dynamicActive
        || prestartedWallpaperAdopted
        || prestartLivePainting
        || dynamicProcess.running
        || externalProcess.running
        || coverPlateVisible
        || liveModePending
    // Keep the background layer transparent whenever a live renderer is
    // expected, so the compositor can composite the engine under this plate.
    readonly property bool yieldToDynamicWallpaper: !settingsReady
        || dynamicActive
        || dynamicSuppressesStatic
        || externalSuppressesStatic
        || liveModePending
        || coverPlateVisible
        || liveModeConfigured
        || prestartLivePainting
        || prestartedWallpaperAdopted
        || dynamicProcess.running
        || externalProcess.running
    property string externalCommand: ""
    property bool dynamicActive: false
    property bool dynamicRestartPending: false
    property bool externalRestartPending: false
    property bool dynamicLaunchFailed: false
    property bool externalLaunchFailed: false
    property bool externalStateLoaded: false
    // Set true only after the first completed sync pass for each live mode so
    // showStaticWallpaper cannot race ahead of refreshExternalCommand /
    // syncDynamicProcess when settingsReady flips wallpaperMode to live.
    property bool externalSyncSettled: false
    property bool dynamicSyncSettled: false
    property bool completed: false
    property bool restartCoverVisible: false
    property bool prestartStateLoaded: false
    property bool prestartedWallpaperStopPending: false
    property var prestartedWallpaperRecord: null
    property bool prestartedWallpaperAdopted: false
    property bool prestartedWallpaperReleased: false
    property string prestartedWallpaperMode: ""
    property string adoptedWallpaperCommand: ""
    // Consecutive health misses required before tearing down an adopted
    // prestart engine. One-shot /proc glitches must not kill live wallpaper.
    property int prestartedHealthMisses: 0
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
    // Always transparent while live paint is expected. An opaque surface here
    // stacks above linux-wallpaperengine and blacks out the desktop.
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

    // Prefer the PanelWindow's bound screen; fall back to the first announced
    // output so boot cover can load the real capture (eDP-2.png) before the
    // window's screen property is set. An empty name used to resolve to
    // default.png which does not exist → only the dark fill flashed.
    function coverCaptureOutputName() {
        var name = screenName();
        if (name.length > 0)
            return name;
        if (Quickshell.screens && Quickshell.screens.length > 0) {
            name = String(Quickshell.screens[0].name || "").trim();
            if (name.length > 0)
                return name;
        }
        return "";
    }

    function coverCapturePath() {
        var name = coverCaptureOutputName();
        return name.length > 0 ? lockWallpaperCapturePath(name) : "";
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
        // Only clear when external mode is actually off. While settings/UX state
        // are still loading, keep the previous command so a prestarted renderer
        // is not released (and the desktop does not flash the static fallback).
        if (!(settingsReady && settingsService.wallpaperMode === "external" && liveWallpaperAllowed)) {
            externalCommand = "";
            return;
        }
        var restored = restoreCommandFromUxState();
        if (restored.length > 0 || externalStateLoaded)
            externalCommand = restored;
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
        // Never plate over an already-painting live surface. tahoe-wallpaper
        // stacks above linux-wallpaperengine; an opaque cover blacks it out.
        if (dynamicActive || prestartedWallpaperAdopted || prestartLivePainting
                || dynamicProcess.running || externalProcess.running)
            return;
        restartCoverVisible = true;
    }

    function hideRestartCoverIfIdle() {
        // Anything that may already be painting under us → clear immediately.
        if (dynamicActive || prestartedWallpaperAdopted || prestartLivePainting
                || dynamicProcess.running || externalProcess.running) {
            restartCoverVisible = false;
            return;
        }
        // Keep only during intentional stop/restart with nothing painting yet.
        if (prestartedWallpaperStopPending
                || dynamicRestartPending || externalRestartPending)
            return;
        restartCoverVisible = false;
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
            // Missing /proc entry means the process is gone.
            if (text.length === 0)
                return false;
            var close = text.lastIndexOf(")");
            if (close < 0)
                return false;
            var fields = text.substring(close + 1).trim().split(/\s+/);
            return fields.length > 19 && String(fields[19]) === expectedStart;
        } catch (e) {
            // Transient FileView/IO errors must NOT count as death — a single
            // false-negative used to kill a healthy prestart engine and black
            // the desktop (adversarial finding S3).
            return true;
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
                // A freshly validated record may replace one we previously
                // released (health false-negative, intentional stop). Allow
                // adoption again for this instance lifetime.
                prestartedWallpaperReleased = false;
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
        if (expected.length === 0)
            return false;
        // Exact match first. Then FPS-normalized match: prestart may embed
        // battery/idle fps while QML still has the AC budget (or the reverse),
        // which used to fail adopt and kill a healthy engine (adversarial S1).
        var recorded = String(prestartedWallpaperRecord.command || "");
        if (recorded === expected)
            return true;
        return normalizeWallpaperCommandForMatch(recorded)
            === normalizeWallpaperCommandForMatch(expected);
    }

    function normalizeWallpaperCommandForMatch(command) {
        var text = String(command || "").trim();
        // Drop --fps so battery/AC budget skew cannot break adoption.
        text = text.replace(/(^|\s)--fps(\s+|=)\d+/g, "$1");
        text = text.replace(/\s+/g, " ").trim();
        return text;
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
        // The serialized launcher already owns a mapped background surface. Do not
        // raise restartCover over it — that is the post-boot "flash" after the live
        // wallpaper was already visible (gray/capture plate for ~1.6s then drop).
        dynamicActive = true;
        restartCoverVisible = false;
        prestartedHealthMisses = 0;
        prestartedWallpaperReadyTimer.stop();
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
        // Wait for the output binding: prestart records and engine args are
        // per-screen. Starting against an empty name creates a second renderer
        // that races the supervised prestart process.
        if (screenName().length === 0)
            return;

        if (!dynamicDesired || dynamicCommand.length === 0) {
            if (prestartedWallpaperMode === "dynamic")
                releasePrestartedWallpaper();
            dynamicRestartPending = false;
            dynamicLaunchFailed = false;
            dynamicProcess.running = false;
            if (!externalDesired && !externalProcess.running
                    && !prestartedWallpaperAdopted)
                hideRestartCoverIfIdle();
            if (!externalProcess.running && !prestartedWallpaperAdopted)
                dynamicActive = false;
            // Stay unsettled while still wanting dynamic (empty command / mid
            // load). When fully off dynamic, clear settled so the next enter
            // re-suppresses static for the first binding pass.
            dynamicSyncSettled = false;
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
                && dynamicCommand.length > 0
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
            dynamicSyncSettled = true;
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
        dynamicSyncSettled = true;
    }

    function syncExternalProcess() {
        if (!completed)
            return;
        if (screenName().length === 0)
            return;

        if (!externalDesired) {
            if (prestartedWallpaperMode === "external")
                releasePrestartedWallpaper();
            externalRestartPending = false;
            externalLaunchFailed = false;
            externalProcess.running = false;
            if (!dynamicDesired && !dynamicProcess.running
                    && !prestartedWallpaperAdopted)
                hideRestartCoverIfIdle();
            if (!dynamicProcess.running && !prestartedWallpaperAdopted)
                dynamicActive = false;
            // Cleared so the next external enter suppresses static for the
            // first binding pass (before refreshExternalCommand runs).
            externalSyncSettled = false;
            return;
        }

        // External command is reconstructed from UX JSON. Until that file is
        // loaded (or prestart is still being evaluated) keep any adopted
        // prestart renderer and do not tear it down over an empty command.
        if (externalCommand.length === 0) {
            if (!externalStateLoaded || !prestartStateLoaded)
                return;
            if (prestartedWallpaperRecord && !prestartedWallpaperAdopted
                    && tryAdoptPrestartedWallpaper("external")) {
                externalLaunchFailed = false;
                externalSyncSettled = true;
                hideRestartCoverIfIdle();
                return;
            }
            if (prestartedWallpaperAdopted && prestartedWallpaperMode === "external")
                return;
            if (externalProcess.running)
                return;
            // Loaded state with no command for this output: fall through to stop.
            // Do NOT raise a sticky restart cover here — that permanently
            // blacks out anything under tahoe-wallpaper (adversarial finding).
            // Mark launch failed so showStaticWallpaper can fall back instead.
            if (prestartedWallpaperMode === "external")
                releasePrestartedWallpaper();
            externalRestartPending = false;
            externalLaunchFailed = true;
            externalProcess.running = false;
            if (!dynamicDesired && !dynamicProcess.running
                    && !prestartedWallpaperAdopted)
                hideRestartCoverIfIdle();
            if (!dynamicProcess.running && !prestartedWallpaperAdopted)
                dynamicActive = false;
            externalSyncSettled = true;
            restartCoverVisible = false;
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

        // Only release a non-matching prestart record once we can compare a
        // fully-built expected command. Early empty/partial comparisons used
        // to kill the boot renderer and flash the static wallpaper.
        if (prestartStateLoaded && prestartedWallpaperRecord
                && externalCommand.length > 0
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
            externalSyncSettled = true;
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
        externalSyncSettled = true;
    }

    onDynamicDesiredChanged: {
        dynamicLaunchFailed = false;
        // Settings just entered (or left) dynamic mode. Force a fresh settle
        // so the one-frame race against showStaticWallpaper cannot open.
        if (dynamicDesired)
            dynamicSyncSettled = false;
        syncDynamicProcess();
    }
    onDynamicCommandChanged: {
        dynamicLaunchFailed = false;
        syncDynamicProcess();
    }
    onExternalDesiredChanged: {
        externalLaunchFailed = false;
        if (externalDesired)
            externalSyncSettled = false;
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
            // Output name drives both the prestart record path and the engine
            // --screen-root. Defer until the PanelWindow has a real screen so we
            // never adopt/start against "default" and thrash the boot renderer.
            if (root.screenName().length === 0)
                return;
            root.reloadPrestartedWallpaperState();
            root.refreshExternalCommand();
            root.syncDynamicProcess();
            root.syncExternalProcess();
            // Cover only if we still need a cold start; never plate over an
            // already-adopted or running live renderer.
            if ((root.dynamicDesired || root.externalDesired)
                    && !root.dynamicActive
                    && !root.prestartedWallpaperAdopted
                    && !dynamicProcess.running
                    && !externalProcess.running)
                root.showRestartCover();
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
        // Adopt/start first. Prestart already paints; raising a cover before
        // adopt would hide the live wallpaper then drop it 1.6s later (flash).
        reloadPrestartedWallpaperState();
        activeWallpaperFile.reload();
        syncDynamicProcess();
        syncExternalProcess();
        if ((dynamicDesired || externalDesired)
                && !dynamicActive
                && !prestartedWallpaperAdopted
                && !dynamicProcess.running
                && !externalProcess.running)
            showRestartCover();
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
        // Only mount when static is actually shown. A brief true→false on
        // showStaticWallpaper with Behavior on opacity used to fade the default
        // image over the live engine for ~160ms after boot adopt.
        visible: root.showStaticWallpaper
        opacity: 1
        clip: true

        readonly property real zoom: root.launchpadOpen ? Motion.launchpadWallpaperScale : 1.0
        readonly property real dimOpacity: root.launchpadOpen ? Motion.launchpadWallpaperDim : 0.0

        Image {
            id: staticImage
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            // Avoid binding apps default (iridescence) while live mode is pending.
            source: root.showStaticWallpaper ? root.staticWallpaperSource() : ""
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
    // Prefer the live capture only. Never fade the cover *in* — the previous
    // Behavior on opacity left opacity at 0 for ~120ms while the PanelWindow was
    // transparent, so niri's default gray (or the dark fill) flashed after the
    // iridescence flash was blocked.
    Item {
        id: restartCover
        anchors.fill: parent
        // Mount immediately when the boot gap needs a plate; keep mounted during
        // the hide fade so the engine can composite underneath without a hole.
        visible: root.coverPlateVisible || opacity > 0.01
        opacity: root.coverPlateVisible ? 1 : 0

        // Fade out only. Showing must be instantaneous so the first live-boot
        // frame is never transparent over niri's clear color.
        Behavior on opacity {
            enabled: !root.coverPlateVisible
            NumberAnimation {
                duration: 120
                easing.type: Motion.emphasizedDecel
            }
        }

        Rectangle {
            anchors.fill: parent
            // Only visible while the capture is missing/decoding. Once the
            // engine frame is ready the Image fully covers this.
            color: "#1c1d20"
            visible: restartCoverCapture.status !== Image.Ready
        }

        Image {
            id: restartCoverCapture
            anchors.fill: parent
            // Always preload the last engine frame while the screen is known so
            // the boot cover does not open on a blank dark plate. Path falls
            // back to the first announced output when PanelWindow.screen is late.
            source: root.coverCapturePath()
            fillMode: Image.PreserveAspectCrop
            // Sync decode on the shell thread is acceptable here: the capture is
            // a single full-size PNG already on disk from the previous session.
            asynchronous: false
            cache: true
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
            // Drop any restart plate immediately so the engine surface under
            // tahoe-wallpaper is not blacked out for the ready-timer duration.
            root.restartCoverVisible = false;
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
            // Intentional restarts keep the cover; unexpected exit drops the latch so
            // showStaticWallpaper (liveLaunchFailed) or a transparent yield can
            // take over instead of a permanent void or sticky plate.
            if (!root.dynamicRestartPending
                    && !externalProcess.running
                    && !root.prestartedWallpaperAdopted)
                root.hideRestartCoverIfIdle();
        }
    }

    Process {
        id: externalProcess
        running: false
        command: ["sh", "-lc", root.externalCommand]
        onStarted: {
            root.externalLaunchFailed = false;
            root.restartCoverVisible = false;
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
            if (!root.externalRestartPending
                    && !dynamicProcess.running
                    && !root.prestartedWallpaperAdopted)
                root.hideRestartCoverIfIdle();
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
            if (!root.prestartedWallpaperAdopted)
                return;
            if (root.prestartedRecordProcessMatches(root.prestartedWallpaperRecord)) {
                root.prestartedHealthMisses = 0;
                return;
            }
            root.prestartedHealthMisses += 1;
            // Require two consecutive misses (~10s) so a single /proc glitch
            // cannot kill a healthy engine and leave a sticky cover.
            if (root.prestartedHealthMisses < 2)
                return;
            root.prestartedHealthMisses = 0;
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
            // Prefer transparent yield + resync over a sticky opaque plate.
            root.restartCoverVisible = false;
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
