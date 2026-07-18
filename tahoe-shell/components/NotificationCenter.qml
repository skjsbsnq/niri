pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion
import "PopupGeometry.js" as PopupGeometry

PanelWindow {
    id: root

    property bool open: false
    property var notificationsService
    property var anchorRect: null
    property var settingsService

    readonly property var history: notificationsService ? notificationsService.historyModel : []
    readonly property int historyCount: history.length
    readonly property var groupedHistory: notificationsService
        ? notificationsService.groupedHistoryModel : []
    readonly property bool dndEnabled: notificationsService ? notificationsService.dndEnabled : false
    readonly property int edgePadding: 8
    readonly property int fallbackRight: 56
    readonly property int fallbackTop: 28
    readonly property int popupGap: 8
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, fallbackRight)
    signal closeRequested()

    // Clear-all stagger: fly cards out then wipe models (budget ≤450ms, ≤40).
    property bool clearing: false
    property int clearTotal: 0
    property int clearTick: 0
    property var pendingHistoryRemovals: Object.create(null)
    property var knownHistoryIds: Object.create(null)
    property bool historyEntryTrackingReady: false

    visible: open
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 360
    implicitHeight: panelLoader.item ? panelLoader.item.implicitHeight : 0
    color: "transparent"
    WlrLayershell.namespace: "tahoe-notification-center"

    anchors {
        top: true
        left: true
    }

    margins {
        top: root.popupTopMargin
        left: root.popupLeftMargin
    }

    TahoeGlass.regions: panelLoader.item ? [panelLoader.item.region] : []

    function startClearAll() {
        if (!notificationsService || root.clearing)
            return;
        root.flushPendingHistoryRemovals();
        if (root.historyCount === 0 && notificationsService.activeCount === 0) {
            notificationsService.clearEverything();
            return;
        }
        clearFinishHold.stop();
        root.clearing = true;
        root.clearTotal = Math.min(Motion.toastClearStaggerMaxItems, Math.max(1, root.historyCount));
        root.clearTick = 0;
        // First tick immediately so the top row starts flying without a dead frame.
        root.clearTick = 1;
        if (root.clearTotal <= 1) {
            clearStaggerTimer.stop();
            clearFinishHold.restart();
        } else {
            clearStaggerTimer.restart();
        }
    }

    function finishClearAll() {
        clearStaggerTimer.stop();
        clearFinishHold.stop();
        root.pendingHistoryRemovals = Object.create(null);
        root.clearing = false;
        root.clearTick = 0;
        root.clearTotal = 0;
        if (root.notificationsService)
            root.notificationsService.clearEverything();
    }

    function historyRemovalPending(id) {
        var key = String(Number(id));
        return (root.pendingHistoryRemovals || Object.create(null))[key] === true;
    }

    function markHistoryRemoval(id) {
        var value = Number(id);
        if (!isFinite(value) || value < 0 || root.clearing)
            return false;
        var key = String(value);
        if (root.historyRemovalPending(value))
            return false;
        var next = Object.create(null);
        var current = root.pendingHistoryRemovals || Object.create(null);
        for (var existing in current) {
            if (Object.prototype.hasOwnProperty.call(current, existing))
                next[existing] = current[existing];
        }
        next[key] = true;
        root.pendingHistoryRemovals = next;
        return true;
    }

    function completeHistoryRemoval(id) {
        var value = Number(id);
        if (!isFinite(value) || value < 0 || !root.historyRemovalPending(value))
            return;
        var key = String(value);
        var next = Object.create(null);
        var current = root.pendingHistoryRemovals || Object.create(null);
        for (var existing in current) {
            if (Object.prototype.hasOwnProperty.call(current, existing) && existing !== key)
                next[existing] = current[existing];
        }
        root.pendingHistoryRemovals = next;
        if (root.notificationsService)
            root.notificationsService.removeHistoryItem(value);
    }

    function flushPendingHistoryRemovals() {
        var current = root.pendingHistoryRemovals || Object.create(null);
        var ids = [];
        for (var key in current) {
            if (Object.prototype.hasOwnProperty.call(current, key) && current[key] === true)
                ids.push(Number(key));
        }
        root.pendingHistoryRemovals = Object.create(null);
        if (!root.notificationsService)
            return;
        for (var i = 0; i < ids.length; i++)
            root.notificationsService.removeHistoryItem(ids[i]);
    }

    function currentHistoryIdSet() {
        var ids = Object.create(null);
        var list = root.history || [];
        for (var i = 0; i < list.length; i++) {
            if (!list[i])
                continue;
            var id = Number(list[i].id);
            if (isFinite(id) && id >= 0)
                ids[String(id)] = true;
        }
        return ids;
    }

    function primeKnownHistoryIds() {
        root.knownHistoryIds = root.currentHistoryIdSet();
    }

    function pruneKnownHistoryIds() {
        var current = root.currentHistoryIdSet();
        var known = root.knownHistoryIds || Object.create(null);
        var next = Object.create(null);
        for (var key in known) {
            if (Object.prototype.hasOwnProperty.call(known, key) && current[key])
                next[key] = true;
        }
        root.knownHistoryIds = next;
    }

    function claimHistoryEntryAnimation(id) {
        var value = Number(id);
        if (!isFinite(value) || value < 0)
            return false;
        var key = String(value);
        var known = root.knownHistoryIds || Object.create(null);
        var animate = root.historyEntryTrackingReady && root.open && known[key] !== true;
        known[key] = true;
        root.knownHistoryIds = known;
        return animate;
    }

    Timer {
        id: clearStaggerTimer
        interval: Math.max(1, Motion.toastClearStaggerMs)
        repeat: true
        onTriggered: {
            root.clearTick += 1;
            var budgetSteps = Math.max(1, Math.ceil(Motion.toastClearStaggerBudgetMs / Math.max(1, interval)));
            // After the last row is marked flyOut, hold for the fly-out
            // animation before wiping the model (Issue 1 review fix).
            if (root.clearTick >= root.clearTotal || root.clearTick >= budgetSteps) {
                clearStaggerTimer.stop();
                clearFinishHold.restart();
            }
        }
    }

    Timer {
        id: clearFinishHold
        // Match NotificationRow fly-out (elementMove) + small settle margin.
        interval: Math.max(120, Motion.elementMove(root.settingsService) + 40)
        repeat: false
        onTriggered: root.finishClearAll()
    }

    onOpenChanged: {
        if (open) {
            root.primeKnownHistoryIds();
        } else {
            if (root.clearing)
                root.finishClearAll();
            else
                root.flushPendingHistoryRemovals();
        }
    }
    onHistoryChanged: {
        if (root.open)
            root.pruneKnownHistoryIds();
        else
            root.primeKnownHistoryIds();
    }
    Component.onCompleted: {
        root.primeKnownHistoryIds();
        root.historyEntryTrackingReady = true;
    }

    Loader {
        id: panelLoader
        width: parent.width
        active: root.open
        sourceComponent: panelComponent
    }

    Component {
        id: panelComponent

        GlassPanel {
            id: panel

            // Keep the compositor glass region anchored. In compositor animation
            // mode niri owns the outer motion.
            y: 0
            width: root.width
            implicitHeight: content.implicitHeight + 24
            height: implicitHeight
            material: GlassStyle.MaterialPanel
            radius: GlassStyle.RadiusPanel
            fillColor: GlassStyle.FillPanelBright
            strokeColor: GlassStyle.StrokePanelBright
            interaction: 0.0
            opacity: 1

            ColumnLayout {
                id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "通知"
                    color: "#1d1d1f"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                Item {
                    Layout.preferredWidth: clearLabel.implicitWidth + 18
                    Layout.preferredHeight: 24
                    visible: root.historyCount > 0 && !root.clearing

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: clearMouse.containsMouse ? "#70ffffff" : "#34ffffff"
                        border.color: "#50ffffff"
                    }

                    Text {
                        id: clearLabel
                        anchors.centerIn: parent
                        text: "清空"
                        color: "#1d1d1f"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.startClearAll()
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 42

                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: "#52ffffff"
                    border.color: "#4cffffff"
                    border.width: 1
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 10

                    TahoeSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        name: root.dndEnabled ? "\ue7f6" : "\ue7f4"
                        color: "#1d1d1f"
                        size: 18
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "勿扰模式"
                            color: "#1d1d1f"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }

                        Text {
                            text: root.dndEnabled ? "横幅和提示音已静音" : "通知正常显示"
                            color: "#881d1d1f"
                            font.pixelSize: 11
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 22
                        radius: 11
                        color: root.dndEnabled ? "#2c9cf2" : "#32000000"

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            x: root.dndEnabled ? parent.width - width - 2 : 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#ffffff"

                            Behavior on x {
                                NumberAnimation { duration: Motion.elementMove(root.settingsService); easing.type: Motion.emphasizedDecel }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.notificationsService)
                            root.notificationsService.toggleDnd();
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#22000000"
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                visible: root.historyCount === 0 && !root.clearing

                Text {
                    anchors.centerIn: parent
                    text: "暂无通知"
                    color: "#8a1d1d1f"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(360, Math.max(120, historyColumn.implicitHeight))
                visible: root.historyCount > 0 || root.clearing
                contentWidth: width
                contentHeight: historyColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: historyColumn

                    width: parent.width
                    spacing: 12

                    Repeater {
                        model: ScriptModel {
                            objectProp: "modelKey"
                            values: root.groupedHistory
                        }

                        delegate: AppGroup {
                            required property var modelData
                            required property int index

                            width: historyColumn.width
                            group: modelData
                            groupIndex: index
                        }
                    }
                }
            }
            }
        }
    }

    component AppGroup: Column {
        id: groupRoot

        property var group
        property int groupIndex: 0
        readonly property string appName: group ? String(group.appName || "应用") : "应用"
        readonly property var items: group && group.items ? group.items : []
        readonly property int itemCount: items.length
        property bool expanded: itemCount <= 2

        width: parent ? parent.width : 0
        spacing: 6

        // Group header
        Item {
            width: parent.width
            height: 22

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: groupRoot.appName
                color: "#991d1d1f"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: groupRoot.itemCount > 1
                    ? (groupRoot.expanded ? "收起" : groupRoot.itemCount + " 条")
                    : ""
                color: "#731d1d1f"
                font.pixelSize: 11
                visible: groupRoot.itemCount > 1

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: groupRoot.expanded = !groupRoot.expanded
                }
            }
        }

        Column {
            width: parent.width
            spacing: 8

            Repeater {
                model: ScriptModel {
                    objectProp: "modelKey"
                    values: groupRoot.items
                }

                delegate: NotificationRow {
                    required property var modelData
                    required property int index

                    width: groupRoot.width
                    entry: modelData
                    rowIndex: {
                        // Flat index estimate for stagger: prior groups + index
                        var base = 0;
                        var groups = root.groupedHistory;
                        for (var g = 0; g < groupRoot.groupIndex && g < groups.length; g++)
                            base += groups[g] && groups[g].items ? groups[g].items.length : 0;
                        return base + index;
                    }
                    collapsedHidden: !groupRoot.expanded && index > 0
                }
            }
        }
    }

    component NotificationRow: Item {
        id: row

        property var entry
        property int rowIndex: 0
        property bool collapsedHidden: false
        property bool enterComplete: false
        property bool entryAnimationPlayed: false
        property bool motionReady: false
        property bool removing: false
        property bool collapsing: false
        readonly property string iconUrl: root.notificationsService
            ? root.notificationsService.iconUrlForHistory(entry)
            : ""
        readonly property bool flyOut: row.removing
            || (root.clearing && rowIndex < root.clearTick)
        readonly property real motionX: row.flyOut ? 80
            : (row.enterComplete ? 0 : Motion.toastEnterOffsetPx)

        height: collapsedHidden || collapsing ? 0 : card.implicitHeight
        visible: !collapsedHidden || root.clearing || row.removing || row.collapsing
        clip: true
        opacity: row.enterComplete && !flyOut ? 1 : 0

        transform: Translate {
            x: row.motionX
            Behavior on x {
                enabled: row.motionReady
                NumberAnimation {
                    duration: Motion.elementMove(root.settingsService)
                    easing.type: Motion.emphasizedAccel
                }
            }
        }

        Behavior on opacity {
            enabled: row.motionReady
            NumberAnimation {
                duration: Motion.fadeFast(root.settingsService)
                easing.type: Motion.standardDecel
            }
        }

        Behavior on height {
            enabled: row.collapsedHidden || row.collapsing
                || (!row.collapsedHidden && height > 0)
            NumberAnimation {
                duration: Motion.elementResize(root.settingsService)
                easing.type: Motion.emphasizedDecel
            }
        }

        function beginRemoval() {
            if (!row.entry || row.removing || root.clearing)
                return;
            if (!root.markHistoryRemoval(row.entry.id))
                return;
            row.removing = true;
            removalExitTimer.restart();
        }

        Component.onCompleted: {
            row.entryAnimationPlayed = row.entry
                && root.claimHistoryEntryAnimation(row.entry.id);
            if (row.entryAnimationPlayed) {
                row.motionReady = true;
                Qt.callLater(function() {
                    row.enterComplete = true;
                });
            } else {
                row.enterComplete = true;
                Qt.callLater(function() {
                    row.motionReady = true;
                });
            }
        }

        Timer {
            id: removalExitTimer
            interval: Math.max(1, Math.max(
                Motion.elementMove(root.settingsService),
                Motion.fadeFast(root.settingsService)))
            repeat: false
            onTriggered: {
                row.collapsing = true;
                removalCollapseTimer.restart();
            }
        }

        Timer {
            id: removalCollapseTimer
            interval: Math.max(1, Motion.elementResize(root.settingsService))
            repeat: false
            onTriggered: {
                if (row.entry)
                    root.completeHistoryRemoval(row.entry.id);
            }
        }

        Rectangle {
            id: card

            width: parent.width
            implicitHeight: rowContent.implicitHeight + 18
            height: implicitHeight
            radius: 14
            color: "#54ffffff"
            border.color: "#48ffffff"
            border.width: 1

            RowLayout {
                id: rowContent

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 9
                spacing: 9

                Item {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    Layout.alignment: Qt.AlignTop

                    Rectangle {
                        anchors.fill: parent
                        radius: 9
                        color: "#44ffffff"
                    }

                    Image {
                        id: historyIcon
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        source: row.iconUrl
                        sourceSize.width: 20
                        sourceSize.height: 20
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                        visible: row.iconUrl.length > 0 && status !== Image.Error
                    }

                    TahoeSymbol {
                        anchors.centerIn: parent
                        name: "\ue7f4"
                        color: "#661d1d1f"
                        size: 17
                        visible: !historyIcon.visible
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: row.entry ? row.entry.appName : ""
                            color: "#991d1d1f"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: root.timeText(row.entry)
                            color: "#731d1d1f"
                            font.pixelSize: 10
                        }
                    }

                    Text {
                        text: row.entry ? row.entry.summary : ""
                        color: "#1d1d1f"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: row.entry ? row.entry.body : ""
                        color: "#991d1d1f"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        visible: text.length > 0
                        Layout.fillWidth: true
                    }
                }

                Item {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    Layout.alignment: Qt.AlignTop

                    Rectangle {
                        anchors.fill: parent
                        radius: 11
                        color: closeMouse.containsMouse ? "#70ffffff" : "transparent"
                    }

                    TahoeSymbol {
                        anchors.centerIn: parent
                        name: "\ue5cd"
                        color: "#731d1d1f"
                        size: 15
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        enabled: !row.removing && !root.clearing
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.beginRemoval()
                    }
                }
            }
        }
    }

    function timeText(entry) {
        if (!entry || !entry.time)
            return "";

        try {
            return Qt.formatTime(entry.time, "HH:mm");
        } catch (e) {
            return "";
        }
    }
}
