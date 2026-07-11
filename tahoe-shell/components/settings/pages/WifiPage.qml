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
    property string expandedSsid: ""

    readonly property var networks: controlsService ? controlsService.wifiNetworks : []
    readonly property bool hasControls: !!controlsService
    readonly property bool networkReady: hasControls && controlsService.networkManagerAvailable
    readonly property bool adapterAvailable: hasControls && !!controlsService.wifiDevice
    readonly property bool wifiOn: hasControls && controlsService.wifiEnabled
    readonly property bool airplaneMode: hasControls && controlsService.airplaneMode
    readonly property bool connected: hasControls && controlsService.wifiConnected
    readonly property var knownProfiles: controlsService ? controlsService.knownWifiProfiles : []
    readonly property bool hotspotActive: hasControls && controlsService.hotspotActive

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color textMuted: theme ? theme.textMuted : "#5f6870"
    readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
    readonly property color rowFillHover: theme ? theme.rowFillHover : "#86ffffff"
    readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"
    readonly property color fieldFill: theme ? theme.fieldFill : "#3fffffff"
    readonly property color fieldStroke: theme ? theme.fieldStroke : "#4cffffff"
    readonly property color fieldStrokeFocus: theme ? theme.fieldStrokeFocus : "#007ff7"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
    readonly property color danger: theme ? theme.danger : "#ff453a"

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function statusKind() {
        if (!page.hasControls)
            return "service";
        if (!page.networkReady)
            return "networkmanager";
        if (page.airplaneMode)
            return "airplane";
        if (!page.adapterAvailable)
            return "adapter";
        if (!page.wifiOn)
            return "off";
        if (page.networks.length === 0)
            return "empty";
        return "";
    }

    function statusTitle(kind) {
        if (kind === "service")
            return "控制服务不可用";
        if (kind === "networkmanager")
            return "NetworkManager 不可用";
        if (kind === "airplane")
            return "飞行模式已开启";
        if (kind === "adapter")
            return "未检测到 Wi-Fi 适配器";
        if (kind === "off")
            return "Wi-Fi 已关闭";
        if (kind === "empty")
            return "未发现网络";
        return "";
    }

    function statusDetail(kind) {
        if (kind === "service")
            return "设置页没有连接到 Controls 服务。";
        if (kind === "networkmanager") {
            var detail = page.controlsService ? String(page.controlsService.networkErrorText || "").trim() : "";
            return detail.length > 0 ? detail : "NetworkManager 未运行或 nmcli 缺失。";
        }
        if (kind === "airplane")
            return "关闭飞行模式后可以重新启用无线网络。";
        if (kind === "adapter")
            return "确认无线网卡、驱动、rfkill 和 NetworkManager 状态。";
        if (kind === "off")
            return "打开 Wi-Fi 后会扫描附近网络。";
        if (kind === "empty")
            return "附近没有可见网络，或扫描结果尚未返回。";
        return "";
    }

    function statusIcon(kind) {
        if (kind === "networkmanager")
            return "\ue1bd";
        if (kind === "airplane")
            return "\ue539";
        if (kind === "adapter")
            return "\ue63e";
        if (kind === "off")
            return "\ue63e";
        if (kind === "empty")
            return "\ue8b6";
        return "\ue88e";
    }

    function statusButtonLabel(kind) {
        if (kind === "networkmanager")
            return "重新检测";
        if (kind === "airplane")
            return "关闭飞行模式";
        if (kind === "off")
            return "打开 Wi-Fi";
        if (kind === "empty")
            return "重新扫描";
        return "";
    }

    function runStatusAction(kind) {
        if (!page.controlsService)
            return;
        if (kind === "networkmanager" && page.controlsService.commandRunner) {
            page.controlsService.commandRunner.refreshDependencies();
        } else if (kind === "airplane") {
            page.controlsService.toggleAirplaneMode();
        } else if (kind === "off") {
            page.controlsService.setWifiEnabled(true);
        } else if (kind === "empty") {
            page.controlsService.rescanWifi();
        }
    }

    function wifiPowerDetail() {
        var kind = page.statusKind();
        if (kind === "networkmanager")
            return "NetworkManager 不可用";
        if (kind === "airplane")
            return "飞行模式已开启";
        if (kind === "adapter")
            return "未检测到无线适配器";
        if (!page.wifiOn)
            return "已关闭";
        if (page.connected && page.controlsService)
            return "已连接 " + page.controlsService.wifiName;
        return "已开启";
    }

    function currentNetworkDetail() {
        if (!page.controlsService)
            return "";
        var signal = page.controlsService.wifiSignalPercent;
        return signal > 0 ? signal + "% 信号强度" : "已连接";
    }

    ColumnLayout {
        id: settingsColumn

        width: parent.width
        spacing: 10

        Controls.TahoeSection {
            theme: page.theme
            title: "Wi-Fi"
            subtitle: "无线网络、飞行模式和可见网络"

            Controls.TahoeListRow {
                theme: page.theme
                label: "Wi-Fi"
                detail: page.wifiPowerDetail()
                iconCode: "\ue63e"
                checkable: true
                checked: page.wifiOn
                enabled: page.hasControls && page.networkReady && page.adapterAvailable && !page.airplaneMode
                onToggled: function(checked) {
                    if (page.controlsService)
                        page.controlsService.setWifiEnabled(checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "飞行模式"
                detail: "关闭 Wi-Fi 和蓝牙无线电"
                iconCode: "\ue539"
                checkable: true
                checked: page.airplaneMode
                enabled: page.hasControls
                onToggled: {
                    if (page.controlsService)
                        page.controlsService.toggleAirplaneMode();
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "当前网络"
                detail: page.currentNetworkDetail()
                iconCode: "\ue5ca"
                visible: page.connected

                Controls.TahoeButton {
                    theme: page.theme
                    label: "断开"
                    iconCode: "\ue14c"
                    onActivated: {
                        if (page.controlsService)
                            page.controlsService.disconnectWifi();
                    }
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
            title: "可见网络"
            subtitle: "按已连接、已保存和信号强度排序"
            visible: page.statusKind().length === 0

            Controls.TahoeListRow {
                theme: page.theme
                label: "扫描"
                detail: page.networks.length + " 个可见网络"
                iconCode: "\ue8b6"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "重新扫描"
                    iconCode: "\ue5d5"
                    onActivated: {
                        if (page.controlsService)
                            page.controlsService.rescanWifi();
                    }
                }
            }

            Repeater {
                model: page.networks

                delegate: WifiNetworkRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    expanded: page.expandedSsid === modelData.name
                    onExpandRequested: function(ssid) {
                        page.expandedSsid = page.expandedSsid === ssid ? "" : ssid;
                    }
                    onConnectRequested: function(entry, psk) {
                        if (page.controlsService)
                            page.controlsService.connectWifi(entry, psk);
                        page.expandedSsid = "";
                    }
                    onDisconnectRequested: {
                        if (page.controlsService)
                            page.controlsService.disconnectWifi();
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "隐藏网络"
            subtitle: "连接未广播 SSID 的 Wi-Fi"
            visible: page.hasControls && page.networkReady && page.adapterAvailable && page.wifiOn && !page.airplaneMode

            Controls.TahoeListRow {
                theme: page.theme
                label: "SSID"
                detail: "输入隐藏网络名称"
                iconCode: "\ue63e"

                Controls.TahoeTextField {
                    id: hiddenSsidField
                    theme: page.theme
                    Layout.preferredWidth: 190
                }

                Controls.TahoeTextField {
                    id: hiddenPasswordField
                    theme: page.theme
                    Layout.preferredWidth: 150
                }

                Controls.TahoeButton {
                    theme: page.theme
                    label: "连接"
                    iconCode: "\ue63e"
                    onActivated: {
                        if (page.controlsService)
                            page.controlsService.connectHiddenWifi(hiddenSsidField.text, hiddenPasswordField.text);
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "QR payload"
                detail: page.controlsService
                    ? page.controlsService.wifiQrPayload(hiddenSsidField.text, hiddenPasswordField.text, hiddenPasswordField.text.length > 0, true)
                    : ""
                iconCode: "\uef6b"
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "已知网络"
            subtitle: page.controlsService
                ? page.controlsService.knownWifiDetail
                : "控制服务不可用"
            visible: page.hasControls && page.networkReady

            Controls.TahoeListRow {
                theme: page.theme
                label: "已保存网络"
                detail: page.knownProfiles.length === 0
                    ? "没有 NetworkManager Wi-Fi profile"
                    : page.knownProfiles.length + " 个 Wi-Fi profile"
                iconCode: "\ue8b8"

                Controls.TahoeButton {
                    theme: page.theme
                    label: page.controlsService && page.controlsService.knownWifiRefreshing ? "刷新中" : "刷新"
                    iconCode: "\ue5d5"
                    enabled: !!page.controlsService && !page.controlsService.knownWifiRefreshing
                    onActivated: {
                        if (page.controlsService)
                            page.controlsService.refreshKnownWifiProfiles();
                    }
                }
            }

            Repeater {
                model: page.knownProfiles

                delegate: KnownWifiRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    onForgetRequested: function(entry) {
                        if (page.controlsService)
                            page.controlsService.forgetWifiProfile(entry);
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "热点与分享"
            subtitle: "NetworkManager 热点和 Wi-Fi QR payload"
            visible: page.hasControls && page.networkReady && page.adapterAvailable && page.wifiOn && !page.airplaneMode

            Controls.TahoeListRow {
                theme: page.theme
                label: "热点"
                detail: page.hotspotActive
                    ? "已开启 " + (page.controlsService ? page.controlsService.hotspotName : "")
                    : "使用当前无线适配器创建热点"
                iconCode: "\ue63e"
                checkable: true
                checked: page.hotspotActive
                onToggled: function(checked) {
                    if (page.controlsService)
                        page.controlsService.setWifiHotspotEnabled(checked, hotspotSsidField.text, hotspotPasswordField.text);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "热点参数"
                detail: "密码少于 8 位时 NetworkManager 可能拒绝开启热点"
                iconCode: "\ue897"

                Controls.TahoeTextField {
                    id: hotspotSsidField
                    theme: page.theme
                    text: "Tahoe Hotspot"
                    Layout.preferredWidth: 170
                }

                Controls.TahoeTextField {
                    id: hotspotPasswordField
                    theme: page.theme
                    Layout.preferredWidth: 150
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "当前网络 QR"
                detail: page.controlsService
                    ? page.controlsService.wifiQrPayload(page.controlsService.currentWifiSsid(), sharePasswordField.text, sharePasswordField.text.length > 0, false)
                    : ""
                iconCode: "\uef6b"
                visible: page.connected

                Controls.TahoeTextField {
                    id: sharePasswordField
                    theme: page.theme
                    Layout.preferredWidth: 160
                }
            }
        }
    }

    component KnownWifiRow: Item {
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

        signal forgetRequested(var entry)

        Layout.fillWidth: true
        Layout.preferredHeight: 50

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: row.entry && row.entry.active ? row.rowFillHover : row.rowFill
            border.color: row.rowStroke
            border.width: 1
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            TahoeSymbol {
                Layout.preferredWidth: 22
                Layout.alignment: Qt.AlignVCenter
                name: row.entry && row.entry.active ? "\ue5ca" : "\ue63e"
                color: row.entry && row.entry.active ? row.accentBlue : row.textPrimary
                size: 18
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.name : ""
                    color: row.textPrimary
                    font.pixelSize: 12
                    font.weight: row.entry && row.entry.active ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: row.entry
                        ? row.entry.uuid + " · " + (row.entry.autoconnect ? "自动连接" : "手动连接")
                        : ""
                    color: row.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Controls.TahoeButton {
                theme: row.theme
                label: "忘记"
                iconCode: "\ue872"
                onActivated: row.forgetRequested(row.entry)
            }
        }
    }

    component WifiNetworkRow: Item {
        id: row

        property var theme
        property var entry
        property bool expanded: false

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color textMuted: theme ? theme.textMuted : "#5f6870"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowFillHover: theme ? theme.rowFillHover : "#86ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"
        readonly property color fieldFill: theme ? theme.fieldFill : "#3fffffff"
        readonly property color fieldStroke: theme ? theme.fieldStroke : "#4cffffff"
        readonly property color fieldStrokeFocus: theme ? theme.fieldStrokeFocus : "#007ff7"
        readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
        readonly property bool canConnectDirectly: !!entry && !entry.connected && (!entry.secured || entry.known)
        readonly property bool canEnterPassword: !!entry && !entry.connected && entry.secured && !entry.known && entry.pskSupported !== false

        signal expandRequested(string ssid)
        signal connectRequested(var entry, string psk)
        signal disconnectRequested()

        Layout.fillWidth: true
        Layout.preferredHeight: frame.implicitHeight

        function detailText() {
            if (!row.entry)
                return "";
            var parts = [];
            if (row.entry.connected)
                parts.push("已连接");
            else if (row.entry.known)
                parts.push("已保存");
            if (row.entry.secured)
                parts.push(row.entry.pskSupported === false ? "需要高级认证" : "需要密码");
            else
                parts.push("开放网络");
            if (row.entry.signalPercent > 0)
                parts.push(row.entry.signalPercent + "%");
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
                        name: row.entry && row.entry.connected ? "\ue5ca" : (row.entry && row.entry.secured ? "\ue897" : "\ue63e")
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
                        enabled: !row.entry || !row.entry.stateChanging
                        onActivated: row.disconnectRequested()
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        label: row.entry && row.entry.stateChanging ? "连接中" : "连接"
                        iconCode: "\ue63e"
                        visible: row.canConnectDirectly
                        enabled: !!row.entry && !row.entry.stateChanging
                        onActivated: row.connectRequested(row.entry, "")
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        label: "输入密码"
                        iconCode: "\ue897"
                        visible: row.canEnterPassword
                        enabled: !!row.entry && !row.entry.stateChanging
                        onActivated: row.expandRequested(row.entry ? row.entry.name : "")
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: row.expanded ? 40 : 0
                    visible: row.expanded
                    radius: 8
                    color: row.fieldFill
                    border.color: passwordInput.activeFocus ? row.fieldStrokeFocus : row.fieldStroke
                    border.width: passwordInput.activeFocus ? 2 : 1
                    clip: true

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: 8

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Text {
                                anchors.fill: parent
                                text: "密码"
                                color: row.textMuted
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                                visible: passwordInput.text.length === 0
                            }

                            TextInput {
                                id: passwordInput

                                anchors.fill: parent
                                color: row.textPrimary
                                selectionColor: row.accentBlue
                                selectedTextColor: "#ffffff"
                                font.pixelSize: 12
                                echoMode: TextInput.Password
                                focus: row.expanded
                                clip: true
                                verticalAlignment: TextInput.AlignVCenter
                                Keys.onReturnPressed: {
                                    row.connectRequested(row.entry, passwordInput.text);
                                    passwordInput.text = "";
                                }
                                Keys.onEscapePressed: row.expandRequested(row.entry ? row.entry.name : "")
                            }
                        }

                        Controls.TahoeButton {
                            theme: row.theme
                            label: "连接"
                            primary: true
                            onActivated: {
                                row.connectRequested(row.entry, passwordInput.text);
                                passwordInput.text = "";
                            }
                        }
                    }
                }
            }
        }
    }
}
