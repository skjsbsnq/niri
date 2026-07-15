pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion

// Scene host for the Dynamic Island capsule.
// Compact/transient chrome stays lightweight and always present.
// Expanded media/summary use Loader so hidden outputs and non-expanded
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
    property color accentColor: "#0a84ff"
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
    readonly property bool mediaExpanded: islandState === "expanded_media"
    readonly property bool summaryExpanded: islandState === "expanded_summary"

    readonly property bool notificationActive: islandState === "transient_notification"
    readonly property bool standardDetailActive: !compactResting && !notificationActive && !osdActive && !mediaExpanded && !summaryExpanded
    readonly property bool osdActive: islandState === "transient_osd"
    // T13: horizontal bar OSD; ring removed. Scene visible whenever OSD active.
    readonly property bool osdSceneVisible: osdActive
    readonly property int notificationFadeInDuration: 280
    readonly property int notificationFadeOutDuration: 140
    // Hold outgoing expanded loaders through exit fade, then destroy.
    readonly property int expandedUnloadHoldMs: IslandMotion.overlayExpandedExitFadeMs + 40

    // Loader active flags: true while showing or exit-hold. Never both heavy
    // scenes need to stay loaded forever on resting/hidden outputs.
    property bool mediaLoaderActive: false
    property bool summaryLoaderActive: false

    function safeProgress(value) {
        var number = Number(value);
        if (!isFinite(number) || number < 0)
            return -1;

        return Math.max(0, Math.min(1, number));
    }

    onMediaExpandedContentVisibleChanged: {
        if (root.mediaExpandedContentVisible) {
            mediaUnloadHold.stop();
            root.mediaLoaderActive = true;
        } else {
            mediaUnloadHold.restart();
        }
    }

    onSummaryExpandedContentVisibleChanged: {
        if (root.summaryExpandedContentVisible) {
            summaryUnloadHold.stop();
            root.summaryLoaderActive = true;
        } else {
            summaryUnloadHold.restart();
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

    Timer {
        id: summaryUnloadHold
        interval: root.expandedUnloadHoldMs
        repeat: false
        onTriggered: {
            if (!root.summaryExpandedContentVisible)
                root.summaryLoaderActive = false;
        }
    }

    // V2 resting clock (T12). Media compact still uses compactLabel until T16.
    DynamicIslandRestingClockView {
        id: restingClock

        anchors.centerIn: parent
        width: Math.min(parent.width - 16, Math.max(contentWidth, 1))
        height: parent.height
        weekdayText: root.clockWeekdayText
        // Prefer split time; never fall back to combined displayText (would re-show weekday).
        timeText: root.clockTimeText
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        opacity: root.compactContentVisible && root.restingClockActive ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.overlayContentDuration; easing.type: IslandMotion.overlayColorEasing }
        }
    }

    Text {
        id: compactLabel

        anchors.centerIn: parent
        width: parent.width - 32
        // Compact media (and any non-clock resting) until T16 redesign.
        text: (root.compactResting && !root.restingClockActive) ? root.displayText : ""
        color: root.textPrimary
        font.pixelSize: 12
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        maximumLineCount: 1
        opacity: root.compactContentVisible && !root.restingClockActive ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.overlayContentDuration; easing.type: IslandMotion.overlayColorEasing }
        }
    }

    Row {
        id: detailRow

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: root.islandState.indexOf("expanded_") === 0 ? 24 : 16
            rightMargin: root.islandState.indexOf("expanded_") === 0 ? 24 : 16
        }
        height: Math.min(parent.height - 16, 52)
        spacing: 10
        opacity: root.standardDetailActive ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.overlayContentDuration; easing.type: IslandMotion.overlayColorEasing }
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
    // Opacity binds only to osdActive so rapid progress ticks do not re-enter.
    DynamicIslandOsdView {
        id: osdView

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 0
            rightMargin: 0
        }
        height: Math.min(parent.height, 44)
        iconCode: root.iconCode
        valueText: root.secondaryText
        // Bind progress directly so continuous OSD ticks update the bar/value.
        progress: root.progress
        muted: root.osdMuted
        darkMode: root.darkMode
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        accentColor: root.accentColor
        opacity: root.osdSceneVisible ? 1 : 0
        // Stay in the tree while OSD is active so progress rebinds without recreate.
        visible: root.osdActive || opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: IslandMotion.overlayContentDuration
                easing.type: IslandMotion.overlayColorEasing
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
            // Intentional hard-cut on collapse (not opacity>0.01 fade): MediaView's
            // visualizerTimer is gated on Item.visible. A mid-fade visible:true would
            // keep the timer ticking after mediaExpandedContentVisible is false.
            // Enter still fades opacity 0→1 while visible is already true.
            // Summary uses opacity-gated visible because it has no running Timer.
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
                    duration: IslandMotion.overlayExpandedEnterFadeMs
                    easing.type: IslandMotion.overlayColorEasing
                }
            }
        }
    }

    // Expanded summary: same Loader/unload policy as media.
    Loader {
        id: summaryLoader
        anchors.fill: parent
        active: root.summaryLoaderActive
        asynchronous: false
        sourceComponent: summarySceneComponent
    }

    Component {
        id: summarySceneComponent
        DynamicIslandSummaryView {
            anchors.fill: parent
            batteryPercent: root.summaryBatteryPercent
            batteryCharging: root.summaryBatteryCharging
            volume: root.summaryVolume
            muted: root.summaryMuted
            brightness: root.summaryBrightness
            brightnessAvailable: root.summaryBrightnessAvailable
            workspaceLabel: root.summaryWorkspaceLabel
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
            opacity: root.summaryExpandedContentVisible ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: root.summaryExpandedContentVisible
                        ? IslandMotion.overlayExpandedEnterFadeMs
                        : IslandMotion.overlayExpandedExitFadeMs
                    easing.type: IslandMotion.overlayColorEasing
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
            NumberAnimation { duration: IslandMotion.overlayContentDuration; easing.type: IslandMotion.overlayColorEasing }
        }
    }

    Component.onCompleted: {
        if (root.mediaExpandedContentVisible)
            root.mediaLoaderActive = true;
        if (root.summaryExpandedContentVisible)
            root.summaryLoaderActive = true;
    }
}
