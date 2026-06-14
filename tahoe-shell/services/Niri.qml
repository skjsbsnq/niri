pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import Quickshell.WindowManager

QtObject {
    id: root

    readonly property var toplevels: ToplevelManager.toplevels
    readonly property var toplevelList: ToplevelManager.toplevels.values
    readonly property var activeToplevel: ToplevelManager.activeToplevel
    readonly property var windowsets: WindowManager.windowsets
    readonly property var visibleWindowsets: displayableWindowsets(WindowManager.windowsets)
    readonly property var activeWorkspace: findActiveWorkspace(WindowManager.windowsets)
    readonly property string activeWorkspaceName: workspaceLabel(activeWorkspace, 0)

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
}
