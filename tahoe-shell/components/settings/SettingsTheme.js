.pragma library

// Tahoe settings design tokens. Light-mode values match the S1 baseline (only
// accentBlue changed #2c9cf2 -> #007ff7 per the macOS reference); every token
// now also resolves a dark-mode variant so the panel stays readable when
// shell.darkMode is on. Brand category colors are solid macOS system colors
// and read well in both modes.

// --- Text -----------------------------------------------------------------

function textPrimary(darkMode) {
    return darkMode ? "#f5f7fb" : "#1d1d1f";
}

function textSecondary(darkMode) {
    return darkMode ? "#c3ccd6" : "#721d1d1f";
}

function textMuted(darkMode) {
    return darkMode ? "#94a0ad" : "#5f6870";
}

// --- Accent / state -------------------------------------------------------

function accentBlue(darkMode) {
    // macOS system blue: #007ff7 (light, Web reference) / #0a84ff (dark).
    return darkMode ? "#0a84ff" : "#007ff7";
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

function stateColor(state, darkMode) {
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
    return accentBlue(darkMode);
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

function accentFillStrong(darkMode) {
    // Primary button fill: accent blue at ~85% alpha.
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

function fieldStrokeFocus(darkMode) {
    return accentBlue(darkMode);
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

// --- Overlay scrim --------------------------------------------------------

function scrim(darkMode) {
    return darkMode ? "#33000000" : "#1a101418";
}

// --- Brand category colors ------------------------------------------------
// One solid accent per legacy summary category. The sidebar uses symbolic
// icons instead of category color blocks.

function categoryColor(key, darkMode) {
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
        return "#0a84ff";     // system blue
    case "weather":
        return "#32ade6";     // system light blue (weather)
    case "niri":
        return "#30b0c8";     // teal (niri layout & window appearance)
    case "niri-glass":
        return "#5e5ce6";     // indigo (tahoe-glass materials & blur)
    case "niri-input":
        return "#0a84ff";     // system blue (keyboard/touchpad/display)
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
        return accentBlue(darkMode);
    }
}
