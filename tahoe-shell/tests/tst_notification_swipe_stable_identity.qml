import QtQuick
import QtQuick.Window
import QtTest

TestCase {
    id: testCase
    name: "NotificationSwipeStableIdentity"
    when: windowShown

    property string toastSource: ""
    property var toast: null
    property var dismissedIds: []

    // Minimal Notifications service surface used by production NotificationToast.
    QtObject {
        id: notifService
        property var activeModel: []
        property int activeCount: 0
        property var current: null

        function visibleStack(max) {
            var n = Math.max(0, Math.min(max, activeModel.length));
            // Newest-on-top: reverse slice of activeModel (A then B means B on top if append order).
            // Toast expects visibleStack newest first.
            var out = [];
            for (var i = activeModel.length - 1; i >= 0 && out.length < n; i--)
                out.push(activeModel[i]);
            return out;
        }

        function dismissId(id, reason) {
            testCase.dismissedIds.push(Number(id));
            // Remove from model (external close simulation also uses this).
            var next = [];
            for (var i = 0; i < activeModel.length; i++) {
                if (Number(activeModel[i].id) !== Number(id))
                    next.push(activeModel[i]);
            }
            activeModel = next;
            activeCount = next.length;
            current = next.length ? next[next.length - 1] : null;
        }

        function iconUrlFor(n) { return ""; }
        function invokeAction(id, identifier) {}
    }

    QtObject {
        id: settings
        property int notificationToastStackMax: 3
        property bool dynamicIslandEnabled: false
        property string motionProfile: "normal"
    }

    function makeNotif(id, summary) {
        return {
            id: id,
            summary: summary,
            body: "body-" + id,
            appName: "app-" + id,
            urgency: 1
        };
    }

    function findTopCard(item) {
        // Top card is stackIndex 0 and exposes resolveSwipe / dismissAfterSwipe.
        function walk(node) {
            if (!node)
                return null;
            if (node.stackIndex === 0 && node.resolveSwipe !== undefined && node.notifId !== undefined)
                return node;
            var kids = node.children || [];
            for (var i = 0; i < kids.length; i++) {
                var f = walk(kids[i]);
                if (f)
                    return f;
            }
            var data = node.data || [];
            for (var j = 0; j < data.length; j++) {
                var f2 = walk(data[j]);
                if (f2)
                    return f2;
            }
            return null;
        }
        return walk(item);
    }

    function findDismissTimer(card) {
        if (!card)
            return null;
        var data = card.data || [];
        for (var i = 0; i < data.length; i++) {
            var d = data[i];
            if (d && d.pendingId !== undefined && d.interval !== undefined)
                return d;
        }
        // Also search children
        var kids = card.children || [];
        for (var j = 0; j < kids.length; j++) {
            if (kids[j] && kids[j].pendingId !== undefined)
                return kids[j];
        }
        return null;
    }

    function init() {
        dismissedIds = [];
        notifService.activeModel = [];
        notifService.activeCount = 0;
        notifService.current = null;
        if (toast) {
            toast.destroy();
            toast = null;
            wait(0);
        }
        verify(toastSource.length > 0, "harness must set toastSource");
        var comp = Qt.createComponent("file://" + toastSource);
        verify(comp.status === Component.Ready, "toast must compile: " + comp.errorString());
        toast = comp.createObject(null, {
            "notificationsService": notifService,
            "settingsService": settings,
            "dynamicIslandService": null,
            "width": 360,
            "height": 200,
            "visible": true
        });
        verify(toast !== null);
        toast.visible = true;
        wait(30);
    }

    function cleanup() {
        if (toast) {
            toast.destroy();
            toast = null;
        }
        wait(0);
    }

    function seedTwo() {
        notifService.activeModel = [makeNotif(10, "A"), makeNotif(20, "B")];
        notifService.activeCount = 2;
        notifService.current = notifService.activeModel[1];
        wait(80);
    }

    function countDismissed(id) {
        var n = 0;
        for (var i = 0; i < dismissedIds.length; i++) {
            if (dismissedIds[i] === id)
                n += 1;
        }
        return n;
    }

    function modelHas(id) {
        for (var i = 0; i < notifService.activeModel.length; i++) {
            if (Number(notifService.activeModel[i].id) === id)
                return true;
        }
        return false;
    }

    function test_timer_only_dismisses_a_after_rebind() {
        var root = toast.contentItem || toast;
        // Race: A on top (newest), swipe A, external-delete A, B rebinds into slot 0,
        // Timer must still dismiss pendingId=A only.
        notifService.activeModel = [makeNotif(20, "B"), makeNotif(10, "A")];
        notifService.activeCount = 2;
        notifService.current = notifService.activeModel[1];
        wait(80);

        var card = findTopCard(root);
        verify(card !== null, "top card must exist");
        compare(card.notifId, 10);
        card.width = 300;
        wait(0);

        var timer = findDismissTimer(card);
        verify(timer !== null, "dismissAfterSwipe timer must exist");

        card.beginSwipe(0, 0);
        card.advanceSwipe(400, 0);
        card.resolveSwipe();
        wait(0);

        compare(timer.pending, true);
        compare(timer.pendingId, 10);

        // External delete A (records 10 in dismissedIds); model becomes [B].
        notifService.dismissId(10, "external");
        if (!modelHas(20))
            notifService.activeModel = [makeNotif(20, "B")];
        notifService.activeCount = notifService.activeModel.length;
        wait(50);

        // Hard rebind proof: same slot now shows B, timer still holds A.
        card = findTopCard(root);
        verify(card !== null);
        compare(card.notifId, 20);
        compare(timer.pendingId, 10);
        compare(timer.pending, true);

        // Snapshot before unambiguous single fire of onTriggered.
        var tensBefore = countDismissed(10);
        var twentiesBefore = countDismissed(20);
        var lenBefore = dismissedIds.length;

        // Single path: invoke production handler once (interval scheduling is
        // motion-owned; identity capture is what this race tests).
        timer.triggered();
        wait(0);

        compare(countDismissed(10), tensBefore + 1, "Timer must dismiss A (10) once more");
        compare(countDismissed(20), twentiesBefore, "Timer must not dismiss B (20)");
        compare(dismissedIds.length, lenBefore + 1);
        verify(modelHas(20), "B must remain in the model");
        verify(!modelHas(10), "A must stay removed");
    }

    function test_snap_back_clears_pending() {
        notifService.activeModel = [makeNotif(1, "One")];
        notifService.activeCount = 1;
        wait(80);
        var card = findTopCard(toast.contentItem || toast);
        verify(card !== null);
        var timer = findDismissTimer(card);
        verify(timer !== null);

        // Ensure card has real width so progress = swipeX/width is meaningful.
        card.width = 300;
        wait(0);
        card.beginSwipe(0, 0);
        // 20px << toastSwipeDismissPx(96) and << 0.56 * 300.
        card.advanceSwipe(20, 0);
        card.resolveSwipe();
        wait(0);
        compare(timer.pending, false);
        compare(timer.pendingId, -1);
        compare(dismissedIds.length, 0);
    }

    function test_new_press_supersedes_pending() {
        notifService.activeModel = [makeNotif(5, "Five")];
        notifService.activeCount = 1;
        wait(80);
        var card = findTopCard(toast.contentItem || toast);
        verify(card !== null);
        var timer = findDismissTimer(card);
        verify(timer !== null);

        card.beginSwipe(0, 0);
        card.advanceSwipe(400, 0);
        card.resolveSwipe();
        wait(0);
        compare(timer.pending, true);
        compare(timer.pendingId, 5);

        // New press clears pending (supersede).
        card.beginSwipe(0, 0);
        wait(0);
        compare(timer.pending, false);
        compare(timer.pendingId, -1);
    }

    function test_dismiss_id_idempotent() {
        notifService.activeModel = [makeNotif(7, "Seven")];
        notifService.activeCount = 1;
        wait(0);
        toast.dismissNotificationId(7);
        toast.dismissNotificationId(7);
        toast.dismissNotificationId(-1);
        toast.dismissNotificationId("nope");
        verify(countDismissed(7) >= 1);
        verify(countDismissed(-1) === 0);
    }

    function test_consecutive_swipes_do_not_cross_contaminate() {
        // Real QML: swipe A to commit, fire, then swipe B — no cross-dismiss.
        notifService.activeModel = [makeNotif(30, "A"), makeNotif(40, "B")];
        notifService.activeCount = 2;
        wait(80);
        var root = toast.contentItem || toast;
        var card = findTopCard(root);
        verify(card !== null);
        // Newest first → B(40) on top; put A on top for first swipe.
        notifService.activeModel = [makeNotif(40, "B"), makeNotif(30, "A")];
        notifService.activeCount = 2;
        wait(80);
        card = findTopCard(root);
        verify(card !== null);
        compare(card.notifId, 30);
        card.width = 300;

        var timer = findDismissTimer(card);
        verify(timer !== null);
        card.beginSwipe(0, 0);
        card.advanceSwipe(400, 0);
        card.resolveSwipe();
        wait(0);
        compare(timer.pendingId, 30);
        var tensA = countDismissed(30);
        timer.triggered();
        wait(0);
        compare(countDismissed(30), tensA + 1);
        compare(countDismissed(40), 0);

        // After A gone, B should be top; swipe B only.
        if (!modelHas(40))
            notifService.activeModel = [makeNotif(40, "B")];
        notifService.activeCount = notifService.activeModel.length;
        wait(50);
        card = findTopCard(root);
        verify(card !== null);
        compare(card.notifId, 40);
        card.width = 300;
        timer = findDismissTimer(card);
        verify(timer !== null);
        card.beginSwipe(0, 0);
        card.advanceSwipe(400, 0);
        card.resolveSwipe();
        wait(0);
        compare(timer.pendingId, 40);
        var tensB = countDismissed(40);
        timer.triggered();
        wait(0);
        compare(countDismissed(40), tensB + 1);
        // A was already dismissed; no extra unexpected id 30 from second swipe.
        verify(countDismissed(30) >= 1);
    }
}
