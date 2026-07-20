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
    // P1: near-solid system-settings surface (~0.96) so the panel reads as a
    // window, not a translucent popup over wallpaper.
    return darkMode ? "#f51c1c1e" : "#f5f2f2f7";
}

function panelStroke(darkMode) {
    return darkMode ? "#28ffffff" : "#24000000";
}

function sectionFill(darkMode) {
    // Quiet grouped list card — low contrast over the panel, not a second glass stack.
    return darkMode ? "#14ffffff" : "#ffffffff";
}

function sectionStroke(darkMode) {
    return darkMode ? "#18ffffff" : "#14000000";
}

function rowFill(darkMode) {
    return darkMode ? "#12ffffff" : "#0a000000";
}

function rowFillHover(darkMode) {
    return darkMode ? "#1cffffff" : "#12000000";
}

function rowStroke(darkMode) {
    return darkMode ? "#14ffffff" : "#10000000";
}

// --- Sidebar --------------------------------------------------------------

function sidebarFill(darkMode) {
    return darkMode ? "#0cffffff" : "#0a000000";
}

function sidebarStroke(darkMode) {
    return darkMode ? "#14ffffff" : "#10000000";
}

function sidebarActiveFill(darkMode) {
    // Soft accent wash (not a solid brand capsule).
    return darkMode ? "#3a0a84ff" : "#28007ff7";
}

function sidebarActiveStroke(darkMode) {
    return darkMode ? "#20ffffff" : "#14000000";
}

function sidebarHoverFill(darkMode) {
    return darkMode ? "#14ffffff" : "#0e000000";
}

// Solid secondary button fill (T16) — light gray pill, not glass wash.
function buttonFillSolid(darkMode) {
    return darkMode ? "#3a3a3c" : "#e5e5ea";
}

function buttonFillSolidHover(darkMode) {
    return darkMode ? "#48484a" : "#d1d1d6";
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
    return darkMode ? "#14ffffff" : "#ffffffff";
}

function tileFillHover(darkMode) {
    return darkMode ? "#1cffffff" : "#f5f5f7";
}

function tileStroke(darkMode) {
    return darkMode ? "#18ffffff" : "#14000000";
}

function tileStrokeHover(darkMode) {
    return darkMode ? "#24ffffff" : "#1a000000";
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

// --- Category icon color --------------------------------------------------
// Kept as a stable API for hub tiles / legacy call sites. P1 returns a single
// muted symbolic color so settings no longer rainbow-codes every domain.
// Status colors (ok/warn/danger) remain elsewhere via stateColor().

function categoryColor(key, darkMode, accentId) {
    // Neutral symbolic gray; accent only through selection / controls.
    return darkMode ? "#a1a1a6" : "#636366";
}

// --- Dynamic Island V2 surface tokens (T10) --------------------------------
// Single theme owner for island semantic colors. Do not create
// DynamicIslandTheme.js. Values match roadmap §9 "dark focus glass".
//
// Island surfaces intentionally use a neutral deep fill in both shell light
// and dark modes so the resting capsule remains a stable focus element over
// wallpaper; text contrast is calibrated for that surface.

function islandTextPrimary(darkMode) {
    return "#f7f8fa";
}

function islandTextSecondary(darkMode) {
    return "#aeb6c2";
}

function islandTextMuted(darkMode) {
    return "#7f8996";
}

// fillRole: "compact" | "transient" | "expanded"
function islandSurfaceFill(darkMode, fillRole) {
    var role = String(fillRole || "compact");
    if (role === "expanded")
        return "#df10141a"; // ~87% deep neutral
    if (role === "transient")
        return "#d610141a"; // ~84%
    return "#cc10141a";     // ~80% compact
}

function islandSurfaceStroke(darkMode, fillRole) {
    var role = String(fillRole || "compact");
    if (role === "expanded")
        return "#30ffffff";
    if (role === "transient")
        return "#28ffffff";
    return "#24ffffff";
}

function islandProgressTrack(darkMode) {
    return "#30ffffff";
}

// Island progress fill is monochrome by design (media / timer / OSD share this).
// Independent of user accent — accent remains for transport chrome (play button).
function islandProgressFill(darkMode) {
    return islandTextPrimary(darkMode);
}

function islandControlFill(darkMode) {
    return "#20ffffff";
}

function islandRecording(darkMode) {
    return darkMode ? "#ff453a" : "#ff3b30";
}

function islandCriticalEdge(darkMode) {
    return statusAttention(darkMode);
}
