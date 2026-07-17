import QtQuick
import QtTest
import "../services" as Services

TestCase {
    id: testCase
    name: "R13NotificationLifecycle"
    when: windowShown

    property var ownedNotifications: []

    Services.Notifications {
        id: notifications
    }

    Component {
        id: notificationComponent

        QtObject {
            property int id: -1
            property string appName: "Test"
            property string summary: "Summary"
            property string body: "Body"
            property string appIcon: ""
            property string desktopEntry: ""
            property string image: ""
            property int urgency: 1
            property real expireTimeout: 0
            property bool tracked: false
            property var hints: ({})
            property var actions: []
            property int expireCalls: 0
            property int dismissCalls: 0

            signal closed(int reason)

            function expire() {
                expireCalls += 1;
                closed(1);
            }

            function dismiss() {
                dismissCalls += 1;
                closed(2);
            }
        }
    }

    function makeNotification(id) {
        var notification = notificationComponent.createObject(testCase, { "id": id });
        verify(notification !== null);
        ownedNotifications.push(notification);
        return notification;
    }

    function init() {
        notifications.activeModel = [];
        notifications.historyModel = [];
        notifications.expireMap = ({});
        notifications.pausedExpireMap = ({});
        notifications.toastInteractionMap = ({});
        notifications.dndEnabled = false;
    }

    function cleanup() {
        notifications.activeModel = [];
        notifications.expireMap = ({});
        notifications.pausedExpireMap = ({});
        notifications.toastInteractionMap = ({});
        for (var i = 0; i < ownedNotifications.length; i++)
            ownedNotifications[i].destroy();
        ownedNotifications = [];
    }

    function test_hover_or_press_pauses_and_resumes_remaining_deadline() {
        var notification = makeNotification(13);
        notifications.handleIncoming(notification);
        notifications.scheduleExpire(13, 220);
        wait(50);

        notifications.setToastInteraction(13, true);
        verify(notifications.toastInteractionMap["13"] === true);
        verify(notifications.expireMap["13"] === undefined);
        var remaining = Number(notifications.pausedExpireMap["13"]);
        verify(remaining > 0 && remaining < 220);

        wait(240);
        compare(notification.expireCalls, 0);
        compare(notifications.activeCount, 1);

        notifications.setToastInteraction(13, false);
        verify(notifications.toastInteractionMap["13"] === undefined);
        verify(Number(notifications.expireMap["13"]) > Date.now());
        wait(Math.ceil(remaining) + 80);
        compare(notification.expireCalls, 1);
        compare(notifications.activeCount, 0);
    }

    function test_enabling_dnd_withdraws_banners_but_keeps_history() {
        var first = makeNotification(21);
        var second = makeNotification(22);
        notifications.handleIncoming(first);
        notifications.handleIncoming(second);
        compare(notifications.activeCount, 2);
        compare(notifications.historyCount, 2);

        notifications.dndEnabled = true;
        compare(notifications.activeCount, 0);
        compare(notifications.historyCount, 2);
        compare(first.dismissCalls, 1);
        compare(second.dismissCalls, 1);

        var suppressed = makeNotification(23);
        notifications.handleIncoming(suppressed);
        compare(notifications.activeCount, 0);
        compare(notifications.historyCount, 3);
        compare(suppressed.expireCalls, 1);
    }
}
