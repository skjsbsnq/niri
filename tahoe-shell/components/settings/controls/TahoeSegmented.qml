pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// macOS-style segmented control: a row of equal-width toggle segments used to
// pick one value (e.g. the glass material). Reads theme tokens, uses no spring
// (guardrail E: VM/software-rendering safety), and emits selected(value).
RowLayout {
    id: control

    property var theme
    property var model: []          // [{value: string, label: string}]
    property string value: ""

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
    readonly property color buttonFill: theme ? theme.buttonFill : "#40ffffff"
    readonly property color buttonStroke: theme ? theme.buttonStroke : "#50ffffff"

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
            // Round only the outer corners so adjacent segments form a pill.
            radius: 8
            color: segment.active ? control.accentBlue : control.buttonFill
            border.color: control.buttonStroke
            border.width: 1
            visible: index < control.model.length

            readonly property bool active: control.value === segment.modelData.value

            // Clip the inner corners against neighbours for a contiguous bar.
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
                font.pixelSize: 11
                font.weight: segment.active ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: control.selected(segment.modelData.value)
            }
        }
    }
}
