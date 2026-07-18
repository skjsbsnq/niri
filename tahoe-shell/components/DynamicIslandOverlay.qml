pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "DynamicIslandMotion.js" as IslandMotion
import "TahoeGlass.js" as GlassStyle
import "DynamicIslandOwnership.js" as IslandOwnership
import "settings/SettingsTheme.js" as Theme

PanelWindow {
    id: root

    property var dynamicIslandService
    property var settingsService
    property bool fullscreenActive: false
    // useSpring gates the R08 geometry driver springs (and content-transform
    // springs downstream). Glass region submission reads clamped + quantized
    // driver output only — never a SpringAnimation directly.
    property bool useSpring: false
    property bool darkMode: false
    readonly property string islandState: dynamicIslandService ? String(dynamicIslandService.presentation || "resting_time") : "resting_time"
    readonly property string geometryState: islandState
    readonly property string displayText: dynamicIslandService ? String(dynamicIslandService.displayText || "") : ""
    readonly property string secondaryText: dynamicIslandService ? String(dynamicIslandService.secondaryText || "") : ""
    readonly property string iconCode: dynamicIslandService ? String(dynamicIslandService.iconCode || "") : ""
    readonly property string ownScreenName: root.screen ? String(root.screen.name || "") : ""
    readonly property string targetScreenName: dynamicIslandService ? String(dynamicIslandService.targetScreenName || "") : ""
    readonly property bool islandEnabled: dynamicIslandService ? !!dynamicIslandService.islandEnabled : true
    readonly property bool dynamicIslandHideTopbarTime: dynamicIslandService ? !!dynamicIslandService.dynamicIslandHideTopbarTime : true
    readonly property bool hoverExpandEnabled: dynamicIslandService ? !!dynamicIslandService.dynamicIslandHoverExpand : false
    readonly property bool swipeInteractive: dynamicIslandService ? !!dynamicIslandService.swipeDragging : false
    readonly property bool swipeSettling: dynamicIslandService ? !!dynamicIslandService.swipeSettling : false
    // T08: pure per-screen role — resting clocks on every screen; activity only on owner.
    readonly property var screenRole: IslandOwnership.screenPresentationRole(
        ownScreenName,
        targetScreenName,
        geometryState,
        {
            "islandEnabled": islandEnabled,
            "hideTopbarTime": dynamicIslandHideTopbarTime,
            "swipeInteractive": swipeInteractive,
            "swipeSettling": swipeSettling
        })
    readonly property bool activeForScreen: !!dynamicIslandService && !!screenRole && !!screenRole.isOwner
    readonly property bool capsuleShown: !!dynamicIslandService && !!screenRole && !!screenRole.showIslandCapsule
    // Non-owner surfaces always present resting_time geometry/content while owner
    // may show activity. Effective presentation for this screen only.
    readonly property string effectiveGeometryState: (!!screenRole && screenRole.showActivity)
        ? geometryState
        : "resting_time"
    readonly property string desiredContentState: (!!screenRole && screenRole.showActivity)
        ? islandState
        : "resting_time"
    readonly property string effectiveContentState: desiredContentState
    // R07: geometry and content start at the same instant. Scene-to-scene
    // transitions are per-scene crossfades inside DynamicIslandContent
    // (outgoing keeps rendering while fading; incoming fades in on top), so
    // there is no staged full-hide swap and no blank-capsule frame.
    // Non-owner screens always render the resting clock, never owner activity text.
    readonly property string contentDisplayText: (!!screenRole && screenRole.showActivity)
        ? displayText
        : (dynamicIslandService ? String(dynamicIslandService.fallbackTimeText || displayText) : displayText)
    readonly property string contentSecondaryText: (!!screenRole && screenRole.showActivity)
        ? secondaryText
        : ""
    readonly property string contentIconCode: (!!screenRole && screenRole.showActivity)
        ? iconCode
        : "\ue8b5"
    // T12: split clock labels for RestingClockView. Non-owner / base always uses service clock.
    readonly property string contentClockWeekday: dynamicIslandService
        ? String(dynamicIslandService.clockWeekdayText || "")
        : ""
    readonly property string contentClockTime: dynamicIslandService
        ? String(dynamicIslandService.clockTimeText || "")
        : ""
    // Horizontal padding around measured clock row (matches content host margins).
    readonly property int restingClockHorizontalPad: 28
    // Compact media horizontal pad around measured content (T16).
    readonly property int compactMediaHorizontalPad: 0
    readonly property string accentId: settingsService ? String(settingsService.accentColor || "blue") : "blue"
    readonly property color accentColor: Theme.accent(root.darkMode, root.accentId)
    readonly property color progressTrackColor: Theme.islandProgressTrack(root.darkMode)
    readonly property real progress: (!!screenRole && screenRole.showActivity && dynamicIslandService)
        ? Number(dynamicIslandService.progress)
        : -1
    readonly property bool contentOsdMuted: (!!screenRole && screenRole.showActivity && dynamicIslandService)
        ? !!dynamicIslandService.transientOsdMuted
        : false
    readonly property bool contentOsdExiting: (!!screenRole && screenRole.showActivity && dynamicIslandService)
        ? !!dynamicIslandService.transientOsdExiting
        : false
    readonly property bool osdImmediateGeometry: dynamicIslandService
        ? !!dynamicIslandService.transientOsdImmediate
        : false
    readonly property string contentNotificationAppName: (!!screenRole && screenRole.showActivity && dynamicIslandService)
        ? String(dynamicIslandService.transientNotificationAppName || "")
        : ""
    readonly property string contentNotificationIconUrl: (!!screenRole && screenRole.showActivity && dynamicIslandService)
        ? String(dynamicIslandService.transientNotificationIconUrl || "")
        : ""
    readonly property string contentNotificationUrgency: (!!screenRole && screenRole.showActivity && dynamicIslandService)
        ? String(dynamicIslandService.transientNotificationUrgency || "normal")
        : "normal"
    readonly property bool contentNotificationHasOverflow: (!!screenRole && screenRole.showActivity && dynamicIslandService)
        ? !!dynamicIslandService.transientNotificationHasOverflow
        : false
    readonly property bool contentNotificationExpanded: (!!screenRole && screenRole.showActivity && dynamicIslandService)
        ? !!dynamicIslandService.transientNotificationExpanded
        : false
    readonly property var contentNotificationActions: (!!screenRole && screenRole.showActivity && dynamicIslandService)
        ? (dynamicIslandService.transientNotificationActions || [])
        : []
    readonly property int screenWidth: Math.max(1, Number(root.screen && root.screen.width) || root.width)
    readonly property int screenHeight: Math.max(1, Number(root.screen && root.screen.height) || root.height)
    readonly property real swipePreviewWidth: dynamicIslandService ? Number(dynamicIslandService.swipePreviewWidth) : -1
    // V2 surface: keep pill glass within screen margins (roadmap §9.4).
    readonly property int maxCapsuleWidth: Math.max(1, screenWidth - (IslandMotion.v2ScreenMargin * 2))
    // Height: design max, also clamp to remaining screen below the compact top inset.
    readonly property int maxCapsuleHeight: Math.max(1, Math.min(
        Math.max(
            IslandMotion.v2MediaExpandedHeightMax,
            IslandMotion.v2NotificationExpandedHeightMax,
            220),
        Math.max(1, screenHeight - IslandMotion.v2CompactTopInset - IslandMotion.v2ScreenMargin)))
    readonly property int requestedCapsuleWidth: (swipePreviewWidth > 0 && activeForScreen)
        ? Math.round(swipePreviewWidth)
        : widthForState(effectiveGeometryState)
    readonly property int capsuleTargetWidth: clampInt(requestedCapsuleWidth, 1, maxCapsuleWidth)
    // Geometry duration uses V2 morph tokens (T19); swipe settle keeps own token.
    readonly property string geometryMorphKind: {
        if (root.effectiveGeometryState.indexOf("expanded_") === 0
                || root.geometryState.indexOf("expanded_") === 0)
            return "expanded";
        if (root.effectiveGeometryState.indexOf("transient_") === 0)
            return "transient";
        return "collapse";
    }
    // R08 geometry driver pipeline. Springs drive the island driver values
    // only; islandSurface binds clamp(driver, min, max) and the TahoeGlass
    // region submits quantized clamped values — the region can never leave
    // the layer surface even at full spring overshoot (guardrail 0704ea4
    // satisfied by construction). useSpring=false and reduced motion fall
    // back to eased NumberAnimation on the same drivers.
    property bool geometryDriversReady: false
    property real islandDriverWidth: 1
    property real islandDriverHeight: 1
    property real islandDriverRadius: 1
    // Hard clamp bounds: width within screen margins; height must also fit the
    // layer surface below the top inset so overshoot can never push the glass
    // region past the window bounds.
    readonly property int driverHeightMax: Math.max(2, Math.min(
        root.maxCapsuleHeight,
        (root.height > 0 ? root.height : root.implicitHeight) - root.capsuleTargetTop))
    readonly property real islandAnimatedWidth: Math.max(2, Math.min(root.islandDriverWidth, root.maxCapsuleWidth))
    readonly property real islandAnimatedHeight: Math.max(2, Math.min(root.islandDriverHeight, root.driverHeightMax))
    // Radius validity is enforced per-frame against the clamped animated size
    // (spring undershoot on height must never yield radius > height/2).
    readonly property real islandAnimatedRadius: Math.max(0, Math.min(
        root.islandDriverRadius,
        root.islandAnimatedWidth / 2,
        root.islandAnimatedHeight / 2))

    function geometryEaseDurationMs() {
        // OSD entry: fast eased expansion (R08 #23). While OSD stays active,
        // targets do not change between ticks, so nothing re-animates.
        if (root.osdImmediateGeometry)
            return IslandMotion.v2OsdEnterMs;
        return IslandMotion.geometryDurationMs(root.settingsService, root.geometryMorphKind);
    }

    function retargetWidthDriver() {
        if (!root.geometryDriversReady) {
            root.islandDriverWidth = root.capsuleTargetWidth;
            return;
        }
        driverWidthSpring.stop();
        driverWidthEase.stop();
        // Swipe drag: width follows the pointer 1:1 (no animation lag).
        if (root.swipeInteractive) {
            root.islandDriverWidth = root.capsuleTargetWidth;
            return;
        }
        if (root.swipeSettling) {
            driverWidthEase.duration = IslandMotion.swipeSettleDuration;
            driverWidthEase.easing.type = IslandMotion.swipeSettleEasing;
            driverWidthEase.to = root.capsuleTargetWidth;
            driverWidthEase.restart();
            return;
        }
        if (!root.osdImmediateGeometry
                && IslandMotion.geometrySpringEnabled(root.settingsService, root.useSpring)) {
            driverWidthSpring.to = root.capsuleTargetWidth;
            driverWidthSpring.restart();
            return;
        }
        driverWidthEase.duration = root.geometryEaseDurationMs();
        driverWidthEase.easing.type = IslandMotion.v2GeometryEasing;
        driverWidthEase.to = root.capsuleTargetWidth;
        driverWidthEase.restart();
    }

    function retargetHeightDriver() {
        if (!root.geometryDriversReady) {
            root.islandDriverHeight = root.capsuleTargetHeight;
            return;
        }
        driverHeightSpring.stop();
        driverHeightEase.stop();
        if (!root.osdImmediateGeometry
                && IslandMotion.geometrySpringEnabled(root.settingsService, root.useSpring)) {
            driverHeightSpring.to = root.capsuleTargetHeight;
            driverHeightSpring.restart();
            return;
        }
        driverHeightEase.duration = root.geometryEaseDurationMs();
        driverHeightEase.to = root.capsuleTargetHeight;
        driverHeightEase.restart();
    }

    function retargetRadiusDriver() {
        // Radius stays eased (compact pills read radius = height/2 through the
        // per-frame clamp; a springing radius would make corners breathe).
        if (!root.geometryDriversReady) {
            root.islandDriverRadius = root.capsuleTargetRadius;
            return;
        }
        driverRadiusEase.stop();
        driverRadiusEase.duration = root.geometryEaseDurationMs();
        driverRadiusEase.to = root.capsuleTargetRadius;
        driverRadiusEase.restart();
    }

    function syncGeometryDriversImmediately() {
        driverWidthSpring.stop();
        driverWidthEase.stop();
        driverHeightSpring.stop();
        driverHeightEase.stop();
        driverRadiusEase.stop();
        root.islandDriverWidth = root.capsuleTargetWidth;
        root.islandDriverHeight = root.capsuleTargetHeight;
        root.islandDriverRadius = root.capsuleTargetRadius;
    }

    onCapsuleTargetWidthChanged: retargetWidthDriver()
    onCapsuleTargetHeightChanged: retargetHeightDriver()
    onCapsuleTargetRadiusChanged: retargetRadiusDriver()

    Component.onCompleted: {
        root.syncGeometryDriversImmediately();
        root.geometryDriversReady = true;
    }

    SpringAnimation {
        id: driverWidthSpring
        target: root
        property: "islandDriverWidth"
        spring: IslandMotion.v2GeometrySpring.spring
        damping: IslandMotion.v2GeometrySpring.damping
        epsilon: IslandMotion.v2GeometrySpringEpsilon
    }

    NumberAnimation {
        id: driverWidthEase
        target: root
        property: "islandDriverWidth"
        easing.type: IslandMotion.v2GeometryEasing
    }

    SpringAnimation {
        id: driverHeightSpring
        target: root
        property: "islandDriverHeight"
        spring: IslandMotion.v2GeometrySpring.spring
        damping: IslandMotion.v2GeometrySpring.damping
        epsilon: IslandMotion.v2GeometrySpringEpsilon
    }

    NumberAnimation {
        id: driverHeightEase
        target: root
        property: "islandDriverHeight"
        easing.type: IslandMotion.v2GeometryEasing
    }

    NumberAnimation {
        id: driverRadiusEase
        target: root
        property: "islandDriverRadius"
        easing.type: IslandMotion.v2GeometryEasing
    }

    readonly property int capsuleTargetHeight: clampInt(heightForState(effectiveGeometryState), 1, driverHeightMax)
    readonly property int capsuleTargetLeft: clampInt(Math.round((screenWidth - capsuleTargetWidth) / 2), 0, Math.max(0, screenWidth - capsuleTargetWidth))
    // Align compact top inset with TopBar floating inner surface (topMargin 4).
    readonly property int capsuleTargetTop: IslandMotion.v2CompactTopInset
    readonly property real capsuleTargetRadius: Math.min(
        radiusForState(effectiveGeometryState, capsuleTargetHeight),
        capsuleTargetWidth / 2,
        capsuleTargetHeight / 2)
    // Settled: snap the protocol region to the exact target. Threshold sits
    // above the spring epsilon (0.25) so the latch is stable once the driver
    // animation stops; the snap lands within 0.6px of the painted edge —
    // sub-pixel against the ~80%-opaque dark fill — while floor quantization
    // keeps the morph-time region inside the painted rect.
    readonly property bool protocolGeometrySettled: Math.abs(islandSurface.width - capsuleTargetWidth) < 0.6
        && Math.abs(islandSurface.height - capsuleTargetHeight) < 0.6
        && Math.abs(islandSurface.radius - capsuleTargetRadius) < 0.6
    // Morphing region submission (R08 #22): width/height floor-quantize so the
    // glass region never overhangs the painted capsule (an overhang renders raw
    // glass — a bright bar under the capsule bottom edge); radius ceil-quantizes
    // so glass corners recede inside the painted corner, and is re-clamped to
    // the submitted size so it stays a valid rounded rect.
    readonly property int protocolCapsuleWidth: protocolGeometrySettled
        ? Math.round(capsuleTargetWidth)
        : quantizeProtocolFloor(islandSurface.width, IslandMotion.v2ProtocolSizeQuantumPx)
    readonly property int protocolCapsuleHeight: protocolGeometrySettled
        ? Math.round(capsuleTargetHeight)
        : quantizeProtocolFloor(islandSurface.height, IslandMotion.v2ProtocolSizeQuantumPx)
    readonly property int protocolCapsuleRadius: protocolGeometrySettled
        ? Math.round(capsuleTargetRadius)
        : Math.min(
            quantizeProtocolCeil(islandSurface.radius, IslandMotion.v2ProtocolRadiusQuantumPx),
            Math.floor(protocolCapsuleWidth / 2),
            Math.floor(protocolCapsuleHeight / 2))
    readonly property bool compactResting: effectiveContentState === "resting_time" || effectiveContentState === "resting_media" || effectiveContentState === "resting_timer"
    readonly property bool compactContentVisible: compactResting && capsuleShown
    // Expanded media only on the owner screen.
    readonly property bool mediaContentVisible: effectiveContentState === "expanded_media" && activeForScreen
    // T11: SettingsTheme island tokens (single color owner). No DynamicIslandTheme.js.
    readonly property string surfaceFillRole: fillRoleForState(effectiveGeometryState)
    readonly property color glassFill: Theme.islandSurfaceFill(root.darkMode, root.surfaceFillRole)
    readonly property color glassStroke: Theme.islandSurfaceStroke(root.darkMode, root.surfaceFillRole)
    readonly property color textPrimary: Theme.islandTextPrimary(root.darkMode)
    readonly property color textSecondary: Theme.islandTextSecondary(root.darkMode)
    readonly property string mediaArtUrl: (activeForScreen && dynamicIslandService)
        ? String(dynamicIslandService.mediaArtUrl || "")
        : ""
    // T16: title comes from Controls via service — never contentDisplayText /
    // fallbackTimeText, so media→clock exit cannot flash the clock string.
    readonly property string mediaTrackTitle: (activeForScreen && dynamicIslandService)
        ? String(dynamicIslandService.mediaTrackTitle || "")
        : ""
    readonly property string mediaTrackArtist: contentSecondaryText
    readonly property bool mediaPlaying: activeForScreen && dynamicIslandService
        ? !!dynamicIslandService.mediaPlaying
        : false
    readonly property real mediaPosition: dynamicIslandService ? Number(dynamicIslandService.mediaPosition) : 0
    readonly property real mediaLength: dynamicIslandService ? Number(dynamicIslandService.mediaLength) : 0
    readonly property real mediaProgress: dynamicIslandService ? Number(dynamicIslandService.mediaProgress) : 0
    readonly property bool mediaPositionSupported: dynamicIslandService ? !!dynamicIslandService.mediaPositionSupported : false
    readonly property bool mediaLengthSupported: dynamicIslandService ? !!dynamicIslandService.mediaLengthSupported : false
    readonly property bool canPlayPause: dynamicIslandService ? !!dynamicIslandService.canPlayPause : false
    readonly property bool canPrev: dynamicIslandService ? !!dynamicIslandService.canPrev : false
    readonly property bool canNext: dynamicIslandService ? !!dynamicIslandService.canNext : false
    readonly property int workspaceDirection: (activeForScreen && dynamicIslandService)
        ? Number(dynamicIslandService.transientWorkspaceDirection) || 0
        : 0
    readonly property string workspaceLabel: contentDisplayText
    readonly property string timerRemainingLabel: (activeForScreen && dynamicIslandService)
        ? String(dynamicIslandService.timerRemainingLabel || "")
        : ""
    readonly property real timerProgress: (activeForScreen && dynamicIslandService)
        ? Number(dynamicIslandService.timerProgress) || 0
        : 0
    readonly property bool timerRunning: activeForScreen && dynamicIslandService
        ? !!dynamicIslandService.timerRunning
        : false
    readonly property bool timerPaused: activeForScreen && dynamicIslandService
        ? !!dynamicIslandService.timerPaused
        : false
    readonly property bool timerFinished: activeForScreen && dynamicIslandService
        ? !!dynamicIslandService.timerFinished
        : false
    readonly property string bluetoothKind: (activeForScreen && dynamicIslandService)
        ? String(dynamicIslandService.transientBluetoothKind || "") : ""
    readonly property string bluetoothDeviceName: (activeForScreen && dynamicIslandService)
        ? String(dynamicIslandService.transientBluetoothDeviceName || "") : ""
    readonly property string bluetoothDeviceIcon: (activeForScreen && dynamicIslandService)
        ? String(dynamicIslandService.transientBluetoothDeviceIcon || "") : ""
    readonly property int workspaceCount: dynamicIslandService
        ? Number(dynamicIslandService.workspaceCount) || 0
        : 0

    function widthForState(stateName) {
        // Mid-band V2 geometry (IslandMotion v2* tokens). Service swipe widths
        // must stay in lockstep with these values.
        switch (stateName) {
        case "expanded_media":
            return Math.round((IslandMotion.v2MediaExpandedWidthMin + IslandMotion.v2MediaExpandedWidthMax) / 2);
        case "transient_notification":
            return notificationCompactTargetWidth();
        case "transient_bluetooth":
            return Math.round((IslandMotion.v2NotificationCompactWidthMin
                               + IslandMotion.v2NotificationCompactWidthMax) / 2);
        case "transient_osd":
            return Math.round((IslandMotion.v2OsdWidthMin + IslandMotion.v2OsdWidthMax) / 2);
        case "transient_workspace":
            return Math.round((IslandMotion.v2WorkspaceWidthMin + IslandMotion.v2WorkspaceWidthMax) / 2);
        case "resting_media":
            // Content-driven compact media width (T16).
            // Band: IslandMotion.v2CompactMediaWidthMin .. v2CompactMediaWidthMax.
            return compactMediaTargetWidth();
        case "resting_timer":
        case "transient_timer_complete":
            return Math.round((IslandMotion.v2WorkspaceWidthMin + IslandMotion.v2WorkspaceWidthMax) / 2);
        case "expanded_timer":
            return Math.round((IslandMotion.v2TimerExpandedWidthMin + IslandMotion.v2TimerExpandedWidthMax) / 2);
        case "resting_time":
        default:
            // Content-driven clock width (T12). Fall back to mid-band before measure.
            return restingClockTargetWidth();
        }
    }

    function quantizeProtocolFloor(value, quantum) {
        var step = Math.max(1, Math.round(Number(quantum) || 1));
        return Math.max(0, Math.floor(Number(value) / step) * step);
    }

    function quantizeProtocolCeil(value, quantum) {
        var step = Math.max(1, Math.round(Number(quantum) || 1));
        return Math.max(0, Math.ceil(Number(value) / step) * step);
    }

    function restingClockTargetWidth() {
        var measured = 0;
        if (islandContent && islandContent.restingClockContentWidth > 0)
            measured = Math.round(islandContent.restingClockContentWidth) + root.restingClockHorizontalPad;
        if (measured <= 0)
            measured = Math.round((IslandMotion.v2ClockWidthMin + IslandMotion.v2ClockWidthMax) / 2);
        return clampInt(measured, IslandMotion.v2ClockWidthMin, IslandMotion.v2ClockWidthMax);
    }

    function compactMediaTargetWidth() {
        var measured = 0;
        if (islandContent && islandContent.compactMediaContentWidth > 0)
            measured = Math.round(islandContent.compactMediaContentWidth) + root.compactMediaHorizontalPad;
        if (measured <= 0)
            measured = Math.round((IslandMotion.v2CompactMediaWidthMin + IslandMotion.v2CompactMediaWidthMax) / 2);
        return clampInt(measured, IslandMotion.v2CompactMediaWidthMin, IslandMotion.v2CompactMediaWidthMax);
    }

    function notificationCompactTargetWidth() {
        // Expanded: up to 440. Compact short ≈ 300, long/overflow up to 420.
        if (dynamicIslandService && (!!screenRole && screenRole.showActivity)
                && !!dynamicIslandService.transientNotificationExpanded)
            return IslandMotion.v2NotificationExpandedWidthMax;
        var overflow = false;
        if (dynamicIslandService && (!!screenRole && screenRole.showActivity))
            overflow = !!dynamicIslandService.transientNotificationHasOverflow;
        if (overflow)
            return IslandMotion.v2NotificationCompactWidthMax;
        return IslandMotion.v2NotificationCompactWidthMin;
    }

    function notificationCompactTargetHeight() {
        if (dynamicIslandService && (!!screenRole && screenRole.showActivity)
                && !!dynamicIslandService.transientNotificationExpanded) {
            // Content-driven expanded height within 96–176.
            var base = IslandMotion.v2NotificationExpandedHeightMin;
            var actions = dynamicIslandService.transientNotificationActions || [];
            var actionRows = actions.length > 0 ? 1 : 0;
            var h = base + 40 + (actionRows * 40);
            return clampInt(h, IslandMotion.v2NotificationExpandedHeightMin,
                IslandMotion.v2NotificationExpandedHeightMax);
        }
        var overflow = false;
        if (dynamicIslandService && (!!screenRole && screenRole.showActivity))
            overflow = !!dynamicIslandService.transientNotificationHasOverflow;
        if (overflow)
            return IslandMotion.v2NotificationCompactHeightMax;
        return IslandMotion.v2NotificationCompactHeightMin;
    }

    function heightForState(stateName) {
        switch (stateName) {
        case "expanded_media":
            return Math.round((IslandMotion.v2MediaExpandedHeightMin + IslandMotion.v2MediaExpandedHeightMax) / 2);
        case "transient_notification":
            return notificationCompactTargetHeight();
        case "transient_bluetooth":
            return IslandMotion.v2NotificationCompactHeightMin;
        case "transient_osd":
            return IslandMotion.v2OsdHeight;
        case "transient_workspace":
            return IslandMotion.v2WorkspaceHeight;
        case "resting_media":
            return IslandMotion.v2CompactMediaHeight;
        case "resting_timer":
        case "transient_timer_complete":
            return IslandMotion.v2WorkspaceHeight;
        case "expanded_timer":
            return Math.round((IslandMotion.v2TimerExpandedHeightMin + IslandMotion.v2TimerExpandedHeightMax) / 2);
        case "resting_time":
        default:
            return IslandMotion.v2ClockHeight;
        }
    }

    function clampInt(value, minValue, maxValue) {
        var number = Number(value);
        if (!isFinite(number))
            number = minValue;

        return Math.round(Math.max(minValue, Math.min(maxValue, number)));
    }

    function fillRoleForState(stateName) {
        if (stateName === "expanded_media" || stateName === "expanded_timer")
            return "expanded";
        if (stateName === "transient_osd"
                || stateName === "transient_workspace"
                || stateName === "transient_notification"
                || stateName === "transient_bluetooth"
                || stateName === "transient_timer_complete")
            return "transient";
        return "compact";
    }

    function radiusForState(stateName, itemHeight) {
        // V2: compact tracks half-height of its design height; expanded is
        // hard-capped (never height/2 ellipse on tall panels).
        var h = Number(itemHeight);
        if (!isFinite(h) || h <= 0)
            h = IslandMotion.v2ClockHeight;

        switch (stateName) {
        case "expanded_media":
        case "expanded_timer":
            return Math.min(
                IslandMotion.v2RadiusExpandedMax,
                Math.max(IslandMotion.v2RadiusExpandedMin, 30));
        case "transient_notification":
            return Math.min(
                IslandMotion.v2RadiusNotificationMax,
                Math.max(IslandMotion.v2RadiusNotificationMin, 24));
        case "transient_bluetooth":
            return Math.min(
                IslandMotion.v2RadiusNotificationMax,
                Math.max(IslandMotion.v2RadiusNotificationMin, 24));
        case "transient_osd":
            return IslandMotion.v2RadiusOsd;
        case "resting_media":
        case "transient_workspace":
            return IslandMotion.v2RadiusCompactMedia;
        case "resting_time":
        default:
            return IslandMotion.v2RadiusCompactClock;
        }
    }

    function isRestingState(stateName) {
        return stateName === "resting_time" || stateName === "resting_media" || stateName === "resting_timer";
    }

    visible: !root.fullscreenActive
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    focusable: false
    implicitWidth: screenWidth
    implicitHeight: 220
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "tahoe-dynamic-island"

    anchors {
        left: true
        right: true
        top: true
    }

    mask: Region {
        Region {
            x: root.capsuleTargetLeft
            y: root.capsuleTargetTop
            width: root.capsuleShown ? root.capsuleTargetWidth : 0
            height: root.capsuleShown ? root.capsuleTargetHeight : 0
            radius: Math.round(root.capsuleTargetRadius)
        }
    }

    TahoeGlass.regions: [islandSurface.region]

    GlassPanel {
        id: islandSurface

        // R08: geometry reads the clamped driver values (spring lives on the
        // drivers only). x derives from the live width so the capsule stays
        // perfectly centered through spring overshoot and swipe alike; y is
        // the fixed top inset.
        x: (root.screenWidth - width) / 2
        y: root.capsuleTargetTop
        width: root.islandAnimatedWidth
        height: root.islandAnimatedHeight
        material: GlassStyle.MaterialPill
        // V2 surface radius is authoritative. Keep GlassStyle.RadiusPill in the
        // expression so glass guardrails still see a governed radius token; the
        // arithmetic equals the clamped animated radius (no pill half-height
        // override).
        radius: GlassStyle.RadiusPill + (root.islandAnimatedRadius - GlassStyle.RadiusPill)
        clip: true
        fillColor: root.glassFill
        strokeColor: root.glassStroke
        strokeWidth: 1
        interaction: islandSurface.opacity
        materialAlpha: islandSurface.opacity
        regionEnabled: root.capsuleShown || islandSurface.opacity > 0.01
        useItemRegion: false
        regionX: Math.round((root.screenWidth - root.protocolCapsuleWidth) / 2)
        regionY: root.capsuleTargetTop
        regionWidth: root.protocolCapsuleWidth
        regionHeight: root.protocolCapsuleHeight
        regionRadius: root.protocolCapsuleRadius
        opacity: root.capsuleShown ? 1 : 0

        // Geometry → TahoeGlassRegion: submission is clamped + floor-quantized;
        // no Behavior animates the surface geometry channels (all motion lives
        // in the root driver pipeline), so the region is bounded by design.

        Behavior on fillColor {
            ColorAnimation { duration: IslandMotion.overlayColorDuration; easing.type: IslandMotion.overlayColorEasing }
        }

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.v2ContentEnterMs; easing.type: IslandMotion.v2ContentEasing }
        }

        // Content layer: V2 does not whole-scene scale 0.9→1 on state switch
        // (roadmap §11.2). That scale + height morph made clock/date text look
        // like it was sinking on click collapse. Scene crossfades live inside
        // DynamicIslandContent; per-scene enabled gates (opacity > 0.5) keep
        // outgoing scenes from stealing hits — no host-level input dead zone.
        // Stack above the capsule MouseArea so media controls receive hits;
        // blank capsule regions still fall through to the fill MouseArea below.
        Item {
            id: contentHost
            anchors.fill: parent
            z: 1
            // Keep scale fixed at 1. useSpring remains on Overlay for API/tests
            // but must not drive glass-adjacent content scale enter.
            scale: 1.0
            transformOrigin: Item.Center

            DynamicIslandContent {
                id: islandContent
                anchors.fill: parent
                islandState: root.effectiveContentState
                displayText: root.contentDisplayText
                secondaryText: root.contentSecondaryText
                iconCode: root.contentIconCode
                clockWeekdayText: root.contentClockWeekday
                clockTimeText: root.contentClockTime
                progress: root.progress
                osdMuted: root.contentOsdMuted
                osdExiting: root.contentOsdExiting
                notificationAppName: root.contentNotificationAppName
                notificationIconUrl: root.contentNotificationIconUrl
                notificationUrgency: root.contentNotificationUrgency
                notificationHasOverflow: root.contentNotificationHasOverflow
                notificationExpanded: root.contentNotificationExpanded
                notificationActions: root.contentNotificationActions
                compactResting: root.compactResting
                compactContentVisible: root.compactContentVisible
                mediaExpandedContentVisible: root.mediaContentVisible
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                darkMode: root.darkMode
                mediaArtUrl: root.mediaArtUrl
                mediaTrackTitle: root.mediaTrackTitle
                mediaTrackArtist: root.mediaTrackArtist
                mediaPlaying: root.mediaPlaying
                mediaPosition: root.mediaPosition
                mediaLength: root.mediaLength
                mediaProgress: root.mediaProgress
                mediaPositionSupported: root.mediaPositionSupported
                mediaLengthSupported: root.mediaLengthSupported
                canPlayPause: root.canPlayPause
                canPrev: root.canPrev
                canNext: root.canNext
                settingsService: root.settingsService
                accentColor: root.accentColor
                progressTrackColor: root.progressTrackColor
                workspaceDirection: root.workspaceDirection
                workspaceLabel: root.workspaceLabel
                workspaceCount: root.workspaceCount
                timerRemainingLabel: root.timerRemainingLabel
                timerProgress: root.timerProgress
                timerRunning: root.timerRunning
                timerPaused: root.timerPaused
                timerFinished: root.timerFinished
                bluetoothKind: root.bluetoothKind
                bluetoothDeviceName: root.bluetoothDeviceName
                bluetoothDeviceIcon: root.bluetoothDeviceIcon
                useSpring: root.useSpring
                onMediaPreviousRequested: if (root.dynamicIslandService) root.dynamicIslandService.mediaPrevious()
                onMediaPlayPauseRequested: if (root.dynamicIslandService) root.dynamicIslandService.mediaTogglePlayPause()
                onMediaNextRequested: if (root.dynamicIslandService) root.dynamicIslandService.mediaNext()
                onMediaControlPressed: if (root.dynamicIslandService) root.dynamicIslandService.setUserInteracting(true)
                onMediaControlReleased: if (root.dynamicIslandService) root.dynamicIslandService.setUserInteracting(false)
                onTimerPauseResumeRequested: {
                    if (!root.dynamicIslandService) return;
                    if (root.dynamicIslandService.timerPaused || !root.dynamicIslandService.timerRunning)
                        root.dynamicIslandService.timerResume();
                    else
                        root.dynamicIslandService.timerPause();
                }
                onTimerCancelRequested: {
                    if (root.dynamicIslandService)
                        root.dynamicIslandService.timerCancel();
                }
                onTimerControlPressed: if (root.dynamicIslandService) root.dynamicIslandService.setUserInteracting(true)
                onTimerControlReleased: if (root.dynamicIslandService) root.dynamicIslandService.setUserInteracting(false)
                onNotificationBodyClicked: {
                    if (root.dynamicIslandService)
                        root.dynamicIslandService.invokeNotificationDefaultAction();
                }
                onNotificationDismissRequested: {
                    if (root.dynamicIslandService)
                        root.dynamicIslandService.dismissDisplayedNotification();
                }
                onNotificationExpandToggleRequested: {
                    if (root.dynamicIslandService)
                        root.dynamicIslandService.toggleNotificationExpanded();
                }
                onNotificationActionInvoked: function(actionId) {
                    if (root.dynamicIslandService)
                        root.dynamicIslandService.invokeNotificationAction(actionId);
                }
                onNotificationInteractionBegan: {
                    if (root.dynamicIslandService)
                        root.dynamicIslandService.setUserInteracting(true);
                }
                onNotificationInteractionEnded: {
                    if (root.dynamicIslandService)
                        root.dynamicIslandService.setUserInteracting(false);
                }
            }
        }

        MouseArea {
           anchors.fill: parent
           enabled: root.capsuleShown
           hoverEnabled: true
           acceptedButtons: Qt.LeftButton | Qt.RightButton
           cursorShape: Qt.PointingHandCursor
           property real swipeStartX: 0
           property real swipeLastX: 0
           property real swipeStartY: 0
           // Gesture phases for click vs horizontal swipe intent:
           // armed → dragging (beginSwipe) | rejected (vertical) | idle.
           property bool armingSwipe: false
           property bool gestureRejected: false
           // Session-scoped click suppression: only the composed click from the
           // current press→release can be suppressed. A new press ends the prior
           // suppression lifecycle so a follow-up click within 180ms is not eaten.
           property int pointerSession: 0
           property int suppressClickSession: -1

           function resetGesturePhase() {
               armingSwipe = false;
               gestureRejected = false;
           }

           function suppressClickTemporarily() {
               suppressClickSession = pointerSession;
               swipeClickSuppress.restart();
           }

           function clickSuppressedForCurrentSession() {
               return suppressClickSession === pointerSession;
           }
       
           Timer {
               id: swipeClickSuppress
               interval: IslandMotion.swipeSuppressClickMs
               repeat: false
               onTriggered: {
                   // Only clear if this timer still belongs to the suppress session.
                   if (parent.suppressClickSession === parent.pointerSession)
                       parent.suppressClickSession = -1;
               }
           }

            Timer {
                id: hoverExpandDelay
                interval: IslandMotion.hoverExpandDelayMs
                repeat: false
                onTriggered: {
                    if (root.dynamicIslandService)
                        root.dynamicIslandService.requestHoverExpand(root.ownScreenName);
                }
            }

            Timer {
                id: hoverCollapseDelay
                interval: IslandMotion.hoverCollapseDelayMs
                repeat: false
                onTriggered: {
                    if (root.dynamicIslandService)
                        root.dynamicIslandService.requestHoverCollapse();
                }
            }

            onEntered: {
                if (!root.hoverExpandEnabled || !root.dynamicIslandService)
                    return;
                hoverCollapseDelay.stop();
                hoverExpandDelay.restart();
            }

            onExited: {
                hoverExpandDelay.stop();
                if (root.hoverExpandEnabled && root.dynamicIslandService)
                    hoverCollapseDelay.restart();
            }
       
           onPressed: function(mouse) {
               hoverExpandDelay.stop();
               hoverCollapseDelay.stop();
               // New pointer session: prior swipe/reject suppress must not carry over.
               pointerSession += 1;
               suppressClickSession = -1;
               swipeClickSuppress.stop();
               // Pointer owns the gesture: abort any in-flight wheel swipe session.
               if (root.dynamicIslandService && root.dynamicIslandService.swipeDragging)
                   root.dynamicIslandService.cancelSwipe();
               wheelSwipeSettle.stop();
               if (root.dynamicIslandService)
                   root.dynamicIslandService.setUserInteracting(true);
               swipeStartX = mouse.x;
               swipeStartY = mouse.y;
               swipeLastX = mouse.x;
               gestureRejected = false;
               armingSwipe = (mouse.button === Qt.LeftButton)
                   && root.dynamicIslandService
                   && root.dynamicIslandService.canSwipe();
           }
           onPositionChanged: function(mouse) {
               if (!pressed || !root.dynamicIslandService)
                   return;

               // Already dragging: stream incremental deltas only.
               if (root.dynamicIslandService.swipeDragging) {
                   var dragDeltaX = mouse.x - swipeLastX;
                   var dragDeltaY = Math.abs(mouse.y - swipeStartY);
                   swipeLastX = mouse.x;
                   root.dynamicIslandService.advanceSwipe(dragDeltaX, dragDeltaY);
                   return;
               }

               if (!armingSwipe || gestureRejected)
                   return;

               var totalDx = mouse.x - swipeStartX;
               var totalDy = mouse.y - swipeStartY;
               var absX = Math.abs(totalDx);
               var absY = Math.abs(totalDy);

               // Dominant vertical motion: cancel click, never beginSwipe.
               if (absY >= IslandMotion.swipeVerticalRejectPx && absY > absX) {
                   gestureRejected = true;
                   armingSwipe = false;
                   suppressClickTemporarily();
                   return;
               }

               // Both axes below arm threshold: still a potential click (jitter OK).
               if (absX < IslandMotion.swipeArmThresholdPx
                       && absY < IslandMotion.swipeArmThresholdPx)
                   return;

               // Past arm without clear horizontal dominance: reject click
               // (covers diagonal dead-band that used to mis-fire chip click).
               if (!(absX > absY && absX >= IslandMotion.swipeArmThresholdPx)) {
                   gestureRejected = true;
                   armingSwipe = false;
                   suppressClickTemporarily();
                   return;
               }

               if (!root.dynamicIslandService.beginSwipe()) {
                   armingSwipe = false;
                   return;
               }

               // Seed with total displacement so the first frame is not lost.
               swipeLastX = mouse.x;
               root.dynamicIslandService.advanceSwipe(totalDx, absY);
           }
           onReleased: function(mouse) {
               if (root.dynamicIslandService) {
                   if (root.dynamicIslandService.swipeDragging) {
                       // Any committed swipe session owns the press; never click.
                       root.dynamicIslandService.consumeSwipeMoved();
                       root.dynamicIslandService.resolveSwipe(root.ownScreenName);
                       suppressClickTemporarily();
                   } else if (root.effectiveContentState === "transient_notification"
                              && !gestureRejected
                              && Math.abs(mouse.x - swipeStartX) >= IslandMotion.swipeArmThresholdPx * 2
                              && Math.abs(mouse.x - swipeStartX) > Math.abs(mouse.y - swipeStartY)) {
                       // T14: horizontal swipe dismisses the leased notification by stable id.
                       root.dynamicIslandService.dismissDisplayedNotification();
                       suppressClickTemporarily();
                   } else if (gestureRejected) {
                       suppressClickTemporarily();
                   }
                   root.dynamicIslandService.setUserInteracting(false);
               }
               resetGesturePhase();
           }
           onCanceled: {
               if (root.dynamicIslandService && root.dynamicIslandService.swipeDragging)
                   root.dynamicIslandService.cancelSwipe();
               if (root.dynamicIslandService)
                   root.dynamicIslandService.setUserInteracting(false);
               resetGesturePhase();
           }
           onClicked: function(mouse) {
               // Session-scoped: only the composed click of this press is blocked
               // after swipe/reject; the next press starts a new session.
               if (clickSuppressedForCurrentSession())
                   return;
               if (root.dynamicIslandService)
                   root.dynamicIslandService.handleChipClick(mouse.button, root.ownScreenName);
           }
           onWheel: function(wheel) {
               // Ignore wheel while a pointer gesture is active (mutual exclusion).
               if (pressed || armingSwipe || gestureRejected)
                   return;
               if (!root.dynamicIslandService || !root.dynamicIslandService.canSwipe())
                   return;
       
               var deltaX = wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : wheel.angleDelta.x / 4;
               var deltaY = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 4;
               var effective = Math.abs(deltaX) > Math.abs(deltaY) ? deltaX : deltaY;
               if (effective === 0)
                   return;
       
               if (!root.dynamicIslandService.swipeDragging)
                   root.dynamicIslandService.beginSwipe();
               root.dynamicIslandService.advanceSwipe(effective * 0.8, 0);
               wheelSwipeSettle.restart();
           }
       
            Timer {
                id: wheelSwipeSettle
                interval: IslandMotion.swipeSettleIdleMs
               repeat: false
               onTriggered: {
                   if (root.dynamicIslandService && root.dynamicIslandService.swipeDragging)
                       root.dynamicIslandService.resolveSwipe(root.ownScreenName);
               }
           }
       }
    }
}
