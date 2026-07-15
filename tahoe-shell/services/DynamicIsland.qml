pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../components/DynamicIslandMotion.js" as IslandMotion
import "DynamicIslandReducer.js" as IslandReducer
import "../components/DynamicIslandOwnership.js" as IslandOwnership

// Dynamic Island state owner. The service owns transient arbitration so the
// overlay can stay a pure renderer for chip/notification/OSD states.
// Presentation base decisions (clock/media/expand) go through IslandReducer;
// this Item remains the sole production orchestrator and effect runner.
Item {
    id: root
    visible: false

    property var controlsService
    property var notificationsService
    property var windowsService
    property var batteryService
    property var settingsService
    property real swipeProgress: 0 // -1 = summary (left), +1 = media (right)
    property real swipeStartProgress: 0
    property string swipeStartForcedState: ""
    property bool swipeDragging: false
    property bool swipeSettling: false
    property bool swipeMoved: false
    // Keep in lockstep with DynamicIslandOverlay.widthForState (T11 V2 mid-band).
    readonly property int swipeLeftWidth: 360
    readonly property int swipeRightWidth: Math.round(
        (IslandMotion.v2MediaExpandedWidthMin + IslandMotion.v2MediaExpandedWidthMax) / 2)
    // Compute from preferMedia/hasMedia only — avoid binding through presentation.
    readonly property int swipeRestingWidth: restingWidthForState(
        (root.preferMediaWhenAvailable && root.hasMedia) ? "resting_media" : "resting_time")
    readonly property real swipePreviewWidth: swipeDragging || swipeSettling
        ? IslandOwnership.swipePreviewWidthFor(
            root.swipeProgress,
            root.swipeRestingWidth,
            root.swipeLeftWidth,
            root.swipeRightWidth)
        : -1

    property bool preferMediaWhenAvailable: true
    property date now: new Date()
    property string forcedState: ""
    property string transientDisplayText: ""
    property string transientSecondaryText: ""
    property real transientProgress: -1
    property string transientIconCode: ""
    // T13: explicit OSD muted flag for the view (not locale-dependent).
    property bool transientOsdMuted: false
    // T14: compact notification presentation fields (not a second model).
    property string transientNotificationAppName: ""
    property string transientNotificationIconUrl: ""
    property string transientNotificationUrgency: "normal"
    property bool transientNotificationHasOverflow: false
    // T15: expand + actions stay on the same transient_notification presentation.
    property bool transientNotificationExpanded: false
    property var transientNotificationActions: []
    property bool userInteracting: false
    // Stable notification identity tracking (T07 lease model).
    // seenNotificationIds: IDs already observed in activeModel (set membership).
    // completedNotificationIds: live IDs whose island presentation finished.
    // pendingNotificationIds: manual IPC payloads only (not a live ID queue).
    //   manual → { kind: "manual", summary, body, appName } immutable IPC payload
    // Live notifications resolve from Notifications.qml FIFO head/order.
    // displayingNotificationId: live ID currently shown (-1 for manual / none).
    property var seenNotificationIds: ({})
    property var completedNotificationIds: ({})
    property var pendingNotificationIds: []
    property int displayingNotificationId: -1
    property real lastVolume: 0
    property bool lastMuted: false
    // False while PipeWire sink is absent/unready so the first live sample
    // after reconnect only reseeds lastVolume/lastMuted (same pattern as
    // brightnessTrackingReady). Missing audioReady on fakes counts as ready.
    property bool volumeOsdTrackingReady: true
    property real lastBrightness: 1.0
    property bool brightnessTrackingReady: false
    property var pendingOsd: null
    property string lastWorkspaceName: ""
    property bool workspaceTrackingReady: false
    property bool hoverExpanded: false
    // Suppress onStateChanged restore while applyReducerResult runs so a single
    // presentation commit drains pending work exactly once (T07 H1).
    property bool applyingPresentationReducer: false
    // T08: pin event/session owners so transients do not jump with focus.
    // eventOwnerOutput: set when a transient is created; cleared on hide.
    // sessionOwnerOutput: set when user opens expanded on a screen; cleared on collapse.
    property string eventOwnerOutput: ""
    property string sessionOwnerOutput: ""

    readonly property bool islandEnabled: settingsService ? !!settingsService.dynamicIslandEnabled : true
    readonly property bool dynamicIslandHideTopbarTime: settingsService ? !!settingsService.dynamicIslandHideTopbarTime : true
    readonly property string leftClickAction: settingsService ? String(settingsService.dynamicIslandLeftClickAction || "toggle_media") : "toggle_media"
    readonly property string rightClickAction: settingsService ? String(settingsService.dynamicIslandRightClickAction || "control_center") : "control_center"
    readonly property bool dynamicIslandAutoExpandMedia: settingsService ? !!settingsService.dynamicIslandAutoExpandMedia : false
    readonly property bool dynamicIslandHoverExpand: settingsService ? !!settingsService.dynamicIslandHoverExpand : false
    readonly property bool hasMedia: controlsService ? controlsService.hasMedia : false
    readonly property bool expanded: presentation === "expanded_media" || presentation === "expanded_summary"
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
    // T12: split clock presentation (weekday secondary + 24h time primary).
    // fallbackTimeText remains the single TopBar disabled/legacy plain-text owner.
    readonly property string clockWeekdayText: formatClockWeekday()
    readonly property string clockTimeText: formatClockTime()
    readonly property string fallbackTimeText: timeText()
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
    // Presentation fields for the Overlay. For continuous OSD ramps, bind
    // transient* fields directly so each volume/brightness tick updates
    // bar/value while state remains "transient_osd".
    readonly property string displayText: (root.presentation === "transient_osd"
            || root.presentation === "transient_notification"
            || root.presentation === "transient_workspace")
        ? (root.transientDisplayText.length > 0
            ? root.transientDisplayText
            : fallbackTransientText(root.presentation))
        : displayTextForState(root.presentation)
    readonly property string secondaryText: (root.presentation === "transient_osd"
            || root.presentation === "transient_notification"
            || root.presentation === "transient_workspace")
        ? root.transientSecondaryText
        : secondaryTextForState(root.presentation)
    readonly property real progress: root.presentation === "transient_osd"
        ? Math.max(0, Math.min(1, Number(root.transientProgress) || 0))
        : -1
    readonly property string iconCode: (root.presentation.indexOf("transient_") === 0
            && root.transientIconCode.length > 0)
        ? root.transientIconCode
        : iconCodeForState(root.presentation)
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

    // Named presentation string — never use Item.state (Qt reserved; binding loops).
    // Imperative recompute only: a binding on presentation that reads hasMedia /
    // preferMedia / hoverExpanded re-entered through restore drains and froze OSD.
    property string presentation: "resting_time"

    signal openControlCenterRequested()
    signal openNotificationCenterRequested()

    onPresentationChanged: {
        if (!root.applyingPresentationReducer)
            root.restoreAfterTransient();
    }
    onUserInteractingChanged: {
        if (!root.applyingPresentationReducer)
            root.restoreAfterTransient();
    }
    onForcedStateChanged: root.recomputePresentation()
    onPreferMediaWhenAvailableChanged: root.recomputePresentation()
    onHoverExpandedChanged: root.recomputePresentation()
    onNotificationsServiceChanged: resetNotificationTracking()
    onIslandEnabledChanged: handleIslandEnabledChanged()
    onHasMediaChanged: {
        handleMediaAvailabilityChanged();
        root.recomputePresentation();
    }
    onDynamicIslandAutoExpandMediaChanged: {
        if (root.dynamicIslandAutoExpandMedia)
            handleMediaAvailabilityChanged();
        root.recomputePresentation();
    }

    onControlsServiceChanged: captureOsdBaselines()

    Component.onCompleted: {
        root.recomputePresentation();
        resetNotificationTracking();
        captureOsdBaselines();
        captureWorkspaceBaseline();
    }

    function recomputePresentation() {
        var next = normalizedState(root.forcedState);
        if (String(root.presentation || "") !== String(next || ""))
            root.presentation = String(next || "resting_time");
    }

    function msecsToNextMinute() {
        return Math.max(250, 60000 - (root.now.getSeconds() * 1000 + root.now.getMilliseconds()));
    }

    function presentationSlice() {
        return {
            "forcedState": root.forcedState,
            "preferMediaWhenAvailable": root.preferMediaWhenAvailable,
            "hoverExpanded": root.hoverExpanded
        };
    }

    function presentationContext() {
        return IslandReducer.createContext({
            "islandEnabled": root.islandEnabled,
            "hasMedia": root.hasMedia,
            "autoExpandMedia": root.dynamicIslandAutoExpandMedia,
            "userInteracting": root.userInteracting
        });
    }

    function runReducerEffect(item) {
        if (!item)
            return;

        switch (String(item.type || "")) {
        case "stopTransientTimer":
            transientTimer.stop();
            break;
        case "clearEventOwner":
            root.clearEventOwnerOutput();
            break;
        case "clearTransientFields":
            root.clearTransientFields();
            break;
        case "clearPendingNotifications":
            root.clearPendingNotificationIds();
            break;
        case "clearDisplayingNotification":
            // Abort/reset lease without marking completed (RESET / disable).
            root.displayingNotificationId = -1;
            break;
        case "endNotificationLease":
            // Abort an active notification presentation: mark completed so the
            // same live ID is not re-shown, then drop the lease id.
            if (root.displayingNotificationId >= 0)
                root.markNotificationPresentationCompleted(root.displayingNotificationId);
            root.displayingNotificationId = -1;
            break;
        case "clearPendingOsd":
            root.pendingOsd = null;
            break;
        case "clearUserInteracting":
            root.userInteracting = false;
            break;
        case "clearSwipe":
            swipeSettleTimer.stop();
            root.swipeDragging = false;
            root.swipeSettling = false;
            root.swipeMoved = false;
            root.swipeProgress = 0;
            root.swipeStartProgress = 0;
            root.swipeStartForcedState = "";
            break;
        case "maybeShowPendingNotification":
        case "maybeShowPendingOsd":
        case "restoreAfterTransient":
            // Drain is owned solely by onStateChanged / explicit restore call
            // sites. Reducer drain effect types are accepted but ignored here
            // so a single state commit cannot double-invoke restoreAfterTransient.
            break;
        }
    }

    function applyReducerResult(outcome) {
        if (!outcome || !outcome.state)
            return outcome;

        // Historical show*/collapse paths stopped timers and cleared transient
        // fields BEFORE assigning forcedState. Commit cleanup effects first so
        // onPresentationChanged drain cannot start a transient that later effects
        // immediately kill (stuck transient_notification with no hide timer).
        root.applyingPresentationReducer = true;
        var effects = outcome.effects || [];
        var cleanupTypes = {
            "stopTransientTimer": true,
            "clearEventOwner": true,
            "clearTransientFields": true,
            "clearPendingNotifications": true,
            "clearDisplayingNotification": true,
            "endNotificationLease": true,
            "clearPendingOsd": true,
            "clearUserInteracting": true,
            "clearSwipe": true
        };
        for (var i = 0; i < effects.length; i++) {
            if (effects[i] && cleanupTypes[String(effects[i].type || "")])
                root.runReducerEffect(effects[i]);
        }

        var next = outcome.state;
        root.forcedState = String(next.forcedState || "");
        root.preferMediaWhenAvailable = next.preferMediaWhenAvailable !== false;
        root.hoverExpanded = !!next.hoverExpanded;
        // Imperative recompute while applying so onPresentationChanged does not drain early.
        root.recomputePresentation();

        for (var j = 0; j < effects.length; j++) {
            if (effects[j] && !cleanupTypes[String(effects[j].type || "")])
                root.runReducerEffect(effects[j]);
        }

        root.applyingPresentationReducer = false;
        // Exactly one drain after reducer apply (covers forcedState no-op too).
        root.restoreAfterTransient();

        return outcome;
    }

    function dispatchPresentation(kind, payload) {
        return root.applyReducerResult(IslandReducer.reduce(
            root.presentationSlice(),
            IslandReducer.createEvent(kind, payload),
            root.presentationContext()
        ));
    }

    function isValidState(nextState) {
        return IslandReducer.isValidState(nextState);
    }

    function restingState() {
        return IslandReducer.restingState(root.presentationSlice(), root.presentationContext());
    }

    function normalizedState(nextState) {
        // state binding: normalizedState(root.forcedState) — candidate is the
        // forced override, not the whole presentation slice.
        return IslandReducer.presentationState({
            "forcedState": nextState,
            "preferMediaWhenAvailable": root.preferMediaWhenAvailable,
            "hoverExpanded": root.hoverExpanded
        }, root.presentationContext());
    }

    function formatClockWeekday() {
        // Locale-aware short weekday (e.g. 周二 / Tue). Single now owner.
        return Qt.formatDateTime(root.now, "ddd");
    }

    function formatClockTime() {
        // Always 24-hour HH:mm for the island primary time.
        return Qt.formatDateTime(root.now, "HH:mm");
    }

    function timeText() {
        // Combined plain-text clock for TopBar fallback and IPC displayText.
        var weekday = formatClockWeekday();
        var time = formatClockTime();
        if (weekday.length > 0 && time.length > 0)
            return weekday + " " + time;
        return time.length > 0 ? time : weekday;
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
            // V2 clock uses clockWeekdayText + clockTimeText only. Do not expose
            // yyyy-MM-dd here — it flashed as "sinking" English/digit noise during
            // collapse morphs when secondary briefly became visible.
            return "";
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

    function liveFocusedOutputName() {
        if (root.windowsService && root.windowsService.focusedOutputName) {
            var named = String(root.windowsService.focusedOutputName || "").trim();
            if (named.length > 0)
                return named;
        }
        var focused = root.windowsService ? root.windowsService.focusedWindow : null;
        var output = focused ? String(focused.output || "").trim() : "";
        if (output.length > 0)
            return output;

        var workspace = root.windowsService ? root.windowsService.activeWorkspace : null;
        output = workspace ? String(workspace.output || "").trim() : "";
        if (output.length > 0)
            return output;
        return "";
    }

    function firstAvailableOutputName() {
        var screens = [...Quickshell.screens];
        for (var i = 0; i < screens.length; i++) {
            var name = String(screens[i].name || "").trim();
            if (name.length > 0)
                return name;
        }
        return "";
    }

    function availableOutputNames() {
        var screens = [...Quickshell.screens];
        var names = [];
        for (var i = 0; i < screens.length; i++) {
            var name = String(screens[i].name || "").trim();
            if (name.length > 0)
                names.push(name);
        }
        return names;
    }

    function captureEventOwnerOutput(preferred) {
        // Only pin when starting a new event lease. In-lease refreshes
        // (rapid OSD steps) must not re-capture focus and jump screens.
        var existing = String(root.eventOwnerOutput || "").trim();
        if (existing.length > 0)
            return existing;

        var preferredName = String(preferred || "").trim();
        if (preferredName.length > 0) {
            root.eventOwnerOutput = preferredName;
            return preferredName;
        }
        var live = root.liveFocusedOutputName();
        if (live.length > 0) {
            root.eventOwnerOutput = live;
            return live;
        }
        var first = root.firstAvailableOutputName();
        root.eventOwnerOutput = first;
        return first;
    }

    function clearEventOwnerOutput() {
        root.eventOwnerOutput = "";
    }

    function setSessionOwnerOutput(screenName) {
        var name = String(screenName || "").trim();
        if (name.length === 0)
            name = root.liveFocusedOutputName() || root.firstAvailableOutputName();
        root.sessionOwnerOutput = name;
        return name;
    }

    function clearSessionOwnerOutput() {
        root.sessionOwnerOutput = "";
    }

    function sanitizeOwnerOutputs() {
        var next = IslandOwnership.sanitizeOwnerPins({
            "eventOwnerOutput": root.eventOwnerOutput,
            "sessionOwnerOutput": root.sessionOwnerOutput
        }, root.availableOutputNames());
        root.eventOwnerOutput = String(next.eventOwnerOutput || "");
        root.sessionOwnerOutput = String(next.sessionOwnerOutput || "");
    }

    function computeTargetScreenName() {
        // Honor pinned event/session owners for the lifetime of the activity.
        root.sanitizeOwnerOutputs();
        return IslandOwnership.resolvePresentationOwner({
            "eventOwnerOutput": root.eventOwnerOutput,
            "sessionOwnerOutput": root.sessionOwnerOutput
        }, {
            "focusedOutput": root.liveFocusedOutputName(),
            "firstOutput": root.firstAvailableOutputName()
        });
    }

    function claimSessionOwnerForScreen(screenName) {
        // User click / hover expand on a specific output locks session owner.
        root.setSessionOwnerOutput(screenName);
    }


    function clearTransientFields() {
        root.transientDisplayText = "";
        root.transientSecondaryText = "";
        root.transientProgress = -1;
        root.transientIconCode = "";
        root.transientOsdMuted = false;
        root.transientNotificationAppName = "";
        root.transientNotificationIconUrl = "";
        root.transientNotificationUrgency = "normal";
        root.transientNotificationHasOverflow = false;
        root.transientNotificationExpanded = false;
        root.transientNotificationActions = [];
    }

    function handleIslandEnabledChanged() {
        if (root.islandEnabled) {
            // Re-enable must seed lastVolume/lastMuted from the live controls
            // snapshot so disable-period steps do not present as fresh changes.
            captureOsdBaselines();
            handleMediaAvailabilityChanged();
            root.restoreAfterTransient();
            return;
        }

        // While disabled, keep baselines aligned with controls without showing.
        // Notification identity contract requires clearPendingNotificationIds to
        // remain source-visible on this path; reducer effects are idempotent.
        captureOsdBaselines();
        root.clearPendingNotificationIds();
        root.clearEventOwnerOutput();
        root.clearSessionOwnerOutput();
        root.dispatchPresentation("ISLAND_DISABLED");
    }

    function handleMediaAvailabilityChanged() {
        var wasExpanded = root.expanded;
        root.dispatchPresentation("MEDIA_AVAILABILITY_CHANGED");
        // Auto-expand claims session so expanded media does not follow focus.
        if (!wasExpanded && root.expanded && !root.sessionOwnerOutput.length)
            root.claimSessionOwnerForScreen(root.liveFocusedOutputName());
        if (wasExpanded && !root.expanded)
            root.clearSessionOwnerOutput();
    }

    function reset() {
        root.dispatchPresentation("RESET");
        root.clearEventOwnerOutput();
        root.clearSessionOwnerOutput();
    }

    function showTime() {
        root.dispatchPresentation("SHOW_TIME");
    }

    function showMedia() {
        root.dispatchPresentation("SHOW_MEDIA");
    }

    function showExpandedMedia() {
        if (!root.sessionOwnerOutput.length)
            root.claimSessionOwnerForScreen(root.liveFocusedOutputName());
        root.dispatchPresentation("SHOW_EXPANDED_MEDIA");
    }

    function showExpandedSummary() {
        if (!root.sessionOwnerOutput.length)
            root.claimSessionOwnerForScreen(root.liveFocusedOutputName());
        root.dispatchPresentation("SHOW_EXPANDED_SUMMARY");
    }

    function toggleExpanded() {
        // Expanding claims session; collapsing releases session owner.
        var wasExpanded = root.expanded;
        if (!wasExpanded && !root.sessionOwnerOutput.length)
            root.claimSessionOwnerForScreen(root.liveFocusedOutputName());
        root.dispatchPresentation("TOGGLE_EXPANDED");
        if (wasExpanded)
            root.clearSessionOwnerOutput();
    }

    function showTransient(nextState, text, secondary, progressValue, icon, hideMs, osdMuted) {
        if (!root.islandEnabled)
            return;

        var candidate = String(nextState || "");
        if (candidate !== "transient_osd"
                && candidate !== "transient_notification"
                && candidate !== "transient_workspace")
            return;

        // Capture owner at event create so focus changes cannot jump the island.
        root.captureEventOwnerOutput();
        root.transientDisplayText = String(text || "");
        root.transientSecondaryText = String(secondary || "");
        root.transientProgress = Number(progressValue);
        root.transientIconCode = String(icon || "");
        root.transientOsdMuted = candidate === "transient_osd" ? !!osdMuted : false;
        root.forcedState = candidate;
        root.recomputePresentation();
        transientTimer.interval = Math.max(250, Math.round(Number(hideMs) || root.smokeTransientHideMs));
        transientTimer.restart();
    }

   function showTransientOsd(text, progressValue) {
        showTransientOsdWithIcon(text, progressValue, "\ue050");
    }

    function showTransientOsdWithIcon(text, progressValue, icon, valueText, osdMuted) {
        // Clamp progress; treat NaN as 0 so brightness 0 and invalid map cleanly.
        var sample = Number(progressValue);
        if (!isFinite(sample))
            sample = 0;
        var progress = Math.max(0, Math.min(1, sample));
        var muted = !!osdMuted;
        if (muted)
            progress = 0;
        // Optional explicit value label (e.g. "静音"); default is "N%".
        var secondary = (valueText !== undefined && valueText !== null && String(valueText).length > 0)
            ? String(valueText)
            : (muted ? "静音" : (Math.round(progress * 100) + "%"));
        showTransient("transient_osd", text, secondary, progress,
            String(icon || "\ue050"), root.osdHideMs, muted);
   }

   function showTransientNotification(summary, body, appName) {
        // Manual/smoke IPC: no live Notifications owner. Queue as a manual-only
        // payload (not a live ID queue). Live order remains on Notifications.qml.
        if (!root.islandEnabled || notificationsDndEnabled())
            return;
        var entry = {
            "kind": "manual",
            "summary": sanitizeNotificationText(summary, ""),
            "body": sanitizeNotificationText(body, ""),
            "appName": sanitizeNotificationText(appName, "")
        };
        if (blocksTransientNotification()) {
            enqueuePendingNotificationEntry(entry);
            return;
        }
        presentNotificationEntry({
            "id": -1,
            "summary": entry.summary,
            "body": entry.body,
            "appName": entry.appName
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
        return IslandReducer.blocksWorkspace(root.presentation, root.arbitrationFlags());
    }

    function arbitrationFlags() {
        return {
            "expanded": root.expanded,
            "userInteracting": root.userInteracting,
            "displayingNotification": Number(root.displayingNotificationId) >= 0
                || root.presentation === "transient_notification"
        };
    }

    function handleWorkspaceChange() {
        if (!root.islandEnabled)
            return;

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
        // T11: same mid-band geometry as Overlay.widthForState.
        switch (currentState) {
        case "resting_media":
            return Math.round(
                (IslandMotion.v2CompactMediaWidthMin + IslandMotion.v2CompactMediaWidthMax) / 2);
        case "expanded_media":
            return Math.round(
                (IslandMotion.v2MediaExpandedWidthMin + IslandMotion.v2MediaExpandedWidthMax) / 2);
        case "expanded_summary":
            return 360;
        case "transient_notification":
            return Math.round(
                (IslandMotion.v2NotificationCompactWidthMin + IslandMotion.v2NotificationCompactWidthMax) / 2);
        case "transient_osd":
            return Math.round((IslandMotion.v2OsdWidthMin + IslandMotion.v2OsdWidthMax) / 2);
        case "transient_workspace":
            return Math.round(
                (IslandMotion.v2WorkspaceWidthMin + IslandMotion.v2WorkspaceWidthMax) / 2);
        case "resting_time":
        default:
            return Math.round((IslandMotion.v2ClockWidthMin + IslandMotion.v2ClockWidthMax) / 2);
        }
    }

    function swipeSideWidthForProgress(progressValue) {
        return progressValue >= 0 ? root.swipeRightWidth : root.swipeLeftWidth;
    }

    function canSwipe() {
        if (!root.islandEnabled)
            return false;

        var s = root.presentation;
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
        // Record start presentation for cancel restore (T09).
        root.swipeStartForcedState = root.forcedState;
        if (root.presentation === "expanded_media")
            root.swipeStartProgress = 1;
        else if (root.presentation === "expanded_summary")
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

    function resolveSwipe(screenName) {
        if (!root.swipeDragging)
            return;

        root.swipeDragging = false;
        root.setUserInteracting(false);
        // One-shot settle: target progress + state computed together (T09).
        // Do NOT zero swipeProgress while settling — preview width must hold target.
        var decision = IslandOwnership.resolveSwipeSettle(
            root.swipeProgress,
            root.swipeStartProgress,
            root.hasMedia,
            IslandMotion.swipeEnterThreshold,
            IslandMotion.swipeReturnThreshold
        );
        root.swipeSettling = true;
        root.swipeProgress = Number(decision.swipeProgress) || 0;
        if (decision.forcedState !== null && decision.forcedState !== undefined)
            root.forcedState = String(decision.forcedState);
        var entered = !!decision.entered;

        swipeSettleTimer.restart();
        root.swipeMoved = false;
        if (entered) {
            if (!root.sessionOwnerOutput.length)
                root.claimSessionOwnerForScreen(screenName || root.liveFocusedOutputName());
            root.restoreAfterTransient();
        } else if (!root.expanded) {
            // Swipe return-to-compact releases session owner (T08 collapse rule).
            root.clearSessionOwnerOutput();
        }
    }

    function cancelSwipe() {
        if (!root.swipeDragging)
            return;

        root.swipeDragging = false;
        root.swipeSettling = true;
        // Restore start presentation and progress for continuous geometry.
        root.swipeProgress = root.swipeStartProgress;
        root.forcedState = root.swipeStartForcedState;
        root.setUserInteracting(false);
        swipeSettleTimer.restart();
    }

    function consumeSwipeMoved() {
        var moved = root.swipeMoved;
        root.swipeMoved = false;
        return moved;
    }


    function requestHoverExpand(screenName) {
        if (!root.islandEnabled || !root.dynamicIslandHoverExpand || root.expanded || root.userInteracting)
            return;

        root.claimSessionOwnerForScreen(screenName);
        root.dispatchPresentation("HOVER_EXPAND");
    }

    function requestHoverCollapse() {
        // Historical: only acts when hoverExpanded; drains pending on collapse.
        root.dispatchPresentation("HOVER_COLLAPSE");
        if (!root.expanded)
            root.clearSessionOwnerOutput();
    }

    function performClickAction(action) {
        if (!root.islandEnabled)
            return;

        root.dispatchPresentation("CLEAR_HOVER_EXPANDED");
        switch (String(action || "toggle_media")) {
        case "summary":
            if (root.presentation === "expanded_summary") {
                root.dispatchPresentation("COLLAPSE");
                root.clearSessionOwnerOutput();
            } else {
                showExpandedSummary();
            }
            break;
        case "notifications":
            root.dispatchPresentation("COLLAPSE");
            root.clearSessionOwnerOutput();
            root.openNotificationCenterRequested();
            break;
        case "control_center":
            root.dispatchPresentation("COLLAPSE");
            root.clearSessionOwnerOutput();
            root.openControlCenterRequested();
            break;
        case "none":
            break;
        case "toggle_media":
        default:
            toggleExpanded();
            break;
        }
    }

    function handleChipClick(button, screenName) {
        // Optional screenName pins the session owner for multi-output clicks.
        if (screenName !== undefined && screenName !== null && String(screenName).length > 0)
            root.claimSessionOwnerForScreen(screenName);
        if (button === Qt.LeftButton)
            performClickAction(root.leftClickAction);
        else if (button === Qt.RightButton)
            performClickAction(root.rightClickAction);
    }

    function setUserInteracting(active) {
        if (!root.islandEnabled) {
            root.userInteracting = false;
            return;
        }

        root.userInteracting = !!active;
        if (!root.userInteracting)
            root.restoreAfterTransient();
    }

    function resetNotificationTracking() {
        // Seed seen + completed from current activeModel so history is not re-presented.
        var seen = {};
        var completed = {};
        var list = root.notificationsService ? root.notificationsService.activeModel : [];
        if (list) {
            for (var i = 0; i < list.length; i++) {
                var id = notificationId(list[i]);
                if (id >= 0) {
                    seen[String(id)] = true;
                    completed[String(id)] = true;
                }
            }
        }
        root.seenNotificationIds = seen;
        root.completedNotificationIds = completed;
        root.clearPendingNotificationIds();
        root.displayingNotificationId = -1;
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

    function clearPendingNotificationIds() {
        root.pendingNotificationIds = [];
    }

    function pendingNotificationIdKey(id) {
        return String(Number(id));
    }

    function normalizePendingEntry(entry) {
        // Accept legacy bare IDs (pre-tagged FIFO) and tagged live/manual entries.
        if (entry === undefined || entry === null)
            return null;
        if (typeof entry === "number" || typeof entry === "string") {
            var bare = Number(entry);
            if (!isFinite(bare) || bare < 0)
                return null;
            return { "kind": "live", "id": bare };
        }
        var kind = String(entry.kind || "");
        if (kind === "live") {
            var lid = Number(entry.id);
            if (!isFinite(lid) || lid < 0)
                return null;
            return { "kind": "live", "id": lid };
        }
        if (kind === "manual") {
            return {
                "kind": "manual",
                "summary": sanitizeNotificationText(entry.summary, ""),
                "body": sanitizeNotificationText(entry.body, ""),
                "appName": sanitizeNotificationText(entry.appName, "")
            };
        }
        return null;
    }

    function isPendingNotificationId(id) {
        var nid = Number(id);
        if (!isFinite(nid) || nid < 0)
            return false;
        var key = pendingNotificationIdKey(nid);
        var queue = root.pendingNotificationIds || [];
        for (var i = 0; i < queue.length; i++) {
            var item = normalizePendingEntry(queue[i]);
            if (item && item.kind === "live" && pendingNotificationIdKey(item.id) === key)
                return true;
        }
        return false;
    }

    function enqueuePendingNotificationId(id) {
        // T07: live IDs are not island-queued. Notifications.qml owns FIFO order;
        // island resolves the next presentable live notification on restore.
        // Keep this helper as a no-op so older call sites cannot rebuild a queue.
        void id;
    }

    function enqueuePendingNotificationEntry(entry) {
        var item = normalizePendingEntry(entry);
        if (!item)
            return;
        // Live IDs must not enter the island pending queue (T07).
        if (item.kind === "live")
            return;
        if (item.kind !== "manual")
            return;
        root.pendingNotificationIds = (root.pendingNotificationIds || []).concat([item]);
    }

    function removePendingNotificationId(id) {
        var key = pendingNotificationIdKey(id);
        var queue = root.pendingNotificationIds || [];
        var next = [];
        for (var i = 0; i < queue.length; i++) {
            var item = normalizePendingEntry(queue[i]);
            if (!item) {
                continue;
            }
            if (item.kind === "live" && pendingNotificationIdKey(item.id) === key)
                continue;
            next.push(item);
        }
        if (next.length !== queue.length)
            root.pendingNotificationIds = next;
    }

    function findLiveNotificationById(id) {
        if (root.notificationsService && root.notificationsService.findActiveById)
            return root.notificationsService.findActiveById(id);
        var nid = Number(id);
        if (!isFinite(nid) || nid < 0)
            return null;
        var list = root.notificationsService ? root.notificationsService.activeModel : [];
        if (!list)
            return null;
        for (var i = 0; i < list.length; i++) {
            if (notificationId(list[i]) === nid)
                return list[i];
        }
        return null;
    }

    function markNotificationPresentationCompleted(id) {
        var nid = Number(id);
        if (!isFinite(nid) || nid < 0)
            return;
        var next = Object.assign({}, root.completedNotificationIds || {});
        next[String(nid)] = true;
        root.completedNotificationIds = next;
    }

    function clearNotificationPresentationCompleted(id) {
        var nid = Number(id);
        if (!isFinite(nid) || nid < 0)
            return;
        var completed = root.completedNotificationIds || {};
        var key = String(nid);
        if (!completed[key])
            return;
        var next = Object.assign({}, completed);
        delete next[key];
        root.completedNotificationIds = next;
    }

    function nextPresentableLiveNotification() {
        // Walk Notifications-owned FIFO; skip active lease and completed presentations.
        var list = root.notificationsService ? root.notificationsService.activeModel : [];
        if (!list)
            return null;
        var completed = root.completedNotificationIds || {};
        var displaying = Number(root.displayingNotificationId);
        for (var i = 0; i < list.length; i++) {
            var nid = notificationId(list[i]);
            if (nid < 0)
                continue;
            if (nid === displaying)
                continue;
            if (completed[String(nid)])
                continue;
            return list[i];
        }
        return null;
    }

    function handleNotificationsChanged() {
        var list = root.notificationsService ? root.notificationsService.activeModel : [];
        if (!list)
            list = [];

        var nextSeen = {};
        for (var i = 0; i < list.length; i++) {
            var id = notificationId(list[i]);
            if (id < 0)
                continue;
            nextSeen[String(id)] = true;
        }

        // Drop completed markers for IDs that left the Notifications model.
        var completed = root.completedNotificationIds || {};
        var nextCompleted = {};
        for (var ck in completed) {
            if (completed.hasOwnProperty(ck) && nextSeen[ck])
                nextCompleted[ck] = true;
        }
        root.completedNotificationIds = nextCompleted;

        // Manual IPC queue only — strip any legacy live entries.
        var queue = root.pendingNotificationIds || [];
        var kept = [];
        for (var q = 0; q < queue.length; q++) {
            var item = normalizePendingEntry(queue[q]);
            if (item && item.kind === "manual")
                kept.push(item);
        }
        if (kept.length !== queue.length)
            root.pendingNotificationIds = kept;

        // If the currently displayed notification left the model, end the lease
        // (including expanded UI) so the island does not stick open.
        if (root.displayingNotificationId >= 0
                && !nextSeen[String(root.displayingNotificationId)]) {
            root.displayingNotificationId = -1;
            if (root.presentation === "transient_notification") {
                root.transientNotificationExpanded = false;
                root.setUserInteracting(false);
                transientTimer.stop();
                root.forcedState = "";
                clearTransientFields();
                root.clearEventOwnerOutput();
            }
        }

        root.seenNotificationIds = nextSeen;

        if (notificationsDndEnabled() || !root.islandEnabled) {
            root.clearPendingNotificationIds();
            return;
        }

        // Live FIFO is owned by Notifications.qml; resolve head/order on restore.
        root.restoreAfterTransient();
    }

    function handleNotificationUpdated(id) {
        // replace-id path: live object property change, no activeModel rewrite.
        var nid = Number(id);
        if (!isFinite(nid) || nid < 0)
            return;
        if (notificationsDndEnabled() || !root.islandEnabled)
            return;

        // Currently displaying this id → refresh text in place, no re-entry animation/timer.
        if (Number(root.displayingNotificationId) === nid
                && root.presentation === "transient_notification") {
            var live = findLiveNotificationById(nid);
            if (!live)
                return;
            applyNotificationEntryText(notificationEntry(live));
            return;
        }

        // Not the active lease → do not re-popup; live content stays on Notifications model.
        // Completed or waiting IDs re-resolve from Notifications FIFO on restore.
    }

    function notificationEntry(notification) {
        if (!notification)
            return null;

        var appName = sanitizeNotificationText(notification.appName, "");
        var summary = sanitizeNotificationText(notification.summary, "");
        var body = sanitizeNotificationText(notification.body, "");

        if (summary.length === 0)
            summary = appName.length > 0 ? appName : "通知";

        var urgency = "normal";
        try {
            if (Number(notification.urgency) === 2)
                urgency = "critical";
        } catch (e) {}

        var iconUrl = "";
        if (root.notificationsService && root.notificationsService.iconUrlFor)
            iconUrl = String(root.notificationsService.iconUrlFor(notification) || "");

        return {
            "id": notificationId(notification),
            "summary": summary,
            "body": body,
            "appName": appName,
            "iconUrl": iconUrl,
            "urgency": urgency,
            "actions": extractNotificationActions(notification)
        };
    }

    function notificationHasOverflow(summary, body, appName, actionCount) {
        // Long content or available actions drive wider compact geometry / chevron.
        var s = String(summary || "");
        var b = String(body || "");
        var a = String(appName || "");
        var actions = Number(actionCount) || 0;
        return s.length > 28 || b.length > 36 || (a.length + s.length + b.length) > 64 || actions > 0;
    }

    function extractNotificationActions(notification) {
        // Up to 3 non-default actions. Default is body-click only (T14 freeze).
        var out = [];
        if (!notification)
            return out;
        try {
            var actions = notification.actions;
            if (!actions)
                return out;
            for (var i = 0; i < actions.length && out.length < 3; i++) {
                var act = actions[i];
                if (!act)
                    continue;
                var id = String(act.identifier !== undefined ? act.identifier : (act.id || "")).trim();
                if (id.length === 0)
                    continue;
                var lower = id.toLowerCase();
                if (lower === "default" || lower === "default_action")
                    continue;
                var label = String(act.text !== undefined ? act.text : (act.label || id)).trim();
                if (label.length === 0)
                    label = id;
                // Skip Chinese/English "Open" labels that only mirror default.
                var labelLower = label.toLowerCase();
                if (labelLower === "open" || label === "打开")
                    continue;
                out.push({ "id": id, "label": label });
            }
        } catch (e) {}
        return out;
    }

    function applyNotificationPresentation(entry, restartTimer) {
        // Shared mapping for present + replace-id refresh.
        // restartTimer=false keeps the active lease timer (in-place replace).
        if (!entry)
            return;

        var title = sanitizeNotificationText(entry.summary, "通知");
        var detail = sanitizeNotificationText(entry.body, "");
        var appName = sanitizeNotificationText(entry.appName, "");
        var iconUrl = String(entry.iconUrl || "");
        var urgency = String(entry.urgency || "normal");
        var actions = entry.actions && entry.actions.length ? entry.actions : [];
        var overflow = notificationHasOverflow(title, detail, appName, actions.length);

        root.transientDisplayText = title;
        root.transientSecondaryText = detail;
        root.transientProgress = -1;
        root.transientIconCode = "";
        root.transientNotificationAppName = appName;
        root.transientNotificationIconUrl = iconUrl;
        root.transientNotificationUrgency = urgency === "critical" ? "critical" : "normal";
        root.transientNotificationHasOverflow = overflow;
        root.transientNotificationActions = actions;
        if (restartTimer)
            root.transientNotificationExpanded = false;

        if (restartTimer) {
            root.captureEventOwnerOutput();
            root.forcedState = "transient_notification";
            if (!root.userInteracting) {
                transientTimer.interval = Math.max(250, root.notificationHideMs);
                transientTimer.restart();
            }
        }
    }

    function applyNotificationEntryText(entry) {
        // In-place text update for replace-id while the same id is displayed.
        // Does not restart transientTimer or reassign forcedState.
        if (!entry)
            return;
        var title = sanitizeNotificationText(entry.summary, "通知");
        var detail = sanitizeNotificationText(entry.body, "");
        var appName = sanitizeNotificationText(entry.appName, "");
        var iconUrl = String(entry.iconUrl || "");
        var urgency = String(entry.urgency || "normal");
        var actions = entry.actions && entry.actions.length
            ? entry.actions
            : (root.transientNotificationActions || []);
        var overflow = notificationHasOverflow(title, detail, appName, actions.length);
        root.transientDisplayText = title;
        root.transientSecondaryText = detail;
        root.transientProgress = -1;
        root.transientIconCode = "";
        root.transientNotificationAppName = appName;
        root.transientNotificationIconUrl = iconUrl;
        root.transientNotificationUrgency = urgency === "critical" ? "critical" : "normal";
        root.transientNotificationHasOverflow = overflow;
        root.transientNotificationActions = actions;
        // Keep expanded flag; if overflow disappears, collapse.
        if (!overflow)
            root.transientNotificationExpanded = false;
    }

    // T14 freeze: body click invokes default action via Notifications API.
    // T15 must not rewrite this body-click → default-action contract.
    function invokeNotificationDefaultAction() {
        var nid = Number(root.displayingNotificationId);
        if (!isFinite(nid) || nid < 0)
            return;
        if (!root.notificationsService || !root.notificationsService.invokeAction)
            return;
        // Single invoke: FreeDesktop default action id is "default".
        root.notificationsService.invokeAction(nid, "default");
    }

    function toggleNotificationExpanded() {
        if (root.presentation !== "transient_notification")
            return;
        if (!root.transientNotificationHasOverflow)
            return;
        root.transientNotificationExpanded = !root.transientNotificationExpanded;
        // Expanded interaction pauses auto-collapse (T15).
        if (root.transientNotificationExpanded) {
            root.setUserInteracting(true);
            transientTimer.stop();
        } else {
            root.setUserInteracting(false);
            if (root.presentation === "transient_notification") {
                transientTimer.interval = Math.max(250, root.notificationHideMs);
                transientTimer.restart();
            }
        }
    }

    function invokeNotificationAction(actionId) {
        var nid = Number(root.displayingNotificationId);
        var id = String(actionId || "").trim();
        if (!isFinite(nid) || nid < 0 || id.length === 0)
            return;
        if (!root.notificationsService || !root.notificationsService.invokeAction)
            return;
        // Only end lease when the action is one we presented (identity match).
        var known = false;
        var list = root.transientNotificationActions || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i] && String(list[i].id) === id) {
                known = true;
                break;
            }
        }
        if (!known)
            return;
        root.notificationsService.invokeAction(nid, id);
        // After a presented action, end the lease (server/dismiss semantics own the object).
        root.markNotificationPresentationCompleted(nid);
        root.displayingNotificationId = -1;
        root.transientNotificationExpanded = false;
        root.setUserInteracting(false);
        transientTimer.stop();
        root.forcedState = "";
        clearTransientFields();
        root.clearEventOwnerOutput();
        root.restoreAfterTransient();
    }

    function dismissDisplayedNotification() {
        var nid = Number(root.displayingNotificationId);
        if (isFinite(nid) && nid >= 0) {
            if (root.notificationsService && root.notificationsService.dismissId)
                root.notificationsService.dismissId(nid, "dismiss");
            root.markNotificationPresentationCompleted(nid);
        }
        // Also ends manual (id=-1) presentation leases cleanly.
        root.displayingNotificationId = -1;
        root.transientNotificationExpanded = false;
        root.setUserInteracting(false);
        transientTimer.stop();
        root.forcedState = "";
        clearTransientFields();
        root.clearEventOwnerOutput();
        root.restoreAfterTransient();
    }

    function notificationsDndEnabled() {
        return !!(root.notificationsService && root.notificationsService.dndEnabled);
    }

   function blocksTransientNotification() {
       return IslandReducer.blocksNotification(root.presentation, root.arbitrationFlags());
   }

    function blocksTransientOsd() {
        // Yield to an active notification lease (T07 priority).
        return IslandReducer.blocksOsd(root.presentation, root.arbitrationFlags());
    }

    // Single restore/drain entry after any presentation change (T07).
    // Priority: notification lease first, then coalesced OSD. Workspace is
    // latest-only and never queued as a pending presenter.
    function restoreAfterTransient() {
        if (!root.islandEnabled)
            return;
        root.maybeShowPendingNotification();
        root.maybeShowPendingOsd();
    }

    function captureOsdBaselines() {
        if (!root.controlsService)
            return;
        root.lastVolume = Number(root.controlsService.volume) || 0;
        root.lastMuted = !!root.controlsService.muted;
        // audioReady is optional; only explicit false means sink not live.
        root.volumeOsdTrackingReady = root.controlsService.audioReady !== false;
        // Brightness 0 is legal. Only non-finite samples are ignored; never
        // rewrite a real 0% reading into a synthetic 1.0 baseline.
        var brightnessSample = Number(root.controlsService.brightness);
        if (isFinite(brightnessSample))
            root.lastBrightness = Math.max(0, Math.min(1, brightnessSample));
        root.brightnessTrackingReady = !!root.controlsService.brightnessAvailable;
    }

   function presentOsdEntry(entry) {
       if (!root.islandEnabled) {
           root.pendingOsd = null;
           return;
       }

       if (!entry || blocksTransientOsd()) {
           if (entry)
               root.pendingOsd = entry;
           return;
       }
       root.pendingOsd = null;
       // T13 presentation: primary label is kind; secondary is exact value text;
       // progress is 0–1 for the horizontal bar (muted forces 0).
       var icon = String(entry.icon || "\ue050");
       if (entry.kind === "volume") {
           var muted = !!entry.muted;
           var volumeProgress = muted ? 0 : Math.max(0, Math.min(1, Number(entry.progress)));
           if (!isFinite(volumeProgress))
               volumeProgress = 0;
           var volumeValue = muted ? "静音" : (Math.round(volumeProgress * 100) + "%");
           showTransientOsdWithIcon(muted ? "静音" : "音量", volumeProgress,
               muted ? "\ue04f" : "\ue050", volumeValue, muted);
       } else {
           var brightnessProgress = Math.max(0, Math.min(1, Number(entry.progress)));
           if (!isFinite(brightnessProgress))
               brightnessProgress = 0;
           showTransientOsdWithIcon("亮度", brightnessProgress, "\ue518",
               Math.round(brightnessProgress * 100) + "%", false);
       }
   }

    function maybeShowPendingOsd() {
        if (!root.islandEnabled) {
            root.pendingOsd = null;
            return;
        }

        if (!root.pendingOsd || blocksTransientOsd())
            return;
        var entry = root.pendingOsd;
        root.pendingOsd = null;
        presentOsdEntry(entry);
    }

    // Single volume/mute OSD path: lastVolume/lastMuted are the only baseline.
    // Backend may emit volumeChanged and mutedChanged for one user action;
    // Qt.callLater coalesces both into one semantic snapshot before present.
    // Exact equality only — no rough epsilon that would swallow small steps.
    // Disabled / audio-not-ready / first post-reconnect sample still advance
    // the baseline so re-enable and sink reconnect never treat the first live
    // sample as a user change.
    function syncVolumeOsdFromControls() {
        if (!root.controlsService)
            return;

        var volume = Number(root.controlsService.volume) || 0;
        var muted = !!root.controlsService.muted;
        var audioReady = root.controlsService.audioReady !== false;

        if (!audioReady) {
            root.lastVolume = volume;
            root.lastMuted = muted;
            root.volumeOsdTrackingReady = false;
            return;
        }

        if (!root.volumeOsdTrackingReady) {
            // First live sample after sink reconnect: baseline only.
            root.lastVolume = volume;
            root.lastMuted = muted;
            root.volumeOsdTrackingReady = true;
            return;
        }

        if (volume === root.lastVolume && muted === root.lastMuted)
            return;

        root.lastVolume = volume;
        root.lastMuted = muted;

        if (!root.islandEnabled)
            return;

        presentOsdEntry({
            "kind": "volume",
            "progress": muted ? 0 : volume,
            "muted": muted,
            "icon": muted ? "\ue04f" : "\ue050"
        });
    }

    function handleVolumeChange() {
        // Sync immediately for sticky ramps. Mute+volume same event still
        // coalesce via lastVolume/lastMuted equality in syncVolumeOsdFromControls.
        root.syncVolumeOsdFromControls();
    }

    function handleMuteChange() {
        root.syncVolumeOsdFromControls();
    }

    function handleAudioReadyChange() {
        // Drop tracking while sink is gone; first post-ready volume/mute
        // sample reseeds via syncVolumeOsdFromControls without presenting.
        // Do not sync immediately on ready=true: Controls still reports the
        // unbound 0 placeholder until the volume binding refreshes.
        if (!root.controlsService || root.controlsService.audioReady === false) {
            root.volumeOsdTrackingReady = false;
            captureOsdBaselines();
            return;
        }
        root.volumeOsdTrackingReady = false;
    }

    // Brightness OSD path mirrors volume: unavailable / first sample only
    // advance the baseline. Finite 0% is a real user value and may present.
    // NaN is unavailable and must not be treated as 0. Disabled island still
    // tracks the baseline so re-enable does not false-present.
    function handleBrightnessChange() {
        if (!root.controlsService)
            return;

        var brightnessSample = Number(root.controlsService.brightness);
        if (!isFinite(brightnessSample))
            return;
        var brightness = Math.max(0, Math.min(1, brightnessSample));

        if (!root.controlsService.brightnessAvailable) {
            root.lastBrightness = brightness;
            root.brightnessTrackingReady = false;
            return;
        }
        if (!root.brightnessTrackingReady) {
            // First valid sample after connect/reconnect: baseline only.
            root.lastBrightness = brightness;
            root.brightnessTrackingReady = true;
            return;
        }
        if (Math.abs(brightness - root.lastBrightness) < 0.005)
            return;
        root.lastBrightness = brightness;

        if (!root.islandEnabled)
            return;

        presentOsdEntry({
            "kind": "brightness",
            "progress": brightness,
            "icon": "\ue518"
        });
    }

    function maybeShowPendingNotification() {
        if (!root.islandEnabled) {
            root.clearPendingNotificationIds();
            return;
        }

        if (notificationsDndEnabled()) {
            root.clearPendingNotificationIds();
            return;
        }

        if (blocksTransientNotification())
            return;

        // Manual IPC payloads first (smoke / debug), then Notifications FIFO order.
        while ((root.pendingNotificationIds || []).length > 0) {
            if (blocksTransientNotification())
                return;

            var queue = root.pendingNotificationIds || [];
            var next = normalizePendingEntry(queue[0]);
            root.pendingNotificationIds = queue.slice(1);

            if (!next || next.kind !== "manual")
                continue;

            presentNotificationEntry({
                "id": -1,
                "summary": next.summary,
                "body": next.body,
                "appName": next.appName
            });
            return;
        }

        var live = root.nextPresentableLiveNotification();
        if (!live)
            return;
        presentNotificationEntry(notificationEntry(live));
    }

    function presentNotificationEntry(entry) {
        if (!entry || notificationsDndEnabled())
            return;

        var nid = Number(entry.id);
        root.displayingNotificationId = (isFinite(nid) && nid >= 0) ? nid : -1;
        // Presenting a live id means it is no longer "completed" for FIFO walk.
        if (isFinite(nid) && nid >= 0)
            root.clearNotificationPresentationCompleted(nid);
        // Manual IPC entries may omit icon/urgency; keep empty URL + normal.
        if (!entry.iconUrl && entry.id !== undefined && Number(entry.id) >= 0) {
            var live = findLiveNotificationById(Number(entry.id));
            if (live) {
                var enriched = notificationEntry(live);
                if (enriched)
                    entry = enriched;
            }
        }
        applyNotificationPresentation(entry, true);
    }

    function handleDndChanged() {
        if (!notificationsDndEnabled()) {
            root.restoreAfterTransient();
            return;
        }

        root.clearPendingNotificationIds();
        if (root.presentation === "transient_notification") {
            if (root.displayingNotificationId >= 0)
                root.markNotificationPresentationCompleted(root.displayingNotificationId);
            transientTimer.stop();
            root.displayingNotificationId = -1;
            root.transientNotificationExpanded = false;
            root.setUserInteracting(false);
            root.forcedState = "";
            clearTransientFields();
            root.clearEventOwnerOutput();
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
            "state=" + root.presentation,
            "enabled=" + root.islandEnabled,
            "hideTopbarTime=" + root.dynamicIslandHideTopbarTime,
            "leftClickAction=" + root.leftClickAction,
            "rightClickAction=" + root.rightClickAction,
            "autoExpandMedia=" + root.dynamicIslandAutoExpandMedia,
            "hoverExpand=" + root.dynamicIslandHoverExpand,
            "displayText=" + root.displayText,
            "secondaryText=" + root.secondaryText,
            "progress=" + root.progress,
            "iconCode=" + root.iconCode,
            "targetScreenName=" + root.targetScreenName,
            "eventOwnerOutput=" + root.eventOwnerOutput,
            "sessionOwnerOutput=" + root.sessionOwnerOutput,
            "expanded=" + root.expanded,
            "pendingNotificationIds=" + (root.pendingNotificationIds ? root.pendingNotificationIds.length : 0),
            "displayingNotificationId=" + root.displayingNotificationId,
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

        function onNotificationUpdated(id) {
            root.handleNotificationUpdated(id);
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

        function onAudioReadyChanged() {
            root.handleAudioReadyChange();
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
            if (root.presentation === "transient_notification") {
                if (root.displayingNotificationId >= 0)
                    root.markNotificationPresentationCompleted(root.displayingNotificationId);
                root.displayingNotificationId = -1;
            }
            root.clearTransientFields();
            root.forcedState = "";
            root.clearEventOwnerOutput();
            // Keep session owner only while expanded; transient end drops event pin.
            if (!root.expanded)
                root.clearSessionOwnerOutput();
            root.restoreAfterTransient();
        }
    }

    Timer {
        id: swipeSettleTimer
        interval: IslandMotion.swipeSettleDuration
        repeat: false
        onTriggered: {
            // Settle complete: drop gesture phase only. Geometry follows state.
            root.swipeSettling = false;
            root.swipeStartProgress = 0;
            root.swipeStartForcedState = "";
            root.swipeProgress = 0;
        }
    }

}
