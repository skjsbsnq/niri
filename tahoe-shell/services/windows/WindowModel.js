.pragma library

// Pure helpers for the unified niri/Quickshell window model. These functions
// must not read QML object state directly; pass workspace/toplevel context in.

function normalizedWindowSnapshot(rawWindows, workspacesById) {
    var source = Array.isArray(rawWindows) ? rawWindows : [];
    var windows = [];
    var byId = {};
    var order = [];

    for (var i = 0; i < source.length; i++) {
        var normalized = normalizeIpcWindow(source[i], workspacesById);
        if (!normalized)
            continue;

        windows.push(normalized);
        byId[String(normalized.id)] = normalized;
        order.push(String(normalized.id));
    }

    return { "windows": windows, "byId": byId, "order": order };
}

function mergeWindowModels(toplevels, ipcWindows, workspacesById) {
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

        result.push(buildWindowModel(ipcWindow, match.toplevel, i, workspacesById));
    }

    for (var j = 0; j < list.length; j++) {
        if (usedToplevels[String(j)])
            continue;

        result.push(buildWindowModel(null, list[j], j, workspacesById));
    }

    return result;
}

function findMatchingToplevel(ipcWindow, toplevels, usedToplevels) {
    var result = { "index": -1, "toplevel": null };
    if (!ipcWindow || !toplevels)
        return result;

    var used = usedToplevels || {};
    var appId = normalizeIdentity(ipcWindow.appId);
    var title = normalizeTitle(ipcWindow.title);

    for (var i = 0; i < toplevels.length; i++) {
        if (used[String(i)])
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
        if (used[String(j)])
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

function buildWindowModel(ipcWindow, toplevel, fallbackIndex, workspacesById) {
    var title = ipcWindow && ipcWindow.title ? ipcWindow.title : toplevelText(toplevel, "title");
    var appId = ipcWindow && ipcWindow.appId ? ipcWindow.appId : toplevelText(toplevel, "appId");
    var workspace = ipcWindow ? workspaceFromId(ipcWindow.workspaceId, workspacesById) : null;
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

function normalizeIpcWindow(raw, workspacesById) {
    if (!raw)
        return null;

    var id = asOptionalNumber(raw.id);
    if (id === null)
        return null;

    var layout = raw.layout || {};
    var workspaceId = asOptionalNumber(raw.workspace_id !== undefined ? raw.workspace_id : raw.workspaceId);
    var workspace = workspaceFromId(workspaceId, workspacesById);
    var geometry = geometryFromLayout(layout);
    var focused = !!(raw.is_focused !== undefined ? raw.is_focused : raw.isFocused);
    var minimized = !!(raw.is_minimized !== undefined ? raw.is_minimized : raw.isMinimized);

    return {
        "id": id,
        "title": textOrEmpty(raw.title),
        "appId": textOrEmpty(raw.app_id !== undefined ? raw.app_id : raw.appId),
        "pid": asOptionalNumber(raw.pid),
        "workspaceId": workspaceId,
        "workspace": workspace,
        "output": workspace ? String(workspace.output || "") : "",
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

function sortedRecentWindows(windows) {
    var result = (windows || []).slice();
    result.sort(function(left, right) {
        if (!!left.isFocused !== !!right.isFocused)
            return left.isFocused ? -1 : 1;

        return focusTimestampValue(right) - focusTimestampValue(left);
    });
    return result;
}

function findFocusedWindow(windows) {
    var list = windows || [];
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].isFocused)
            return list[i];
    }

    return null;
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

// Cheap equality for hot layout events. WindowLayoutsChanged can fire every
// compositor frame during resize/move animations; full JSON.stringify would
// dominate shell CPU and force Dock/TopBar model rebuilds.
function sameNumber(left, right) {
    var a = Number(left);
    var b = Number(right);
    if (!isFinite(a) && !isFinite(b))
        return true;
    return a === b;
}

function samePair(left, right) {
    if (!left && !right)
        return true;
    if (!left || !right || left.length < 2 || right.length < 2)
        return false;
    return sameNumber(left[0], right[0]) && sameNumber(left[1], right[1]);
}

function sameGeometry(left, right) {
    if (!left && !right)
        return true;
    if (!left || !right)
        return false;
    return sameNumber(left.x, right.x)
        && sameNumber(left.y, right.y)
        && sameNumber(left.w !== undefined ? left.w : left.width, right.w !== undefined ? right.w : right.width)
        && sameNumber(left.h !== undefined ? left.h : left.height, right.h !== undefined ? right.h : right.height);
}

function sameFocusTimestamp(left, right) {
    if (!left && !right)
        return true;
    if (!left || !right)
        return false;
    return sameNumber(left.secs, right.secs) && sameNumber(left.nanos, right.nanos);
}

function sameLayout(left, right) {
    if (left === right)
        return true;
    if (!left && !right)
        return true;
    if (!left || !right)
        return false;

    // Mirror niri_ipc::WindowLayout fields (source of truth in niri-ipc).
    var leftPos = left.tile_pos_in_workspace_view !== undefined
        ? left.tile_pos_in_workspace_view
        : left.tilePosInWorkspaceView;
    var rightPos = right.tile_pos_in_workspace_view !== undefined
        ? right.tile_pos_in_workspace_view
        : right.tilePosInWorkspaceView;
    var leftSize = left.tile_size !== undefined ? left.tile_size : left.tileSize;
    var rightSize = right.tile_size !== undefined ? right.tile_size : right.tileSize;
    var leftWindow = left.window_size !== undefined ? left.window_size : left.windowSize;
    var rightWindow = right.window_size !== undefined ? right.window_size : right.windowSize;
    var leftOffset = left.window_offset_in_tile !== undefined
        ? left.window_offset_in_tile
        : left.windowOffsetInTile;
    var rightOffset = right.window_offset_in_tile !== undefined
        ? right.window_offset_in_tile
        : right.windowOffsetInTile;
    var leftScroll = left.pos_in_scrolling_layout !== undefined
        ? left.pos_in_scrolling_layout
        : left.posInScrollingLayout;
    var rightScroll = right.pos_in_scrolling_layout !== undefined
        ? right.pos_in_scrolling_layout
        : right.posInScrollingLayout;

    return samePair(leftPos, rightPos)
        && samePair(leftSize, rightSize)
        && samePair(leftWindow, rightWindow)
        && samePair(leftOffset, rightOffset)
        && samePair(leftScroll, rightScroll);
}

function workspaceFromId(id, workspacesById) {
    if (id === undefined || id === null || !workspacesById)
        return null;
    return workspacesById[String(id)] || null;
}

function windowModelKey(ipcWindow, toplevel, fallbackIndex) {
    if (ipcWindow && ipcWindow.id !== undefined && ipcWindow.id !== null)
        return "id:" + String(ipcWindow.id);

    var appId = toplevelText(toplevel, "appId");
    return "toplevel:" + appId + ":" + String(fallbackIndex || 0);
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

function focusTimestampValue(window) {
    if (!window || !window.focusTimestamp)
        return 0;

    var secs = Number(window.focusTimestamp.secs || 0);
    var nanos = Number(window.focusTimestamp.nanos || 0);
    return secs + nanos / 1000000000;
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

function cloneWorkspace(workspace) {
    if (!workspace)
        return null;

    return {
        "id": workspace.id,
        "idx": workspace.idx,
        "name": workspace.name,
        "output": workspace.output,
        "isActive": !!workspace.isActive,
        "isFocused": !!workspace.isFocused,
        "isUrgent": !!workspace.isUrgent,
        "activeWindowId": workspace.activeWindowId === undefined ? null : workspace.activeWindowId,
        "coordinates": workspace.coordinates || null
    };
}

function workspaceListSnapshot(workspaces) {
    var list = Array.isArray(workspaces) ? workspaces : [];
    var next = [];
    for (var i = 0; i < list.length; i++) {
        var workspace = cloneWorkspace(list[i]);
        if (workspace)
            next.push(workspace);
    }
    return next;
}

function findWorkspaceById(workspaces, id) {
    if (id === undefined || id === null)
        return null;

    var key = String(id);
    var list = Array.isArray(workspaces) ? workspaces : [];
    for (var i = 0; i < list.length; i++) {
        var workspace = list[i];
        if (workspace && String(workspace.id) === key)
            return workspace;
    }
    return null;
}

function findFocusedWorkspace(workspaces) {
    var list = Array.isArray(workspaces) ? workspaces : [];
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].isFocused)
            return list[i];
    }
    return null;
}

function focusedOutputName(workspaces) {
    var focused = findFocusedWorkspace(workspaces);
    return focused ? textOrEmpty(focused.output) : "";
}

function activeWorkspaceForOutput(workspaces, outputName) {
    var target = String(outputName || "").trim();
    if (target.length === 0)
        return null;

    var list = Array.isArray(workspaces) ? workspaces : [];
    for (var i = 0; i < list.length; i++) {
        var workspace = list[i];
        if (!workspace || !workspace.isActive)
            continue;
        if (String(workspace.output || "").trim() === target)
            return workspace;
    }
    return null;
}

function activeWorkspaceIndexForOutput(workspaces, outputName) {
    var workspace = activeWorkspaceForOutput(workspaces, outputName);
    if (!workspace)
        return null;

    var idx = Number(workspace.idx);
    if (isFinite(idx) && idx > 0)
        return idx;

    return workspaceSortIndex(workspace, 0);
}

// Match niri EventStreamState WorkspacesState::apply for WorkspaceActivated:
// activate id on its output; if focused, clear isFocused on others.
function applyWorkspaceActivated(workspaces, id, focused) {
    var target = findWorkspaceById(workspaces, id);
    if (!target)
        return null;

    var output = String(target.output || "");
    var becomeFocused = !!focused;
    var next = workspaceListSnapshot(workspaces);
    for (var i = 0; i < next.length; i++) {
        var workspace = next[i];
        var gotActivated = String(workspace.id) === String(target.id);
        if (String(workspace.output || "") === output)
            workspace.isActive = gotActivated;
        if (becomeFocused)
            workspace.isFocused = gotActivated;
    }
    return next;
}

function applyWorkspaceUrgencyChanged(workspaces, id, urgent) {
    if (!findWorkspaceById(workspaces, id))
        return null;

    var next = workspaceListSnapshot(workspaces);
    var value = !!urgent;
    var changed = false;
    for (var i = 0; i < next.length; i++) {
        if (String(next[i].id) !== String(id))
            continue;
        if (next[i].isUrgent === value)
            return null;
        next[i].isUrgent = value;
        changed = true;
    }
    return changed ? next : null;
}

function applyWorkspaceActiveWindowChanged(workspaces, workspaceId, activeWindowId) {
    if (!findWorkspaceById(workspaces, workspaceId))
        return null;

    var next = workspaceListSnapshot(workspaces);
    var windowId = asOptionalNumber(activeWindowId);
    for (var i = 0; i < next.length; i++) {
        if (String(next[i].id) !== String(workspaceId))
            continue;
        if (next[i].activeWindowId === windowId)
            return null;
        next[i].activeWindowId = windowId;
        return next;
    }
    return null;
}

// Drop workspaces whose output is no longer present. Empty outputs (no monitors)
// are kept only when no connected outputs remain.
function pruneWorkspacesForOutputs(workspaces, connectedOutputs) {
    var outputs = Array.isArray(connectedOutputs) ? connectedOutputs : [];
    var allowed = {};
    for (var i = 0; i < outputs.length; i++) {
        var name = String(outputs[i] || "").trim();
        if (name.length > 0)
            allowed[name] = true;
    }

    var list = Array.isArray(workspaces) ? workspaces : [];
    if (Object.keys(allowed).length === 0)
        return workspaceListSnapshot(list);

    var next = [];
    for (var j = 0; j < list.length; j++) {
        var workspace = list[j];
        if (!workspace)
            continue;
        var output = String(workspace.output || "").trim();
        if (output.length === 0 || allowed[output])
            next.push(cloneWorkspace(workspace));
    }
    return next;
}
