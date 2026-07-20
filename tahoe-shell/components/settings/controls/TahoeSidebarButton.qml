pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../Motion.js" as Motion
import "../.."

// Neutral symbolic sidebar row (system-settings idiom).
// Selected = soft accent wash + accent label; idle = monochrome icon + primary text.
// categoryColor is accepted for API stability with SettingsSidebar but is not
// used for a rainbow brand square.
Item {
    id: btn

    property var theme
    property string label: ""
    property string iconCode: ""
    property color categoryColor: theme ? theme.accentBlue : "#007ff7"
    property bool active: false
    property string badgeText: ""

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color hoverFill: theme ? theme.sidebarHoverFill : "#42ffffff"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
    readonly property color danger: theme ? theme.danger : "#ff453a"
    // Soft accent wash from the live accent color (not a solid capsule).
    readonly property color activeFill: Qt.rgba(
        btn.accentBlue.r, btn.accentBlue.g, btn.accentBlue.b,
        theme && theme.darkMode ? 0.22 : 0.14)
    readonly property color iconColor: btn.active ? btn.accentBlue : btn.textSecondary
    readonly property color labelColor: btn.active ? btn.accentBlue : btn.textPrimary

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
            ? Qt.darker(btn.active ? btn.activeFill : btn.hoverFill, 1.08)
            : btn.active ? btn.activeFill : (buttonMouse.containsMouse ? btn.hoverFill : "transparent")
        border.width: 0
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 8
        spacing: 10

        TahoeSymbol {
            Layout.preferredWidth: 20
            Layout.alignment: Qt.AlignVCenter
            name: btn.iconCode
            color: btn.iconColor
            size: 18
            visible: btn.iconCode.length > 0
        }

        Text {
            Layout.fillWidth: true
            text: btn.label
            color: btn.labelColor
            font.pixelSize: 13
            font.weight: btn.active ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }

        Rectangle {
            id: badge
            Layout.preferredWidth: badgeLabel.implicitWidth + 10
            Layout.preferredHeight: 16
            radius: 8
            color: btn.active ? btn.accentBlue : btn.danger
            opacity: btn.active ? 0.9 : 0.85
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
