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

var profileDurations = {
    "fast": {
        "fadeFast": 90,
        "menuEnter": 120,
        "menuExit": 90,
        "panelEnter": 150,
        "panelExit": 110,
        "elementMove": 110,
        "elementResize": 140
    },
    "balanced": {
        "fadeFast": fadeFastDuration,
        "menuEnter": menuEnterDuration,
        "menuExit": menuExitDuration,
        "panelEnter": panelEnterDuration,
        "panelExit": panelExitDuration,
        "elementMove": elementMoveDuration,
        "elementResize": elementResizeDuration
    },
    "liquid": {
        "fadeFast": 140,
        "menuEnter": 170,
        "menuExit": 140,
        "panelEnter": 210,
        "panelExit": 160,
        "elementMove": 150,
        "elementResize": 210
    },
    "reduced": {
        "fadeFast": 70,
        "menuEnter": 70,
        "menuExit": 60,
        "panelEnter": 80,
        "panelExit": 60,
        "elementMove": 0,
        "elementResize": 0
    }
};

function normalizedProfileName(settingsService) {
    var name = settingsService && settingsService.motionProfile
        ? String(settingsService.motionProfile)
        : "balanced";
    return profileDurations[name] ? name : "balanced";
}

function profileDuration(settingsService, key) {
    var profile = profileDurations[normalizedProfileName(settingsService)];
    return profile[key];
}

function fadeFast(settingsService) {
    return profileDuration(settingsService, "fadeFast");
}

function menuEnter(settingsService) {
    return profileDuration(settingsService, "menuEnter");
}

function menuExit(settingsService) {
    return profileDuration(settingsService, "menuExit");
}

function panelEnter(settingsService) {
    return profileDuration(settingsService, "panelEnter");
}

function panelExit(settingsService) {
    return profileDuration(settingsService, "panelExit");
}

function elementMove(settingsService) {
    return profileDuration(settingsService, "elementMove");
}

function elementResize(settingsService) {
    return profileDuration(settingsService, "elementResize");
}
