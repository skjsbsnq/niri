pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

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
    readonly property string iconFont: theme ? theme.iconFont : "Material Icons"
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color rowFillHover: theme ? theme.rowFillHover : "#48ffffff"

    signal activated()

    Layout.preferredWidth: iconOnly ? 32 : Math.max(minimumWidth, labelText.implicitWidth + (btn.iconCode.length > 0 ? 34 : 20))
    Layout.preferredHeight: iconOnly ? 32 : 30
    opacity: enabled ? 1 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: btn.iconOnly ? 12 : 10
        color: btn.primaryState ? "#d82c9cf2" : (buttonMouse.containsMouse && btn.enabled ? btn.rowFillHover : "#48ffffff")
        border.color: btn.primaryState ? "#70ffffff" : "#50ffffff"
        border.width: 1
    }

    Row {
        anchors.centerIn: parent
        spacing: 5
        visible: !btn.iconOnly

        Text {
            text: btn.iconCode
            color: btn.primaryState ? "#ffffff" : btn.textPrimary
            font.family: btn.iconFont
            font.pixelSize: 15
            visible: btn.iconCode.length > 0
        }

        Text {
            id: labelText
            text: btn.label
            color: btn.primaryState ? "#ffffff" : btn.textPrimary
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }

    Text {
        anchors.centerIn: parent
        text: btn.iconCode
        color: btn.textPrimary
        font.family: btn.iconFont
        font.pixelSize: 18
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
