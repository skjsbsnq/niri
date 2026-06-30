pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.WindowManager

// Unified niri window model.
//
// `niri msg --json event-stream` emits one JSON event per line after an
// initial Handled response. The relevant event shapes are defined in
// niri-ipc/src/lib.rs:
// - {"WindowsChanged":{"windows":[Window...]}}
// - {"WindowOpenedOrChanged":{"window":Window}}
// - {"WindowClosed":{"id":u64}}
// - {"WindowFocusChanged":{"id":u64|null}}
// - {"WindowFocusTimestampChanged":{"id":u64,"focus_timestamp":Timestamp|null}}
// - {"WindowUrgencyChanged":{"id":u64,"urgent":bool}}
// - {"WindowLayoutsChanged":{"changes":[[u64,WindowLayout]...]}}
// - {"WorkspacesChanged":{"workspaces":[Workspace...]}}
//
// Window fields are snake_case in JSON: app_id, workspace_id, is_focused,
// is_floating, is_urgent, is_minimized, layout, focus_timestamp.

Item {
    id: root
    visible: false

    readonly property var toplevels: ToplevelManager.toplevels
    readonly property var toplevelList: ToplevelManager.toplevels.values
    readonly property var activeToplevel: ToplevelManager.activeToplevel
    readonly property var windowsets: WindowManager.windowsets
    readonly property var visibleWindowsets: displayableWindowsets(WindowManager.windowsets)
    readonly property var activeWorkspace: findActiveWorkspace(WindowManager.windowsets)
    readonly property string activeWorkspaceName: workspaceLabel(activeWorkspace, 0)

    property bool available: false
    property string lastError: ""
    property var ipcWindows: []
    property var ipcWindowsById: ({})
    property var eventWindowOrder: []
    property var ipcWorkspaces: []
    property var workspacesById: ({})

    readonly property bool ipcAvailable: available
    readonly property string ipcError: lastError
    readonly property var windowList: mergeWindowModels(toplevelList, ipcWindows)
    readonly property var nonMinimizedWindowList: filteredMinimizedWindows(windowList, false)
    readonly property var minimizedWindowList: filteredMinimizedWindows(windowList, true)
    readonly property var recentWindowList: sortedRecentWindows(windowList)
    readonly property var focusedWindow: findFocusedWindow(windowList)
    readonly property var workspaceList: sortedWorkspaceList(ipcWorkspaces)
    function setValue(name, value) {
        if (root[name] !== value)
            root[name] = value;
    }

    function action(args) {
        if (!args || args.length === 0)
            return;

        Quickshell.execDetached({
            command: ["niri", "msg", "action"].concat(args)
        });
    }

    function windowFromIdOrObject(idOrWindow) {
        if (!idOrWindow)
            return null;

        if (typeof idOrWindow === "object")
            return idOrWindow;

        var id = String(idOrWindow);
        for (var i = 0; i < root.windowList.length; i++) {
            var window = root.windowList[i];
            if (window && String(window.id) === id)
                return window;
        }

        return null;
    }

    function hasWindowId(idOrWindow) {
        var window = windowFromIdOrObject(idOrWindow);
        return !!window && window.id !== undefined && window.id !== null;
    }

    function activate(idOrWindow) {
        var window = windowFromIdOrObject(idOrWindow);
        if (!window)
            return;

        if (window.toplevel) {
            if (window.toplevel.minimized) {
                window.toplevel.minimized = false;
                return;
            }
            if (window.toplevel.activate)
                window.toplevel.activate();
            return;
        }

        if (window.id !== undefined && window.id !== null)
            action(["focus-window", "--id", String(window.id)]);
    }

    function minimize(idOrWindow) {
        var window = windowFromIdOrObject(idOrWindow);
        if (!window)
            return;

        if (window.toplevel) {
            window.toplevel.minimized = true;
            return;
        }

        if (window.id !== undefined && window.id !== null)
            action(["minimize-window", "--id", String(window.id)]);
    }

    function restore(idOrWindow) {
        var window = windowFromIdOrObject(idOrWindow);
        if (!window)
            return;

        if (window.toplevel) {
            window.toplevel.minimized = false;
            if (window.toplevel.activate)
                window.toplevel.activate();
            return;
        }

        if (window.id !== undefined && window.id !== null)
            action(["restore-window", "--id", String(window.id)]);
    }

    function closeWindow(idOrWindow) {
        var window = windowFromIdOrObject(idOrWindow);
        if (!hasWindowId(window))
            return;

        action(["close-window", "--id", String(window.id)]);
    }

    function moveWindowToWorkspace(idOrWindow, workspaceOrReference, focus) {
        var window = windowFromIdOrObject(idOrWindow);
        if (!hasWindowId(window))
            return;

        var reference = typeof workspaceOrReference === "object"
            ? workspaceActionReference(workspaceOrReference, 0)
            : String(workspaceOrReference || "").trim();
        if (reference.length === 0)
            return;

        var shouldFocus = focus === undefined ? false : !!focus;
        action([
            "move-window-to-workspace",
            "--window-id",
            String(window.id),
            "--focus",
            shouldFocus ? "true" : "false",
            reference
        ]);
    }

    function setRectangle(idOrWindow, sourceWindow, x, y, width, height) {
        var window = windowFromIdOrObject(idOrWindow);
        if (!window || !window.toplevel || !window.toplevel.setRectangle)
            return;

        // Support the documented shape setRectangle(id, x, y, w, h) as a
        // no-source fallback, and the Quickshell-required shape
        // setRectangle(id, panelWindow, x, y, w, h) used by Dock/WindowButton.
        if (arguments.length === 5) {
            height = width;
            width = y;
            y = x;
            x = sourceWindow;
            sourceWindow = null;
        }

        if (!sourceWindow)
            return;

        window.toplevel.setRectangle(
            sourceWindow,
            Qt.rect(Math.round(x), Math.round(y), Math.round(width), Math.round(height))
        );
    }

    function activateWindow(window) { activate(window); }
    function minimizeWindow(window) { minimize(window); }
    function restoreWindow(window) { restore(window); }

    function activateWorkspace(workspace) {
        if (workspace && workspace.canActivate) {
            workspace.activate();
            return;
        }

        var label = workspaceLabel(workspace, 0);
        if (label.length > 0)
            action(["focus-workspace", label]);
    }

    function loadWindows(rawWindows) {
        var snapshot = normalizedWindowSnapshot(rawWindows);
        root.eventWindowOrder = snapshot.order;
        root.applyNormalizedWindows(snapshot.windows, snapshot.byId);
    }

    function normalizedWindowSnapshot(rawWindows) {
        if (!Array.isArray(rawWindows))
            rawWindows = [];

        var windows = [];
        var byId = {};
        var order = [];

        for (var i = 0; i < rawWindows.length; i++) {
            var normalized = normalizeIpcWindow(rawWindows[i]);
            if (!normalized)
                continue;

            windows.push(normalized);
            byId[String(normalized.id)] = normalized;
            order.push(String(normalized.id));
        }

        return { "windows": windows, "byId": byId, "order": order };
    }

    function applyNormalizedWindows(windows, byId) {
        root.ipcWindows = windows;
        root.ipcWindowsById = byId;
        root.setValue("available", true);
        root.setValue("lastError", "");
    }

    function applyWindowsFromMap() {
        var windows = [];
        var byId = {};
        var nextOrder = [];
        var seen = {};
        var order = root.eventWindowOrder || [];

        for (var i = 0; i < order.length; i++) {
            var key = String(order[i]);
            var window = root.ipcWindowsById[key];
            if (!window || seen[key])
                continue;

            windows.push(window);
            byId[key] = window;
            nextOrder.push(key);
            seen[key] = true;
        }

        root.eventWindowOrder = nextOrder;
        root.applyNormalizedWindows(windows, byId);
    }

    function upsertWindow(rawWindow) {
        var normalized = normalizeIpcWindow(rawWindow);
        if (!normalized)
            return;

        var key = String(normalized.id);
        if (normalized.isFocused)
            setEventFocus(normalized.id);

        if (root.eventWindowOrder.indexOf(key) < 0)
            root.eventWindowOrder.push(key);

        root.ipcWindowsById[key] = normalized;
        applyWindowsFromMap();
    }

    function removeClosedWindow(id) {
        var key = String(id);
        if (!root.ipcWindowsById[key])
            return;

        delete root.ipcWindowsById[key];
        var nextOrder = [];
        for (var i = 0; i < root.eventWindowOrder.length; i++) {
            if (String(root.eventWindowOrder[i]) !== key)
                nextOrder.push(root.eventWindowOrder[i]);
        }
        root.eventWindowOrder = nextOrder;
        applyWindowsFromMap();
    }

    function setEventFocus(id) {
        var target = id === undefined || id === null ? "" : String(id);
        for (var key in root.ipcWindowsById) {
            var window = root.ipcWindowsById[key];
            if (!window)
                continue;
            window.isFocused = target.length > 0 && String(window.id) === target;
            window.focused = window.isFocused;
        }
    }

    function updateWindowValue(id, propertyName, value) {
        var key = String(id);
        var window = root.ipcWindowsById[key];
        if (!window)
            return;

        window[propertyName] = value;
        if (propertyName === "layout") {
            window.geometry = geometryFromLayout(value);
            window.rect = window.geometry;
        } else if (propertyName === "isUrgent") {
            window.isUrgent = !!value;
            window.urgent = window.isUrgent;
        } else if (propertyName === "focusTimestamp") {
            window.focusTimestamp = value;
        }
        applyWindowsFromMap();
    }

    function loadWorkspaces(rawWorkspaces) {
        var byId = {};
        var normalized = [];
        var workspaces = Array.isArray(rawWorkspaces) ? rawWorkspaces : [];
        for (var i = 0; i < workspaces.length; i++) {
            var workspace = normalizeWorkspace(workspaces[i]);
            if (!workspace || workspace.id === undefined || workspace.id === null)
                continue;

            byId[String(workspace.id)] = workspace;
            normalized.push(workspace);
        }
        root.ipcWorkspaces = normalized;
        root.workspacesById = byId;
        applyWindowsFromMap();
    }

    function handleEventLine(line) {
        var text = String(line || "").trim();
        if (text.length === 0)
            return;

        try {
            var event = JSON.parse(text);
            if (event.WindowsChanged) {
                loadWindows(event.WindowsChanged.windows || []);
            } else if (event.WindowOpenedOrChanged) {
                upsertWindow(event.WindowOpenedOrChanged.window);
            } else if (event.WindowClosed) {
                removeClosedWindow(event.WindowClosed.id);
            } else if (event.WindowFocusChanged) {
                setEventFocus(event.WindowFocusChanged.id);
                applyWindowsFromMap();
            } else if (event.WindowFocusTimestampChanged) {
                updateWindowValue(
                    event.WindowFocusTimestampChanged.id,
                    "focusTimestamp",
                    event.WindowFocusTimestampChanged.focus_timestamp
                );
            } else if (event.WindowUrgencyChanged) {
                updateWindowValue(
                    event.WindowUrgencyChanged.id,
                    "isUrgent",
                    !!event.WindowUrgencyChanged.urgent
                );
            } else if (event.WindowLayoutsChanged) {
                var changes = event.WindowLayoutsChanged.changes || [];
                for (var i = 0; i < changes.length; i++) {
                    if (changes[i] && changes[i].length >= 2)
                        updateWindowValue(changes[i][0], "layout", changes[i][1]);
                }
            } else if (event.WorkspacesChanged) {
                loadWorkspaces(event.WorkspacesChanged.workspaces || []);
            }
        } catch (error) {
            root.setValue("lastError", String(error));
        }
    }

    function mergeWindowModels(toplevels, ipcWindows) {
        var result = [];
        var usedToplevels = {};
        var list = toplevels || [];
        var ipcList = ipcWindows || [];

        for (var i = 0; i < ipcList.length; i++) {
            var ipcWindow = ipcList[i];
            if (!ipcWindow)
                continue;

            var match = findMatchingToplevel(ipcWindow, list, usedToplevels);
            if (match.index !== -1)
                usedToplevels[String(match.index)] = true;

            result.push(buildWindowModel(ipcWindow, match.toplevel, i));
        }

        for (var j = 0; j < list.length; j++) {
            if (usedToplevels[String(j)])
                continue;

            result.push(buildWindowModel(null, list[j], j));
        }

        return result;
    }

    function filteredMinimizedWindows(windows, minimized) {
        var result = [];
        var list = windows || [];
        for (var i = 0; i < list.length; i++) {
            var window = list[i];
            if (!window)
                continue;
            if (!!window.isMinimized === !!minimized)
                result.push(window);
        }
        return result;
    }

    function sortedWorkspaceList(workspaces) {
        var result = (workspaces || []).slice();
        result.sort(function(left, right) {
            var leftOutput = String(left && left.output ? left.output : "");
            var rightOutput = String(right && right.output ? right.output : "");
            if (leftOutput < rightOutput)
                return -1;
            if (leftOutput > rightOutput)
                return 1;

            var leftIndex = workspaceSortIndex(left, 0);
            var rightIndex = workspaceSortIndex(right, 0);
            if (leftIndex !== rightIndex)
                return leftIndex - rightIndex;

            return Number(left && left.id || 0) - Number(right && right.id || 0);
        });
        return result;
    }

    function buildWindowModel(ipcWindow, toplevel, fallbackIndex) {
        var title = ipcWindow && ipcWindow.title ? ipcWindow.title : toplevelText(toplevel, "title");
        var appId = ipcWindow && ipcWindow.appId ? ipcWindow.appId : toplevelText(toplevel, "appId");
        var workspace = ipcWindow ? workspaceFromId(ipcWindow.workspaceId) : null;
        var focused = ipcWindow ? ipcWindow.isFocused : !!(toplevel && toplevel.activated);
        var minimized = ipcWindow ? ipcWindow.isMinimized : !!(toplevel && toplevel.minimized);
        var geometry = ipcWindow ? ipcWindow.geometry : null;

        return {
            "id": ipcWindow ? ipcWindow.id : null,
            "modelKey": windowModelKey(ipcWindow, toplevel, fallbackIndex),
            "title": title,
            "appId": appId,
            "workspace": workspace,
            "workspaceId": ipcWindow ? ipcWindow.workspaceId : null,
            "output": workspace ? String(workspace.output || "") : "",
            "pid": ipcWindow ? ipcWindow.pid : null,
            "focused": focused,
            "isFocused": focused,
            "minimized": minimized,
            "isMinimized": minimized,
            "isFloating": ipcWindow ? ipcWindow.isFloating : false,
            "isUrgent": ipcWindow ? ipcWindow.isUrgent : false,
            "urgent": ipcWindow ? ipcWindow.isUrgent : false,
            "layout": ipcWindow ? ipcWindow.layout : null,
            "geometry": geometry,
            "rect": geometry,
            "focusTimestamp": ipcWindow ? ipcWindow.focusTimestamp : null,
            "ipcWindow": ipcWindow,
            "toplevel": toplevel
        };
    }

    function windowModelKey(ipcWindow, toplevel, fallbackIndex) {
        if (ipcWindow && ipcWindow.id !== undefined && ipcWindow.id !== null)
            return "id:" + String(ipcWindow.id);

        var appId = toplevelText(toplevel, "appId");
        return "toplevel:" + appId + ":" + String(fallbackIndex || 0);
    }

    function findMatchingToplevel(ipcWindow, toplevels, usedToplevels) {
        var result = { "index": -1, "toplevel": null };
        if (!ipcWindow || !toplevels)
            return result;

        var appId = normalizeIdentity(ipcWindow.appId);
        var title = normalizeTitle(ipcWindow.title);

        for (var i = 0; i < toplevels.length; i++) {
            if (usedToplevels[String(i)])
                continue;

            var toplevel = toplevels[i];
            if (!toplevel)
                continue;

            if (appId.length > 0
                    && appId === normalizeIdentity(toplevel.appId)
                    && title.length > 0
                    && title === normalizeTitle(toplevel.title)) {
                result.index = i;
                result.toplevel = toplevel;
                return result;
            }
        }

        for (var j = 0; j < toplevels.length; j++) {
            if (usedToplevels[String(j)])
                continue;

            var candidate = toplevels[j];
            if (candidate && appId.length > 0 && appId === normalizeIdentity(candidate.appId)) {
                result.index = j;
                result.toplevel = candidate;
                return result;
            }
        }

        return result;
    }

    function normalizeIpcWindow(raw) {
        if (!raw)
            return null;

        var id = asOptionalNumber(raw.id);
        if (id === null)
            return null;

        var layout = raw.layout || {};
        var workspaceId = asOptionalNumber(raw.workspace_id !== undefined ? raw.workspace_id : raw.workspaceId);
        var geometry = geometryFromLayout(layout);
        var focused = !!(raw.is_focused !== undefined ? raw.is_focused : raw.isFocused);
        var minimized = !!(raw.is_minimized !== undefined ? raw.is_minimized : raw.isMinimized);

        return {
            "id": id,
            "title": textOrEmpty(raw.title),
            "appId": textOrEmpty(raw.app_id !== undefined ? raw.app_id : raw.appId),
            "pid": asOptionalNumber(raw.pid),
            "workspaceId": workspaceId,
            "workspace": workspaceFromId(workspaceId),
            "output": outputFromWorkspaceId(workspaceId),
            "focused": focused,
            "isFocused": focused,
            "minimized": minimized,
            "isMinimized": minimized,
            "isFloating": !!(raw.is_floating !== undefined ? raw.is_floating : raw.isFloating),
            "isUrgent": !!(raw.is_urgent !== undefined ? raw.is_urgent : raw.isUrgent),
            "layout": layout,
            "geometry": geometry,
            "rect": geometry,
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

        var width = Math.max(0, Number(size[0]) || 0);
        var height = Math.max(0, Number(size[1]) || 0);
        return {
            "x": Number(pos[0]) || 0,
            "y": Number(pos[1]) || 0,
            "w": width,
            "h": height,
            "width": width,
            "height": height
        };
    }

    function workspaceFromId(id) {
        if (id === undefined || id === null)
            return null;
        return root.workspacesById[String(id)] || null;
    }

    function outputFromWorkspaceId(id) {
        var workspace = workspaceFromId(id);
        return workspace ? String(workspace.output || "") : "";
    }

    function workspaceLabel(workspace, fallbackIndex) {
        if (!workspace)
            return "1";

        var name = String(workspace.name || "").trim();
        if (name.length > 0)
            return name;

        var id = String(workspace.id || "").trim();
        if (id.length > 0)
            return id;

        if (workspace.coordinates && workspace.coordinates.length > 0)
            return String(workspace.coordinates[0] + 1);

        return String((fallbackIndex || 0) + 1);
    }

    function workspaceDisplayLabel(workspace, fallbackIndex) {
        if (!workspace)
            return "工作区";

        var name = String(workspace.name || "").trim();
        if (name.length > 0)
            return name;

        var index = workspaceSortIndex(workspace, fallbackIndex);
        if (index > 0)
            return "工作区 " + String(index);

        var id = String(workspace.id || "").trim();
        return id.length > 0 ? "工作区 " + id : "工作区";
    }

    function workspaceActionReference(workspace, fallbackIndex) {
        if (!workspace)
            return "";

        var name = String(workspace.name || "").trim();
        if (name.length > 0)
            return name;

        var index = workspaceSortIndex(workspace, fallbackIndex);
        if (index > 0)
            return String(index);

        var id = String(workspace.id || "").trim();
        return id;
    }

    function workspaceSortIndex(workspace, fallbackIndex) {
        if (!workspace)
            return (fallbackIndex || 0) + 1;

        var idx = Number(workspace.idx);
        if (isFinite(idx) && idx > 0)
            return idx;

        if (workspace.coordinates && workspace.coordinates.length > 0) {
            var coordinate = Number(workspace.coordinates[0]);
            if (isFinite(coordinate))
                return coordinate + 1;
        }

        var id = Number(workspace.id);
        if (isFinite(id) && id > 0)
            return id;

        return (fallbackIndex || 0) + 1;
    }

    function isWindowOnWorkspace(window, workspace) {
        window = windowFromIdOrObject(window);
        if (!window || !workspace)
            return false;
        if (window.workspaceId === undefined || window.workspaceId === null)
            return false;
        if (workspace.id === undefined || workspace.id === null)
            return false;
        return String(window.workspaceId) === String(workspace.id);
    }

    function displayableWindowsets(windowsets) {
        var result = [];
        if (!windowsets)
            return result;

        for (var i = 0; i < windowsets.length; i++) {
            var workspace = windowsets[i];
            if (!workspace)
                continue;
            if (workspace.shouldDisplay === false)
                continue;

            result.push(workspace);
        }

        return result;
    }

    function findActiveWorkspace(windowsets) {
        if (!windowsets)
            return null;

        for (var i = 0; i < windowsets.length; i++) {
            if (windowsets[i] && windowsets[i].active)
                return windowsets[i];
        }

        return windowsets.length > 0 ? windowsets[0] : null;
    }

    function sortedRecentWindows(windows) {
        var result = (windows || []).slice();
        result.sort(function(left, right) {
            if (!!left.isFocused !== !!right.isFocused)
                return left.isFocused ? -1 : 1;

            return focusTimestampValue(right) - focusTimestampValue(left);
        });
        return result;
    }

    function focusTimestampValue(window) {
        if (!window || !window.focusTimestamp)
            return 0;

        var secs = Number(window.focusTimestamp.secs || 0);
        var nanos = Number(window.focusTimestamp.nanos || 0);
        return secs + nanos / 1000000000;
    }

    function findFocusedWindow(windows) {
        if (!windows)
            return null;

        for (var i = 0; i < windows.length; i++) {
            if (windows[i] && windows[i].isFocused)
                return windows[i];
        }

        return null;
    }

    function normalizeIdentity(value) {
        return String(value || "").trim().toLowerCase();
    }

    function normalizeTitle(value) {
        return String(value || "").trim();
    }

    function toplevelText(toplevel, propertyName) {
        if (!toplevel)
            return "";

        return String(toplevel[propertyName] || "").trim();
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

    function normalizeWorkspace(raw) {
        if (!raw)
            return null;

        var id = asOptionalNumber(raw.id);
        if (id === null)
            return null;

        return {
            "id": id,
            "idx": asOptionalNumber(raw.idx),
            "name": textOrEmpty(raw.name),
            "output": textOrEmpty(raw.output),
            "isActive": !!(raw.is_active !== undefined ? raw.is_active : raw.isActive),
            "isFocused": !!(raw.is_focused !== undefined ? raw.is_focused : raw.isFocused),
            "isUrgent": !!(raw.is_urgent !== undefined ? raw.is_urgent : raw.isUrgent),
            "activeWindowId": asOptionalNumber(raw.active_window_id !== undefined ? raw.active_window_id : raw.activeWindowId),
            "coordinates": raw.coordinates || null
        };
    }

    Timer {
        id: eventStreamRestartTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!eventStream.running)
                eventStream.running = true;
        }
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
            root.setValue("available", false);
            if (code !== 0)
                root.setValue("lastError", "niri event-stream exited with code " + code);
        }
    }
}
