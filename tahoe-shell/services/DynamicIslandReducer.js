.pragma library

// Pure Dynamic Island presentation reducer (T06+).
// No QML service access, no timers, no Date.now.
// DynamicIsland.qml is the sole production orchestrator and effect runner.

var VALID_STATES = [
    "resting_time",
    "resting_media",
    "transient_osd",
    "transient_notification",
    "transient_workspace",
    "expanded_media",
    "expanded_summary"
];

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
    return presentation === "expanded_media" || presentation === "expanded_summary";
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
                effect("clearTransientFields"),
                effect("clearPendingNotifications"),
                effect("clearDisplayingNotification"),
                effect("clearPendingOsd"),
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
                effect("clearTransientFields"),
                effect("clearPendingNotifications"),
                effect("clearDisplayingNotification"),
                effect("clearPendingOsd")
            ]);
        }
        // Other events while disabled are no-ops for presentation slice.
        return result(slice, []);
    }

    switch (kind) {
    case "RESET":
        slice.forcedState = "";
        slice.preferMediaWhenAvailable = true;
        slice.hoverExpanded = false;
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearTransientFields"),
            effect("clearPendingNotifications"),
            effect("clearDisplayingNotification"),
            effect("clearPendingOsd")
        ]);

    case "SHOW_TIME":
        // Historical showTime did not touch hoverExpanded.
        slice.preferMediaWhenAvailable = false;
        slice.forcedState = "";
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearTransientFields"),
            effect("maybeShowPendingNotification")
        ]);

    case "SHOW_MEDIA":
        slice.preferMediaWhenAvailable = true;
        slice.forcedState = ctx.hasMedia ? "resting_media" : "";
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearTransientFields"),
            effect("maybeShowPendingNotification")
        ]);

    case "SHOW_EXPANDED_MEDIA":
        slice.preferMediaWhenAvailable = true;
        slice.forcedState = ctx.hasMedia ? "expanded_media" : "expanded_summary";
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearTransientFields")
        ]);

    case "SHOW_EXPANDED_SUMMARY":
        slice.forcedState = "expanded_summary";
        return result(slice, [
            effect("stopTransientTimer"),
            effect("clearTransientFields")
        ]);

    case "COLLAPSE": {
        // payload.drainPending mirrors historical call sites: toggle/hover
        // collapse drain queues; click actions that only clear forcedState do not.
        slice.forcedState = "";
        slice.hoverExpanded = false;
        var drainPending = !!(ev.payload && ev.payload.drainPending);
        if (drainPending) {
            return result(slice, [
                effect("maybeShowPendingNotification"),
                effect("maybeShowPendingOsd")
            ]);
        }
        return result(slice, []);
    }

    case "TOGGLE_EXPANDED": {
        slice.hoverExpanded = false;
        var current = presentationState(slice, ctx);
        if (isExpandedPresentation(current)) {
            slice.forcedState = "";
            return result(slice, [effect("maybeShowPendingNotification")]);
        }
        if (ctx.hasMedia) {
            slice.preferMediaWhenAvailable = true;
            slice.forcedState = "expanded_media";
            return result(slice, [
                effect("stopTransientTimer"),
                effect("clearTransientFields")
            ]);
        }
        slice.forcedState = "expanded_summary";
        return result(slice, [
            effect("stopTransientTimer"),
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
            slice.forcedState = "expanded_summary";
        }
        return result(slice, [
            effect("stopTransientTimer"),
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
            return result(slice, [
                effect("maybeShowPendingNotification"),
                effect("maybeShowPendingOsd")
            ]);
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
