pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// T-29 / F-11+F-12: ControlCenter panel-level Escape close and the
// brightnessErrorText binding. The panel is click-focusable while open
// (focusable: open); the runtime assertions below verify the panel surface
// flips to focusable and that the brightness error row becomes visible with
// the service's explanation when brightness is unavailable (VM / no backlight).
ShellRoot {
    id: probe

    property string panelSource: ""
    property var panel: null
    property int stage: 0

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
        property var wifiNetworks: []
        property var bluetoothDeviceEntries: []
        property bool wifiEnabled: false
        property bool wifiAvailable: false
        property bool wifiConnected: false
        property bool wifiScanning: false
        property string wifiName: ""
        property int wifiSignalPercent: 0
        property var activeWifiNetwork: null
        property bool bluetoothEnabled: false
        property bool bluetoothAvailable: false
        property bool bluetoothScanning: false
        property bool airplaneMode: false
        property bool brightnessAvailable: false
        property string brightnessErrorText: "缺少 brightnessctl"
        property real brightness: 0
        property bool audioReady: true
        property bool muted: false
        property real volume: 0
        property string wifiSsid: ""
        property string wifiStatus: ""
        property bool wifiBusy: false
        property bool bluetoothBusy: false
        property bool hasMedia: false
        property bool isPlaying: false
        property string trackTitle: ""
        property string trackArtist: ""
        property string trackArtUrl: ""
        property bool canPlayPause: false
        property bool canPrev: false
        property bool canNext: false

        function bluetoothDiscoveryOwned(owner) { return false; }
        function rescanWifi() {}
        function setBluetoothDiscoveryActive(owner, active) {}
        function toggleBluetoothDiscovery(owner) {}
        function previewBrightness(v) {}
        function commitBrightness(v) {}
        function setVolume(v) {}
        function toggleMute() {}
        function toggleWifi() {}
        function toggleBluetooth() {}
        function toggleAirplaneMode() {}
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

    function require(condition, message) {
        if (condition)
            return true;
        console.error("CC_ESCAPE_BRIGHTNESS_FAIL: " + message);
        cleanup();
        Qt.exit(1);
        return false;
    }

    function schedule(nextStage, delayMs) {
        stage = nextStage;
        stepTimer.interval = Math.max(1, delayMs);
        stepTimer.restart();
    }

    function findByName(obj, name, depth) {
        if (!obj || depth > 60)
            return null;
        if (obj.objectName === name)
            return obj;
        var result = null;
        var kids = obj.children;
        if (kids) {
            for (var i = 0; i < kids.length; i++) {
                result = findByName(kids[i], name, depth + 1);
                if (result)
                    return result;
            }
        }
        if (obj.contentItem && obj.contentItem !== obj) {
            result = findByName(obj.contentItem, name, depth + 1);
            if (result)
                return result;
        }
        return null;
    }

    function cleanup() {
        stepTimer.stop();
        if (panel) {
            panel.destroy();
            panel = null;
        }
    }

    function finish() {
        console.log("CC_ESCAPE_BRIGHTNESS_OK");
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
            panel.open = true;
            schedule(1, 200);
            return;
        }

        if (stage === 1) {
            // F-11: the surface must be keyboard-focusable while open so the
            // Escape catcher can actually receive keys.
            if (!require(panel.focusable === true,
                    "panel focusable must be true while open, got " + panel.focusable))
                return;
            var catcher = findByName(panel, "controlCenterKeyboardFocusCatcher");
            if (!require(catcher !== null, "Escape focus catcher not found")
                    || !require(catcher.focus === true,
                        "Escape catcher must own QML focus while open"))
                return;

            // F-12: brightness unavailable → the error row is visible and
            // explains why the slider is disabled.
            var errorText = findByName(panel, "brightnessErrorText");
            if (!require(errorText !== null, "brightnessErrorText row not found"))
                return;
            if (!require(errorText.visible === true,
                    "brightness error row must be visible when errorText is set"))
                return;
            var shown = String(errorText.text || "");
            if (!require(shown.indexOf("缺少 brightnessctl") >= 0,
                    "brightness error row must surface the service message, got '"
                    + shown + "'"))
                return;
            if (!require(shown.indexOf("亮度不可用") >= 0,
                    "brightness error row must prefix the explanation, got '"
                    + shown + "'"))
                return;

            // Closing the panel flips focusable back off (no stray grab).
            panel.open = false;
            schedule(2, 80);
            return;
        }

        if (stage === 2) {
            if (!require(panel.focusable === false,
                    "panel focusable must drop back to false when closed, got "
                    + panel.focusable))
                return;
            finish();
            return;
        }
    }

    Component.onCompleted: schedule(0, 40)
}
