.pragma library

// Shared material/radius constants for compositor-owned glass region
// declarations. TahoeGlass handles the ext-background-effect fallback when
// the private protocol is not available.

var MaterialPanel = "panel";
var MaterialPill = "pill";
var MaterialDock = "dock";
var MaterialMenu = "menu";
var MaterialToast = "toast";
var MaterialLauncher = "launcher";
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
//
// Keep light-mode glass readable over high-key white apps: pure white fill
// and white strokes vanish on Chrome/new-tab style backgrounds.
var FillPanel = "#66edf2f8";
var FillPanelBright = "#78f2f5fa";
var FillDock = "#68edf2f8";
var FillTopBar = "#5cedf2f8";
var FillPill = "#a8f4f7fb";
var FillLauncher = "#76edf2f8";
var FillBackdrop = "#18eef2f7";

var StrokePanel = "#24000000";
var StrokePanelBright = "#26000000";
var StrokeDock = "#2c000000";
var StrokeTopBar = "#22000000";
var StrokePill = "#24000000";
var StrokeLauncher = "#2a000000";
var StrokeToast = "#26000000";

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
