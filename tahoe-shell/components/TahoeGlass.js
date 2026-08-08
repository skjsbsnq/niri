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
// Light mode fills are cold gray-blue (matching the compositor tint) so
// glass stays visible on white content — pure-white fills washed it out.
// QML hex is #AARRGGBB (alpha first).
var FillPanel = "#14dce6f0";
var FillPanelBright = "#18dce6f0";
var FillDock = "#2adce6f0";
var FillTopBar = "#22dce6f0";
var FillPill = "#80dce6f0";
var FillLauncher = "#1cdce6f0";
var FillBackdrop = "#12dce6f0";

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
