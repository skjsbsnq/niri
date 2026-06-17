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
    property var controlsService
    property var anchorRect: null
    readonly property var networks: controlsService ? controlsService.wifiNetworks : []
    readonly property string iconFont: "Material Icons"
    readonly property int edgePadding: 8
    readonly property int fallbackRight: 132
    readonly property int fallbackTop: 34
    readonly property int popupGap: 5
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, fallbackRight)

    signal closeRequested()

    visible: open || panel.opacity > 0.01
    aboveWindows: true
    focusable: open
    exclusiveZone: 0
    implicitWidth: 328
    implicitHeight: panel.implicitHeight
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

                ToggleSwitch {
                    checked: root.controlsService && root.controlsService.wifiEnabled
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

                Text {
                    text: "\ue63e"
                    color: "#2c9cf2"
                    font.family: root.iconFont
                    font.pixelSize: 17
                    Layout.alignment: Qt.AlignVCenter
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

                PillButton {
                    label: "断开"
                    danger: true
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
                text: root.controlsService && root.controlsService.wifiEnabled ? "未发现网络" : "Wi-Fi 已关闭"
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
                model: root.networks

                property string expandedSsid: ""

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

                PillButton {
                    label: "重新扫描"
                    onActivated: {
                        if (root.controlsService)
                            root.controlsService.rescanWifi();
                    }
                }

                Item { Layout.fillWidth: true }

                PillButton {
                    label: "Wi-Fi 设置..."
                    onActivated: Quickshell.execDetached({ command: ["nm-connection-editor"] })
                }
            }
        }
    }

    component ToggleSwitch: Item {
        id: sw

        property bool checked: false
        signal toggled()

        Layout.preferredWidth: 42
        Layout.preferredHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: sw.checked ? "#2c9cf2" : "#32000000"
            border.color: "#38ffffff"
            border.width: 1

            Rectangle {
                width: 20
                height: 20
                radius: 10
                x: sw.checked ? parent.width - width - 2 : 2
                anchors.verticalCenter: parent.verticalCenter
                color: "#ffffff"

                Behavior on x {
                    NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
    }

    component PillButton: Item {
        id: btn

        property string label: ""
        property bool danger: false
        signal activated()

        Layout.preferredWidth: labelText.implicitWidth + 18
        Layout.preferredHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: buttonMouse.containsMouse ? "#70ffffff" : "#34ffffff"
            border.color: "#50ffffff"
            border.width: 1
        }

        Text {
            id: labelText
            anchors.centerIn: parent
            text: btn.label
            color: btn.danger ? "#ccff453a" : "#1d1d1f"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
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

                        Text {
                            text: row.entry && row.entry.connected ? "\ue5ca" : (row.entry && row.entry.secured ? "\ue897" : "")
                            color: row.entry && row.entry.connected ? "#2c9cf2" : "#731d1d1f"
                            font.family: root.iconFont
                            font.pixelSize: 16
                            Layout.preferredWidth: 18
                            Layout.alignment: Qt.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
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
                    radius: 10
                    color: "#24ffffff"
                    border.color: "#3cffffff"
                    border.width: 1
                    visible: row.expanded
                    clip: true

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

                        PillButton {
                            label: "连接"
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
