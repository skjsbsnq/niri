pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls
import "../.."

Flickable {
    id: page

    property var panel
    property var theme
    property var controlsService
    property bool active: false
    readonly property string discoveryOwner: "settings-bluetooth"
    readonly property bool discoveryRequested: hasControls
        && controlsService.bluetoothDiscoveryOwned(discoveryOwner)

    readonly property bool hasControls: !!controlsService
    readonly property bool backendReady: hasControls && controlsService.bluetoothBackendAvailable
    readonly property bool adapterAvailable: hasControls && controlsService.bluetoothAvailable
    readonly property bool bluetoothOn: hasControls && controlsService.bluetoothEnabled
    readonly property bool airplaneMode: hasControls && controlsService.airplaneMode
    readonly property bool adapterBlocked: hasControls && controlsService.bluetoothAdapterBlocked
    readonly property var deviceEntries: hasControls ? controlsService.bluetoothDeviceEntries : []
    readonly property var connectedDevices: filterDevices("connected")
    readonly property var pairedDevices: filterDevices("paired")
    readonly property var nearbyDevices: filterDevices("nearby")

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color textMuted: theme ? theme.textMuted : "#5f6870"
    readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
    readonly property color rowFillHover: theme ? theme.rowFillHover : "#86ffffff"
    readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
    readonly property color danger: theme ? theme.danger : "#ff453a"

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    onActiveChanged: {
        if (!page.active && page.controlsService)
            page.controlsService.setBluetoothDiscoveryActive(page.discoveryOwner, false);
    }

    Component.onDestruction: {
        if (page.controlsService)
            page.controlsService.setBluetoothDiscoveryActive(page.discoveryOwner, false);
    }

    function filterDevices(kind) {
        var out = [];
        var values = page.deviceEntries || [];
        for (var i = 0; i < values.length; i++) {
            var entry = values[i];
            if (!entry)
                continue;
            if (kind === "connected" && entry.connected)
                out.push(entry);
            else if (kind === "paired" && !entry.connected && (entry.paired || entry.bonded))
                out.push(entry);
            else if (kind === "nearby" && !entry.connected && !entry.paired && !entry.bonded)
                out.push(entry);
        }
        return out;
    }

    function statusKind() {
        if (!page.hasControls)
            return "service";
        if (!page.backendReady)
            return "bluez";
        if (page.airplaneMode)
            return "airplane";
        if (!page.adapterAvailable)
            return "adapter";
        if (page.adapterBlocked)
            return "blocked";
        if (!page.bluetoothOn)
            return "off";
        if (page.deviceEntries.length === 0)
            return "empty";
        return "";
    }

    function statusTitle(kind) {
        if (kind === "service")
            return "控制服务不可用";
        if (kind === "bluez")
            return "BlueZ 不可用";
        if (kind === "airplane")
            return "飞行模式已开启";
        if (kind === "adapter")
            return "未检测到蓝牙硬件";
        if (kind === "blocked")
            return "蓝牙被硬件或 rfkill 阻止";
        if (kind === "off")
            return "蓝牙已关闭";
        if (kind === "empty")
            return "没有发现蓝牙设备";
        return "";
    }

    function statusDetail(kind) {
        if (kind === "service")
            return "设置页没有连接到 Controls 服务。";
        if (kind === "bluez") {
            var detail = page.controlsService ? String(page.controlsService.bluetoothErrorText || "").trim() : "";
            return detail.length > 0 ? detail : "缺少 bluetoothctl 或 bluetoothd 未运行。";
        }
        if (kind === "airplane")
            return "关闭飞行模式后可以重新启用蓝牙。";
        if (kind === "adapter")
            return "确认蓝牙硬件、rfkill 和 bluetooth.service 状态。";
        if (kind === "blocked")
            return "需要在硬件开关或 rfkill 中解除阻止。";
        if (kind === "off")
            return "打开蓝牙后可以扫描、配对和连接设备。";
        if (kind === "empty")
            return page.discoveryRequested
                ? "正在扫描附近设备。"
                : "开启扫描后，附近设备会显示在这里。";
        return "";
    }

    function statusIcon(kind) {
        if (kind === "bluez")
            return "\ue1a7";
        if (kind === "airplane")
            return "\ue539";
        if (kind === "blocked")
            return "\ue14b";
        if (kind === "empty")
            return "\ue8b6";
        return "\ue1a7";
    }

    function statusButtonLabel(kind) {
        if (kind === "bluez")
            return "重新检测";
        if (kind === "airplane")
            return "关闭飞行模式";
        if (kind === "off")
            return "打开蓝牙";
        if (kind === "empty")
            return page.discoveryRequested ? "停止扫描" : "开始扫描";
        return "";
    }

    function runStatusAction(kind) {
        if (!page.controlsService)
            return;
        if (kind === "bluez" && page.controlsService.commandRunner) {
            page.controlsService.commandRunner.refreshDependencies();
        } else if (kind === "airplane") {
            page.controlsService.toggleAirplaneMode();
        } else if (kind === "off") {
            page.controlsService.setBluetoothEnabled(true);
        } else if (kind === "empty") {
            page.controlsService.toggleBluetoothDiscovery(page.discoveryOwner);
        }
    }

    function adapterStateText() {
        if (!page.controlsService)
            return "";
        if (page.controlsService.bluetoothAdapterBlocked)
            return "已阻止";
        var state = Number(page.controlsService.bluetoothAdapterState);
        if (state === 2)
            return "正在开启";
        if (state === 3)
            return "正在关闭";
        return page.bluetoothOn ? "已开启" : "已关闭";
    }

    function bluetoothPowerDetail() {
        var kind = page.statusKind();
        if (kind === "bluez")
            return "BlueZ 不可用";
        if (kind === "airplane")
            return "飞行模式已开启";
        if (kind === "adapter")
            return "未检测到蓝牙硬件";
        if (kind === "blocked")
            return "已被阻止";
        if (!page.bluetoothOn)
            return "已关闭";
        if (page.controlsService && page.controlsService.bluetoothConnectedCount > 0)
            return page.controlsService.bluetoothConnectedCount + " 台设备已连接";
        return "已开启";
    }

    ColumnLayout {
        id: settingsColumn

        width: parent.width
        spacing: 10

        Controls.TahoeSection {
            theme: page.theme
            title: "蓝牙"
            subtitle: "适配器、扫描和设备连接"

            Controls.TahoeListRow {
                theme: page.theme
                label: "蓝牙"
                detail: page.bluetoothPowerDetail()
                iconCode: "\ue1a7"
                checkable: true
                checked: page.bluetoothOn
                enabled: page.hasControls && page.backendReady && page.adapterAvailable && !page.airplaneMode && !page.adapterBlocked
                onToggled: function(checked) {
                    if (page.controlsService)
                        page.controlsService.setBluetoothEnabled(checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "适配器"
                detail: page.controlsService && page.controlsService.bluetoothAdapterName.length > 0
                    ? page.controlsService.bluetoothAdapterName + " · " + page.adapterStateText()
                    : page.adapterStateText()
                iconCode: "\ue1a7"
                visible: page.adapterAvailable
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "扫描附近设备"
                detail: page.discoveryRequested ? "正在扫描" : "未扫描"
                iconCode: "\ue8b6"
                checkable: true
                checked: page.discoveryRequested
                enabled: page.hasControls && page.backendReady && page.adapterAvailable && page.bluetoothOn && !page.airplaneMode
                onToggled: function(checked) {
                    if (page.controlsService)
                        page.controlsService.setBluetoothDiscoveryActive(page.discoveryOwner, checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "允许被发现"
                detail: "让附近设备看到这台电脑"
                iconCode: "\ue8f4"
                checkable: true
                checked: page.controlsService && page.controlsService.bluetoothDiscoverable
                enabled: page.hasControls && page.backendReady && page.adapterAvailable && page.bluetoothOn && !page.airplaneMode
                onToggled: function(checked) {
                    if (page.controlsService)
                        page.controlsService.setBluetoothDiscoverable(checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "接受配对请求"
                detail: "允许设备向这台电脑发起配对"
                iconCode: "\ue7fe"
                checkable: true
                checked: page.controlsService && page.controlsService.bluetoothPairable
                enabled: page.hasControls && page.backendReady && page.adapterAvailable && page.bluetoothOn && !page.airplaneMode
                onToggled: function(checked) {
                    if (page.controlsService)
                        page.controlsService.setBluetoothPairable(checked);
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: page.statusTitle(page.statusKind())
            subtitle: page.statusDetail(page.statusKind())
            visible: page.statusKind().length > 0

            Controls.TahoeListRow {
                theme: page.theme
                label: page.statusTitle(page.statusKind())
                detail: page.statusDetail(page.statusKind())
                iconCode: page.statusIcon(page.statusKind())

                Controls.TahoeButton {
                    theme: page.theme
                    label: page.statusButtonLabel(page.statusKind())
                    visible: label.length > 0
                    onActivated: page.runStatusAction(page.statusKind())
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "已连接"
            subtitle: "当前正在使用的蓝牙设备"
            visible: page.bluetoothOn && page.connectedDevices.length > 0

            Repeater {
                model: page.connectedDevices

                delegate: BluetoothDeviceRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    onConnectRequested: function(entry) { page.controlsService.connectBluetoothDevice(entry); }
                    onDisconnectRequested: function(entry) { page.controlsService.disconnectBluetoothDevice(entry); }
                    onPairRequested: function(entry) { page.controlsService.pairBluetoothDevice(entry); }
                    onCancelPairRequested: function(entry) { page.controlsService.cancelBluetoothPairing(entry); }
                    onForgetRequested: function(entry) { page.controlsService.forgetBluetoothDevice(entry); }
                    onTrustRequested: function(entry, trusted) { page.controlsService.setBluetoothDeviceTrusted(entry, trusted); }
                    onBlockRequested: function(entry, blocked) { page.controlsService.setBluetoothDeviceBlocked(entry, blocked); }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "已配对"
            subtitle: "保存过的蓝牙设备"
            visible: page.bluetoothOn && page.pairedDevices.length > 0

            Repeater {
                model: page.pairedDevices

                delegate: BluetoothDeviceRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    onConnectRequested: function(entry) { page.controlsService.connectBluetoothDevice(entry); }
                    onDisconnectRequested: function(entry) { page.controlsService.disconnectBluetoothDevice(entry); }
                    onPairRequested: function(entry) { page.controlsService.pairBluetoothDevice(entry); }
                    onCancelPairRequested: function(entry) { page.controlsService.cancelBluetoothPairing(entry); }
                    onForgetRequested: function(entry) { page.controlsService.forgetBluetoothDevice(entry); }
                    onTrustRequested: function(entry, trusted) { page.controlsService.setBluetoothDeviceTrusted(entry, trusted); }
                    onBlockRequested: function(entry, blocked) { page.controlsService.setBluetoothDeviceBlocked(entry, blocked); }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "附近设备"
            subtitle: page.discoveryRequested ? "正在扫描" : "开启扫描后显示附近设备"
            visible: page.bluetoothOn && page.nearbyDevices.length > 0

            Repeater {
                model: page.nearbyDevices

                delegate: BluetoothDeviceRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    onConnectRequested: function(entry) { page.controlsService.connectBluetoothDevice(entry); }
                    onDisconnectRequested: function(entry) { page.controlsService.disconnectBluetoothDevice(entry); }
                    onPairRequested: function(entry) { page.controlsService.pairBluetoothDevice(entry); }
                    onCancelPairRequested: function(entry) { page.controlsService.cancelBluetoothPairing(entry); }
                    onForgetRequested: function(entry) { page.controlsService.forgetBluetoothDevice(entry); }
                    onTrustRequested: function(entry, trusted) { page.controlsService.setBluetoothDeviceTrusted(entry, trusted); }
                    onBlockRequested: function(entry, blocked) { page.controlsService.setBluetoothDeviceBlocked(entry, blocked); }
                }
            }
        }
    }

    component BluetoothDeviceRow: Item {
        id: row

        property var theme
        property var entry

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowFillHover: theme ? theme.rowFillHover : "#86ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"
        readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
        readonly property color danger: theme ? theme.danger : "#ff453a"

        signal connectRequested(var entry)
        signal disconnectRequested(var entry)
        signal pairRequested(var entry)
        signal cancelPairRequested(var entry)
        signal forgetRequested(var entry)
        signal trustRequested(var entry, bool trusted)
        signal blockRequested(var entry, bool blocked)

        Layout.fillWidth: true
        Layout.preferredHeight: frame.implicitHeight

        function stateText() {
            if (!row.entry)
                return "";
            if (row.entry.blocked)
                return "已阻止";
            if (row.entry.pairing)
                return "正在配对";
            if (row.entry.state === 3)
                return "正在连接";
            if (row.entry.state === 2)
                return "正在断开";
            if (row.entry.connected)
                return "已连接";
            if (row.entry.paired || row.entry.bonded)
                return "已配对";
            return "附近设备";
        }

        function detailText() {
            if (!row.entry)
                return "";
            var parts = [row.stateText()];
            if (row.entry.batteryAvailable)
                parts.push("电量 " + row.entry.batteryPercent + "%");
            if (row.entry.trusted)
                parts.push("已信任");
            if (row.entry.address.length > 0)
                parts.push(row.entry.address);
            return parts.join(" · ");
        }

        Rectangle {
            id: frame

            width: parent.width
            implicitHeight: content.implicitHeight + 14
            radius: 8
            color: row.entry && row.entry.connected ? row.rowFillHover : row.rowFill
            border.color: row.rowStroke
            border.width: 1

            ColumnLayout {
                id: content

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    TahoeSymbol {
                        Layout.preferredWidth: 22
                        Layout.alignment: Qt.AlignVCenter
                        name: "\ue1a7"
                        color: row.entry && row.entry.connected ? row.accentBlue : row.textPrimary
                        size: 18
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: row.entry ? row.entry.name : ""
                            color: row.textPrimary
                            font.pixelSize: 12
                            font.weight: row.entry && row.entry.connected ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: row.detailText()
                            color: row.textSecondary
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        label: "断开"
                        iconCode: "\ue14c"
                        visible: !!(row.entry && row.entry.connected)
                        enabled: !!row.entry && !row.entry.stateChanging
                        onActivated: row.disconnectRequested(row.entry)
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        label: row.entry && row.entry.stateChanging ? "连接中" : "连接"
                        iconCode: "\ue1a7"
                        visible: !!(row.entry && !row.entry.connected && (row.entry.paired || row.entry.bonded))
                        enabled: !!row.entry && !row.entry.stateChanging && !row.entry.blocked
                        onActivated: row.connectRequested(row.entry)
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        label: row.entry && row.entry.pairing ? "取消" : "配对"
                        iconCode: "\ue7fe"
                        visible: !!(row.entry && !row.entry.connected && !row.entry.paired && !row.entry.bonded)
                        enabled: !!row.entry && !row.entry.blocked
                        onActivated: {
                            if (row.entry && row.entry.pairing)
                                row.cancelPairRequested(row.entry);
                            else
                                row.pairRequested(row.entry);
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    Item {
                        Layout.fillWidth: true
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        label: row.entry && row.entry.trusted ? "取消信任" : "信任"
                        iconCode: "\ue8e8"
                        visible: !!(row.entry && (row.entry.connected || row.entry.paired || row.entry.bonded))
                        enabled: !!row.entry && !row.entry.stateChanging
                        active: !!(row.entry && row.entry.trusted)
                        onActivated: row.trustRequested(row.entry, !(row.entry && row.entry.trusted))
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        label: row.entry && row.entry.blocked ? "解除阻止" : "阻止"
                        iconCode: "\ue14b"
                        enabled: !!row.entry && !row.entry.stateChanging
                        active: !!(row.entry && row.entry.blocked)
                        onActivated: row.blockRequested(row.entry, !(row.entry && row.entry.blocked))
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        label: "忘记"
                        iconCode: "\ue872"
                        visible: !!(row.entry && (row.entry.paired || row.entry.bonded))
                        enabled: !!row.entry && !row.entry.stateChanging
                        onActivated: row.forgetRequested(row.entry)
                    }
                }
            }
        }
    }
}
