pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Real desktop notification service.
//
// Replaces the old fake "Tahoe / Session ready" toast. This owns a
// Quickshell NotificationServer, which registers as the session's
// org.freedesktop.Notifications daemon over DBus. Any app that calls
// `notify-send`, libnotify, or the spec directly will have its
// notification routed here.
//
// Design, mirroring Controls.qml:
//   - Root is an Item (visible:false), not QtObject, because it owns
//     child QML objects (NotificationServer, Timer). QtObject has no
//     default `children` property and would abort the shell at load.
//
// We store the LIVE Notification objects in `activeModel` rather than
// snapshotting them. They are @@Quickshell.Retainable and remain valid
// until `closed` fires (server.cpp: deleteNotification emits `closed`
// BEFORE retainedDestroy). The popup therefore binds directly to
// `current.appName` / `current.summary` / etc., so a replace-id update
// (which mutates the same object without re-emitting `notification`) is
// reflected live with zero extra work.
//
// Lifecycle of a notification:
//   1. NotificationServer emits `notification(n)`.
//   2. We set `n.tracked = true` so the server keeps it (otherwise it is
//      treated as unhandled and destroyed immediately).
//   3. We push `n` onto the FIFO queue. Only the HEAD is shown by the
//      popup, so only the head needs an expire timer.
//   4. After the client-requested expireTimeout (capped) we auto-dismiss
//      the head via n.expire(), unless it is Critical (urgency=2), which
//      sticks until the user dismisses it (macOS behavior).
//   5. n.closed(reason) fires exactly once; handleClosed() drops it from
//      the queue and re-arms the timer for the new head.

Item {
    id: root
    visible: false

    // ------------------------------------------------------------------
    // Server: claim org.freedesktop.Notifications on the session bus.
    // ------------------------------------------------------------------
    // Advertise body + actions + icon-static so real clients send us rich
    // notifications. We deliberately do NOT advertise persistence: when
    // quickshell reloads we let old notifications be cleared
    // (keepOnReload false) rather than re-spamming stale toasts after
    // every edit.

    NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        onNotification: function (notification) {
            root.handleIncoming(notification);
        }
    }

    // ------------------------------------------------------------------
    // Active queue + head
    // ------------------------------------------------------------------
    //
    // activeModel holds the live Notification objects, FIFO. We replace
    // the whole array on every change (concat / slice) so QML bindings
    // on `activeModel` and `current` re-evaluate cleanly.

    property var activeModel: []
    readonly property int activeCount: activeModel.length
    // Head of FIFO (oldest waiting). Kept for callers that only need "the" toast.
    readonly property var current: activeModel.length > 0 ? activeModel[0] : null
    property var historyModel: []
    property bool dndEnabled: false
    property var soundService: null
    readonly property int historyCount: historyModel.length
    readonly property int maxHistory: 60
    property bool stateLoaded: false
    // id → absolute expire deadline (ms since epoch). Critical ids are absent.
    property var expireMap: ({})
    // Live Notification property updates (replace-id) do not rewrite activeModel.
    // Narrow identity signal for consumers (Dynamic Island); carries only the
    // stable id — never a second snapshot or copied model.
    signal notificationUpdated(int id)

    FileView {
        id: notificationStateFile
        path: Quickshell.stateDir + "/notifications.json"
        blockLoading: true
        blockWrites: true
        printErrors: false
        onLoaded: root.restoreState()
        onLoadFailed: {
            root.stateLoaded = true;
            root.saveState();
        }

        JsonAdapter {
            id: notificationState
            property bool dndEnabled: false
        }
    }

    onDndEnabledChanged: {
        if (soundService)
            soundService.setEventSoundsMuted(dndEnabled);
        root.saveState();
    }

    function restoreState() {
        root.stateLoaded = true;
        root.dndEnabled = notificationState.dndEnabled;
    }

    function saveState() {
        notificationState.dndEnabled = root.dndEnabled;
        notificationStateFile.writeAdapter();
    }

    // Cap auto-expire so a client that sends expireTimeout=-1 (meaning
    // "server default") or a huge value does not leave a toast up
    // forever. macOS toasts sit for ~5s.
    readonly property int defaultExpireMs: 5000
    readonly property int maxExpireMs: 30000

    function emitNotificationUpdated(id) {
        var nid = Number(id);
        if (!isFinite(nid))
            return;
        root.notificationUpdated(nid);
    }

    function wireNotificationPropertyUpdates(notification, id) {
        // replace-id mutates the same live object without re-emitting
        // NotificationServer.notification or rewriting activeModel.
        // Forward property changes as a narrow identity event for island.
        if (!notification)
            return;

        try {
            notification.summaryChanged.connect(function() {
                root.emitNotificationUpdated(id);
            });
        } catch (e1) {}
        try {
            notification.bodyChanged.connect(function() {
                root.emitNotificationUpdated(id);
            });
        } catch (e2) {}
        try {
            notification.appNameChanged.connect(function() {
                root.emitNotificationUpdated(id);
            });
        } catch (e3) {}
    }

    function handleIncoming(notification) {
        if (!notification)
            return;

        // Tell the server to keep this notification tracked. Without
        // this, the server treats the notification as unhandled and
        // immediately destroys it.
        notification.tracked = true;

        var id = notification.id;

        // Wire close handling once. n.closed fires exactly once before
        // the object is destroyed; the closure captures `id`.
        notification.closed.connect(function (reason) {
            root.handleClosed(id);
        });

        root.wireNotificationPropertyUpdates(notification, id);
        root.pushHistory(notification);

        if (root.dndEnabled) {
            // Keep the snapshot in history, suppress the visual toast, and
            // ask clients that honor notification hints not to play a sound.
            try {
                if (notification.hints)
                    notification.hints["suppress-sound"] = true;
            } catch (e) {}
            notification.expire();
            return;
        }

        root.activeModel = root.activeModel.concat([notification]);

        // Expire only for cards currently in the visible stack (newest ≤3).
        // Off-stack waiters keep full lifetime until they become visible —
        // preserves pre-T09 queue semantics while allowing multi-card timers.
        root.rearmVisibleExpires();
    }

    // Newest-first slice for the toast stack (macOS: new card on top).
    // maxCount defaults to 3; DesktopSettings.notificationToastStackMax drives UI.
    function visibleStack(maxCount) {
        var max = Math.max(1, Math.min(3, Math.round(Number(maxCount) || 3)));
        var list = root.activeModel;
        var n = Math.min(max, list.length);
        var out = [];
        for (var i = 0; i < n; i++)
            out.push(list[list.length - 1 - i]);
        return out;
    }

    // Keep independent expire deadlines only for currently visible non-critical
    // cards. Newly visible ids get a fresh timeout; hidden waiters are paused.
    function rearmVisibleExpires() {
        var stack = root.visibleStack(3);
        var nextMap = {};
        var prev = root.expireMap || {};
        for (var i = 0; i < stack.length; i++) {
            var n = stack[i];
            if (!n || root.isCritical(n))
                continue;
            var sid = String(n.id);
            if (Object.prototype.hasOwnProperty.call(prev, sid) && isFinite(Number(prev[sid])))
                nextMap[sid] = prev[sid];
            else
                nextMap[sid] = Date.now() + root.expireMsFor(n);
        }
        root.expireMap = nextMap;
        root.armSoonestExpire();
    }

    // Group history by appName, newest group first (first-seen order of apps
    // following history order which is already newest-first).
    function groupedHistory() {
        var groups = [];
        var indexByApp = {};
        var list = root.historyModel;
        for (var i = 0; i < list.length; i++) {
            var entry = list[i];
            if (!entry)
                continue;
            var app = String(entry.appName || "应用");
            if (indexByApp[app] === undefined) {
                indexByApp[app] = groups.length;
                groups.push({
                    "appName": app,
                    "items": [entry],
                    "count": 1
                });
            } else {
                var g = groups[indexByApp[app]];
                g.items.push(entry);
                g.count = g.items.length;
            }
        }
        return groups;
    }

    function isCritical(notification) {
        try {
            return Number(notification.urgency) === 2;
        } catch (e) {
            return false;
        }
    }

    function expireMsFor(notification) {
        // -1 / 0 means "use server default".
        var requested = 0;
        try {
            requested = Math.round(Number(notification.expireTimeout) * 1000);
            if (!isFinite(requested) || requested <= 0)
                requested = 0;
        } catch (e) {
            requested = 0;
        }
        return requested > 0
            ? Math.min(requested, root.maxExpireMs)
            : root.defaultExpireMs;
    }

    // Resolve the best icon URL for a live notification. The popup calls
    // this; keeping it in the service centralizes the priority rules.
    //   1. notification.image  (inline image, already an image:// URL)
    //   2. appIcon as themed icon -> image://icon/<name>
    //   3. desktopEntry icon    -> image://icon/<name>
    //   4. "" (popup falls back to a generic glyph)
    function iconUrlFor(notification) {
        if (!notification)
            return "";
        try {
            var img = String(notification.image || "").trim();
            if (img.length > 0)
                return img;
            var iconName = String(notification.appIcon || "").trim();
            if (iconName.length === 0)
                iconName = String(notification.desktopEntry || "").trim();
            if (iconName.length > 0)
                return "image://icon/" + iconName;
        } catch (e) {}
        return "";
    }

    function iconUrlForHistory(entry) {
        if (!entry)
            return "";
        try {
            var img = String(entry.image || "").trim();
            if (img.length > 0)
                return img;
            var iconName = String(entry.appIcon || "").trim();
            if (iconName.length === 0)
                iconName = String(entry.desktopEntry || "").trim();
            if (iconName.length > 0)
                return "image://icon/" + iconName;
        } catch (e) {}
        return "";
    }

    function pushHistory(notification) {
        var entry = snapshot(notification);
        if (!entry)
            return;

        var next = [entry];
        var list = root.historyModel;
        for (var i = 0; i < list.length && next.length < root.maxHistory; i++) {
            if (list[i] && list[i].id !== entry.id)
                next.push(list[i]);
        }
        root.historyModel = next;
    }

    function snapshot(notification) {
        if (!notification)
            return null;

        return {
            "id": notification.id,
            "appName": safeString(notification.appName, "应用"),
            "summary": safeString(notification.summary, "通知"),
            "body": safeString(notification.body, ""),
            "appIcon": safeString(notification.appIcon, ""),
            "desktopEntry": safeString(notification.desktopEntry, ""),
            "image": safeString(notification.image, ""),
            "urgency": Number(notification.urgency) || 0,
            "time": new Date()
        };
    }

    function safeString(value, fallback) {
        try {
            var text = String(value || "").trim();
            return text.length > 0 ? text : fallback;
        } catch (e) {
            return fallback;
        }
    }

    function removeHistoryItem(id) {
        var next = [];
        var list = root.historyModel;
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].id !== id)
                next.push(list[i]);
        }
        root.historyModel = next;
    }

    function toggleDnd() {
        root.dndEnabled = !root.dndEnabled;
    }

    function clearHistory() {
        root.historyModel = [];
    }

    function clearEverything() {
        clearHistory();
        clearAll();
    }

    function scheduleExpire(id, expireMs) {
        var at = Date.now() + Math.max(1, Math.round(Number(expireMs) || root.defaultExpireMs));
        var map = {};
        var prev = root.expireMap || {};
        for (var key in prev) {
            if (Object.prototype.hasOwnProperty.call(prev, key))
                map[key] = prev[key];
        }
        map[String(id)] = at;
        root.expireMap = map;
        root.armSoonestExpire();
    }

    function clearExpire(id) {
        var map = {};
        var prev = root.expireMap || {};
        var sid = String(id);
        for (var key in prev) {
            if (Object.prototype.hasOwnProperty.call(prev, key) && key !== sid)
                map[key] = prev[key];
        }
        root.expireMap = map;
        root.armSoonestExpire();
    }

    function armSoonestExpire() {
        var map = root.expireMap || {};
        var soonest = Infinity;
        var soonestId = -1;
        for (var key in map) {
            if (!Object.prototype.hasOwnProperty.call(map, key))
                continue;
            var at = Number(map[key]);
            if (isFinite(at) && at < soonest) {
                soonest = at;
                soonestId = Number(key);
            }
        }
        if (soonestId < 0 || !isFinite(soonest)) {
            expireTimer.stop();
            expireTimer.targetId = -1;
            return;
        }
        expireTimer.targetId = soonestId;
        expireTimer.interval = Math.max(1, Math.round(soonest - Date.now()));
        expireTimer.restart();
    }

    Timer {
        id: expireTimer
        property int targetId: -1
        interval: root.defaultExpireMs
        repeat: false
        onTriggered: {
            var id = targetId;
            root.clearExpire(id);
            root.dismissId(id, "expire");
            // armSoonestExpire runs again from clearExpire / handleClosed.
        }
    }

    function handleClosed(id) {
        // Drop the closed notification from the queue. Compare by id,
        // not object identity, because the object is mid-destruction.
        var remaining = [];
        var list = root.activeModel;
        for (var i = 0; i < list.length; i++) {
            if (list[i].id !== id)
                remaining.push(list[i]);
        }
        root.activeModel = remaining;
        root.clearExpire(id);
        root.rearmVisibleExpires();
    }

    function dismissId(id, mode) {
        // Find the live object by id (the queue holds live objects).
        var n = null;
        var list = root.activeModel;
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id) {
                n = list[i];
                break;
            }
        }
        if (!n) {
            // Already removed (e.g. closed by the client); nothing to do.
            return;
        }
        if (mode === "expire")
            n.expire();
        else
            n.dismiss();
        // handleClosed runs from the n.closed signal and updates the queue.
    }

    function dismissCurrent() {
        // Dismiss the top visible toast (newest), matching the UI stack.
        var stack = root.visibleStack(1);
        if (stack.length > 0)
            root.dismissId(stack[0].id, "dismiss");
        else if (root.current)
            root.dismissId(root.current.id, "dismiss");
    }

    function invokeAction(id, identifier) {
        var n = null;
        var list = root.activeModel;
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id) {
                n = list[i];
                break;
            }
        }
        if (!n)
            return;
        try {
            var actions = n.actions;
            for (var j = 0; j < actions.length; j++) {
                if (String(actions[j].identifier) === String(identifier)) {
                    actions[j].invoke();
                    return;
                }
            }
        } catch (e) {}
    }

    function clearAll() {
        // Dismiss every queued notification. Copy the id list first
        // because each dismiss mutates activeModel via handleClosed.
        var ids = [];
        var list = root.activeModel;
        for (var i = 0; i < list.length; i++)
            ids.push(list[i].id);
        for (var j = 0; j < ids.length; j++)
            root.dismissId(ids[j], "dismiss");
    }
}
