pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: slider

    property var theme
    property string iconCode: ""
    property string label: ""
    property real value: 0
    property bool interactive: true

    readonly property string iconFont: theme ? theme.iconFont : "Material Icons"
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color rowFill: theme ? theme.rowFill : "#28ffffff"
    readonly property color rowStroke: theme ? theme.rowStroke : "#32ffffff"

    signal userSet(real value)

    Layout.fillWidth: true
    Layout.preferredHeight: 52
    opacity: enabled ? 1 : 0.6

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: slider.rowFill
        border.color: slider.rowStroke
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Text {
                Layout.preferredWidth: slider.iconCode.length > 0 ? 22 : 0
                Layout.alignment: Qt.AlignVCenter
                text: slider.iconCode
                color: slider.textPrimary
                font.family: slider.iconFont
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
                visible: slider.iconCode.length > 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5

                Text {
                    Layout.fillWidth: true
                    text: slider.label
                    color: slider.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    visible: text.length > 0
                }

                Rectangle {
                    id: track
                    Layout.fillWidth: true
                    Layout.preferredHeight: 10
                    radius: 5
                    color: "#47ffffff"
                    clip: true

                    Rectangle {
                        height: parent.height
                        width: parent.width * Math.max(0, Math.min(1, slider.value))
                        radius: parent.radius
                        color: "#f2ffffff"
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: slider.enabled && slider.interactive
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onPressed: function(mouse) {
                            slider.userSet(mouse.x / Math.max(1, width));
                        }
                        onPositionChanged: function(mouse) {
                            if (pressed)
                                slider.userSet(mouse.x / Math.max(1, width));
                        }
                    }
                }
            }
        }
    }
}
