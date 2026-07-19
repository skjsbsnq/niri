pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../Motion.js" as Motion

Item {
    id: control

    property var settingsService
    property bool checked: false
    property bool compact: false
    property bool interactive: true
    property color checkedColor: "#2c9cf2"
    property color uncheckedColor: "#32000000"
    property color borderColor: "#38ffffff"
    signal toggled()

    readonly property real trackWidth: compact ? 40 : 42
    readonly property real trackHeight: compact ? 22 : 24
    readonly property real knobSize: compact ? 18 : 20

    Layout.preferredWidth: trackWidth
    Layout.preferredHeight: trackHeight
    Layout.alignment: Qt.AlignVCenter
    opacity: enabled ? 1 : 0.45
    scale: Motion.pressScaleFor(settingsService,
        inputArea.pressed && interactive && enabled)
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
        id: track

        anchors.fill: parent
        radius: height / 2
        color: control.checked ? control.checkedColor : control.uncheckedColor
        border.color: control.borderColor
        border.width: 1

        Behavior on color {
            ColorAnimation {
                duration: Motion.elementMove(control.settingsService)
                easing.type: Motion.emphasizedDecel
            }
        }

        Rectangle {
            id: knob

            width: control.knobSize
            height: control.knobSize
            radius: height / 2
            x: control.checked ? parent.width - width - 2 : 2
            anchors.verticalCenter: parent.verticalCenter
            color: "#ffffff"

            Behavior on x {
                NumberAnimation {
                    duration: Motion.elementMove(control.settingsService)
                    easing.type: Motion.emphasizedDecel
                }
            }
        }
    }

    MouseArea {
        id: inputArea

        objectName: "switchInput"
        anchors.fill: parent
        enabled: control.enabled && control.interactive
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: control.toggled()
    }
}
