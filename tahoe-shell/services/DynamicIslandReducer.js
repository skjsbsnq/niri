.pragma library

// Pure Dynamic Island presentation reducer (T06+).
// No QML service access, no timers, no Date.now.
// DynamicIsland.qml is the sole production orchestrator and effect runner.

var VALID_STATES = [
    "resting_time",
    "resting_media",
    "resting_timer",
    "transient_osd",
    "transient_notification",
    "transient_workspace",
    "transient_timer_complete",
    "transient_bluetooth",
    "expanded_media",
    "expanded_timer"
];


// Presentation priority table (roadmap 14.5). Higher wins.
var PRIORITY = {
    // Direct hardware feedback must win immediately, including while another
    // scene is expanded or a notification lease is active.
    "osd": 110,
    "interaction": 100,
    "critical_notification": 90,
    "notification": 80,
    "timer_completion": 70,
    "bluetooth": 60,
    "workspace": 40,
    "media_preview": 30,
    "clock": 0
};

function priorityValue(kind) {
    var key = String(kind || "");
    if (PRIORITY[key] !== undefined)
        return PRIORITY[key];
    return 0;
}

function presentationPriority(presentation, flags) {
    var f = flags || {};
    if (f.userInteracting || f.expanded)
        return PRIORITY.interaction;
    var p = String(presentation || "");
    if (p === "transient_notification" || f.displayingNotification)
        return f.critical ? PRIORITY.critical_notification : PRIORITY.notification;
    if (p === "transient_osd")
        return PRIORITY.osd;
    if (p === "transient_workspace")
        return PRIORITY.workspace;
    if (p === "transient_timer_complete")
        return PRIORITY.timer_completion;
    if (p === "transient_bluetooth")
        return PRIORITY.bluetooth;
    if (p === "resting_timer" || p === "expanded_timer")
        return p === "expanded_timer" ? PRIORITY.interaction : PRIORITY.media_preview;
    if (p === "resting_media" || p === "expanded_media")
        return p === "expanded_media" ? PRIORITY.interaction : PRIORITY.media_preview;
    return PRIORITY.clock;
}

function blocksCandidate(currentPriority, candidatePriority) {
    // Strict: only higher-or-equal current blocks lower candidate.
    // Equal priority: existing presentation holds (no steal).
    return Number(currentPriority) >= Number(candidatePriority);
}

function blocksOsd(presentation, flags) {
    // Same-kind updates coalesce in place. Treating equal OSD priority as a
    // blocker queued every drag/key-repeat sample until the hide timer fired.
    if (String(presentation || "") === "transient_osd")
        return false;
    return blocksCandidate(presentationPriority(presentation, flags), PRIORITY.osd);
}

function blocksWorkspace(presentation, flags) {
    return blocksCandidate(presentationPriority(presentation, flags), PRIORITY.workspace);
}

function blocksNotification(presentation, flags) {
    var f = flags || {};
    // One notification at a time; expanded/interaction always block.
    if (f.userInteracting || f.expanded)
        return true;
    // Direct hardware feedback keeps its short lease until the retained exit
    // finishes; notifications drain immediately afterwards.
    if (String(presentation || "") === "transient_osd")
        return true;
    if (String(presentation || "") === "transient_notification")
        return true;
    if (f.displayingNotification)
        return true;
    return false;
}

function blocksBluetooth(presentation, flags) {
    var f = flags || {};
    if (f.userInteracting || f.expanded)
        return true;
    if (String(presentation || "") === "transient_notification"
            || String(presentation || "") === "transient_osd")
        return true;
    if (f.displayingNotification)
        return true;
    return blocksCandidate(presentationPriority(presentation, f), PRIORITY.bluetooth);
}

function cloneState(state) {
    var source = state || {};
    return {
        "forcedState": String(source.forcedState || ""),
        "preferMediaWhenAvailable": source.preferMediaWhenAvailable !== false,
        "hoverExpanded": !!source.hoverExpanded
    };
}

function createInitialState() {
    return {
        "forcedState": "",
        "preferMediaWhenAvailable": true,
        "hoverExpanded": false
    };
}

function createContext(partial) {
    var source = partial || {};
    return {
        "islandEnabled": source.islandEnabled !== false,
        "hasMedia": !!source.hasMedia,
        "autoExpandMedia": !!source.autoExpandMedia,
        "userInteracting": !!source.userInteracting
    };
}

function createEvent(kind, payload) {
    return {
        "kind": String(kind || ""),
        "payload": payload === undefined ? null : payload
    };
}

function validStates() {
    return VALID_STATES.slice();
}

function isValidState(nextState) {
    return VALID_STATES.indexOf(String(nextState || "")) >= 0;
}

function restingState(state, context) {
    var ctx = createContext(context);
    var slice = cloneState(state);
    if (!ctx.islandEnabled)
        return "resting_time";
    return slice.preferMediaWhenAvailable && ctx.hasMedia ? "resting_media" : "resting_time";
}

function presentationState(state, context) {
    var ctx = createContext(context);
    var slice = cloneState(state);
    if (!ctx.islandEnabled)
        return "resting_time";

    var candidate = String(slice.forcedState || "");
    if (!isValidState(candidate))
        return restingState(slice, ctx);

    if ((candidate === "resting_media" || candidate === "expanded_media") && !ctx.hasMedia)
        return "resting_time";

    return candidate;
}

function isExpandedPresentation(presentation) {
    return presentation === "expanded_media" || presentation === "expanded_timer";
}

function effect(type, payload) {
    var item = { "type": String(type || "") };
    if (payload !== undefined)
        item.payload = payload;
    return item;
}

function result(nextState, effects) {
    return {
        "state": cloneState(nextState),
        "effects": effects || []
    };
}

function reduce(state, event, context) {
    var slice = cloneState(state);
    var ctx = createContext(context);
    var ev = event || {};
    var kind = String(ev.kind || "");
    var effects = [];

    if (!ctx.islandEnabled) {
        // Disabled: presentation is always resting_time.
        // ISLAND_DISABLED must NOT reset preferMediaWhenAvailable (historical
        // disable path preserved media/clock preference across re-enable).
        // RESET while disabled still resets preference and does not clear swipe.
        if (kind === "ISLAND_DISABLED") {
            slice.forcedState = "";
            slice.hoverExpanded = false;
            return result(slice, [
                effect("stopTransientTimer"),
            effect("clearEventOwner"),
                effect("clearTransientFields"),
                effect("clearPendingNotifications"),
                effect("clearDisplayingNotification"),
                effect("clearPendingOsd"),
                effect("clearPendingBluetooth"),
                effect("clearUserInteracting"),
                effect("clearSwipe")
            ]);
        }
        if (kind === "RESET") {
            slice.forcedState = "";
            slice.preferMediaWhenAvailable = true;
            slice.hoverExpanded = false;
            return result(slice, [
                effect("stopTransientTimer"),
            effect("clearEventOwner"),
                effect("clearTransientFields"),
                effect("clearPendingNotifications"),
                effect("clearDisplayingNotification"),
                effect("clearPendingOsd"),
                effect("clearPendingBluetooth")
            ]);
        }
        // Other events while disabled are no-ops for presentation slice.
        return result(slice, []);
    }

    switch (kind) {
    
    case "SHOW_TIMER_COMPLETION": {
        // timer_completion (70) yields to interaction/critical/notification/OSD.
        var curP = presentationPriority(presentationState(slice, ctx), {
            "userInteracting": ctx.userInteracting,
            "expanded": isExpandedPresentation(presentationState(slice, ctx)),
            "displayingNotification": !!(ev.payload && ev.payload.displayingNotification),
            "critical": !!(ev.payload && ev.payload.criticalNotification)
        });
        if (blocksCandidate(curP, PRIORITY.timer_completion))
            return result(slice, [effect("queueTimerCompletion")]);
        slice.forcedState = "transient_timer_complete";
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearEventOwner"),
            effect("clearTransientFields")
        ]);
    }

    case "SHOW_BLUETOOTH": {
        var bluetoothFlags = {
            "userInteracting": ctx.userInteracting,
            "expanded": isExpandedPresentation(presentationState(slice, ctx)),
            "displayingNotification": !!(ev.payload && ev.payload.displayingNotification),
            "critical": !!(ev.payload && ev.payload.criticalNotification)
        };
        if (blocksBluetooth(presentationState(slice, ctx), bluetoothFlags))
            return result(slice, [effect("queueBluetoothEvent", ev.payload || null)]);
        slice.forcedState = "transient_bluetooth";
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearEventOwner"),
            effect("clearTransientFields")
        ]);
    }

    case "SHOW_TIMER_COMPACT":
        slice.forcedState = "resting_timer";
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearEventOwner"),
            effect("endNotificationLease"),
            effect("clearTransientFields")
        ]);

    case "SHOW_TIMER_EXPANDED":
        slice.forcedState = "expanded_timer";
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearEventOwner"),
            effect("endNotificationLease"),
            effect("clearTransientFields")
        ]);

    case "CLEAR_TIMER_PRESENTATION":
        if (slice.forcedState === "resting_timer"
                || slice.forcedState === "expanded_timer"
                || slice.forcedState === "transient_timer_complete")
            slice.forcedState = "";
        return result(slice, []);

    case "RESET":
        slice.forcedState = "";
        slice.preferMediaWhenAvailable = true;
        slice.hoverExpanded = false;
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearEventOwner"),
            effect("clearTransientFields"),
            effect("clearPendingNotifications"),
            effect("clearDisplayingNotification"),
            effect("clearPendingOsd"),
            effect("clearPendingBluetooth")
        ]);

    case "SHOW_TIME":
        // Historical showTime did not touch hoverExpanded.
        // Abort any active notification lease before changing presentation.
        slice.preferMediaWhenAvailable = false;
        slice.forcedState = "";
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearEventOwner"),
            effect("endNotificationLease"),
            effect("clearTransientFields")
            // Drain happens once via onStateChanged after forcedState commit.
        ]);

    case "SHOW_MEDIA":
        slice.preferMediaWhenAvailable = true;
        slice.forcedState = ctx.hasMedia ? "resting_media" : "";
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearEventOwner"),
            effect("endNotificationLease"),
            effect("clearTransientFields")
        ]);

    case "SHOW_EXPANDED_MEDIA":
        slice.preferMediaWhenAvailable = true;
        // T18: no expanded_summary fallback — without media stay resting.
        slice.forcedState = ctx.hasMedia ? "expanded_media" : "";
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearEventOwner"),
            effect("endNotificationLease"),
            effect("clearTransientFields")
        ]);

    case "SHOW_EXPANDED_SUMMARY":
        // T18 deprecated: never force expanded_summary. Orchestrator opens ControlCenter.
        slice.forcedState = "";
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearEventOwner"),
            effect("endNotificationLease"),
            effect("clearTransientFields"),
            effect("openControlCenter")
        ]);

    case "COLLAPSE": {
        // payload.drainPending is retained for API compatibility; drain itself
        // is performed once by onStateChanged after forcedState changes.
        slice.forcedState = "";
        slice.hoverExpanded = false;
        return result(slice, [
            effect("endNotificationLease")
        ]);
    }

    case "TOGGLE_EXPANDED": {
        slice.hoverExpanded = false;
        var current = presentationState(slice, ctx);
        if (isExpandedPresentation(current)) {
            slice.forcedState = "";
            return result(slice, [effect("endNotificationLease")]);
        }
        if (ctx.hasMedia) {
            slice.preferMediaWhenAvailable = true;
            slice.forcedState = "expanded_media";
            return result(slice, [
                effect("stopTransientTimer"),
                effect("clearEventOwner"),
                effect("endNotificationLease"),
                effect("clearTransientFields")
            ]);
        }
        // T18: no summary page — return to resting base.
        slice.forcedState = "";
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearEventOwner"),
            effect("endNotificationLease"),
            effect("clearTransientFields")
        ]);
    }

    case "MEDIA_AVAILABILITY_CHANGED": {
        // Check forcedState, not normalized presentation: when hasMedia flips
        // false, presentationState already maps expanded_media → resting_time,
        // but the forced override must still be cleared (historical intent).
        if (!ctx.hasMedia && slice.forcedState === "expanded_media") {
            slice.hoverExpanded = false;
            slice.forcedState = "";
            return result(slice, []);
        }
        var presentation = presentationState(slice, ctx);
        if (ctx.autoExpandMedia
                && ctx.hasMedia
                && !isExpandedPresentation(presentation)
                && !ctx.userInteracting) {
            slice.preferMediaWhenAvailable = true;
            slice.forcedState = "expanded_media";
            return result(slice, [
                effect("stopTransientTimer"),
            effect("clearEventOwner"),
                effect("endNotificationLease"),
                effect("clearTransientFields")
            ]);
        }
        return result(slice, []);
    }

    case "HOVER_EXPAND": {
        if (!ctx.islandEnabled || ctx.userInteracting)
            return result(slice, []);
        var hoverPresentation = presentationState(slice, ctx);
        if (isExpandedPresentation(hoverPresentation))
            return result(slice, []);
        // autoExpand flag for hover is gated by orchestrator via event emission.
        slice.hoverExpanded = true;
        if (ctx.hasMedia) {
            slice.preferMediaWhenAvailable = true;
            slice.forcedState = "expanded_media";
        } else {
            // T18: hover without media does not invent a summary panel.
            slice.hoverExpanded = false;
            slice.forcedState = "";
        }
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearEventOwner"),
            effect("endNotificationLease"),
            effect("clearTransientFields")
        ]);
    }

    case "HOVER_COLLAPSE": {
        if (!slice.hoverExpanded)
            return result(slice, []);
        slice.hoverExpanded = false;
        var hoverCurrent = presentationState(slice, ctx);
        if (isExpandedPresentation(hoverCurrent)) {
            slice.forcedState = "";
            return result(slice, [effect("endNotificationLease")]);
        }
        return result(slice, []);
    }

    case "SET_FORCED_STATE": {
        var nextForced = String((ev.payload && ev.payload.forcedState) || "");
        if (nextForced.length > 0 && !isValidState(nextForced))
            return result(slice, []);
        slice.forcedState = nextForced;
        return result(slice, []);
    }

    case "CLEAR_HOVER_EXPANDED":
        slice.hoverExpanded = false;
        return result(slice, []);

    default:
        return result(slice, []);
    }
}

function applyPresentationParity(state, context) {
    // Convenience for tests: single pure path from slice → presentation string.
    return presentationState(state, context);
}
