pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// niri IPC backing service.
//
// First version intentionally uses a cheap `niri msg --json windows` snapshot
// with light polling. This gives the shell stable niri ids, geometry, focus
// timestamps and minimized/floating state without committing the UI to a long
// event-stream parser yet. Event stream can replace the polling later while
// keeping this public model intact.

Item {
    id: root
    visible: false

    property var windows: []
    property var windowsById: ({})
    property bool available: false
    property bool refreshInFlight: false
    property string lastError: ""
    property int pollInterval: 1200

    readonly property var focusedWindow: findFocusedWindow(windows)

    function refresh() {
        if (refreshInFlight || windowProbe.running)
            return;

        refreshInFlight = true;
        windowProbe.running = true;
    }

    function refreshSoon() {
        refreshDelay.restart();
    }

    function action(args) {
        if (!args || args.length === 0)
            return;

        Quickshell.execDetached({
            command: ["niri", "msg", "action"].concat(args)
        });
        refreshSoon();
    }

    function focusWindow(id) {
        if (id === undefined || id === null)
            return;

        action(["focus-window", "--id", String(id)]);
    }

    function minimizeWindow(id) {
        if (id === undefined || id === null)
            return;

        action(["minimize-window", "--id", String(id)]);
    }

    function restoreWindow(id) {
        if (id === undefined || id === null)
            return;

        action(["restore-window", "--id", String(id)]);
    }

    function applyWindows(rawWindows) {
        if (!Array.isArray(rawWindows))
            rawWindows = [];

        var next = [];
        var byId = {};

        for (var i = 0; i < rawWindows.length; i++) {
            var normalized = normalizeWindow(rawWindows[i]);
            if (!normalized)
                continue;

            next.push(normalized);
            byId[String(normalized.id)] = normalized;
        }

        windows = next;
        windowsById = byId;
        available = true;
        lastError = "";
    }

    function normalizeWindow(raw) {
        if (!raw)
            return null;

        var id = asOptionalNumber(raw.id);
        if (id === null)
            return null;

        var layout = raw.layout || {};
        return {
            "id": id,
            "title": textOrEmpty(raw.title),
            "appId": textOrEmpty(raw.app_id !== undefined ? raw.app_id : raw.appId),
            "pid": asOptionalNumber(raw.pid),
            "workspaceId": asOptionalNumber(raw.workspace_id !== undefined ? raw.workspace_id : raw.workspaceId),
            "isFocused": !!(raw.is_focused !== undefined ? raw.is_focused : raw.isFocused),
            "isFloating": !!(raw.is_floating !== undefined ? raw.is_floating : raw.isFloating),
            "isUrgent": !!(raw.is_urgent !== undefined ? raw.is_urgent : raw.isUrgent),
            "isMinimized": !!(raw.is_minimized !== undefined ? raw.is_minimized : raw.isMinimized),
            "layout": layout,
            "geometry": geometryFromLayout(layout),
            "focusTimestamp": raw.focus_timestamp !== undefined ? raw.focus_timestamp : raw.focusTimestamp
        };
    }

    function geometryFromLayout(layout) {
        if (!layout)
            return null;

        var pos = layout.tile_pos_in_workspace_view !== undefined
            ? layout.tile_pos_in_workspace_view
            : layout.tilePosInWorkspaceView;
        var size = layout.tile_size !== undefined
            ? layout.tile_size
            : layout.tileSize;

        if ((!size || size.length < 2) && layout.window_size)
            size = layout.window_size;
        if ((!size || size.length < 2) && layout.windowSize)
            size = layout.windowSize;

        if (!pos || pos.length < 2 || !size || size.length < 2)
            return null;

        return {
            "x": Number(pos[0]) || 0,
            "y": Number(pos[1]) || 0,
            "width": Math.max(0, Number(size[0]) || 0),
            "height": Math.max(0, Number(size[1]) || 0)
        };
    }

    function textOrEmpty(value) {
        if (value === undefined || value === null)
            return "";

        return String(value);
    }

    function asOptionalNumber(value) {
        if (value === undefined || value === null)
            return null;

        var number = Number(value);
        return isFinite(number) ? number : null;
    }

    function focusTimestampValue(window) {
        if (!window || !window.focusTimestamp)
            return 0;

        var secs = Number(window.focusTimestamp.secs || 0);
        var nanos = Number(window.focusTimestamp.nanos || 0);
        return secs + nanos / 1000000000;
    }

    function findFocusedWindow(list) {
        if (!list)
            return null;

        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].isFocused)
                return list[i];
        }

        return null;
    }

    Timer {
        interval: root.pollInterval
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshDelay
        interval: 160
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: windowProbe
        running: false
        command: ["niri", "msg", "--json", "windows"]
        stdout: StdioCollector {
            id: windowOut
            onStreamFinished: {
                var text = String(windowOut.text || "").trim();
                if (text.length === 0)
                    return;

                try {
                    root.applyWindows(JSON.parse(text));
                } catch (error) {
                    root.available = false;
                    root.lastError = String(error);
                }
            }
        }
        onExited: function(code, exitStatus) {
            root.refreshInFlight = false;
            if (code !== 0) {
                root.available = false;
                root.lastError = "niri msg windows exited with code " + code;
            }
        }
    }

    Component.onCompleted: refresh()
}
