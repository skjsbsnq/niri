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

    // S5.1 glass + blur mirrors. glassMaterials is a nested object keyed by
    // material name; each material carries the five visual material fields
    // (edge_highlight/refraction/inner_shadow/chromatic/lens_depth). Defaults
    // mirror the deployed config.kdl so the first frame matches truth before
    // the first read reconciles. setGlassField rebuilds the top-level object
    // (QML does not observe nested mutation) and queues a glass.<m>.<f> write.
    property var glassMaterials: ({
        "panel":    { edge_highlight: 0.14, refraction: 0.004, inner_shadow: 0.06,  chromatic: 0.0, lens_depth: 0.0 },
        "pill":     { edge_highlight: 0.32, refraction: 0.013, inner_shadow: 0.07,  chromatic: 0.0, lens_depth: 0.010 },
        "launcher": { edge_highlight: 0.15, refraction: 0.004, inner_shadow: 0.055, chromatic: 0.0, lens_depth: 0.003 },
        "dock":     { edge_highlight: 0.18, refraction: 0.007, inner_shadow: 0.07,  chromatic: 0.0, lens_depth: 0.006 },
        "menu":     { edge_highlight: 0.26, refraction: 0.004, inner_shadow: 0.10,  chromatic: 0.0, lens_depth: 0.0 },
        "toast":    { edge_highlight: 0.24, refraction: 0.005, inner_shadow: 0.09,  chromatic: 0.0, lens_depth: 0.0 },
        "backdrop": { edge_highlight: 0.05, refraction: 0.002, inner_shadow: 0.0,   chromatic: 0.0, lens_depth: 0.0 }
    })
    property bool blurEnabled: true
    property int blurPasses: 5
    property real blurOffset: 7
    property real blurNoise: 0.012
    property real blurSaturation: 1.6

    // S5.2 input mirrors. keyboard repeat-rate/repeat-delay/numlock and
    // touchpad tap/natural-scroll/dwt/accel-speed are writable through setX.
    // Defaults mirror the deployed config.kdl. Output scale is writable through
    // the same validated helper path; variable-refresh-rate is never touched.
    property int keyboardRepeatRate: 25
    property int keyboardRepeatDelay: 600
    property bool keyboardNumlock: true
    property bool touchpadTap: true
    property bool touchpadNaturalScroll: true
    property bool touchpadDwt: false
    property real touchpadAccelSpeed: 0
    property string outputName: ""
    property real outputScale: 1
    property bool outputPresent: false

    // S5.3 animation mirrors. Spring params for the four spring-based actions
    // in the config (workspace-switch/window-movement/window-resize/
    // overview-open-close). window-open/close carry custom GLSL shaders and
    // are never written by the GUI. animSprings is a nested object keyed by
    // action; setAnimParam rebuilds the top-level object and queues a write.
    property var animSprings: ({
        "workspace_switch":  { damping_ratio: 1.0,  stiffness: 780, epsilon: 0.0001 },
        "window_movement":   { damping_ratio: 0.86, stiffness: 620, epsilon: 0.001 },
        "window_resize":     { damping_ratio: 0.96, stiffness: 700, epsilon: 0.0005 },
        "overview_open_close": { damping_ratio: 0.95, stiffness: 760, epsilon: 0.0005 }
    })
    property bool layerAnimationsEnabled: true
    property string motionProfile: "balanced"
    readonly property var motionProfileModel: [
        { value: "fast", label: "Fast" },
        { value: "balanced", label: "Balanced" },
        { value: "liquid", label: "Liquid" },
        { value: "reduced", label: "Reduced" }
    ]

    // S5.4 binds mirror (read-only). binds is a replace-on-conflict authoritative
    // block; the GUI never writes it. bindsList holds {combo, action, protected}
    // for the viewer; protected marks the task-switcher IPC binds (441b637).
    property var bindsList: []

    // Per-field queue of the latest committed value while a write is in
    // flight. Sliders own their drag preview and call setX once on commit;
    // setX updates the mirror immediately and records the final write here.
    // Overlapping cross-field edits still converge on disk in one queue.
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

    function setGlassField(material, field, value) {
        var current = root.glassMaterials[material];
        if (!current)
            return;
        var number = Number(value);
        if (!isFinite(number) || current[field] === number)
            return;
        var next = {};
        for (var key in root.glassMaterials)
            next[key] = key === material ? Object(root.glassMaterials[key]) : root.glassMaterials[key];
        next[material][field] = number;
        root.glassMaterials = next;
        root.writeField("glass." + material + "." + field, String(number));
    }

    function clampReal(value, minimum, maximum, fallback) {
        var number = Number(value);
        if (!isFinite(number))
            number = fallback;
        return Math.max(minimum, Math.min(maximum, number));
    }

    function setBlurEnabled(enabled) {
        var next = !!enabled;
        if (next === blurEnabled)
            return;
        root.blurEnabled = next;
        root.writeField("blur.enabled", next);
    }

    function setBlurPasses(value) {
        var next = clampNumber(value, 0, 255, blurPasses);
        if (next === blurPasses)
            return;
        root.blurPasses = next;
        root.writeField("blur.passes", next);
    }

    function setBlurOffset(value) {
        var next = clampReal(value, 0, 100, blurOffset);
        if (Math.abs(next - blurOffset) < 1e-9)
            return;
        root.blurOffset = next;
        root.writeField("blur.offset", next);
    }

    function setBlurNoise(value) {
        var next = clampReal(value, 0, 1000, blurNoise);
        if (Math.abs(next - blurNoise) < 1e-9)
            return;
        root.blurNoise = next;
        root.writeField("blur.noise", next);
    }

    function setBlurSaturation(value) {
        var next = clampReal(value, 0, 1000, blurSaturation);
        if (Math.abs(next - blurSaturation) < 1e-9)
            return;
        root.blurSaturation = next;
        root.writeField("blur.saturation", next);
    }

    function setKeyboardRepeatRate(value) {
        var next = clampNumber(value, 0, 255, keyboardRepeatRate);
        if (next === keyboardRepeatRate)
            return;
        root.keyboardRepeatRate = next;
        root.writeField("input.keyboard.repeat_rate", next);
    }

    function setKeyboardRepeatDelay(value) {
        var next = clampNumber(value, 0, 65535, keyboardRepeatDelay);
        if (next === keyboardRepeatDelay)
            return;
        root.keyboardRepeatDelay = next;
        root.writeField("input.keyboard.repeat_delay", next);
    }

    function setKeyboardNumlock(enabled) {
        var next = !!enabled;
        if (next === keyboardNumlock)
            return;
        root.keyboardNumlock = next;
        root.writeField("input.keyboard.numlock", next);
    }

    function setTouchpadTap(enabled) {
        var next = !!enabled;
        if (next === touchpadTap)
            return;
        root.touchpadTap = next;
        root.writeField("input.touchpad.tap", next);
    }

    function setTouchpadNaturalScroll(enabled) {
        var next = !!enabled;
        if (next === touchpadNaturalScroll)
            return;
        root.touchpadNaturalScroll = next;
        root.writeField("input.touchpad.natural_scroll", next);
    }

    function setTouchpadDwt(enabled) {
        var next = !!enabled;
        if (next === touchpadDwt)
            return;
        root.touchpadDwt = next;
        root.writeField("input.touchpad.dwt", next);
    }

    function setTouchpadAccelSpeed(value) {
        var next = clampReal(value, -1, 1, touchpadAccelSpeed);
        if (Math.abs(next - touchpadAccelSpeed) < 1e-9)
            return;
        root.touchpadAccelSpeed = next;
        root.writeField("input.touchpad.accel_speed", next);
    }

    function setOutputScale(value) {
        var next = clampReal(value, 0.5, 4, outputScale);
        if (Math.abs(next - outputScale) < 1e-9)
            return;
        root.outputScale = next;
        root.writeField("output.scale", next);
    }

    function setAnimParam(action, param, value) {
        var current = root.animSprings[action];
        if (!current)
            return;
        var number = Number(value);
        if (!isFinite(number) || current[param] === number)
            return;
        var next = {};
        for (var key in root.animSprings)
            next[key] = key === action ? Object(root.animSprings[key]) : root.animSprings[key];
        next[action][param] = number;
        root.animSprings = next;
        root.writeField("animations." + action + "." + param, String(number));
    }

    function validMotionProfile(profile) {
        var text = String(profile || "");
        return text === "fast" || text === "balanced" || text === "liquid" || text === "reduced";
    }

    function setMotionProfile(profile) {
        var next = validMotionProfile(profile) ? String(profile) : "balanced";
        if (root.motionProfile === next)
            return;
        root.motionProfile = next;
        root.writeField("animations.profile", next);
    }

    function setLayerAnimationsEnabled(enabled) {
        var next = !!enabled;
        if (root.layerAnimationsEnabled === next)
            return;
        root.layerAnimationsEnabled = next;
        root.writeField("animations.layer_animations_enabled", next);
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

    function applyGlass(glass) {
        if (!glass || !glass.materials)
            return;
        root.glassMaterials = glass.materials;
    }

    function applyBlur(blur) {
        if (!blur)
            return;
        root.blurEnabled = !!blur.enabled;
        root.blurPasses = clampNumber(blur.passes, 0, 255, 5);
        root.blurOffset = clampReal(blur.offset, 0, 100, 3);
        root.blurNoise = clampReal(blur.noise, 0, 1000, 0.02);
        root.blurSaturation = clampReal(blur.saturation, 0, 1000, 1.5);
    }

    function applyInput(input) {
        if (!input)
            return;
        if (input.keyboard) {
            root.keyboardRepeatRate = clampNumber(input.keyboard.repeat_rate, 0, 255, 25);
            root.keyboardRepeatDelay = clampNumber(input.keyboard.repeat_delay, 0, 65535, 600);
            root.keyboardNumlock = !!input.keyboard.numlock;
        }
        if (input.touchpad) {
            root.touchpadTap = !!input.touchpad.tap;
            root.touchpadNaturalScroll = !!input.touchpad.natural_scroll;
            root.touchpadDwt = !!input.touchpad.dwt;
            root.touchpadAccelSpeed = clampReal(input.touchpad.accel_speed, -1, 1, 0);
        }
        if (input.output) {
            root.outputPresent = !!input.output.present;
            root.outputName = String(input.output.name || "");
            root.outputScale = clampReal(input.output.scale, 0.1, 10, 1);
        }
    }

    function applyAnimations(anim) {
        if (!anim || !anim.actions)
            return;
        root.animSprings = anim.actions;
        if (anim.layerAnimationsEnabled !== undefined)
            root.layerAnimationsEnabled = !!anim.layerAnimationsEnabled;
        if (anim.profile && root.validMotionProfile(anim.profile))
            root.motionProfile = String(anim.profile);
        else if (anim.profile)
            root.motionProfile = "custom";
    }

    function applyBinds(binds) {
        if (!binds || !binds.items)
            return;
        root.bindsList = binds.items;
    }

    // Read-only convenience: open config.kdl in the user's $EDITOR (fallback
    // xdg-open) so keybinds can be edited by hand. The GUI never writes binds.
    function openConfigInEditor() {
        Quickshell.execDetached({
            command: [
                "sh", "-lc",
                'editor="${EDITOR:-${VISUAL:-xdg-open}}"; exec "$editor" "$1"',
                "sh",
                root.configPath
            ],
            workingDirectory: ""
        });
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
            root.applyGlass(payload.glass);
            root.applyBlur(payload.blur);
            root.applyInput(payload.input);
            root.applyAnimations(payload.animations);
            root.applyBinds(payload.binds);
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
            root.applyGlass(payload.glass);
            root.applyBlur(payload.blur);
            root.applyInput(payload.input);
            root.applyAnimations(payload.animations);
            root.applyBinds(payload.binds);
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
