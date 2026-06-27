.pragma library

// Shared material/radius constants for compositor-owned TahoeGlassRegion
// declarations. TahoeGlass handles the ext-background-effect fallback when
// the private protocol is not available.

var MaterialPanel = "panel";
var MaterialPill = "pill";
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
var FillPanel = "#14ffffff";
var FillPanelBright = "#18f7f8fb";
var FillDock = "#24f7fbff";
var FillTopBar = "#22f7fbff";
var FillPill = "#80f7fbff";
var FillBackdrop = "#12eef2f7";

var StrokePanel = "#24ffffff";
var StrokePanelBright = "#34ffffff";
var StrokeDock = "#30ffffff";
var StrokeTopBar = "#34ffffff";
var StrokePill = "#48ffffff";
var StrokeToast = "#34ffffff";
