.pragma library

// Tahoe shell design tokens (T14). Expanded from settings-only tokens into the
// shared shell color library — one export surface for TopBar / menus / CC /
// sidebar / settings. Do not introduce a parallel theme file (rules §2.4 / §3.2).
//
// Accent is selectable (macOS 8 system colors) via DesktopSettings.accentColor.
// Call sites pass darkMode + optional accentId; default accent is system blue.

// --- Text (semantic aliases + legacy names) --------------------------------

function label(darkMode) {
    return textPrimary(darkMode);
}

function secondaryLabel(darkMode) {
    return textSecondary(darkMode);
}

function tertiaryLabel(darkMode) {
    return textMuted(darkMode);
}

function textPrimary(darkMode) {
    return darkMode ? "#f5f7fb" : "#1d1d1f";
}

function textSecondary(darkMode) {
    return darkMode ? "#c3ccd6" : "#721d1d1f";
}

function textMuted(darkMode) {
    return darkMode ? "#94a0ad" : "#5f6870";
}

function separator(darkMode) {
    return darkMode ? "#1affffff" : "#1a000000";
}

// --- Accent system (macOS 8) ----------------------------------------------

// Stable ids stored in DesktopSettings.accentColor.
var ACCENT_IDS = [
    "blue",
    "purple",
    "pink",
    "red",
    "orange",
    "yellow",
    "green",
    "graphite"
];

function accentIds() {
    return ACCENT_IDS.slice();
}

function normalizeAccentId(value) {
    var id = String(value || "").trim().toLowerCase();
    if (id === "gray" || id === "grey")
        return "graphite";
    for (var i = 0; i < ACCENT_IDS.length; i++) {
        if (ACCENT_IDS[i] === id)
            return id;
    }
    return "blue";
}

function accentLabel(value) {
    switch (normalizeAccentId(value)) {
    case "purple":
        return "紫色";
    case "pink":
        return "粉色";
    case "red":
        return "红色";
    case "orange":
        return "橙色";
    case "yellow":
        return "黄色";
    case "green":
        return "绿色";
    case "graphite":
        return "石墨";
    default:
        return "蓝色";
    }
}

// Light / dark pairs match macOS system colors (approximate public palette).
function systemAccent(value, darkMode) {
    switch (normalizeAccentId(value)) {
    case "purple":
        return darkMode ? "#bf5af2" : "#af52de";
    case "pink":
        return darkMode ? "#ff375f" : "#ff2d55";
    case "red":
        return darkMode ? "#ff453a" : "#ff3b30";
    case "orange":
        return darkMode ? "#ff9f0a" : "#ff9500";
    case "yellow":
        return darkMode ? "#ffd60a" : "#ffcc00";
    case "green":
        return darkMode ? "#30d158" : "#34c759";
    case "graphite":
        return darkMode ? "#98989d" : "#8e8e93";
    default: // blue
        return darkMode ? "#0a84ff" : "#007ff7";
    }
}

// Backward-compatible name: default system blue when accentId omitted.
function accentBlue(darkMode, accentId) {
    if (accentId === undefined || accentId === null || String(accentId).length === 0)
        return systemAccent("blue", darkMode);
    return systemAccent(accentId, darkMode);
}

// Preferred shell API: accent(darkMode, accentId).
function accent(darkMode, accentId) {
    return systemAccent(accentId, darkMode);
}

function systemBlue(darkMode) {
    return systemAccent("blue", darkMode);
}

function stateLabel(state) {
    if (state === "ok")
        return "正常";
    if (state === "warn")
        return "注意";
    if (state === "stale")
        return "过期";
    if (state === "missing")
        return "缺失";
    if (state === "broken")
        return "损坏";
    if (state === "unknown")
        return "未知";
    return "信息";
}

function stateColor(state, darkMode, accentId) {
    if (state === "ok")
        return darkMode ? "#30d158" : "#34c759";
    if (state === "warn")
        return "#ff9f0a";
    if (state === "stale")
        return "#ffcc00";
    if (state === "missing")
        return "#ff453a";
    if (state === "broken")
        return darkMode ? "#ff6961" : "#d70015";
    return accent(darkMode, accentId);
}

function danger(darkMode) {
    return darkMode ? "#ff6961" : "#ff453a";
}

// --- Panel and grouping surfaces -------------------------------------------

function panelFill(darkMode) {
    // Settings carries dense text, so its light material needs a readable
    // baseline even when the wallpaper or compositor fallback is dark.
    return darkMode ? "#d01d1f24" : "#b8f7f8fb";
}

function panelStroke(darkMode) {
    return darkMode ? "#44ffffff" : "#90ffffff";
}

function sectionFill(darkMode) {
    return darkMode ? "#1cffffff" : "#5effffff";
}

function sectionStroke(darkMode) {
    return darkMode ? "#2effffff" : "#80ffffff";
}

function rowFill(darkMode) {
    return darkMode ? "#1affffff" : "#66ffffff";
}

function rowFillHover(darkMode) {
    return darkMode ? "#2affffff" : "#86ffffff";
}

function rowStroke(darkMode) {
    return darkMode ? "#22ffffff" : "#72ffffff";
}

// --- Sidebar --------------------------------------------------------------

function sidebarFill(darkMode) {
    return darkMode ? "#16ffffff" : "#58ffffff";
}

function sidebarStroke(darkMode) {
    return darkMode ? "#26ffffff" : "#80ffffff";
}

function sidebarActiveFill(darkMode) {
    return darkMode ? "#3affffff" : "#a6ffffff";
}

function sidebarActiveStroke(darkMode) {
    return darkMode ? "#30ffffff" : "#96ffffff";
}

function sidebarHoverFill(darkMode) {
    return darkMode ? "#26ffffff" : "#80ffffff";
}

// --- Buttons --------------------------------------------------------------

function buttonFill(darkMode) {
    return darkMode ? "#22ffffff" : "#40ffffff";
}

function buttonStroke(darkMode) {
    return darkMode ? "#2effffff" : "#50ffffff";
}

function accentFillStrong(darkMode, accentId) {
    // Primary button fill: accent at ~85% alpha.
    var c = String(accent(darkMode, accentId) || "#007ff7").replace("#", "");
    if (c.length === 6)
        return "#" + "d8" + c;
    if (c.length === 8)
        return "#" + "d8" + c.substring(2);
    return darkMode ? "#d80a84ff" : "#d8007ff7";
}

function accentStrokeStrong(darkMode) {
    return darkMode ? "#4affffff" : "#70ffffff";
}

// --- Text field -----------------------------------------------------------

function fieldFill(darkMode) {
    return darkMode ? "#24ffffff" : "#3fffffff";
}

function fieldStroke(darkMode) {
    return darkMode ? "#30ffffff" : "#4cffffff";
}

function fieldStrokeFocus(darkMode, accentId) {
    return accent(darkMode, accentId);
}

// --- Slider / switch ------------------------------------------------------

function sliderTrack(darkMode) {
    // Recessed track: darker than the row in light mode, lighter in dark.
    return darkMode ? "#2effffff" : "#26000000";
}

function switchOff(darkMode) {
    return darkMode ? "#42ffffff" : "#2e000000";
}

// --- Summary tile ---------------------------------------------------------

function tileFill(darkMode) {
    return darkMode ? "#1cffffff" : "#6affffff";
}

function tileFillHover(darkMode) {
    return darkMode ? "#28ffffff" : "#88ffffff";
}

function tileStroke(darkMode) {
    return darkMode ? "#26ffffff" : "#82ffffff";
}

function tileStrokeHover(darkMode) {
    return darkMode ? "#34ffffff" : "#a0ffffff";
}

// --- Shell surfaces (TopBar / CC / LeftSidebar shared) --------------------

function topText(darkMode) {
    return label(darkMode);
}

function topTextSecondary(darkMode) {
    return darkMode ? "#d6dde5" : "#3a3a3c";
}

function statusAttention(darkMode) {
    return danger(darkMode);
}

function buttonHover(darkMode) {
    return darkMode ? "#24ffffff" : "#26ffffff";
}

function buttonOpen(darkMode) {
    return "#34ffffff";
}

function cardFill(darkMode) {
    return darkMode ? "#24ffffff" : "#58ffffff";
}

function cardStroke(darkMode) {
    return darkMode ? "#2effffff" : "#66ffffff";
}

function controlTileFill(darkMode) {
    return darkMode ? "#2c343dcc" : "#80ffffff";
}

function controlTileFillHover(darkMode) {
    return darkMode ? "#36424dcc" : "#8fffffff";
}

function controlTileFillActive(darkMode) {
    return darkMode ? "#37424dcc" : "#88ffffff";
}

function controlTileFillPressed(darkMode) {
    return darkMode ? "#242c34cc" : "#70ffffff";
}

function controlTileStroke(darkMode) {
    return darkMode ? "#34ffffff" : "#5affffff";
}

function controlInnerFill(darkMode) {
    return darkMode ? "#1cffffff" : "#14ffffff";
}

function sliderFill(darkMode) {
    return darkMode ? "#d8e4f0" : "#f2ffffff";
}

// --- Overlay scrim --------------------------------------------------------

function scrim(darkMode) {
    return darkMode ? "#33000000" : "#1a101418";
}

// --- Brand category colors ------------------------------------------------
// One solid accent per legacy summary category. The sidebar uses symbolic
// icons instead of category color blocks.

function categoryColor(key, darkMode, accentId) {
    switch (key) {
    case "overview":
        return "#8e8e93";     // system gray (General)
    case "appearance":
        return "#5856d6";     // system indigo
    case "wallpaper":
        return "#30b0c8";     // teal
    case "notifications":
        return "#ff3b30";     // system red
    case "dynamic-island":
        return "#5e5ce6";     // system indigo (top-bar dynamic island)
    case "screenshot":
        return "#ff7a59";     // coral
    case "dock":
        return systemAccent("blue", darkMode);
    case "weather":
        return "#32ade6";     // system light blue (weather)
    case "niri":
        return "#30b0c8";     // teal (niri layout & window appearance)
    case "niri-glass":
        return "#5e5ce6";     // indigo (tahoe-glass materials & blur)
    case "niri-input":
        return systemAccent("blue", darkMode);
    case "niri-animations":
        return "#ff9f0a";     // system orange (spring animations)
    case "niri-keyboard":
        return "#8e8e93";     // system gray (read-only binds viewer)
    case "startup":
        return "#ff9f0a";     // system orange
    case "health":
        return "#34c759";     // system green
    case "about":
        return "#8e8e93";     // system gray
    default:
        return accent(darkMode, accentId);
    }
}
