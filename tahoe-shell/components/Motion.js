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

// Menu selection flash (T06). Two half-cycles of highlight at this interval
// before the parent closes the menu and runs the action.
var menuFlashInterval = 70;
var menuFlashCount = 2;

// Dock magnification wave (T07 / T08-fix9). Cosine-bell attenuation:
//   scale(d) = 1 + (peak − 1) · cos²(πd / 2R)   for d < R, else 1
// R is measured in icon widths (dockMagRangeIcons × iconSize). Analytical
// push positions use the same curve; never drive glass region geometry with it.
//
// Hand-feel targets (macOS-like sweep):
//  - peak ≈1.62 — clear pop without a harsh spike
//  - range ≈3.2 icon-widths — soft multi-icon skirt so neighbors blend
//  - follow ≈170ms SmoothedAnimation — continuous retarget (not 90ms
//    OutCubic NumberAnimation restarts, which felt fast and choppy)
// Glass stays rest-sized; mag/push never drive glass geometry.
var dockMagPeak = 1.62;
var dockMagRangeIcons = 3.2;
// Legacy spring group kept for tests / optional future use. Wave path uses
// SmoothedAnimation (duration-based, velocity=-1) — never Spring.restart().
var dockMagSpring = {
    spring: 3.2,
    damping: 0.52,
    epsilon: 0.001
};
// Approximate settle time for mag/push SmoothedAnimation (velocity: -1).
// Longer + InOutQuad → elegant cross-icon blend while sweeping.
var dockMagFollowMs = 170;

// Dock launch bounce loop + autohide (T08). Parabolic cycle while an app is
// launching: height ≈ factor×icon, period ms, InQuad up / OutQuad down.
// Stops on appHasRunningWindow or timeout. Reveal debounce suppresses edge jitter.
var dockLaunchBounceHeightFactor = 0.7;
var dockLaunchBouncePeriodMs = 550;
var dockLaunchBounceTimeoutMs = 10000;
// T08-fix4: edge-enter debounce must NOT restart on every positionChanged
// (that made autohide feel stuck). Keep a short single-shot only.
var dockRevealDebounceMs = 40;
// Autohide slide distance fallback (px). Dock.qml uses max(this, surfaceHeight)
// so a taller panel never leaves a strip at the bottom (T08-fix).
var dockAutohideSlidePx = 88;

function dockLaunchBounceHeight(iconSizePx) {
    var size = iconSizePx > 0 ? iconSizePx : 48;
    return size * dockLaunchBounceHeightFactor;
}

// Notification toast stack + swipe dismiss (T09). Stack count lives in
// DesktopSettings.notificationToastStackMax (default 3). Glass region geometry
// still uses eased NumberAnimation only; springPanel drives content transforms.
var toastStackMaxDefault = 3;
var toastStackYStep = 8;
var toastStackScaleStep = 0.04; // index 0 → 1.0, 1 → 0.96, 2 → 0.92
var toastEnterOffsetPx = 60;
var toastSwipeEnterThreshold = 0.56; // share DynamicIslandMotion enter feel
var toastSwipeReturnThreshold = 0.44;
var toastSwipeVerticalTolerance = 24;
var toastSwipeDismissPx = 96; // absolute px fallback if width unknown
var toastClearStaggerMs = 30;
var toastClearStaggerBudgetMs = 450;
var toastClearStaggerMaxItems = 40;
var toastHoverLiftPx = 4;

function toastStackScaleForIndex(stackIndex) {
    var idx = Math.max(0, Math.round(Number(stackIndex) || 0));
    return Math.max(0.88, 1.0 - idx * toastStackScaleStep);
}

function toastStackYForIndex(stackIndex) {
    var idx = Math.max(0, Math.round(Number(stackIndex) || 0));
    return idx * toastStackYStep;
}

function toastClearStaggerDelay(index, total) {
    var n = Math.min(toastClearStaggerMaxItems, Math.max(0, Math.round(Number(total) || 0)));
    var i = Math.max(0, Math.round(Number(index) || 0));
    if (n <= 0 || i >= n)
        return 0;
    var step = toastClearStaggerMs;
    if (step * (n - 1) > toastClearStaggerBudgetMs && n > 1)
        step = Math.floor(toastClearStaggerBudgetMs / (n - 1));
    return Math.min(toastClearStaggerBudgetMs, i * step);
}

// Control Center control feel (T10) + module morph (T11).
// Glass region height/width must use eased NumberAnimation only (no spring).
var ccPanelWidth = 330;
var ccTilePressScale = 0.97;
var ccSliderKnobDragScale = 1.15;
var ccToggleBounceMs = 200;
var ccToggleColorMs = 200;
var ccMorphDurationMs = 280; // emphasized panel height expand/collapse
var ccMorphSiblingOffsetPx = 8;
var ccMorphListMaxHeight = 220;

// Settings shell page transition (T15). Glass region geometry is unchanged;
// only content opacity/x animate (emphasized, no spring).
var settingsPageTransitionMs = 280;
var settingsPageEnterOffsetPx = 24;
var settingsPageExitOffsetPx = 12;

function settingsPageTransition(settingsService) {
    return reducedMotion(settingsService) ? 0 : settingsPageTransitionMs;
}

// Spotlight (T17). Single glass panel; height uses eased NumberAnimation only
// (no spring on glass region geometry). Selection highlight y may spring.
var spotlightHeightMs = 250;
var spotlightPreviewFadeMs = 150;
var spotlightPreviewWidth = 220;
var spotlightRowHeight = 44;
var spotlightGroupHeaderHeight = 28;
var spotlightSearchRowHeight = 56;
var spotlightMaxResults = 12;
var spotlightMinPanelHeight = 56;
var spotlightMaxListHeight = 360;

function spotlightHeightDuration(settingsService) {
    return reducedMotion(settingsService) ? 0 : spotlightHeightMs;
}

function spotlightPreviewFade(settingsService) {
    return reducedMotion(settingsService) ? 0 : spotlightPreviewFadeMs;
}

// Launchpad (T18 + hand-feel fix). Full-screen QML path only (rules §2.11).
// Wallpaper zoom is content-side on Wallpaper.qml.
// Hand-feel: icons reveal together (short unified fade/scale), not one-by-one
// distance stagger — the old per-icon opacity:0 + long stagger looked like
// "only one icon then the rest". Paging uses intent thresholds (short drag OR
// light flick commits a page) — not "drag past 50% / until icons vanish".
var launchpadWallpaperScale = 1.06;
var launchpadWallpaperDim = 0.25;
var launchpadWallpaperMs = 400;
// Soft unified enter (whole grid), not per-icon cascade.
var launchpadIconEnterMs = 280;
var launchpadIconEnterScaleFrom = 0.92;
// Whole-layer open/close (opacity + soft settle). Explicit progress so close
// still animates after open flips false.
var launchpadLayerEnterMs = 280;
var launchpadLayerExitMs = 200;
var launchpadLayerScaleFrom = 0.985;
// Icon launch pop before layer exit.
var launchpadLaunchPopMs = 180;
var launchpadLaunchPopScaleBoost = 0.18;
// Page snap after intent decision.
var launchpadPageSnapMs = 240;
// iOS-like paging: short drag OR any intentional flick advances one page.
// Thresholds are intentionally low — "press and fling" must commit.
var launchpadPageCommitRatio = 0.08;
var launchpadPageCommitMinPx = 28;
// Capture at finger-up (not after coast). Units ≈ px/s in Flickable.
var launchpadPageFlickVelocity = 80;
var launchpadStaggerPerPxMs = 0; // disabled cascade (kept for API/tests)
var launchpadStaggerBudgetMs = 450;
var launchpadStaggerMaxItems = 40;
var launchpadGridCols = 7;
var launchpadGridRows = 5;
var launchpadPageDotsHeight = 28;

function launchpadWallpaperDuration(settingsService) {
    return reducedMotion(settingsService) ? 0 : launchpadWallpaperMs;
}

function launchpadIconEnterDuration(settingsService) {
    return reducedMotion(settingsService) ? 0 : launchpadIconEnterMs;
}

function launchpadLayerEnterDuration(settingsService) {
    return reducedMotion(settingsService) ? 0 : launchpadLayerEnterMs;
}

function launchpadLayerExitDuration(settingsService) {
    return reducedMotion(settingsService) ? 0 : launchpadLayerExitMs;
}

function launchpadLaunchPopDuration(settingsService) {
    return reducedMotion(settingsService) ? 0 : launchpadLaunchPopMs;
}

function launchpadPageSnapDuration(settingsService) {
    return reducedMotion(settingsService) ? 0 : launchpadPageSnapMs;
}

function launchpadStaggerDelay(distanceFromCenterPx, index, total) {
    // Cascade disabled: return 0 so all icons share one enter timeline.
    return 0;
}

// Left sidebar widget stack (T19 + polish). Short, subtle card rise — avoid
// long opacity-0 cascades that make the panel feel empty then "pop in".
var sidebarCardStaggerMs = 24;
var sidebarCardEnterOffsetPx = 10;
var sidebarCardStaggerBudgetMs = 280;
var sidebarCardStaggerMaxItems = 12;
var sidebarCardEnterMs = 260;

function sidebarCardStaggerDelay(index) {
    var i = Math.max(0, Math.round(Number(index) || 0));
    if (i >= sidebarCardStaggerMaxItems)
        return sidebarCardStaggerBudgetMs;
    var delay = i * sidebarCardStaggerMs;
    return Math.min(sidebarCardStaggerBudgetMs, delay);
}

function sidebarCardEnterDuration(settingsService) {
    return reducedMotion(settingsService) ? 0 : sidebarCardEnterMs;
}

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

function reducedMotion(settingsService) {
    return normalizedProfileName(settingsService) === "reduced";
}

function pressDurationFor(settingsService) {
    return reducedMotion(settingsService) ? 0 : pressDuration;
}

function pressScaleFor(settingsService, pressed) {
    return pressed && !reducedMotion(settingsService) ? pressScale : 1.0;
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

// Cosine-bell dock magnification. Pure function of distance in px;
// Dock keeps layout sizes local and only imports peak/range from here.
function dockCosineScale(distancePx, iconSizePx) {
    var size = iconSizePx > 0 ? iconSizePx : 48;
    var R = dockMagRangeIcons * size;
    if (R <= 0)
        return 1.0;
    var d = Math.abs(distancePx);
    if (d >= R)
        return 1.0;
    var c = Math.cos(Math.PI * d / (2 * R));
    return 1.0 + (dockMagPeak - 1.0) * c * c;
}
