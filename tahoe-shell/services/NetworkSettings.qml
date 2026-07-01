pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Networking

Item {
    id: root
    visible: false

    property var commandRunner
    property var vpnProfiles: []
    property var wiredProfiles: []
    property var proxySettings: ({
        "status": "unknown",
        "mode": "none",
        "autoconfigUrl": "",
        "httpHost": "",
        "httpPort": "0",
        "httpsHost": "",
        "httpsPort": "0",
        "socksHost": "",
        "socksPort": "0"
    })
    property bool vpnRefreshing: false
    property string networkProbeState: "unknown"
    property string networkProbeDetail: "尚未检测"
    property var lastActionResult: null
    property int revision: 0

    readonly property string dependencyState: root.commandRunner && root.commandRunner.revision > 0
        ? root.commandRunner.dependencyState("network")
        : ""
    readonly property string dependencyDetail: root.commandRunner && root.commandRunner.revision > 0
        ? root.commandRunner.dependencyDetail("network")
        : ""
    readonly property bool networkManagerAvailable: {
        if (root.dependencyState.length > 0)
            return root.commandRunner.dependencyReady("network") && root.networkProbeState !== "missing";
        return root.networkProbeState === "ok";
    }
    readonly property string networkErrorText: {
        if (!root.commandRunner)
            return "CommandRunner 未注入，网络命令不可用。";
        if (root.dependencyState === "missing")
            return root.dependencyDetail.length > 0 ? root.dependencyDetail : "NetworkManager 不可用。";
        if (root.networkProbeState === "missing")
            return root.networkProbeDetail.length > 0 ? root.networkProbeDetail : "NetworkManager 不可用。";
        return "";
    }
    readonly property var wiredDevices: {
        try {
            var devices = Networking.devices;
            if (!devices || !devices.values)
                return [];

            var out = [];
            for (var i = 0; i < devices.values.length; i++) {
                var d = devices.values[i];
                if (!d)
                    continue;
                var typeText = String(d.type || "").toLowerCase();
                if (d.type === DeviceType.Wired || typeText === "wired" || typeText === "ethernet")
                    out.push(d);
            }
            return out;
        } catch (e) {
            return [];
        }
    }
    readonly property var wiredEntries: {
        var out = [];
        var values = root.wiredDevices || [];
        for (var i = 0; i < values.length; i++) {
            var entry = root.wiredEntry(values[i]);
            if (entry)
                out.push(entry);
        }
        out.sort(function(a, b) {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            if (a.hasLink !== b.hasLink)
                return a.hasLink ? -1 : 1;
            return a.name.localeCompare(b.name);
        });
        return out;
    }

    function connectionStateText(state, connected) {
        var value = Number(state);
        if (value === ConnectionState.Connecting)
            return "正在连接";
        if (value === ConnectionState.Connected)
            return "已连接";
        if (value === ConnectionState.Disconnecting)
            return "正在断开";
        if (value === ConnectionState.Disconnected)
            return "已断开";
        return connected ? "已连接" : "未知";
    }

    function firstNetwork(device) {
        if (!device)
            return null;
        try {
            if (device.network)
                return device.network;
        } catch (e) {}
        try {
            var networks = device.networks;
            if (networks && networks.values && networks.values.length > 0)
                return networks.values[0];
        } catch (e) {}
        return null;
    }

    function wiredEntry(device) {
        if (!device)
            return null;

        var name = "";
        try {
            name = String(device.name || "").trim();
        } catch (e) {}
        if (name.length === 0)
            name = "有线设备";

        var network = root.firstNetwork(device);
        var networkName = "";
        try {
            networkName = network ? String(network.name || "").trim() : "";
        } catch (e) {}

        var state = 0;
        try {
            state = Number(device.state);
        } catch (e) {}

        var speed = 0;
        try {
            speed = Number(device.linkSpeed) || 0;
        } catch (e) {}

        var hasLink = false;
        try {
            hasLink = !!device.hasLink;
        } catch (e) {}

        var connected = false;
        try {
            connected = !!device.connected;
        } catch (e) {}

        var address = "";
        try {
            address = String(device.address || "").trim();
        } catch (e) {}

        var managed = true;
        try {
            managed = !!device.nmManaged;
        } catch (e) {}

        var autoconnect = false;
        try {
            autoconnect = !!device.autoconnect;
        } catch (e) {}

        return {
            "device": device,
            "network": network,
            "name": name,
            "networkName": networkName,
            "address": address,
            "connected": connected,
            "hasLink": hasLink,
            "linkSpeed": speed,
            "nmManaged": managed,
            "autoconnect": autoconnect,
            "state": state,
            "stateText": root.connectionStateText(state, connected),
            "stateChanging": state === ConnectionState.Connecting || state === ConnectionState.Disconnecting
        };
    }

    function connectWired(entry) {
        if (!entry)
            return;

        var network = entry.network || root.firstNetwork(entry.device);
        try {
            if (network && network.connect) {
                network.connect();
                return;
            }
        } catch (e) {}
    }

    function disconnectWired(entry) {
        if (!entry)
            return;

        try {
            if (entry.network && entry.network.disconnect) {
                entry.network.disconnect();
                return;
            }
        } catch (e) {}

        try {
            if (entry.device && entry.device.disconnect)
                entry.device.disconnect();
        } catch (e) {}
    }

    function setWiredAutoconnect(entry, enabled) {
        if (!entry || !entry.device)
            return;
        try {
            entry.device.autoconnect = !!enabled;
        } catch (e) {}
    }

    function refresh() {
        root.refreshVpnProfiles();
    }

    function refreshVpnProfiles() {
        if (!root.commandRunner || !root.commandRunner.networkVpnListCommand) {
            root.networkProbeState = "missing";
            root.networkProbeDetail = "CommandRunner 未注入，无法检测 NetworkManager。";
            root.vpnProfiles = [];
            root.revision += 1;
            return;
        }

        if (root.commandRunner.revision === 0)
            root.commandRunner.refreshDependencies();

        if (vpnProbe.running)
            return;

        root.vpnRefreshing = true;
        vpnProbe.command = root.commandRunner.networkVpnListCommand();
        vpnProbe.running = true;
    }

    function parseVpnProfiles(text) {
        var state = "missing";
        var detail = "NetworkManager 状态未知。";
        var profiles = [];
        var wired = [];
        var proxy = {
            "status": "missing",
            "mode": "none",
            "autoconfigUrl": "",
            "httpHost": "",
            "httpPort": "0",
            "httpsHost": "",
            "httpsPort": "0",
            "socksHost": "",
            "socksPort": "0"
        };
        var lines = String(text || "").split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            if (!line || line.length === 0)
                continue;

            var fields = line.split("|");
            if (fields[0] === "STATUS" && fields.length >= 3) {
                state = fields[1];
                detail = fields.slice(2).join("|");
            } else if (fields[0] === "VPN" && fields.length >= 6) {
                var name = String(fields[1] || "").trim();
                var uuid = String(fields[2] || "").trim();
                if (uuid.length === 0)
                    continue;
                profiles.push({
                    "name": name.length > 0 ? name : "VPN",
                    "uuid": uuid,
                    "type": String(fields[3] || "").trim(),
                    "device": String(fields[4] || "").trim(),
                    "active": String(fields[5] || "") === "1",
                    "autoconnect": fields.length >= 7 ? String(fields[6] || "") === "yes" : false
                });
            } else if (fields[0] === "WIRED_PROFILE" && fields.length >= 14) {
                wired.push({
                    "name": String(fields[1] || "").trim() || "有线网络",
                    "uuid": String(fields[2] || "").trim(),
                    "device": String(fields[3] || "").trim(),
                    "active": String(fields[4] || "") === "1",
                    "autoconnect": String(fields[5] || "") === "yes",
                    "ipv4Method": String(fields[6] || "auto"),
                    "ipv4Addresses": String(fields[7] || ""),
                    "ipv4Gateway": String(fields[8] || ""),
                    "ipv4Dns": String(fields[9] || ""),
                    "ipv6Method": String(fields[10] || "auto"),
                    "ipv6Addresses": String(fields[11] || ""),
                    "ipv6Gateway": String(fields[12] || ""),
                    "ipv6Dns": String(fields[13] || "")
                });
            } else if (fields[0] === "PROXY" && fields.length >= 10) {
                proxy = {
                    "status": String(fields[1] || "missing"),
                    "mode": String(fields[2] || "none"),
                    "autoconfigUrl": String(fields[3] || ""),
                    "httpHost": String(fields[4] || ""),
                    "httpPort": String(fields[5] || "0"),
                    "httpsHost": String(fields[6] || ""),
                    "httpsPort": String(fields[7] || "0"),
                    "socksHost": String(fields[8] || ""),
                    "socksPort": String(fields[9] || "0")
                };
            }
        }

        profiles.sort(function(a, b) {
            if (a.active !== b.active)
                return a.active ? -1 : 1;
            return a.name.localeCompare(b.name);
        });

        wired.sort(function(a, b) {
            if (a.active !== b.active)
                return a.active ? -1 : 1;
            if (a.autoconnect !== b.autoconnect)
                return a.autoconnect ? -1 : 1;
            return a.name.localeCompare(b.name);
        });

        root.networkProbeState = state;
        root.networkProbeDetail = detail;
        root.vpnProfiles = profiles;
        root.wiredProfiles = wired;
        root.proxySettings = proxy;
        root.revision += 1;
    }

    function setVpnEnabled(entry, enabled) {
        if (!entry || !entry.uuid || !root.commandRunner)
            return;

        var result = enabled
            ? root.commandRunner.runNetworkVpnUp(entry.uuid, entry.name)
            : root.commandRunner.runNetworkVpnDown(entry.uuid, entry.name);
        root.lastActionResult = result;
        actionRefreshTimer.restart();
    }

    function openVpnEditor(entry) {
        if (!root.commandRunner)
            return;
        var result = entry && entry.uuid
            ? root.commandRunner.runNetworkConnectionEditor(entry.uuid)
            : root.commandRunner.runNetworkNewVpn();
        root.lastActionResult = result;
        actionRefreshTimer.restart();
    }

    function importVpn(vpnType, path) {
        if (!root.commandRunner || !root.commandRunner.runNetworkVpnImport)
            return;
        root.lastActionResult = root.commandRunner.runNetworkVpnImport(vpnType, path);
        actionRefreshTimer.restart();
    }

    function saveVpn(entry, name, autoconnect) {
        if (!entry || !entry.uuid || !root.commandRunner || !root.commandRunner.runNetworkVpnSave)
            return;
        root.lastActionResult = root.commandRunner.runNetworkVpnSave(entry.uuid, name, autoconnect);
        actionRefreshTimer.restart();
    }

    function saveProxy(settings) {
        if (!settings || !root.commandRunner || !root.commandRunner.runNetworkProxySave)
            return;
        root.lastActionResult = root.commandRunner.runNetworkProxySave(
            settings.mode,
            settings.autoconfigUrl,
            settings.httpHost,
            settings.httpPort,
            settings.httpsHost,
            settings.httpsPort,
            settings.socksHost,
            settings.socksPort
        );
        actionRefreshTimer.restart();
    }

    function saveWiredProfile(entry, values) {
        if (!entry || !entry.uuid || !values || !root.commandRunner || !root.commandRunner.runNetworkWiredSave)
            return;
        root.lastActionResult = root.commandRunner.runNetworkWiredSave(
            entry.uuid,
            values.ipv4Method,
            values.ipv4Addresses,
            values.ipv4Gateway,
            values.ipv4Dns,
            values.ipv6Method,
            values.ipv6Addresses,
            values.ipv6Gateway,
            values.ipv6Dns
        );
        actionRefreshTimer.restart();
    }

    Process {
        id: vpnProbe
        running: false
        stdout: StdioCollector {
            id: vpnProbeOut
            onStreamFinished: root.parseVpnProfiles(vpnProbeOut.text)
        }
        onExited: function(code, exitStatus) {
            root.vpnRefreshing = false;
            if (code !== 0 && root.networkProbeState !== "ok") {
                root.networkProbeState = "missing";
                root.networkProbeDetail = "VPN 列表检测失败，退出码 " + String(code);
                root.vpnProfiles = [];
                root.wiredProfiles = [];
                root.proxySettings = {
                    "status": "missing",
                    "mode": "none",
                    "autoconfigUrl": "",
                    "httpHost": "",
                    "httpPort": "0",
                    "httpsHost": "",
                    "httpsPort": "0",
                    "socksHost": "",
                    "socksPort": "0"
                };
                root.revision += 1;
            }
        }
    }

    Timer {
        id: actionRefreshTimer
        interval: 1600
        repeat: false
        onTriggered: root.refreshVpnProfiles()
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.refreshVpnProfiles()
    }

    Connections {
        target: root.commandRunner
        function onRevisionChanged() {
            root.refreshVpnProfiles();
        }
    }

    Component.onCompleted: root.refreshVpnProfiles()
}
