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
    property var fanService
    property var anchorRect: null
    property var settingsService

    readonly property int edgePadding: 8
    readonly property int fallbackRight: 164
    readonly property int fallbackTop: 28
    readonly property int popupGap: 8
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, fallbackRight)
    readonly property bool backendAvailable: !!fanService && fanService.backendAvailable
    readonly property bool controlEnabled: !!fanService && fanService.controlEnabled
    readonly property bool available: !!fanService && fanService.available
    readonly property int percent: fanService ? fanService.effectivePercent : 0
    signal closeRequested()

    visible: open
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 328
    implicitHeight: panel.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "tahoe-fan-popup"

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
            spacing: 11

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "风扇"
                    color: "#1d1d1f"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                Controls.IconButton {
                    iconCode: "\ue5d5"
                    enabled: !!root.fanService
                    settingsService: root.settingsService
                    onActivated: {
                        if (root.fanService)
                            root.fanService.refresh();
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 78
                radius: 18
                color: "#40ffffff"
                border.color: "#44ffffff"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: 24
                        color: root.available ? "#2c9cf2" : "#24ffffff"
                        border.color: "#34ffffff"
                        border.width: 1

                        TahoeSymbol {
                            anchors.centerIn: parent
                            // Semantic "fan" PNG (not e332 toys/car).
                            name: "fan"
                            color: root.available ? "#ffffff" : "#731d1d1f"
                            size: 24
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: root.available
                                ? (root.fanService.autoMode ? "自动控制" : "手动 " + root.percent + "%")
                                : (root.backendAvailable ? "BIOS 接管" : "未连接")
                            color: "#1d1d1f"
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.fanService
                                ? (root.fanService.temperatureText.length > 0
                                   ? root.fanService.temperatureText + " · " + root.fanService.statusText
                                   : root.fanService.statusText)
                                : "不可用"
                            color: "#731d1d1f"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.fanService ? root.fanService.errorText : "需要风扇服务"
                color: "#ccff453a"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                visible: text.length > 0
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "NBFC 控制"
                    color: "#991d1d1f"
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }

                Controls.ToggleSwitch {
                    checked: root.controlEnabled
                    enabled: root.backendAvailable && root.fanService && !root.fanService.updating
                    settingsService: root.settingsService
                    onToggled: {
                        if (root.fanService)
                            root.fanService.setControlEnabled(!root.fanService.controlEnabled);
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "自动"
                    color: "#991d1d1f"
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }

                Controls.ToggleSwitch {
                    checked: root.fanService && root.fanService.autoMode
                    enabled: root.available
                    settingsService: root.settingsService
                    onToggled: {
                        if (root.fanService)
                            root.fanService.setAutoMode(!root.fanService.autoMode);
                    }
                }
            }

            FanSlider {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                value: root.percent / 100
                enabled: root.available
                onUserSet: function(v) {
                    if (root.fanService)
                        root.fanService.setManualSpeed(Math.round(v * 100));
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 7

                Controls.TextButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    label: "30%"
                    enabled: root.available
                    settingsService: root.settingsService
                    onActivated: {
                        if (root.fanService)
                            root.fanService.setManualSpeed(30);
                    }
                }

                Controls.TextButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    label: "50%"
                    enabled: root.available
                    settingsService: root.settingsService
                    onActivated: {
                        if (root.fanService)
                            root.fanService.setManualSpeed(50);
                    }
                }

                Controls.TextButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    label: "70%"
                    enabled: root.available
                    settingsService: root.settingsService
                    onActivated: {
                        if (root.fanService)
                            root.fanService.setManualSpeed(70);
                    }
                }

                Controls.TextButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    label: "100%"
                    enabled: root.available
                    settingsService: root.settingsService
                    onActivated: {
                        if (root.fanService)
                            root.fanService.setManualSpeed(100);
                    }
                }
            }
        }
    }

    component FanSlider: Item {
        id: slider

        property real value: 0
        property bool enabled: true
        property bool userDragging: false
        property real userValue: 0
        signal userSet(real value)

        readonly property real sourceValue: Math.max(0, Math.min(1, slider.value))
        readonly property real displayValue: userDragging ? userValue : sourceValue

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: "#40ffffff"
            border.color: "#44ffffff"
            border.width: 1
            opacity: slider.enabled ? 1 : 0.5

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 5

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "转速"
                        color: "#991d1d1f"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }

                    Text {
                        text: Math.round(slider.displayValue * 100) + "%"
                        color: "#1d1d1f"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    id: track
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    radius: 13
                    color: "#47ffffff"
                    clip: true

                    Rectangle {
                        id: sliderFill

                        width: parent.width * slider.displayValue
                        height: parent.height
                        radius: parent.radius
                        color: "#f2ffffff"

                        Behavior on width {
                            enabled: !dragArea.pressed && !slider.userDragging
                            NumberAnimation {
                                id: fillFollowAnimation
                                duration: Motion.elementMove(root.settingsService)
                                easing.type: Motion.emphasizedDecel
                            }
                        }
                    }

                    TahoeSymbol {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: "fan"
                        color: "#731d1d1f"
                        size: 15
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        enabled: slider.enabled
                        cursorShape: slider.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        preventStealing: true

                        function applyValue(mouseX) {
                            if (track.width <= 0)
                                return;
                            var v = Math.max(0, Math.min(1, mouseX / track.width));
                            slider.userValue = v;
                            slider.userSet(v);
                            return v;
                        }

                        onPressed: function(mouse) {
                            fillFollowAnimation.stop();
                            slider.userDragging = true;
                            dragArea.applyValue(mouse.x);
                        }
                        onPositionChanged: function(mouse) {
                            if (pressed)
                                dragArea.applyValue(mouse.x);
                        }
                        onReleased: function(mouse) {
                            dragArea.applyValue(mouse.x);
                            slider.userDragging = false;
                        }
                        onCanceled: slider.userDragging = false
                    }
                }
            }
        }
    }
}
