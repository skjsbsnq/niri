pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls
import "../.."

Flickable {
    id: page

    property var panel
    property var theme
    property var networkSettingsService
    property string expandedWiredUuid: ""
    property string expandedVpnUuid: ""

    readonly property bool hasService: !!networkSettingsService
    readonly property bool networkReady: hasService && networkSettingsService.networkManagerAvailable
    readonly property var wiredEntries: hasService ? networkSettingsService.wiredEntries : []
    readonly property var wiredProfiles: hasService ? networkSettingsService.wiredProfiles : []
    readonly property var vpnProfiles: hasService ? networkSettingsService.vpnProfiles : []
    readonly property var proxySettings: hasService ? networkSettingsService.proxySettings : ({})
    readonly property bool vpnRefreshing: hasService && networkSettingsService.vpnRefreshing

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
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

    function activeVpnCount() {
        var count = 0;
        for (var i = 0; i < page.vpnProfiles.length; i++) {
            if (page.vpnProfiles[i] && page.vpnProfiles[i].active)
                count += 1;
        }
        return count;
    }

    function statusKind() {
        if (!page.hasService)
            return "service";
        if (!page.networkReady)
            return "networkmanager";
        return "";
    }

    function statusTitle(kind) {
        if (kind === "service")
            return "网络设置服务不可用";
        if (kind === "networkmanager")
            return "NetworkManager 不可用";
        return "";
    }

    function statusDetail(kind) {
        if (kind === "service")
            return "设置页没有连接到 NetworkSettings 服务。";
        if (kind === "networkmanager") {
            var detail = page.networkSettingsService ? String(page.networkSettingsService.networkErrorText || "").trim() : "";
            return detail.length > 0 ? detail : "NetworkManager 未运行或 nmcli 缺失。";
        }
        return "";
    }

    function runStatusAction(kind) {
        if (!page.networkSettingsService)
            return;
        if (page.networkSettingsService.commandRunner)
            page.networkSettingsService.commandRunner.refreshDependencies();
        page.networkSettingsService.refresh();
    }

    function networkSummaryDetail() {
        if (!page.hasService)
            return "服务不可用";
        if (!page.networkReady)
            return page.statusDetail("networkmanager");

        var parts = [];
        if (page.wiredEntries.length > 0)
            parts.push(page.wiredEntries.length + " 个有线设备");
        else
            parts.push("未检测到有线设备");

        var active = page.activeVpnCount();
        if (active > 0)
            parts.push(active + " 个 VPN 已连接");
        else if (page.vpnProfiles.length > 0)
            parts.push(page.vpnProfiles.length + " 个 VPN profile");
        else
            parts.push("无 VPN profile");

        return parts.join(" · ");
    }

    ColumnLayout {
        id: settingsColumn

        width: parent.width
        spacing: 10

        Controls.TahoeSection {
            theme: page.theme
            title: "网络"
            subtitle: "有线网络、VPN 和代理"

            Controls.TahoeListRow {
                theme: page.theme
                label: "NetworkManager"
                detail: page.networkSummaryDetail()
                iconCode: "\ue1bd"

                Controls.TahoeButton {
                    theme: page.theme
                    label: page.vpnRefreshing ? "刷新中" : "刷新"
                    iconCode: "\ue5d5"
                    enabled: page.hasService && !page.vpnRefreshing
                    onActivated: {
                        if (page.networkSettingsService)
                            page.networkSettingsService.refresh();
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
                iconCode: "\ue1bd"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "重新检测"
                    iconCode: "\ue5d5"
                    onActivated: page.runStatusAction(page.statusKind())
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "有线网络"
            subtitle: "设备、link、连接状态和速率"
            visible: page.networkReady

            Controls.TahoeListRow {
                theme: page.theme
                label: "有线设备"
                detail: "未检测到 Ethernet 设备"
                iconCode: "\ue1bd"
                visible: page.wiredEntries.length === 0
            }

            Repeater {
                model: page.wiredEntries

                delegate: WiredDeviceRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    onConnectRequested: function(entry) {
                        if (page.networkSettingsService)
                            page.networkSettingsService.connectWired(entry);
                    }
                    onDisconnectRequested: function(entry) {
                        if (page.networkSettingsService)
                            page.networkSettingsService.disconnectWired(entry);
                    }
                    onAutoconnectRequested: function(entry, enabled) {
                        if (page.networkSettingsService)
                            page.networkSettingsService.setWiredAutoconnect(entry, enabled);
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "有线连接配置"
            subtitle: "NetworkManager profile 的 IPv4、IPv6、网关和 DNS"
            visible: page.networkReady

            Controls.TahoeListRow {
                theme: page.theme
                label: "有线 profiles"
                detail: page.wiredProfiles.length === 0
                    ? "没有 Ethernet profile"
                    : page.wiredProfiles.length + " 个 Ethernet profile"
                iconCode: "\ue1bd"
                visible: page.wiredProfiles.length === 0
            }

            Repeater {
                model: page.wiredProfiles

                delegate: WiredProfileRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    expanded: page.expandedWiredUuid === modelData.uuid
                    onToggleExpanded: function(uuid) {
                        page.expandedWiredUuid = page.expandedWiredUuid === uuid ? "" : uuid;
                    }
                    onSaveRequested: function(entry, values) {
                        if (page.networkSettingsService)
                            page.networkSettingsService.saveWiredProfile(entry, values);
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "VPN"
            subtitle: "NetworkManager VPN 和 WireGuard profiles"
            visible: page.networkReady

            Controls.TahoeListRow {
                theme: page.theme
                label: "VPN Profiles"
                detail: page.vpnProfiles.length === 0
                    ? "尚未配置 VPN"
                    : page.activeVpnCount() + " 个已连接，" + page.vpnProfiles.length + " 个 profile"
                iconCode: "\ue897"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "新增"
                    iconCode: "\ue145"
                    onActivated: {
                        if (page.networkSettingsService)
                            page.networkSettingsService.openVpnEditor(null);
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "导入 VPN"
                detail: "输入 openvpn/wireguard 和配置文件路径"
                iconCode: "\ue2c4"

                Controls.TahoeTextField {
                    id: vpnImportTypeField
                    theme: page.theme
                    text: "openvpn"
                    Layout.preferredWidth: 110
                }

                Controls.TahoeTextField {
                    id: vpnImportPathField
                    theme: page.theme
                    Layout.preferredWidth: 250
                }

                Controls.TahoeButton {
                    theme: page.theme
                    label: "导入"
                    iconCode: "\ue2c4"
                    onActivated: {
                        if (page.networkSettingsService)
                            page.networkSettingsService.importVpn(vpnImportTypeField.text, vpnImportPathField.text);
                    }
                }
            }

            Repeater {
                model: page.vpnProfiles

                delegate: VpnProfileRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    expanded: page.expandedVpnUuid === modelData.uuid
                    onToggleRequested: function(entry, enabled) {
                        if (page.networkSettingsService)
                            page.networkSettingsService.setVpnEnabled(entry, enabled);
                    }
                    onEditRequested: function(entry) {
                        if (entry)
                            page.expandedVpnUuid = page.expandedVpnUuid === entry.uuid ? "" : entry.uuid;
                    }
                    onSaveRequested: function(entry, name, autoconnect) {
                        if (page.networkSettingsService)
                            page.networkSettingsService.saveVpn(entry, name, autoconnect);
                    }
                    onExternalEditRequested: function(entry) {
                        if (page.networkSettingsService)
                            page.networkSettingsService.openVpnEditor(entry);
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "代理"
            subtitle: "系统代理配置"
            visible: page.networkReady

            ProxyEditor {
                Layout.fillWidth: true
                theme: page.theme
                settings: page.proxySettings
                onSaveRequested: function(settings) {
                    if (page.networkSettingsService)
                        page.networkSettingsService.saveProxy(settings);
                }
            }
        }
    }

    component WiredProfileRow: Item {
        id: row

        property var theme
        property var entry
        property bool expanded: false

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowFillHover: theme ? theme.rowFillHover : "#86ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"
        readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"

        signal toggleExpanded(string uuid)
        signal saveRequested(var entry, var values)

        Layout.fillWidth: true
        Layout.preferredHeight: frame.implicitHeight

        function detailText() {
            if (!row.entry)
                return "";
            var parts = [];
            parts.push(row.entry.active ? "已连接" : "未连接");
            parts.push(row.entry.autoconnect ? "自动连接" : "手动连接");
            parts.push("IPv4 " + row.entry.ipv4Method);
            parts.push("IPv6 " + row.entry.ipv6Method);
            return parts.join(" · ");
        }

        function saveValues() {
            row.saveRequested(row.entry, {
                "ipv4Method": ipv4MethodField.text,
                "ipv4Addresses": ipv4AddressesField.text,
                "ipv4Gateway": ipv4GatewayField.text,
                "ipv4Dns": ipv4DnsField.text,
                "ipv6Method": ipv6MethodField.text,
                "ipv6Addresses": ipv6AddressesField.text,
                "ipv6Gateway": ipv6GatewayField.text,
                "ipv6Dns": ipv6DnsField.text
            });
        }

        Rectangle {
            id: frame

            width: parent.width
            implicitHeight: content.implicitHeight + 14
            radius: 8
            color: row.expanded ? row.rowFillHover : row.rowFill
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
                        name: "\ue1bd"
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
                            text: row.detailText()
                            color: row.textSecondary
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        label: row.expanded ? "收起" : "编辑"
                        iconCode: row.expanded ? "\ue5ce" : "\ue3c9"
                        onActivated: row.toggleExpanded(row.entry ? row.entry.uuid : "")
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 7
                    visible: row.expanded

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Controls.TahoeTextField { id: ipv4MethodField; theme: row.theme; text: row.entry ? row.entry.ipv4Method : "auto"; Layout.preferredWidth: 90 }
                        Controls.TahoeTextField { id: ipv4AddressesField; theme: row.theme; text: row.entry ? row.entry.ipv4Addresses : ""; Layout.fillWidth: true }
                        Controls.TahoeTextField { id: ipv4GatewayField; theme: row.theme; text: row.entry ? row.entry.ipv4Gateway : ""; Layout.preferredWidth: 130 }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Controls.TahoeTextField { id: ipv4DnsField; theme: row.theme; text: row.entry ? row.entry.ipv4Dns : ""; Layout.fillWidth: true }
                        Controls.TahoeTextField { id: ipv6MethodField; theme: row.theme; text: row.entry ? row.entry.ipv6Method : "auto"; Layout.preferredWidth: 90 }
                        Controls.TahoeTextField { id: ipv6AddressesField; theme: row.theme; text: row.entry ? row.entry.ipv6Addresses : ""; Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Controls.TahoeTextField { id: ipv6GatewayField; theme: row.theme; text: row.entry ? row.entry.ipv6Gateway : ""; Layout.fillWidth: true }
                        Controls.TahoeTextField { id: ipv6DnsField; theme: row.theme; text: row.entry ? row.entry.ipv6Dns : ""; Layout.fillWidth: true }
                        Controls.TahoeButton {
                            theme: row.theme
                            label: "保存"
                            iconCode: "\ue161"
                            primary: true
                            onActivated: row.saveValues()
                        }
                    }
                }
            }
        }
    }

    component WiredDeviceRow: Item {
        id: row

        property var theme
        property var entry

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowFillHover: theme ? theme.rowFillHover : "#86ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"
        readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"

        signal connectRequested(var entry)
        signal disconnectRequested(var entry)
        signal autoconnectRequested(var entry, bool enabled)

        Layout.fillWidth: true
        Layout.preferredHeight: frame.implicitHeight

        function detailText() {
            if (!row.entry)
                return "";
            var parts = [];
            parts.push(row.entry.hasLink ? "Link 已连接" : "未插入网线");
            parts.push(row.entry.stateText);
            if (row.entry.linkSpeed > 0)
                parts.push(row.entry.linkSpeed + " Mb/s");
            if (row.entry.networkName.length > 0)
                parts.push(row.entry.networkName);
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
                        name: "\ue1bd"
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
                        iconCode: "\ue1bd"
                        visible: !!(row.entry && !row.entry.connected)
                        enabled: !!(row.entry && row.entry.hasLink && !row.entry.stateChanging && row.entry.nmManaged)
                        onActivated: row.connectRequested(row.entry)
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
                        label: row.entry && row.entry.autoconnect ? "自动连接" : "手动连接"
                        iconCode: "\ue863"
                        active: !!(row.entry && row.entry.autoconnect)
                        enabled: !!(row.entry && row.entry.nmManaged)
                        onActivated: row.autoconnectRequested(row.entry, !(row.entry && row.entry.autoconnect))
                    }
                }
            }
        }
    }

    component VpnProfileRow: Item {
        id: row

        property var theme
        property var entry
        property bool expanded: false

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowFillHover: theme ? theme.rowFillHover : "#86ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"
        readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"

        signal toggleRequested(var entry, bool enabled)
        signal editRequested(var entry)
        signal saveRequested(var entry, string name, bool autoconnect)
        signal externalEditRequested(var entry)

        Layout.fillWidth: true
        Layout.preferredHeight: frame.implicitHeight

        function detailText() {
            if (!row.entry)
                return "";
            var parts = [];
            parts.push(row.entry.active ? "已连接" : "未连接");
            if (row.entry.type.length > 0)
                parts.push(row.entry.type === "wireguard" ? "WireGuard" : "VPN");
            if (row.entry.device.length > 0 && row.entry.device !== "--")
                parts.push(row.entry.device);
            return parts.join(" · ");
        }

        Rectangle {
            id: frame

            width: parent.width
            implicitHeight: content.implicitHeight + 14
            radius: 8
            color: row.entry && row.entry.active ? row.rowFillHover : row.rowFill
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
                        name: "\ue897"
                        color: row.entry && row.entry.active ? row.accentBlue : row.textPrimary
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
                            font.weight: row.entry && row.entry.active ? Font.DemiBold : Font.Normal
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

                    Item {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 30
                        Layout.alignment: Qt.AlignVCenter

                        Controls.TahoeSwitch {
                            anchors.centerIn: parent
                            theme: row.theme
                            checked: !!(row.entry && row.entry.active)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: row.toggleRequested(row.entry, !(row.entry && row.entry.active))
                        }
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        iconOnly: true
                        iconCode: row.expanded ? "\ue5ce" : "\ue8b8"
                        onActivated: row.editRequested(row.entry)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7
                    visible: row.expanded

                    Controls.TahoeTextField {
                        id: vpnNameField
                        theme: row.theme
                        text: row.entry ? row.entry.name : ""
                        Layout.fillWidth: true
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        label: row.entry && row.entry.autoconnect ? "自动连接" : "手动连接"
                        iconCode: "\ue863"
                        active: !!(row.entry && row.entry.autoconnect)
                        onActivated: row.saveRequested(row.entry, vpnNameField.text, !(row.entry && row.entry.autoconnect))
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        label: "保存"
                        iconCode: "\ue161"
                        primary: true
                        onActivated: row.saveRequested(row.entry, vpnNameField.text, row.entry && row.entry.autoconnect)
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        label: "高级"
                        iconCode: "\ue8b8"
                        onActivated: row.externalEditRequested(row.entry)
                    }
                }
            }
        }
    }

    component ProxyEditor: Item {
        id: editor

        property var theme
        property var settings

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"

        signal saveRequested(var settings)

        Layout.fillWidth: true
        Layout.preferredHeight: frame.implicitHeight

        function saveValues() {
            editor.saveRequested({
                "mode": modeField.text,
                "autoconfigUrl": autoUrlField.text,
                "httpHost": httpHostField.text,
                "httpPort": httpPortField.text,
                "httpsHost": httpsHostField.text,
                "httpsPort": httpsPortField.text,
                "socksHost": socksHostField.text,
                "socksPort": socksPortField.text
            });
        }

        Rectangle {
            id: frame

            width: parent.width
            implicitHeight: content.implicitHeight + 14
            radius: 8
            color: editor.rowFill
            border.color: editor.rowStroke
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
                        name: "\ue8d3"
                        color: editor.textPrimary
                        size: 18
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: "代理"
                            color: editor.textPrimary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: editor.settings && editor.settings.status === "ok"
                                ? "模式 " + editor.settings.mode
                                : "gsettings 代理 schema 不可用"
                            color: editor.textSecondary
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    Controls.TahoeButton {
                        theme: editor.theme
                        label: "保存"
                        iconCode: "\ue161"
                        primary: true
                        enabled: editor.settings && editor.settings.status === "ok"
                        onActivated: editor.saveValues()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    Controls.TahoeTextField { id: modeField; theme: editor.theme; text: editor.settings ? editor.settings.mode : "none"; Layout.preferredWidth: 90 }
                    Controls.TahoeTextField { id: autoUrlField; theme: editor.theme; text: editor.settings ? editor.settings.autoconfigUrl : ""; Layout.fillWidth: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    Controls.TahoeTextField { id: httpHostField; theme: editor.theme; text: editor.settings ? editor.settings.httpHost : ""; Layout.fillWidth: true }
                    Controls.TahoeTextField { id: httpPortField; theme: editor.theme; text: editor.settings ? editor.settings.httpPort : "0"; Layout.preferredWidth: 80 }
                    Controls.TahoeTextField { id: httpsHostField; theme: editor.theme; text: editor.settings ? editor.settings.httpsHost : ""; Layout.fillWidth: true }
                    Controls.TahoeTextField { id: httpsPortField; theme: editor.theme; text: editor.settings ? editor.settings.httpsPort : "0"; Layout.preferredWidth: 80 }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    Controls.TahoeTextField { id: socksHostField; theme: editor.theme; text: editor.settings ? editor.settings.socksHost : ""; Layout.fillWidth: true }
                    Controls.TahoeTextField { id: socksPortField; theme: editor.theme; text: editor.settings ? editor.settings.socksPort : "0"; Layout.preferredWidth: 80 }
                }
            }
        }
    }
}
