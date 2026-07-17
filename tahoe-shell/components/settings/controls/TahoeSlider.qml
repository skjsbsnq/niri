pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../Motion.js" as Motion
import "../.."

// Full-width slider row: optional leading icon, label + value, track with a
// white circular knob + soft shadow (T16). value is a normalized 0..1 ratio.
Item {
    id: slider

    property var theme
    property string iconCode: ""
    property string label: ""
    property string valueText: ""
    property real value: 0 // committed 0..1 value
    property bool interactive: true
    property bool dragging: trackMouse.pressed
    property real dragValue: 0

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
    readonly property color rowFill: theme ? theme.rowFill : "#28ffffff"
    readonly property color rowStroke: theme ? theme.rowStroke : "#32ffffff"
    readonly property color trackColor: theme ? theme.sliderTrack : "#26000000"
    readonly property real knobDiameter: 18
    readonly property real knobScale: dragging ? 1.12 : 1.0
    readonly property real displayValue: dragging ? dragValue : clampRatio(value)

    signal userPreview(real value)
    signal userCommit(real value)

    Layout.fillWidth: true
    Layout.preferredHeight: 56
    opacity: enabled ? 1 : 0.6

    function clampRatio(r) {
        return Math.max(0, Math.min(1, r));
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: slider.rowFill
        border.color: slider.rowStroke
        border.width: 1
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        TahoeSymbol {
            Layout.preferredWidth: slider.iconCode.length > 0 ? 22 : 0
            Layout.alignment: Qt.AlignVCenter
            name: slider.iconCode
            color: slider.textPrimary
            size: 18
            visible: slider.iconCode.length > 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: slider.label
                    color: slider.textPrimary
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    visible: text.length > 0
                }

                Text {
                    text: slider.valueText
                    color: slider.accentBlue
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    visible: slider.valueText.length > 0
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                }
            }

            Item {
                id: trackHost
                Layout.fillWidth: true
                Layout.preferredHeight: 20

                Rectangle {
                    id: track
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6
                    radius: 3
                    color: slider.trackColor

                    Rectangle {
                        height: parent.height
                        width: Math.max(0, (parent.width - slider.knobDiameter) * slider.displayValue + slider.knobDiameter / 2)
                        radius: parent.radius
                        color: slider.accentBlue
                    }
                }

                Item {
                    id: knob
                    width: slider.knobDiameter
                    height: slider.knobDiameter
                    x: (trackHost.width - width) * slider.displayValue
                    anchors.verticalCenter: parent.verticalCenter
                    scale: slider.knobScale

                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.pressDurationFor(slider.theme && slider.theme.settingsService ? slider.theme.settingsService : null)
                            easing.type: Motion.emphasizedDecel
                        }
                    }

                    // Soft shadow disc under the white knob.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 1
                        width: parent.width + 4
                        height: parent.height + 4
                        radius: width / 2
                        color: "#30000000"
                        z: -1
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "#ffffff"
                        border.color: "#14000000"
                        border.width: 1
                    }
                }

                MouseArea {
                    id: trackMouse
                    objectName: "trackMouse"
                    anchors.fill: parent
                    enabled: slider.enabled && slider.interactive
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    preventStealing: true

                    // Map pointer x onto the knob-center travel range so ends
                    // match the visual knob (half-width compensation).
                    function ratioAt(mx) {
                        var travel = Math.max(1, width - slider.knobDiameter);
                        return slider.clampRatio((mx - slider.knobDiameter / 2) / travel);
                    }

                    function previewAt(mx) {
                        slider.dragValue = ratioAt(mx);
                        slider.userPreview(slider.dragValue);
                    }

                    onPressed: function(mouse) {
                        previewAt(mouse.x);
                    }
                    onPositionChanged: function(mouse) {
                        if (pressed)
                            previewAt(mouse.x);
                    }
                    onReleased: function(mouse) {
                        previewAt(mouse.x);
                        slider.userCommit(slider.dragValue);
                    }
                    onCanceled: {
                        slider.userCommit(slider.dragValue);
                    }
                }
            }
        }
    }
}
