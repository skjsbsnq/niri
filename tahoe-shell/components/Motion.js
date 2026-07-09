.pragma library
.import QtQuick as QtQuick

// Shared QML motion tokens for components that hand outer layer motion to niri.
// Durations mirror the Tahoe v2 compositor profiles closely enough that the
// fallback QML path and internal microinteractions keep the same vocabulary.
//
// Tahoe Motion 2.0 (2026-07-09, T01): Apple-style spring vocabulary + retimed
// durations. Apple response/bounce converts to niri spring (mass=1) via
//   stiffness = (2π/response)², damping-ratio = 1 − bounce
// QML SpringAnimation groups below are the hand-tuned equivalents from the
// research report §3; the matching niri KDL params live in each token comment.

var fadeFastDuration = 120;
var menuEnterDuration = 180;
var menuExitDuration = 160;
var panelEnterDuration = 320;
var panelExitDuration = 200;
var elementMoveDuration = 130;
var elementResizeDuration = 180;

var emphasizedDecel = QtQuick.Easing.OutCubic;
var emphasizedAccel = QtQuick.Easing.InCubic;
var standardDecel = QtQuick.Easing.OutQuad;
var expressiveEffects = QtQuick.Easing.OutQuart;

// Press-state token (pressIn). T05 rolls this out as the single outlet for
// every pressable element; reduced profile downgrades to instant color change.
var pressDuration = 120;
var pressScale = 0.96;
var pressEasing = QtQuick.Easing.OutQuad;

// Spring vocabulary — QML SpringAnimation parameter groups. Glass region
// geometry must never use these (guardrail 0704ea4); springs are only for
// content transforms/opacity inside panels, compositor-side channels, and
// non-glass elements, always behind the shell.useSpring gate.
var springSnappy = {
    // Apple snappy (response .28 / bounce .12) → niri: damping-ratio=0.88 stiffness=500 epsilon=0.0005
    // Menus, small popups, toggles.
    spring: 4.2,
    damping: 0.30
};
var springSmooth = {
    // Apple smooth (response .40 / bounce 0) → niri: damping-ratio=1.0 stiffness=250 epsilon=0.0005
    // Panel translation, height settle (non-glass geometry only).
    spring: 3.0,
    damping: 0.40
};
var springPanel = {
    // Apple default spring (response .50 / bounce .15) → niri: damping-ratio=0.85 stiffness=160 epsilon=0.0005
    // Control center / notification center / sidebar content.
    spring: 2.5,
    damping: 0.28
};
var springBouncy = {
    // Apple bouncy (response .50 / bounce .30) → niri: damping-ratio=0.70 stiffness=160 epsilon=0.0005
    // Dock bounce, dynamic island morph.
    spring: 2.5,
    damping: 0.22
};

var profileDurations = {
    "fast": {
        "fadeFast": 90,
        "menuEnter": 145,
        "menuExit": 130,
        "panelEnter": 260,
        "panelExit": 160,
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
        "menuEnter": 210,
        "menuExit": 185,
        "panelEnter": 370,
        "panelExit": 230,
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
