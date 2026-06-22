.pragma library
.import QtQuick as QtQuick

// Shared QML motion tokens for components that hand outer layer motion to niri.
// Durations mirror the Tahoe v2 compositor profiles closely enough that the
// fallback QML path and internal microinteractions keep the same vocabulary.

var fadeFastDuration = 120;
var menuEnterDuration = 150;
var menuExitDuration = 120;
var panelEnterDuration = 180;
var panelExitDuration = 140;
var elementMoveDuration = 130;
var elementResizeDuration = 180;

var emphasizedDecel = QtQuick.Easing.OutCubic;
var emphasizedAccel = QtQuick.Easing.InCubic;
var standardDecel = QtQuick.Easing.OutQuad;
var expressiveEffects = QtQuick.Easing.OutQuart;
