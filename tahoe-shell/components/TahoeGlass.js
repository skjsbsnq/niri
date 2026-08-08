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
// Light mode fills are visible cold gray-blue plates (matching the
// compositor tint) so glass reads as frosted glass even on white content —
// pure-white or too-transparent fills were invisible on white backgrounds.
// QML hex is #AARRGGBB (alpha first).
var FillPanel = "#4dd0d8e2";
var FillPanelBright = "#59d0d8e2";
var FillDock = "#80ccd6e2";
var FillTopBar = "#66d0d8e2";
var FillPill = "#8cc8d2e0";
var FillLauncher = "#59d0d8e2";
var FillBackdrop = "#40d0d8e2";

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
