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
// Light mode fills are light cold-gray plates — dark enough to read as
// glass on white content, light enough to stay airy. Edge light and
// refraction come from the compositor material. QML hex is #AARRGGBB.
var FillPanel = "#33dce4ec";
var FillPanelBright = "#3ddce4ec";
var FillDock = "#55d8e0e8";
var FillTopBar = "#40dce4ec";
var FillPill = "#66e2e8ef";
var FillLauncher = "#3ddce4ec";
var FillBackdrop = "#2ee2e8ef";

var StrokePanel = "#24ffffff";
var StrokePanelBright = "#34ffffff";
var StrokeDock = "#44ffffff";
var StrokeTopBar = "#34ffffff";
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
