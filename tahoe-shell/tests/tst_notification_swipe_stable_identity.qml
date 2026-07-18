pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// Real Tahoe qs probe. qmltestrunner cannot load Quickshell's statically linked
// ScriptModel plugin, so the Python harness runs this file through qs and injects
// the production NotificationToast path below.
ShellRoot {
    id: testCase

    property string toastSource: ""
    property var toast: null
    property var ownedNotifications: []
    property var dismissedIds: []
    property var stable10: null
    property var stable20: null
    property var stable30: null
    property var stable53: null
    property var stable54: null
    property int replacePhase: 0
    property int stage: 0

    QtObject {
        id: notifService

        property var activeModel: []
        property var interactionMap: ({})
        readonly property int activeCount: activeModel.length
        readonly property var current: activeModel.length > 0
            ? activeModel[activeModel.length - 1] : null
        signal notificationUpdated(real id)

        function visibleStack(max) {
            var count = Math.max(0, Math.min(max, activeModel.length));
            var out = [];
            for (var i = activeModel.length - 1; i >= 0 && out.length < count; i--)
                out.push(activeModel[i]);
            return out;
        }

        function dismissId(id, reason) {
            testCase.dismissedIds = testCase.dismissedIds.concat([Number(id)]);
            removeWithoutDismiss(id);
        }

        function removeWithoutDismiss(id) {
            var next = [];
            for (var i = 0; i < activeModel.length; i++) {
                if (Number(activeModel[i].id) !== Number(id))
                    next.push(activeModel[i]);
            }
            activeModel = next;
        }

        function findActiveById(id) {
            for (var i = 0; i < activeModel.length; i++) {
                if (Number(activeModel[i].id) === Number(id))
                    return activeModel[i];
            }
            return null;
        }

        function iconUrlFor(notification) { return ""; }
        function invokeAction(id, identifier) {}
        function setToastInteraction(id, active) {
            var next = {};
            var key = String(Number(id));
            for (var existing in interactionMap) {
                if (Object.prototype.hasOwnProperty.call(interactionMap, existing)
                        && existing !== key)
                    next[existing] = interactionMap[existing];
            }
            if (active)
                next[key] = true;
            interactionMap = next;
        }
    }

    QtObject {
        id: settings
        property int notificationToastStackMax: 3
        property bool dynamicIslandEnabled: false
        property string motionProfile: "normal"
    }

    Component {
        id: notificationFactory

        QtObject {
            property real id: -1
            property string summary: ""
            property string body: ""
            property string appName: "Test"
            property string appIcon: ""
            property string desktopEntry: ""
            property string image: ""
            property int urgency: 1
            property var actions: []
        }
    }

    Timer {
        id: stepTimer
        interval: 20
        repeat: false
        onTriggered: testCase.advance()
    }

    function fail(message) {
        console.error("NOTIFICATION_STACK_FAIL: " + message);
        cleanupToast();
        Qt.exit(1);
    }

    function require(condition, message) {
        if (!condition) {
            fail(message);
            return false;
        }
        return true;
    }

    function schedule(nextStage, delayMs) {
        stage = nextStage;
        stepTimer.interval = Math.max(1, delayMs);
        stepTimer.restart();
    }

    function makeNotif(id) {
        var notification = notificationFactory.createObject(testCase, {
            "id": id,
            "summary": "summary-" + id,
            "body": "body-" + id,
            "appName": "app-" + id
        });
        if (!notification) {
            fail("could not create notification " + id);
            return null;
        }
        ownedNotifications = ownedNotifications.concat([notification]);
        return notification;
    }

    function countDismissed(id) {
        var count = 0;
        for (var i = 0; i < dismissedIds.length; i++) {
            if (Number(dismissedIds[i]) === Number(id))
                count += 1;
        }
        return count;
    }

    function findCard(id) {
        if (!toast)
            return null;
        function walk(node) {
            if (!node)
                return null;
            if (node.notifId !== undefined && Number(node.notifId) === Number(id)
                    && node.resolveSwipe !== undefined)
                return node;
            var children = node.children || [];
            for (var i = 0; i < children.length; i++) {
                var found = walk(children[i]);
                if (found)
                    return found;
            }
            return null;
        }
        return walk(toast.contentItem || toast);
    }

    function findDismissTimer(card) {
        if (!card)
            return null;
        var data = card.data || [];
        for (var i = 0; i < data.length; i++) {
            var item = data[i];
            if (item && item.pendingId !== undefined && item.interval !== undefined)
                return item;
        }
        return null;
    }

    function cleanupToast() {
        stepTimer.stop();
        if (toast) {
            toast.destroy();
            toast = null;
        }
        for (var i = 0; i < ownedNotifications.length; i++) {
            if (ownedNotifications[i] && ownedNotifications[i].destroy)
                ownedNotifications[i].destroy();
        }
        ownedNotifications = [];
    }

    function finish() {
        console.log("NOTIFICATION_STACK_OK");
        cleanupToast();
        Qt.quit();
    }

    function startProbe() {
        if (!require(toastSource.length > 0, "toastSource was not injected"))
            return;
        var component = Qt.createComponent("file://" + toastSource);
        if (!require(component.status === Component.Ready,
                "toast compile: " + component.errorString()))
            return;
        toast = component.createObject(null, {
            "notificationsService": notifService,
            "settingsService": settings,
            "dynamicIslandService": null,
            "useSpring": false
        });
        if (!require(toast !== null, "toast creation"))
            return;

        var n10 = makeNotif(10);
        var n20 = makeNotif(20);
        var n30 = makeNotif(30);
        notifService.activeModel = [n10, n20, n30];
        schedule(1, 180);
    }

    function advance() {
        if (stage === 0) {
            startProbe();
            return;
        }

        if (stage === 1) {
            stable10 = findCard(10);
            stable20 = findCard(20);
            stable30 = findCard(30);
            if (!require(stable10 && stable20 && stable30, "initial three cards")
                    || !require(stable30.stackIndex === 0
                        && stable20.stackIndex === 1 && stable10.stackIndex === 2,
                        "initial stack order"))
                return;
            if (replacePhase === 0) {
                replacePhase = 1;
                ownedNotifications[2].summary = "summary-30-updated";
                ownedNotifications[2].urgency = 2;
                ownedNotifications[2].actions = [{ "identifier": "open", "text": "Open" }];
                schedule(1, 40);
                return;
            }
            if (replacePhase === 1) {
                if (!require(findCard(30) === stable30,
                        "replace-id mutation preserves delegate")
                        || !require(stable30.displaySummary === "summary-30-updated",
                            "live summary mutation reaches stable card")
                        || !require(stable30.actionItems.length === 1,
                            "live action mutation reaches stable card"))
                    return;
                replacePhase = 2;
                var replacement30 = makeNotif(30);
                replacement30.summary = "summary-30-reentered";
                notifService.activeModel = [
                    notifService.activeModel[0],
                    notifService.activeModel[1],
                    replacement30
                ];
                schedule(1, 40);
                return;
            }
            if (!require(findCard(30) === stable30,
                    "same-id replacement preserves delegate")
                    || !require(stable30.liveNotification === notifService.activeModel[2],
                        "same-id replacement updates live object")
                    || !require(stable30.displaySummary === "summary-30-reentered",
                        "same-id replacement updates content"))
                return;
            notifService.activeModel = notifService.activeModel.concat([makeNotif(40)]);
            schedule(2, 180);
            return;
        }

        if (stage === 2) {
            var card40 = findCard(40);
            if (!require(card40 && card40.stackIndex === 0, "new top card")
                    || !require(findCard(30) === stable30 && stable30.stackIndex === 1,
                        "30 delegate must move in place")
                    || !require(findCard(20) === stable20 && stable20.stackIndex === 2,
                        "20 delegate must move in place"))
                return;
            card40.width = 300;
            card40.beginSwipe(0, 0);
            card40.advanceSwipe(400, 0);
            card40.resolveSwipe();
            var timer40 = findDismissTimer(card40);
            if (!require(timer40 && timer40.pending && timer40.pendingId === 40,
                    "swipe captured id 40"))
                return;
            // Canonical race: service removes A while its delayed exit is live.
            notifService.dismissId(40, "external");
            schedule(3, 30);
            return;
        }

        if (stage === 3) {
            if (!require(findCard(40) !== null, "40 retained through exit")
                    || !require(findCard(30) === stable30 && stable30.stackIndex === 0,
                        "30 promoted in place during 40 exit")
                    || !require(countDismissed(30) === 0,
                        "40 exit must not dismiss promoted 30")
                    || !require(notifService.interactionMap["40"] === true,
                        "local swipe keeps expiration paused through exit"))
                return;
            schedule(4, 230);
            return;
        }

        if (stage === 4) {
            if (!require(findCard(40) === null, "40 retired after exit")
                    || !require(findCard(30) === stable30, "30 identity survived swipe race")
                    || !require(countDismissed(30) === 0, "30 still not dismissed")
                    || !require(notifService.interactionMap["40"] === undefined,
                        "swipe expiration pause released after exit"))
                return;
            // Timeout/client-close removes from the service first. The view must
            // synthesize the same slide+fade and hold the mapped surface.
            notifService.removeWithoutDismiss(30);
            schedule(5, 40);
            return;
        }

        if (stage === 5) {
            var exiting30 = findCard(30);
            if (!require(exiting30 && exiting30.entry.exiting,
                    "timeout card retained as exiting")
                    || !require(toast.visible, "surface held during timeout exit")
                    || !require(findCard(20) === stable20 && stable20.stackIndex === 0,
                        "20 promoted in place during timeout exit"))
                return;
            schedule(6, 230);
            return;
        }

        if (stage === 6) {
            if (!require(findCard(30) === null, "timeout card retired")
                    || !require(findCard(20) === stable20, "20 identity survived timeout"))
                return;
            // 10 may have legitimately retired while it was outside the three-card
            // visible stack; capture its current stable delegate before promotion.
            stable10 = findCard(10);
            if (!require(stable10 !== null, "10 visible before X promotion"))
                return;
            // Direct function call is the close-button command path.
            toast.dismissNotification(stable20.entry);
            schedule(7, 40);
            return;
        }

        if (stage === 7) {
            if (!require(findCard(20) === stable20 && stable20.entry.exiting,
                    "X path retains card through exit")
                    || !require(findCard(10) === stable10 && stable10.stackIndex === 0,
                        "10 promoted in place during X exit")
                    || !require(toast.visible, "surface held during X exit"))
                return;
            if (!require(notifService.interactionMap["20"] === true,
                    "X keeps expiration paused through exit"))
                return;
            schedule(8, 230);
            return;
        }

        if (stage === 8) {
            if (!require(findCard(20) === null, "X card retired")
                    || !require(countDismissed(20) === 1, "X dismisses id 20 once")
                    || !require(notifService.interactionMap["20"] === undefined,
                        "X expiration pause released after exit"))
                return;
            var burst = [];
            for (var id = 50; id <= 54; id++) {
                burst.push(makeNotif(id));
                notifService.activeModel = burst.slice();
            }
            if (!require(toast.displayCount <= 6,
                    "notification storm bounds active plus exiting wrappers"))
                return;
            schedule(9, 260);
            return;
        }

        if (stage === 9) {
            stable53 = findCard(53);
            stable54 = findCard(54);
            if (!require(toast.displayCount === 3, "five-notification burst settles to three cards")
                    || !require(toast.cardRegions.length === 3,
                        "five-notification burst settles to three glass regions")
                    || !require(stable54 && stable54.stackIndex === 0,
                        "burst top 54")
                    || !require(stable53 && stable53.stackIndex === 1,
                        "burst second 53")
                    || !require(findCard(52) && findCard(52).stackIndex === 2,
                        "burst third 52"))
                return;
            notifService.activeModel = notifService.activeModel.concat([makeNotif(55)]);
            schedule(10, 40);
            return;
        }

        if (stage === 10) {
            if (!require(findCard(55) && findCard(55).stackIndex === 0,
                    "rapid new top 55")
                    || !require(findCard(54) === stable54 && stable54.stackIndex === 1,
                        "54 moved in place")
                    || !require(findCard(53) === stable53 && stable53.stackIndex === 2,
                        "53 moved in place")
                    || !require(findCard(52) && findCard(52).entry.exiting,
                        "bottom card exits without slot competition"))
                return;
            schedule(11, 230);
            return;
        }

        if (stage === 11) {
            if (!require(findCard(52) === null, "displaced bottom retired")
                    || !require(findCard(54) === stable54 && findCard(53) === stable53,
                        "burst survivors preserve identity"))
                return;
            notifService.activeModel = [];
            schedule(12, 260);
            return;
        }

        if (stage === 12) {
            if (!require(toast.displayCount === 0, "all exit delegates retired")
                    || !require(!toast.visible, "toast unmaps after final QML exit"))
                return;
            settings.notificationToastStackMax = 3;
            notifService.activeModel = [makeNotif(70), makeNotif(71), makeNotif(72)];
            schedule(13, 180);
            return;
        }

        if (stage === 13) {
            var card72 = findCard(72);
            if (!require(card72 && card72.stackIndex === 0, "shrink-race top 72"))
                return;
            toast.dismissNotification(card72.entry);
            schedule(14, 20);
            return;
        }

        if (stage === 14) {
            var card71 = findCard(71);
            if (!require(card71 && card71.stackIndex === 0, "shrink-race top 71"))
                return;
            toast.dismissNotification(card71.entry);
            schedule(15, 20);
            return;
        }

        if (stage === 15) {
            var card70 = findCard(70);
            if (!require(card70 && card70.stackIndex === 0, "shrink-race top 70"))
                return;
            toast.dismissNotification(card70.entry);
            settings.notificationToastStackMax = 1;
            schedule(16, 30);
            return;
        }

        if (stage === 16) {
            if (!require(toast.displayCount <= 3,
                    "stack-max shrink bounds retained exit wrappers")
                    || !require(toast.cardRegions.length <= 3,
                        "stack-max shrink bounds registered glass regions"))
                return;
            schedule(17, 260);
            return;
        }

        if (stage === 17) {
            if (!require(countDismissed(72) === 1 && countDismissed(71) === 1
                        && countDismissed(70) === 1,
                    "stack-max shrink settles every dismiss exactly once")
                    || !require(notifService.activeModel.length === 0,
                        "stack-max shrink leaves no dismissed notification queued")
                    || !require(toast.displayCount === 0 && !toast.visible,
                        "stack-max shrink retires all exit delegates"))
                return;
            var largeId = 4000000000;
            notifService.activeModel = [makeNotif(largeId)];
            schedule(18, 180);
            return;
        }

        if (stage === 18) {
            var largeIdCard = findCard(4000000000);
            if (!require(largeIdCard && largeIdCard.notifId === 4000000000,
                    "uint32 notification id reaches toast without narrowing"))
                return;
            var largeIdLive = largeIdCard.liveNotification;
            largeIdCard.entry.notification = null;
            largeIdCard.entry.summary = "stale-large-id";
            largeIdLive.summary = "summary-4000000000-updated";
            notifService.notificationUpdated(4000000000);
            schedule(19, 40);
            return;
        }

        if (stage === 19) {
            var largeIdCard = findCard(4000000000);
            if (!require(largeIdCard && largeIdCard.liveNotification
                        === notifService.activeModel[0],
                    "uint32 service update resolves the live notification")
                    || !require(largeIdCard.displaySummary
                        === "summary-4000000000-updated",
                        "uint32 service update refreshes stable content"))
                return;
            toast.dismissNotification(largeIdCard.entry);
            var largeIdTimer = findDismissTimer(largeIdCard);
            if (!require(largeIdTimer && largeIdTimer.pendingId === 4000000000,
                    "uint32 notification id reaches delayed dismiss without narrowing"))
                return;
            schedule(20, 260);
            return;
        }

        if (stage === 20) {
            if (!require(countDismissed(4000000000) === 1,
                    "uint32 notification id dismisses exactly once")
                    || !require(notifService.activeModel.length === 0,
                        "uint32 notification id leaves no queued notification")
                    || !require(toast.displayCount === 0 && !toast.visible,
                        "uint32 notification id exit retires and unmaps"))
                return;
            finish();
        }
    }

    Component.onCompleted: schedule(0, 20)
}
