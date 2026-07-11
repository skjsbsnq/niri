pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../Motion.js" as Motion
import "../.."

Item {
    id: btn

    property var theme
    property string label: ""
    property string iconCode: ""
    // Brand color for TahoeCategoryIcon square; falls back to accent.
    property color categoryColor: theme ? theme.accentBlue : "#007ff7"
    property bool active: false
    property string badgeText: ""

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
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

    // T15: selected = solid accent capsule + white label; idle = transparent + hover wash.
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: buttonMouse.pressed
            ? Qt.darker(btn.active ? btn.accentBlue : btn.hoverFill, 1.12)
            : btn.active ? btn.accentBlue : (buttonMouse.containsMouse ? btn.hoverFill : "transparent")
        border.width: 0
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 10

        TahoeCategoryIcon {
            id: catIcon
            theme: btn.theme
            iconCode: btn.iconCode
            accentColor: btn.categoryColor
            square: 24
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            Layout.fillWidth: true
            text: btn.label
            color: btn.active ? "#ffffff" : btn.textPrimary
            font.pixelSize: 13
            font.weight: btn.active ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }

        Rectangle {
            id: badge
            Layout.preferredWidth: badgeLabel.implicitWidth + 10
            Layout.preferredHeight: 16
            radius: 8
            color: btn.active ? "#33ffffff" : btn.danger
            opacity: btn.active ? 1 : 0.85
            visible: btn.badgeText.length > 0

            Text {
                id: badgeLabel
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
