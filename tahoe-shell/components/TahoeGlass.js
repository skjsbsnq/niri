.pragma library

// Shared material/radius constants for compositor-owned glass region
// declarations. TahoeGlass handles the ext-background-effect fallback when
// the private protocol is not available.

var MaterialPanel = "panel";
var MaterialPill = "pill";
var MaterialLauncher = "launcher";
var MaterialDock = "dock";
var MaterialMenu = "menu";
var MaterialToast = "toast";
var MaterialBackdrop = "backdrop";

var RadiusPanel = 28;
var RadiusPanelCompact = 18;
var RadiusPill = 33;
var RadiusDock = 24;
var RadiusMenu = 18;
var RadiusToast = 18;
var RadiusBackdrop = 0;
var RadiusTopBar = 18;
var RadiusPopup = 24;

// Phase 3: QML only provides tint/fallback weight. Edge highlight,
// refraction, shadow, and depth belong to the compositor material.
// macOS 26 liquid-glass recipe: white translucent fill (15-40%) + white
// edge glow, NOT gray — the glass reads through brightness + edge light.
// QML hex is #AARRGGBB (alpha first).
var FillPanel = "#33ffffff";
var FillPanelBright = "#3dffffff";
var FillDock = "#26ffffff";
var FillTopBar = "#33ffffff";
var FillPill = "#59ffffff";
var FillLauncher = "#3dffffff";
var FillBackdrop = "#26ffffff";
// Desktop widgets (A8): macOS Sonoma/Sequoia adaptive glass. Dark mode =
// translucent white glass (~24%) + white hairline; light mode = near-white
// glass (~90%) + subtle dark hairline. Text/icon colors adapt via the
// widget's darkMode (see Widget.qml textPrimary/textSecondary/textTertiary).
function widgetFill(darkMode) {
    return darkMode ? "#3dffffff" : "#e6ffffff";
}
function widgetStroke(darkMode) {
    return darkMode ? "#40ffffff" : "#2e000000";
}
// macOS widget card curvature: small/medium ≈ 15% of the short edge
// (capped 24px), large ≈ 10% (capped 36px). Deployment feedback (A8):
// the original 24%/14% caps read as exaggerated on the desktop; 22-24px
// small/medium and 31-34px large match macOS Notification Center widgets.
// size + minDim come from the widget instance.
function widgetRadius(size, minDim) {
    var m = Math.max(1, Math.round(Number(minDim) || 1));
    if (String(size || "") === "large")
        return Math.min(36, Math.round(m * 0.10));
    return Math.min(24, Math.round(m * 0.15));
}

var StrokePanel = "#24ffffff";
var StrokePanelBright = "#34ffffff";
var StrokeDock = "#1affffff";
var StrokeTopBar = "#14ffffff";
var StrokePill = "#48ffffff";
var StrokeLauncher = "#32ffffff";
var StrokeToast = "#34ffffff";

function radiusForMaterial(material) {
    switch (material) {
    case MaterialPill:
        return RadiusPill;
    case MaterialDock:
        return RadiusDock;
    case MaterialMenu:
        return RadiusMenu;
    case MaterialToast:
        return RadiusToast;
    case MaterialLauncher:
        return RadiusPanel;
    case MaterialBackdrop:
        return RadiusBackdrop;
    case MaterialPanel:
    default:
        return RadiusPanel;
    }
}

function fillForMaterial(material) {
    switch (material) {
    case MaterialPill:
        return FillPill;
    case MaterialDock:
        return FillDock;
    case MaterialLauncher:
        return FillLauncher;
    case MaterialBackdrop:
        return FillBackdrop;
    case MaterialMenu:
        return FillPanelBright;
    case MaterialPanel:
    case MaterialToast:
    default:
        return FillPanel;
    }
}

function strokeForMaterial(material) {
    switch (material) {
    case MaterialPill:
        return StrokePill;
    case MaterialDock:
        return StrokeDock;
    case MaterialMenu:
        return StrokePanelBright;
    case MaterialLauncher:
        return StrokeLauncher;
    case MaterialToast:
        return StrokeToast;
    case MaterialPanel:
    case MaterialBackdrop:
    default:
        return StrokePanel;
    }
}
