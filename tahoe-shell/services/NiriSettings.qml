pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    readonly property string helperPath: Quickshell.shellPath("services/niri_settings_tool.py")
    readonly property string homeDir: envString("HOME")
    readonly property string configPath: configHome() + "/niri/tahoe/config.kdl"

    property bool loaded: false
    property bool updating: false
    property string lastError: ""

    // Defaults mirror the deployed config.kdl layout block so the brief
    // window before the first read completes shows the real values instead
    // of a flash of wrong defaults. refresh() reconciles to truth on load.
    property int gaps: 16
    property bool focusRingEnabled: false
    property bool borderEnabled: false
    property bool shadowEnabled: true
    property int shadowSoftness: 36
    property int shadowSpread: 4
    property int shadowOffsetX: 0
    property int shadowOffsetY: 10
    property bool snapAssistEnabled: true
    property int snapAssistThreshold: 16

    // Per-field queue of the latest intended value while a write is in
    // flight. setX updates its property optimistically (so the UI tracks a
    // drag immediately) and records the intended write here; the writer
    // drains one field per round-trip so rapid slider drags and overlapping
    // cross-field edits all converge on disk. See S4 wiring (NiriPage).
    property var pending: ({})

    function envString(name) {
        var value = Quickshell.env(name);
        return value === undefined || value === null ? "" : String(value);
    }

    function configHome() {
        var xdgConfig = envString("XDG_CONFIG_HOME");
        if (xdgConfig.length > 0)
            return xdgConfig;
        return homeDir.length > 0 ? homeDir + "/.config" : "";
    }

    function clampNumber(value, minimum, maximum, fallback) {
        var number = Number(value);
        if (!isFinite(number))
            number = fallback;
        return Math.max(minimum, Math.min(maximum, Math.round(number)));
    }

    function refresh() {
        if (reader.running)
            return;

        reader.command = ["python3", root.helperPath, "read", "--config", root.configPath];
        reader.running = true;
    }

    function setGaps(value) {
        var next = clampNumber(value, 0, 65535, gaps);
        if (next === gaps)
            return;
        root.gaps = next;
        writeField("layout.gaps", next);
    }

    function setFocusRingEnabled(enabled) {
        var next = !!enabled;
        if (next === focusRingEnabled)
            return;
        root.focusRingEnabled = next;
        writeField("layout.focus_ring.enabled", next);
    }

    function setBorderEnabled(enabled) {
        var next = !!enabled;
        if (next === borderEnabled)
            return;
        root.borderEnabled = next;
        writeField("layout.border.enabled", next);
    }

    function setShadowEnabled(enabled) {
        var next = !!enabled;
        if (next === shadowEnabled)
            return;
        root.shadowEnabled = next;
        writeField("layout.shadow.enabled", next);
    }

    function setShadowSoftness(value) {
        var next = clampNumber(value, 0, 1024, shadowSoftness);
        if (next === shadowSoftness)
            return;
        root.shadowSoftness = next;
        writeField("layout.shadow.softness", next);
    }

    function setShadowSpread(value) {
        var next = clampNumber(value, -1024, 1024, shadowSpread);
        if (next === shadowSpread)
            return;
        root.shadowSpread = next;
        writeField("layout.shadow.spread", next);
    }

    function setShadowOffsetX(value) {
        var next = clampNumber(value, -65535, 65535, shadowOffsetX);
        if (next === shadowOffsetX)
            return;
        root.shadowOffsetX = next;
        writeField("layout.shadow.offset_x", next);
    }

    function setShadowOffsetY(value) {
        var next = clampNumber(value, -65535, 65535, shadowOffsetY);
        if (next === shadowOffsetY)
            return;
        root.shadowOffsetY = next;
        writeField("layout.shadow.offset_y", next);
    }

    function setSnapAssistEnabled(enabled) {
        var next = !!enabled;
        if (next === snapAssistEnabled)
            return;
        root.snapAssistEnabled = next;
        writeField("layout.snap_assist.enabled", next);
    }

    function setSnapAssistThreshold(value) {
        var next = clampNumber(value, 0, 65535, snapAssistThreshold);
        if (next === snapAssistThreshold)
            return;
        root.snapAssistThreshold = next;
        writeField("layout.snap_assist.threshold", next);
    }

    function writeField(field, value) {
        root.lastError = "";
        var next = root.pending;
        next[field] = String(value);
        root.pending = next;
        if (!root.updating)
            root.flushPending();
    }

    // Drain one queued field per write round-trip. Each call takes the
    // oldest pending field, removes it, and starts a writer; if more fields
    // remain they are written after this one exits (see writer.onExited).
    function flushPending() {
        var fields = Object.keys(root.pending);
        if (fields.length === 0)
            return;

        var field = fields[0];
        var value = root.pending[field];
        var remaining = root.pending;
        delete remaining[field];
        root.pending = remaining;
        root.startWriter(field, value);
    }

    function startWriter(field, value) {
        root.updating = true;
        writer.command = [
            "python3",
            root.helperPath,
            "write",
            "--config",
            root.configPath,
            "--field",
            field,
            "--value",
            value
        ];
        writer.running = true;
    }

    function applyLayout(layout) {
        if (!layout)
            return;

        root.gaps = clampNumber(layout.gaps, 0, 65535, 16);

        if (layout.focusRing)
            root.focusRingEnabled = !!layout.focusRing.enabled;
        if (layout.border)
            root.borderEnabled = !!layout.border.enabled;

        if (layout.shadow) {
            root.shadowEnabled = !!layout.shadow.enabled;
            root.shadowSoftness = clampNumber(layout.shadow.softness, 0, 1024, 30);
            root.shadowSpread = clampNumber(layout.shadow.spread, -1024, 1024, 5);
            root.shadowOffsetX = clampNumber(layout.shadow.offsetX, -65535, 65535, 0);
            root.shadowOffsetY = clampNumber(layout.shadow.offsetY, -65535, 65535, 5);
        }

        if (layout.snapAssist) {
            root.snapAssistEnabled = !!layout.snapAssist.enabled;
            root.snapAssistThreshold = clampNumber(layout.snapAssist.threshold, 0, 65535, 36);
        }
    }

    function payloadError(text, fallback) {
        try {
            var payload = JSON.parse(String(text || "{}"));
            if (payload.error)
                return String(payload.error);
        } catch (error) {
        }
        return fallback;
    }

    function handleReadOutput(text) {
        try {
            var payload = JSON.parse(String(text || "{}"));
            if (!payload.ok) {
                root.lastError = payload.error ? String(payload.error) : "niri 设置读取失败";
                root.loaded = true;
                return;
            }
            applyLayout(payload.layout);
            root.lastError = "";
            root.loaded = true;
        } catch (error) {
            root.lastError = "niri 设置读取结果无法解析";
            root.loaded = true;
        }
    }

    function handleWriteOutput(text) {
        try {
            var payload = JSON.parse(String(text || "{}"));
            if (!payload.ok) {
                root.lastError = payload.error ? String(payload.error) : "niri 设置写入失败";
                return;
            }
            applyLayout(payload.layout);
            root.lastError = "";
            root.loaded = true;
        } catch (error) {
            root.lastError = "niri 设置写入结果无法解析";
        }
    }

    function applyNiriConfig() {
        Quickshell.execDetached({
            command: [
                "sh",
                "-lc",
                [
                    "config=\"$1\"",
                    "command -v niri >/dev/null 2>&1 || exit 0",
                    "niri msg action load-config-file --path \"$config\" >/dev/null 2>&1 || niri msg action load-config-file >/dev/null 2>&1 || true"
                ].join("\n"),
                "sh",
                root.configPath
            ],
            workingDirectory: ""
        });
    }

    Process {
        id: reader
        running: false
        stdout: StdioCollector {
            id: readerOut
            onStreamFinished: root.handleReadOutput(readerOut.text)
        }
        onExited: function(code) {
            if (code !== 0) {
                root.lastError = root.payloadError(readerOut.text, "niri 设置读取失败，退出码 " + String(code));
                root.loaded = true;
            }
        }
    }

    Process {
        id: writer
        running: false
        stdout: StdioCollector {
            id: writerOut
            onStreamFinished: root.handleWriteOutput(writerOut.text)
        }
        onExited: function(code) {
            root.updating = false;
            if (code === 0) {
                root.applyNiriConfig();
                root.flushPending();
                return;
            }
            // A failed write may have left optimistic values ahead of disk;
            // drop any queued writes and re-read so the UI reflects truth.
            root.pending = ({});
            root.lastError = root.payloadError(writerOut.text, "niri 设置写入失败，退出码 " + String(code));
            root.refresh();
        }
    }

    Component.onCompleted: root.refresh()
}
