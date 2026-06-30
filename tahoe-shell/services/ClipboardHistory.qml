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
    property bool loadingPinnedState: false
    property bool pinning: false
    property string pendingPinRaw: ""
    property string pendingPinPreview: ""
    property string pendingPinIcon: "\ue14f"
    property var pinnedEntries: []
    property var commandRunner

    readonly property bool available: cliphistAvailable && wlCopyAvailable
    readonly property int historyCount: entries ? entries.length : 0
    readonly property int pinnedCount: pinnedEntries ? pinnedEntries.length : 0
    readonly property int maxPinnedEntries: 40
    readonly property int maxPinnedTextChars: 131072
    readonly property string textMimeType: "text/plain;charset=utf-8"
    readonly property string pinnedStatePath: Quickshell.stateDir + "/clipboard-pins.json"

    function setValue(name, value) {
        if (root[name] !== value)
            root[name] = value;
    }

    function clearEntries() {
        if (root.entries.length > 0)
            root.entries = [];
    }

    function previewForText(text) {
        var preview = String(text || "").replace(/\t/g, " ").replace(/\s+/g, " ").trim();
        if (preview.length === 0)
            preview = "空文本";
        if (preview.length > 180)
            preview = preview.slice(0, 177) + "...";
        return preview;
    }

    function sanitizedPins(values) {
        var result = [];
        var seen = [];
        var list = Array.isArray(values) ? values : [];

        for (var i = 0; i < list.length && result.length < root.maxPinnedEntries; i++) {
            var item = list[i] || {};
            var text = String(item.text || "");
            if (text.length === 0 || text.length > root.maxPinnedTextChars)
                continue;

            if (seen.indexOf(text) >= 0)
                continue;
            seen.push(text);

            result.push({
                "text": text,
                "preview": String(item.preview || root.previewForText(text)).slice(0, 180),
                "icon": String(item.icon || "\ue14f"),
                "sourceRaw": String(item.sourceRaw || ""),
                "addedAt": String(item.addedAt || "")
            });
        }

        return result;
    }

    function loadPinnedState() {
        if (loadingPinnedState)
            return;

        loadingPinnedState = true;
        try {
            var text = pinnedFile.text();
            if (!text || String(text).trim().length === 0) {
                root.pinnedEntries = [];
                root.writePinnedState();
                return;
            }

            var parsed = JSON.parse(String(text));
            root.pinnedEntries = root.sanitizedPins(parsed && parsed.pinned ? parsed.pinned : []);
        } catch (e) {
            root.pinnedEntries = [];
            root.writePinnedState();
        } finally {
            loadingPinnedState = false;
        }
    }

    function writePinnedState() {
        pinnedFile.setText(JSON.stringify({
            "version": 1,
            "pinned": root.sanitizedPins(root.pinnedEntries)
        }, null, 4) + "\n");
    }

    function isEntryPinned(entry) {
        if (!entry)
            return false;

        var raw = String(entry.raw || "");
        if (raw.length === 0)
            return false;

        for (var i = 0; i < root.pinnedEntries.length; i++) {
            if (String(root.pinnedEntries[i].sourceRaw || "") === raw)
                return true;
        }

        return false;
    }

    function pinnedIndexByText(text) {
        text = String(text || "");
        for (var i = 0; i < root.pinnedEntries.length; i++) {
            if (String(root.pinnedEntries[i].text || "") === text)
                return i;
        }
        return -1;
    }

    function pinnedIndexBySourceRaw(raw) {
        raw = String(raw || "");
        if (raw.length === 0)
            return -1;

        for (var i = 0; i < root.pinnedEntries.length; i++) {
            if (String(root.pinnedEntries[i].sourceRaw || "") === raw)
                return i;
        }
        return -1;
    }

    function addPinnedText(text, preview, icon, sourceRaw) {
        text = String(text || "");
        if (text.length === 0) {
            root.setValue("statusText", "无法固定空内容");
            return;
        }
        if (text.length > root.maxPinnedTextChars) {
            root.setValue("statusText", "内容过大，未固定");
            return;
        }

        var pins = root.pinnedEntries.slice();
        var existing = root.pinnedIndexByText(text);
        if (existing >= 0) {
            var current = pins[existing];
            pins[existing] = {
                "text": current.text,
                "preview": current.preview || root.previewForText(text),
                "icon": current.icon || "\ue14f",
                "sourceRaw": String(sourceRaw || current.sourceRaw || ""),
                "addedAt": current.addedAt || new Date().toISOString()
            };
            root.pinnedEntries = root.sanitizedPins(pins);
            root.writePinnedState();
            root.setValue("statusText", "已固定过");
            return;
        }

        pins.unshift({
            "text": text,
            "preview": root.previewForText(preview && String(preview).length > 0 ? preview : text),
            "icon": String(icon || "\ue14f"),
            "sourceRaw": String(sourceRaw || ""),
            "addedAt": new Date().toISOString()
        });

        root.pinnedEntries = root.sanitizedPins(pins);
        root.writePinnedState();
        root.setValue("statusText", "已固定");
    }

    function unpinPinnedEntry(pin) {
        if (!pin)
            return;

        var text = String(pin.text || "");
        root.pinnedEntries = root.pinnedEntries.filter(function(item) {
            return String(item.text || "") !== text;
        });
        root.writePinnedState();
        root.setValue("statusText", "已取消固定");
    }

    function unpinEntry(entry) {
        var index = root.pinnedIndexBySourceRaw(entry && entry.raw ? entry.raw : "");
        if (index < 0)
            return;

        var pins = root.pinnedEntries.slice();
        pins.splice(index, 1);
        root.pinnedEntries = pins;
        root.writePinnedState();
        root.setValue("statusText", "已取消固定");
    }

    function pinEntry(entry) {
        if (!entry || !entry.raw || !root.cliphistAvailable)
            return;

        if (root.isEntryPinned(entry)) {
            root.unpinEntry(entry);
            return;
        }

        if (entry.binary || entry.pinnable === false) {
            root.setValue("statusText", "只能固定文本");
            return;
        }

        if (pinDecodeProcess.running || root.pinning) {
            root.setValue("statusText", "正在固定上一项");
            return;
        }

        root.pendingPinRaw = String(entry.raw || "");
        root.pendingPinPreview = String(entry.preview || "");
        root.pendingPinIcon = String(entry.icon || "\ue14f");
        root.pinning = true;
        root.setValue("statusText", "正在固定");
        pinDecodeProcess.running = true;
    }

    function finishPinDecode(text) {
        if (!root.pinning)
            return;

        var decoded = String(text || "");
        root.addPinnedText(decoded, root.pendingPinPreview, root.pendingPinIcon, root.pendingPinRaw);
        root.resetPinDecode();
    }

    function resetPinDecode() {
        root.pinning = false;
        root.pendingPinRaw = "";
        root.pendingPinPreview = "";
        root.pendingPinIcon = "\ue14f";
    }

    function applyCommandRunnerTools() {
        if (!root.commandRunner)
            return false;

        if (root.commandRunner.revision === 0) {
            root.commandRunner.refreshDependencies();
            return false;
        }

        root.cliphistAvailable = root.commandRunner.commandAvailable("cliphist");
        root.wlCopyAvailable = root.commandRunner.commandAvailable("wl-copy");
        root.wlPasteAvailable = root.commandRunner.commandAvailable("wl-paste");

        if (!root.cliphistAvailable)
            root.errorText = "需要安装 cliphist";
        else if (!root.wlCopyAvailable)
            root.errorText = "需要安装 wl-clipboard";
        else if (!root.wlPasteAvailable)
            root.errorText = "需要 wl-paste 以监听剪贴板";
        else
            root.errorText = "";

        var detail = root.commandRunner.dependencyDetail("clipboard");
        if (root.errorText.length === 0 && root.commandRunner.dependencyState("clipboard") === "warn")
            root.errorText = detail;

        root.statusText = root.available ? "剪贴板历史可用" : "剪贴板历史不可用";

        if (root.cliphistAvailable && root.wlPasteAvailable)
            root.startWatcher();
        if (root.cliphistAvailable)
            Qt.callLater(root.refresh);

        return true;
    }

    function detectTools() {
        if (root.applyCommandRunnerTools())
            return;

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

    function dependencyWarningText() {
        if (!root.commandRunner || root.commandRunner.revision === 0)
            return "";
        return root.commandRunner.dependencyState("clipboard") === "ok" ? "" : root.commandRunner.dependencyDetail("clipboard");
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
                "icon": binary ? "\ue3f4" : "\ue14f",
                "binary": binary,
                "pinnable": !binary
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

        if (entry.binary || entry.pinnable === false) {
            root.statusText = "只能复制文本项";
            return;
        }

        if (root.commandRunner && root.commandRunner.runClipboardCopyEntry) {
            var result = root.commandRunner.runClipboardCopyEntry(entry.raw, root.textMimeType);
            root.statusText = result && result.success ? "已复制" : String(result && (result.detail || result.message) || "复制失败");
            root.errorText = result && result.success ? root.dependencyWarningText() : root.statusText;
            return;
        }

        root.statusText = "已复制";
        Quickshell.execDetached({
            command: ["sh", "-c", "printf %s \"$1\" | cliphist decode | wl-copy --type '" + root.textMimeType + "'", "sh", entry.raw],
            workingDirectory: ""
        });
    }

    function copyPinnedEntry(pin) {
        if (!pin || !pin.text || !root.wlCopyAvailable)
            return;

        if (root.commandRunner && root.commandRunner.runClipboardCopyText) {
            var result = root.commandRunner.runClipboardCopyText(String(pin.text || ""), root.textMimeType);
            root.statusText = result && result.success ? "已复制固定项" : String(result && (result.detail || result.message) || "复制失败");
            root.errorText = result && result.success ? root.dependencyWarningText() : root.statusText;
            return;
        }

        root.statusText = "已复制固定项";
        Quickshell.execDetached({
            command: ["sh", "-c", "printf %s \"$1\" | wl-copy --type '" + root.textMimeType + "'", "sh", String(pin.text || "")],
            workingDirectory: ""
        });
    }

    function deleteEntry(entry) {
        if (!entry || !entry.raw || !root.cliphistAvailable)
            return;

        if (root.commandRunner && root.commandRunner.runClipboardDeleteEntry) {
            var result = root.commandRunner.runClipboardDeleteEntry(entry.raw);
            root.statusText = result && result.success ? "已删除" : String(result && (result.detail || result.message) || "删除失败");
            root.errorText = result && result.success ? root.dependencyWarningText() : root.statusText;
            root.scheduleRefresh();
            return;
        }

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
        root.setValue("statusText", root.pinnedCount > 0 ? "已清空历史，固定项保留" : "已清空历史");
        if (root.commandRunner && root.commandRunner.runClipboardClearHistory) {
            var result = root.commandRunner.runClipboardClearHistory();
            if (result && !result.success) {
                root.statusText = String(result.detail || result.message || "清空失败");
                root.errorText = root.statusText;
            } else {
                root.errorText = root.dependencyWarningText();
            }
            root.scheduleRefresh();
            return;
        }

        Quickshell.execDetached({
            command: ["cliphist", "wipe"],
            workingDirectory: ""
        });
        root.scheduleRefresh();
    }

    FileView {
        id: pinnedFile
        path: root.pinnedStatePath
        preload: false
        blockLoading: true
        blockWrites: true
        printErrors: false
        onLoaded: root.loadPinnedState()
        onLoadFailed: root.loadPinnedState()
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
        command: root.commandRunner && root.commandRunner.clipboardListCommand ? root.commandRunner.clipboardListCommand() : ["cliphist", "list"]
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
        id: pinDecodeProcess
        running: false
        command: root.commandRunner && root.commandRunner.clipboardDecodeCommand ? root.commandRunner.clipboardDecodeCommand(root.pendingPinRaw) : ["sh", "-c", "printf %s \"$1\" | cliphist decode", "sh", root.pendingPinRaw]
        stdout: StdioCollector {
            id: pinDecodeOut
            onStreamFinished: root.finishPinDecode(pinDecodeOut.text)
        }
        onExited: function(code, exitStatus) {
            if (code !== 0 && root.pinning) {
                root.setValue("statusText", "固定失败");
                root.resetPinDecode();
            }
        }
    }

    Process {
        id: clipboardWatcher
        running: false
        command: root.commandRunner && root.commandRunner.clipboardWatchCommand ? root.commandRunner.clipboardWatchCommand() : ["wl-paste", "--watch", "cliphist", "store"]
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

    Connections {
        target: root.commandRunner
        ignoreUnknownSignals: true

        function onRevisionChanged() {
            root.applyCommandRunnerTools();
        }
    }

    Component.onCompleted: {
        root.loadPinnedState();
        root.detectTools();
    }
}
