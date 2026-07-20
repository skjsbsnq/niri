pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Fan control service using the open-source NBFC/NBFC-Linux command line.
// The UI remains visible when NBFC is missing so the user can see which
// backend must be installed/configured for their laptop model.
//
// Shell gates continuous polling via pollingActive (popups open). Top-bar
// availability still needs a one-shot bootstrap on startup so the icon is not
// stuck grey until the first hover/click opens the fan popup.
Item {
    id: root
    visible: false

    property bool backendAvailable: false
    property bool pollingActive: true
    // One-shot startup probe chain: allows detect/service/status even while
    // shell.servicePollingActive is false. Cleared after the first complete
    // probe path so continuous timers stay activity-gated.
    property bool bootstrapPending: true
    // During bootstrap, briefly re-check systemd if nbfc is still activating
    // so a racing boot does not freeze the icon grey until the user opens the popup.
    property int bootstrapServiceRetries: 0
    readonly property int bootstrapServiceRetryLimit: 4
    property bool controlEnabled: false
    property bool available: false
    property bool updating: false
    property bool autoMode: true
    property int speedPercent: 0
    property int targetPercent: 0
    property int manualPercent: 50
    property int pendingManualPercent: -1
    property string backendName: ""
    property string temperatureText: ""
    property string statusText: "检测中"
    property string errorText: ""

    readonly property int effectivePercent: targetPercent > 0 ? targetPercent : speedPercent
    readonly property bool canProbe: root.pollingActive || root.bootstrapPending

    function setValue(name, value) {
        if (root[name] !== value)
            root[name] = value;
    }

    function clampPercent(value) {
        var n = Math.round(Number(value));
        if (!isFinite(n))
            n = 0;
        return Math.max(0, Math.min(100, n));
    }

    function finishBootstrap() {
        if (!root.bootstrapPending)
            return;
        root.bootstrapPending = false;
        root.bootstrapServiceRetries = 0;
        if (bootstrapServiceRetryTimer.running)
            bootstrapServiceRetryTimer.stop();
        if (bootstrapWatchdog.running)
            bootstrapWatchdog.stop();
    }

    function detectBackend() {
        if (root.canProbe && !backendProbe.running)
            backendProbe.running = true;
    }

    function refresh() {
        if (!root.canProbe)
            return;

        if (!root.backendAvailable) {
            root.detectBackend();
            return;
        }
        if (!root.controlEnabled) {
            root.refreshServiceState();
            return;
        }
        if (!statusProbe.running)
            statusProbe.running = true;
    }

    function refreshServiceState() {
        if (root.canProbe && !serviceProbe.running)
            serviceProbe.running = true;
    }

    function parseBackend(path) {
        if (!root.canProbe)
            return;

        var value = String(path || "").trim();
        var detected = value.length > 0;
        // Only clear control/available when the backend result actually changes
        // the picture — avoid a grey flash if we already know the service is up.
        root.setValue("backendAvailable", detected);
        if (!detected) {
            root.setValue("controlEnabled", false);
            root.setValue("available", false);
            root.setValue("backendName", "");
            root.setValue("errorText", "需要安装并配置 nbfc-linux");
            root.setValue("statusText", "未检测到 NBFC");
            root.finishBootstrap();
            return;
        }

        root.setValue("backendName", "NBFC");
        root.setValue("errorText", "");
        if (!root.controlEnabled)
            root.setValue("statusText", "NBFC 已安装");
        Qt.callLater(root.refreshServiceState);
    }

    function parseServiceState(text) {
        if (!root.canProbe)
            return;

        var state = String(text || "").trim().toLowerCase();
        var active = state === "active";
        // systemd may report activating/reloading during early boot.
        var pending = state === "activating" || state === "reloading";

        root.setValue("controlEnabled", active);
        root.setValue("available", root.backendAvailable && active);
        root.setValue("errorText", "");
        if (active) {
            root.setValue("statusText", "NBFC 控制中");
            root.bootstrapServiceRetries = 0;
            if (bootstrapServiceRetryTimer.running)
                bootstrapServiceRetryTimer.stop();
            Qt.callLater(root.refresh);
            return;
        }

        if (pending && root.bootstrapPending
                && root.bootstrapServiceRetries < root.bootstrapServiceRetryLimit) {
            root.bootstrapServiceRetries += 1;
            root.setValue("statusText", "NBFC 启动中");
            bootstrapServiceRetryTimer.restart();
            return;
        }

        root.setValue("statusText", "BIOS 接管");
        // BIOS takeover / inactive is a terminal bootstrap state (no status probe).
        root.finishBootstrap();
    }

    function firstNumber(line) {
        var match = String(line || "").match(/(-?\d+(?:\.\d+)?)/);
        if (!match)
            return NaN;
        return parseFloat(match[1]);
    }

    function boolFromLine(line) {
        var value = String(line || "").toLowerCase();
        var match = value.match(/:\s*(true|false|yes|no|enabled|disabled|1|0)\s*$/);
        if (!match)
            return false;

        var token = match[1];
        return token === "true"
            || token === "yes"
            || token === "enabled"
            || token === "1";
    }

    function parseStatus(text) {
        if (!root.canProbe)
            return;

        var raw = String(text || "").trim();
        if (raw.length === 0) {
            root.finishBootstrap();
            return;
        }

        var lines = raw.split(/\r?\n/);
        var sawSpeed = false;
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            var lower = line.toLowerCase();

            if (lower.indexOf("auto") >= 0 && lower.indexOf("control") >= 0)
                root.setValue("autoMode", root.boolFromLine(line));

            if (lower.indexOf("target") >= 0 && lower.indexOf("fan") >= 0 && lower.indexOf("speed") >= 0) {
                var target = root.firstNumber(line);
                if (isFinite(target)) {
                    var targetPercent = root.clampPercent(target);
                    root.setValue("targetPercent", targetPercent);
                    root.setValue("manualPercent", targetPercent);
                    sawSpeed = true;
                }
            } else if (lower.indexOf("current") >= 0 && lower.indexOf("fan") >= 0 && lower.indexOf("speed") >= 0) {
                var current = root.firstNumber(line);
                if (isFinite(current)) {
                    root.setValue("speedPercent", root.clampPercent(current));
                    sawSpeed = true;
                }
            } else if (lower.indexOf("temperature") >= 0 || lower.indexOf("temp") >= 0) {
                var temp = root.firstNumber(line);
                if (isFinite(temp))
                    root.setValue("temperatureText", Math.round(temp) + "°C");
            }
        }

        root.setValue("available", true);
        root.setValue("errorText", "");
        root.setValue("statusText", sawSpeed ? "风扇状态已更新" : "NBFC 已连接");
        root.finishBootstrap();
    }

    function setAutoMode(enabled) {
        if (!root.available || root.updating)
            return;

        if (enabled) {
            root.setValue("autoMode", true);
            root.setValue("updating", true);
            fanSetter.command = ["nbfc", "set", "-a"];
            fanSetter.running = true;
            return;
        }

        root.setManualSpeed(root.effectivePercent > 0 ? root.effectivePercent : root.manualPercent);
    }

    function setControlEnabled(enabled) {
        if (!root.backendAvailable || root.updating)
            return;

        root.setValue("updating", true);
        root.setValue("errorText", "");
        if (enabled) {
            root.setValue("statusText", "正在启动 NBFC");
            serviceSetter.command = ["pkexec", "/usr/bin/nbfc", "start"];
        } else {
            root.setValue("statusText", "正在交还 BIOS");
            serviceSetter.command = ["pkexec", "/usr/bin/nbfc", "stop"];
        }
        serviceSetter.running = true;
    }

    function setManualSpeed(percent) {
        if (!root.available)
            return;

        var value = root.clampPercent(percent);
        root.setValue("autoMode", false);
        root.setValue("manualPercent", value);
        root.setValue("targetPercent", value);
        root.setValue("speedPercent", value);
        root.setValue("pendingManualPercent", value);
        manualCommitTimer.restart();
    }

    function commitManualSpeed() {
        if (root.pendingManualPercent < 0)
            return;
        if (root.updating) {
            manualCommitTimer.restart();
            return;
        }

        var value = root.pendingManualPercent;
        root.setValue("pendingManualPercent", -1);
        root.setValue("updating", true);
        fanSetter.command = ["nbfc", "set", "-s", String(value)];
        fanSetter.running = true;
    }

    Process {
        id: backendProbe
        running: false
        command: ["sh", "-c", "command -v nbfc 2>/dev/null"]
        stdout: StdioCollector {
            id: backendProbeOut
            onStreamFinished: root.parseBackend(backendProbeOut.text)
        }
        onExited: function(code, exitStatus) {
            if (!root.canProbe)
                return;
            if (code !== 0) {
                root.setValue("backendAvailable", false);
                root.setValue("controlEnabled", false);
                root.setValue("available", false);
                root.setValue("backendName", "");
                root.setValue("errorText", "需要安装并配置 nbfc-linux");
                root.setValue("statusText", "未检测到 NBFC");
                root.finishBootstrap();
            }
        }
    }

    Process {
        id: serviceProbe
        running: false
        command: ["systemctl", "is-active", "nbfc_service.service"]
        stdout: StdioCollector {
            id: serviceProbeOut
            onStreamFinished: root.parseServiceState(serviceProbeOut.text)
        }
        onExited: function(code, exitStatus) {
            if (!root.canProbe)
                return;
            // systemctl is-active exits non-zero for inactive/failed/unknown.
            // Prefer stdout; fall back to inactive when empty so bootstrap ends.
            if (code !== 0 && String(serviceProbeOut.text || "").trim().length === 0)
                root.parseServiceState("inactive");
        }
    }

    Process {
        id: statusProbe
        running: false
        command: ["nbfc", "status", "-a"]
        stdout: StdioCollector {
            id: statusProbeOut
            onStreamFinished: root.parseStatus(statusProbeOut.text)
        }
        onExited: function(code, exitStatus) {
            if (!root.bootstrapPending && !root.pollingActive)
                return;
            if (code !== 0) {
                root.setValue("statusText", "NBFC 状态不可用");
                root.setValue("errorText", "请确认 nbfc 服务已启动并选择了机型配置");
                // Keep available=true when control is already known active so the
                // top-bar icon stays solid; status text carries the error.
            }
            // Always clear bootstrap on status exit (success path may have already).
            root.finishBootstrap();
        }
    }

    Process {
        id: fanSetter
        running: false
        onExited: function(code, exitStatus) {
            root.setValue("updating", false);
            if (code !== 0)
                root.setValue("errorText", "风扇写入失败，请检查 NBFC 权限或服务状态");
            if (root.pendingManualPercent >= 0)
                manualCommitTimer.restart();
            if (root.canProbe)
                root.refresh();
        }
    }

    Process {
        id: serviceSetter
        running: false
        onExited: function(code, exitStatus) {
            root.setValue("updating", false);
            if (code !== 0)
                root.setValue("errorText", "NBFC 服务切换失败，请检查权限或服务状态");
            if (root.canProbe)
                root.refreshServiceState();
        }
    }

    Timer {
        id: manualCommitTimer
        interval: 220
        repeat: false
        onTriggered: root.commitManualSpeed()
    }

    Timer {
        id: bootstrapServiceRetryTimer
        interval: 700
        repeat: false
        onTriggered: {
            if (root.bootstrapPending && root.backendAvailable)
                root.refreshServiceState();
        }
    }

    Timer {
        id: bootstrapWatchdog
        // Hard ceiling so a hung probe never leaves canProbe open forever.
        interval: 12000
        repeat: false
        running: root.bootstrapPending
        onTriggered: root.finishBootstrap()
    }

    Timer {
        id: statusRefreshTimer
        interval: 5000
        // Continuous polling stays activity-gated; bootstrap is one-shot only.
        running: root.pollingActive
        repeat: true
        onTriggered: root.refresh()
    }

    onPollingActiveChanged: {
        if (root.pollingActive) {
            root.refresh();
        } else if (!root.bootstrapPending) {
            // Do not cancel in-flight bootstrap probes when shell activity drops.
            if (backendProbe.running)
                backendProbe.running = false;
            if (serviceProbe.running)
                serviceProbe.running = false;
            if (statusProbe.running)
                statusProbe.running = false;
        }
    }

    Component.onCompleted: {
        // Always start the one-shot availability probe so the top-bar icon
        // reflects NBFC state without requiring the fan popup to open first.
        if (root.canProbe)
            root.detectBackend();
    }
}
