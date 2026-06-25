pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../components/DynamicIslandMotion.js" as IslandMotion

// Dynamic Island state owner. The service owns transient arbitration so the
// overlay can stay a pure renderer for chip/notification/OSD states.
Item {
    id: root
    visible: false

    property var controlsService
    property var notificationsService
    property var windowsService
    property var batteryService
    property real swipeProgress: 0 // -1 = summary (left), +1 = media (right)
    property real swipeStartProgress: 0
    property bool swipeDragging: false
    property bool swipeSettling: false
    property bool swipeMoved: false
    readonly property int swipeLeftWidth: 360
    readonly property int swipeRightWidth: 400
    readonly property int swipeRestingWidth: restingWidthForState(restingState())
    readonly property real swipePreviewWidth: swipeDragging || swipeSettling
        ? swipeRestingWidth + (swipeSideWidthForProgress(swipeProgress) - swipeRestingWidth) * Math.min(1, Math.abs(swipeProgress))
        : -1

    property bool preferMediaWhenAvailable: true
    property date now: new Date()
    property string forcedState: ""
    property string transientDisplayText: ""
    property string transientSecondaryText: ""
    property real transientProgress: -1
    property string transientIconCode: ""
    property bool userInteracting: false
    property int observedNotificationCount: 0
    property int lastSeenNotificationId: -1
    property var pendingNotificationEntry: null
    property real lastVolume: 0
    property bool lastMuted: false
    property real lastBrightness: 1.0
    property bool brightnessTrackingReady: false
    property var pendingOsd: null
    property string lastWorkspaceName: ""
    property bool workspaceTrackingReady: false

    readonly property bool hasMedia: controlsService ? controlsService.hasMedia : false
    readonly property bool expanded: state === "expanded_media" || state === "expanded_summary"
    readonly property string mediaArtUrl: controlsService ? String(controlsService.trackArtUrl || "") : ""
    readonly property bool mediaPlaying: controlsService ? !!controlsService.isPlaying : false
    readonly property real mediaPosition: controlsService ? Number(controlsService.trackPosition) : 0
    readonly property real mediaLength: controlsService ? Number(controlsService.trackLength) : 0
    readonly property real mediaProgress: controlsService ? Number(controlsService.trackProgress) : 0
    readonly property bool mediaPositionSupported: controlsService ? !!controlsService.trackPositionSupported : false
    readonly property bool mediaLengthSupported: controlsService ? !!controlsService.trackLengthSupported : false
    readonly property bool canPlayPause: controlsService ? !!controlsService.canPlayPause : false
    readonly property bool canNext: controlsService ? !!controlsService.canNext : false
    readonly property bool canPrev: controlsService ? !!controlsService.canPrev : false
    readonly property int summaryBatteryPercent: batteryService ? Number(batteryService.roundedPercentage) : 0
    readonly property bool summaryBatteryCharging: batteryService ? !!batteryService.charging : false
    readonly property real summaryVolume: controlsService ? Number(controlsService.volume) : 0
    readonly property bool summaryMuted: controlsService ? !!controlsService.muted : false
    readonly property real summaryBrightness: controlsService ? Number(controlsService.brightness) : 0
    readonly property bool summaryBrightnessAvailable: controlsService ? !!controlsService.brightnessAvailable : false
    readonly property string summaryWorkspaceLabel: activeWorkspaceText()
    function mediaTogglePlayPause() {
        if (root.controlsService)
            root.controlsService.togglePlayPause();
    }
    function mediaNext() {
        if (root.controlsService)
            root.controlsService.next();
    }
    function mediaPrevious() {
        if (root.controlsService)
            root.controlsService.previous();
    }
    readonly property string displayText: displayTextForState(state)
    readonly property string secondaryText: secondaryTextForState(state)
    readonly property real progress: progressForState(state)
    readonly property string iconCode: iconCodeForState(state)
    readonly property string targetScreenName: computeTargetScreenName()
    readonly property int smokeTransientHideMs: 1250
    readonly property int notificationHideMs: 4200
    readonly property int smokeNotificationHideMs: notificationHideMs
    readonly property int osdHideMs: 1250
    readonly property var validStates: [
        "resting_time",
        "resting_media",
        "transient_osd",
        "transient_notification",
        "transient_workspace",
        "expanded_media",
        "expanded_summary"
    ]

    state: normalizedState(root.forcedState)

    onStateChanged: {
        maybeShowPendingNotification();
        maybeShowPendingOsd();
    }
    onUserInteractingChanged: {
        maybeShowPendingNotification();
        maybeShowPendingOsd();
    }
    onNotificationsServiceChanged: resetNotificationTracking()

    Component.onCompleted: {
        resetNotificationTracking();
        captureOsdBaselines();
        captureWorkspaceBaseline();
    }

    function msecsToNextMinute() {
        return Math.max(250, 60000 - (root.now.getSeconds() * 1000 + root.now.getMilliseconds()));
    }

    function isValidState(nextState) {
        return root.validStates.indexOf(String(nextState || "")) >= 0;
    }

    function restingState() {
        return root.preferMediaWhenAvailable && root.hasMedia ? "resting_media" : "resting_time";
    }

    function normalizedState(nextState) {
        var candidate = String(nextState || "");
        if (!isValidState(candidate))
            return restingState();

        if ((candidate === "resting_media" || candidate === "expanded_media") && !root.hasMedia)
            return "resting_time";

        return candidate;
    }

    function timeText() {
        return Qt.formatDateTime(root.now, "ddd HH:mm");
    }

    function dateText() {
        return Qt.formatDateTime(root.now, "yyyy-MM-dd");
    }

    function mediaTitle() {
        if (!root.controlsService)
            return "";

        var title = String(root.controlsService.trackTitle || "").trim();
        if (title.length > 0)
            return title;

        var artist = String(root.controlsService.trackArtist || "").trim();
        return artist.length > 0 ? artist : "正在播放";
    }

    function mediaArtist() {
        if (!root.controlsService)
            return "";

        return String(root.controlsService.trackArtist || "").trim();
    }

    function activeWorkspaceText() {
        if (!root.windowsService)
            return "";

        var label = String(root.windowsService.activeWorkspaceName || "").trim();
        return label.length > 0 ? "Workspace " + label : "";
    }

    function displayTextForState(currentState) {
        switch (currentState) {
        case "resting_media":
        case "expanded_media":
            return mediaTitle();
        case "transient_osd":
        case "transient_notification":
        case "transient_workspace":
            return root.transientDisplayText.length > 0 ? root.transientDisplayText : fallbackTransientText(currentState);
        case "expanded_summary":
            return "摘要";
        case "resting_time":
        default:
            return timeText();
        }
    }

    function secondaryTextForState(currentState) {
        switch (currentState) {
        case "resting_media":
        case "expanded_media":
            return mediaArtist();
        case "transient_osd":
        case "transient_notification":
        case "transient_workspace":
            return root.transientSecondaryText;
        case "expanded_summary":
            return activeWorkspaceText();
        case "resting_time":
        default:
            return dateText();
        }
    }

    function progressForState(currentState) {
        if (currentState === "transient_osd")
            return Math.max(0, Math.min(1, root.transientProgress));

        return -1;
    }

    function iconCodeForState(currentState) {
        if (root.transientIconCode.length > 0 && currentState.indexOf("transient_") === 0)
            return root.transientIconCode;

        switch (currentState) {
        case "resting_media":
        case "expanded_media":
            return root.controlsService && root.controlsService.isPlaying ? "\ue034" : "\ue037";
        case "transient_notification":
            return "\ue7f4";
        case "transient_workspace":
            return "\ue1b1";
        case "transient_osd":
            return "\ue050";
        case "expanded_summary":
            return "\ue8b8";
        case "resting_time":
        default:
            return "\ue8b5";
        }
    }

    function fallbackTransientText(currentState) {
        switch (currentState) {
        case "transient_osd":
            return "系统";
        case "transient_notification":
            return "通知";
        case "transient_workspace":
            return activeWorkspaceText();
        default:
            return timeText();
        }
    }

    function computeTargetScreenName() {
        var focused = root.windowsService ? root.windowsService.focusedWindow : null;
        var output = focused ? String(focused.output || "").trim() : "";
        if (output.length > 0)
            return output;

        var workspace = root.windowsService ? root.windowsService.activeWorkspace : null;
        output = workspace ? String(workspace.output || "").trim() : "";
        if (output.length > 0)
            return output;

        var screens = [...Quickshell.screens];
        return screens.length > 0 ? String(screens[0].name || "") : "";
    }

    function clearTransientFields() {
        root.transientDisplayText = "";
        root.transientSecondaryText = "";
        root.transientProgress = -1;
        root.transientIconCode = "";
    }

    function reset() {
        transientTimer.stop();
        root.pendingNotificationEntry = null;
        root.preferMediaWhenAvailable = true;
        clearTransientFields();
        root.forcedState = "";
    }

    function showTime() {
        transientTimer.stop();
        root.preferMediaWhenAvailable = false;
        clearTransientFields();
        root.forcedState = "";
        maybeShowPendingNotification();
    }

    function showMedia() {
        transientTimer.stop();
        root.preferMediaWhenAvailable = true;
        clearTransientFields();
        root.forcedState = root.hasMedia ? "resting_media" : "";
        maybeShowPendingNotification();
    }

    function showExpandedMedia() {
        transientTimer.stop();
        root.preferMediaWhenAvailable = true;
        clearTransientFields();
        root.forcedState = root.hasMedia ? "expanded_media" : "expanded_summary";
    }

    function showExpandedSummary() {
        transientTimer.stop();
        clearTransientFields();
        root.forcedState = "expanded_summary";
    }

    function toggleExpanded() {
        if (root.expanded) {
            root.forcedState = "";
            maybeShowPendingNotification();
            return;
        }

        if (root.hasMedia)
            showExpandedMedia();
        else
            showExpandedSummary();
    }

    function showTransient(nextState, text, secondary, progressValue, icon, hideMs) {
        var candidate = String(nextState || "");
        if (candidate !== "transient_osd"
                && candidate !== "transient_notification"
                && candidate !== "transient_workspace")
            return;

        root.transientDisplayText = String(text || "");
        root.transientSecondaryText = String(secondary || "");
        root.transientProgress = Number(progressValue);
        root.transientIconCode = String(icon || "");
        root.forcedState = candidate;
        transientTimer.interval = Math.max(250, Math.round(Number(hideMs) || root.smokeTransientHideMs));
        transientTimer.restart();
    }

   function showTransientOsd(text, progressValue) {
        showTransientOsdWithIcon(text, progressValue, "\ue050");
    }

    function showTransientOsdWithIcon(text, progressValue, icon) {
        var progress = Math.max(0, Math.min(1, Number(progressValue) || 0));
        showTransient("transient_osd", text, Math.round(progress * 100) + "%", progress,
            String(icon || "\ue050"), root.osdHideMs);
   }

   function showTransientNotification(summary, body, appName) {
        queueOrShowNotificationEntry({
            "id": -1,
            "summary": sanitizeNotificationText(summary, ""),
            "body": sanitizeNotificationText(body, ""),
            "appName": sanitizeNotificationText(appName, "")
        });
    }

    function showTransientWorkspace(label) {
        var text = String(label || "").trim();
        showTransient("transient_workspace", text.length > 0 ? text : activeWorkspaceText(), "", -1, "\ue1b1", root.smokeTransientHideMs);
    }
    function captureWorkspaceBaseline() {
        var label = root.windowsService ? String(root.windowsService.activeWorkspaceName || "") : "";
        root.lastWorkspaceName = label;
        root.workspaceTrackingReady = label.length > 0;
    }

    function blocksTransientWorkspace() {
        return root.expanded || root.userInteracting;
    }

    function handleWorkspaceChange() {
        if (!root.windowsService)
            return;

        var label = String(root.windowsService.activeWorkspaceName || "");
        if (label.length === 0) {
            root.lastWorkspaceName = label;
            return;
        }

        if (!root.workspaceTrackingReady) {
            root.lastWorkspaceName = label;
            root.workspaceTrackingReady = true;
            return;
        }

        if (label === root.lastWorkspaceName)
            return;

        root.lastWorkspaceName = label;
        if (root.blocksTransientWorkspace())
            return;

        var display = activeWorkspaceText();
        showTransient("transient_workspace", display, "", -1, "\ue1b1", root.smokeTransientHideMs);
    }


    function restingWidthForState(currentState) {
        switch (currentState) {
        case "resting_media":
            return 190;
        case "expanded_media":
            return 400;
        case "expanded_summary":
            return 360;
        case "transient_notification":
            return 320;
        case "transient_osd":
        case "transient_workspace":
            return 220;
        case "resting_time":
        default:
            return 140;
        }
    }

    function swipeSideWidthForProgress(progressValue) {
        return progressValue >= 0 ? root.swipeRightWidth : root.swipeLeftWidth;
    }

    function canSwipe() {
        var s = root.state;
        return s === "resting_time"
            || s === "resting_media"
            || s === "expanded_media"
            || s === "expanded_summary";
    }

    function beginSwipe() {
        if (!root.canSwipe())
            return false;
        swipeSettleTimer.stop();
        root.swipeDragging = true;
        root.swipeSettling = false;
        root.swipeMoved = false;
        if (root.state === "expanded_media")
            root.swipeStartProgress = 1;
        else if (root.state === "expanded_summary")
            root.swipeStartProgress = -1;
        else
            root.swipeStartProgress = 0;
        root.swipeProgress = root.swipeStartProgress;
        root.setUserInteracting(true);
        return true;
    }

    function advanceSwipe(deltaX, deltaY) {
        if (!root.swipeDragging)
            return;

        var vertical = Math.abs(Number(deltaY) || 0);
        var horizontal = vertical > 220 ? 0 : (Number(deltaX) || 0);
        // vertical drift beyond the tolerance degrades the horizontal pull,
        // matching Tide's sideSwipeVerticalTolerance behaviour.
        if (vertical > IslandMotion.swipeVerticalTolerance)
            horizontal = horizontal * Math.max(0, 1 - (vertical - IslandMotion.swipeVerticalTolerance) / 36);

        var sideWidth = Math.max(1, root.swipeSideWidthForProgress(root.swipeProgress || horizontal));
        var next = root.swipeProgress + horizontal / sideWidth;
        next = Math.max(-1, Math.min(1, next));
        if (Math.abs(next - root.swipeProgress) > 0.01)
            root.swipeMoved = true;
        root.swipeProgress = next;
    }

    function resolveSwipe() {
        if (!root.swipeDragging)
            return;

        root.swipeDragging = false;
        root.setUserInteracting(false);
        var progress = root.swipeProgress;
        var startProgress = root.swipeStartProgress;
        var entered = false;

        if (progress >= IslandMotion.swipeEnterThreshold) {
            root.swipeSettling = true;
            root.swipeProgress = 0;
            root.forcedState = root.hasMedia ? "expanded_media" : "expanded_summary";
            entered = true;
        } else if (progress <= -IslandMotion.swipeEnterThreshold) {
            root.swipeSettling = true;
            root.swipeProgress = 0;
            root.forcedState = "expanded_summary";
            entered = true;
        } else if (startProgress >= 0.5 && progress <= IslandMotion.swipeReturnThreshold) {
            root.swipeSettling = true;
            root.swipeProgress = 0;
            root.forcedState = "";
        } else if (startProgress <= -0.5 && progress >= -IslandMotion.swipeReturnThreshold) {
            root.swipeSettling = true;
            root.swipeProgress = 0;
            root.forcedState = "";
        } else {
            root.swipeSettling = true;
            root.swipeProgress = 0;
        }

        swipeSettleTimer.restart();
        root.swipeMoved = false;
        if (entered)
            root.maybeShowPendingNotification();
    }

    function cancelSwipe() {
        if (!root.swipeDragging)
            return;

        root.swipeDragging = false;
        root.swipeSettling = true;
        root.swipeStartProgress = 0;
        root.swipeProgress = 0;
        root.setUserInteracting(false);
        swipeSettleTimer.restart();
    }

    function consumeSwipeMoved() {
        var moved = root.swipeMoved;
        root.swipeMoved = false;
        return moved;
    }


   function handleChipClick(button) {
        if (button === Qt.LeftButton)
            toggleExpanded();
        else if (button === Qt.RightButton)
            showExpandedSummary();
    }

    function setUserInteracting(active) {
        root.userInteracting = !!active;
        if (!root.userInteracting)
            maybeShowPendingNotification();
    }

    function resetNotificationTracking() {
        var list = root.notificationsService ? root.notificationsService.activeModel : [];
        root.observedNotificationCount = list ? list.length : 0;
        root.lastSeenNotificationId = root.observedNotificationCount > 0
            ? notificationId(list[root.observedNotificationCount - 1])
            : -1;
        root.pendingNotificationEntry = null;
    }

    function notificationId(notification) {
        if (!notification)
            return -1;

        try {
            var id = Number(notification.id);
            return isFinite(id) ? id : -1;
        } catch (e) {
            return -1;
        }
    }

    function handleNotificationsChanged() {
        var list = root.notificationsService ? root.notificationsService.activeModel : [];
        var nextCount = list ? list.length : 0;
        if (nextCount <= root.observedNotificationCount) {
            root.observedNotificationCount = nextCount;
            return;
        }

        var notification = list[nextCount - 1];
        root.observedNotificationCount = nextCount;
        handleIncomingNotification(notification);
    }

    function handleIncomingNotification(notification) {
        if (!notification || notificationsDndEnabled())
            return;

        var id = notificationId(notification);
        if (id >= 0 && id === root.lastSeenNotificationId)
            return;

        root.lastSeenNotificationId = id;
        queueOrShowNotificationEntry(notificationEntry(notification));
    }

    function notificationEntry(notification) {
        if (!notification)
            return null;

        var appName = sanitizeNotificationText(notification.appName, "");
        var summary = sanitizeNotificationText(notification.summary, "");
        var body = sanitizeNotificationText(notification.body, "");

        if (summary.length === 0)
            summary = appName.length > 0 ? appName : "通知";

        return {
            "id": notificationId(notification),
            "summary": summary,
            "body": body,
            "appName": appName
        };
    }

    function notificationsDndEnabled() {
        return !!(root.notificationsService && root.notificationsService.dndEnabled);
    }

   function blocksTransientNotification() {
       return root.expanded || root.userInteracting;
   }

    function blocksTransientOsd() {
        return root.expanded || root.userInteracting;
    }

    function captureOsdBaselines() {
        if (!root.controlsService)
            return;
        root.lastVolume = Number(root.controlsService.volume) || 0;
        root.lastMuted = !!root.controlsService.muted;
        root.lastBrightness = Number(root.controlsService.brightness);
        if (!(root.lastBrightness > 0))
            root.lastBrightness = 1.0;
        root.brightnessTrackingReady = !!root.controlsService.brightnessAvailable;
    }

   function presentOsdEntry(entry) {
       if (!entry || blocksTransientOsd()) {
           if (entry)
               root.pendingOsd = entry;
           return;
       }
       root.pendingOsd = null;
       var icon = String(entry.icon || "\ue050");
       if (entry.kind === "volume") {
           var muted = !!entry.muted;
           var progress = muted ? 0 : Math.max(0, Math.min(1, Number(entry.progress)));
            showTransientOsdWithIcon(muted ? "静音" : "音量", progress,
                muted ? "\ue04f" : "\ue050");
       } else {
            showTransientOsdWithIcon("亮度", Number(entry.progress), "\ue518");
       }
   }

    function maybeShowPendingOsd() {
        if (!root.pendingOsd || blocksTransientOsd())
            return;
        var entry = root.pendingOsd;
        root.pendingOsd = null;
        presentOsdEntry(entry);
    }

    function handleVolumeChange() {
        if (!root.controlsService)
            return;
        var volume = Number(root.controlsService.volume) || 0;
        var muted = !!root.controlsService.muted;
        root.lastVolume = volume;
        root.lastMuted = muted;
        presentOsdEntry({
            "kind": "volume",
            "progress": muted ? 0 : volume,
            "muted": muted,
            "icon": muted ? "\ue04f" : "\ue050"
        });
    }

    function handleMuteChange() {
        if (!root.controlsService)
            return;
        var muted = !!root.controlsService.muted;
        root.lastMuted = muted;
        var volume = Number(root.controlsService.volume) || 0;
        presentOsdEntry({
            "kind": "volume",
            "progress": muted ? 0 : volume,
            "muted": muted,
            "icon": muted ? "\ue04f" : "\ue050"
        });
    }

    function handleBrightnessChange() {
        if (!root.controlsService)
            return;
        var brightness = Number(root.controlsService.brightness);
        if (!(brightness > 0))
            return;
        if (!root.controlsService.brightnessAvailable) {
            root.lastBrightness = brightness;
            root.brightnessTrackingReady = false;
            return;
        }
        if (!root.brightnessTrackingReady) {
            root.lastBrightness = brightness;
            root.brightnessTrackingReady = true;
            return;
        }
        if (Math.abs(brightness - root.lastBrightness) < 0.005)
            return;
        root.lastBrightness = brightness;
        presentOsdEntry({
            "kind": "brightness",
            "progress": brightness,
            "icon": "\ue518"
        });
    }

   function queueOrShowNotificationEntry(entry) {
        if (!entry || notificationsDndEnabled())
            return;

        if (blocksTransientNotification()) {
            root.pendingNotificationEntry = entry;
            return;
        }

        presentNotificationEntry(entry);
    }

    function maybeShowPendingNotification() {
        if (!root.pendingNotificationEntry || blocksTransientNotification() || notificationsDndEnabled())
            return;

        var entry = root.pendingNotificationEntry;
        root.pendingNotificationEntry = null;
        presentNotificationEntry(entry);
    }

    function presentNotificationEntry(entry) {
        if (!entry || notificationsDndEnabled())
            return;

        var title = sanitizeNotificationText(entry.summary, "通知");
        var detail = sanitizeNotificationText(entry.body, "");
        var appName = sanitizeNotificationText(entry.appName, "");
        if (detail.length === 0 && appName.length > 0 && appName !== title)
            detail = appName;
        if (detail === title)
            detail = "";

        showTransient("transient_notification", title, detail, -1, "\ue7f4", root.notificationHideMs);
    }

    function handleDndChanged() {
        if (!notificationsDndEnabled())
            return;

        root.pendingNotificationEntry = null;
        if (root.state === "transient_notification") {
            transientTimer.stop();
            root.forcedState = "";
            clearTransientFields();
        }
    }

    function decodeHtmlEntity(entity) {
        var key = String(entity || "").toLowerCase();
        switch (key) {
        case "amp":
            return "&";
        case "lt":
            return "<";
        case "gt":
            return ">";
        case "quot":
            return "\"";
        case "apos":
            return "'";
        case "nbsp":
            return " ";
        default:
            break;
        }

        if (key.indexOf("#x") === 0) {
            var hex = parseInt(key.slice(2), 16);
            return isFinite(hex) && hex > 0 ? String.fromCharCode(hex) : "";
        }

        if (key.indexOf("#") === 0) {
            var dec = parseInt(key.slice(1), 10);
            return isFinite(dec) && dec > 0 ? String.fromCharCode(dec) : "";
        }

        return "";
    }

    function decodeHtmlEntities(text) {
        return String(text || "").replace(/&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos|nbsp);/g, function(match, entity) {
            var decoded = root.decodeHtmlEntity(entity);
            return decoded.length > 0 ? decoded : match;
        });
    }

    function sanitizeNotificationText(value, fallback) {
        var text = "";
        try {
            text = String(value || "");
        } catch (e) {
            text = "";
        }

        text = text.replace(/<\s*br\s*\/?\s*>/gi, " ");
        text = text.replace(/<\s*\/\s*p\s*>/gi, " ");
        text = text.replace(/<\s*\/\s*div\s*>/gi, " ");
        text = decodeHtmlEntities(text);
        text = text.replace(/<[^>]*>/g, " ");
        text = decodeHtmlEntities(text);
        text = text.replace(/\s+/g, " ").trim();

        if (text.length > 0)
            return text;

        return String(fallback || "");
    }

    function debugSummary() {
        return [
            "state=" + root.state,
            "displayText=" + root.displayText,
            "secondaryText=" + root.secondaryText,
            "progress=" + root.progress,
            "iconCode=" + root.iconCode,
            "targetScreenName=" + root.targetScreenName,
            "expanded=" + root.expanded,
            "pendingNotification=" + !!root.pendingNotificationEntry,
            "swipeStartProgress=" + root.swipeStartProgress,
            "swipeProgress=" + root.swipeProgress,
            "swipePreviewWidth=" + root.swipePreviewWidth,
            "swipeDragging=" + root.swipeDragging,
            "swipeSettling=" + root.swipeSettling
        ].join("; ");
    }

    Connections {
        target: root.notificationsService
        ignoreUnknownSignals: true

        function onActiveModelChanged() {
            root.handleNotificationsChanged();
        }

        function onDndEnabledChanged() {
            root.handleDndChanged();
        }
    }

    Connections {
        target: root.controlsService
        ignoreUnknownSignals: true

        function onVolumeChanged() {
            root.handleVolumeChange();
        }

        function onMutedChanged() {
            root.handleMuteChange();
        }

        function onBrightnessChanged() {
            root.handleBrightnessChange();
        }

       function onBrightnessAvailableChanged() {
           root.captureOsdBaselines();
       }
   }

    Connections {
        target: root.windowsService
        ignoreUnknownSignals: true

        function onActiveWorkspaceNameChanged() {
            root.handleWorkspaceChange();
        }
    }

    Timer {
        id: minuteTimer
        interval: root.msecsToNextMinute()
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Timer {
        id: transientTimer
        interval: root.smokeTransientHideMs
        repeat: false
        onTriggered: {
            root.clearTransientFields();
            root.forcedState = "";
        }
    }

    Timer {
        id: swipeSettleTimer
        interval: IslandMotion.swipeSettleDuration
        repeat: false
        onTriggered: {
            root.swipeSettling = false;
            root.swipeStartProgress = 0;
        }
    }

}
