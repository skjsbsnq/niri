pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion
import "Motion.js" as Motion

// Scene host for the Dynamic Island capsule.
// Compact/transient chrome stays lightweight and always present.
// Expanded media uses Loader so hidden outputs and non-expanded
// states do not keep heavy scenes (and their Timers) instantiated.
// Transition may hold current + outgoing for the exit fade only.
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
    property bool compactResting: true
    signal notificationBodyClicked()
    signal notificationDismissRequested()
    signal notificationExpandToggleRequested()
    signal notificationActionInvoked(string actionId)
    signal notificationInteractionBegan()
    signal notificationInteractionEnded()
    property bool compactContentVisible: compactResting
    property bool mediaExpandedContentVisible: mediaExpanded
    property bool summaryExpandedContentVisible: summaryExpanded
    property bool showSecondaryText: false
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property bool darkMode: true
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
    property int summaryBatteryPercent: 0
    property bool summaryBatteryCharging: false
    property real summaryVolume: 0
    property bool summaryMuted: false
    property real summaryBrightness: 0
    property bool summaryBrightnessAvailable: false
    property string summaryWorkspaceLabel: ""
    property int workspaceDirection: 0
    property string workspaceLabel: ""
    property int workspaceCount: 0
    readonly property bool mediaExpanded: islandState === "expanded_media"
    readonly property bool summaryExpanded: false
    readonly property bool compactMediaActive: islandState === "resting_media"
    // Measured compact media content width (no capsule padding). Overlay clamps.
    // While compact media is exiting, freeze measured width on the latch so the
    // capsule does not shrink mid-fade when the player disappears.
    readonly property int compactMediaContentWidth: {
        if (root.compactMediaActive || root.compactLayerHeld)
            return Math.max(compactMedia.contentWidth, root.latchedCompactMediaWidth);
        return compactMedia.contentWidth;
    }
    // Last non-empty title/width while compact media is shown or exit-held so
    // player disappear does not rewrite the fading scene with clock text.
    property string latchedCompactMediaTitle: ""
    property int latchedCompactMediaWidth: 0
    readonly property string compactMediaTitle: {
        var live = String(root.mediaTrackTitle || "").trim();
        if (live.length > 0)
            return live;
        // Keep latched title through exit fade (including media→clock without
        // compactLayerHeld, when both stay in the compact resting layer).
        return root.latchedCompactMediaTitle;
    }
    readonly property int compactContentMotionMs: root.osdActive
        ? IslandMotion.v2OsdEnterMs
        : IslandMotion.contentExitMs(root.settingsService)

    readonly property bool notificationActive: islandState === "transient_notification"
    readonly property bool standardDetailActive: !compactResting && !notificationActive && !osdActive && !mediaExpanded && !summaryExpanded && !workspaceActive
    readonly property bool osdActive: islandState === "transient_osd"
    readonly property bool workspaceActive: islandState === "transient_workspace"
    // T13: horizontal bar OSD; ring removed. Scene visible whenever OSD active.
    readonly property bool osdSceneVisible: osdActive && !osdExiting
    property real osdLayerOpacity: 0
    property real osdLayerOffset: 0
    // T19: notification enter/exit use V2 content helpers (reduced-aware).
    readonly property int notificationFadeInDuration: IslandMotion.contentEnterMs(root.settingsService)
    readonly property int notificationFadeOutDuration: IslandMotion.contentExitMs(root.settingsService)
    // Hold outgoing expanded loaders through exit fade, then destroy.
    readonly property int expandedUnloadHoldMs: IslandMotion.contentExitMs(root.settingsService) + 40

    // Loader active flags: true while showing or exit-hold. Never both heavy
    // scenes need to stay loaded forever on resting/hidden outputs.
    property bool mediaLoaderActive: false

    function safeProgress(value) {
        var number = Number(value);
        if (!isFinite(number) || number < 0)
            return -1;

        return Math.max(0, Math.min(1, number));
    }

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


    // Compact chrome (clock / media label): real exit animation — fade + move UP
    // (never sink). Hold the layer for exit duration after state leaves resting.
    property bool compactLayerWanted: root.compactContentVisible
        && (root.restingClockActive || (!root.restingClockActive && root.compactResting))
    property bool compactLayerHeld: false
    readonly property bool compactLayerShown: compactLayerWanted || compactLayerHeld
    property real compactLayerOpacity: 0
    property real compactLayerY: 0

    onCompactLayerWantedChanged: {
        if (root.compactLayerWanted) {
            compactExitHold.stop();
            root.compactLayerHeld = false;
            root.compactLayerOpacity = 1;
            root.compactLayerY = 0;
        } else if (root.compactLayerShown || root.compactLayerOpacity > 0.01) {
            if (root.osdActive) {
                // Hardware feedback owns the first frame; do not cross-fade the
                // old clock/media label over the live bar and number.
                compactExitHold.stop();
                root.compactLayerHeld = false;
                root.compactLayerOpacity = 0;
                root.compactLayerY = 0;
                return;
            }
            // Exit: fade out and travel up (negative y), then unload.
            root.compactLayerHeld = true;
            root.compactLayerOpacity = 0;
            root.compactLayerY = -IslandMotion.contentTravelPx(root.settingsService);
            compactExitHold.restart();
        }
    }

    Timer {
        id: compactExitHold
        interval: root.compactContentMotionMs + 20
        repeat: false
        onTriggered: {
            root.compactLayerHeld = false;
            root.compactLayerY = 0;
            if (!root.compactMediaActive) {
                root.latchedCompactMediaTitle = "";
                root.latchedCompactMediaWidth = 0;
            }
        }
    }

    // V2 resting clock (T12). Top-stable; exit via compactLayerOpacity/Y.
    DynamicIslandRestingClockView {
        id: restingClock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.compactLayerY
        width: Math.min(parent.width - 16, Math.max(contentWidth, 1))
        height: IslandMotion.v2ClockHeight
        weekdayText: root.clockWeekdayText
        timeText: root.clockTimeText
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        // Show while resting_time, or during exit hold that started from clock.
        opacity: root.restingClockActive
                 ? root.compactLayerOpacity
                 : (root.compactLayerHeld && root.clockTimeText.length > 0 ? root.compactLayerOpacity : 0)
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: root.compactContentMotionMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
        Behavior on anchors.topMargin {
            NumberAnimation {
                duration: root.compactContentMotionMs
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
            compactMediaExitLatch.stop();
            var live = String(root.mediaTrackTitle || "").trim();
            if (live.length > 0)
                root.latchedCompactMediaTitle = live;
            if (compactMedia.contentWidth > 0)
                root.latchedCompactMediaWidth = compactMedia.contentWidth;
        } else if (!root.compactLayerHeld) {
            // media→clock (compact layer stays wanted): clear latch after fade.
            compactMediaExitLatch.restart();
        }
    }

    Timer {
        id: compactMediaExitLatch
        interval: root.compactContentMotionMs + 20
        repeat: false
        onTriggered: {
            if (!root.compactMediaActive && !root.compactLayerHeld) {
                root.latchedCompactMediaTitle = "";
                root.latchedCompactMediaWidth = 0;
            }
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

    // T16: V2 compact media (art + title + play/pause). Shares compactLayer
    // opacity/y with the resting clock so clock↔media morph has no black frame.
    DynamicIslandCompactMediaView {
        id: compactMedia

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.compactLayerY
        width: Math.min(parent.width - 8, Math.max(contentWidth, IslandMotion.v2CompactMediaWidthMin))
        height: IslandMotion.v2CompactMediaHeight
        artUrl: root.mediaArtUrl
        // Never fall back to displayText (clock) — use live or latched title only.
        trackTitle: root.compactMediaTitle
        isPlaying: root.mediaPlaying
        progress: root.mediaProgress
        // Show progress only when Controls reports position support (and length > 0).
        progressSupported: root.mediaPositionSupported && root.mediaLength > 0
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        accentColor: root.accentColor
        trackColor: root.progressTrackColor
        // Active media: follow compact layer. Leave media: fade to 0 (Behavior)
        // while latched title keeps geometry; leave compact entirely: follow
        // compactLayerOpacity during exit hold.
        opacity: {
            if (root.compactMediaActive)
                return root.compactLayerOpacity;
            if (root.compactLayerHeld && root.latchedCompactMediaTitle.length > 0)
                return root.compactLayerOpacity;
            return 0;
        }
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: root.compactContentMotionMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
        Behavior on anchors.topMargin {
            NumberAnimation {
                duration: root.compactContentMotionMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
    }

    Row {
        id: detailRow

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: 8
            leftMargin: root.islandState.indexOf("expanded_") === 0 ? 24 : 16
            rightMargin: root.islandState.indexOf("expanded_") === 0 ? 24 : 16
        }
        height: Math.min(parent.height - 16, 52)
        spacing: 10
        opacity: root.standardDetailActive ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.contentEnterMs(root.settingsService); easing.type: IslandMotion.v2ContentEasing }
        }

        TahoeSymbol {
            name: root.iconCode
            color: root.textPrimary
            size: 20
        }

        Item {
            width: Math.max(1, parent.width - 34)
            height: parent.height

            Text {
                id: detailPrimary

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: root.showSecondaryText ? 4 : 0
                }
                text: root.displayText
                color: root.textPrimary
                font.pixelSize: root.islandState.indexOf("expanded_") === 0 ? 17 : 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: detailPrimary.bottom
                    topMargin: 2
                }
                text: root.secondaryText
                color: root.textSecondary
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: root.showSecondaryText
            }
        }
    }

    // T14/T15: notification with app identity, expand chevron, and actions.
    DynamicIslandNotificationView {
        id: notificationView

        anchors.fill: parent
        appName: root.notificationAppName
        summary: root.displayText
        body: root.secondaryText
        iconUrl: root.notificationIconUrl
        urgency: root.notificationUrgency
        hasOverflow: root.notificationHasOverflow
        expanded: root.notificationExpanded
        actions: root.notificationActions
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        opacity: root.notificationActive ? 1 : 0
        visible: opacity > 0.01
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

        Behavior on opacity {
            NumberAnimation {
                duration: root.notificationActive
                    ? root.notificationFadeInDuration
                    : root.notificationFadeOutDuration
                easing.type: IslandMotion.overlayColorEasing
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
                duration: root.compactContentMotionMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
        Behavior on x {
            NumberAnimation {
                duration: root.compactContentMotionMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
    }

    // Expanded media: Loader only while visible or exit-hold (no hidden Timer).
    Loader {
        id: mediaLoader
        anchors.fill: parent
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
            // T17: no visualizer Timer. Hard-cut on collapse still avoids mid-fade
            // hit targets; enter fades opacity 0→1 while visible is already true.
            opacity: root.mediaExpandedContentVisible ? 1 : 0
            visible: root.mediaExpandedContentVisible
            onPreviousRequested: root.mediaPreviousRequested()
            onPlayPauseRequested: root.mediaPlayPauseRequested()
            onNextRequested: root.mediaNextRequested()
            onControlPressed: root.mediaControlPressed()
            onControlReleased: root.mediaControlReleased()

            Behavior on opacity {
                enabled: root.mediaExpandedContentVisible
                NumberAnimation {
                    duration: IslandMotion.contentEnterMs(root.settingsService)
                    easing.type: IslandMotion.v2ContentEasing
                }
            }
        }
    }


    Rectangle {
        id: progressTrack

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 18
            rightMargin: 18
            bottomMargin: 8
        }
        height: 3
        radius: 2
        color: "#28ffffff"
        // Bottom track is for non-OSD progress (e.g. media compact later). OSD uses OsdView bar.
        opacity: (root.safeProgress(root.progress) >= 0 && !root.osdActive) ? 1 : 0
        visible: opacity > 0.01

        Rectangle {
            width: parent.width * Math.max(0, root.safeProgress(root.progress))
            height: parent.height
            radius: parent.radius
            color: "#f0ffffff"

            Behavior on width {
                NumberAnimation { duration: IslandMotion.overlayProgressDuration; easing.type: IslandMotion.overlayProgressEasing }
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.contentEnterMs(root.settingsService); easing.type: IslandMotion.v2ContentEasing }
        }
    }

    Component.onCompleted: {
        root.syncOsdLayerImmediately();
        if (root.compactLayerWanted) {
            root.compactLayerOpacity = 1;
            root.compactLayerY = 0;
        }
        if (root.mediaExpandedContentVisible)
            root.mediaLoaderActive = true;
    }
}
