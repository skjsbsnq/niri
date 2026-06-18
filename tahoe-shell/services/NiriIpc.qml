pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// niri IPC backing service.
//
// The event stream is the primary path for stable niri ids, geometry, focus
// timestamps and minimized/floating state. Snapshot polling remains as a
// fallback when the stream is unavailable.

Item {
    id: root
    visible: false

    property var windows: []
    property var windowsById: ({})
    property bool available: false
    property bool refreshInFlight: false
    property string lastError: ""
    property int pollInterval: 1200
    property string lastWindowsJson: ""
    property int eventApplyInterval: 900
    property bool eventStreamReady: false
    property var eventWindowsById: ({})
    property var eventWindowOrder: []

    readonly property var focusedWindow: findFocusedWindow(windows)

    function setValue(name, value) {
        if (root[name] !== value)
            root[name] = value;
    }

    function refresh() {
        if (refreshInFlight || windowProbe.running)
            return;

        refreshInFlight = true;
        windowProbe.running = true;
    }

    function refreshSoon() {
        if (root.eventStreamReady)
            return;
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
        var snapshot = normalizedWindowSnapshot(rawWindows);
        root.applyNormalizedWindows(snapshot.windows, snapshot.byId);
    }

    function normalizedWindowSnapshot(rawWindows) {
        if (!Array.isArray(rawWindows))
            rawWindows = [];

        var next = [];
        var byId = {};
        var order = [];

        for (var i = 0; i < rawWindows.length; i++) {
            var normalized = normalizeWindow(rawWindows[i]);
            if (!normalized)
                continue;

            next.push(normalized);
            var key = String(normalized.id);
            byId[key] = normalized;
            order.push(key);
        }

        return { "windows": next, "byId": byId, "order": order };
    }

    function applyNormalizedWindows(next, byId) {
        windows = next;
        windowsById = byId;
        root.setValue("available", true);
        root.setValue("lastError", "");
    }

    function loadEventWindows(rawWindows) {
        var snapshot = root.normalizedWindowSnapshot(rawWindows);
        root.eventWindowsById = snapshot.byId;
        root.eventWindowOrder = snapshot.order;
        root.applyNormalizedWindows(snapshot.windows, snapshot.byId);
        root.setValue("eventStreamReady", true);
    }

    function applyEventWindows() {
        var next = [];
        var byId = {};
        var seen = {};
        var order = root.eventWindowOrder || [];

        for (var i = 0; i < order.length; i++) {
            var key = String(order[i]);
            var window = root.eventWindowsById[key];
            if (!window || seen[key])
                continue;

            next.push(window);
            byId[key] = window;
            seen[key] = true;
        }

        root.eventWindowOrder = next.map(function(window) { return String(window.id); });
        root.applyNormalizedWindows(next, byId);
        root.setValue("eventStreamReady", true);
    }

    function scheduleEventApply(immediate) {
        if (immediate) {
            eventApplyTimer.stop();
            root.applyEventWindows();
            return;
        }

        if (!eventApplyTimer.running)
            eventApplyTimer.restart();
    }

    function sameWindow(left, right) {
        return JSON.stringify(left) === JSON.stringify(right);
    }

    function setEventFocus(id) {
        var changed = false;
        var target = id === undefined || id === null ? "" : String(id);

        for (var key in root.eventWindowsById) {
            var window = root.eventWindowsById[key];
            if (!window)
                continue;

            var focused = target.length > 0 && String(window.id) === target;
            if (window.isFocused !== focused) {
                window.isFocused = focused;
                changed = true;
            }
        }

        return changed;
    }

    function upsertEventWindow(rawWindow) {
        var normalized = root.normalizeWindow(rawWindow);
        if (!normalized)
            return { "changed": false, "immediate": false };

        var key = String(normalized.id);
        var previous = root.eventWindowsById[key] || null;
        var immediate = !previous || (!!previous.isFocused !== !!normalized.isFocused);
        var changed = !previous || !root.sameWindow(previous, normalized);

        if (normalized.isFocused)
            changed = root.setEventFocus(normalized.id) || changed;

        if (!previous || root.eventWindowOrder.indexOf(key) < 0)
            root.eventWindowOrder.push(key);

        root.eventWindowsById[key] = normalized;
        return { "changed": changed, "immediate": immediate };
    }

    function closeEventWindow(id) {
        var key = String(id);
        if (!root.eventWindowsById[key])
            return false;

        delete root.eventWindowsById[key];
        var nextOrder = [];
        for (var i = 0; i < root.eventWindowOrder.length; i++) {
            if (String(root.eventWindowOrder[i]) !== key)
                nextOrder.push(root.eventWindowOrder[i]);
        }
        root.eventWindowOrder = nextOrder;
        return true;
    }

    function updateEventWindowValue(id, propertyName, value, immediate) {
        var key = String(id);
        var window = root.eventWindowsById[key];
        if (!window)
            return false;

        if (JSON.stringify(window[propertyName]) === JSON.stringify(value))
            return false;

        window[propertyName] = value;
        if (propertyName === "layout")
            window.geometry = root.geometryFromLayout(value);
        root.scheduleEventApply(!!immediate);
        return true;
    }

    function handleEventLine(line) {
        var text = String(line || "").trim();
        if (text.length === 0)
            return;

        try {
            var event = JSON.parse(text);
            if (event.WindowsChanged) {
                root.loadEventWindows(event.WindowsChanged.windows || []);
            } else if (event.WindowOpenedOrChanged) {
                var result = root.upsertEventWindow(event.WindowOpenedOrChanged.window);
                if (result.changed)
                    root.scheduleEventApply(result.immediate);
            } else if (event.WindowClosed) {
                if (root.closeEventWindow(event.WindowClosed.id))
                    root.scheduleEventApply(true);
            } else if (event.WindowFocusChanged) {
                if (root.setEventFocus(event.WindowFocusChanged.id))
                    root.scheduleEventApply(true);
            } else if (event.WindowFocusTimestampChanged) {
                root.updateEventWindowValue(
                    event.WindowFocusTimestampChanged.id,
                    "focusTimestamp",
                    event.WindowFocusTimestampChanged.focus_timestamp,
                    false
                );
            } else if (event.WindowUrgencyChanged) {
                root.updateEventWindowValue(
                    event.WindowUrgencyChanged.id,
                    "isUrgent",
                    !!event.WindowUrgencyChanged.urgent,
                    true
                );
            } else if (event.WindowLayoutsChanged) {
                var changes = event.WindowLayoutsChanged.changes || [];
                var changed = false;
                for (var i = 0; i < changes.length; i++) {
                    if (changes[i] && changes[i].length >= 2)
                        changed = root.updateEventWindowValue(changes[i][0], "layout", changes[i][1], false) || changed;
                }
                if (changed)
                    root.scheduleEventApply(false);
            }
        } catch (error) {
            root.setValue("lastError", String(error));
        }
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
        running: !eventStream.running
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: eventApplyTimer
        interval: root.eventApplyInterval
        repeat: false
        onTriggered: root.applyEventWindows()
    }

    Timer {
        id: eventStreamRestartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (!eventStream.running)
                eventStream.running = true;
        }
    }

    Timer {
        id: refreshDelay
        interval: 160
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: eventStream
        running: true
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                root.handleEventLine(line);
            }
        }
        onStarted: {
            root.setValue("lastError", "");
        }
        onRunningChanged: {
            if (!running && !eventStreamRestartTimer.running)
                eventStreamRestartTimer.restart();
        }
        onExited: function(code, exitStatus) {
            root.setValue("eventStreamReady", false);
            if (code !== 0)
                root.setValue("lastError", "niri event stream exited with code " + code);
        }
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
                if (root.available && text === root.lastWindowsJson) {
                    root.setValue("lastError", "");
                    return;
                }

                try {
                    var parsed = JSON.parse(text);
                    root.lastWindowsJson = text;
                    root.applyWindows(parsed);
                } catch (error) {
                    root.setValue("available", false);
                    root.setValue("lastError", String(error));
                }
            }
        }
        onExited: function(code, exitStatus) {
            root.refreshInFlight = false;
            if (code !== 0) {
                root.setValue("available", false);
                root.setValue("lastError", "niri msg windows exited with code " + code);
            }
        }
    }

    Component.onCompleted: {
        if (!eventStream.running)
            root.refresh();
    }
}
