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
        return value === "static" || value === "dynamic";
    }

    function clampInt(value, minimum, maximum, fallback) {
        var number = Math.round(Number(value));
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
            return "动态";
        return "静态";
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
            property string wallpaperMode: "static"
            property string staticWallpaperPath: ""
            property string dynamicWallpaperCommand: ""
            property string screenshotDirectory: ""
            property bool screenshotCopyToClipboard: true
            property bool screenshotOfferActions: true
            property string startupNote: ""
        }
    }
}
