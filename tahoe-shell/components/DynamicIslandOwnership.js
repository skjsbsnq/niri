.pragma library

// Pure multi-output ownership helpers for Dynamic Island (T08).
// No QML service access. Used by Overlay and unit tests.

function textOrEmpty(value) {
    if (value === undefined || value === null)
        return "";
    return String(value).trim();
}

function isExpandedStateName(name) {
    var s = String(name || "");
    return s === "expanded_media" || s === "expanded_summary";
}

function isTransientStateName(name) {
    var s = String(name || "");
    return s.indexOf("transient_") === 0;
}

function isRestingStateName(name) {
    var s = String(name || "");
    return s === "resting_time" || s === "resting_media" || s === "";
}

function resolvePresentationOwner(pins, live) {
    var p = pins || {};
    var l = live || {};
    var session = textOrEmpty(p.sessionOwnerOutput);
    if (session.length > 0)
        return session;
    var event = textOrEmpty(p.eventOwnerOutput);
    if (event.length > 0)
        return event;
    var focused = textOrEmpty(l.focusedOutput);
    if (focused.length > 0)
        return focused;
    var first = textOrEmpty(l.firstOutput);
    return first;
}

function sanitizeOwnerPins(pins, availableOutputs) {
    var p = pins || {};
    var available = availableOutputs || [];
    var set = {};
    for (var i = 0; i < available.length; i++) {
        var name = textOrEmpty(available[i]);
        if (name.length > 0)
            set[name] = true;
    }
    function keep(name) {
        var n = textOrEmpty(name);
        if (n.length === 0)
            return "";
        if (available.length === 0)
            return n;
        return set[n] ? n : "";
    }
    return {
        "eventOwnerOutput": keep(p.eventOwnerOutput),
        "sessionOwnerOutput": keep(p.sessionOwnerOutput)
    };
}

function screenPresentationRole(screenName, ownerName, presentation, flags) {
    var f = flags || {};
    var islandEnabled = f.islandEnabled !== false;
    var hideTopbarTime = f.hideTopbarTime !== false;
    var screen = textOrEmpty(screenName);
    var owner = textOrEmpty(ownerName);
    var state = String(presentation || "resting_time");
    var isOwner = owner.length === 0 || screen.length === 0 || screen === owner;
    var transient = isTransientStateName(state);
    var expanded = isExpandedStateName(state);
    // Compact media is owner activity (replaces base clock on the owner only).
    // Pure resting_time is the base clock scene, not activity.
    var compactMedia = state === "resting_media";
    var activity = transient || expanded || compactMedia
        || !!f.swipeInteractive || !!f.swipeSettling;
    var baseClockOnly = state === "resting_time" || state === "";

    if (!islandEnabled) {
        return {
            "showIslandCapsule": false,
            "showIslandRestingClock": false,
            "showTopbarTime": true,
            "showActivity": false,
            "isOwner": isOwner,
            "maskFollowsCapsule": false
        };
    }

    if (!hideTopbarTime) {
        // TopBar owns resting clock; Overlay only for owner activity.
        var showActivity = isOwner && activity;
        return {
            "showIslandCapsule": showActivity,
            "showIslandRestingClock": false,
            "showTopbarTime": true,
            "showActivity": showActivity,
            "isOwner": isOwner,
            "maskFollowsCapsule": showActivity
        };
    }

    if (isOwner) {
        return {
            "showIslandCapsule": true,
            "showIslandRestingClock": baseClockOnly && !activity,
            "showTopbarTime": false,
            "showActivity": activity,
            "isOwner": true,
            "maskFollowsCapsule": true
        };
    }

    // Non-owner: always base clock; never transient/expanded/compact media.
    return {
        "showIslandCapsule": true,
        "showIslandRestingClock": true,
        "showTopbarTime": false,
        "showActivity": false,
        "isOwner": false,
        "maskFollowsCapsule": true
    };
}


// T09: one-shot swipe settle decision. No QML access.
// Returns target progress for preview width, target forcedState, and whether entered expanded.
function resolveSwipeSettle(progress, startProgress, hasMedia, enterThreshold, returnThreshold) {
    var p = Number(progress) || 0;
    var start = Number(startProgress) || 0;
    var enter = Number(enterThreshold);
    var ret = Number(returnThreshold);
    if (!isFinite(enter))
        enter = 0.56;
    if (!isFinite(ret))
        ret = 0.44;

    if (p >= enter) {
        // Right enter: media when available; otherwise summary still uses the
        // summary/left geometry (360), not the media/right width (400).
        if (hasMedia) {
            return {
                "swipeProgress": 1,
                "forcedState": "expanded_media",
                "entered": true,
                "collapsed": false
            };
        }
        return {
            "swipeProgress": -1,
            "forcedState": "expanded_summary",
            "entered": true,
            "collapsed": false
        };
    }
    if (p <= -enter) {
        return {
            "swipeProgress": -1,
            "forcedState": "expanded_summary",
            "entered": true,
            "collapsed": false
        };
    }
    if (start >= 0.5 && p <= ret) {
        return {
            "swipeProgress": 0,
            "forcedState": "",
            "entered": false,
            "collapsed": true
        };
    }
    if (start <= -0.5 && p >= -ret) {
        return {
            "swipeProgress": 0,
            "forcedState": "",
            "entered": false,
            "collapsed": true
        };
    }
    // Snap back to start presentation; keep start progress for continuous geometry.
    return {
        "swipeProgress": start,
        "forcedState": null,
        "entered": false,
        "collapsed": false
    };
}

function swipePreviewWidthFor(progress, restingWidth, leftWidth, rightWidth) {
    var p = Number(progress) || 0;
    var resting = Number(restingWidth) || 0;
    var side = p >= 0 ? Number(rightWidth) : Number(leftWidth);
    return resting + (side - resting) * Math.min(1, Math.abs(p));
}
