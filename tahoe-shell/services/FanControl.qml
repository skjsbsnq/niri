pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Fan control service using the open-source NBFC/NBFC-Linux command line.
// The UI remains visible when NBFC is missing so the user can see which
// backend must be installed/configured for their laptop model.
Item {
    id: root
    visible: false

    property bool backendAvailable: false
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

    function detectBackend() {
        if (!backendProbe.running)
            backendProbe.running = true;
    }

    function refresh() {
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
        if (!serviceProbe.running)
            serviceProbe.running = true;
    }

    function parseBackend(path) {
        var value = String(path || "").trim();
        var detected = value.length > 0;
        root.setValue("backendAvailable", detected);
        root.setValue("controlEnabled", false);
        root.setValue("available", false);
        root.setValue("backendName", detected ? "NBFC" : "");
        root.setValue("errorText", detected ? "" : "需要安装并配置 nbfc-linux");
        root.setValue("statusText", detected ? "NBFC 已安装" : "未检测到 NBFC");
        if (detected)
            Qt.callLater(root.refreshServiceState);
    }

    function parseServiceState(text) {
        var active = String(text || "").trim() === "active";
        root.setValue("controlEnabled", active);
        root.setValue("available", root.backendAvailable && active);
        root.setValue("errorText", "");
        root.setValue("statusText", active ? "NBFC 控制中" : "BIOS 接管");
        if (active)
            Qt.callLater(root.refresh);
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
        var raw = String(text || "").trim();
        if (raw.length === 0)
            return;

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
            if (code !== 0) {
                root.setValue("backendAvailable", false);
                root.setValue("controlEnabled", false);
                root.setValue("available", false);
                root.setValue("backendName", "");
                root.setValue("errorText", "需要安装并配置 nbfc-linux");
                root.setValue("statusText", "未检测到 NBFC");
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
            if (code !== 0) {
                root.setValue("statusText", "NBFC 状态不可用");
                root.setValue("errorText", "请确认 nbfc 服务已启动并选择了机型配置");
            }
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
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.detectBackend()
}
