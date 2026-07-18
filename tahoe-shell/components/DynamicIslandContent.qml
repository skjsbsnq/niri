pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion

// Scene host for the Dynamic Island capsule.
// R07 crossfade architecture: every scene owns its own enter/exit fade
// (exit v2ContentExitMs while the incoming scene enters over v2ContentEnterMs
// with <=6px directional travel). Outgoing scenes keep rendering while they
// fade — there is no staged full-hide swap and no blank-capsule frame.
// Heavy scenes (notification, expanded media) use Loaders with a hold/release
// window (expandedUnloadHoldMs) so their exit fade completes before unload.
Item {
    id: root
    clip: true

    property string islandState: "resting_time"
    property string displayText: ""
    property string secondaryText: ""
    property string iconCode: ""
    // T12: split resting clock labels (weekday secondary + time primary).
    property string clockWeekdayText: ""
    property string clockTimeText: ""
    property real progress: -1
    // T13: explicit muted flag from service (avoid locale string probes).
    property bool osdMuted: false
    // Keep the OSD snapshot mounted while its retained exit animation runs.
    property bool osdExiting: false
    // T14: compact notification presentation (from service lease fields).
    property string notificationAppName: ""
    property string notificationIconUrl: ""
    property string notificationUrgency: "normal"
    property bool notificationHasOverflow: false
    property bool notificationExpanded: false
    property var notificationActions: []
    // Fresh-lease counter from the service (via Overlay); the notification
    // view resets swipe state when it changes.
    property int notificationEpoch: 0
    property bool compactResting: true
    signal notificationBodyClicked()
    signal notificationDismissRequested()
    signal notificationExpandToggleRequested()
    signal notificationActionInvoked(string actionId)
    signal notificationInteractionBegan()
    signal notificationInteractionEnded()
    property bool compactContentVisible: compactResting
    property bool mediaExpandedContentVisible: mediaExpanded
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property bool darkMode: true
    // Content-level spring gate (notification swipe settle only — glass region
    // geometry never springs).
    property bool useSpring: false
    // Measured resting clock content width (no capsule padding). Overlay adds pad + clamp.
    readonly property int restingClockContentWidth: restingClock.contentWidth
    readonly property bool restingClockActive: islandState === "resting_time"
    property string mediaArtUrl: ""
    property string mediaTrackTitle: ""
    property string mediaTrackArtist: ""
    property bool mediaPlaying: false
    property real mediaPosition: 0
    property real mediaLength: 0
    property real mediaProgress: 0
    property bool mediaPositionSupported: false
    property bool mediaLengthSupported: false
    property bool canPlayPause: false
    property bool canPrev: false
    property bool canNext: false
    property var settingsService
    property color accentColor: "#0a84ff"
    property color progressTrackColor: "#30ffffff"
    signal mediaPreviousRequested()
    signal mediaPlayPauseRequested()
    signal mediaNextRequested()
    signal mediaControlPressed()
    signal mediaControlReleased()
    property int workspaceDirection: 0
    property string workspaceLabel: ""
    property int workspaceCount: 0
    property string timerRemainingLabel: ""
    property real timerProgress: 0
    property bool timerRunning: false
    property bool timerPaused: false
    property bool timerFinished: false
    property string bluetoothKind: ""
    property string bluetoothDeviceName: ""
    property string bluetoothDeviceIcon: ""
    signal timerPauseResumeRequested()
    signal timerCancelRequested()
    signal timerControlPressed()
    signal timerControlReleased()
    readonly property bool mediaExpanded: islandState === "expanded_media"
    readonly property bool compactMediaActive: islandState === "resting_media"
    // Measured compact media content width (no capsule padding). Overlay clamps.
    // While compact media is exiting (still visible mid-fade), freeze measured
    // width on the latch so the capsule does not shrink mid-fade when the
    // player disappears.
    readonly property int compactMediaContentWidth: (root.compactMediaActive || compactMedia.visible)
        ? Math.max(compactMedia.contentWidth, root.latchedCompactMediaWidth)
        : compactMedia.contentWidth
    // Last non-empty title/width while compact media is shown or fading so
    // player disappear does not rewrite the fading scene with fallback text.
    property string latchedCompactMediaTitle: ""
    property int latchedCompactMediaWidth: 0
    readonly property string compactMediaTitle: {
        var live = String(root.mediaTrackTitle || "").trim();
        if (live.length > 0)
            return live;
        // Keep latched title through the exit fade.
        return root.latchedCompactMediaTitle;
    }
    // Compact exits under OSD must be immediate: hardware feedback owns the
    // first frame, so the outgoing clock/media must not cross-fade over it.
    readonly property int compactContentMotionMs: root.osdActive
        ? IslandMotion.v2OsdEnterMs
        : IslandMotion.contentExitMs(root.settingsService)

    readonly property bool notificationActive: islandState === "transient_notification"
    readonly property bool bluetoothActive: islandState === "transient_bluetooth"
    readonly property bool osdActive: islandState === "transient_osd"
    readonly property bool workspaceActive: islandState === "transient_workspace"
    readonly property bool timerActiveScene: islandState === "resting_timer"
        || islandState === "expanded_timer"
        || islandState === "transient_timer_complete"
    readonly property bool timerExpanded: islandState === "expanded_timer"

    // T13: horizontal bar OSD; ring removed. Scene visible whenever OSD active.
    readonly property bool osdSceneVisible: osdActive && !osdExiting
    property real osdLayerOpacity: 0
    property real osdLayerOffset: 0
    // T19: scene enter/exit use V2 content helpers (reduced-aware).
    readonly property int sceneEnterMs: IslandMotion.contentEnterMs(root.settingsService)
    readonly property int sceneExitMs: IslandMotion.contentExitMs(root.settingsService)
    readonly property int notificationFadeInDuration: sceneEnterMs
    readonly property int notificationFadeOutDuration: sceneExitMs
    // Enter travel (<=6px, top-anchored: scenes settle downward into place).
    readonly property int sceneTravelPx: IslandMotion.contentTravelPx(root.settingsService)
    // Hold outgoing heavy loaders through exit fade, then destroy.
    readonly property int expandedUnloadHoldMs: IslandMotion.contentExitMs(root.settingsService) + 40

    // Loader active flags: true while showing or exit-hold. Neither heavy
    // scene stays loaded forever on resting/hidden outputs.
    property bool mediaLoaderActive: false
    property bool notificationLoaderActive: false

    function syncOsdLayerImmediately() {
        osdExitOpacity.stop();
        osdExitTravel.stop();
        root.osdLayerOpacity = root.osdActive && !root.osdExiting ? 1 : 0;
        root.osdLayerOffset = 0;
    }

    onOsdActiveChanged: {
        if (!root.osdExiting)
            root.syncOsdLayerImmediately();
    }

    onOsdExitingChanged: {
        if (root.osdExiting && root.osdActive) {
            osdExitOpacity.restart();
            osdExitTravel.restart();
        } else {
            root.syncOsdLayerImmediately();
        }
    }

    NumberAnimation {
        id: osdExitOpacity
        target: root
        property: "osdLayerOpacity"
        to: 0
        duration: IslandMotion.contentExitMs(root.settingsService)
        easing.type: IslandMotion.v2ContentEasing
    }

    NumberAnimation {
        id: osdExitTravel
        target: root
        property: "osdLayerOffset"
        to: -IslandMotion.contentTravelPx(root.settingsService)
        duration: IslandMotion.contentExitMs(root.settingsService)
        easing.type: IslandMotion.v2ContentEasing
    }

    onMediaExpandedContentVisibleChanged: {
        if (root.mediaExpandedContentVisible) {
            mediaUnloadHold.stop();
            root.mediaLoaderActive = true;
        } else {
            mediaUnloadHold.restart();
        }
    }

    Timer {
        id: mediaUnloadHold
        interval: root.expandedUnloadHoldMs
        repeat: false
        onTriggered: {
            if (!root.mediaExpandedContentVisible)
                root.mediaLoaderActive = false;
        }
    }

    onNotificationActiveChanged: {
        if (root.notificationActive) {
            notificationUnloadHold.stop();
            root.notificationLoaderActive = true;
        } else {
            notificationUnloadHold.restart();
        }
    }

    Timer {
        id: notificationUnloadHold
        interval: root.expandedUnloadHoldMs
        repeat: false
        onTriggered: {
            if (!root.notificationActive)
                root.notificationLoaderActive = false;
        }
    }

    // V2 resting clock (T12). Top-stable; crossfades in place (exit up,
    // enter from above) — no hold timers, visibility follows opacity.
    DynamicIslandRestingClockView {
        id: restingClock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.restingClockActive ? 0 : -root.sceneTravelPx
        width: Math.min(parent.width - 16, Math.max(contentWidth, 1))
        height: IslandMotion.v2ClockHeight
        weekdayText: root.clockWeekdayText
        timeText: root.clockTimeText
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        opacity: root.restingClockActive && root.compactContentVisible ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: root.restingClockActive ? root.sceneEnterMs : root.compactContentMotionMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
        Behavior on anchors.topMargin {
            NumberAnimation {
                duration: root.restingClockActive ? root.sceneEnterMs : root.compactContentMotionMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
    }

    // Latch non-empty compact title/width while media is active so exit fades
    // keep the last track identity (never clock displayText).
    onMediaTrackTitleChanged: {
        var live = String(root.mediaTrackTitle || "").trim();
        if (live.length > 0)
            root.latchedCompactMediaTitle = live;
    }

    onCompactMediaActiveChanged: {
        if (root.compactMediaActive) {
            var live = String(root.mediaTrackTitle || "").trim();
            if (live.length > 0)
                root.latchedCompactMediaTitle = live;
            if (compactMedia.contentWidth > 0)
                root.latchedCompactMediaWidth = compactMedia.contentWidth;
        }
    }

    Connections {
        target: compactMedia
        function onContentWidthChanged() {
            if (root.compactMediaActive
                    && compactMedia.contentWidth > 0
                    && String(root.mediaTrackTitle || "").trim().length > 0)
                root.latchedCompactMediaWidth = compactMedia.contentWidth;
        }
    }

    // T16: V2 compact media (art + title + play/pause). Same compact-layer
    // motion vocabulary as the resting clock so clock↔media morph crossfades
    // in place with no black frame.
    DynamicIslandCompactMediaView {
        id: compactMedia

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.compactMediaActive ? 0 : -root.sceneTravelPx
        width: Math.min(parent.width - 8, Math.max(contentWidth, IslandMotion.v2CompactMediaWidthMin))
        height: IslandMotion.v2CompactMediaHeight
        artUrl: root.mediaArtUrl
        // Never fall back to displayText (clock) — use live or latched title only.
        trackTitle: root.compactMediaTitle
        isPlaying: root.mediaPlaying
        progress: root.mediaProgress
        // Show progress only when Controls reports position support (and length > 0).
        progressSupported: root.mediaPositionSupported && root.mediaLength > 0
        settingsService: root.settingsService
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        accentColor: root.accentColor
        trackColor: root.progressTrackColor
        opacity: root.compactMediaActive && root.compactContentVisible ? 1 : 0
        visible: opacity > 0.01
        // Release the latch once the exit fade has fully completed.
        onVisibleChanged: {
            if (!visible && !root.compactMediaActive) {
                root.latchedCompactMediaTitle = "";
                root.latchedCompactMediaWidth = 0;
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root.compactMediaActive ? root.sceneEnterMs : root.compactContentMotionMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
        Behavior on anchors.topMargin {
            NumberAnimation {
                duration: root.compactMediaActive ? root.sceneEnterMs : root.compactContentMotionMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
    }

    DynamicIslandBluetoothView {
        id: bluetoothView
        anchors.fill: parent
        kind: root.bluetoothKind
        deviceName: root.bluetoothDeviceName
        deviceIcon: root.bluetoothDeviceIcon
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        accentColor: root.accentColor
        opacity: root.bluetoothActive ? 1 : 0
        visible: opacity > 0.01
        transform: Translate {
            y: root.bluetoothActive ? 0 : -root.sceneTravelPx
            Behavior on y {
                NumberAnimation {
                    duration: root.bluetoothActive ? root.sceneEnterMs : root.sceneExitMs
                    easing.type: IslandMotion.v2ContentEasing
                }
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: root.bluetoothActive ? root.sceneEnterMs : root.sceneExitMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
    }

    // Notification is the only compact scene with a Flickable and two Images.
    // Loader holds through the exit fade (hold/release), then unloads so
    // hidden outputs never keep the heavy scene instantiated.
    Loader {
        id: notificationLoader
        objectName: "notificationLoader"
        anchors.fill: parent
        active: root.notificationLoaderActive
        asynchronous: false
        sourceComponent: notificationSceneComponent
    }

    Component {
        id: notificationSceneComponent

        DynamicIslandNotificationView {
            anchors.fill: parent
            appName: root.notificationAppName
            summary: root.displayText
            body: root.secondaryText
            iconUrl: root.notificationIconUrl
            urgency: root.notificationUrgency
            hasOverflow: root.notificationHasOverflow
            expanded: root.notificationExpanded
            actions: root.notificationActions
            notificationEpoch: root.notificationEpoch
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
            settingsService: root.settingsService
            useSpring: root.useSpring
            onBodyClicked: root.notificationBodyClicked()
            onDismissRequested: root.notificationDismissRequested()
            onExpandToggleRequested: root.notificationExpandToggleRequested()
            onActionInvoked: function(actionId) { root.notificationActionInvoked(actionId); }
            // Expanded hold owns userInteracting; do not clear it on flick/action press end.
            onInteractionBegan: {
                if (!root.notificationExpanded)
                    root.notificationInteractionBegan();
            }
            onInteractionEnded: {
                if (!root.notificationExpanded)
                    root.notificationInteractionEnded();
            }

            opacity: root.notificationActive ? 1 : 0
            // Outgoing scene must not steal hits from the incoming one.
            enabled: opacity > 0.5
            transform: Translate {
                y: root.notificationActive ? 0 : -root.sceneTravelPx
                Behavior on y {
                    NumberAnimation {
                        duration: root.notificationActive
                            ? root.notificationFadeInDuration
                            : root.notificationFadeOutDuration
                        easing.type: IslandMotion.v2ContentEasing
                    }
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: root.notificationActive
                        ? root.notificationFadeInDuration
                        : root.notificationFadeOutDuration
                    easing.type: IslandMotion.v2ContentEasing
                }
            }
        }
    }

    // T13: single OSD scene (icon + horizontal bar + value). No Canvas ring.
    // Top-anchored at OSD design height so capsule morph does not drag the bar.
    DynamicIslandOsdView {
        id: osdView

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 0
            rightMargin: 0
            topMargin: root.osdLayerOffset
        }
        height: IslandMotion.v2OsdHeight
        iconCode: root.iconCode
        valueText: root.secondaryText
        // Bind progress directly so continuous OSD ticks update the bar/value.
        progress: root.progress
        muted: root.osdMuted
        darkMode: root.darkMode
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        opacity: root.osdLayerOpacity
        // Stay in the tree while OSD is active so progress rebinds without recreate.
        visible: root.osdActive || root.osdLayerOpacity > 0.01
    }

    // T18: dedicated workspace transient scene (not generic detailRow).
    DynamicIslandWorkspaceView {
        id: workspaceView
        anchors.fill: parent
        workspaceLabel: root.workspaceLabel.length > 0 ? root.workspaceLabel : root.displayText
        workspaceIndex: {
            var m = String(root.workspaceLabel || root.displayText || "").match(/(\d+)/);
            return m ? Number(m[1]) : 0;
        }
        workspaceCount: root.workspaceCount
        direction: root.workspaceDirection
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        accentColor: root.accentColor
        opacity: root.workspaceActive ? 1 : 0
        visible: opacity > 0.01
        // Directional enter: slide from activation side, capped travel.
        x: {
            var travel = IslandMotion.contentTravelPx(root.settingsService);
            if (root.workspaceActive || travel <= 0)
                return 0;
            if (root.workspaceDirection > 0)
                return travel;
            if (root.workspaceDirection < 0)
                return -travel;
            return 0;
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root.workspaceActive ? root.sceneEnterMs : root.sceneExitMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
        Behavior on x {
            NumberAnimation {
                duration: root.workspaceActive ? root.sceneEnterMs : root.sceneExitMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
    }

    DynamicIslandTimerView {
        id: timerView
        anchors.fill: parent
        z: 1
        remainingLabel: root.timerRemainingLabel
        progress: root.timerProgress
        running: root.timerRunning
        paused: root.timerPaused
        finished: root.timerFinished
        expanded: root.timerExpanded
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        accentColor: root.accentColor
        trackColor: root.progressTrackColor
        opacity: root.timerActiveScene ? 1 : 0
        visible: opacity > 0.01
        enabled: opacity > 0.5
        onPauseResumeRequested: root.timerPauseResumeRequested()
        onCancelRequested: root.timerCancelRequested()
        onTimerInteractionPressed: root.timerControlPressed()
        onTimerInteractionReleased: root.timerControlReleased()

        Behavior on opacity {
            NumberAnimation {
                duration: root.timerActiveScene ? root.sceneEnterMs : root.sceneExitMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
    }

    // Expanded media: Loader only while visible or exit-hold (no hidden Timer).
    Loader {
        id: mediaLoader
        objectName: "mediaLoader"
        anchors.fill: parent
        z: 2
        active: root.mediaLoaderActive
        asynchronous: false
        sourceComponent: mediaSceneComponent
    }

    Component {
        id: mediaSceneComponent
        DynamicIslandMediaView {
            anchors.fill: parent
            artUrl: root.mediaArtUrl
            trackTitle: root.mediaTrackTitle
            trackArtist: root.mediaTrackArtist
            isPlaying: root.mediaPlaying
            position: root.mediaPosition
            duration: root.mediaLength
            progress: root.mediaProgress
            positionSupported: root.mediaPositionSupported
            durationSupported: root.mediaLengthSupported
            canPlayPause: root.canPlayPause
            canPrev: root.canPrev
            canNext: root.canNext
            settingsService: root.settingsService
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
            accentColor: root.accentColor
            trackColor: root.progressTrackColor
            // R07: collapse fades out (no hard cut). Loader hold keeps the
            // scene mounted through the exit fade; enabled gate keeps the
            // fading scene from stealing hits mid-collapse.
            opacity: root.mediaExpandedContentVisible ? 1 : 0
            visible: root.mediaExpandedContentVisible || opacity > 0.01
            enabled: opacity > 0.5
            onPreviousRequested: root.mediaPreviousRequested()
            onPlayPauseRequested: root.mediaPlayPauseRequested()
            onNextRequested: root.mediaNextRequested()
            onControlPressed: root.mediaControlPressed()
            onControlReleased: root.mediaControlReleased()

            Behavior on opacity {
                NumberAnimation {
                    duration: root.mediaExpandedContentVisible
                        ? IslandMotion.contentEnterMs(root.settingsService)
                        : IslandMotion.contentExitMs(root.settingsService)
                    easing.type: IslandMotion.v2ContentEasing
                }
            }
        }
    }

    Component.onCompleted: {
        root.syncOsdLayerImmediately();
        if (root.mediaExpandedContentVisible)
            root.mediaLoaderActive = true;
        if (root.notificationActive)
            root.notificationLoaderActive = true;
    }
}
