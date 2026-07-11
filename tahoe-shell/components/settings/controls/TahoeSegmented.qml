pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../Motion.js" as Motion

// macOS-style segmented control (T16): equal-width segments, solid selected
// accent, light-gray idle fill, 13px labels. No spring (guardrail E).
RowLayout {
    id: control

    property var theme
    property var model: []          // [{value: string, label: string}]
    property string value: ""

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
    readonly property color solidFill: theme && theme.buttonFillSolid !== undefined
        ? theme.buttonFillSolid
        : "#e5e5ea"
    readonly property color solidHover: theme && theme.buttonFillSolidHover !== undefined
        ? theme.buttonFillSolidHover
        : "#d1d1d6"

    signal selected(string value)

    spacing: 0
    Layout.fillWidth: true

    Repeater {
        model: control.model

        delegate: Rectangle {
            id: segment

            required property var modelData
            required property int index

            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 8
            color: segmentMouse.pressed
                ? Qt.darker(segment.active ? control.accentBlue : control.solidFill, 1.12)
                : segment.active
                    ? control.accentBlue
                    : (segmentMouse.containsMouse ? control.solidHover : control.solidFill)
            border.width: 0
            visible: index < control.model.length
            scale: Motion.pressScaleFor(control.theme && control.theme.settingsService ? control.theme.settingsService : null, segmentMouse.pressed)

            readonly property bool active: control.value === segment.modelData.value

            Behavior on scale {
                NumberAnimation {
                    duration: Motion.pressDurationFor(control.theme && control.theme.settingsService ? control.theme.settingsService : null)
                    easing.type: Motion.pressEasing
                }
            }

            // Contiguous bar: fill the join against neighbours.
            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.radius
                color: parent.color
                visible: segment.index > 0
                x: -0.5
            }
            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.radius
                color: parent.color
                visible: segment.index < control.model.length - 1
                anchors.right: parent.right
                anchors.rightMargin: -0.5
            }

            Text {
                anchors.centerIn: parent
                text: segment.modelData.label
                color: segment.active ? "#ffffff" : control.textPrimary
                font.pixelSize: 13
                font.weight: segment.active ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }

            MouseArea {
                id: segmentMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: control.selected(segment.modelData.value)
            }
        }
    }
}
