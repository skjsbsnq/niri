pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: btn

    property var theme
    property string label: ""
    property string iconCode: ""
    property bool active: false
    property string badgeText: ""

    readonly property string iconFont: theme ? theme.iconFont : "Material Icons"
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"

    signal activated()

    Layout.fillWidth: true
    Layout.preferredHeight: 34

    Rectangle {
        anchors.fill: parent
        radius: 11
        color: btn.active ? "#64ffffff" : (buttonMouse.containsMouse ? "#42ffffff" : "transparent")
        border.color: btn.active ? "#5cffffff" : "transparent"
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: btn.iconCode
        color: btn.textPrimary
        font.family: btn.iconFont
        font.pixelSize: 17
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 38
        anchors.right: badge.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: btn.label
        color: btn.textPrimary
        font.pixelSize: 12
        font.weight: btn.active ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
    }

    Rectangle {
        id: badge
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: badgeText.implicitWidth + 8
        height: 16
        radius: 8
        color: "#ccff453a"
        visible: btn.badgeText.length > 0

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: btn.badgeText
            color: "#ffffff"
            font.pixelSize: 9
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        id: buttonMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.activated()
    }
}
