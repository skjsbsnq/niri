pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion
import "PopupGeometry.js" as PopupGeometry
import "controls" as Controls

PanelWindow {
    id: root

    property bool open: false
    property var batteryService
    property var powerProfileService
    property var anchorRect: null
    property var settingsService

    readonly property bool available: !!batteryService && batteryService.available
    readonly property int percentage: available ? batteryService.roundedPercentage : 0
    readonly property bool profileAvailable: !!powerProfileService && powerProfileService.available
    readonly property int edgePadding: 8
    readonly property int fallbackRight: 92
    readonly property int fallbackTop: 28
    readonly property int popupGap: 8
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, fallbackRight)
    signal closeRequested()

    visible: open
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
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

    TahoeGlass.regions: [panel.region]

    GlassPanel {
        id: panel

        // Keep the compositor glass region anchored. In compositor animation
        // mode niri owns the outer motion.
        y: 0
        width: parent.width
        implicitHeight: content.implicitHeight + 24
        height: implicitHeight
        material: GlassStyle.MaterialPanel
        radius: GlassStyle.RadiusPopup
        fillColor: GlassStyle.FillPanelBright
        strokeColor: GlassStyle.StrokePanelBright
        opacity: 1

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
                    text: "电池"
                    color: "#1d1d1f"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                TahoeSymbol {
                    name: root.available && root.batteryService.charging ? "\ue1a3" : "\ue1a4"
                    color: "#1d1d1f"
                    size: 18
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
                            id: batteryFill

                            x: 5
                            y: 5
                            width: root.available ? Math.max(4, (parent.width - 10) * root.percentage / 100) : 0
                            height: parent.height - 10
                            radius: 6
                            color: root.available && root.percentage <= 15 && root.batteryService.onBattery ? "#ff453a" : "#34c759"

                            Behavior on width {
                                NumberAnimation {
                                    duration: Motion.elementResize(root.settingsService)
                                    easing.type: Motion.emphasizedDecel
                                }
                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: Motion.fadeFast(root.settingsService)
                                    easing.type: Motion.standardDecel
                                }
                            }
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
                        text: root.available ? root.percentage + "%" : "不可用"
                        color: "#1d1d1f"
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: root.available ? root.batteryService.stateText : "未检测到电池"
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
                label: "电源"
                value: root.batteryService ? root.batteryService.powerSourceText : "不可用"
            }

            InfoRow {
                label: "电池健康"
                value: root.batteryService && root.batteryService.healthText.length > 0
                    ? root.batteryService.healthText
                    : "未报告"
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#22000000"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "性能配置"
                    color: "#991d1d1f"
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }

                Text {
                    text: root.profileAvailable
                        ? root.powerProfileService.labelFor(root.powerProfileService.profile)
                        : "不可用"
                    color: "#1d1d1f"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    Layout.maximumWidth: 150
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 7

                Repeater {
                    model: root.powerProfileService ? root.powerProfileService.profiles : []

                    delegate: Controls.ButtonSurface {
                        id: profileButton

                        required property var modelData
                        readonly property bool supported: root.powerProfileService
                            && root.powerProfileService.supports(modelData.id)

                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        settingsService: root.settingsService
                        active: root.powerProfileService && root.powerProfileService.profile === modelData.id
                        enabled: supported
                        cornerRadius: 14
                        baseColor: "#34ffffff"
                        hoverColor: "#54ffffff"
                        borderColor: "#44ffffff"
                        activeColor: "#5ad7f0ff"
                        activeHoverColor: "#68d7f0ff"
                        activeBorderColor: "#882c9cf2"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 1

                            TahoeSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                name: profileButton.modelData ? profileButton.modelData.icon : ""
                                color: profileButton.active ? "#0b6bd3" : "#731d1d1f"
                                size: 16
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: profileButton.modelData ? profileButton.modelData.label : ""
                                color: "#1d1d1f"
                                font.pixelSize: 11
                                font.weight: profileButton.active ? Font.DemiBold : Font.Normal
                            }
                        }

                        onActivated: {
                            if (root.powerProfileService)
                                root.powerProfileService.setProfile(modelData.id);
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.powerProfileService ? root.powerProfileService.errorText : "需要 power-profiles-daemon"
                color: "#ccff453a"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                visible: text.length > 0
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
