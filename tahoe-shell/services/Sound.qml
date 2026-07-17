pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property var commandRunner
    property bool pollingActive: true
    property bool eventSoundsMuted: false
    property var outputDevices: []
    property var inputDevices: []
    property string deviceStatus: "unknown"
    property string deviceDetail: "尚未读取 PipeWire/PulseAudio 设备"
    property bool refreshingDevices: false
    property int revision: 0

    function run(command) {
        try {
            Quickshell.execDetached({
                command: command,
                workingDirectory: ""
            });
        } catch (e) {
            console.warn("[Sound] command failed:", command, e);
        }
    }

    function setEventSoundsMuted(muted) {
        var next = !!muted;
        if (root.eventSoundsMuted === next)
            return;

        root.eventSoundsMuted = next;

        root.run([
            "gsettings",
            "set",
            "org.gnome.desktop.sound",
            "event-sounds",
            next ? "false" : "true"
        ]);
        root.run([
            "gsettings",
            "set",
            "org.gnome.desktop.sound",
            "theme-name",
            next ? "__no_sounds" : "freedesktop"
        ]);
    }

    function refreshDevices() {
        if (!root.pollingActive || deviceProbe.running)
            return;
        root.refreshingDevices = true;
        deviceProbe.running = true;
    }

    function normalizeDevice(item, type) {
        var props = item && item.properties ? item.properties : {};
        var name = String(item && item.name || "");
        var description = String(props["device.description"] || props["node.description"] || props["media.name"] || name);
        return {
            "name": name,
            "description": description.length > 0 ? description : name,
            "type": type,
            "muted": !!(item && item.mute),
            "volume": item && item.volume && item.volume["front-left"] ? Number(item.volume["front-left"].value || 0) : 0,
            "state": String(item && item.state || "")
        };
    }

    function parseDevices(text) {
        if (!root.pollingActive)
            return;

        var raw = String(text || "");
        var parts = raw.split("\n---TAHOE-SOURCES---\n");
        if (parts.length < 2) {
            root.deviceStatus = "missing";
            root.deviceDetail = raw.trim().length > 0 ? raw.trim().split(/\r?\n/)[0] : "pactl 不可用";
            root.outputDevices = [];
            root.inputDevices = [];
            root.revision += 1;
            return;
        }

        try {
            var sinks = JSON.parse(parts[0] || "[]");
            var sources = JSON.parse(parts[1] || "[]");
            var out = [];
            var ins = [];
            for (var i = 0; i < sinks.length; i++)
                out.push(root.normalizeDevice(sinks[i], "sink"));
            for (var j = 0; j < sources.length; j++) {
                var source = sources[j];
                if (source && String(source.name || "").indexOf(".monitor") >= 0)
                    continue;
                ins.push(root.normalizeDevice(source, "source"));
            }
            root.outputDevices = out;
            root.inputDevices = ins;
            root.deviceStatus = "ok";
            root.deviceDetail = out.length + " 个输出设备，" + ins.length + " 个输入设备";
        } catch (e) {
            root.deviceStatus = "error";
            root.deviceDetail = "音频设备解析失败：" + String(e);
            root.outputDevices = [];
            root.inputDevices = [];
        }
        root.revision += 1;
    }

    function setDefaultOutput(device) {
        if (!device || !device.name)
            return;
        if (root.commandRunner && root.commandRunner.runDetached) {
            root.commandRunner.runDetached("sound.default-output", ["pactl", "set-default-sink", String(device.name || "")], ["pactl"], {
                "missingMessage": "音频输出切换不可用",
                "missingDetail": "需要 pactl",
                "successMessage": "已请求切换默认输出"
            });
        } else {
            root.run(["pactl", "set-default-sink", String(device.name || "")]);
        }
        refreshTimer.restart();
    }

    function setDefaultInput(device) {
        if (!device || !device.name)
            return;
        if (root.commandRunner && root.commandRunner.runDetached) {
            root.commandRunner.runDetached("sound.default-input", ["pactl", "set-default-source", String(device.name || "")], ["pactl"], {
                "missingMessage": "音频输入切换不可用",
                "missingDetail": "需要 pactl",
                "successMessage": "已请求切换默认输入"
            });
        } else {
            root.run(["pactl", "set-default-source", String(device.name || "")]);
        }
        refreshTimer.restart();
    }

    Process {
        id: deviceProbe
        running: false
        command: ["sh", "-lc", "command -v pactl >/dev/null 2>&1 || { echo '缺少 pactl'; exit 0; }; pactl -f json list sinks 2>/dev/null; printf '\\n---TAHOE-SOURCES---\\n'; pactl -f json list sources 2>/dev/null"]
        stdout: StdioCollector {
            id: deviceOut
            onStreamFinished: root.parseDevices(deviceOut.text)
        }
        onExited: function(code, exitStatus) {
            root.refreshingDevices = false;
            if (root.pollingActive && code !== 0 && root.deviceStatus !== "ok") {
                root.deviceStatus = "error";
                root.deviceDetail = "音频设备读取失败，退出码 " + String(code);
                root.revision += 1;
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 1200
        repeat: false
        onTriggered: root.refreshDevices()
    }

    Timer {
        id: deviceRefreshTimer
        interval: 15000
        running: root.pollingActive
        repeat: true
        onTriggered: root.refreshDevices()
    }

    onPollingActiveChanged: {
        if (root.pollingActive) {
            root.refreshDevices();
        } else {
            refreshTimer.stop();
            if (deviceProbe.running)
                deviceProbe.running = false;
            root.refreshingDevices = false;
        }
    }

    Component.onCompleted: {
        if (root.pollingActive)
            root.refreshDevices();
    }
}
