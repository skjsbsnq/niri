pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion
import "DynamicIslandMotion.js" as IslandMotion

// Real notification toast stack (T09).
//
// Driven by Notifications.activeModel via visibleStack(max). Up to
// notificationToastStackMax (default 3) cards render newest-on-top.
// Enter / scale use springPanel on *content* transforms only. Glass region
// geometry uses eased y (stack) and eased x (swipe) — never SpringAnimation
// (guardrail 0704ea4). Horizontal swipe dismiss reuses DynamicIslandMotion
// thresholds. Hover lifts the top card and reveals a top-left close button.
//
// DND and Dynamic Island still suppress the whole toast surface.

PanelWindow {
    id: root

    property var notificationsService
    property var settingsService
    property var dynamicIslandService
    property var current: notificationsService ? notificationsService.current : null
    property bool hasCurrent: !!current
    // T08: when the island is enabled, toast is globally suppressed (notification
    // transient only on the event owner output). Island disabled restores toast.
    readonly property bool suppressedByDynamicIsland: root.dynamicIslandService
        ? !!root.dynamicIslandService.islandEnabled
        : (!!root.settingsService && !!root.settingsService.dynamicIslandEnabled)
    readonly property int stackMax: {
        var n = root.settingsService ? Number(root.settingsService.notificationToastStackMax) : Motion.toastStackMaxDefault;
        if (!isFinite(n))
            n = Motion.toastStackMaxDefault;
        return Math.max(1, Math.min(3, Math.round(n)));
    }
    // Depend on activeCount so FIFO mutations re-evaluate the stack slice.
    readonly property int activeCount: notificationsService ? notificationsService.activeCount : 0
    readonly property var stackItems: {
        var _watch = root.activeCount;
        if (!notificationsService || root.suppressedByDynamicIsland || _watch <= 0)
            return [];
        return notificationsService.visibleStack(root.stackMax);
    }
    readonly property int stackCount: stackItems.length
    readonly property int maxRetainedExits: stackMax
    // Stable QObject wrappers outlive service removal until their exit finishes.
    // This keeps the surface mapped for timeout/client-close animations and lets
    // cards move between stack slots without rebinding a fixed delegate.
    property var displayItems: []
    property var displayItemCache: Object.create(null)
    property var cardRegions: []
    readonly property int displayCount: displayItems.length
    readonly property bool shouldShowToast: !root.suppressedByDynamicIsland && displayCount > 0
    // Kept for shell.qml compatibility. Glass geometry never uses Spring.
    property bool useSpring: false
    readonly property int screenWidth: Math.max(1, root.numberOr(root.screen && root.screen.width, 1))
    readonly property int toastLeftMargin: Math.round(Math.max(8, root.screenWidth - root.implicitWidth - 16))
    readonly property int cardBaseHeight: 86
    property int measuredStackHeight: cardBaseHeight
    // Previous visible ids are used so promote/demote does not replay enter.
    property var prevStackIds: []

    Component {
        id: toastEntryFactory

        QtObject {
            property string modelKey: ""
            property int notificationId: -1
            property int stackIndex: -1
            property bool present: false
            property bool exiting: false
            property bool exitAnimationDone: false
            property bool dismissRequested: false
            property int exitDirection: 1
            property int enterSerial: 0
            property var notification: null
            property string appName: "Notification"
            property string summary: ""
            property string body: ""
            property string iconUrl: ""
            property int urgency: 0
            property var actions: []
        }
    }

    function numberOr(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
    }

    function isNewlyAppearedId(id) {
        var n = Number(id);
        if (!isFinite(n) || n < 0)
            return false;
        var prev = root.prevStackIds || [];
        for (var i = 0; i < prev.length; i++) {
            if (Number(prev[i]) === n)
                return false;
        }
        return true;
    }

    function notificationId(notification) {
        if (!notification)
            return -1;
        try {
            var id = Number(notification.id);
            return isFinite(id) && id >= 0 ? id : -1;
        } catch (e) {
            return -1;
        }
    }

    function textOr(value, fallback) {
        try {
            var text = String(value || "").trim();
            return text.length > 0 ? text : fallback;
        } catch (e) {
            return fallback;
        }
    }

    function actionSnapshots(notification) {
        var result = [];
        if (!notification)
            return result;
        try {
            var actions = notification.actions || [];
            for (var i = 0; i < actions.length; i++) {
                var action = actions[i];
                if (!action)
                    continue;
                result.push({
                    "identifier": String(action.identifier || ""),
                    "text": String(action.text || "")
                });
            }
        } catch (e) {}
        return result;
    }

    function updateDisplayEntry(entry, notification) {
        if (!entry || !notification)
            return;
        entry.notification = notification;
        entry.appName = root.textOr(notification.appName, "Notification");
        entry.summary = root.textOr(notification.summary, "");
        entry.body = root.textOr(notification.body, "");
        entry.iconUrl = root.iconUrlFor(notification);
        try {
            entry.urgency = Number(notification.urgency) || 0;
        } catch (e) {
            entry.urgency = 0;
        }
        entry.actions = root.actionSnapshots(notification);
    }

    function stackContainsId(id) {
        var items = root.stackItems || [];
        for (var i = 0; i < items.length; i++) {
            if (root.notificationId(items[i]) === id)
                return true;
        }
        return false;
    }

    function reconcileStack() {
        var items = root.stackItems || [];
        var cache = root.displayItemCache || Object.create(null);
        var activeIds = Object.create(null);
        var next = [];
        var nextIds = [];
        var nextStackIndex = 0;
        var overflow = [];

        for (var i = 0; i < items.length; i++) {
            var notification = items[i];
            var id = root.notificationId(notification);
            if (id < 0)
                continue;
            var key = String(id);
            if (activeIds[key])
                continue;
            activeIds[key] = true;
            nextIds.push(id);

            var entry = cache[key];
            var created = !entry;
            if (!entry) {
                entry = toastEntryFactory.createObject(root, {
                    "modelKey": "notification:" + key,
                    "notificationId": id
                });
                if (!entry)
                    continue;
                cache[key] = entry;
            }

            root.updateDisplayEntry(entry, notification);
            if (entry.exiting && !entry.dismissRequested) {
                entry.exiting = false;
                entry.exitAnimationDone = false;
                entry.exitDirection = 1;
            }

            // A locally dismissed card remains in the service briefly while its
            // exit runs. Remove it from slot accounting immediately so the same
            // lower-card delegates can move up and grow during the exit.
            if (entry.exiting && entry.dismissRequested) {
                entry.present = false;
            } else {
                entry.present = true;
                entry.stackIndex = nextStackIndex;
                nextStackIndex += 1;
                if (created && entry.stackIndex === 0 && root.isNewlyAppearedId(id))
                    entry.enterSerial += 1;
            }
            next.push(entry);
        }

        var previous = root.displayItems || [];
        for (var p = 0; p < previous.length; p++) {
            var retained = previous[p];
            if (!retained)
                continue;
            var retainedKey = String(retained.notificationId);
            if (activeIds[retainedKey])
                continue;
            // closed() is emitted before the retained live object is destroyed.
            // Freeze its final fields for the retained exit delegate, then drop
            // the live reference so no binding reads a destroyed notification.
            if (retained.notification)
                root.updateDisplayEntry(retained, retained.notification);
            retained.notification = null;
            retained.present = false;
            if (!retained.exiting) {
                retained.exitDirection = 1;
                retained.exitAnimationDone = false;
                retained.dismissRequested = false;
                retained.exiting = true;
            }
            next.push(retained);
        }

        // A notification storm can otherwise retain one exiting glass region
        // per arrival for panelExit milliseconds. Keep at most one stack depth
        // of exits, so active + exiting regions are bounded to six.
        var bounded = [];
        var retainedExitCount = 0;
        for (var b = 0; b < next.length; b++) {
            var candidate = next[b];
            if (candidate && candidate.exiting) {
                retainedExitCount += 1;
                if (retainedExitCount > root.maxRetainedExits) {
                    delete cache[String(candidate.notificationId)];
                    overflow.push(candidate);
                    continue;
                }
            }
            if (candidate)
                bounded.push(candidate);
        }

        root.displayItemCache = cache;
        root.displayItems = bounded;
        root.prevStackIds = nextIds;
        for (var o = 0; o < overflow.length; o++) {
            if (overflow[o] && overflow[o].destroy)
                overflow[o].destroy(1000);
        }
        Qt.callLater(root.recomputeStackHeight);
        Qt.callLater(root.retireCompletedEntries);
    }

    function refreshDisplayEntry(id) {
        var key = String(Number(id));
        var entry = (root.displayItemCache || Object.create(null))[key];
        if (!entry)
            return;
        var notification = entry.notification;
        if (!notification && root.notificationsService && root.notificationsService.findActiveById)
            notification = root.notificationsService.findActiveById(Number(id));
        root.updateDisplayEntry(entry, notification);
    }

    function requestEntryExit(entry, direction, dismissRequested) {
        if (!entry)
            return;
        if (dismissRequested)
            entry.dismissRequested = true;
        entry.exitDirection = Number(direction) < 0 ? -1 : 1;
        entry.exitAnimationDone = false;
        entry.present = false;
        if (!entry.exiting)
            entry.exiting = true;
        root.reconcileStack();
    }

    function completeEntryExit(id) {
        var key = String(Number(id));
        var entry = (root.displayItemCache || Object.create(null))[key];
        if (!entry)
            return;
        entry.exitAnimationDone = true;
        if (entry.dismissRequested)
            root.dismissNotificationId(entry.notificationId);
        Qt.callLater(root.retireCompletedEntries);
    }

    function retireCompletedEntries() {
        var current = root.displayItems || [];
        var cache = root.displayItemCache || Object.create(null);
        var next = [];
        var retired = [];
        for (var i = 0; i < current.length; i++) {
            var entry = current[i];
            if (entry && entry.exiting && entry.exitAnimationDone
                    && !root.stackContainsId(entry.notificationId)) {
                delete cache[String(entry.notificationId)];
                retired.push(entry);
            } else if (entry) {
                next.push(entry);
            }
        }
        if (retired.length === 0)
            return;
        root.displayItemCache = cache;
        root.displayItems = next;
        for (var r = 0; r < retired.length; r++) {
            if (retired[r] && retired[r].destroy)
                retired[r].destroy(1000);
        }
        Qt.callLater(root.recomputeStackHeight);
    }

    function registerCardRegion(region) {
        if (!region || root.cardRegions.indexOf(region) >= 0)
            return;
        root.cardRegions = root.cardRegions.concat([region]);
    }

    function unregisterCardRegion(region) {
        var next = [];
        for (var i = 0; i < root.cardRegions.length; i++) {
            if (root.cardRegions[i] !== region)
                next.push(root.cardRegions[i]);
        }
        root.cardRegions = next;
    }

    function accentFor(entry) {
        if (!entry)
            return GlassStyle.StrokeToast;
        try {
            return Number(entry.urgency) === 2 ? "#ccff453a" : GlassStyle.StrokeToast;
        } catch (e) {
            return GlassStyle.StrokeToast;
        }
    }

    function iconUrlFor(notification) {
        if (!notificationsService || !notification)
            return "";
        return notificationsService.iconUrlFor(notification);
    }

    function dismissNotification(entry) {
        if (!notificationsService || !entry)
            return;
        root.requestEntryExit(entry, 1, true);
    }

    // Swipe-dismiss Timer must use the id captured at gesture commit time.
    // Never re-read a stackIndex-bound notification object after rebind.
    function dismissNotificationId(id) {
        if (!notificationsService)
            return;
        var n = Number(id);
        if (!isFinite(n) || n < 0)
            return;
        notificationsService.dismissId(n, "dismiss");
    }

    function invokeAction(entry, identifier) {
        if (!notificationsService || !entry)
            return;
        notificationsService.invokeAction(entry.notificationId, identifier);
    }

    function recomputeStackHeight() {
        var h = root.cardBaseHeight;
        for (var i = 0; i < toastRepeater.count; i++) {
            var item = toastRepeater.itemAt(i);
            if (!item || !item.active)
                continue;
            var bottom = item.y + item.height;
            if (bottom > h)
                h = bottom;
        }
        measuredStackHeight = Math.ceil(h + 4);
    }

    visible: shouldShowToast
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    implicitWidth: 318
    implicitHeight: Math.max(cardBaseHeight, measuredStackHeight)
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "tahoe-notification-toast"

    anchors {
        top: true
        left: true
    }

    margins {
        top: 48
        left: root.toastLeftMargin
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Motion.elementResize(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }
    }

    TahoeGlass.regions: root.cardRegions

    Repeater {
        id: toastRepeater

        model: ScriptModel {
            objectProp: "modelKey"
            values: root.displayItems
        }

        delegate: ToastCard {
            required property var modelData
            entry: modelData
        }
    }

    onStackCountChanged: Qt.callLater(recomputeStackHeight)
    onStackItemsChanged: root.reconcileStack()

    Connections {
        target: root.notificationsService
        ignoreUnknownSignals: true

        function onActiveModelChanged() {
            root.reconcileStack();
        }

        function onNotificationUpdated(id) {
            root.refreshDisplayEntry(id);
        }
    }

    Component.onCompleted: root.reconcileStack()

    component ToastCard: Item {
        id: cardRoot

        property var entry
        readonly property int stackIndex: entry ? entry.stackIndex : -1
        readonly property bool active: !!entry
        readonly property bool interactive: active && entry.present && !entry.exiting
            && stackIndex === 0
        readonly property var liveNotification: entry ? entry.notification : null
        readonly property string iconUrl: liveNotification
            ? root.iconUrlFor(liveNotification)
            : (entry ? String(entry.iconUrl || "") : "")
        readonly property bool hasIcon: iconUrl.length > 0
        readonly property color accentColor: root.accentFor(liveNotification || entry)
        readonly property int notifId: entry ? Number(entry.notificationId) : -1
        readonly property string displayAppName: liveNotification
            ? String(liveNotification.appName || "Notification")
            : (entry ? String(entry.appName || "Notification") : "")
        readonly property string displaySummary: liveNotification
            ? String(liveNotification.summary || "")
            : (entry ? String(entry.summary || "") : "")
        readonly property string displayBody: liveNotification
            ? String(liveNotification.body || "")
            : (entry ? String(entry.body || "") : "")
        readonly property var actionItems: {
            if (liveNotification) {
                try {
                    return liveNotification.actions || [];
                } catch (e) {}
            }
            return entry && entry.actions ? entry.actions : [];
        }

        // Content-only motion (spring-safe).
        property real enterX: 0
        property real contentScale: 1
        property real contentOpacity: 0

        // Glass-safe geometry: eased only. Animate stackY / hoverLift
        // independently; y is a pure binding (no dual Behavior).
        property real stackY: 0
        property real swipeX: 0
        property real hoverLift: 0

        property bool swipeDragging: false
        property bool swipeMoved: false
        property real swipeStartX: 0
        property real swipePointerStartX: 0
        property real swipePointerStartY: 0
        property int lastEnterSerial: -1
        property int interactionNotifId: -1
        property bool pointerPressed: false
        readonly property bool exitInteractionHold: active && entry.exiting
            && entry.dismissRequested && interactionNotifId === notifId
        readonly property bool interactionActive: (interactive
            && (cardHover.hovered || pointerPressed)) || exitInteractionHold

        readonly property alias cardRegion: glass.region

        width: root.implicitWidth
        height: Math.max(root.cardBaseHeight, contentColumn.implicitHeight + 28)
        enabled: interactive
        // Glass-safe: stack offset + hover lift + swipe (all NumberAnimation).
        x: swipeX
        y: stackY - hoverLift
        z: entry && entry.exiting ? 100 + Math.max(0, root.stackMax - stackIndex)
            : root.stackMax - stackIndex
        visible: active || contentOpacity > 0.01 || Math.abs(swipeX) > 0.5
        opacity: contentOpacity

        onHeightChanged: root.recomputeStackHeight()
        onYChanged: root.recomputeStackHeight()
        onXChanged: root.recomputeStackHeight()

        Behavior on x {
            enabled: !cardRoot.swipeDragging
            NumberAnimation {
                duration: Motion.panelExit(root.settingsService)
                easing.type: Motion.emphasizedAccel
            }
        }
        Behavior on stackY {
            NumberAnimation {
                duration: Motion.elementMove(root.settingsService)
                easing.type: Motion.emphasizedDecel
            }
        }
        Behavior on hoverLift {
            NumberAnimation {
                duration: Motion.fadeFast(root.settingsService)
                easing.type: Motion.emphasizedDecel
            }
        }

        function syncFromEntry() {
            if (!active) {
                contentOpacity = 0;
                hoverLift = 0;
                if (!swipeDragging && Math.abs(swipeX) < 1)
                    swipeX = 0;
                return;
            }

            var targetScale = Motion.toastStackScaleForIndex(stackIndex);
            var targetY = Motion.toastStackYForIndex(stackIndex);
            stackY = targetY;
            animateScaleTo(targetScale);

            if (entry.exiting) {
                syncExitState();
                return;
            }

            dismissAfterSwipe.stop();
            dismissAfterSwipe.pending = false;
            dismissAfterSwipe.pendingId = -1;
            swipeDragging = false;
            swipeX = 0;
            contentOpacity = 1;

            // Only a truly new top entry increments enterSerial. Stable cards
            // changing stackIndex keep the same delegate and only move/scale.
            if (lastEnterSerial !== entry.enterSerial) {
                lastEnterSerial = entry.enterSerial;
                if (stackIndex === 0 && entry.enterSerial > 0) {
                    enterX = Motion.toastEnterOffsetPx;
                    Qt.callLater(function () {
                        if (cardRoot.entry && !cardRoot.entry.exiting
                                && cardRoot.stackIndex === 0)
                            cardRoot.animateEnterTo(0);
                    });
                } else {
                    enterX = 0;
                }
            }
        }

        function syncExitState() {
            if (!entry || !entry.exiting)
                return;
            if (entry.dismissRequested && interactionNotifId < 0 && notifId >= 0
                    && root.notificationsService
                    && root.notificationsService.setToastInteraction) {
                root.notificationsService.setToastInteraction(notifId, true);
                interactionNotifId = notifId;
            } else if (!entry.dismissRequested) {
                releaseToastInteraction();
            }
            pointerPressed = false;
            swipeDragging = false;
            hoverLift = 0;
            var direction = entry.exitDirection < 0 ? -1 : 1;
            dismissAfterSwipe.pending = true;
            dismissAfterSwipe.pendingId = notifId;
            swipeX = direction * (Math.max(1, cardRoot.width) + 48);
            contentOpacity = 0;
            dismissAfterSwipe.restart();
        }

        function releaseToastInteraction() {
            if (interactionNotifId < 0)
                return;
            if (root.notificationsService && root.notificationsService.setToastInteraction)
                root.notificationsService.setToastInteraction(interactionNotifId, false);
            interactionNotifId = -1;
        }

        function syncToastInteraction() {
            var nextId = interactionActive && notifId >= 0 ? notifId : -1;
            if (interactionNotifId === nextId)
                return;
            releaseToastInteraction();
            if (nextId >= 0 && root.notificationsService
                    && root.notificationsService.setToastInteraction) {
                root.notificationsService.setToastInteraction(nextId, true);
                interactionNotifId = nextId;
            }
        }

        onActiveChanged: {
            syncFromEntry();
            syncToastInteraction();
        }
        onNotifIdChanged: syncToastInteraction()
        onInteractionActiveChanged: syncToastInteraction()
        onStackIndexChanged: {
            if (active) {
                stackY = Motion.toastStackYForIndex(stackIndex);
                animateScaleTo(Motion.toastStackScaleForIndex(stackIndex));
            }
            syncToastInteraction();
        }

        onEntryChanged: {
            syncFromEntry();
            syncToastInteraction();
        }

        Connections {
            target: cardRoot.entry
            ignoreUnknownSignals: true

            function onExitingChanged() {
                if (cardRoot.entry && cardRoot.entry.exiting)
                    cardRoot.syncExitState();
                else
                    cardRoot.syncFromEntry();
                cardRoot.syncToastInteraction();
            }

            function onEnterSerialChanged() {
                cardRoot.syncFromEntry();
            }
        }

        Connections {
            target: cardRoot.entry ? cardRoot.entry.notification : null
            ignoreUnknownSignals: true

            function onAppNameChanged() { root.refreshDisplayEntry(cardRoot.notifId); }
            function onSummaryChanged() { root.refreshDisplayEntry(cardRoot.notifId); }
            function onBodyChanged() { root.refreshDisplayEntry(cardRoot.notifId); }
            function onImageChanged() { root.refreshDisplayEntry(cardRoot.notifId); }
            function onAppIconChanged() { root.refreshDisplayEntry(cardRoot.notifId); }
            function onDesktopEntryChanged() { root.refreshDisplayEntry(cardRoot.notifId); }
            function onUrgencyChanged() { root.refreshDisplayEntry(cardRoot.notifId); }
            function onActionsChanged() { root.refreshDisplayEntry(cardRoot.notifId); }
        }

        Component.onCompleted: {
            root.registerCardRegion(cardRoot.cardRegion);
            syncFromEntry();
            syncToastInteraction();
        }
        Component.onDestruction: {
            releaseToastInteraction();
            root.unregisterCardRegion(cardRoot.cardRegion);
        }

        function animateEnterTo(value) {
            enterSpring.stop();
            enterEase.stop();
            if (root.useSpring && !Motion.reducedMotion(root.settingsService)) {
                enterSpring.to = value;
                enterSpring.restart();
            } else {
                enterEase.to = value;
                enterEase.restart();
            }
        }

        function animateScaleTo(value) {
            // Stack scale is content-only and always eased (no spring): lower
            // cards settle to 0.96/0.92 without overshoot near glass bounds.
            scaleEase.stop();
            scaleEase.to = value;
            scaleEase.restart();
        }

        function clearPendingDismiss() {
            // Cancel/rebound/new-gesture: drop pending identity. Do not clear
            // on stack rebind alone — a late Timer must still target the
            // notification that was swiped, not the promoted replacement.
            dismissAfterSwipe.stop();
            dismissAfterSwipe.pending = false;
            dismissAfterSwipe.pendingId = -1;
        }

        function beginSwipe(px, py) {
            if (!interactive)
                return;
            swipeDragging = true;
            swipeMoved = false;
            swipeStartX = swipeX;
            swipePointerStartX = px;
            swipePointerStartY = py;
            // A new press supersedes any prior swipe-dismiss commit.
            cardRoot.clearPendingDismiss();
        }

        function advanceSwipe(px, py) {
            if (!swipeDragging)
                return;
            var dx = px - swipePointerStartX;
            var dy = py - swipePointerStartY;
            var vertical = Math.abs(dy);
            var horizontal = dx;
            var tol = IslandMotion.swipeVerticalTolerance;
            if (vertical > tol)
                horizontal = horizontal * Math.max(0, 1 - (vertical - tol) / 36);
            swipeX = swipeStartX + horizontal;
            if (Math.abs(swipeX - swipeStartX) > 4)
                swipeMoved = true;
        }

        function resolveSwipe() {
            if (!swipeDragging)
                return;
            swipeDragging = false;
            var w = Math.max(1, cardRoot.width);
            var progress = swipeX / w;
            var absPx = Math.abs(swipeX);
            var enter = IslandMotion.swipeEnterThreshold;
            if (Math.abs(progress) >= enter || absPx >= Motion.toastSwipeDismissPx) {
                // Capture stable id at commit time — not at Timer fire.
                var idAtCommit = cardRoot.notifId;
                if (idAtCommit < 0) {
                    cardRoot.clearPendingDismiss();
                    return;
                }
                dismissAfterSwipe.pending = true;
                dismissAfterSwipe.pendingId = idAtCommit;
                root.requestEntryExit(cardRoot.entry, swipeX >= 0 ? 1 : -1, true);
            } else {
                // Snap back: no dismiss; clear any stale pending identity.
                swipeX = 0;
                cardRoot.clearPendingDismiss();
            }
        }

        SpringAnimation {
            id: enterSpring
            target: cardRoot
            property: "enterX"
            spring: Motion.springPanel.spring
            damping: Motion.springPanel.damping
            epsilon: 0.001
        }
        NumberAnimation {
            id: enterEase
            target: cardRoot
            property: "enterX"
            duration: Motion.panelEnter(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }

        NumberAnimation {
            id: scaleEase
            target: cardRoot
            property: "contentScale"
            duration: Motion.elementMove(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }

        Timer {
            id: dismissAfterSwipe
            // pendingId is the only identity the delayed exit may act on.
            // The stable entry remains rendered even if the service has already
            // removed that id (timeout/client close).
            property bool pending: false
            property int pendingId: -1
            interval: Motion.panelExit(root.settingsService)
            repeat: false
            onTriggered: {
                var id = pendingId;
                var wasPending = pending;
                pending = false;
                pendingId = -1;
                if (wasPending && id >= 0)
                    root.completeEntryExit(id);
            }
        }

        Behavior on contentOpacity {
            NumberAnimation {
                duration: cardRoot.entry && cardRoot.entry.exiting
                    ? Motion.panelExit(root.settingsService)
                    : Motion.fadeFast(root.settingsService)
                easing.type: cardRoot.entry && cardRoot.entry.exiting
                    ? Motion.emphasizedAccel
                    : Motion.standardDecel
            }
        }

        GlassPanel {
            id: glass

            // Rest geometry only — no transform on GlassPanel (region tracks
            // item bounds; scale/enter must stay on contentHost). Swipe is
            // cardRoot.x (eased NumberAnimation, never Spring).
            x: 0
            y: 0
            width: parent.width
            height: parent.height
            material: GlassStyle.MaterialToast
            radius: GlassStyle.RadiusToast
            fillColor: GlassStyle.FillPanelBright
            strokeWidth: 0
            interaction: cardRoot.contentOpacity * (cardRoot.interactive && cardHover.hovered ? 1 : 0.85)
            materialAlpha: cardRoot.contentOpacity
            regionEnabled: cardRoot.active && root.shouldShowToast && cardRoot.contentOpacity > 0.01
                && !root.suppressedByDynamicIsland
            opacity: 1

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.color: cardRoot.accentColor
                border.width: 1
            }

            Item {
                id: contentHost
                anchors.fill: parent
                opacity: 1
                // Enter slide + stack scale: content transforms only (red line §2.1).
                // GlassPanel region stays at rest width/height.
                transform: [
                    Translate { x: cardRoot.enterX },
                    Scale {
                        origin.x: contentHost.width / 2
                        origin.y: 0
                        xScale: cardRoot.contentScale
                        yScale: cardRoot.contentScale
                    }
                ]

                Column {
                    id: contentColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 8

                    Item {
                        width: parent.width
                        height: 36

                        Rectangle {
                            id: iconBox
                            x: 0
                            y: 0
                            width: 36
                            height: 36
                            radius: 11
                            color: "#70ffffff"
                            border.color: "#60ffffff"

                            TahoeSymbol {
                                anchors.centerIn: parent
                                name: "\ue7f4"
                                color: "#3c4043"
                                size: 20
                                visible: !cardRoot.hasIcon
                            }

                            Image {
                                anchors.fill: parent
                                anchors.margins: 4
                                fillMode: Image.PreserveAspectCrop
                                source: cardRoot.iconUrl
                                visible: cardRoot.hasIcon
                                sourceSize.width: 64
                                sourceSize.height: 64
                                asynchronous: true
                            }
                        }

                        Text {
                            anchors.left: iconBox.right
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: cardRoot.interactive ? 28 : 0
                            anchors.verticalCenter: iconBox.verticalCenter
                            text: cardRoot.displayAppName
                            color: "#202124"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        width: parent.width
                        text: cardRoot.displaySummary
                        color: "#202124"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        visible: text.length > 0
                    }

                    Text {
                        width: parent.width
                        text: cardRoot.displayBody
                        color: "#5f6368"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 4
                        visible: text.length > 0
                    }

                    Row {
                        width: parent.width
                        spacing: 8
                        layoutDirection: Qt.RightToLeft
                        visible: cardRoot.actionItems.length > 0

                        Repeater {
                            model: cardRoot.actionItems

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                height: 26
                                width: actionLabel.implicitWidth + 22
                                radius: 13
                                color: actionMouse.containsMouse ? "#a0ffffff" : "#60ffffff"
                                border.color: "#50ffffff"

                                Text {
                                    id: actionLabel
                                    anchors.centerIn: parent
                                    text: {
                                        var t = String(modelData.text || "");
                                        if (t.length > 0)
                                            return t;
                                        return String(modelData.identifier || "");
                                    }
                                    color: "#1a73e8"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: actionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: cardRoot.pointerPressed = true
                                    onReleased: cardRoot.pointerPressed = false
                                    onCanceled: cardRoot.pointerPressed = false
                                    onClicked: root.invokeAction(cardRoot.entry, modelData.identifier)
                                }
                            }
                        }
                    }
                }
            }

            HoverHandler {
                id: cardHover
                enabled: cardRoot.interactive
                onHoveredChanged: {
                    if (hovered)
                        cardRoot.hoverLift = Motion.toastHoverLiftPx;
                    else if (!closeMouse.containsMouse)
                        cardRoot.hoverLift = 0;
                }
            }

            Item {
                id: closeBtn
                width: 22
                height: 22
                x: 8
                y: 8
                z: 5
                visible: cardRoot.interactive
                         && (cardHover.hovered || closeMouse.containsMouse)

                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: closeMouse.containsMouse ? "#90ffffff" : "#60ffffff"
                    border.color: "#50ffffff"
                }

                TahoeSymbol {
                    anchors.centerIn: parent
                    name: "\ue5cd"
                    color: "#3c4043"
                    size: 14
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: cardRoot.pointerPressed = true
                    onReleased: cardRoot.pointerPressed = false
                    onCanceled: cardRoot.pointerPressed = false
                    onClicked: root.dismissNotification(cardRoot.entry)
                    onContainsMouseChanged: {
                        if (!containsMouse && !cardHover.hovered)
                            cardRoot.hoverLift = 0;
                    }
                }
            }

            MouseArea {
                id: swipeArea
                anchors.fill: parent
                z: -1
                enabled: cardRoot.interactive
                cursorShape: Qt.PointingHandCursor
                preventStealing: true

                onPressed: function (mouse) {
                    cardRoot.pointerPressed = true;
                    cardRoot.beginSwipe(mouse.x, mouse.y);
                }
                onPositionChanged: function (mouse) {
                    if (pressed)
                        cardRoot.advanceSwipe(mouse.x, mouse.y);
                }
                onReleased: function (mouse) {
                    cardRoot.pointerPressed = false;
                    if (cardRoot.swipeMoved) {
                        cardRoot.resolveSwipe();
                    } else {
                        cardRoot.swipeDragging = false;
                        cardRoot.swipeX = 0;
                        root.dismissNotification(cardRoot.entry);
                    }
                }
                onCanceled: {
                    cardRoot.pointerPressed = false;
                    cardRoot.swipeDragging = false;
                    cardRoot.swipeX = 0;
                    cardRoot.clearPendingDismiss();
                }
            }
        }
    }
}
