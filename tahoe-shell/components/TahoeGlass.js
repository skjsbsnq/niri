.pragma library

// Phase 3 constants for the future compositor-owned TahoeGlassRegion API.
// QML still uses BackgroundEffect.blurRegion as fallback, but every glass
// object now has a single material/radius vocabulary to migrate from.

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

var FillPanel = "#20ffffff";
var FillPanelBright = "#20f7f8fb";
var FillDock = "#38f7fbff";
var FillTopBar = "#1cffffff";
var FillPill = "#eef7fbff";
var FillBackdrop = "#30eef2f7";

var StrokePanel = "#46ffffff";
var StrokePanelBright = "#70ffffff";
var StrokeDock = "#5cffffff";
var StrokeTopBar = "#36ffffff";
var StrokePill = "#88ffffff";
var StrokeInner = "#24ffffff";
var ShadowLine = "#14000000";
var ShadowLineSoft = "#16000000";
