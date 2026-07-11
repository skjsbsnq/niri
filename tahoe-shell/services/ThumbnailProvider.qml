pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/*
 * Centralized window thumbnail queue for Tahoe shell surfaces.
 *
 * Public contract:
 * - requestThumbnail(window, maxWidth, maxHeight, reason, force) is the only
 *   shell-side entry point for a single window preview. window may be a niri
 *   window object or a numeric niri window id. reason is diagnostic only.
 * - requestThumbnails(windows, maxWidth, maxHeight, reason, force) batches
 *   requests through the same queue and keeps the same cache semantics.
 * - thumbnailStateForWindow(window, revisionToken) returns the provider-owned
 *   state object. Callers should bind revisionToken to revision so QML updates
 *   when queued/loading/ready/failed changes.
 * - markImageFailed(window, error) lets an Image consumer report decode/load
 *   failures back to the provider so every preview surface sees the same
 *   failed state and fallback.
 *
 * Cache key:
 * - The cache key is the decimal niri window id. Toplevel-only windows without
 *   a numeric id cannot request compositor thumbnails and must render fallback.
 * - Files are provider-owned runtime artifacts at
 *   $XDG_RUNTIME_DIR/tahoe/window-thumbnails/window-<id>.png.
 *
 * Failure state:
 * - state.status is one of idle, queued, loading, ready, failed.
 * - On queue overflow, niri failure, or image decode failure, state.failed is
 *   true and state.error contains a user/debuggable reason.
 *
 * Cleanup:
 * - When Windows.windowList changes, stale cache entries are removed and their
 *   runtime PNG files are deleted.
 * - A cancelled active job is allowed to exit, then its output path is removed.
 *
 * Guardrail:
 * - Dock, TaskSwitcher, WindowOverview, and future window-preview surfaces must
 *   call this provider. Do not spawn `niri msg window-thumbnail`, use screencopy,
 *   or create a second thumbnail queue in component code.
 */
Item {
    id: root
    visible: false

    property var windowsService
    property int maxQueueLength: 64
    property int maxCacheAgeMs: 30000
    property int revision: 0
    property int successCount: 0
    property int failureCount: 0
    property string lastError: ""
    property var cache: ({})
    property var queuedKeys: ({})
    // Cursor-backed queue avoids copying the whole array for each thumbnail burst step.
    property var queue: []
    property int queueHead: 0
    property int pendingQueueLength: 0
    property var activeJob: null
    // Membership fingerprint so layout-only windowList patches (geometry churn)
    // do not re-walk the whole cache every compositor frame.
    property string lastLiveWindowKeys: ""

    readonly property int pendingCount: pendingQueueLength
    readonly property bool running: thumbnailProcess.running
    readonly property string thumbnailDirectory: runtimeDirectory() + "/tahoe/window-thumbnails"

    function runtimeDirectory() {
        var dir = String(Quickshell.env("XDG_RUNTIME_DIR") || "").trim();
        return dir.length > 0 ? dir : "/tmp";
    }

    function setCacheState(key, state) {
        root.cache[key] = state;
    }

    function deleteCacheState(key) {
        delete root.cache[key];
    }

    function touch() {
        root.revision += 1;
    }

    function queuePendingCount() {
        return Math.max(0, root.queue.length - root.queueHead);
    }

    function refreshPendingCount() {
        root.pendingQueueLength = queuePendingCount();
    }

    function compactQueueStorage() {
        if (root.queueHead <= 0) {
            refreshPendingCount();
            return;
        }

        if (root.queueHead >= root.queue.length) {
            root.queue = [];
            root.queueHead = 0;
        } else if (root.queueHead >= 32 && root.queueHead * 2 >= root.queue.length) {
            root.queue = root.queue.slice(root.queueHead);
            root.queueHead = 0;
        }

        refreshPendingCount();
    }

    function windowFromIdOrObject(idOrWindow) {
        if (idOrWindow === undefined || idOrWindow === null)
            return null;
        if (typeof idOrWindow === "object")
            return idOrWindow;
        if (root.windowsService && root.windowsService.windowFromIdOrObject)
            return root.windowsService.windowFromIdOrObject(idOrWindow);
        return { "id": idOrWindow };
    }

    function keyForWindow(idOrWindow) {
        var window = windowFromIdOrObject(idOrWindow);
        var id = window && window.id !== undefined && window.id !== null ? window.id : idOrWindow;
        var key = String(id === undefined || id === null ? "" : id).trim();
        return /^\d+$/.test(key) ? key : "";
    }

    function thumbnailPathForId(id) {
        var key = keyForWindow(id);
        if (key.length === 0)
            return "";
        return root.thumbnailDirectory + "/window-" + key + ".png";
    }

    function thumbnailPathForWindow(idOrWindow) {
        var key = keyForWindow(idOrWindow);
        return key.length > 0 ? root.thumbnailDirectory + "/window-" + key + ".png" : "";
    }

    function makeState(key) {
        return {
            "key": key,
            "path": root.thumbnailDirectory + "/window-" + key + ".png",
            "ready": false,
            "failed": false,
            "queued": false,
            "loading": false,
            "generation": 0,
            "maxWidth": 0,
            "maxHeight": 0,
            "desiredWidth": 0,
            "desiredHeight": 0,
            "updatedAt": 0,
            "error": "",
            "status": "idle",
            "refreshPending": false
        };
    }

    function stateForKey(key, create) {
        key = String(key || "");
        if (key.length === 0)
            return null;

        var state = root.cache[key];
        if (!state && create) {
            state = makeState(key);
            setCacheState(key, state);
        }
        return state || null;
    }

    function thumbnailStateForWindow(idOrWindow, revisionToken) {
        revisionToken = revisionToken;
        var key = keyForWindow(idOrWindow);
        return key.length > 0 ? stateForKey(key, true) : null;
    }

    function clampDimension(value, fallback) {
        var number = Math.round(Number(value));
        if (!isFinite(number) || number <= 0)
            number = fallback;
        return Math.max(1, Math.min(4096, number));
    }

    function removeQueuedKey(key) {
        key = String(key || "");
        if (key.length === 0)
            return;

        for (var i = root.queue.length - 1; i >= root.queueHead; i--) {
            if (String(root.queue[i]) !== key)
                continue;
            root.queue.splice(i, 1);
        }
        compactQueueStorage();

        delete root.queuedKeys[key];

        var state = stateForKey(key, false);
        if (state) {
            state.queued = false;
            if (!state.loading && state.status === "queued")
                state.status = state.ready ? "ready" : "idle";
        }
    }

    function queueKey(key) {
        key = String(key || "");
        if (key.length === 0)
            return false;

        var state = stateForKey(key, true);
        if (!state)
            return false;

        if (root.queuedKeys[key]) {
            state.queued = true;
            touch();
            return true;
        }

        if (queuePendingCount() >= root.maxQueueLength) {
            state.loading = false;
            state.queued = false;
            state.failed = true;
            state.status = "failed";
            state.error = "thumbnail queue is full";
            root.lastError = state.error;
            root.failureCount += 1;
            touch();
            return false;
        }

        root.queuedKeys[key] = true;
        root.queue.push(key);
        refreshPendingCount();
        state.queued = true;
        state.status = "queued";
        pumpTimer.restart();
        touch();
        return true;
    }

    function requestThumbnail(idOrWindow, maxWidth, maxHeight, reason, force) {
        var key = keyForWindow(idOrWindow);
        if (key.length === 0)
            return false;

        var state = stateForKey(key, true);
        if (!state)
            return false;

        var width = clampDimension(maxWidth, 320);
        var height = clampDimension(maxHeight, 220);
        state.desiredWidth = Math.max(Number(state.desiredWidth) || 0, width);
        state.desiredHeight = Math.max(Number(state.desiredHeight) || 0, height);

        var now = Date.now();
        var age = state.updatedAt > 0 ? now - state.updatedAt : 999999999999;
        var hasEnoughSize = state.maxWidth >= width && state.maxHeight >= height;
        var cacheFresh = state.ready && !state.failed && hasEnoughSize && age < root.maxCacheAgeMs;
        if (!force && cacheFresh) {
            touch();
            return true;
        }

        if (state.loading) {
            state.refreshPending = true;
            touch();
            return true;
        }

        state.failed = false;
        state.error = "";
        state.status = "queued";
        return queueKey(key);
    }

    function requestThumbnails(windows, maxWidth, maxHeight, reason, force) {
        var values = Array.isArray(windows) ? windows : [];
        var limit = Math.min(values.length, root.maxQueueLength);
        for (var i = 0; i < limit; i++)
            requestThumbnail(values[i], maxWidth, maxHeight, reason, force);
    }

    function markImageFailed(idOrWindow, error) {
        var key = keyForWindow(idOrWindow);
        var state = stateForKey(key, false);
        if (!state)
            return;
        state.ready = false;
        state.failed = true;
        state.loading = false;
        state.status = "failed";
        state.error = String(error || "thumbnail image failed to load");
        root.lastError = state.error;
        touch();
    }

    function cleanupThumbnailFileForId(id) {
        var path = thumbnailPathForId(id);
        if (path.length === 0)
            return;
        Quickshell.execDetached({ command: ["rm", "-f", "--", path] });
    }

    function cleanupCachedKey(key) {
        key = String(key || "");
        if (key.length === 0)
            return;

        removeQueuedKey(key);
        if (root.activeJob && root.activeJob.key === key)
            root.activeJob.cancelled = true;
        deleteCacheState(key);
        cleanupThumbnailFileForId(key);
        touch();
    }

    function pruneStaleThumbnails() {
        if (!root.windowsService || !root.windowsService.windowList)
            return;

        var live = {};
        var liveKeys = [];
        var windows = root.windowsService.windowList || [];
        for (var i = 0; i < windows.length; i++) {
            var key = keyForWindow(windows[i]);
            if (key.length > 0 && !live[key]) {
                live[key] = true;
                liveKeys.push(key);
            }
        }
        liveKeys.sort();
        var fingerprint = liveKeys.join(",");
        if (fingerprint === root.lastLiveWindowKeys)
            return;
        root.lastLiveWindowKeys = fingerprint;

        var keys = [];
        for (var cacheKey in root.cache) {
            if (!live[cacheKey])
                keys.push(cacheKey);
        }
        for (var j = 0; j < keys.length; j++)
            cleanupCachedKey(keys[j]);
    }

    function pumpQueue() {
        if (thumbnailProcess.running || root.activeJob)
            return;

        while (queuePendingCount() > 0) {
            var key = String(root.queue[root.queueHead]);
            root.queueHead += 1;
            delete root.queuedKeys[key];
            compactQueueStorage();

            var state = stateForKey(key, false);
            if (!state || state.path.length === 0)
                continue;

            state.queued = false;
            state.loading = true;
            state.failed = false;
            state.error = "";
            state.status = "loading";

            var width = clampDimension(state.desiredWidth, 320);
            var height = clampDimension(state.desiredHeight, 220);
            root.activeJob = {
                "key": key,
                "path": state.path,
                "maxWidth": width,
                "maxHeight": height,
                "cancelled": false
            };
            thumbnailProcess.command = [
                "sh",
                "-c",
                "if command -v timeout >/dev/null 2>&1; then exec timeout 8s niri msg --json window-thumbnail --id \"$1\" --path \"$2\" --max-width \"$3\" --max-height \"$4\"; else exec niri msg --json window-thumbnail --id \"$1\" --path \"$2\" --max-width \"$3\" --max-height \"$4\"; fi",
                "sh",
                key,
                state.path,
                String(width),
                String(height)
            ];
            thumbnailProcess.running = true;
            touch();
            return;
        }
    }

    function finishActiveJob(code) {
        var job = root.activeJob;
        if (!job)
            return;

        var state = stateForKey(job.key, false);
        if (job.cancelled) {
            cleanupThumbnailFileForId(job.key);
            root.activeJob = null;
            pumpTimer.restart();
            touch();
            return;
        }

        if (state) {
            state.loading = false;
            state.queued = false;
            if (code === 0) {
                state.ready = true;
                state.failed = false;
                state.generation = (Number(state.generation) || 0) + 1;
                state.maxWidth = job.maxWidth;
                state.maxHeight = job.maxHeight;
                state.updatedAt = Date.now();
                state.error = "";
                state.status = "ready";
                root.successCount += 1;
            } else {
                state.ready = false;
                state.failed = true;
                state.error = "niri window-thumbnail exited with code " + String(code);
                state.status = "failed";
                root.lastError = state.error;
                root.failureCount += 1;
            }

            if (state.refreshPending) {
                state.refreshPending = false;
                queueKey(job.key);
            }
        }

        root.activeJob = null;
        pumpTimer.restart();
        touch();
    }

    onWindowsServiceChanged: pruneStaleThumbnails()

    Connections {
        target: root.windowsService
        ignoreUnknownSignals: true

        function onWindowListChanged() {
            root.pruneStaleThumbnails();
        }
    }

    Timer {
        id: pumpTimer
        interval: 0
        repeat: false
        onTriggered: root.pumpQueue()
    }

    Process {
        id: thumbnailProcess
        running: false
        onExited: function(code, exitStatus) {
            root.finishActiveJob(code);
        }
    }
}
