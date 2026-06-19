pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: btn

    property var theme
    property string label: ""
    property string iconCode: ""
    property color accentColor: theme ? theme.accentBlue : "#007ff7"
    property bool active: false
    property string badgeText: ""

    readonly property string iconFont: theme ? theme.iconFont : "Material Icons"
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color activeFill: theme ? theme.sidebarActiveFill : "#64ffffff"
    readonly property color activeStroke: theme ? theme.sidebarActiveStroke : "#5cffffff"
    readonly property color hoverFill: theme ? theme.sidebarHoverFill : "#42ffffff"
    readonly property color danger: theme ? theme.danger : "#ff453a"

    signal activated()

    Layout.fillWidth: true
    Layout.preferredHeight: 36

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: btn.active ? btn.activeFill : (buttonMouse.containsMouse ? btn.hoverFill : "transparent")
        border.color: btn.active ? btn.activeStroke : "transparent"
        border.width: 1
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 7
        anchors.rightMargin: 8
        spacing: 9

        TahoeCategoryIcon {
            theme: btn.theme
            iconCode: btn.iconCode
            accentColor: btn.accentColor
            square: 22
        }

        Text {
            Layout.fillWidth: true
            text: btn.label
            color: btn.textPrimary
            font.pixelSize: 12
            font.weight: btn.active ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }

        Rectangle {
            id: badge
            Layout.preferredWidth: badgeText.implicitWidth + 10
            Layout.preferredHeight: 16
            radius: 8
            color: btn.danger
            opacity: 0.85
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
    }

    MouseArea {
        id: buttonMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.activated()
    }
}
