.pragma library
.import QtQuick as QtQuick
.import "Motion.js" as Motion

// Dynamic Island motion tokens (T19 V2 convergence).
// Geometry: eased NumberAnimation only (glass region, no Spring).
// Content: opacity + <=6px travel; no whole-scene scale 0.9->1.
// All scene/callsite durations and easings must read these tokens
// (or Motion.js helpers). No inline Easing.OutCubic in QML scenes.

// Color / progress (shared).
var overlayColorDuration = 260;
var overlayProgressDuration = 180;
var overlayColorEasing = QtQuick.Easing.InOutQuad;
var overlayProgressEasing = QtQuick.Easing.OutCubic;

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

// Notification swipe-to-dismiss (finger-following, R07).
var notificationDismissThresholdPx = 72;
var notificationFlyOutMs = 160;

// Hover expand (settings-gated; default off for product).
var hoverExpandDelayMs = 350;
var hoverCollapseDelayMs = 250;

// --- V2 motion (authoritative geometry + content) ----------------------------
// compact->transient 220-260, compact->expanded 260-300, expanded->compact 220-260
var v2CompactToTransientMs = 240;
var v2CompactToExpandedMs = 280;
var v2ExpandedToCompactMs = 240;
// OSD geometry: fast eased expansion on first appearance (R08 #23 — content
// still owns the first frame; geometry no longer 0ms hard-cuts). Exit soft.
var v2OsdEnterMs = 80;
var v2OsdExitMs = 110;

// R08 geometry driver pipeline: springs drive island driver values only —
// the surface binds clamp(driver, min, max) and the TahoeGlass region submits
// quantized clamped values, so the region can never leave the layer surface
// even at full overshoot (guardrail 0704ea4 satisfied by construction).
// Island morph uses springBouncy stiffness with slightly higher damping so
// the content-reveal threshold (~0.55 height progress) is not followed by a
// long rubber-band tail around the already-revealed layout. Dock bounce keeps
// Motion.springBouncy unchanged.
var v2GeometrySpring = {
    spring: Motion.springBouncy.spring,
    damping: 0.28
};
// Stop the spring tail early so the settled snap engages promptly (protocol
// settle threshold in the overlay is 0.6 > this epsilon).
var v2GeometrySpringEpsilon = 0.25;

// Protocol quantization during morph (R08 #22). Width/height floor to the
// quantum so the glass region never overhangs the painted capsule (the old
// round-to-nearest-8 lifted a 36px collapse target to a 40px region — a raw
// glass bar flashing under the capsule bottom edge); radius ceils so glass
// corners recede inside the painted corner instead of protruding.
var v2ProtocolSizeQuantumPx = 2;
var v2ProtocolRadiusQuantumPx = 2;

// Content exit 100-120, enter 160-180, travel <= 6px.
var v2ContentExitMs = 110;
var v2ContentEnterMs = 170;
var v2ContentMaxTravelPx = 6;
var v2GeometryEasing = QtQuick.Easing.OutCubic;
var v2ContentEasing = QtQuick.Easing.OutCubic;

// Expanded content (media/timer) must not paint the full expanded layout
// inside a still-compact clip. Reveal only after geometry morph progress
// crosses this threshold (or the protocol region has settled).
// 0.55 ≈ mid-band of compact→expanded height (36→166) so the pill is
// already large enough for 64px art + timeline without a squashed frame.
var v2ExpandedContentRevealThreshold = 0.55;
// Minimum height growth (px) before reveal gating engages. Tiny retargets
// (e.g. measured width-only tweaks while already expanded) must not hide
// expanded chrome.
var v2ExpandedContentRevealMinDeltaPx = 12;

// Pure helper: should expanded media/timer content paint yet?
// progress is 0..1 geometryRevealProgress; heightDelta is target-base height.
function expandedContentRevealAllowed(settingsService, settled, progress, heightDelta) {
    if (settled)
        return true;
    if (Motion.reducedMotion(settingsService))
        return true;
    var delta = Number(heightDelta) || 0;
    if (!(delta >= v2ExpandedContentRevealMinDeltaPx))
        return true;
    var p = Number(progress);
    if (!isFinite(p))
        return !!settled;
    return p >= v2ExpandedContentRevealThreshold;
}

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

// R08: geometry springs are allowed only behind the shell useSpring gate and
// degrade to eased NumberAnimation under reduced motion.
function geometrySpringEnabled(settingsService, useSpring) {
    return !!useSpring && !Motion.reducedMotion(settingsService);
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
