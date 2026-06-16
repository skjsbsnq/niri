pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property bool open: false
    property var batteryService

    readonly property bool available: !!batteryService && batteryService.available
    readonly property int percentage: available ? batteryService.roundedPercentage : 0
    readonly property string iconFont: "Material Icons"

    signal closeRequested()

    visible: open || panel.opacity > 0.01
    aboveWindows: true
    exclusiveZone: 0
    implicitWidth: 292
    implicitHeight: panel.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "tahoe-battery-popup"

    anchors {
        top: true
        right: true
    }

    margins {
        top: 0
        right: 92
    }

    TahoeGlass.regions: [
        TahoeGlassRegion {
            item: panel
            material: panel.tahoeGlassMaterial
            radius: panel.tahoeGlassRadius
            blur: true
            shadow: true
            clip: true
            enabled: root.open || panel.opacity > 0.01
        }
    ]

    Rectangle {
        id: panel
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialPanel
        readonly property real tahoeGlassRadius: GlassStyle.RadiusPopup

        y: root.open ? 0 : -12
        width: parent.width
        implicitHeight: content.implicitHeight + 24
        height: implicitHeight
        radius: tahoeGlassRadius
        color: GlassStyle.FillPanelBright
        opacity: root.open ? 1 : 0

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: GlassStyle.StrokePanelBright
            border.width: 1
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: GlassStyle.ShadowLineSoft
            border.width: 1
            z: -1
        }

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Battery"
                    color: "#1d1d1f"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                Text {
                    text: root.available && root.batteryService.charging ? "\ue1a3" : "\ue1a4"
                    color: "#1d1d1f"
                    font.family: root.iconFont
                    font.pixelSize: 18
                    visible: root.available
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Item {
                    Layout.preferredWidth: 108
                    Layout.preferredHeight: 52

                    Rectangle {
                        id: batteryBody

                        x: 0
                        y: 8
                        width: 96
                        height: 36
                        radius: 9
                        color: "#18ffffff"
                        border.color: "#9a1d1d1f"
                        border.width: 2

                        Rectangle {
                            x: 5
                            y: 5
                            width: root.available ? Math.max(4, (parent.width - 10) * root.percentage / 100) : 0
                            height: parent.height - 10
                            radius: 6
                            color: root.available && root.percentage <= 15 && root.batteryService.onBattery ? "#ff453a" : "#34c759"
                        }
                    }

                    Rectangle {
                        x: batteryBody.x + batteryBody.width + 2
                        y: batteryBody.y + 12
                        width: 7
                        height: 12
                        radius: 3
                        color: "#9a1d1d1f"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        text: root.available ? root.percentage + "%" : "Unavailable"
                        color: "#1d1d1f"
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: root.available ? root.batteryService.stateText : "No battery reported"
                        color: "#991d1d1f"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.available ? root.batteryService.timeText : ""
                        color: "#731d1d1f"
                        font.pixelSize: 11
                        visible: text.length > 0
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#22000000"
            }

            InfoRow {
                label: "Power Source"
                value: root.batteryService ? root.batteryService.powerSourceText : "Unavailable"
            }

            InfoRow {
                label: "Battery Health"
                value: root.batteryService && root.batteryService.healthText.length > 0
                    ? root.batteryService.healthText
                    : "Not Reported"
            }
        }
    }

    component InfoRow: RowLayout {
        id: row

        property string label: ""
        property string value: ""

        Layout.fillWidth: true
        spacing: 10

        Text {
            text: row.label
            color: "#991d1d1f"
            font.pixelSize: 12
            Layout.fillWidth: true
        }

        Text {
            text: row.value
            color: "#1d1d1f"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            Layout.maximumWidth: 150
        }
    }
}
