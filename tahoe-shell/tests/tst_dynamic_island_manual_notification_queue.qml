import QtQuick
import QtTest
import "../services" as Services

TestCase {
    id: testCase
    name: "DynamicIslandManualNotificationQueue"
    when: windowShown

    property var island: null

    QtObject {
        id: notifications
        property var activeModel: []
        property bool dndEnabled: false
        // notificationUpdated is not a property change signal.
        signal notificationUpdated(int id)

        function findActiveById(id) {
            var nid = Number(id);
            for (var i = 0; i < activeModel.length; i++) {
                if (Number(activeModel[i].id) === nid)
                    return activeModel[i];
            }
            return null;
        }

        function presentationHead() {
            return activeModel.length > 0 ? activeModel[0] : null;
        }
    }

    QtObject {
        id: settings
        property bool dynamicIslandEnabled: true
        property bool dynamicIslandHideTopbarTime: true
        property string dynamicIslandLeftClickAction: "toggle_media"
        property string dynamicIslandRightClickAction: "control_center"
        property bool dynamicIslandAutoExpandMedia: false
        property bool dynamicIslandHoverExpand: false
    }

    QtObject {
        id: controls
        property real volume: 0.5
        property bool muted: false
        property real brightness: 1.0
        property bool brightnessAvailable: false
        property bool hasMedia: false
        property string trackArtUrl: ""
        property bool isPlaying: false
        property real trackPosition: 0
        property real trackLength: 0
        property real trackProgress: 0
        property bool trackPositionSupported: false
        property bool trackLengthSupported: false
    }

    QtObject {
        id: windows
        property string activeWorkspaceName: ""
    }

    Component {
        id: islandComponent
        Services.DynamicIsland {}
    }

    function init() {
        notifications.activeModel = [];
        notifications.dndEnabled = false;
        settings.dynamicIslandEnabled = true;
        island = islandComponent.createObject(testCase, {
            notificationsService: notifications,
            settingsService: settings,
            controlsService: controls,
            windowsService: windows
        });
        verify(island !== null);
        // Stop auto timers from interfering; tests drive show/drain explicitly.
        wait(0);
        island.reset();
        // Fresh tracking: empty completed set for clean presents.
        island.completedNotificationIds = ({});
        island.seenNotificationIds = ({});
        wait(0);
    }

    function cleanup() {
        if (island) {
            island.destroy();
            island = null;
        }
        wait(0);
    }

    function liveNotif(id, summary) {
        return {
            id: id,
            summary: summary,
            body: "body-" + id,
            appName: "app-" + id
        };
    }

    function test_manual_queues_while_busy_and_shows_after() {
        island.userInteracting = true;
        island.showTransientNotification("Manual A", "body A");
        compare(island.presentation !== "transient_notification", true);
        compare(island.pendingNotificationIds.length, 1);
        compare(island.pendingNotificationIds[0].kind, "manual");
        compare(island.pendingNotificationIds[0].summary, "Manual A");

        island.userInteracting = false;
        island.maybeShowPendingNotification();
        compare(island.presentation, "transient_notification");
        compare(island.transientDisplayText, "Manual A");
        compare(island.pendingNotificationIds.length, 0);
        compare(island.displayingNotificationId, -1);
    }

    function test_manual_and_live_fifo_order() {
        // T07: manual IPC queue is separate; live order is Notifications.activeModel.
        island.userInteracting = true;
        island.showTransientNotification("Manual First", "m");
        notifications.activeModel = [
            liveNotif(10, "Live Ten"),
            liveNotif(20, "Live Twenty")
        ];
        island.handleNotificationsChanged();
        // Only manual remains on island pending queue.
        compare(island.pendingNotificationIds.length, 1);
        compare(island.pendingNotificationIds[0].kind, "manual");
        compare(island.pendingNotificationIds[0].summary, "Manual First");

        island.userInteracting = false;
        if (island.presentation !== "transient_notification")
            island.maybeShowPendingNotification();
        compare(island.transientDisplayText, "Manual First");
        compare(island.displayingNotificationId, -1);
        compare(island.pendingNotificationIds.length, 0);

        // Hide manual presentation, then live FIFO head (10) should present.
        // Clear lease fields first, then forcedState so restore drain can present live.
        island.displayingNotificationId = -1;
        island.forcedState = "";
        // forcedState change recomputes presentation and drains pending/live FIFO.
        wait(0);
        if (island.presentation !== "transient_notification")
            island.maybeShowPendingNotification();
        compare(island.transientDisplayText, "Live Ten");
        compare(island.displayingNotificationId, 10);

        // Complete lease for 10 and drain next.
        island.markNotificationPresentationCompleted(10);
        island.displayingNotificationId = -1;
        island.forcedState = "";
        wait(0);
        island.maybeShowPendingNotification();
        compare(island.transientDisplayText, "Live Twenty");
        compare(island.displayingNotificationId, 20);
    }

    function test_deleted_live_skipped_manual_preserved() {
        island.userInteracting = true;
        notifications.activeModel = [liveNotif(1, "Live One")];
        island.handleNotificationsChanged();
        island.showTransientNotification("Manual Keep", "k");
        // Manual only on island queue; live waits on Notifications model.
        compare(island.pendingNotificationIds.length, 1);
        compare(island.pendingNotificationIds[0].kind, "manual");

        // Delete live id 1 while still blocked.
        notifications.activeModel = [];
        island.handleNotificationsChanged();
        compare(island.pendingNotificationIds.length, 1);
        compare(island.pendingNotificationIds[0].kind, "manual");
        compare(island.pendingNotificationIds[0].summary, "Manual Keep");

        island.userInteracting = false;
        island.maybeShowPendingNotification();
        compare(island.transientDisplayText, "Manual Keep");
    }

    function test_dnd_clears_manual_and_live_pending() {
        island.userInteracting = true;
        island.showTransientNotification("Manual DND", "d");
        notifications.activeModel = [liveNotif(5, "Live Five")];
        island.handleNotificationsChanged();
        compare(island.pendingNotificationIds.length, 1);

        notifications.dndEnabled = true;
        island.handleDndChanged();
        compare(island.pendingNotificationIds.length, 0);
    }

    function test_disable_clears_all_pending() {
        island.userInteracting = true;
        island.showTransientNotification("Manual Off", "o");
        notifications.activeModel = [liveNotif(7, "Live Seven")];
        island.handleNotificationsChanged();
        compare(island.pendingNotificationIds.length, 1);

        settings.dynamicIslandEnabled = false;
        island.reset();
        compare(island.pendingNotificationIds.length, 0);
    }
}
