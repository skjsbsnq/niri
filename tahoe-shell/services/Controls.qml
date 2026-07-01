pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Mpris

// Control Center backing service.
//
// Aggregates real hardware/media state from Quickshell singletons and exposes
// it as plain readonly properties + untyped action functions, mirroring the
// Niri.qml / Apps.qml service pattern. Every access is null-guarded so the
// shell never crashes when running under a VM that lacks Wi-Fi, Bluetooth,
// MPRIS players or a backlight.

// NOTE: the root is an Item (not QtObject) because this service owns child
// QML objects (PwObjectTracker, Process, Timer, Component.onCompleted).
// QtObject has no default `children` property, so declaring child objects
// inside it throws "Cannot assign to non-existent default property" at load
// time and aborts the whole shell. Item has a `children` slot and, with
// visible:false, does not participate in rendering, so it is the idiomatic
// container for a stateful non-visual service in Quickshell.

Item {
    id: root
    visible: false

    readonly property string controlsStatePath: Quickshell.stateDir + "/controls.json"
    property bool controlsStateLoaded: false
    property int preferredWifiRestoreAttempts: 0
    property bool preferredWifiRestoreSuppressed: false
    property var commandRunner
    property string networkErrorText: ""
    property string bluetoothErrorText: ""
    property string brightnessErrorText: ""
    property var lastActionResult: null
    property var knownWifiProfiles: []
    property string knownWifiStatus: "unknown"
    property string knownWifiDetail: "尚未读取已知网络"
    property bool knownWifiRefreshing: false
    property bool hotspotActive: false
    property string hotspotName: ""

    FileView {
        id: controlsStateFile
        path: root.controlsStatePath
        blockLoading: true
        blockWrites: true
        printErrors: false
        onLoaded: root.restoreControlsState()
        onLoadFailed: {
            root.controlsStateLoaded = true;
            root.saveControlsState();
        }

        JsonAdapter {
            id: controlsState
            property bool wifiRadioEnabled: true
            property string preferredWifiSsid: ""
        }
    }

    function saveControlsState() {
        controlsStateFile.writeAdapter();
    }

    function restoreControlsState() {
        root.controlsStateLoaded = true;

        if (root.wifiConnected)
            root.rememberCurrentWifi();

        root.saveControlsState();
        root.schedulePreferredWifiRestore(2800, true);
    }

    // ------------------------------------------------------------------
    // Audio (PipeWire / pipewire-pulse)
    // ------------------------------------------------------------------
    // PwNode.audio.volume/muted are only valid once the node is tracked by a
    // PwObjectTracker. We bind the default sink so its audio object stays live.

    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property bool audioReady: Pipewire.ready && !!audioSink

    // Binding the default sink makes its audio.volume / audio.muted writable.
    // Without this the node is unbound and writes are silently dropped.
    PwObjectTracker {
        objects: root.audioSink ? [root.audioSink] : []
    }

    readonly property real volume: audioReady && audioSink.audio ? audioSink.audio.volume : 0
    readonly property bool muted: audioReady && audioSink.audio ? audioSink.audio.muted : false

    function setVolume(value) {
        if (!audioReady || !audioSink.audio)
            return;
        var v = Math.max(0, Math.min(1, Number(value) || 0));
        audioSink.audio.volume = v;
        if (v > 0 && audioSink.audio.muted)
            audioSink.audio.muted = false;
    }

    function toggleMute() {
        if (!audioReady || !audioSink.audio)
            return;
        audioSink.audio.muted = !audioSink.audio.muted;
    }

    // ------------------------------------------------------------------
    // Brightness (brightnessctl via Process — no Quickshell module exists)
    // ------------------------------------------------------------------
    // brightnessctl -m prints CSV, e.g.:
    //   "nvidia_0,backlight,100,100%,100"
    // We read the numeric current/max fields and fall back to any trailing
    // numbers so the slider still works across backend variants.
    // On systems without a backlight (VMs), the command exits non-zero and we
    // mark the slider unavailable but keep the UI visible.

    property real brightness: 1.0
    property bool brightnessAvailable: false
    property bool brightnessUpdating: false
    readonly property string brightnessMonitorScript: [
        "last='__unset__'",
        "while :; do",
        "  line=''",
        "  for d in /sys/class/backlight/*; do",
        "    [ -r \"$d/brightness\" ] && [ -r \"$d/max_brightness\" ] || continue",
        "    name=${d##*/}",
        "    cur=$(cat \"$d/brightness\" 2>/dev/null) || continue",
        "    max=$(cat \"$d/max_brightness\" 2>/dev/null) || continue",
        "    line=\"$name,$cur,$max\"",
        "    break",
        "  done",
        "  if [ \"$line\" != \"$last\" ]; then",
        "    printf '%s\\n' \"$line\"",
        "    last=\"$line\"",
        "  fi",
        "  sleep 0.2",
        "done"
    ].join("\n")

    function setBrightnessValue(value) {
        var clamped = Math.max(0, Math.min(1, Number(value) || 0));
        if (Math.abs(root.brightness - clamped) > 0.0005)
            root.brightness = clamped;
    }

    function setBrightnessAvailable(available) {
        var next = !!available;
        if (root.brightnessAvailable !== next)
            root.brightnessAvailable = next;
    }

    function refreshBrightness() {
        if (root.commandRunner && root.commandRunner.revision > 0 && !root.commandRunner.commandAvailable("brightnessctl")) {
            root.brightnessErrorText = "缺少 brightnessctl";
            root.setBrightnessAvailable(false);
            return;
        }
        brightnessProbe.running = true;
    }

    function parseBrightnessMonitorLine(line) {
        var text = String(line || "").trim();
        if (text.length === 0) {
            root.setBrightnessAvailable(false);
            return;
        }

        var parts = text.split(",");
        if (parts.length < 3)
            return;

        var current = parseFloat(parts[1]);
        var max = parseFloat(parts[2]);
        if (!isFinite(current) || !isFinite(max) || max <= 0)
            return;

        if (root.commandRunner && root.commandRunner.revision > 0 && !root.commandRunner.commandAvailable("brightnessctl")) {
            root.brightnessErrorText = "缺少 brightnessctl";
            root.setBrightnessAvailable(false);
            return;
        }

        root.setBrightnessValue(current / max);
        root.setBrightnessAvailable(true);
    }

    function setBrightness(value) {
        if (!brightnessAvailable)
            return;
        if (root.commandRunner && root.commandRunner.revision > 0 && !root.commandRunner.commandAvailable("brightnessctl")) {
            root.brightnessErrorText = "缺少 brightnessctl";
            root.setBrightnessAvailable(false);
            return;
        }
        var v = Math.max(0.05, Math.min(1, Number(value) || 0));
        brightnessUpdating = true;
        root.setBrightnessValue(v);
        var pct = Math.round(v * 100).toString();
        brightnessSetter.command = ["brightnessctl", "set", pct + "%"];
        brightnessSetter.running = true;
    }

    Process {
        id: brightnessProbe
        running: false
        command: ["brightnessctl", "-m", "info"]
        stdout: StdioCollector {
            id: brightnessOut
            onStreamFinished: {
                var text = String(brightnessOut.text || "").trim();
                var parts = text.split(/[,;\s]+/).filter(function (s) { return s.length > 0; });
                var numbers = [];
                for (var i = 0; i < parts.length; i++) {
                    var token = parts[i].replace(/%$/, "");
                    var value = parseFloat(token);
                    if (isFinite(value))
                        numbers.push(value);
                }

                var current = NaN;
                var max = NaN;
                if (numbers.length >= 2) {
                    current = numbers[numbers.length - 2];
                    max = numbers[numbers.length - 1];
                }

                if (isFinite(current) && isFinite(max) && max > 0) {
                    root.setBrightnessValue(current / max);
                    root.setBrightnessAvailable(true);
                    return;
                }
                root.setBrightnessAvailable(false);
            }
        }
        onExited: function (code, exitStatus) {
            if (code !== 0)
                root.setBrightnessAvailable(false);
        }
    }

    Process {
        id: brightnessSetter
        running: false
        onExited: function (code, exitStatus) {
            root.brightnessUpdating = false;
            if (code !== 0)
                root.refreshBrightness();
        }
    }

    Process {
        id: brightnessMonitor
        running: true
        command: ["sh", "-lc", root.brightnessMonitorScript]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                root.parseBrightnessMonitorLine(line);
            }
        }
        onRunningChanged: {
            if (!running)
                brightnessMonitorRestart.restart();
        }
    }

    Timer {
        id: brightnessMonitorRestart
        interval: 1000
        repeat: false
        onTriggered: {
            if (!brightnessMonitor.running)
                brightnessMonitor.running = true;
        }
    }

    // Poll brightness every 4s so external changes (Fn keys, other tools)
    // are reflected even if sysfs monitoring is unavailable.
    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: {
            if (!root.brightnessUpdating)
                root.refreshBrightness();
        }
    }

    Component.onCompleted: {
        if (root.commandRunner)
            root.commandRunner.refreshDependencies();
        root.refreshBrightness();
        root.rescanWifi();
        root.refreshKnownWifiProfiles();
        if (root.wifiConnected)
            root.rememberCurrentWifi();
        root.schedulePreferredWifiRestore(4200, true);
    }

    // ------------------------------------------------------------------
    // Wi-Fi
    // ------------------------------------------------------------------

    readonly property bool networkManagerAvailable: {
        if (root.commandRunner && root.commandRunner.revision > 0)
            return root.commandRunner.dependencyReady("network");
        return String(root.networkErrorText || "").trim().length === 0;
    }

    readonly property bool wifiEnabled: {
        try {
            return !!Networking.wifiEnabled;
        } catch (e) {
            return false;
        }
    }

    property bool airplaneMode: false
    property bool savedWifiEnabled: true
    property bool savedBluetoothEnabled: false

    readonly property var wifiDevice: {
        try {
            var devices = Networking.devices;
            if (!devices || !devices.values)
                return null;
            for (var i = 0; i < devices.values.length; i++) {
                var d = devices.values[i];
                if (d && (d.type === DeviceType.Wifi || String(d.type || "").toLowerCase() === "wifi"))
                    return d;
            }
        } catch (e) {}
        return null;
    }

    readonly property bool wifiConnected: {
        var d = root.wifiDevice;
        return !!d && !!d.connected;
    }

    readonly property string wifiName: {
        var d = root.wifiDevice;
        if (!d || !d.connected)
            return root.wifiEnabled ? "未连接" : "已关闭";
        try {
            var nets = d.networks;
            if (nets && nets.values) {
                for (var i = 0; i < nets.values.length; i++) {
                    var n = nets.values[i];
                    if (n && n.connected) {
                        var name = String(n.name || "").trim();
                        if (name.length > 0)
                            return name;
                    }
                }
            }
        } catch (e) {}
        return "已连接";
    }

    readonly property int wifiSignalPercent: {
        var active = root.activeWifiNetwork;
        return active ? root.signalPercent(active.signalStrength) : 0;
    }

    readonly property var activeWifiNetwork: {
        var d = root.wifiDevice;
        if (!d)
            return null;
        try {
            var nets = d.networks;
            if (!nets || !nets.values)
                return null;
            for (var i = 0; i < nets.values.length; i++) {
                var n = nets.values[i];
                if (n && n.connected)
                    return n;
            }
        } catch (e) {}
        return null;
    }

    readonly property var wifiNetworks: {
        var d = root.wifiDevice;
        if (!d)
            return [];

        try {
            var nets = d.networks;
            if (!nets || !nets.values)
                return [];

            var byName = {};
            for (var i = 0; i < nets.values.length; i++) {
                var n = nets.values[i];
                if (!n)
                    continue;

                var name = String(n.name || "").trim();
                if (name.length === 0)
                    continue;

                var signal = root.signalPercent(n.signalStrength);
                var existing = byName[name];
                if (!existing || n.connected || signal > existing.signalPercent) {
                    byName[name] = {
                        network: n,
                        name: name,
                        signalPercent: signal,
                        security: n.security,
                        secured: root.wifiNeedsPassword(n),
                        pskSupported: root.wifiSupportsPsk(n),
                        known: !!n.known,
                        connected: !!n.connected,
                        stateChanging: !!n.stateChanging
                    };
                }
            }

            var out = [];
            for (var key in byName)
                out.push(byName[key]);

            out.sort(function(a, b) {
                if (a.connected !== b.connected)
                    return a.connected ? -1 : 1;
                if (a.known !== b.known)
                    return a.known ? -1 : 1;
                return b.signalPercent - a.signalPercent;
            });

            return out;
        } catch (e) {
            console.warn("[Controls] failed to read wifi networks:", e);
            return [];
        }
    }

    onWifiConnectedChanged: {
        if (root.wifiConnected)
            root.rememberCurrentWifi();
    }

    onWifiNameChanged: {
        if (root.wifiConnected)
            root.rememberCurrentWifi();
    }

    function setWifiEnabled(enabled, fromState) {
        try {
            Networking.wifiEnabled = !!enabled;
        } catch (e) {}

        controlsState.wifiRadioEnabled = !!enabled;
        root.saveControlsState();

        if (enabled) {
            root.preferredWifiRestoreSuppressed = false;
            Qt.callLater(function() { root.rescanWifi(); });
            if (!fromState)
                root.schedulePreferredWifiRestore(1800, true);
        } else {
            root.preferredWifiRestoreSuppressed = true;
        }
    }

    function toggleWifi() {
        root.airplaneMode = false;
        setWifiEnabled(!root.wifiEnabled);
    }

    function signalPercent(value) {
        var n = Number(value);
        if (!isFinite(n) || n <= 0)
            return 0;
        if (n <= 1)
            return Math.round(n * 100);
        return Math.round(Math.min(100, n));
    }

    function validWifiSsid(value) {
        var text = String(value || "").trim();
        return text.length > 0
            && text !== "已连接"
            && text !== "未连接"
            && text !== "已关闭";
    }

    function currentWifiSsid() {
        var active = root.activeWifiNetwork;
        var activeName = active ? String(active.name || "").trim() : "";
        if (root.validWifiSsid(activeName))
            return activeName;

        var label = String(root.wifiName || "").trim();
        return root.validWifiSsid(label) ? label : "";
    }

    function rememberPreferredWifiSsid(ssid) {
        var text = String(ssid || "").trim();
        if (!root.validWifiSsid(text))
            return;

        if (controlsState.preferredWifiSsid !== text) {
            controlsState.preferredWifiSsid = text;
            root.saveControlsState();
        }
        root.ensureWifiAutoconnect(text);
    }

    function rememberCurrentWifi() {
        root.rememberPreferredWifiSsid(root.currentWifiSsid());
    }

    function schedulePreferredWifiRestore(delayMs, resetAttempts) {
        if (resetAttempts)
            root.preferredWifiRestoreAttempts = 0;
        preferredWifiRestoreTimer.interval = Math.max(500, Number(delayMs) || 2500);
        preferredWifiRestoreTimer.restart();
    }

    function restorePreferredWifi() {
        if (root.preferredWifiRestoreSuppressed || root.wifiConnected)
            return;

        var ssid = String(controlsState.preferredWifiSsid || "").trim();
        if (!root.validWifiSsid(ssid))
            return;

        if (!controlsState.wifiRadioEnabled)
            return;

        if (!root.wifiDevice) {
            if (root.preferredWifiRestoreAttempts < 6) {
                root.preferredWifiRestoreAttempts += 1;
                root.schedulePreferredWifiRestore(5000, false);
            }
            return;
        }

        root.preferredWifiRestoreAttempts += 1;
        root.rescanWifi();
        if (root.commandRunner && root.commandRunner.runWifiRestorePreferred) {
            var result = root.commandRunner.runWifiRestorePreferred(ssid);
            root.lastActionResult = result;
            root.networkErrorText = result && result.success ? "" : String(result && (result.detail || result.message) || "");
        } else {
            Quickshell.execDetached({
                command: [
                    "sh",
                    "-lc",
                    [
                        "ssid=\"$1\"",
                        "[ -n \"$ssid\" ] || exit 0",
                        "command -v nmcli >/dev/null 2>&1 || exit 0",
                        "nmcli radio wifi on >/dev/null 2>&1 || true",
                        "nmcli connection modify \"$ssid\" connection.autoconnect yes >/dev/null 2>&1 || true",
                        "nmcli --wait 20 connection up id \"$ssid\" >/dev/null 2>&1",
                        "  || nmcli --wait 20 device wifi connect \"$ssid\" >/dev/null 2>&1",
                        "  || true"
                    ].join("\n"),
                    "sh",
                    ssid
                ]
            });
        }

        if (root.preferredWifiRestoreAttempts < 6)
            root.schedulePreferredWifiRestore(10000, false);
    }

    Timer {
        id: preferredWifiRestoreTimer
        interval: 2500
        repeat: false
        onTriggered: root.restorePreferredWifi()
    }

    function ensureWifiAutoconnect(ssid) {
        var name = String(ssid || "").trim();
        if (!root.validWifiSsid(name))
            return;

        if (root.commandRunner && root.commandRunner.runWifiAutoconnect) {
            var result = root.commandRunner.runWifiAutoconnect(name);
            root.lastActionResult = result;
            root.networkErrorText = result && result.success ? "" : String(result && (result.detail || result.message) || "");
            return;
        }

        Quickshell.execDetached({
            command: [
                "sh",
                "-lc",
                [
                    "ssid=\"$1\"",
                    "[ -n \"$ssid\" ] || exit 0",
                    "command -v nmcli >/dev/null 2>&1 || exit 0",
                    "nmcli connection modify \"$ssid\" connection.autoconnect yes >/dev/null 2>&1 || true"
                ].join("\n"),
                "sh",
                name
            ]
        });
    }

    function wifiNeedsPassword(network) {
        if (!network)
            return false;
        try {
            return network.security !== WifiSecurityType.Open
                && network.security !== WifiSecurityType.Owe;
        } catch (e) {
            return true;
        }
    }

    function wifiSupportsPsk(network) {
        if (!network)
            return false;
        try {
            return network.security === WifiSecurityType.WpaPsk
                || network.security === WifiSecurityType.Wpa2Psk
                || network.security === WifiSecurityType.Sae;
        } catch (e) {
            return true;
        }
    }

    function connectWifi(entry, psk) {
        var network = entry && entry.network ? entry.network : entry;
        if (!network)
            return;

        var ssid = entry && entry.name ? String(entry.name || "").trim() : String(network.name || "").trim();
        root.rememberPreferredWifiSsid(ssid);
        root.preferredWifiRestoreSuppressed = false;
        root.ensureWifiAutoconnect(ssid);

        try {
            if (psk && psk.length > 0 && network.connectWithPsk && (!entry || entry.pskSupported !== false)) {
                network.connectWithPsk(psk);
                root.schedulePreferredWifiRestore(6500, true);
                return;
            }
            if ((!psk || psk.length === 0) && network.connect) {
                network.connect();
                root.schedulePreferredWifiRestore(6500, true);
                return;
            }
        } catch (e) {
            console.warn("[Controls] wifi connect failed, falling back to nmcli:", e);
        }

        if (ssid.length === 0)
            return;

        var command = ["nmcli", "device", "wifi", "connect", ssid];
        if (psk && psk.length > 0)
            command.push("password", psk);
        if (root.commandRunner && root.commandRunner.runWifiConnect) {
            var result = root.commandRunner.runWifiConnect(ssid, psk || "");
            root.lastActionResult = result;
            root.networkErrorText = result && result.success ? "" : String(result && (result.detail || result.message) || "");
        } else {
            Quickshell.execDetached({ command: command });
        }
        root.schedulePreferredWifiRestore(6500, true);
    }

    function wifiEscapeQr(value) {
        return String(value || "").replace(/([\\;,:"])/g, "\\$1");
    }

    function wifiQrPayload(ssid, psk, secured, hidden) {
        var auth = secured ? "WPA" : "nopass";
        var payload = "WIFI:T:" + auth + ";S:" + root.wifiEscapeQr(ssid) + ";";
        if (secured)
            payload += "P:" + root.wifiEscapeQr(psk) + ";";
        if (hidden)
            payload += "H:true;";
        return payload + ";";
    }

    function refreshKnownWifiProfiles() {
        if (!root.commandRunner || !root.commandRunner.wifiKnownListCommand) {
            root.knownWifiStatus = "missing";
            root.knownWifiDetail = "CommandRunner 未注入，无法读取已知网络。";
            root.knownWifiProfiles = [];
            return;
        }
        if (knownWifiProbe.running)
            return;

        root.knownWifiRefreshing = true;
        knownWifiProbe.command = root.commandRunner.wifiKnownListCommand();
        knownWifiProbe.running = true;
    }

    function parseKnownWifiProfiles(text) {
        var profiles = [];
        var status = "missing";
        var detail = "NetworkManager 状态未知。";
        var lines = String(text || "").split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            if (!line || line.length === 0)
                continue;
            var fields = line.split("|");
            if (fields[0] === "STATUS" && fields.length >= 3) {
                status = fields[1];
                detail = fields.slice(2).join("|");
            } else if (fields[0] === "HOTSPOT" && fields.length >= 2) {
                root.hotspotActive = fields[1] === "1";
                root.hotspotName = fields.length >= 3 ? String(fields[2] || "") : "";
            } else if (fields[0] === "WIFI" && fields.length >= 5) {
                var name = String(fields[1] || "").trim();
                var uuid = String(fields[2] || "").trim();
                if (uuid.length === 0)
                    continue;
                profiles.push({
                    "name": name.length > 0 ? name : "未命名网络",
                    "uuid": uuid,
                    "autoconnect": String(fields[3] || "") === "yes",
                    "active": String(fields[4] || "") === "1"
                });
            }
        }
        profiles.sort(function(a, b) {
            if (a.active !== b.active)
                return a.active ? -1 : 1;
            if (a.autoconnect !== b.autoconnect)
                return a.autoconnect ? -1 : 1;
            return a.name.localeCompare(b.name);
        });
        root.knownWifiStatus = status;
        root.knownWifiDetail = detail;
        root.knownWifiProfiles = profiles;
    }

    function forgetWifiProfile(entry) {
        if (!entry || !entry.uuid || !root.commandRunner || !root.commandRunner.runWifiForget)
            return;
        var result = root.commandRunner.runWifiForget(entry.uuid, entry.name);
        root.lastActionResult = result;
        knownWifiRefreshTimer.restart();
    }

    function connectHiddenWifi(ssid, psk) {
        var name = String(ssid || "").trim();
        if (name.length === 0 || !root.commandRunner || !root.commandRunner.runWifiHiddenConnect)
            return;
        root.rememberPreferredWifiSsid(name);
        var result = root.commandRunner.runWifiHiddenConnect(name, psk || "");
        root.lastActionResult = result;
        root.preferredWifiRestoreSuppressed = false;
        root.schedulePreferredWifiRestore(6500, true);
        knownWifiRefreshTimer.restart();
    }

    function setWifiHotspotEnabled(enabled, ssid, psk) {
        if (!root.commandRunner)
            return;
        var result = enabled
            ? root.commandRunner.runWifiHotspotUp(ssid || "Tahoe Hotspot", psk || "")
            : root.commandRunner.runWifiHotspotDown();
        root.lastActionResult = result;
        knownWifiRefreshTimer.restart();
    }

    function disconnectWifi() {
        root.preferredWifiRestoreSuppressed = true;
        var d = root.wifiDevice;
        if (d && d.disconnect) {
            try { d.disconnect(); } catch (e) {}
        }
    }

    function rescanWifi() {
        var d = root.wifiDevice;
        if (!d || !root.wifiEnabled)
            return;

        try {
            d.scannerEnabled = false;
        } catch (e) {}
        Qt.callLater(function() {
            try {
                if (root.wifiDevice && root.wifiEnabled)
                    root.wifiDevice.scannerEnabled = true;
            } catch (e) {}
        });
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            root.rescanWifi();
            root.refreshKnownWifiProfiles();
        }
    }

    Process {
        id: knownWifiProbe
        running: false
        stdout: StdioCollector {
            id: knownWifiOut
            onStreamFinished: root.parseKnownWifiProfiles(knownWifiOut.text)
        }
        onExited: function(code, exitStatus) {
            root.knownWifiRefreshing = false;
            if (code !== 0 && root.knownWifiStatus !== "ok") {
                root.knownWifiStatus = "missing";
                root.knownWifiDetail = "已知网络读取失败，退出码 " + String(code);
                root.knownWifiProfiles = [];
            }
        }
    }

    Timer {
        id: knownWifiRefreshTimer
        interval: 1600
        repeat: false
        onTriggered: root.refreshKnownWifiProfiles()
    }

    // ------------------------------------------------------------------
    // Bluetooth
    // ------------------------------------------------------------------

    readonly property var bluetoothAdapter: {
        try {
            return Bluetooth.defaultAdapter || null;
        } catch (e) {
            return null;
        }
    }

    readonly property bool bluetoothAvailable: !!bluetoothAdapter

    readonly property bool bluetoothEnabled: {
        var a = root.bluetoothAdapter;
        return !!a && !!a.enabled;
    }

    readonly property string bluetoothDependencyState: {
        if (root.commandRunner && root.commandRunner.revision > 0)
            return root.commandRunner.dependencyState("bluetooth");
        return String(root.bluetoothErrorText || "").trim().length > 0 ? "warn" : "ok";
    }

    readonly property bool bluetoothBackendAvailable: bluetoothDependencyState !== "missing"

    readonly property string bluetoothAdapterName: {
        var a = root.bluetoothAdapter;
        if (!a)
            return "";
        try {
            var name = String(a.name || "").trim();
            if (name.length > 0)
                return name;
        } catch (e) {}
        try {
            return String(a.adapterId || "").trim();
        } catch (e) {}
        return "";
    }

    readonly property int bluetoothAdapterState: {
        var a = root.bluetoothAdapter;
        if (!a)
            return -1;
        try {
            return Number(a.state);
        } catch (e) {
            return -1;
        }
    }

    readonly property bool bluetoothAdapterBlocked: bluetoothAdapterState === 4

    readonly property bool bluetoothDiscovering: {
        var a = root.bluetoothAdapter;
        if (!a)
            return false;
        try {
            return !!a.discovering;
        } catch (e) {
            return false;
        }
    }

    readonly property bool bluetoothDiscoverable: {
        var a = root.bluetoothAdapter;
        if (!a)
            return false;
        try {
            return !!a.discoverable;
        } catch (e) {
            return false;
        }
    }

    readonly property bool bluetoothPairable: {
        var a = root.bluetoothAdapter;
        if (!a)
            return false;
        try {
            return !!a.pairable;
        } catch (e) {
            return false;
        }
    }

    readonly property var bluetoothDeviceEntries: {
        var a = root.bluetoothAdapter;
        var values = [];
        try {
            if (a && a.devices && a.devices.values)
                values = a.devices.values;
            else {
                var devs = Bluetooth.devices;
                if (devs && devs.values)
                    values = devs.values;
            }
        } catch (e) {
            values = [];
        }

        var out = [];
        var seen = {};
        for (var i = 0; i < values.length; i++) {
            var device = values[i];
            if (!device)
                continue;
            var entry = root.bluetoothDeviceEntry(device);
            if (!entry)
                continue;
            var key = entry.address.length > 0 ? entry.address : entry.dbusPath;
            if (key.length > 0 && seen[key])
                continue;
            if (key.length > 0)
                seen[key] = true;
            out.push(entry);
        }

        out.sort(function(a, b) {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            if (a.paired !== b.paired)
                return a.paired ? -1 : 1;
            if (a.trusted !== b.trusted)
                return a.trusted ? -1 : 1;
            return a.name.localeCompare(b.name);
        });

        return out;
    }

    readonly property int bluetoothConnectedCount: {
        var count = 0;
        var entries = root.bluetoothDeviceEntries || [];
        for (var i = 0; i < entries.length; i++) {
            if (entries[i] && entries[i].connected)
                count += 1;
        }
        return count;
    }

    function bluetoothDeviceEntry(device) {
        if (!device)
            return null;

        var name = "";
        try {
            name = String(device.name || "").trim();
        } catch (e) {}
        if (name.length === 0) {
            try {
                name = String(device.deviceName || "").trim();
            } catch (e) {}
        }
        if (name.length === 0)
            name = "未命名设备";

        var address = "";
        try {
            address = String(device.address || "").trim();
        } catch (e) {}

        var state = 0;
        try {
            state = Number(device.state);
        } catch (e) {
            state = device.connected ? 1 : 0;
        }

        var battery = 0;
        var batteryAvailable = false;
        try {
            batteryAvailable = !!device.batteryAvailable;
            battery = Math.round(Math.max(0, Math.min(1, Number(device.battery) || 0)) * 100);
        } catch (e) {}

        return {
            "device": device,
            "name": name,
            "address": address,
            "icon": String(device.icon || ""),
            "dbusPath": String(device.dbusPath || ""),
            "connected": !!device.connected,
            "paired": !!device.paired,
            "bonded": !!device.bonded,
            "pairing": !!device.pairing,
            "trusted": !!device.trusted,
            "blocked": !!device.blocked,
            "wakeAllowed": !!device.wakeAllowed,
            "batteryAvailable": batteryAvailable,
            "batteryPercent": battery,
            "state": state,
            "stateChanging": state === 2 || state === 3 || !!device.pairing
        };
    }

    function bluetoothDeviceFromEntry(entry) {
        if (!entry)
            return null;
        return entry.device ? entry.device : entry;
    }

    function setBluetoothEnabled(enabled) {
        var a = root.bluetoothAdapter;
        if (!a)
            return;
        try {
            a.enabled = !!enabled;
        } catch (e) {}
    }

    function setBluetoothDiscovering(enabled) {
        var a = root.bluetoothAdapter;
        if (!a || !root.bluetoothEnabled)
            return;

        try {
            a.discovering = !!enabled;
            return;
        } catch (e) {}

        try {
            if (enabled && a.startDiscovery)
                a.startDiscovery();
            else if (!enabled && a.stopDiscovery)
                a.stopDiscovery();
        } catch (e) {}
    }

    function toggleBluetoothDiscovering() {
        root.setBluetoothDiscovering(!root.bluetoothDiscovering);
    }

    function setBluetoothDiscoverable(enabled) {
        var a = root.bluetoothAdapter;
        if (!a || !root.bluetoothEnabled)
            return;
        try {
            a.discoverable = !!enabled;
        } catch (e) {}
    }

    function setBluetoothPairable(enabled) {
        var a = root.bluetoothAdapter;
        if (!a || !root.bluetoothEnabled)
            return;
        try {
            a.pairable = !!enabled;
        } catch (e) {}
    }

    function connectBluetoothDevice(entry) {
        var d = root.bluetoothDeviceFromEntry(entry);
        if (!d)
            return;
        try {
            if (d.connect)
                d.connect();
            else
                d.connected = true;
        } catch (e) {}
    }

    function disconnectBluetoothDevice(entry) {
        var d = root.bluetoothDeviceFromEntry(entry);
        if (!d)
            return;
        try {
            if (d.disconnect)
                d.disconnect();
            else
                d.connected = false;
        } catch (e) {}
    }

    function pairBluetoothDevice(entry) {
        var d = root.bluetoothDeviceFromEntry(entry);
        if (!d)
            return;
        try {
            if (d.pair)
                d.pair();
        } catch (e) {}
    }

    function cancelBluetoothPairing(entry) {
        var d = root.bluetoothDeviceFromEntry(entry);
        if (!d)
            return;
        try {
            if (d.cancelPair)
                d.cancelPair();
        } catch (e) {}
    }

    function forgetBluetoothDevice(entry) {
        var d = root.bluetoothDeviceFromEntry(entry);
        if (!d)
            return;
        try {
            if (d.forget)
                d.forget();
        } catch (e) {}
    }

    function setBluetoothDeviceTrusted(entry, trusted) {
        var d = root.bluetoothDeviceFromEntry(entry);
        if (!d)
            return;
        try {
            d.trusted = !!trusted;
        } catch (e) {}
    }

    function setBluetoothDeviceBlocked(entry, blocked) {
        var d = root.bluetoothDeviceFromEntry(entry);
        if (!d)
            return;
        try {
            d.blocked = !!blocked;
        } catch (e) {}
    }

    function toggleBluetooth() {
        if (!root.bluetoothAvailable)
            return;

        root.airplaneMode = false;
        setBluetoothEnabled(!root.bluetoothEnabled);
    }

    function syncCommandDependencies() {
        if (!root.commandRunner || root.commandRunner.revision === 0)
            return;

        var networkState = root.commandRunner.dependencyState("network");
        root.networkErrorText = networkState === "missing" ? root.commandRunner.dependencyDetail("network") : "";

        var bluetoothState = root.commandRunner.dependencyState("bluetooth");
        root.bluetoothErrorText = bluetoothState === "missing" || bluetoothState === "warn"
            ? root.commandRunner.dependencyDetail("bluetooth")
            : "";

        var brightnessState = root.commandRunner.dependencyState("brightness");
        root.brightnessErrorText = brightnessState === "ok" ? "" : root.commandRunner.dependencyDetail("brightness");
        if (brightnessState === "missing")
            root.setBrightnessAvailable(false);
    }

    function toggleAirplaneMode() {
        if (!root.airplaneMode) {
            root.savedWifiEnabled = root.wifiEnabled;
            root.savedBluetoothEnabled = root.bluetoothEnabled;
            root.setWifiEnabled(false);
            root.setBluetoothEnabled(false);
            root.airplaneMode = true;
        } else {
            root.setWifiEnabled(root.savedWifiEnabled);
            root.setBluetoothEnabled(root.savedBluetoothEnabled);
            root.airplaneMode = false;
        }
    }

    // ------------------------------------------------------------------
    // Now Playing (MPRIS)
    // ------------------------------------------------------------------
    // Pick the first player. Mpris.players.values is an ObjectModel so we
    // guard its length defensively.

    readonly property var activePlayer: {
        try {
            var players = Mpris.players;
            if (!players || !players.values || players.values.length === 0)
                return null;

            var first = null;
            var pausedWithTrack = null;
            for (var i = 0; i < players.values.length; i++) {
                var p = players.values[i];
                if (!p)
                    continue;

                if (!first)
                    first = p;

                if (p.playbackState === MprisPlaybackState.Playing)
                    return p;

                if (!pausedWithTrack
                        && p.playbackState === MprisPlaybackState.Paused
                        && String(p.trackTitle || "").trim().length > 0)
                    pausedWithTrack = p;
            }

            return pausedWithTrack || first;
        } catch (e) {}
        return null;
    }

    readonly property bool hasMedia: !!activePlayer

    readonly property bool isPlaying: {
        var p = root.activePlayer;
        if (!p)
            return false;
        try {
            return !!p.isPlaying || p.playbackState === MprisPlaybackState.Playing;
        } catch (e) {
            return false;
        }
    }

    readonly property real trackPosition: {
        var p = root.activePlayer;
        if (!p)
            return 0;
        try {
            return Math.max(0, Number(p.position) || 0);
        } catch (e) {
            return 0;
        }
    }

    readonly property real trackLength: {
        var p = root.activePlayer;
        if (!p)
            return 0;
        try {
            return Math.max(0, Number(p.length) || 0);
        } catch (e) {
            return 0;
        }
    }

    readonly property bool trackPositionSupported: {
        var p = root.activePlayer;
        try {
            return !!(p && p.positionSupported);
        } catch (e) {
            return false;
        }
    }

    readonly property bool trackLengthSupported: {
        var p = root.activePlayer;
        try {
            return !!(p && p.lengthSupported);
        } catch (e) {
            return false;
        }
    }

    readonly property real trackProgress: trackLength > 0
        ? Math.max(0, Math.min(1, trackPosition / trackLength))
        : 0

    readonly property string trackTitle: {
        var p = root.activePlayer;
        if (!p)
            return "";
        return String(p.trackTitle || "").trim();
    }

    readonly property string trackArtist: {
        var p = root.activePlayer;
        if (!p)
            return "";
        var artist = String(p.trackArtist || "").trim();
        if (artist.length > 0)
            return artist;
        // Fall back to album artist.
        try {
            return String(p.trackAlbumArtist || "").trim();
        } catch (e) {
            return "";
        }
    }

    readonly property string trackArtUrl: {
        var p = root.activePlayer;
        if (!p)
            return "";
        try {
            return String(p.trackArtUrl || "");
        } catch (e) {
            return "";
        }
    }

    readonly property bool canPlayPause: {
        var p = root.activePlayer;
        return !!p && (!!p.canPause || !!p.canPlay);
    }

    readonly property bool canNext: {
        var p = root.activePlayer;
        return !!p && !!p.canGoNext;
    }

    readonly property bool canPrev: {
        var p = root.activePlayer;
        return !!p && !!p.canGoPrevious;
    }

    function togglePlayPause() {
        var p = root.activePlayer;
        if (!p)
            return;
        try {
            if (p.canTogglePlaying)
                p.togglePlaying();
            else if (root.isPlaying && p.canPause)
                p.pause();
            else if (!root.isPlaying && p.canPlay)
                p.play();
        } catch (e) {}
    }

    function next() {
        var p = root.activePlayer;
        if (!p || !p.canGoNext)
            return;
        try { p.next(); } catch (e) {}
    }

    function previous() {
        var p = root.activePlayer;
        if (!p || !p.canGoPrevious)
            return;
        try { p.previous(); } catch (e) {}
    }

    Timer {
        interval: 1000
        running: root.activePlayer && root.isPlaying && root.trackPositionSupported
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var p = root.activePlayer;
            if (!p)
                return;
            try {
                p.positionChanged();
            } catch (e) {}
        }
    }

    Connections {
        target: root.commandRunner
        ignoreUnknownSignals: true

        function onRevisionChanged() {
            root.syncCommandDependencies();
        }
    }
}
