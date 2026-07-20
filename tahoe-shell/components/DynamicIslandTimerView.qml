pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion

// V2 timer scene (T20): compact remaining + expanded controls.
// Countdown ownership lives in services/Timer.qml — this view is pure UI.
Item {
    id: root

    property string remainingLabel: "0:00"
    property real progress: 0
    property bool running: false
    property bool paused: false
    property bool finished: false
    property bool expanded: false
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color accentColor: "#0a84ff"
    property color trackColor: "#30ffffff"
    // Progress rail fill is monochrome (islandProgressFill); accent not used for bars.
    property color progressFillColor: "#f7f8fa"
    property color controlFill: "#20ffffff"

    signal pauseResumeRequested()
    signal cancelRequested()
    // Distinct from MediaView.controlPressed so Content walkers do not confuse scenes.
    signal timerInteractionPressed()
    signal timerInteractionReleased()

    readonly property real safeProgress: Math.max(0, Math.min(1, Number(progress) || 0))
    readonly property string statusLabel: {
        if (root.finished)
            return "时间到";
        if (root.paused)
            return "已暂停";
        if (root.running)
            return "进行中";
        return "";
    }

    // ---- Compact ----
    Row {
        id: compactRow
        visible: !root.expanded
        anchors.centerIn: parent
        spacing: 8

        TahoeSymbol {
            anchors.verticalCenter: parent.verticalCenter
            name: "\ue425" // timer
            color: root.textSecondary
            size: 16
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.remainingLabel
            color: root.textPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.letterSpacing: 0
        }
    }

    Rectangle {
        visible: !root.expanded && root.safeProgress > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        height: 2
        radius: 1
        color: root.trackColor

        Rectangle {
            width: parent.width * root.safeProgress
            height: parent.height
            radius: 1
            color: root.progressFillColor
        }
    }

    // ---- Expanded ----
    Column {
        visible: root.expanded
        anchors.centerIn: parent
        spacing: 10
        width: parent.width - 32

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.remainingLabel
            color: root.textPrimary
            font.pixelSize: 30
            font.weight: Font.DemiBold
            font.letterSpacing: 0
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.statusLabel
            color: root.textSecondary
            font.pixelSize: 12
            font.letterSpacing: 0
            visible: text.length > 0
        }

        Rectangle {
            width: Math.min(200, parent.width)
            height: 4
            radius: 2
            color: root.trackColor
            anchors.horizontalCenter: parent.horizontalCenter

            Rectangle {
                width: parent.width * root.safeProgress
                height: parent.height
                radius: 2
                color: root.progressFillColor
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            TimerActionButton {
                label: root.paused || !root.running ? "继续" : "暂停"
                onActivated: root.pauseResumeRequested()
            }

            TimerActionButton {
                label: "取消"
                onActivated: root.cancelRequested()
            }
        }
    }

    component TimerActionButton: Item {
        id: btn
        property string label: ""
        signal activated()
        width: 72
        height: 36

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: root.controlFill
        }

        Text {
            anchors.centerIn: parent
            text: btn.label
            color: root.textPrimary
            font.pixelSize: 12
            font.letterSpacing: 0
        }

        MouseArea {
            anchors.fill: parent
            // 44px hit via padding on parent height 36 + margins handled by row.
            anchors.margins: -4
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onPressed: {
                root.timerInteractionPressed();
                mouse.accepted = true;
            }
            onReleased: {
                root.activated();
                root.timerInteractionReleased();
                mouse.accepted = true;
            }
            onCanceled: root.timerInteractionReleased()
        }
    }
}
