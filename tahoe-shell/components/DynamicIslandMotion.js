.pragma library
.import QtQuick as QtQuick
.import "Motion.js" as Motion

// Dynamic Island motion tokens (T19 V2 convergence).
// Geometry: eased NumberAnimation only (glass region, no Spring).
// Content: opacity + <=6px travel; no whole-scene scale 0.9->1.
// All scene/callsite durations and easings must read these tokens
// (or Motion.js helpers). No inline Easing.OutCubic in QML scenes.

// Chip (legacy DynamicIslandChip paths if still referenced).
var chipColorDuration = 260;
var chipScaleDuration = 200;
var chipContentDuration = 160;
var chipColorEasing = QtQuick.Easing.InOutQuad;
var chipSettleEasing = QtQuick.Easing.OutCubic;

// Color / progress (shared).
var overlayColorDuration = 260;
var overlayProgressDuration = 180;
var overlayColorEasing = QtQuick.Easing.InOutQuad;
var overlayProgressEasing = QtQuick.Easing.OutCubic;

// Content fade aliases (map to V2 content tokens below for one source of truth).
// Prefer v2ContentExitMs / v2ContentEnterMs at call sites.
var overlayContentDuration = 170;          // == v2ContentEnterMs mid-band
var overlayExpandedExitFadeMs = 110;       // == v2ContentExitMs
var overlayExpandedEnterFadeMs = 170;      // == v2ContentEnterMs

// Side-swipe.
var swipeSettleDuration = 220;
var swipeSettleEasing = QtQuick.Easing.OutCubic;
var swipeEnterThreshold = 0.56;
var swipeReturnThreshold = 0.44;
var swipeVerticalTolerance = 24;
var swipeArmThresholdPx = 10;
var swipeVerticalRejectPx = 20;
var swipeSettleIdleMs = 150;
var swipeSuppressClickMs = 180;

// Hover expand (settings-gated; default off for product).
var hoverExpandDelayMs = 350;
var hoverCollapseDelayMs = 250;

// --- V2 motion (authoritative geometry + content) ----------------------------
// compact->transient 220-260, compact->expanded 260-300, expanded->compact 220-260
var v2CompactToTransientMs = 240;
var v2CompactToExpandedMs = 280;
var v2ExpandedToCompactMs = 240;
// Legacy name kept as alias so residual references resolve to V2 expanded morph.
var overlayMorphDuration = v2CompactToExpandedMs;
var overlayMorphEasing = QtQuick.Easing.OutCubic;

// OSD: first frame immediate; exit soft.
var v2OsdEnterMs = 0;
var v2OsdExitMs = 110;

// Content exit 100-120, enter 160-180, travel <= 6px.
var v2ContentExitMs = 110;
var v2ContentEnterMs = 170;
var v2ContentMaxTravelPx = 6;
var v2GeometryEasing = QtQuick.Easing.OutCubic;
var v2ContentEasing = QtQuick.Easing.OutCubic;

// reduced motion: geometry 0-100, content opacity only (no spatial travel).
var v2ReducedGeometryMs = 80;
var v2ReducedContentMs = 80;

// Helpers (pure; settingsService optional).
function geometryDurationMs(settingsService, kind) {
    if (Motion.reducedMotion(settingsService))
        return v2ReducedGeometryMs;
    var k = String(kind || "expanded");
    if (k === "transient")
        return v2CompactToTransientMs;
    if (k === "collapse")
        return v2ExpandedToCompactMs;
    return v2CompactToExpandedMs;
}

function contentExitMs(settingsService) {
    return Motion.reducedMotion(settingsService) ? v2ReducedContentMs : v2ContentExitMs;
}

function contentEnterMs(settingsService) {
    return Motion.reducedMotion(settingsService) ? v2ReducedContentMs : v2ContentEnterMs;
}

function contentTravelPx(settingsService) {
    return Motion.reducedMotion(settingsService) ? 0 : v2ContentMaxTravelPx;
}

// V2 radius caps (roadmap §9.3).
var v2RadiusCompactClock = 16;
var v2RadiusCompactMedia = 18;
var v2RadiusOsd = 22;
var v2RadiusNotificationMin = 22;
var v2RadiusNotificationMax = 26;
var v2RadiusExpandedMin = 28;
var v2RadiusExpandedMax = 32;

// V2 geometry baselines (logical px, roadmap §9.4).
var v2ClockHeight = 32;
var v2ClockWidthMin = 112;
var v2ClockWidthMax = 136;
var v2CompactMediaHeight = 36;
var v2CompactMediaWidthMin = 200;
var v2CompactMediaWidthMax = 224;
var v2OsdHeight = 44;
var v2OsdWidthMin = 220;
var v2OsdWidthMax = 240;
var v2WorkspaceHeight = 36;
var v2WorkspaceWidthMin = 140;
var v2WorkspaceWidthMax = 168;
var v2NotificationCompactHeightMin = 60;
var v2NotificationCompactHeightMax = 80;
var v2NotificationCompactWidthMin = 300;
var v2NotificationCompactWidthMax = 420;
var v2MediaExpandedWidthMin = 404;
var v2MediaExpandedWidthMax = 432;
var v2MediaExpandedHeightMin = 160;
var v2MediaExpandedHeightMax = 172;
var v2NotificationExpandedWidthMin = 380;
var v2NotificationExpandedWidthMax = 440;
var v2NotificationExpandedHeightMin = 96;
var v2NotificationExpandedHeightMax = 176;
var v2TimerExpandedWidthMin = 340;
var v2TimerExpandedWidthMax = 380;
var v2TimerExpandedHeightMin = 136;
var v2TimerExpandedHeightMax = 152;
var v2CompactTopInset = 4;
var v2ScreenMargin = 16;
