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
    property bool pollingActive: true
    property bool initialProbePending: false
    readonly property string displayText: !available ? "--" : (active ? languageLabel(currentName) : "EN")
    readonly property string tooltipText: !available
        ? (errorText.length > 0 ? errorText : "输入法不可用")
        : (active ? (currentName.length > 0 ? currentName : "中文输入") : "英文输入")

    // Single label entry for the top-bar / chip language glyph.
    // Maps common fcitx engine names; unknown engines use a non-Chinese fallback.
    // Order: Japanese/Korean scripts & engines first so shared CJK ideographs
    // (e.g. 日本語) are not mislabeled as Chinese.
    function languageLabel(name) {
        var raw = String(name || "");
        var text = raw.toLowerCase().trim();
        if (text.length === 0)
            return "Aa";

        // Japanese (mozc / anthy / skk / kkc / ja* / kana / kanji+kana names).
        if (text.indexOf("mozc") !== -1 || text.indexOf("anthy") !== -1
                || text.indexOf("kkc") !== -1 || text.indexOf("skk") !== -1
                || text.indexOf("japanese") !== -1 || text.indexOf("japan") !== -1
                || text.indexOf("ja-") !== -1 || text.indexOf("ja_") !== -1
                || text === "ja" || text.indexOf("nihongo") !== -1
                || /[\u3040-\u30ff]/.test(raw)
                || (text.indexOf("\u65e5\u672c") !== -1))  // 日本
            return "\u3042";  // あ

        // Korean (hangul / ko* / Hangul syllables in name).
        if (text.indexOf("hangul") !== -1 || text.indexOf("libhangul") !== -1
                || text.indexOf("korean") !== -1 || text.indexOf("korea") !== -1
                || text.indexOf("ko-") !== -1 || text.indexOf("ko_") !== -1
                || text === "ko"
                || /[\uac00-\ud7af]/.test(raw))
            return "\ud55c";  // 한

        // Chinese (pinyin / rime / wubi / zh* / Chinese-script names without JA/KO).
        if (text.indexOf("pinyin") !== -1 || text.indexOf("rime") !== -1
                || text.indexOf("wubi") !== -1 || text.indexOf("zhuyin") !== -1
                || text.indexOf("cangjie") !== -1 || text.indexOf("chinese") !== -1
                || text.indexOf("zh-") !== -1 || text.indexOf("zh_") !== -1
                || text === "zh" || text.indexOf("zh ") !== -1
                || text === "cn" || text.indexOf("cn-") === 0 || text.indexOf("cn_") === 0
                || /[\u4e00-\u9fff]/.test(raw))
            return "\u4e2d";  // 中

        // Explicit English / latin keyboard engines.
        if (text.indexOf("english") !== -1 || text.indexOf("keyboard-us") !== -1
                || text.indexOf("keyboard-uk") !== -1 || text === "us"
                || text === "en" || text.indexOf("en-") === 0
                || text.indexOf("en_") === 0)
            return "EN";

        // Non-misleading fallback: never claim Chinese for unknown engines.
        return "Aa";
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
        if (!root.pollingActive && !root.initialProbePending)
            return;

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
            var mayPublish = root.pollingActive || root.initialProbePending;
            if (code !== 0 && mayPublish)
                root.applyProbe("");
            root.initialProbePending = false;
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
        id: statusPollTimer
        interval: 1800
        running: root.pollingActive
        repeat: true
        onTriggered: root.refresh()
    }

    onPollingActiveChanged: {
        if (root.pollingActive) {
            root.refresh();
        } else if (!root.initialProbePending) {
            refreshDelay.stop();
            if (probe.running)
                probe.running = false;
        }
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

    Component.onCompleted: {
        root.initialProbePending = true;
        root.refresh();
    }
}
