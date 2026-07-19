pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../Motion.js" as Motion

Item {
    id: control

    property var settingsService
    property bool active: false
    property bool prominent: false
    property bool flat: false
    property color baseColor: flat ? "transparent" : "#34ffffff"
    property color hoverColor: "#70ffffff"
    property color activeColor: "#d82c9cf2"
    property color activeHoverColor: activeColor
    property color prominentColor: activeColor
    property color prominentHoverColor: prominentColor
    property color borderColor: flat ? "transparent" : "#50ffffff"
    property color activeBorderColor: "#70ffffff"
    property color prominentBorderColor: activeBorderColor
    property real cornerRadius: height / 2
    readonly property bool hovered: inputArea.containsMouse
    readonly property bool pressed: inputArea.pressed
    default property alias contentData: content.data

    signal activated()

    opacity: enabled ? 1 : 0.45
    scale: Motion.pressScaleFor(settingsService, inputArea.pressed && enabled)
    transformOrigin: Item.Center

    Behavior on opacity {
        NumberAnimation {
            duration: Motion.fadeFast(control.settingsService)
            easing.type: Motion.standardDecel
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: Motion.pressDurationFor(control.settingsService)
            easing.type: Motion.pressEasing
        }
    }

    Rectangle {
        id: background

        anchors.fill: parent
        radius: control.cornerRadius
        color: control.prominent
            ? (control.hovered && control.enabled ? control.prominentHoverColor : control.prominentColor)
            : (control.active
                ? (control.hovered && control.enabled ? control.activeHoverColor : control.activeColor)
                : (control.hovered && control.enabled ? control.hoverColor : control.baseColor))
        border.color: control.prominent ? control.prominentBorderColor
            : (control.active ? control.activeBorderColor : control.borderColor)
        border.width: border.color.a > 0 ? 1 : 0

        Behavior on color {
            ColorAnimation {
                duration: Motion.fadeFast(control.settingsService)
                easing.type: Motion.standardDecel
            }
        }
    }

    Item {
        id: content

        anchors.fill: parent
    }

    MouseArea {
        id: inputArea

        objectName: "buttonInput"
        anchors.fill: parent
        enabled: control.enabled
        hoverEnabled: true
        cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: control.activated()
    }
}
