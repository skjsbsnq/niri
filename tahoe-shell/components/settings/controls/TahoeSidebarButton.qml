pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../Motion.js" as Motion

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
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color activeFill: theme ? theme.sidebarActiveFill : "#64ffffff"
    readonly property color activeStroke: theme ? theme.sidebarActiveStroke : "#5cffffff"
    readonly property color hoverFill: theme ? theme.sidebarHoverFill : "#42ffffff"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
    readonly property color danger: theme ? theme.danger : "#ff453a"

    signal activated()

    Layout.fillWidth: true
    Layout.preferredHeight: 34
    scale: Motion.pressScaleFor(theme && theme.settingsService ? theme.settingsService : null, buttonMouse.pressed)

    Behavior on scale {
        NumberAnimation {
            duration: Motion.pressDurationFor(btn.theme && btn.theme.settingsService ? btn.theme.settingsService : null)
            easing.type: Motion.pressEasing
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: buttonMouse.pressed
            ? Qt.darker(btn.active ? btn.activeFill : btn.hoverFill, 1.18)
            : btn.active ? btn.activeFill : (buttonMouse.containsMouse ? btn.hoverFill : "transparent")
        border.color: btn.active ? btn.activeStroke : "transparent"
        border.width: 1
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 9
        anchors.rightMargin: 8
        spacing: 10

        Text {
            Layout.preferredWidth: 22
            Layout.alignment: Qt.AlignVCenter
            text: btn.iconCode
            color: btn.active ? btn.accentBlue : btn.textSecondary
            font.family: btn.iconFont
            font.pixelSize: 18
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
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
