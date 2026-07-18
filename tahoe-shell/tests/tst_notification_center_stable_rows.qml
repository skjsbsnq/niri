pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

ShellRoot {
    id: testCase

    property string centerSource: ""
    property var center: null
    property var ownedObjects: []
    property var stable1: null
    property var stable2: null
    property var stableGroup: null
    property var removalRow: null
    property real removalStartHeight: 0
    property int stage: 0

    QtObject {
        id: settings
        property string motionProfile: "balanced"
    }

    QtObject {
        id: notifService
        property var historyModel: []
        property var groupedHistoryModel: []
        property bool dndEnabled: false
        property int activeCount: 0
        property var removedIds: []

        function iconUrlForHistory(entry) { return ""; }
        function toggleDnd() { dndEnabled = !dndEnabled; }
        function clearEverything() {
            historyModel = [];
            groupedHistoryModel = [];
        }
        function removeHistoryItem(id) {
            var value = Number(id);
            removedIds = removedIds.concat([value]);
            var nextHistory = [];
            for (var i = 0; i < historyModel.length; i++) {
                if (Number(historyModel[i].id) !== value)
                    nextHistory.push(historyModel[i]);
            }
            historyModel = nextHistory;
            if (groupedHistoryModel.length === 0)
                return;
            var group = groupedHistoryModel[0];
            var nextItems = [];
            for (var j = 0; j < group.items.length; j++) {
                if (Number(group.items[j].id) !== value)
                    nextItems.push(group.items[j]);
            }
            group.items = nextItems;
            group.count = nextItems.length;
        }
    }

    Component {
        id: entryFactory
        QtObject {
            property real id: -1
            property string modelKey: ""
            property string appName: "Mail"
            property string summary: ""
            property string body: ""
            property string appIcon: ""
            property string desktopEntry: ""
            property string image: ""
            property int urgency: 1
            property date time: new Date()
        }
    }

    Component {
        id: groupFactory
        QtObject {
            property string modelKey: "history-group:Mail"
            property string appName: "Mail"
            property var items: []
            property int count: items.length
        }
    }

    Timer {
        id: stepTimer
        interval: 20
        repeat: false
        onTriggered: testCase.advance()
    }

    function require(condition, message) {
        if (condition)
            return true;
        console.error("NOTIFICATION_CENTER_FAIL: " + message);
        cleanup();
        Qt.exit(1);
        return false;
    }

    function schedule(nextStage, delayMs) {
        stage = nextStage;
        stepTimer.interval = Math.max(1, delayMs);
        stepTimer.restart();
    }

    function makeEntry(id) {
        var entry = entryFactory.createObject(testCase, {
            "id": id,
            "modelKey": "history:" + id,
            "summary": "summary-" + id
        });
        if (!entry)
            return null;
        ownedObjects = ownedObjects.concat([entry]);
        return entry;
    }

    function findRow(id) {
        if (!center)
            return null;
        function walk(node) {
            if (!node)
                return null;
            if (node.entry !== undefined && node.beginRemoval !== undefined
                    && node.entry && Number(node.entry.id) === Number(id))
                return node;
            var children = node.children || [];
            for (var i = 0; i < children.length; i++) {
                var found = walk(children[i]);
                if (found)
                    return found;
            }
            return null;
        }
        return walk(center.contentItem || center);
    }

    function findGroup() {
        if (!center)
            return null;
        function walk(node) {
            if (!node)
                return null;
            if (node.group !== undefined && node.itemCount !== undefined
                    && node.group && node.group.modelKey === "history-group:Mail")
                return node;
            var children = node.children || [];
            for (var i = 0; i < children.length; i++) {
                var found = walk(children[i]);
                if (found)
                    return found;
            }
            return null;
        }
        return walk(center.contentItem || center);
    }

    function countRemoved(id) {
        var count = 0;
        for (var i = 0; i < notifService.removedIds.length; i++) {
            if (Number(notifService.removedIds[i]) === Number(id))
                count += 1;
        }
        return count;
    }

    function cleanup() {
        stepTimer.stop();
        if (center) {
            center.destroy();
            center = null;
        }
        for (var i = 0; i < ownedObjects.length; i++) {
            if (ownedObjects[i] && ownedObjects[i].destroy)
                ownedObjects[i].destroy();
        }
        ownedObjects = [];
    }

    function finish() {
        console.log("NOTIFICATION_CENTER_OK");
        cleanup();
        Qt.quit();
    }

    function startCloseRace() {
        var entry4 = makeEntry(4);
        var group = notifService.groupedHistoryModel[0];
        group.items = [entry4].concat(group.items);
        group.count = group.items.length;
        notifService.historyModel = [entry4].concat(notifService.historyModel);
        schedule(7, 220);
    }

    function startProbe() {
        if (!require(centerSource.length > 0, "centerSource was not injected"))
            return;
        var entry1 = makeEntry(1);
        var entry2 = makeEntry(2);
        var group = groupFactory.createObject(testCase, {
            "items": [entry2, entry1]
        });
        if (!require(entry1 && entry2 && group, "initial stable model objects"))
            return;
        ownedObjects = ownedObjects.concat([group]);
        notifService.historyModel = [entry2, entry1];
        notifService.groupedHistoryModel = [group];

        var component = Qt.createComponent("file://" + centerSource);
        if (!require(component.status === Component.Ready,
                "center compile: " + component.errorString()))
            return;
        center = component.createObject(null, {
            "open": true,
            "notificationsService": notifService,
            "settingsService": settings
        });
        if (!require(center !== null, "center creation"))
            return;
        schedule(1, 260);
    }

    function advance() {
        if (stage === 0) {
            startProbe();
            return;
        }
        if (stage === 1) {
            stable1 = findRow(1);
            stable2 = findRow(2);
            stableGroup = findGroup();
            if (!require(stable1 && stable2 && stableGroup,
                    "initial row and group delegates")
                    || !require(stable1.enterComplete && stable2.enterComplete,
                        "initial rows complete entry")
                    || !require(!stable1.entryAnimationPlayed
                        && !stable2.entryAnimationPlayed,
                        "pre-existing rows do not replay entry on panel open")
                    || !require(stable1.opacity > 0.99 && stable2.opacity > 0.99,
                        "initial rows settle opaque"))
                return;
            var entry3 = makeEntry(3);
            var group = notifService.groupedHistoryModel[0];
            group.items = [entry3, group.items[0], group.items[1]];
            group.count = group.items.length;
            notifService.historyModel = [entry3].concat(notifService.historyModel);
            schedule(2, 20);
            return;
        }
        if (stage === 2) {
            var row3 = findRow(3);
            if (!require(row3, "new row delegate")
                    || !require(findRow(1) === stable1 && findRow(2) === stable2,
                        "existing row delegates survive insertion")
                    || !require(findGroup() === stableGroup,
                        "app group delegate survives insertion")
                    || !require(!stableGroup.expanded,
                        "three-item group keeps collapsed presentation")
                    || !require(row3.entryAnimationPlayed,
                        "only the new row claims entry animation")
                    || !require(row3.opacity < 0.99,
                        "new row fades in before settling")
                    || !require(settings.motionProfile === "reduced"
                        || Number(row3.transform[0].x) > 0,
                        "balanced profile new row slides from the right"))
                return;
            stableGroup.expanded = true;
            schedule(3, 220);
            return;
        }
        if (stage === 3) {
            var row3 = findRow(3);
            if (!require(row3 && row3.opacity > 0.99,
                    "new row settles opaque")
                    || !require(stableGroup.expanded,
                        "expanded group state survives row entry")
                    || !require(findRow(1) === stable1 && findRow(2) === stable2,
                        "survivor identities remain stable after entry"))
                return;
            removalRow = row3;
            removalStartHeight = removalRow.height;
            removalRow.beginRemoval();
            removalRow.beginRemoval();
            schedule(4, 20);
            return;
        }
        if (stage === 4) {
            if (!require(removalRow.removing, "single delete starts local fly-out")
                    || !require(countRemoved(3) === 0,
                        "service model remains during fly-out")
                    || !require(removalRow.opacity < 0.99,
                        "single delete fades before service removal"))
                return;
            schedule(5, 150);
            return;
        }
        if (stage === 5) {
            if (settings.motionProfile === "reduced") {
                if (!require(countRemoved(3) === 1,
                        "reduced delete completes exactly once")
                        || !require(findRow(1) === stable1 && findRow(2) === stable2,
                            "reduced delete preserves survivors"))
                    return;
                startCloseRace();
                return;
            }
            if (!require(removalRow.collapsing, "balanced delete reaches collapse phase")
                    || !require(removalRow.height < removalStartHeight,
                        "balanced delete collapses row height")
                    || !require(countRemoved(3) === 0,
                        "service removal waits for collapse"))
                return;
            schedule(6, 240);
            return;
        }
        if (stage === 6) {
            if (!require(countRemoved(3) === 1,
                    "balanced delete completes exactly once")
                    || !require(findRow(3) === null, "deleted row retires")
                    || !require(findRow(1) === stable1 && findRow(2) === stable2,
                        "balanced delete preserves survivors"))
                return;
            startCloseRace();
            return;
        }
        if (stage === 7) {
            var row4 = findRow(4);
            if (!require(row4 && row4.entryAnimationPlayed,
                    "second new row claims entry animation"))
                return;
            row4.beginRemoval();
            row4.beginRemoval();
            schedule(8, 20);
            return;
        }
        if (stage === 8) {
            if (!require(countRemoved(4) === 0,
                    "close-race row remains in service during fly-out"))
                return;
            center.open = false;
            schedule(9, 40);
            return;
        }
        if (stage === 9) {
            if (!require(countRemoved(4) === 1,
                    "closing Loader flushes pending delete exactly once")
                    || !require(Object.keys(center.pendingHistoryRemovals).length === 0,
                        "closing Loader clears pending delete map"))
                return;
            center.open = true;
            schedule(10, 30);
            return;
        }
        if (stage === 10) {
            var reopened1 = findRow(1);
            var reopened2 = findRow(2);
            if (!require(reopened1 && reopened2, "rows return after reopening panel")
                    || !require(!reopened1.entryAnimationPlayed
                        && !reopened2.entryAnimationPlayed,
                        "reopening panel does not replay old row entry")
                    || !require(reopened1.opacity > 0.99 && reopened2.opacity > 0.99,
                        "reopened rows are immediately opaque"))
                return;
            center.startClearAll();
            schedule(11, 20);
            return;
        }
        if (stage === 11) {
            if (!require(center.clearing, "clear-all starts stagger before close"))
                return;
            center.open = false;
            schedule(12, 40);
            return;
        }
        if (stage === 12) {
            if (!require(!center.clearing, "closing panel completes clear-all")
                    || !require(notifService.historyModel.length === 0
                        && notifService.groupedHistoryModel.length === 0,
                        "closing clear-all leaves no history rows"))
                return;
            finish();
        }
    }

    Component.onCompleted: schedule(0, 20)
}
