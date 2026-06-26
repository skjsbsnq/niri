pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    readonly property string settingsPath: Quickshell.stateDir + "/desktop-settings.json"
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
    readonly property string screenshotDirectory: settingsAdapter.screenshotDirectory
    readonly property string effectiveScreenshotDirectory: normalizedDirectory(screenshotDirectory).length > 0
        ? normalizedDirectory(screenshotDirectory)
        : defaultScreenshotDirectory
    readonly property bool screenshotCopyToClipboard: settingsAdapter.screenshotCopyToClipboard
    readonly property bool screenshotOfferActions: settingsAdapter.screenshotOfferActions
    readonly property string startupNote: settingsAdapter.startupNote
    readonly property bool compositorLayerAnimations: settingsAdapter.compositorLayerAnimations
    readonly property bool dynamicIslandEnabled: settingsAdapter.dynamicIslandEnabled
    readonly property bool dynamicIslandHideTopbarTime: settingsAdapter.dynamicIslandHideTopbarTime
    readonly property string dynamicIslandLeftClickAction: settingsAdapter.dynamicIslandLeftClickAction
    readonly property string dynamicIslandRightClickAction: settingsAdapter.dynamicIslandRightClickAction
    readonly property bool dynamicIslandAutoExpandMedia: settingsAdapter.dynamicIslandAutoExpandMedia
    readonly property bool dynamicIslandHoverExpand: settingsAdapter.dynamicIslandHoverExpand
    readonly property real weatherLatitude: settingsAdapter.weatherLatitude
    readonly property real weatherLongitude: settingsAdapter.weatherLongitude
    readonly property string weatherLocationName: settingsAdapter.weatherLocationName
    readonly property bool weatherManualOverride: settingsAdapter.weatherManualOverride
    readonly property string weatherTempUnit: settingsAdapter.weatherTempUnit
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

    function sanitizeState() {
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
            property string screenshotDirectory: ""
            property bool screenshotCopyToClipboard: true
            property bool screenshotOfferActions: true
            property string startupNote: ""
            property bool compositorLayerAnimations: false
            property bool dynamicIslandEnabled: true
            property bool dynamicIslandHideTopbarTime: true
            property string dynamicIslandLeftClickAction: "toggle_media"
            property string dynamicIslandRightClickAction: "control_center"
            property bool dynamicIslandAutoExpandMedia: false
            property bool dynamicIslandHoverExpand: false
            property real weatherLatitude: 0
            property real weatherLongitude: 0
            property string weatherLocationName: ""
            property bool weatherManualOverride: false
            property string weatherTempUnit: "c"
        }
    }
}
