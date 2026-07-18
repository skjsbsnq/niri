import QtQuick
import QtTest
import "../services" as Services

TestCase {
    id: testCase
    name: "NotificationCenterStableHistory"
    when: windowShown

    property var ownedNotifications: []

    Services.Notifications {
        id: notifications
    }

    Component {
        id: notificationComponent

        QtObject {
            property real id: -1
            property string appName: "Test"
            property string summary: "Summary"
            property string body: "Body"
            property string appIcon: ""
            property string desktopEntry: ""
            property string image: ""
            property int urgency: 1
        }
    }

    function makeNotification(id, appName, summary) {
        var notification = notificationComponent.createObject(testCase, {
            "id": id,
            "appName": appName,
            "summary": summary
        });
        verify(notification !== null);
        ownedNotifications.push(notification);
        return notification;
    }

    function init() {
        notifications.clearHistory();
    }

    function cleanup() {
        notifications.clearHistory();
        for (var i = 0; i < ownedNotifications.length; i++)
            ownedNotifications[i].destroy();
        ownedNotifications = [];
    }

    function test_entry_and_group_identity_survive_update_and_reorder() {
        notifications.pushHistory(makeNotification(10, "Mail", "First"));
        var entry10 = notifications.historyModel[0];
        var mailGroup = notifications.groupedHistoryModel[0];

        compare(entry10.modelKey, "history:10");
        compare(mailGroup.modelKey, "history-group:Mail");
        compare(mailGroup.items[0], entry10);

        notifications.pushHistory(makeNotification(20, "Chat", "Second"));
        var entry20 = notifications.historyModel[0];
        var chatGroup = notifications.groupedHistoryModel[0];
        compare(notifications.historyModel[1], entry10);
        compare(notifications.groupedHistoryModel[1], mailGroup);

        notifications.pushHistory(makeNotification(10, "Mail", "Updated"));
        compare(notifications.historyModel[0], entry10);
        compare(notifications.historyModel[1], entry20);
        compare(entry10.summary, "Updated");
        compare(notifications.groupedHistoryModel[0], mailGroup);
        compare(notifications.groupedHistoryModel[1], chatGroup);
        compare(mailGroup.items[0], entry10);
        compare(chatGroup.items[0], entry20);
    }

    function test_same_group_add_remove_preserves_survivors() {
        notifications.pushHistory(makeNotification(31, "Mail", "Older"));
        var entry31 = notifications.historyModel[0];
        var mailGroup = notifications.groupedHistoryModel[0];

        notifications.pushHistory(makeNotification(32, "Mail", "Newer"));
        var entry32 = notifications.historyModel[0];
        compare(notifications.historyModel[1], entry31);
        compare(notifications.groupedHistoryModel[0], mailGroup);
        compare(mailGroup.count, 2);
        compare(mailGroup.items[0], entry32);
        compare(mailGroup.items[1], entry31);

        notifications.removeHistoryItem(32);
        compare(notifications.historyModel.length, 1);
        compare(notifications.historyModel[0], entry31);
        compare(notifications.groupedHistoryModel[0], mailGroup);
        compare(mailGroup.count, 1);
        compare(mailGroup.items[0], entry31);
        verify(notifications.historyEntryCache["32"] === undefined);
    }

    function test_uint32_id_special_group_key_and_cache_pruning() {
        notifications.pushHistory(makeNotification(4000000000, "__proto__", "Large"));
        var largeEntry = notifications.historyModel[0];
        var specialGroup = notifications.groupedHistoryModel[0];
        compare(largeEntry.id, 4000000000);
        compare(largeEntry.modelKey, "history:4000000000");
        compare(notifications.historyEntryCache["4000000000"], largeEntry);
        compare(notifications.historyGroupCache["__proto__"], specialGroup);

        notifications.pushHistory(makeNotification(41, "Other", "Survivor"));
        var survivor = notifications.historyModel[0];
        var otherGroup = notifications.groupedHistoryModel[0];
        notifications.removeHistoryItem(4000000000);

        compare(notifications.historyModel.length, 1);
        compare(notifications.historyModel[0], survivor);
        compare(notifications.groupedHistoryModel.length, 1);
        compare(notifications.groupedHistoryModel[0], otherGroup);
        verify(notifications.historyEntryCache["4000000000"] === undefined);
        verify(notifications.historyGroupCache["__proto__"] === undefined);

        notifications.clearHistory();
        compare(notifications.historyModel.length, 0);
        compare(notifications.groupedHistoryModel.length, 0);
        compare(Object.keys(notifications.historyEntryCache).length, 0);
        compare(Object.keys(notifications.historyGroupCache).length, 0);
    }

    function test_external_model_is_canonicalized_and_retired_object_is_not_revived() {
        notifications.pushHistory(makeNotification(50, "Mail", "Original"));
        var retiredEntry = notifications.historyModel[0];
        notifications.removeHistoryItem(50);
        verify(notifications.historyEntryCache["50"] === undefined);

        notifications.historyModel = [retiredEntry];
        var canonicalEntry = notifications.historyModel[0];
        verify(canonicalEntry !== retiredEntry);
        compare(canonicalEntry.modelKey, "history:50");
        compare(canonicalEntry.summary, "Original");
        compare(notifications.historyEntryCache["50"], canonicalEntry);

        wait(1100);
        compare(notifications.historyModel[0], canonicalEntry);
        compare(canonicalEntry.summary, "Original");
        compare(notifications.groupedHistoryModel[0].items[0], canonicalEntry);
    }

    function test_max_history_evicts_only_oldest_cached_entry() {
        var entry1 = null;
        for (var id = 0; id <= notifications.maxHistory; id++) {
            notifications.pushHistory(makeNotification(id, "Bulk", "Item-" + id));
            if (id === 1)
                entry1 = notifications.historyModel[0];
        }
        compare(notifications.historyModel.length, notifications.maxHistory);
        compare(notifications.historyModel[notifications.maxHistory - 1], entry1);
        compare(notifications.historyEntryCache["1"], entry1);
        verify(notifications.historyEntryCache["0"] === undefined);
        compare(notifications.groupedHistoryModel.length, 1);
        compare(notifications.groupedHistoryModel[0].count, notifications.maxHistory);
    }
}
