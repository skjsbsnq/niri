pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion
import "PopupGeometry.js" as PopupGeometry

PanelWindow {
    id: root

    property bool open: false
    property var batteryService
    property var powerProfileService
    property var anchorRect: null
    property var settingsService
    property bool closeHold: false
    property bool wasOpen: false
    property real panelOffset: 0

    readonly property bool available: !!batteryService && batteryService.available
    readonly property int percentage: available ? batteryService.roundedPercentage : 0
    readonly property bool profileAvailable: !!powerProfileService && powerProfileService.available
    readonly property string iconFont: "Material Icons"
    readonly property int edgePadding: 8
    readonly property int fallbackRight: 92
    readonly property int fallbackTop: 28
    readonly property int popupGap: 8
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, fallbackRight)
    readonly property int closeDistance: 18
    signal closeRequested()

    visible: open || closeHold
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

    onOpenChanged: {
        if (open) {
            closeUnmapTimer.stop();
            closeMotion.stop();
            wasOpen = true;
            closeHold = false;
            panelOffset = 0;
        } else if (wasOpen) {
            wasOpen = false;
            closeHold = true;
            closeMotion.restart();
            closeUnmapTimer.restart();
        }
    }

    NumberAnimation {
        id: closeMotion
        target: root
        property: "panelOffset"
        from: 0
        to: -root.closeDistance
        duration: Motion.panelExitDuration
        easing.type: Motion.emphasizedAccel
    }

    Timer {
        id: closeUnmapTimer
        interval: Motion.panelExitDuration
        repeat: false
        onTriggered: if (!root.open) root.closeHold = false
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
            interaction: 1
            materialAlpha: 1
            enabled: true
        }
    ]

    Rectangle {
        id: panel
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialPanel
        readonly property real tahoeGlassRadius: GlassStyle.RadiusPopup

        // Keep TahoeGlass live during close; niri only owns the map/open motion.
        y: root.panelOffset
        width: parent.width
        implicitHeight: content.implicitHeight + 24
        height: implicitHeight
        radius: tahoeGlassRadius
        color: GlassStyle.FillPanelBright
        opacity: 1

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: GlassStyle.StrokePanelBright
            border.width: 1
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
                    text: "电池"
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

                    delegate: ProfileButton {
                        required property var modelData

                        Layout.fillWidth: true
                        profile: modelData
                        active: root.powerProfileService && root.powerProfileService.profile === modelData.id
                        supported: root.powerProfileService && root.powerProfileService.supports(modelData.id)
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

    component ProfileButton: Item {
        id: btn

        property var profile
        property bool active: false
        property bool supported: true
        signal activated()

        Layout.preferredHeight: 44

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: btn.active ? "#5ad7f0ff" : (buttonMouse.containsMouse ? "#54ffffff" : "#34ffffff")
            border.color: btn.active ? "#882c9cf2" : "#44ffffff"
            border.width: 1
            opacity: btn.supported ? 1 : 0.45
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 1

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: btn.profile ? btn.profile.icon : ""
                color: btn.active ? "#0b6bd3" : "#731d1d1f"
                font.family: root.iconFont
                font.pixelSize: 16
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: btn.profile ? btn.profile.label : ""
                color: "#1d1d1f"
                font.pixelSize: 11
                font.weight: btn.active ? Font.DemiBold : Font.Normal
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.supported ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (btn.supported)
                    btn.activated();
            }
        }
    }
}
