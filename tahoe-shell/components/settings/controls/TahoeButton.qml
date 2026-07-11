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
    property bool primary: false
    property bool active: false
    property bool iconOnly: false
    property real minimumWidth: iconOnly ? 32 : 54

    readonly property bool primaryState: primary || active
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    // T16: primary = solid accent; secondary = solid light gray (not glass wash).
    readonly property color solidFill: theme && theme.buttonFillSolid !== undefined
        ? theme.buttonFillSolid
        : (theme && theme.darkMode ? "#3a3a3c" : "#e5e5ea")
    readonly property color solidHover: theme && theme.buttonFillSolidHover !== undefined
        ? theme.buttonFillSolidHover
        : (theme && theme.darkMode ? "#48484a" : "#d1d1d6")
    readonly property color accentFill: theme ? theme.accentFillStrong : "#d8007ff7"
    readonly property color accentStroke: theme ? theme.accentStrokeStrong : "#70ffffff"
    readonly property color fillColor: buttonMouse.pressed && btn.enabled
        ? Qt.darker(btn.primaryState ? btn.accentFill : btn.solidFill, 1.12)
        : btn.primaryState
            ? btn.accentFill
            : (buttonMouse.containsMouse && btn.enabled ? btn.solidHover : btn.solidFill)

    signal activated()

    Layout.preferredWidth: iconOnly ? 32 : Math.max(minimumWidth, labelText.implicitWidth + (btn.iconCode.length > 0 ? 34 : 24))
    Layout.preferredHeight: iconOnly ? 32 : 30
    opacity: enabled ? 1 : 0.45
    scale: Motion.pressScaleFor(theme && theme.settingsService ? theme.settingsService : null, buttonMouse.pressed && enabled)

    Behavior on scale {
        NumberAnimation {
            duration: Motion.pressDurationFor(btn.theme && btn.theme.settingsService ? btn.theme.settingsService : null)
            easing.type: Motion.pressEasing
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: btn.fillColor
        border.width: 0
    }

    Row {
        anchors.centerIn: parent
        spacing: 5
        visible: !btn.iconOnly

        TahoeSymbol {
            name: btn.iconCode
            color: btn.primaryState ? "#ffffff" : btn.textPrimary
            size: 15
            visible: btn.iconCode.length > 0
        }

        Text {
            id: labelText
            text: btn.label
            color: btn.primaryState ? "#ffffff" : btn.textPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }

    TahoeSymbol {
        anchors.centerIn: parent
        name: btn.iconCode
        color: btn.textPrimary
        size: 18
        visible: btn.iconOnly
    }

    MouseArea {
        id: buttonMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (btn.enabled)
                btn.activated();
        }
    }
}
