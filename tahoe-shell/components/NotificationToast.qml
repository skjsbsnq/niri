pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

PanelWindow {
    id: root

    property bool open: false
    property string title: "Tahoe"
    property string message: "Session ready"

    signal dismissRequested()

    visible: open || card.opacity > 0.01
    aboveWindows: true
    exclusiveZone: 0
    implicitWidth: 318
    implicitHeight: 86
    color: "transparent"

    anchors {
        top: true
        right: true
    }

    margins {
        top: 48
        right: 16
    }

    Timer {
        interval: 3600
        running: root.open
        repeat: false
        onTriggered: root.dismissRequested()
    }

    Rectangle {
        id: card

        x: root.open ? 0 : root.width + 24
        y: root.open ? 0 : -4
        width: parent.width
        height: parent.height
        radius: 18
        color: "#dff7f8fb"
        border.color: "#70ffffff"
        border.width: 1
        opacity: root.open ? 1 : 0

        Behavior on x {
            SpringAnimation {
                spring: 3.4
                damping: 0.36
                epsilon: 0.2
            }
        }

        Behavior on y {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }

        Rectangle {
            x: 14
            y: 14
            width: 36
            height: 36
            radius: 11
            color: "#70ffffff"
            border.color: "#60ffffff"

            Text {
                anchors.centerIn: parent
                text: "T"
                color: "#202124"
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 62
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.top: parent.top
            anchors.topMargin: 16
            text: root.title
            color: "#202124"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 62
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.top: parent.top
            anchors.topMargin: 38
            text: root.message
            color: "#5f6368"
            font.pixelSize: 12
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dismissRequested()
        }
    }
}
