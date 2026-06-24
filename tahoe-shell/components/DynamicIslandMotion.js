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

var overlayMorphEasing = QtQuick.Easing.OutQuint;
var overlayColorEasing = QtQuick.Easing.InOutQuad;
var overlayProgressEasing = QtQuick.Easing.OutCubic;
