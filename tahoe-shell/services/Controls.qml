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
    // brightnessctl prints "<device> <brightness> <max>" with `-m`, e.g.
    //   "intel_backlight 45000 75000". We parse the percentage as value/max.
    // On systems without a backlight (VMs), the command exits non-zero and we
    // mark the slider unavailable but keep the UI visible.

    property real brightness: 1.0
    property bool brightnessAvailable: false
    property bool brightnessUpdating: false

    function refreshBrightness() {
        brightnessProbe.running = true;
    }

    function setBrightness(value) {
        if (!brightnessAvailable)
            return;
        var v = Math.max(0.05, Math.min(1, Number(value) || 0));
        brightnessUpdating = true;
        root.brightness = v;
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
                // Expected: "intel_backlight 45000 75000\n"
                var text = String(brightnessOut.text || "").trim();
                var parts = text.split(/[,;\s]+/).filter(function (s) { return s.length > 0; });
                if (parts.length >= 3) {
                    var value = parseFloat(parts[1]);
                    var max = parseFloat(parts[2]);
                    if (isFinite(value) && isFinite(max) && max > 0) {
                        root.brightness = Math.max(0, Math.min(1, value / max));
                        root.brightnessAvailable = true;
                        return;
                    }
                }
                root.brightnessAvailable = false;
            }
        }
        onExited: function (code, exitStatus) {
            if (code !== 0)
                root.brightnessAvailable = false;
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

    // Poll brightness every 4s so external changes (Fn keys, other tools)
    // are reflected. Cheap one-shot process, not worth a longer-lived channel.
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
        root.refreshBrightness();
        root.rescanWifi();
    }

    // ------------------------------------------------------------------
    // Wi-Fi
    // ------------------------------------------------------------------

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

    function setWifiEnabled(enabled) {
        try {
            Networking.wifiEnabled = !!enabled;
        } catch (e) {}
        if (enabled)
            Qt.callLater(function() { root.rescanWifi(); });
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

        try {
            if (psk && psk.length > 0 && network.connectWithPsk && (!entry || entry.pskSupported !== false)) {
                network.connectWithPsk(psk);
                return;
            }
            if ((!psk || psk.length === 0) && network.connect) {
                network.connect();
                return;
            }
        } catch (e) {
            console.warn("[Controls] wifi connect failed, falling back to nmcli:", e);
        }

        var ssid = entry && entry.name ? entry.name : String(network.name || "");
        if (ssid.length === 0)
            return;

        var command = ["nmcli", "device", "wifi", "connect", ssid];
        if (psk && psk.length > 0)
            command.push("password", psk);
        Quickshell.execDetached({ command: command });
    }

    function disconnectWifi() {
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
        onTriggered: root.rescanWifi()
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

    readonly property int bluetoothConnectedCount: {
        try {
            var devs = Bluetooth.devices;
            return devs && devs.values ? devs.values.length : 0;
        } catch (e) {
            return 0;
        }
    }

    function setBluetoothEnabled(enabled) {
        var a = root.bluetoothAdapter;
        if (!a)
            return;
        try {
            a.enabled = !!enabled;
        } catch (e) {}
    }

    function toggleBluetooth() {
        if (!root.bluetoothAvailable)
            return;

        root.airplaneMode = false;
        setBluetoothEnabled(!root.bluetoothEnabled);
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
            if (players && players.values && players.values.length > 0)
                return players.values[0];
        } catch (e) {}
        return null;
    }

    readonly property bool hasMedia: !!activePlayer

    readonly property bool isPlaying: {
        var p = root.activePlayer;
        if (!p)
            return false;
        try {
            return p.playbackState === MprisPlaybackState.Playing;
        } catch (e) {
            return false;
        }
    }

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
}
