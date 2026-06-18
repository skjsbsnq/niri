pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Wayland clipboard history backed by cliphist. Selecting an item decodes it
// back into the current clipboard through wl-copy.
Item {
    id: root
    visible: false

    property bool cliphistAvailable: false
    property bool wlCopyAvailable: false
    property bool wlPasteAvailable: false
    property bool updating: false
    property var entries: []
    property string statusText: "检测中"
    property string errorText: ""
    property bool listLoaded: false
    property string lastListText: ""

    readonly property bool available: cliphistAvailable && wlCopyAvailable
    readonly property int historyCount: entries ? entries.length : 0

    function setValue(name, value) {
        if (root[name] !== value)
            root[name] = value;
    }

    function clearEntries() {
        if (root.entries.length > 0)
            root.entries = [];
    }

    function detectTools() {
        if (!toolProbe.running)
            toolProbe.running = true;
    }

    function refresh() {
        if (!root.cliphistAvailable) {
            root.detectTools();
            return;
        }
        if (!listProbe.running) {
            root.updating = true;
            listProbe.running = true;
        }
    }

    function scheduleRefresh() {
        refreshTimer.restart();
    }

    function updateListStatus(count) {
        root.setValue("statusText", count > 0 ? (count + " 项") : "暂无历史");
    }

    function parseTools(text) {
        var lines = String(text || "").split(/\r?\n/);
        root.cliphistAvailable = lines.indexOf("cliphist") >= 0;
        root.wlCopyAvailable = lines.indexOf("wl-copy") >= 0;
        root.wlPasteAvailable = lines.indexOf("wl-paste") >= 0;

        if (!root.cliphistAvailable)
            root.errorText = "需要安装 cliphist";
        else if (!root.wlCopyAvailable)
            root.errorText = "需要安装 wl-clipboard";
        else
            root.errorText = "";

        root.statusText = root.available ? "剪贴板历史可用" : "剪贴板历史不可用";

        if (root.cliphistAvailable && root.wlPasteAvailable)
            root.startWatcher();
        if (root.cliphistAvailable)
            Qt.callLater(root.refresh);
    }

    function parseList(text) {
        var normalizedText = String(text || "");
        if (root.listLoaded && normalizedText === root.lastListText) {
            root.updateListStatus(root.entries ? root.entries.length : 0);
            return;
        }

        root.listLoaded = true;
        root.lastListText = normalizedText;

        var rawLines = normalizedText.split(/\r?\n/);
        var out = [];
        for (var i = 0; i < rawLines.length && out.length < 60; i++) {
            var line = rawLines[i];
            if (!line || line.length === 0)
                continue;

            var preview = line.replace(/^\s*\d+\s+/, "");
            preview = preview.replace(/\t/g, " ").replace(/\s+/g, " ").trim();
            if (preview.length === 0)
                preview = "空项目";
            if (preview.length > 180)
                preview = preview.slice(0, 177) + "...";

            var lower = preview.toLowerCase();
            var binary = lower.indexOf("binary data") >= 0
                || lower.indexOf("image/") >= 0
                || lower.indexOf("application/") >= 0;

            out.push({
                "raw": line,
                "preview": preview,
                "icon": binary ? "\ue3f4" : "\ue14f"
            });
        }

        root.entries = out;
        root.updateListStatus(out.length);
    }

    function startWatcher() {
        if (clipboardWatcher.running)
            return;

        clipboardWatcher.running = true;
    }

    function copyEntry(entry) {
        if (!entry || !entry.raw || !root.available)
            return;

        root.statusText = "已复制";
        Quickshell.execDetached({
            command: ["sh", "-c", "printf %s \"$1\" | cliphist decode | wl-copy", "sh", entry.raw],
            workingDirectory: ""
        });
    }

    function deleteEntry(entry) {
        if (!entry || !entry.raw || !root.cliphistAvailable)
            return;

        root.statusText = "已删除";
        Quickshell.execDetached({
            command: ["sh", "-c", "printf %s \"$1\" | cliphist delete", "sh", entry.raw],
            workingDirectory: ""
        });
        root.scheduleRefresh();
    }

    function clearHistory() {
        if (!root.cliphistAvailable)
            return;

        root.listLoaded = false;
        root.lastListText = "";
        root.clearEntries();
        root.setValue("statusText", "已清空");
        Quickshell.execDetached({
            command: ["cliphist", "wipe"],
            workingDirectory: ""
        });
        root.scheduleRefresh();
    }

    Process {
        id: toolProbe
        running: false
        command: [
            "sh",
            "-c",
            "command -v cliphist >/dev/null 2>&1 && echo cliphist; command -v wl-copy >/dev/null 2>&1 && echo wl-copy; command -v wl-paste >/dev/null 2>&1 && echo wl-paste"
        ]
        stdout: StdioCollector {
            id: toolProbeOut
            onStreamFinished: root.parseTools(toolProbeOut.text)
        }
    }

    Process {
        id: listProbe
        running: false
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            id: listProbeOut
            onStreamFinished: root.parseList(listProbeOut.text)
        }
        onExited: function(code, exitStatus) {
            root.updating = false;
            if (code !== 0) {
                root.listLoaded = false;
                root.lastListText = "";
                root.clearEntries();
                root.setValue("statusText", "暂无历史");
            }
        }
    }

    Process {
        id: clipboardWatcher
        running: false
        command: ["wl-paste", "--watch", "cliphist", "store"]
        onExited: function(code, exitStatus) {
            if (root.cliphistAvailable && root.wlPasteAvailable)
                watcherRestartTimer.restart();
        }
    }

    Timer {
        id: watcherRestartTimer
        interval: 1200
        repeat: false
        onTriggered: root.startWatcher()
    }

    Timer {
        id: refreshTimer
        interval: 450
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.detectTools()
}
