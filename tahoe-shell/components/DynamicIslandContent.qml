pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion

Item {
    id: root

    property string islandState: "resting_time"
    property string displayText: ""
    property string secondaryText: ""
    property string iconCode: ""
    property real progress: -1
    property bool compactResting: true
    property bool showSecondaryText: false
    property color textPrimary: "#f7f9fc"
    property color textSecondary: "#b9c0cc"

    readonly property bool notificationActive: islandState === "transient_notification"
    readonly property bool standardDetailActive: !compactResting && !notificationActive
    readonly property int notificationFadeInDuration: 280
    readonly property int notificationFadeOutDuration: 140

    function safeProgress(value) {
        var number = Number(value);
        if (!isFinite(number) || number < 0)
            return -1;

        return Math.max(0, Math.min(1, number));
    }

    Text {
        id: compactLabel

        anchors.centerIn: parent
        width: parent.width - 32
        text: root.displayText
        color: root.textPrimary
        font.pixelSize: root.islandState === "resting_time" ? 13 : 12
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        maximumLineCount: 1
        opacity: root.compactResting ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.overlayContentDuration; easing.type: IslandMotion.overlayColorEasing }
        }
    }

    Row {
        id: detailRow

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: root.islandState.indexOf("expanded_") === 0 ? 24 : 16
            rightMargin: root.islandState.indexOf("expanded_") === 0 ? 24 : 16
        }
        height: Math.min(parent.height - 16, 52)
        spacing: 10
        opacity: root.standardDetailActive ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.overlayContentDuration; easing.type: IslandMotion.overlayColorEasing }
        }

        Text {
            width: 24
            height: parent.height
            text: root.iconCode
            color: root.textPrimary
            font.family: "Material Icons"
            font.pixelSize: 20
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            width: Math.max(1, parent.width - 34)
            height: parent.height

            Text {
                id: detailPrimary

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: root.showSecondaryText ? 4 : 0
                }
                text: root.displayText
                color: root.textPrimary
                font.pixelSize: root.islandState.indexOf("expanded_") === 0 ? 17 : 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: detailPrimary.bottom
                    topMargin: 2
                }
                text: root.secondaryText
                color: root.textSecondary
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: root.showSecondaryText
            }
        }
    }

    Row {
        id: notificationRow

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 16
            rightMargin: 18
        }
        height: Math.min(parent.height - 14, 42)
        spacing: 10
        opacity: root.notificationActive ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: root.notificationActive ? root.notificationFadeInDuration : root.notificationFadeOutDuration
                easing.type: IslandMotion.overlayColorEasing
            }
        }

        Text {
            width: 24
            height: parent.height
            text: root.iconCode.length > 0 ? root.iconCode : "\ue7f4"
            color: root.textPrimary
            font.family: "Material Icons"
            font.pixelSize: 20
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            width: Math.max(1, parent.width - 34)
            height: parent.height

            Text {
                id: notificationTitle

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: root.secondaryText.length > 0 ? 3 : Math.round((parent.height - height) / 2)
                }
                text: root.displayText
                color: root.textPrimary
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: notificationTitle.bottom
                    topMargin: 2
                }
                text: root.secondaryText
                color: root.textSecondary
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: text.length > 0
            }
        }
    }

    Rectangle {
        id: progressTrack

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 18
            rightMargin: 18
            bottomMargin: 8
        }
        height: 3
        radius: 2
        color: "#28ffffff"
        opacity: root.safeProgress(root.progress) >= 0 ? 1 : 0
        visible: opacity > 0.01

        Rectangle {
            width: parent.width * Math.max(0, root.safeProgress(root.progress))
            height: parent.height
            radius: parent.radius
            color: "#f0ffffff"

            Behavior on width {
                NumberAnimation { duration: IslandMotion.overlayProgressDuration; easing.type: IslandMotion.overlayProgressEasing }
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.overlayContentDuration; easing.type: IslandMotion.overlayColorEasing }
        }
    }
}
