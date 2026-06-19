pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// Full-width slider row: optional leading icon, a label with a right-aligned
// value, and a fill-bar track (no visible thumb, matching ControlCenter's
// GlassSlider idiom — the project never uses QtQuick.Controls). value is a
// normalized 0..1 ratio; the owning page maps it to the real domain and
// supplies valueText (e.g. "4500K"). Click or drag the track to set it.
Item {
    id: slider

    property var theme
    property string iconCode: ""
    property string label: ""
    property string valueText: ""
    property real value: 0 // 0..1
    property bool interactive: true

    readonly property string iconFont: theme ? theme.iconFont : "Material Icons"
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
    readonly property color rowFill: theme ? theme.rowFill : "#28ffffff"
    readonly property color rowStroke: theme ? theme.rowStroke : "#32ffffff"
    readonly property color trackColor: theme ? theme.sliderTrack : "#26000000"

    signal userSet(real value)

    Layout.fillWidth: true
    Layout.preferredHeight: 56
    opacity: enabled ? 1 : 0.6

    function clampRatio(r) {
        return Math.max(0, Math.min(1, r));
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: slider.rowFill
        border.color: slider.rowStroke
        border.width: 1
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
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
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: slider.label
                    color: slider.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    visible: text.length > 0
                }

                Text {
                    text: slider.valueText
                    color: slider.accentBlue
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    visible: slider.valueText.length > 0
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                }
            }

            Rectangle {
                id: track
                Layout.fillWidth: true
                Layout.preferredHeight: 8
                radius: 4
                color: slider.trackColor
                clip: true

                Rectangle {
                    height: parent.height
                    width: parent.width * slider.clampRatio(slider.value)
                    radius: parent.radius
                    color: slider.accentBlue
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: slider.enabled && slider.interactive
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: function(mouse) {
                        slider.userSet(slider.clampRatio(mouse.x / Math.max(1, width)));
                    }
                    onPositionChanged: function(mouse) {
                        if (pressed)
                            slider.userSet(slider.clampRatio(mouse.x / Math.max(1, width)));
                    }
                }
            }
        }
    }
}
