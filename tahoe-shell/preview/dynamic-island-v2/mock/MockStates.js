.pragma library

// Pure mock presentation models for the non-production V2 preview.
// Geometry mid-band values track DynamicIslandMotion v2* ranges (asserted in tests).
// No service access. No IPC.

function clock(localeTag) {
    var tag = String(localeTag || "zh-CN");
    var en = tag.indexOf("en") === 0;
    return {
        kind: "clock",
        weekday: en ? "Tue" : "周二",
        time: "22:31",
        localeTag: tag,
        width: 124,
        height: 32,
        radius: 16,
        fillRole: "compact"
    };
}

function compactMedia(variant, localeTag) {
    var v = String(variant || "playing");
    var en = String(localeTag || "").indexOf("en") === 0;
    var title;
    if (v === "long") {
        title = en
            ? "Very Long Track Title · Midnight Drive Through Empty Cities"
            : "超长曲名示例 · Midnight Drive Through Empty Cities";
    } else {
        title = en ? "Midnight Drive" : "午夜驰骋";
    }
    return {
        kind: "compact_media",
        title: title,
        artUrl: "",
        playing: v !== "paused",
        progress: v === "paused" ? 0.35 : 0.62,
        width: v === "long" ? 224 : 212,
        height: 36,
        radius: 18,
        fillRole: "compact"
    };
}

function osd(kind, value, localeTag) {
    var k = String(kind || "volume");
    var en = String(localeTag || "").indexOf("en") === 0;
    var raw = Number(value);
    if (!isFinite(raw))
        raw = k === "muted" ? 0 : 0.5;
    var clamped = Math.max(0, Math.min(1, raw));
    var label;
    if (k === "brightness")
        label = en ? "Brightness" : "亮度";
    else if (k === "muted")
        label = en ? "Muted" : "静音";
    else
        label = en ? "Volume" : "音量";
    var icon = k === "brightness" ? "brightness" : (k === "muted" ? "volume_off" : "volume_up");
    return {
        kind: "osd",
        osdKind: k === "muted" ? "volume" : k,
        muted: k === "muted",
        value: clamped,
        percentLabel: String(Math.round(clamped * 100)),
        label: label,
        mutedLabel: en ? "Muted" : "静音",
        iconName: icon,
        width: 232,
        height: 44,
        radius: 22,
        fillRole: "transient"
    };
}

function notificationCompact(variant, localeTag) {
    var v = String(variant || "short");
    var en = String(localeTag || "").indexOf("en") === 0 || v === "en";
    var longBody = v === "long" || v === "actions";
    var critical = v === "critical";
    return {
        kind: "notification_compact",
        notificationId: 42,
        appName: en ? "Messages" : "信息",
        appIcon: "",
        summary: longBody
            ? (en ? "Project sync finished with notes" : "项目同步完成，请查看备注")
            : (en ? "New message" : "新消息"),
        body: longBody
            ? (en
                ? "The overnight build published artifacts and updated three review threads."
                : "夜间构建已发布产物，并更新了三条评审线程。")
            : (en ? "Are you free later?" : "晚上有空吗？"),
        urgency: critical ? "critical" : "normal",
        hasOverflow: longBody,
        width: longBody ? 400 : 320,
        height: longBody ? 76 : 64,
        radius: longBody ? 24 : 22,
        fillRole: "transient"
    };
}

function notificationExpanded(variant, localeTag) {
    var v = String(variant || "actions");
    var en = String(localeTag || "").indexOf("en") === 0 || v === "en";
    var compact = notificationCompact(v === "en" ? "actions" : v, en ? "en-US" : "zh-CN");
    return {
        kind: "notification_expanded",
        notificationId: compact.notificationId,
        appName: compact.appName,
        appIcon: compact.appIcon,
        summary: compact.summary,
        body: compact.body,
        urgency: compact.urgency,
        hasOverflow: true,
        bodyLines: 3,
        actions: [
            { id: "reply", label: en ? "Reply" : "回复" },
            { id: "later", label: en ? "Later" : "稍后" },
            { id: "archive", label: en ? "Archive" : "归档" }
        ],
        width: 420,
        height: 148,
        radius: 28,
        fillRole: "expanded"
    };
}

function expandedMedia(variant, localeTag) {
    var longMeta = String(variant || "") === "long";
    var en = String(localeTag || "").indexOf("en") === 0;
    return {
        kind: "expanded_media",
        title: longMeta
            ? (en ? "Very Long Title · Neon Highways After Rain" : "超长曲名示例 · Neon Highways After Rain")
            : (en ? "Neon Highways" : "霓虹公路"),
        artist: longMeta
            ? "An Extremely Long Artist Name Collective"
            : (en ? "Night Runner" : "夜行者"),
        artUrl: "",
        playing: true,
        position: 97,
        duration: 248,
        progress: 97 / 248,
        canSeek: true,
        canPlayPause: true,
        canPrev: true,
        canNext: true,
        width: 420,
        height: 168,
        radius: 30,
        fillRole: "expanded"
    };
}

function workspace(localeTag) {
    var en = String(localeTag || "").indexOf("en") === 0;
    return {
        kind: "workspace",
        index: 2,
        name: en ? "Design" : "设计",
        direction: "right",
        width: 156,
        height: 36,
        radius: 18,
        fillRole: "transient"
    };
}

function timer(variant, localeTag) {
    var expanded = String(variant || "compact") === "expanded";
    var en = String(localeTag || "").indexOf("en") === 0;
    if (expanded) {
        return {
            kind: "timer_expanded",
            remainingLabel: "12:48",
            statusLabel: en ? "Running" : "进行中",
            pauseLabel: en ? "Pause" : "暂停",
            cancelLabel: en ? "Cancel" : "取消",
            running: true,
            progress: 0.42,
            width: 360,
            height: 144,
            radius: 30,
            fillRole: "expanded"
        };
    }
    return {
        kind: "timer_compact",
        remainingLabel: "12:48",
        statusLabel: en ? "Running" : "进行中",
        pauseLabel: en ? "Pause" : "暂停",
        cancelLabel: en ? "Cancel" : "取消",
        running: true,
        progress: 0.42,
        width: 148,
        height: 36,
        radius: 18,
        fillRole: "compact"
    };
}

function allStates(localeTag) {
    var tag = String(localeTag || "zh-CN");
    return [
        clock(tag),
        compactMedia("playing", tag),
        compactMedia("paused", tag),
        compactMedia("long", tag),
        osd("volume", 0.72, tag),
        osd("muted", 0, tag),
        osd("brightness", 0, tag),
        osd("brightness", 1, tag),
        notificationCompact("short", tag),
        notificationCompact("long", tag),
        notificationCompact("critical", tag),
        notificationExpanded("actions", tag),
        expandedMedia("default", tag),
        expandedMedia("long", tag),
        workspace(tag),
        timer("compact", tag),
        timer("expanded", tag)
    ];
}

// Offline matrix cell: appearance dimensions that MUST change rendered pixels.
function matrixCells() {
    var widths = [1366, 1920, 2048];
    var scales = [1.0, 1.25];
    var locales = ["zh-CN", "en-US"];
    var modes = ["light", "dark"];
    var wallpapers = ["bright", "dark"];
    var cells = [];
    for (var wi = 0; wi < widths.length; wi++) {
        for (var si = 0; si < scales.length; si++) {
            for (var li = 0; li < locales.length; li++) {
                for (var mi = 0; mi < modes.length; mi++) {
                    for (var pi = 0; pi < wallpapers.length; pi++) {
                        cells.push({
                            width: widths[wi],
                            scale: scales[si],
                            locale: locales[li],
                            mode: modes[mi],
                            wallpaper: wallpapers[pi]
                        });
                    }
                }
            }
        }
    }
    return cells;
}

// Geometry bands mirrored from DynamicIslandMotion v2* (tests cross-check source).
function geometryBands() {
    return {
        clock: { wMin: 112, wMax: 136, h: 32, r: 16 },
        compactMedia: { wMin: 200, wMax: 224, h: 36, r: 18 },
        osd: { wMin: 220, wMax: 240, h: 44, r: 22 },
        workspace: { wMin: 140, wMax: 168, h: 36, r: 18 },
        notificationCompact: { wMin: 300, wMax: 420, hMin: 60, hMax: 80, rMin: 22, rMax: 26 },
        mediaExpanded: { wMin: 404, wMax: 432, hMin: 160, hMax: 172, rMin: 28, rMax: 32 },
        notificationExpanded: { wMin: 380, wMax: 440, hMin: 96, hMax: 176, rMin: 28, rMax: 32 },
        timerExpanded: { wMin: 340, wMax: 380, hMin: 136, hMax: 152, rMin: 28, rMax: 32 }
    };
}
