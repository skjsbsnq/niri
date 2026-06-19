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

    property int gaps: 16
    property bool focusRingEnabled: true
    property bool borderEnabled: false
    property bool shadowEnabled: false
    property int shadowSoftness: 30
    property int shadowSpread: 5
    property int shadowOffsetX: 0
    property int shadowOffsetY: 5
    property bool snapAssistEnabled: false
    property int snapAssistThreshold: 36

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
        writeField("layout.gaps", next);
    }

    function setFocusRingEnabled(enabled) {
        var next = !!enabled;
        if (next === focusRingEnabled)
            return;
        writeField("layout.focus_ring.enabled", next);
    }

    function setBorderEnabled(enabled) {
        var next = !!enabled;
        if (next === borderEnabled)
            return;
        writeField("layout.border.enabled", next);
    }

    function setShadowEnabled(enabled) {
        var next = !!enabled;
        if (next === shadowEnabled)
            return;
        writeField("layout.shadow.enabled", next);
    }

    function setShadowSoftness(value) {
        var next = clampNumber(value, 0, 1024, shadowSoftness);
        if (next === shadowSoftness)
            return;
        writeField("layout.shadow.softness", next);
    }

    function setShadowSpread(value) {
        var next = clampNumber(value, -1024, 1024, shadowSpread);
        if (next === shadowSpread)
            return;
        writeField("layout.shadow.spread", next);
    }

    function setShadowOffsetX(value) {
        var next = clampNumber(value, -65535, 65535, shadowOffsetX);
        if (next === shadowOffsetX)
            return;
        writeField("layout.shadow.offset_x", next);
    }

    function setShadowOffsetY(value) {
        var next = clampNumber(value, -65535, 65535, shadowOffsetY);
        if (next === shadowOffsetY)
            return;
        writeField("layout.shadow.offset_y", next);
    }

    function setSnapAssistEnabled(enabled) {
        var next = !!enabled;
        if (next === snapAssistEnabled)
            return;
        writeField("layout.snap_assist.enabled", next);
    }

    function setSnapAssistThreshold(value) {
        var next = clampNumber(value, 0, 65535, snapAssistThreshold);
        if (next === snapAssistThreshold)
            return;
        writeField("layout.snap_assist.threshold", next);
    }

    function writeField(field, value) {
        if (writer.running) {
            root.lastError = "niri 设置正在写入";
            return;
        }

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
            String(value)
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
                return;
            }
            root.lastError = root.payloadError(writerOut.text, "niri 设置写入失败，退出码 " + String(code));
        }
    }

    Component.onCompleted: root.refresh()
}
