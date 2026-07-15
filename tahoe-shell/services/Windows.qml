pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.WindowManager
import "windows/WindowModel.js" as WindowModel

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
// - {"WorkspaceActivated":{"id":u64,"focused":bool}}
// - {"WorkspaceUrgencyChanged":{"id":u64,"urgent":bool}}
// - {"WorkspaceActiveWindowChanged":{"workspace_id":u64,"active_window_id":u64|null}}
//
// Window fields are snake_case in JSON: app_id, workspace_id, is_focused,
// is_floating, is_urgent, is_minimized, layout, focus_timestamp.
// Workspace idx is the user-visible per-output index and changes on reorder;
// workspace id is the stable niri entity key.

Item {
    id: root
    visible: false

    readonly property var toplevels: ToplevelManager.toplevels
    readonly property var toplevelList: ToplevelManager.toplevels.values
    readonly property var activeToplevel: ToplevelManager.activeToplevel
    readonly property var windowsets: WindowManager.windowsets
    readonly property var visibleWindowsets: displayableWindowsets(WindowManager.windowsets)
    // Prefer the IPC-focused workspace (niri EventStream). Fall back to
    // Quickshell WindowManager only before the first WorkspacesChanged baseline.
    readonly property var activeWorkspace: findIpcFocusedWorkspace(ipcWorkspaces)
        || findActiveWorkspace(WindowManager.windowsets)
    readonly property string activeWorkspaceName: workspaceLabel(activeWorkspace, 0)
    readonly property string focusedOutputName: WindowModel.focusedOutputName(ipcWorkspaces)

    property bool available: false
    property string lastError: ""
    property var ipcWindows: []
    property var ipcWindowsById: ({})
    property var eventWindowOrder: []
    property var ipcWorkspaces: []
    property var workspacesById: ({})
    // Cached merge results. WindowLayoutsChanged can fire every compositor
    // frame during resize/move; recomputing merge + filtered/recent lists on
    // every event made Dock/TopBar/Overview rebuild constantly.
    property var windowList: []
    property var nonMinimizedWindowList: []
    property var minimizedWindowList: []
    property var recentWindowList: []
    property var focusedWindow: null
    property bool layoutPatchPending: false

    readonly property bool ipcAvailable: available
    readonly property string ipcError: lastError
    readonly property var workspaceList: sortedWorkspaceList(ipcWorkspaces)

    onToplevelListChanged: rebuildMergedWindows()
    Component.onCompleted: rebuildMergedWindows()

    // Coalesce layout publishes to ~one shell paint. ipc state is still updated
    // immediately; only the QML model identity refresh is deferred.
    Timer {
        id: layoutPatchTimer
        interval: 16
        repeat: false
        onTriggered: {
            root.layoutPatchPending = false;
            root.patchMergedWindowLayouts();
        }
    }

    function setValue(name, value) {
        if (root[name] !== value)
            root[name] = value;
    }

    function scheduleLayoutPatch() {
        root.layoutPatchPending = true;
        if (!layoutPatchTimer.running)
            layoutPatchTimer.start();
    }

    function rebuildMergedWindows() {
        // Membership/focus changes must not race a deferred layout publish.
        layoutPatchTimer.stop();
        root.layoutPatchPending = false;
        var merged = mergeWindowModels(root.toplevelList, root.ipcWindows);
        root.windowList = merged;
        root.nonMinimizedWindowList = filteredMinimizedWindows(merged, false);
        root.minimizedWindowList = filteredMinimizedWindows(merged, true);
        root.recentWindowList = sortedRecentWindows(merged);
        root.focusedWindow = findFocusedWindow(merged);
    }

    // Layout-only path: keep window membership/order stable and only refresh
    // geometry fields. Avoids O(windows²) rematch against toplevels every frame.
    function patchMergedWindowLayouts() {
        var list = root.windowList || [];
        if (list.length === 0)
            return;

        var next = null;
        for (var i = 0; i < list.length; i++) {
            var model = list[i];
            if (!model || model.id === undefined || model.id === null)
                continue;

            var ipc = root.ipcWindowsById[String(model.id)];
            if (!ipc)
                continue;

            if (WindowModel.sameLayout(model.layout, ipc.layout)
                    && WindowModel.sameGeometry(model.geometry, ipc.geometry))
                continue;

            if (!next)
                next = list.slice();

            next[i] = {
                "id": model.id,
                "modelKey": model.modelKey,
                "title": model.title,
                "appId": model.appId,
                "workspace": model.workspace,
                "workspaceId": model.workspaceId,
                "output": model.output,
                "pid": model.pid,
                "focused": model.focused,
                "isFocused": model.isFocused,
                "minimized": model.minimized,
                "isMinimized": model.isMinimized,
                "isFloating": model.isFloating,
                "isUrgent": model.isUrgent,
                "urgent": model.urgent,
                "layout": ipc.layout,
                "geometry": ipc.geometry,
                "rect": ipc.geometry,
                "focusTimestamp": model.focusTimestamp,
                "ipcWindow": ipc,
                "toplevel": model.toplevel
            };
        }

        if (next) {
            root.windowList = next;
            // Membership unchanged; refresh derived views so they share the
            // patched model objects (geometry consumers / overview / dock).
            root.nonMinimizedWindowList = filteredMinimizedWindows(next, false);
            root.minimizedWindowList = filteredMinimizedWindows(next, true);
            // Keep public API identity consistent with windowList (no orphan
            // pre-patch objects for focused/recent consumers).
            root.focusedWindow = findFocusedWindow(next);
            root.recentWindowList = sortedRecentWindows(next);
        }
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
        return WindowModel.normalizedWindowSnapshot(rawWindows, root.workspacesById);
    }

    function applyNormalizedWindows(windows, byId, options) {
        root.ipcWindows = windows;
        root.ipcWindowsById = byId;
        root.setValue("available", true);
        root.setValue("lastError", "");

        var mode = options && options.mode ? options.mode : "full";
        if (mode === "layout")
            root.scheduleLayoutPatch();
        else
            root.rebuildMergedWindows();
    }

    function applyWindowsFromMap(options) {
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
        root.applyNormalizedWindows(windows, byId, options);
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
        applyWindowsFromMap({ "mode": "full" });
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
        applyWindowsFromMap({ "mode": "full" });
    }

    function setEventFocus(id) {
        var target = id === undefined || id === null ? "" : String(id);
        var changed = false;
        for (var key in root.ipcWindowsById) {
            var window = root.ipcWindowsById[key];
            if (!window)
                continue;
            var focused = target.length > 0 && String(window.id) === target;
            if (window.isFocused !== focused || window.focused !== focused) {
                window.isFocused = focused;
                window.focused = focused;
                changed = true;
            }
        }
        return changed;
    }

    function updateWindowValue(id, propertyName, value) {
        var key = String(id);
        var window = root.ipcWindowsById[key];
        if (!window)
            return false;

        if (propertyName === "layout") {
            if (WindowModel.sameLayout(window.layout, value))
                return false;
            window.layout = value;
            window.geometry = geometryFromLayout(value);
            window.rect = window.geometry;
            return true;
        }

        if (propertyName === "isUrgent") {
            var urgent = !!value;
            if (window.isUrgent === urgent && window.urgent === urgent)
                return false;
            window.isUrgent = urgent;
            window.urgent = urgent;
            return true;
        }

        if (propertyName === "focusTimestamp") {
            if (WindowModel.sameFocusTimestamp(window.focusTimestamp, value))
                return false;
            window.focusTimestamp = value;
            return true;
        }

        if (window[propertyName] === value)
            return false;
        window[propertyName] = value;
        return true;
    }

    function applyLayoutChanges(changes) {
        var list = Array.isArray(changes) ? changes : [];
        var changed = false;
        for (var i = 0; i < list.length; i++) {
            if (!list[i] || list[i].length < 2)
                continue;
            if (updateWindowValue(list[i][0], "layout", list[i][1]))
                changed = true;
        }
        if (changed)
            applyWindowsFromMap({ "mode": "layout" });
    }

    function publishWorkspaces(normalized) {
        var list = Array.isArray(normalized) ? normalized : [];
        var byId = {};
        for (var i = 0; i < list.length; i++) {
            var workspace = list[i];
            if (!workspace || workspace.id === undefined || workspace.id === null)
                continue;
            byId[String(workspace.id)] = workspace;
        }
        root.ipcWorkspaces = list;
        root.workspacesById = byId;
    }

    function clearIpcWorkspaceBaseline() {
        // Used on event-stream exit/reconnect so stale isFocused rows cannot
        // mask WindowManager fallback before the next WorkspacesChanged.
        if ((root.ipcWorkspaces || []).length === 0
                && Object.keys(root.workspacesById || {}).length === 0)
            return;
        root.ipcWorkspaces = [];
        root.workspacesById = ({});
    }

    function loadWorkspaces(rawWorkspaces) {
        var normalized = [];
        var workspaces = Array.isArray(rawWorkspaces) ? rawWorkspaces : [];
        for (var i = 0; i < workspaces.length; i++) {
            var workspace = normalizeWorkspace(workspaces[i]);
            if (!workspace || workspace.id === undefined || workspace.id === null)
                continue;
            normalized.push(workspace);
        }
        publishWorkspaces(normalized);
        // Structure baseline: re-merge windows so workspace/output labels refresh.
        applyWindowsFromMap({ "mode": "full" });
    }

    function applyWorkspaceList(nextWorkspaces, options) {
        if (!nextWorkspaces)
            return false;

        publishWorkspaces(nextWorkspaces);
        var mode = options && options.mode ? options.mode : "activation";
        if (mode === "full")
            applyWindowsFromMap({ "mode": "full" });
        return true;
    }

    function activeWorkspaceForOutput(outputName) {
        return WindowModel.activeWorkspaceForOutput(root.ipcWorkspaces, outputName);
    }

    function activeWorkspaceIndexForOutput(outputName) {
        return WindowModel.activeWorkspaceIndexForOutput(root.ipcWorkspaces, outputName);
    }

    function findIpcFocusedWorkspace(workspaces) {
        return WindowModel.findFocusedWorkspace(workspaces);
    }

    // Output hotplug: niri emits full WorkspacesChanged when outputs or
    // workspace membership change (ipc/server.rs need_workspaces_changed).
    // That structural baseline is the primary cleanup path. pruneStale* is an
    // optional local helper for tests or future screen-model wiring.
    function pruneStaleOutputWorkspaces(connectedOutputs) {
        var next = WindowModel.pruneWorkspacesForOutputs(root.ipcWorkspaces, connectedOutputs);
        if (!next)
            return false;
        // Only publish when membership actually changes.
        if (next.length === (root.ipcWorkspaces || []).length) {
            var same = true;
            for (var i = 0; i < next.length; i++) {
                if (!root.ipcWorkspaces[i] || String(next[i].id) !== String(root.ipcWorkspaces[i].id)) {
                    same = false;
                    break;
                }
            }
            if (same)
                return false;
        }
        return applyWorkspaceList(next, { "mode": "full" });
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
                if (setEventFocus(event.WindowFocusChanged.id))
                    applyWindowsFromMap({ "mode": "full" });
            } else if (event.WindowFocusTimestampChanged) {
                if (updateWindowValue(
                        event.WindowFocusTimestampChanged.id,
                        "focusTimestamp",
                        event.WindowFocusTimestampChanged.focus_timestamp
                    )) {
                    applyWindowsFromMap({ "mode": "full" });
                }
            } else if (event.WindowUrgencyChanged) {
                if (updateWindowValue(
                        event.WindowUrgencyChanged.id,
                        "isUrgent",
                        !!event.WindowUrgencyChanged.urgent
                    )) {
                    applyWindowsFromMap({ "mode": "full" });
                }
            } else if (event.WindowLayoutsChanged) {
                applyLayoutChanges(event.WindowLayoutsChanged.changes || []);
            } else if (event.WorkspacesChanged) {
                loadWorkspaces(event.WorkspacesChanged.workspaces || []);
            } else if (event.WorkspaceActivated) {
                applyWorkspaceList(WindowModel.applyWorkspaceActivated(
                    root.ipcWorkspaces,
                    event.WorkspaceActivated.id,
                    !!event.WorkspaceActivated.focused
                ), { "mode": "activation" });
            } else if (event.WorkspaceUrgencyChanged) {
                applyWorkspaceList(WindowModel.applyWorkspaceUrgencyChanged(
                    root.ipcWorkspaces,
                    event.WorkspaceUrgencyChanged.id,
                    !!event.WorkspaceUrgencyChanged.urgent
                ), { "mode": "activation" });
            } else if (event.WorkspaceActiveWindowChanged) {
                applyWorkspaceList(WindowModel.applyWorkspaceActiveWindowChanged(
                    root.ipcWorkspaces,
                    event.WorkspaceActiveWindowChanged.workspace_id,
                    event.WorkspaceActiveWindowChanged.active_window_id
                ), { "mode": "activation" });
            }
        } catch (error) {
            root.setValue("lastError", String(error));
        }
    }

    function mergeWindowModels(toplevels, ipcWindows) {
        return WindowModel.mergeWindowModels(toplevels, ipcWindows, root.workspacesById);
    }

    function filteredMinimizedWindows(windows, minimized) {
        return WindowModel.filteredMinimizedWindows(windows, minimized);
    }

    function sortedWorkspaceList(workspaces) {
        return WindowModel.sortedWorkspaceList(workspaces);
    }

    function buildWindowModel(ipcWindow, toplevel, fallbackIndex) {
        return WindowModel.buildWindowModel(ipcWindow, toplevel, fallbackIndex, root.workspacesById);
    }

    function windowModelKey(ipcWindow, toplevel, fallbackIndex) {
        return WindowModel.windowModelKey(ipcWindow, toplevel, fallbackIndex);
    }

    function findMatchingToplevel(ipcWindow, toplevels, usedToplevels) {
        return WindowModel.findMatchingToplevel(ipcWindow, toplevels, usedToplevels);
    }

    function normalizeIpcWindow(raw) {
        return WindowModel.normalizeIpcWindow(raw, root.workspacesById);
    }

    function geometryFromLayout(layout) {
        return WindowModel.geometryFromLayout(layout);
    }

    function workspaceFromId(id) {
        return WindowModel.workspaceFromId(id, root.workspacesById);
    }

    function outputFromWorkspaceId(id) {
        var workspace = WindowModel.workspaceFromId(id, root.workspacesById);
        return workspace ? String(workspace.output || "") : "";
    }

    function workspaceLabel(workspace, fallbackIndex) {
        if (!workspace)
            return "1";

        var name = String(workspace.name || "").trim();
        if (name.length > 0)
            return name;

        // User-visible ordinal: prefer niri idx (per-output index). Stable entity
        // id must not be used as a display/action reference — idx changes on
        // reorder while id stays fixed; users expect the 1-based number.
        var index = workspaceSortIndex(workspace, fallbackIndex);
        if (index > 0)
            return String(index);

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
        return WindowModel.workspaceSortIndex(workspace, fallbackIndex);
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
        return WindowModel.sortedRecentWindows(windows);
    }

    function focusTimestampValue(window) {
        return WindowModel.focusTimestampValue(window);
    }

    function findFocusedWindow(windows) {
        return WindowModel.findFocusedWindow(windows);
    }

    function normalizeIdentity(value) {
        return WindowModel.normalizeIdentity(value);
    }

    function normalizeTitle(value) {
        return WindowModel.normalizeTitle(value);
    }

    function toplevelText(toplevel, propertyName) {
        return WindowModel.toplevelText(toplevel, propertyName);
    }

    function textOrEmpty(value) {
        return WindowModel.textOrEmpty(value);
    }

    function asOptionalNumber(value) {
        return WindowModel.asOptionalNumber(value);
    }

    function normalizeWorkspace(raw) {
        return WindowModel.normalizeWorkspace(raw);
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
            // Drop any pre-reconnect IPC snapshot so focused queries fall back
            // to WindowManager until niri replicate() sends WorkspacesChanged.
            root.clearIpcWorkspaceBaseline();
            root.setValue("lastError", "");
        }
        onRunningChanged: {
            if (!running && !eventStreamRestartTimer.running)
                eventStreamRestartTimer.restart();
        }
        onExited: function(code, exitStatus) {
            root.setValue("available", false);
            root.clearIpcWorkspaceBaseline();
            if (code !== 0)
                root.setValue("lastError", "niri event-stream exited with code " + code);
        }
    }
}
