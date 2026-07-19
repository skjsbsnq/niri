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
    property var controlsService
    property var anchorRect: null
    property var settingsService
    readonly property var networks: controlsService ? controlsService.wifiNetworks : []
    readonly property bool scanning: controlsService ? !!controlsService.wifiScanning : false
    readonly property int edgePadding: 8
    readonly property int fallbackRight: 132
    readonly property int fallbackTop: 28
    readonly property int popupGap: 8
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, fallbackRight)
    signal closeRequested()

    visible: open
    aboveWindows: true
    focusable: open
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 328
    implicitHeight: panel.height
    color: "transparent"
    WlrLayershell.namespace: "tahoe-wifi-popup"

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
        clip: true
        material: GlassStyle.MaterialPanel
        radius: GlassStyle.RadiusPopup
        fillColor: GlassStyle.FillPanelBright
        strokeColor: GlassStyle.StrokePanelBright
        opacity: 1

        // Glass region geometry follows this height: eased only, never spring.
        Behavior on height {
            NumberAnimation {
                duration: Motion.elementResize(root.settingsService)
                easing.type: Motion.emphasizedDecel
            }
        }

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "Wi-Fi"
                    color: "#1d1d1f"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                Controls.ToggleSwitch {
                    checked: root.controlsService && root.controlsService.wifiEnabled
                    enabled: !!root.controlsService
                    settingsService: root.settingsService
                    onToggled: {
                        if (root.controlsService)
                            root.controlsService.toggleWifi();
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.controlsService && root.controlsService.wifiConnected
                spacing: 8

                TahoeSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    name: "\ue63e"
                    color: "#2c9cf2"
                    size: 17
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: root.controlsService ? root.controlsService.wifiName : ""
                        color: "#1d1d1f"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.controlsService ? (root.controlsService.wifiSignalPercent + "%") : ""
                        color: "#731d1d1f"
                        font.pixelSize: 11
                    }
                }

                Controls.TextButton {
                    label: "断开"
                    danger: true
                    settingsService: root.settingsService
                    onActivated: {
                        if (root.controlsService)
                            root.controlsService.disconnectWifi();
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#22000000"
                visible: root.controlsService && root.controlsService.wifiEnabled
            }

            Text {
                Layout.fillWidth: true
                text: root.controlsService && root.controlsService.wifiEnabled
                    ? (root.scanning ? "正在扫描…" : "未发现网络")
                    : "Wi-Fi 已关闭"
                color: "#8a1d1d1f"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                visible: !root.controlsService
                    || !root.controlsService.wifiEnabled
                    || root.networks.length === 0
                Layout.preferredHeight: 48
                verticalAlignment: Text.AlignVCenter
            }

            ListView {
                id: netList

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(282, Math.max(96, contentHeight))
                visible: root.controlsService && root.controlsService.wifiEnabled && root.networks.length > 0
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel {
                    objectProp: "name"
                    values: root.networks
                }

                property string expandedSsid: ""

                Behavior on Layout.preferredHeight {
                    NumberAnimation {
                        duration: Motion.elementResize(root.settingsService)
                        easing.type: Motion.emphasizedDecel
                    }
                }

                add: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Motion.fadeFast(root.settingsService)
                        easing.type: Motion.standardDecel
                    }
                }

                remove: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: Motion.fadeFast(root.settingsService)
                        easing.type: Motion.standardDecel
                    }
                }

                displaced: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: Motion.elementMove(root.settingsService)
                        easing.type: Motion.emphasizedDecel
                    }
                }

                delegate: WifiNetworkRow {
                    required property var modelData

                    width: netList.width
                    entry: modelData
                    expanded: netList.expandedSsid === modelData.name
                    onToggleExpanded: function(ssid) {
                        netList.expandedSsid = netList.expandedSsid === ssid ? "" : ssid;
                    }
                    onConnectRequested: function(entry, psk) {
                        if (root.controlsService)
                            root.controlsService.connectWifi(entry, psk);
                        netList.expandedSsid = "";
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.controlsService && root.controlsService.wifiEnabled
                spacing: 8

                Controls.TextButton {
                    label: "重新扫描"
                    settingsService: root.settingsService
                    onActivated: {
                        if (root.controlsService)
                            root.controlsService.rescanWifi();
                    }
                }

                Item { Layout.fillWidth: true }

                Controls.TextButton {
                    label: "Wi-Fi 设置..."
                    settingsService: root.settingsService
                    onActivated: Quickshell.execDetached({ command: ["nm-connection-editor"] })
                }
            }
        }
    }

    component WifiNetworkRow: Item {
        id: row

        property var entry
        property bool expanded: false
        signal toggleExpanded(string ssid)
        signal connectRequested(var entry, string psk)

        height: rowFrame.implicitHeight

        Rectangle {
            id: rowFrame

            width: parent.width
            implicitHeight: rowContent.implicitHeight + 14
            height: implicitHeight
            radius: 14
            color: row.entry && row.entry.connected ? "#5ad7f0ff" : (rowMouse.containsMouse ? "#54ffffff" : "#34ffffff")
            border.color: row.entry && row.entry.connected ? "#882c9cf2" : "#44ffffff"
            border.width: 1

            ColumnLayout {
                id: rowContent

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 7
                spacing: 7

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30

                    RowLayout {
                        anchors.fill: parent
                        spacing: 8

                        TahoeSymbol {
                            Layout.preferredWidth: 18
                            Layout.alignment: Qt.AlignVCenter
                            name: row.entry && row.entry.connected ? "\ue5ca" : (row.entry && row.entry.secured ? "\ue897" : "")
                            color: row.entry && row.entry.connected ? "#2c9cf2" : "#731d1d1f"
                            size: 16
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: row.entry ? row.entry.name : ""
                                color: "#1d1d1f"
                                font.pixelSize: 13
                                font.weight: row.entry && row.entry.connected ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: row.entry && row.entry.known ? "已保存" : ""
                                color: "#731d1d1f"
                                font.pixelSize: 10
                                visible: text.length > 0
                            }
                        }

                        Text {
                            text: row.entry ? (row.entry.signalPercent + "%") : ""
                            color: "#731d1d1f"
                            font.pixelSize: 11
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!row.entry || row.entry.connected)
                                return;
                            if (row.entry.secured && !row.entry.known) {
                                row.toggleExpanded(row.entry.name);
                                return;
                            }
                            row.connectRequested(row.entry, "");
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: row.expanded ? 42 : 0
                    opacity: row.expanded ? 1 : 0
                    radius: 10
                    color: "#24ffffff"
                    border.color: "#3cffffff"
                    border.width: 1
                    visible: row.expanded || opacity > 0.01 || Layout.preferredHeight > 0.5
                    clip: true

                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: Motion.elementResize(root.settingsService)
                            easing.type: Motion.emphasizedDecel
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.fadeFast(root.settingsService)
                            easing.type: Motion.standardDecel
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 6

                        TextInput {
                            id: pskInput

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "#1d1d1f"
                            selectionColor: "#662c9cf2"
                            selectedTextColor: "#ffffff"
                            font.pixelSize: 13
                            echoMode: TextInput.Password
                            clip: true
                            focus: row.expanded
                            selectByMouse: true
                            verticalAlignment: TextInput.AlignVCenter
                            Keys.onReturnPressed: {
                                row.connectRequested(row.entry, pskInput.text);
                                pskInput.text = "";
                            }
                            Keys.onEscapePressed: row.toggleExpanded(row.entry ? row.entry.name : "")
                        }

                        Controls.TextButton {
                            label: "连接"
                            settingsService: root.settingsService
                            onActivated: {
                                row.connectRequested(row.entry, pskInput.text);
                                pskInput.text = "";
                            }
                        }
                    }
                }
            }
        }
    }
}
