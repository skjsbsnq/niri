.pragma library

function textPrimary(darkMode) {
    return "#1d1d1f";
}

function textSecondary(darkMode) {
    return "#721d1d1f";
}

function textMuted(darkMode) {
    return "#5f6870";
}

function accentBlue(darkMode) {
    return "#2c9cf2";
}

function sectionFill(darkMode) {
    return "#24ffffff";
}

function sectionStroke(darkMode) {
    return "#38ffffff";
}

function rowFill(darkMode) {
    return "#28ffffff";
}

function rowFillHover(darkMode) {
    return "#48ffffff";
}

function rowStroke(darkMode) {
    return "#32ffffff";
}

function stateLabel(state) {
    if (state === "ok")
        return "正常";
    if (state === "warn")
        return "注意";
    if (state === "missing")
        return "缺失";
    return "信息";
}

function stateColor(state) {
    if (state === "ok")
        return "#34c759";
    if (state === "warn")
        return "#ff9f0a";
    if (state === "missing")
        return "#ff453a";
    return "#2c9cf2";
}
