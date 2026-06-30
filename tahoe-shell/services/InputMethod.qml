pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property bool available: false
    property bool active: false
    property int stateCode: 0
    property string currentName: ""
    property bool updating: false
    property string errorText: ""
    property var commandRunner
    readonly property string displayText: !available ? "--" : (active ? languageLabel(currentName) : "EN")
    readonly property string tooltipText: !available
        ? (errorText.length > 0 ? errorText : "输入法不可用")
        : (active ? (currentName.length > 0 ? currentName : "中文输入") : "英文输入")

    function languageLabel(name) {
        var text = String(name || "").toLowerCase();
        if (text.indexOf("pinyin") !== -1 || text.indexOf("rime") !== -1
                || text.indexOf("wubi") !== -1 || text.indexOf("zh") !== -1
                || /[\u4e00-\u9fff]/.test(text))
            return "中";
        return "中";
    }

    function refresh() {
        if (commandRunner && commandRunner.revision === 0)
            commandRunner.refreshDependencies();
        if (!probe.running)
            probe.running = true;
    }

    function toggle() {
        if (!available)
            return;

        if (commandRunner && commandRunner.revision > 0 && commandRunner.missingCommands && commandRunner.missingCommands(["fcitx5-remote"]).length > 0) {
            available = false;
            active = false;
            errorText = "缺少 fcitx5-remote";
            return;
        }

        updating = true;
        toggleProcess.command = commandRunner && commandRunner.inputMethodToggleCommand ? commandRunner.inputMethodToggleCommand() : ["fcitx5-remote", "-t"];
        toggleProcess.running = true;
    }

    function applyProbe(text) {
        var line = String(text || "").trim();
        if (line.length === 0) {
            available = false;
            active = false;
            stateCode = 0;
            currentName = "";
            errorText = commandRunner && commandRunner.dependencyDetail ? commandRunner.dependencyDetail("fcitx") : "输入法不可用";
            return;
        }

        var parts = line.split("|");
        var code = Number(parts[0]) || 0;
        stateCode = code;
        available = code > 0;
        active = code === 2;
        currentName = parts.length > 1 ? parts.slice(1).join("|").trim() : "";
        errorText = available ? "" : (commandRunner && commandRunner.dependencyDetail ? commandRunner.dependencyDetail("fcitx") : "输入法不可用");
    }

    Process {
        id: probe
        running: false
        command: root.commandRunner && root.commandRunner.inputMethodProbeCommand ? root.commandRunner.inputMethodProbeCommand() : [
            "sh",
            "-lc",
            "if ! command -v fcitx5-remote >/dev/null 2>&1; then echo '0|'; exit 0; fi; " +
            "state=\"$(fcitx5-remote 2>/dev/null || echo 0)\"; " +
            "name=\"$(fcitx5-remote -n 2>/dev/null || true)\"; " +
            "printf '%s|%s\\n' \"$state\" \"$name\""
        ]
        stdout: StdioCollector {
            id: probeOut
            onStreamFinished: root.applyProbe(probeOut.text)
        }
        onExited: function(code, exitStatus) {
            if (code !== 0)
                root.applyProbe("");
        }
    }

    Process {
        id: toggleProcess
        running: false
        command: ["fcitx5-remote", "-t"]
        onExited: function(code, exitStatus) {
            root.updating = false;
            refreshDelay.restart();
        }
    }

    Timer {
        id: refreshDelay
        interval: 180
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        interval: 1800
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: root.commandRunner
        ignoreUnknownSignals: true

        function onRevisionChanged() {
            if (!root.commandRunner.commandAvailable("fcitx5-remote")) {
                root.available = false;
                root.active = false;
                root.errorText = "缺少 fcitx5-remote";
            }
        }
    }

    Component.onCompleted: root.refresh()
}
