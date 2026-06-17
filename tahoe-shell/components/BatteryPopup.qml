pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "PopupGeometry.js" as PopupGeometry

PanelWindow {
    id: root

    property bool open: false
    property var batteryService
    property var anchorRect: null

    readonly property bool available: !!batteryService && batteryService.available
    readonly property int percentage: available ? batteryService.roundedPercentage : 0
    readonly property string iconFont: "Material Icons"
    readonly property int edgePadding: 8
    readonly property int fallbackRight: 92
    readonly property int fallbackTop: 34
    readonly property int popupGap: 5
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, fallbackRight)

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
        left: true
    }

    margins {
        top: root.popupTopMargin
        left: root.popupLeftMargin
    }

    TahoeGlass.regions: [
        TahoeGlassRegion {
            x: panel.x
            y: panel.y
            width: panel.width
            height: panel.height
            material: panel.tahoeGlassMaterial
            radius: panel.tahoeGlassRadius
            blur: true
            shadow: true
            clip: true
            interaction: panel.opacity
            materialAlpha: panel.opacity
            enabled: root.open || panel.opacity > 0.01
        }
    ]

    Rectangle {
        id: panel
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialPanel
        readonly property real tahoeGlassRadius: GlassStyle.RadiusPopup
        property real contentScale: root.open ? 1 : 0.98

        // Keep the compositor glass region anchored; popup motion is content
        // scale/opacity plus material alpha, not region translation.
        y: 0
        width: parent.width
        implicitHeight: content.implicitHeight + 24
        height: implicitHeight
        radius: tahoeGlassRadius
        color: GlassStyle.FillPanelBright
        opacity: root.open ? 1 : 0

        transform: Scale {
            origin.x: root.popupOriginX
            origin.y: 0
            xScale: panel.contentScale
            yScale: panel.contentScale
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: GlassStyle.StrokePanelBright
            border.width: 1
        }

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Behavior on contentScale {
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
