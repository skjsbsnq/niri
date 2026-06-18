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

    function validDockWindowTitleMode(value) {
        return value === "auto" || value === "icons" || value === "titles";
    }

    function modeLabel(mode) {
        if (mode === "icons")
            return "仅图标";
        if (mode === "titles")
            return "标题优先";
        return "自动";
    }

    function setDockWindowTitleMode(mode) {
        var next = validDockWindowTitleMode(mode) ? mode : "auto";
        if (settingsAdapter.dockWindowTitleMode === next)
            return;

        settingsAdapter.dockWindowTitleMode = next;
        settingsFile.writeAdapter();
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
            property string screenshotDirectory: ""
            property bool screenshotCopyToClipboard: true
            property bool screenshotOfferActions: true
            property string startupNote: ""
        }
    }
}
