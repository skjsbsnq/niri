pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../Motion.js" as Motion

Item {
    id: sw

    property var theme
    property var settingsService
    property bool checked: false
    // Parent (TahoeListRow) binds this for press-stretch feedback.
    property bool pressed: false

    readonly property var motionSettings: settingsService
        ? settingsService
        : (theme && theme.settingsService ? theme.settingsService : null)
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
    readonly property color switchOff: theme ? theme.switchOff : "#2e000000"
    // T16: pressed knob stretches 20 → 24.
    readonly property real knobSize: 20
    readonly property real knobWidth: pressed ? 24 : 20
    readonly property real trackPad: 2

    Layout.preferredWidth: 42
    Layout.preferredHeight: 24

    Rectangle {
        id: track
        anchors.fill: parent
        radius: 12
        color: sw.checked ? sw.accentBlue : sw.switchOff

        Behavior on color {
            ColorAnimation {
                duration: Motion.reducedMotion(sw.motionSettings) ? 0 : 150
                easing.type: Motion.emphasizedDecel
            }
        }

        // Soft shadow under the white knob (drawn first).
        Rectangle {
            width: knob.width + 2
            height: knob.height + 2
            radius: height / 2
            x: knob.x - 1
            y: knob.y + 1
            color: "#28000000"
            z: 0
        }

        Rectangle {
            id: knob
            width: sw.knobWidth
            height: sw.knobSize
            radius: height / 2
            x: sw.checked ? parent.width - width - sw.trackPad : sw.trackPad
            anchors.verticalCenter: parent.verticalCenter
            color: "#ffffff"
            z: 1

            Behavior on x {
                NumberAnimation {
                    duration: Motion.elementMove(sw.motionSettings)
                    easing.type: Motion.emphasizedDecel
                }
            }

            Behavior on width {
                NumberAnimation {
                    duration: Motion.pressDurationFor(sw.motionSettings)
                    easing.type: Motion.emphasizedDecel
                }
            }
        }
    }
}
