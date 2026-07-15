.pragma library
.import QtQuick as QtQuick
.import "Motion.js" as Motion

// Dynamic Island motion tokens. Keep Tide-derived timings here instead of
// scattering durations through chip/overlay components.
//
// T12: overlay morph targets springBouncy for non-glass content transforms.
// islandSurface is a GlassPanel with TahoeGlass.regions — width/height/x/radius
// drive region geometry, so those channels stay eased (no Spring/overshoot).
// Content enter scale uses springBouncy behind useSpring.

var chipColorDuration = 260;
var chipScaleDuration = 200;
var chipContentDuration = 160;

var chipColorEasing = QtQuick.Easing.InOutQuad;
var chipSettleEasing = QtQuick.Easing.OutCubic;

// Geometry morph: eased only (glass region). Duration approximates springBouncy
// settle without overshoot (emphasized-decel family).
var overlayMorphDuration = 380;
var overlayColorDuration = 260;
var overlayContentDuration = 180;
var overlayProgressDuration = 180;
var overlayExpandedExitHoldMs = 130;
var overlayExpandedExitFadeMs = 110;
var overlayExpandedEnterFadeMs = 220;

var overlayMorphEasing = QtQuick.Easing.OutCubic;
var overlayColorEasing = QtQuick.Easing.InOutQuad;
var overlayProgressEasing = QtQuick.Easing.OutCubic;

// Content switch enter: scale 0.9 → 1 (springBouncy when useSpring).
var overlayContentEnterScale = 0.9;
var overlayContentSpring = {
    spring: Motion.springBouncy.spring,
    damping: Motion.springBouncy.damping,
    epsilon: 0.001
};
// Eased fallback when useSpring is false or reduced motion.
var overlayContentScaleDuration = 220;
var overlayContentScaleEasing = QtQuick.Easing.OutCubic;

// Side-swipe (T07). Thresholds and timing mirror Tide's side-swipe feel.
var swipeSettleDuration = 220;
var swipeSettleEasing = QtQuick.Easing.OutCubic;
var swipeEnterThreshold = 0.56;
var swipeReturnThreshold = 0.44;
var swipeVerticalTolerance = 24;
// Gesture arming (Task 11): press stays click-eligible until horizontal
// displacement crosses the arm threshold. Dominant vertical motion rejects
// click without starting a meaningless settle path.
var swipeArmThresholdPx = 10;
var swipeVerticalRejectPx = 20;
var swipeSettleIdleMs = 150;
var swipeSuppressClickMs = 180;

// Hover expand (T09). Matches the Tide-derived hover timing guardrails.
var hoverExpandDelayMs = 350;
var hoverCollapseDelayMs = 250;

// Media visualizer (Task 21): one phase owner, update period matched to bar
// height settle so 5× NumberAnimation are not continuously redirected.
// Old path: 64ms phase tick into 120ms height Behaviors → perpetual retarget.
var visualizerUpdateMs = 120;
var visualizerPhaseStep = 0.34;
var visualizerPlayingDuration = 120;
var visualizerPausedDuration = 260;

// --- V2 motion tokens (T10 baseline; production migrates in T19) ------------
// Geometry stays eased NumberAnimation only (glass region, no Spring).
// Content enter no longer defaults to whole-scene scale 0.9 → 1.

var v2CompactToTransientMs = 240;
var v2CompactToExpandedMs = 280;
var v2ExpandedToCompactMs = 240;
// OSD is direct manipulation feedback. Its first frame must not wait for the
// decorative capsule/content enter animations used by other transient scenes.
var v2OsdEnterMs = 0;
var v2OsdExitMs = 110;
var v2ContentExitMs = 110;
var v2ContentEnterMs = 170;
var v2ContentMaxTravelPx = 6;
var v2GeometryEasing = QtQuick.Easing.OutCubic;
var v2ContentEasing = QtQuick.Easing.OutCubic;
var v2ReducedGeometryMs = 80;
var v2ReducedContentMs = 80;

// V2 radius caps (roadmap §9.3). Compact still tracks half-height; expanded
// must not use height/2 ellipse morph.
var v2RadiusCompactClock = 16;     // 32px height
var v2RadiusCompactMedia = 18;     // 36px height
var v2RadiusOsd = 22;              // 44px height
var v2RadiusNotificationMin = 22;
var v2RadiusNotificationMax = 26;
var v2RadiusExpandedMin = 28;
var v2RadiusExpandedMax = 32;

// V2 geometry baselines (logical px, roadmap §9.4). Production clamps later.
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
