pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import Quickshell.WindowManager

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
    readonly property bool ipcAvailable: ipc.available
    readonly property string ipcError: ipc.lastError
    readonly property var ipcWindows: ipc.windows
    readonly property var windowList: mergeWindowModels(toplevelList, ipc.windows)
    readonly property var recentWindowList: sortedRecentWindows(windowList)
    readonly property var focusedWindow: findFocusedWindow(windowList)

    NiriIpc {
        id: ipc
    }

    function activateToplevel(toplevel) {
        if (!toplevel)
            return;

        if (toplevel.minimized) {
            toplevel.minimized = false;
            return;
        }

        if (toplevel.activate)
            toplevel.activate();
    }

    function activateWindow(window) {
        if (!window)
            return;

        if (window.toplevel) {
            activateToplevel(window.toplevel);
            return;
        }

        if (window.id !== undefined && window.id !== null)
            ipc.focusWindow(window.id);
    }

    function minimizeWindow(window) {
        if (!window)
            return;

        if (window.toplevel) {
            window.toplevel.minimized = true;
            return;
        }

        if (window.id !== undefined && window.id !== null)
            ipc.minimizeWindow(window.id);
    }

    function restoreWindow(window) {
        if (!window)
            return;

        if (window.toplevel) {
            window.toplevel.minimized = false;
            if (window.toplevel.activate)
                window.toplevel.activate();
            return;
        }

        if (window.id !== undefined && window.id !== null)
            ipc.restoreWindow(window.id);
    }

    function activateWorkspace(workspace) {
        if (workspace && workspace.canActivate)
            workspace.activate();
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

            result.push(buildWindowModel(ipcWindow, match.toplevel));
        }

        for (var j = 0; j < list.length; j++) {
            if (usedToplevels[String(j)])
                continue;

            result.push(buildWindowModel(null, list[j]));
        }

        return result;
    }

    function buildWindowModel(ipcWindow, toplevel) {
        var title = ipcWindow && ipcWindow.title ? ipcWindow.title : toplevelText(toplevel, "title");
        var appId = ipcWindow && ipcWindow.appId ? ipcWindow.appId : toplevelText(toplevel, "appId");

        return {
            "id": ipcWindow ? ipcWindow.id : null,
            "title": title,
            "appId": appId,
            "workspaceId": ipcWindow ? ipcWindow.workspaceId : null,
            "pid": ipcWindow ? ipcWindow.pid : null,
            "isFocused": ipcWindow ? ipcWindow.isFocused : !!(toplevel && toplevel.activated),
            "isFloating": ipcWindow ? ipcWindow.isFloating : false,
            "isUrgent": ipcWindow ? ipcWindow.isUrgent : false,
            "isMinimized": ipcWindow ? ipcWindow.isMinimized : !!(toplevel && toplevel.minimized),
            "layout": ipcWindow ? ipcWindow.layout : null,
            "geometry": ipcWindow ? ipcWindow.geometry : null,
            "focusTimestamp": ipcWindow ? ipcWindow.focusTimestamp : null,
            "ipcWindow": ipcWindow,
            "toplevel": toplevel
        };
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
}
