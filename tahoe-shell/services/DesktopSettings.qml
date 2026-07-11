pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    readonly property string settingsPath: Quickshell.stateDir + "/desktop-settings.json"
    readonly property string autostartManagerPath: Quickshell.shellPath("services/autostart_manager.py")
    readonly property string homeDir: envString("HOME")
    readonly property string defaultScreenshotDirectory: homeDir.length > 0
        ? homeDir + "/Pictures/Screenshots"
        : "Pictures/Screenshots"
    readonly property string dockWindowTitleMode: settingsAdapter.dockWindowTitleMode
    readonly property bool dockForceIconOnly: dockWindowTitleMode === "icons"
    readonly property bool dockPreferTitles: dockWindowTitleMode === "titles"
    readonly property bool dockAutoHide: settingsAdapter.dockAutoHide
    readonly property int dockAutoHideDelayMs: settingsAdapter.dockAutoHideDelayMs
    readonly property int dockRevealZoneHeight: settingsAdapter.dockRevealZoneHeight
    readonly property bool dockMinimizedShelfEnabled: settingsAdapter.dockMinimizedShelfEnabled
    readonly property string wallpaperMode: settingsAdapter.wallpaperMode
    readonly property string staticWallpaperPath: settingsAdapter.staticWallpaperPath
    readonly property string effectiveStaticWallpaper: normalizedPath(staticWallpaperPath)
    readonly property string dynamicWallpaperCommand: settingsAdapter.dynamicWallpaperCommand
    readonly property string effectiveDynamicWallpaperCommand: String(dynamicWallpaperCommand || "").trim()
    readonly property string dynamicWallpaperExampleCommand: "linux-wallpaperengine --screen-root {output} --assets-dir \"$HOME/.local/share/Steam/steamapps/workshop/content/431960\" WALLPAPER_ID"
    // Live wallpaper engine budget. Active fps is capped low so glass sampling
    // is not forced to full-screen damage at 30Hz; idle drops further (or pauses).
    readonly property int wallpaperEngineFps: settingsAdapter.wallpaperEngineFps
    readonly property int wallpaperEngineIdleFps: settingsAdapter.wallpaperEngineIdleFps
    readonly property int wallpaperEngineIdleSeconds: settingsAdapter.wallpaperEngineIdleSeconds
    readonly property bool wallpaperPauseWhenIdle: settingsAdapter.wallpaperPauseWhenIdle
    readonly property string screenshotDirectory: settingsAdapter.screenshotDirectory
    readonly property string effectiveScreenshotDirectory: normalizedDirectory(screenshotDirectory).length > 0
        ? normalizedDirectory(screenshotDirectory)
        : defaultScreenshotDirectory
    readonly property bool screenshotCopyToClipboard: settingsAdapter.screenshotCopyToClipboard
    readonly property bool screenshotOfferActions: settingsAdapter.screenshotOfferActions
    readonly property string startupNote: settingsAdapter.startupNote
    readonly property bool compositorLayerAnimations: settingsAdapter.compositorLayerAnimations
    readonly property string motionProfile: settingsAdapter.motionProfile
    readonly property bool dynamicIslandEnabled: settingsAdapter.dynamicIslandEnabled
    readonly property bool dynamicIslandHideTopbarTime: settingsAdapter.dynamicIslandHideTopbarTime
    readonly property string dynamicIslandLeftClickAction: settingsAdapter.dynamicIslandLeftClickAction
    readonly property string dynamicIslandRightClickAction: settingsAdapter.dynamicIslandRightClickAction
    readonly property bool dynamicIslandAutoExpandMedia: settingsAdapter.dynamicIslandAutoExpandMedia
    readonly property bool dynamicIslandHoverExpand: settingsAdapter.dynamicIslandHoverExpand
    readonly property string iconThemeMode: settingsAdapter.iconThemeMode
    readonly property string customIconTheme: settingsAdapter.customIconTheme
    readonly property string effectiveIconTheme: iconThemeName(iconThemeMode, customIconTheme)
    readonly property string currentIconTheme: envString("QS_ICON_THEME").trim()
    readonly property bool iconThemeRestartRequired: iconThemeMode !== "builtin" && effectiveIconTheme !== currentIconTheme
    readonly property real weatherLatitude: settingsAdapter.weatherLatitude
    readonly property real weatherLongitude: settingsAdapter.weatherLongitude
    readonly property string weatherLocationName: settingsAdapter.weatherLocationName
    readonly property bool weatherManualOverride: settingsAdapter.weatherManualOverride
    readonly property string weatherTempUnit: settingsAdapter.weatherTempUnit
    // T09: max simultaneous toast cards in the live stack (1–3).
    readonly property int notificationToastStackMax: settingsAdapter.notificationToastStackMax
    // T14: macOS-style accent id (blue/purple/pink/red/orange/yellow/green/graphite).
    readonly property string accentColor: settingsAdapter.accentColor
    property var autostartEntries: []
    property string autostartStatus: "unknown"
    property string autostartDetail: "尚未读取启动项"
    property string autostartUserDir: homeDir.length > 0 ? homeDir + "/.config/autostart" : ""
    property string autostartActionText: ""
    property bool autostartRefreshing: false
    property bool autostartActionRunning: false
    property int autostartRevision: 0
    property bool loaded: false

    function envString(name) {
        var value = Quickshell.env(name);
        return value === undefined || value === null ? "" : String(value);
    }

    function normalizedDirectory(value) {
        var text = String(value || "").trim();
        if (text.length === 0)
            return "";
        if (text === "~")
            return homeDir;
        if (text.indexOf("~/") === 0 && homeDir.length > 0)
            return homeDir + text.substring(1);
        return text;
    }

    function normalizedPath(value) {
        var text = String(value || "").trim();
        if (text.length === 0)
            return "";
        if (text === "~")
            return homeDir;
        if (text.indexOf("~/") === 0 && homeDir.length > 0)
            return homeDir + text.substring(1);
        return text;
    }

    function validDockWindowTitleMode(value) {
        return value === "auto" || value === "icons" || value === "titles";
    }

    function validWallpaperMode(value) {
        return value === "static" || value === "dynamic" || value === "external";
    }

    function validDynamicIslandClickAction(value) {
        return value === "toggle_media"
            || value === "summary"
            || value === "notifications"
            || value === "control_center"
            || value === "none";
    }

    function normalizedWeatherTempUnit(value) {
        var text = String(value || "").trim().toLowerCase();
        if (text === "f" || text === "fahrenheit" || text === "°f")
            return "f";
        return "c";
    }

    function validIconThemeMode(value) {
        return value === "system"
            || value === "builtin"
            || value === "papirus"
            || value === "papirus-dark"
            || value === "papirus-light"
            || value === "custom";
    }

    function validMotionProfile(value) {
        return value === "fast"
            || value === "balanced"
            || value === "liquid"
            || value === "reduced";
    }

    function validAccentColor(value) {
        var id = String(value || "").trim().toLowerCase();
        return id === "blue"
            || id === "purple"
            || id === "pink"
            || id === "red"
            || id === "orange"
            || id === "yellow"
            || id === "green"
            || id === "graphite"
            || id === "gray"
            || id === "grey";
    }

    function normalizeAccentColor(value) {
        var id = String(value || "").trim().toLowerCase();
        if (id === "gray" || id === "grey")
            return "graphite";
        return validAccentColor(id) ? (id === "gray" || id === "grey" ? "graphite" : id) : "blue";
    }

    function accentColorLabel(value) {
        var id = normalizeAccentColor(value);
        if (id === "purple")
            return "紫色";
        if (id === "pink")
            return "粉色";
        if (id === "red")
            return "红色";
        if (id === "orange")
            return "橙色";
        if (id === "yellow")
            return "黄色";
        if (id === "green")
            return "绿色";
        if (id === "graphite")
            return "石墨";
        return "蓝色";
    }

    function cleanIconThemeName(value) {
        return String(value || "").replace(/[\/\\:\n\r\t]/g, "").trim();
    }

    function iconThemeName(mode, customName) {
        if (mode === "papirus")
            return "Papirus";
        if (mode === "papirus-dark")
            return "Papirus-Dark";
        if (mode === "papirus-light")
            return "Papirus-Light";
        if (mode === "custom")
            return cleanIconThemeName(customName);
        return "";
    }

    function cleanWeatherLocationName(value) {
        return String(value || "").trim();
    }

    function clampInt(value, minimum, maximum, fallback) {
        var number = Math.round(Number(value));
        if (!isFinite(number))
            number = fallback;
        return Math.max(minimum, Math.min(maximum, number));
    }

    function clampNumber(value, minimum, maximum, fallback) {
        var number = Number(value);
        if (!isFinite(number))
            number = fallback;
        return Math.max(minimum, Math.min(maximum, number));
    }

    function modeLabel(mode) {
        if (mode === "icons")
            return "仅图标";
        if (mode === "titles")
            return "标题优先";
        return "自动";
    }

    function wallpaperModeLabel(mode) {
        if (mode === "dynamic")
            return "动态命令";
        if (mode === "external")
            return "UX 管理";
        return "静态";
    }

    function iconThemeLabel(mode) {
        if (mode === "papirus")
            return "Papirus";
        if (mode === "papirus-dark")
            return "Papirus Dark";
        if (mode === "papirus-light")
            return "Papirus Light";
        if (mode === "builtin")
            return "内置默认";
        if (mode === "custom")
            return customIconTheme.length > 0 ? customIconTheme : "自定义";
        return "系统默认";
    }

    function iconThemeStatusText() {
        if (iconThemeMode === "builtin")
            return "内置默认 · 当前生效";
        var wanted = effectiveIconTheme.length > 0 ? effectiveIconTheme : "系统默认";
        if (!iconThemeRestartRequired)
            return wanted + " · 当前生效";
        var current = currentIconTheme.length > 0 ? currentIconTheme : "系统默认";
        return wanted + " · 重启 Tahoe Shell 后生效，当前 " + current;
    }

    function dynamicIslandClickActionLabel(action) {
        if (action === "summary")
            return "摘要页";
        if (action === "notifications")
            return "通知中心";
        if (action === "control_center")
            return "控制中心";
        if (action === "none")
            return "无动作";
        return "媒体/摘要";
    }

    function setDockWindowTitleMode(mode) {
        var next = validDockWindowTitleMode(mode) ? mode : "auto";
        if (settingsAdapter.dockWindowTitleMode === next)
            return;

        settingsAdapter.dockWindowTitleMode = next;
        settingsFile.writeAdapter();
    }

    function setDockAutoHide(enabled) {
        var next = !!enabled;
        if (settingsAdapter.dockAutoHide === next)
            return;

        settingsAdapter.dockAutoHide = next;
        settingsFile.writeAdapter();
    }

    function setDockAutoHideDelayMs(value) {
        var next = clampInt(value, 0, 1500, 260);
        if (settingsAdapter.dockAutoHideDelayMs === next)
            return;

        settingsAdapter.dockAutoHideDelayMs = next;
        settingsFile.writeAdapter();
    }

    function setDockRevealZoneHeight(value) {
        var next = clampInt(value, 2, 24, 8);
        if (settingsAdapter.dockRevealZoneHeight === next)
            return;

        settingsAdapter.dockRevealZoneHeight = next;
        settingsFile.writeAdapter();
    }

    function setDockMinimizedShelfEnabled(enabled) {
        var next = !!enabled;
        if (settingsAdapter.dockMinimizedShelfEnabled === next)
            return;

        settingsAdapter.dockMinimizedShelfEnabled = next;
        settingsFile.writeAdapter();
    }

    function setWallpaperMode(mode) {
        var next = validWallpaperMode(mode) ? mode : "static";
        if (settingsAdapter.wallpaperMode === next)
            return;

        settingsAdapter.wallpaperMode = next;
        settingsFile.writeAdapter();
    }

    function setStaticWallpaperPath(path) {
        var next = normalizedPath(path);
        if (settingsAdapter.staticWallpaperPath === next)
            return;

        settingsAdapter.staticWallpaperPath = next;
        settingsFile.writeAdapter();
    }

    function resetStaticWallpaperPath() {
        setStaticWallpaperPath("");
    }

    function setDynamicWallpaperCommand(command) {
        var next = String(command || "").trim();
        if (settingsAdapter.dynamicWallpaperCommand === next)
            return;

        settingsAdapter.dynamicWallpaperCommand = next;
        settingsFile.writeAdapter();
    }

    function useDynamicWallpaperExampleCommand() {
        setDynamicWallpaperCommand(dynamicWallpaperExampleCommand);
    }

    function setWallpaperEngineFps(value) {
        var next = clampInt(value, 1, 20, 15);
        if (settingsAdapter.wallpaperEngineFps === next)
            return;
        settingsAdapter.wallpaperEngineFps = next;
        if (settingsAdapter.wallpaperEngineIdleFps > next)
            settingsAdapter.wallpaperEngineIdleFps = next;
        settingsFile.writeAdapter();
    }

    function setWallpaperEngineIdleFps(value) {
        var cap = clampInt(settingsAdapter.wallpaperEngineFps, 1, 20, 15);
        var next = clampInt(value, 1, cap, Math.min(8, cap));
        if (settingsAdapter.wallpaperEngineIdleFps === next)
            return;
        settingsAdapter.wallpaperEngineIdleFps = next;
        settingsFile.writeAdapter();
    }

    function setWallpaperEngineIdleSeconds(value) {
        var next = clampInt(value, 15, 900, 60);
        if (settingsAdapter.wallpaperEngineIdleSeconds === next)
            return;
        settingsAdapter.wallpaperEngineIdleSeconds = next;
        settingsFile.writeAdapter();
    }

    function setWallpaperPauseWhenIdle(enabled) {
        var next = !!enabled;
        if (settingsAdapter.wallpaperPauseWhenIdle === next)
            return;
        settingsAdapter.wallpaperPauseWhenIdle = next;
        settingsFile.writeAdapter();
    }

    function openWallpaperEngineUx() {
        Quickshell.execDetached({
            command: [
                "sh",
                "-lc",
                "command -v linux-wallpaper-engine-ux >/dev/null 2>&1 && exec linux-wallpaper-engine-ux"
            ],
            workingDirectory: ""
        });
    }

    function setScreenshotDirectory(path) {
        var next = normalizedDirectory(path);
        if (settingsAdapter.screenshotDirectory === next)
            return;

        settingsAdapter.screenshotDirectory = next;
        settingsFile.writeAdapter();
    }

    function resetScreenshotDirectory() {
        setScreenshotDirectory("");
    }

    function setScreenshotCopyToClipboard(enabled) {
        var next = !!enabled;
        if (settingsAdapter.screenshotCopyToClipboard === next)
            return;

        settingsAdapter.screenshotCopyToClipboard = next;
        settingsFile.writeAdapter();
    }

    function setScreenshotOfferActions(enabled) {
        var next = !!enabled;
        if (settingsAdapter.screenshotOfferActions === next)
            return;

        settingsAdapter.screenshotOfferActions = next;
        settingsFile.writeAdapter();
    }

    function setStartupNote(note) {
        var next = String(note || "").trim();
        if (settingsAdapter.startupNote === next)
            return;

        settingsAdapter.startupNote = next;
        settingsFile.writeAdapter();
    }

    function setCompositorLayerAnimations(enabled) {
        var next = !!enabled;
        if (settingsAdapter.compositorLayerAnimations === next)
            return;

        settingsAdapter.compositorLayerAnimations = next;
        settingsFile.writeAdapter();
    }

    function setMotionProfile(profile) {
        var next = validMotionProfile(profile) ? String(profile) : "balanced";
        if (settingsAdapter.motionProfile === next)
            return;

        settingsAdapter.motionProfile = next;
        settingsFile.writeAdapter();
    }

    function setAccentColor(value) {
        var next = normalizeAccentColor(value);
        if (settingsAdapter.accentColor === next)
            return;

        settingsAdapter.accentColor = next;
        settingsFile.writeAdapter();
    }

    function setNotificationToastStackMax(value) {
        var next = clampInt(value, 1, 3, 3);
        if (settingsAdapter.notificationToastStackMax === next)
            return;

        settingsAdapter.notificationToastStackMax = next;
        settingsFile.writeAdapter();
    }

    function setDynamicIslandEnabled(enabled) {
        var next = !!enabled;
        if (settingsAdapter.dynamicIslandEnabled === next)
            return;

        settingsAdapter.dynamicIslandEnabled = next;
        settingsFile.writeAdapter();
    }

    function setDynamicIslandHideTopbarTime(enabled) {
        var next = !!enabled;
        if (settingsAdapter.dynamicIslandHideTopbarTime === next)
            return;

        settingsAdapter.dynamicIslandHideTopbarTime = next;
        settingsFile.writeAdapter();
    }

    function setDynamicIslandLeftClickAction(action) {
        var next = validDynamicIslandClickAction(action) ? action : "toggle_media";
        if (settingsAdapter.dynamicIslandLeftClickAction === next)
            return;

        settingsAdapter.dynamicIslandLeftClickAction = next;
        settingsFile.writeAdapter();
    }

    function setDynamicIslandRightClickAction(action) {
        var next = validDynamicIslandClickAction(action) ? action : "control_center";
        if (settingsAdapter.dynamicIslandRightClickAction === next)
            return;

        settingsAdapter.dynamicIslandRightClickAction = next;
        settingsFile.writeAdapter();
    }

    function setDynamicIslandAutoExpandMedia(enabled) {
        var next = !!enabled;
        if (settingsAdapter.dynamicIslandAutoExpandMedia === next)
            return;

        settingsAdapter.dynamicIslandAutoExpandMedia = next;
        settingsFile.writeAdapter();
    }

    function setDynamicIslandHoverExpand(enabled) {
        var next = !!enabled;
        if (settingsAdapter.dynamicIslandHoverExpand === next)
            return;

        settingsAdapter.dynamicIslandHoverExpand = next;
        settingsFile.writeAdapter();
    }

    function setIconThemeMode(mode) {
        var next = validIconThemeMode(mode) ? mode : "system";
        if (settingsAdapter.iconThemeMode === next)
            return;

        settingsAdapter.iconThemeMode = next;
        settingsFile.writeAdapter();
    }

    function setCustomIconTheme(name) {
        var next = cleanIconThemeName(name);
        if (settingsAdapter.customIconTheme === next && settingsAdapter.iconThemeMode === "custom")
            return;

        settingsAdapter.customIconTheme = next;
        settingsAdapter.iconThemeMode = next.length > 0 ? "custom" : "system";
        settingsFile.writeAdapter();
    }

    function setWeatherLocation(lat, lon, name) {
        var nextLat = clampNumber(lat, -90, 90, 0);
        var nextLon = clampNumber(lon, -180, 180, 0);
        var nextName = cleanWeatherLocationName(name);
        if (nextName.length === 0)
            nextName = "手动位置";

        if (settingsAdapter.weatherManualOverride
                && settingsAdapter.weatherLatitude === nextLat
                && settingsAdapter.weatherLongitude === nextLon
                && settingsAdapter.weatherLocationName === nextName)
            return;

        settingsAdapter.weatherLatitude = nextLat;
        settingsAdapter.weatherLongitude = nextLon;
        settingsAdapter.weatherLocationName = nextName;
        settingsAdapter.weatherManualOverride = true;
        settingsFile.writeAdapter();
    }

    function clearWeatherLocation() {
        if (!settingsAdapter.weatherManualOverride
                && settingsAdapter.weatherLatitude === 0
                && settingsAdapter.weatherLongitude === 0
                && settingsAdapter.weatherLocationName === "")
            return;

        settingsAdapter.weatherLatitude = 0;
        settingsAdapter.weatherLongitude = 0;
        settingsAdapter.weatherLocationName = "";
        settingsAdapter.weatherManualOverride = false;
        settingsFile.writeAdapter();
    }

    function setWeatherTempUnit(unit) {
        var next = normalizedWeatherTempUnit(unit);
        if (settingsAdapter.weatherTempUnit === next)
            return;

        settingsAdapter.weatherTempUnit = next;
        settingsFile.writeAdapter();
    }

    function openAutostartFolder() {
        var dir = homeDir.length > 0 ? homeDir + "/.config/autostart" : Quickshell.stateDir;
        Quickshell.execDetached({
            command: [
                "sh",
                "-lc",
                "dir=\"$1\"; mkdir -p \"$dir\"; command -v xdg-open >/dev/null 2>&1 && xdg-open \"$dir\"",
                "sh",
                dir
            ],
            workingDirectory: ""
        });
    }

    function autostartCommand(args) {
        return ["python3", root.autostartManagerPath].concat(args || []);
    }

    function refreshAutostart() {
        if (autostartProbe.running)
            return;

        root.autostartRefreshing = true;
        autostartProbe.command = autostartCommand(["list"]);
        autostartProbe.running = true;
    }

    function parseAutostart(text) {
        try {
            var parsed = JSON.parse(String(text || "{}"));
            root.autostartStatus = String(parsed.status || "unknown");
            root.autostartDetail = String(parsed.detail || "");
            root.autostartUserDir = String(parsed.userDir || root.autostartUserDir || "");
            root.autostartEntries = parsed.entries || [];
        } catch (e) {
            root.autostartStatus = "error";
            root.autostartDetail = "启动项数据解析失败：" + String(e);
            root.autostartEntries = [];
        }
        root.autostartRevision += 1;
    }

    function runAutostartAction(args, fallbackText) {
        if (autostartAction.running)
            return;

        root.autostartActionRunning = true;
        root.autostartActionText = fallbackText || "";
        autostartAction.command = autostartCommand(args || []);
        autostartAction.running = true;
    }

    function parseAutostartAction(text) {
        try {
            var parsed = JSON.parse(String(text || "{}"));
            root.autostartActionText = String(parsed.message || parsed.detail || "");
            if (String(parsed.status || "") !== "ok" && root.autostartActionText.length === 0)
                root.autostartActionText = "启动项操作失败";
        } catch (e) {
            root.autostartActionText = "启动项操作结果解析失败：" + String(e);
        }
    }

    function setAutostartEnabled(desktopId, enabled) {
        runAutostartAction(
            ["set-enabled", String(desktopId || ""), enabled ? "true" : "false"],
            enabled ? "正在启用启动项" : "正在停用启动项"
        );
    }

    function addAutostartApp(desktopId) {
        runAutostartAction(["add", String(desktopId || "")], "正在添加启动项");
    }

    function removeAutostartEntry(desktopId) {
        runAutostartAction(["remove", String(desktopId || "")], "正在移除启动项");
    }

    function sanitizeState() {
        settingsAdapter.accentColor = normalizeAccentColor(settingsAdapter.accentColor);
        root.loaded = true;
        var changed = false;

        if (!validDockWindowTitleMode(settingsAdapter.dockWindowTitleMode)) {
            settingsAdapter.dockWindowTitleMode = "auto";
            changed = true;
        }

        var autoHideDelay = clampInt(settingsAdapter.dockAutoHideDelayMs, 0, 1500, 260);
        if (settingsAdapter.dockAutoHideDelayMs !== autoHideDelay) {
            settingsAdapter.dockAutoHideDelayMs = autoHideDelay;
            changed = true;
        }

        var revealHeight = clampInt(settingsAdapter.dockRevealZoneHeight, 2, 24, 8);
        if (settingsAdapter.dockRevealZoneHeight !== revealHeight) {
            settingsAdapter.dockRevealZoneHeight = revealHeight;
            changed = true;
        }

        if (!validWallpaperMode(settingsAdapter.wallpaperMode)) {
            settingsAdapter.wallpaperMode = "static";
            changed = true;
        }

        var liveFps = clampInt(settingsAdapter.wallpaperEngineFps, 1, 20, 15);
        if (settingsAdapter.wallpaperEngineFps !== liveFps) {
            settingsAdapter.wallpaperEngineFps = liveFps;
            changed = true;
        }

        var idleFps = clampInt(settingsAdapter.wallpaperEngineIdleFps, 1, liveFps, Math.min(8, liveFps));
        if (settingsAdapter.wallpaperEngineIdleFps !== idleFps) {
            settingsAdapter.wallpaperEngineIdleFps = idleFps;
            changed = true;
        }

        var idleSec = clampInt(settingsAdapter.wallpaperEngineIdleSeconds, 15, 900, 60);
        if (settingsAdapter.wallpaperEngineIdleSeconds !== idleSec) {
            settingsAdapter.wallpaperEngineIdleSeconds = idleSec;
            changed = true;
        }

        if (!validIconThemeMode(settingsAdapter.iconThemeMode)) {
            settingsAdapter.iconThemeMode = "system";
            changed = true;
        }

        if (!validMotionProfile(settingsAdapter.motionProfile)) {
            settingsAdapter.motionProfile = "balanced";
            changed = true;
        }

        var toastStackMax = clampInt(settingsAdapter.notificationToastStackMax, 1, 3, 3);
        if (settingsAdapter.notificationToastStackMax !== toastStackMax) {
            settingsAdapter.notificationToastStackMax = toastStackMax;
            changed = true;
        }

        var iconTheme = cleanIconThemeName(settingsAdapter.customIconTheme);
        if (settingsAdapter.customIconTheme !== iconTheme) {
            settingsAdapter.customIconTheme = iconTheme;
            changed = true;
        }

        if (settingsAdapter.iconThemeMode === "custom" && settingsAdapter.customIconTheme.length === 0) {
            settingsAdapter.iconThemeMode = "system";
            changed = true;
        }

        var wallpaperPath = normalizedPath(settingsAdapter.staticWallpaperPath);
        if (settingsAdapter.staticWallpaperPath !== wallpaperPath) {
            settingsAdapter.staticWallpaperPath = wallpaperPath;
            changed = true;
        }

        var dynamicCommand = String(settingsAdapter.dynamicWallpaperCommand || "").trim();
        if (settingsAdapter.dynamicWallpaperCommand !== dynamicCommand) {
            settingsAdapter.dynamicWallpaperCommand = dynamicCommand;
            changed = true;
        }

        var normalized = normalizedDirectory(settingsAdapter.screenshotDirectory);
        if (settingsAdapter.screenshotDirectory !== normalized) {
            settingsAdapter.screenshotDirectory = normalized;
            changed = true;
        }

        if (!validDynamicIslandClickAction(settingsAdapter.dynamicIslandLeftClickAction)) {
            settingsAdapter.dynamicIslandLeftClickAction = "toggle_media";
            changed = true;
        }

        if (!validDynamicIslandClickAction(settingsAdapter.dynamicIslandRightClickAction)) {
            settingsAdapter.dynamicIslandRightClickAction = "control_center";
            changed = true;
        }

        var weatherLat = clampNumber(settingsAdapter.weatherLatitude, -90, 90, 0);
        if (settingsAdapter.weatherLatitude !== weatherLat) {
            settingsAdapter.weatherLatitude = weatherLat;
            changed = true;
        }

        var weatherLon = clampNumber(settingsAdapter.weatherLongitude, -180, 180, 0);
        if (settingsAdapter.weatherLongitude !== weatherLon) {
            settingsAdapter.weatherLongitude = weatherLon;
            changed = true;
        }

        var weatherName = cleanWeatherLocationName(settingsAdapter.weatherLocationName);
        if (settingsAdapter.weatherManualOverride && weatherName.length === 0)
            weatherName = "手动位置";
        if (!settingsAdapter.weatherManualOverride)
            weatherName = "";
        if (settingsAdapter.weatherLocationName !== weatherName) {
            settingsAdapter.weatherLocationName = weatherName;
            changed = true;
        }

        var tempUnit = normalizedWeatherTempUnit(settingsAdapter.weatherTempUnit);
        if (settingsAdapter.weatherTempUnit !== tempUnit) {
            settingsAdapter.weatherTempUnit = tempUnit;
            changed = true;
        }

        if (changed)
            settingsFile.writeAdapter();
    }

    Component.onCompleted: refreshAutostart()

    Process {
        id: autostartProbe
        running: false
        stdout: StdioCollector {
            id: autostartOut
            onStreamFinished: root.parseAutostart(autostartOut.text)
        }
        onExited: function(code, exitStatus) {
            root.autostartRefreshing = false;
            if (code !== 0) {
                root.autostartStatus = "error";
                root.autostartDetail = "启动项读取失败，退出码 " + String(code);
                root.autostartEntries = [];
                root.autostartRevision += 1;
            }
        }
    }

    Process {
        id: autostartAction
        running: false
        stdout: StdioCollector {
            id: autostartActionOut
            onStreamFinished: root.parseAutostartAction(autostartActionOut.text)
        }
        onExited: function(code, exitStatus) {
            root.autostartActionRunning = false;
            if (code !== 0)
                root.autostartActionText = "启动项操作失败，退出码 " + String(code);
            root.refreshAutostart();
        }
    }

    FileView {
        id: settingsFile
        path: root.settingsPath
        blockLoading: true
        blockWrites: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.sanitizeState()
        onLoadFailed: {
            root.loaded = true;
            writeAdapter();
        }

        JsonAdapter {
            id: settingsAdapter
            property string dockWindowTitleMode: "auto"
            property bool dockAutoHide: false
            property int dockAutoHideDelayMs: 260
            property int dockRevealZoneHeight: 8
            property bool dockMinimizedShelfEnabled: false
            property string wallpaperMode: "static"
            property string staticWallpaperPath: ""
            property string dynamicWallpaperCommand: ""
            // Active/idle fps for linux-wallpaperengine (external + dynamic modes).
            property int wallpaperEngineFps: 15
            property int wallpaperEngineIdleFps: 8
            property int wallpaperEngineIdleSeconds: 60
            // When true, stop the engine while idle and show static wallpaper.
            property bool wallpaperPauseWhenIdle: false
            property string screenshotDirectory: ""
            property bool screenshotCopyToClipboard: true
            property bool screenshotOfferActions: true
            property string startupNote: ""
            property bool compositorLayerAnimations: true
            property string motionProfile: "balanced"
            property string accentColor: "blue"
            property int notificationToastStackMax: 3
            property bool dynamicIslandEnabled: true
            property bool dynamicIslandHideTopbarTime: true
            property string dynamicIslandLeftClickAction: "toggle_media"
            property string dynamicIslandRightClickAction: "control_center"
            property bool dynamicIslandAutoExpandMedia: false
            property bool dynamicIslandHoverExpand: false
            property string iconThemeMode: "system"
            property string customIconTheme: ""
            property real weatherLatitude: 0
            property real weatherLongitude: 0
            property string weatherLocationName: ""
            property bool weatherManualOverride: false
            property string weatherTempUnit: "c"
        }
    }
}
