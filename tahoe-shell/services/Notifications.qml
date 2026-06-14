pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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
    readonly property var current: activeModel.length > 0 ? activeModel[0] : null

    // Cap auto-expire so a client that sends expireTimeout=-1 (meaning
    // "server default") or a huge value does not leave a toast up
    // forever. macOS toasts sit for ~5s.
    readonly property int defaultExpireMs: 5000
    readonly property int maxExpireMs: 30000

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

        var wasEmpty = root.activeModel.length === 0;
        root.activeModel = root.activeModel.concat([notification]);

        // Only the head is shown, so only the head needs an expire
        // timer. If this notification became the head (queue was empty)
        // and is not Critical, arm the timer.
        if (wasEmpty && !isCritical(notification))
            root.scheduleExpire(id, expireMsFor(notification));
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

    function scheduleExpire(id, expireMs) {
        expireTimer.targetId = id;
        expireTimer.interval = expireMs;
        expireTimer.restart();
    }

    Timer {
        id: expireTimer
        property int targetId: -1
        interval: root.defaultExpireMs
        repeat: false
        onTriggered: {
            // Guard: only expire if this id is still the head. If the user
            // dismissed it already the timer is harmless (dismissId on a
            // missing id no-ops), but this keeps the intent explicit.
            root.dismissId(targetId, "expire");
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

        // Re-arm the timer for the new head, if any.
        if (root.activeModel.length > 0) {
            var head = root.activeModel[0];
            if (!isCritical(head))
                root.scheduleExpire(head.id, expireMsFor(head));
            else
                expireTimer.stop();
        } else {
            expireTimer.stop();
        }
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
        if (root.current)
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
