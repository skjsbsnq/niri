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
var swipeSettleIdleMs = 150;
var swipeSuppressClickMs = 180;

// Hover expand (T09). Matches the Tide-derived hover timing guardrails.
var hoverExpandDelayMs = 350;
var hoverCollapseDelayMs = 250;
