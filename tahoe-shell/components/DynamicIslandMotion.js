.pragma library
.import QtQuick as QtQuick

// Dynamic Island motion tokens. Keep Tide-derived timings here instead of
// scattering durations through chip/overlay components.
var chipColorDuration = 280;
var chipScaleDuration = 220;
var chipContentDuration = 180;

var chipColorEasing = QtQuick.Easing.InOutQuad;
var chipSettleEasing = QtQuick.Easing.OutCubic;

var overlayMorphDuration = 400;
var overlayColorDuration = 280;
var overlayContentDuration = 180;
var overlayProgressDuration = 180;
var overlayExpandedExitHoldMs = 130;
var overlayExpandedExitFadeMs = 110;
var overlayExpandedEnterFadeMs = 220;

var overlayMorphEasing = QtQuick.Easing.OutQuint;
var overlayColorEasing = QtQuick.Easing.InOutQuad;
var overlayProgressEasing = QtQuick.Easing.OutCubic;

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
