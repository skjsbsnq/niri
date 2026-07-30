pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// T-23 / S-M2: the ControlCenter panel height must move monotonically across a
// module morph. Before the fix, the sibling stack (sliders + utilities) dropped
// to height 0 on the first morph frame while morphHost was still growing, so the
// glass panel's bottom edge jumped ~150-250px and then came back.
//
// Runs the production ControlCenter.qml under the Tahoe Quickshell runtime (real
// PanelWindow / ScriptModel / TahoeGlassRegion), samples panel.implicitHeight
// each frame and asserts the sequence never reverses direction.
ShellRoot {
    id: probe

    property string panelSource: ""
    property var panel: null
    property int stage: 0
    property var samples: []
    property real expandedHeight: 0
    property real collapsedHeight: 0
    property int frameSamples: 0
    // False when the component under test predates the single morph clock. The
    // geometry assertions below work on any implementation, so the probe can be
    // pointed at an older ControlCenter.qml to confirm it actually detects the
    // S-M2 dive (it reports the 312 → 132 first-frame drop) rather than merely
    // detecting that a property was renamed.
    property bool hasClock: false

    function clockAt(expected, label) {
        if (!hasClock)
            return true;
        return require(Math.abs(panel.morphProgress - expected) < 1e-6,
            label + ", got " + panel.morphProgress);
    }

    QtObject {
        id: settings
        property string motionProfile: "balanced"
        property string accentColor: "blue"
    }

    QtObject {
        id: appearance
        property bool darkMode: false
        property bool nightMode: false
        function toggleDarkMode() { darkMode = !darkMode; }
        function toggleNightMode() { nightMode = !nightMode; }
    }

    QtObject {
        id: controls
        property var wifiNetworks: [
            { name: "net-a", signal: 70, secure: true, active: false },
            { name: "net-b", signal: 40, secure: false, active: false }
        ]
        property var bluetoothDeviceEntries: [
            { name: "buds", address: "AA:BB", icon: "audio-headphones",
              connected: false, paired: false, device: null, dbusPath: "/d/1" }
        ]
        property bool wifiEnabled: true
        property bool wifiAvailable: true
        property bool wifiConnected: true
        property bool wifiScanning: false
        property string wifiName: "net-a"
        property int wifiSignalPercent: 70
        property var activeWifiNetwork: null
        property bool bluetoothEnabled: true
        property bool bluetoothAvailable: true
        property bool bluetoothScanning: false
        property bool airplaneMode: false
        property bool brightnessAvailable: true
        property real brightness: 0.5
        property bool audioReady: true
        property bool muted: false
        property real volume: 0.4
        property string wifiSsid: "net-a"
        property string wifiStatus: ""
        property bool wifiBusy: false
        property bool bluetoothBusy: false
        // MusicTile reads the Mpris-facing surface of services/Controls.qml.
        property bool hasMedia: true
        property bool isPlaying: false
        property string trackTitle: "song"
        property string trackArtist: "artist"
        property string trackArtUrl: ""
        property bool canPlayPause: true
        property bool canPrev: true
        property bool canNext: true

        function bluetoothDiscoveryOwned(owner) { return false; }
        function rescanWifi() {}
        function setBluetoothDiscoveryActive(owner, active) {}
        function toggleBluetoothDiscovery(owner) {}
        function previewBrightness(v) { brightness = v; }
        function commitBrightness(v) { brightness = v; }
        function setVolume(v) { volume = v; }
        function toggleMute() { muted = !muted; }
        function toggleWifi() { wifiEnabled = !wifiEnabled; }
        function toggleBluetooth() { bluetoothEnabled = !bluetoothEnabled; }
        function toggleAirplaneMode() { airplaneMode = !airplaneMode; }
        function connectWifi(ssid, psk) {}
        function disconnectWifi() {}
        function forgetWifi(ssid) {}
        function connectBluetoothDevice(entry) {}
        function disconnectBluetoothDevice(entry) {}
        function pairBluetoothDevice(entry) {}
        function togglePlayPause() {}
        function next() {}
        function previous() {}
    }

    Timer {
        id: stepTimer
        interval: 20
        repeat: false
        onTriggered: probe.advance()
    }

    // Frame-rate sampler: one implicitHeight reading per rendered frame.
    FrameAnimation {
        id: sampler
        running: false
        onTriggered: {
            if (!probe.panel)
                return;
            probe.samples = probe.samples.concat([probe.panel.implicitHeight]);
            probe.frameSamples += 1;
        }
    }

    function require(condition, message) {
        if (condition)
            return true;
        console.error("CONTROL_CENTER_MORPH_FAIL: " + message);
        cleanup();
        Qt.exit(1);
        return false;
    }

    function schedule(nextStage, delayMs) {
        stage = nextStage;
        stepTimer.interval = Math.max(1, delayMs);
        stepTimer.restart();
    }

    function startSampling() {
        // Seed with the height as it stands *before* the caller triggers the
        // morph. The defect this guards is an instantaneous drop on the very
        // first morph frame, which a sampler that only starts on the next frame
        // tick would silently adopt as its baseline.
        samples = panel ? [panel.implicitHeight] : [];
        frameSamples = 0;
        sampler.running = true;
    }

    function stopSampling() {
        sampler.running = false;
        return samples;
    }

    // Assert the sampled sequence moves straight from its first to its last
    // value: never against the measured direction, and never outside the
    // endpoint band.
    //
    // The two endpoints are close together (312 collapsed vs 300 expanded with
    // the default token set) because the module host grows by almost exactly
    // what the sibling stack gives up. That makes the *band* the load-bearing
    // check: the pre-fix code dropped the sibling stack to height 0 on frame one
    // while morphHost was still growing, so the series dived ~190px below both
    // endpoints before climbing back.
    //
    // Tolerance is 1.5px because ColumnLayout rounds each child's height
    // independently, so the sum of the two morph-driven terms can wobble by a
    // pixel between frames. The defect being guarded is two orders of magnitude
    // larger than that.
    function assertStraightTravel(series, label) {
        if (!require(series.length >= 6,
                label + ": expected several frames, got " + series.length))
            return false;
        var tolerance = 1.5;
        var start = series[0];
        var end = series[series.length - 1];
        var low = Math.min(start, end) - tolerance;
        var high = Math.max(start, end) + tolerance;
        var rising = end >= start;

        for (var i = 0; i < series.length; i++) {
            if (!require(series[i] >= low && series[i] <= high,
                    label + ": frame " + i + " left the endpoint band ["
                    + low.toFixed(2) + ", " + high.toFixed(2) + "] at "
                    + series[i].toFixed(2)))
                return false;
        }
        for (var j = 1; j < series.length; j++) {
            var delta = series[j] - series[j - 1];
            if (rising) {
                if (!require(delta > -tolerance,
                        label + ": height fell mid-travel at frame " + j + " ("
                        + series[j - 1].toFixed(2) + " → " + series[j].toFixed(2) + ")"))
                    return false;
            } else {
                if (!require(delta < tolerance,
                        label + ": height rose mid-travel at frame " + j + " ("
                        + series[j - 1].toFixed(2) + " → " + series[j].toFixed(2) + ")"))
                    return false;
            }
        }
        return true;
    }

    function cleanup() {
        stepTimer.stop();
        sampler.running = false;
        if (panel) {
            panel.destroy();
            panel = null;
        }
    }

    function finish() {
        console.log("CONTROL_CENTER_MORPH_OK");
        cleanup();
        Qt.quit();
    }

    function advance() {
        if (stage === 0) {
            if (!require(panelSource.length > 0, "panelSource was not injected"))
                return;
            var component = Qt.createComponent("file://" + panelSource);
            if (!require(component.status === Component.Ready,
                    "ControlCenter compile: " + component.errorString()))
                return;
            panel = component.createObject(null, {
                "controlsService": controls,
                "settingsService": settings,
                "appearanceService": appearance
            });
            if (!require(panel !== null, "ControlCenter creation"))
                return;
            hasClock = panel.morphProgress !== undefined;
            panel.open = true;
            schedule(1, 200);
            return;
        }

        if (stage === 1) {
            collapsedHeight = panel.implicitHeight;
            if (!require(collapsedHeight > 100,
                    "collapsed panel has real height, got " + collapsedHeight)
                    || !clockAt(0, "morph clock rests at 0"))
                return;
            startSampling();
            panel.openModule("wifi");
            schedule(2, 520);
            return;
        }

        if (stage === 2) {
            var expandSeries = stopSampling();
            if (!assertStraightTravel(expandSeries, "expand"))
                return;
            expandedHeight = panel.implicitHeight;
            // At rest the expanded panel is exactly the module host plus the
            // glass padding: the sibling host and its gap are fully collapsed.
            // The two endpoints are close together (312 vs 300 by default),
            // which is why the dive has to be caught as a band excursion rather
            // than as a direction reversal.
            if (!require(Math.abs(expandedHeight - (panel.expandedTopHeight + 28)) < 1.5,
                    "expanded rest height is host + padding, expected "
                    + (panel.expandedTopHeight + 28) + " got " + expandedHeight)
                    || !clockAt(1, "morph clock reaches 1"))
                return;
            startSampling();
            panel.closeModule();
            schedule(3, 520);
            return;
        }

        if (stage === 3) {
            var collapseSeries = stopSampling();
            if (!assertStraightTravel(collapseSeries, "collapse"))
                return;
            if (!require(Math.abs(panel.implicitHeight - collapsedHeight) < 1.5,
                    "collapse returns to rest height: " + collapsedHeight
                    + " → " + panel.implicitHeight)
                    || !clockAt(0, "morph clock returns to 0"))
                return;
            // Bluetooth module travels the same path.
            startSampling();
            panel.openModule("bluetooth");
            schedule(4, 520);
            return;
        }

        if (stage === 4) {
            if (!assertStraightTravel(stopSampling(), "expand-bluetooth"))
                return;
            // Dismissing the panel mid-morph must snap the clock to rest, not
            // leave a partial progress that replays on the next open.
            panel.open = false;
            schedule(5, 60);
            return;
        }

        if (stage === 5) {
            if (!require(panel.expandedModule === "",
                    "closing clears expandedModule, got '" + panel.expandedModule + "'")
                    || !clockAt(0, "closed panel snaps morph clock to rest"))
                return;
            panel.open = true;
            schedule(6, 80);
            return;
        }

        if (stage === 6) {
            if (!clockAt(0, "reopened panel starts collapsed")
                    || !require(Math.abs(panel.implicitHeight - collapsedHeight) < 1.5,
                        "reopened panel starts at rest height: " + collapsedHeight
                        + " → " + panel.implicitHeight))
                return;
            // 「编辑控制项」grow must still animate while the morph clock is at
            // rest — the sibling host must not pin the stack's natural height.
            var beforeEdit = panel.implicitHeight;
            panel.controlsExpanded = true;
            schedule(7, 40);
            expandedHeight = beforeEdit;
            return;
        }

        if (stage === 7) {
            var midEdit = panel.implicitHeight;
            if (!require(midEdit > expandedHeight,
                    "edit-controls row grows the panel: " + expandedHeight
                    + " → " + midEdit)
                    || !require(midEdit < expandedHeight + 50,
                        "edit-controls growth is animated, not instant: +"
                        + (midEdit - expandedHeight)))
                return;
            schedule(8, 400);
            return;
        }

        if (stage === 8) {
            if (!require(panel.implicitHeight > expandedHeight + 40,
                    "edit-controls row reaches full height: "
                    + panel.implicitHeight))
                return;
            finish();
            return;
        }
    }

    Component.onCompleted: schedule(0, 40)
}
