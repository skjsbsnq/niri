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

QtObject {
    id: root

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

    Component.onCompleted: root.refreshBrightness()

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

    readonly property var wifiDevice: {
        try {
            var devices = Networking.devices;
            if (!devices || !devices.values)
                return null;
            for (var i = 0; i < devices.values.length; i++) {
                var d = devices.values[i];
                if (d && String(d.type || "") === "wifi")
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
            return root.wifiEnabled ? "Not Connected" : "Off";
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
        return "Connected";
    }

    function toggleWifi() {
        try {
            Networking.wifiEnabled = !Networking.wifiEnabled;
        } catch (e) {}
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

    function toggleBluetooth() {
        var a = root.bluetoothAdapter;
        if (!a)
            return;
        try {
            a.enabled = !a.enabled;
        } catch (e) {}
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
