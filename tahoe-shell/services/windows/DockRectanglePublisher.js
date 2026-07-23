.pragma library

// Shell-side owner for wlr foreign-toplevel set_rectangle (R04 / F05–F06).
//
// Protocol: only the last rectangle is considered. Ownership is therefore a
// single publisher that:
//   1. keys candidates by the actual wlr Toplevel handle object identity
//      (never by IPC id / appId / title merge result);
//   2. accepts a candidate only when that handle's `screens` is exactly one
//      screen and it matches the submitting Dock's screen (fail closed on
//      zero, multi, or switching screens);
//   3. frame-coalesces high-frequency geometry (mag/push/bounce) to at most
//      one wire publish per handle per flush.
//
// R11 residual risk: WindowModel may still mis-pair IPC data to the wrong
// handle for labels/shelf grouping. This publisher never uses IPC output to
// pick which screen may publish; it only trusts handle.screens.

function screenName(screen) {
    if (!screen)
        return "";
    return String(screen.name || "").trim();
}

function toplevelObjectId(toplevel) {
    // Qt object identity for Map keys. Prefer objectName-less unique pointer
    // string that QML exposes via toString / unique stable form.
    if (!toplevel)
        return "";
    // Quickshell Toplevel is a QObject; toString is typically
    // "Toplevel(0x...)" which is unique for the lifetime of the handle.
    return String(toplevel);
}

/**
 * Decide whether `dockScreen` is the sole current-screen owner for `toplevel`.
 *
 * @returns {{ ok: boolean, reason: string, screenCount: number }}
 */
function currentScreenOwnership(toplevel, dockScreen) {
    if (!toplevel)
        return { "ok": false, "reason": "no-toplevel", "screenCount": 0 };

    var screens = toplevel.screens;
    var list = [];
    if (screens) {
        // QList may expose as array-like with .length
        var n = screens.length !== undefined ? screens.length : 0;
        for (var i = 0; i < n; i++)
            list.push(screens[i]);
    }

    var count = list.length;
    if (count === 0)
        return { "ok": false, "reason": "no-screens", "screenCount": 0 };
    if (count > 1)
        return { "ok": false, "reason": "multi-screen", "screenCount": count };

    var only = list[0];
    var dockName = screenName(dockScreen);
    var handleName = screenName(only);
    if (!dockName || !handleName || dockName !== handleName)
        return { "ok": false, "reason": "screen-mismatch", "screenCount": 1 };

    return { "ok": true, "reason": "current-screen", "screenCount": 1 };
}

/**
 * Normalize a geometry candidate. Width/height clamped to >= 0 integers.
 * Callers should not send negatives; compositor posts invalid_rectangle.
 */
function normalizeRect(x, y, width, height) {
    return {
        "x": Math.round(Number(x) || 0),
        "y": Math.round(Number(y) || 0),
        "width": Math.max(0, Math.round(Number(width) || 0)),
        "height": Math.max(0, Math.round(Number(height) || 0))
    };
}

/**
 * Pure decision: should this candidate become the pending publish for the handle?
 * Does not perform wire I/O.
 *
 * @param {object|null} existing pending entry for this handle
 * @param {object} candidate { toplevel, sourceWindow, dockScreen, rect, force, rejected }
 * @returns {{ accept: boolean, reason: string, entry: object|null }}
 */
function evaluateCandidate(existing, candidate) {
    if (!candidate || !candidate.toplevel)
        return { "accept": false, "reason": "no-toplevel", "entry": existing || null };

    var ownership = currentScreenOwnership(candidate.toplevel, candidate.dockScreen);
    if (!ownership.ok) {
        return {
            "accept": false,
            "reason": ownership.reason,
            "entry": existing || null,
            "ownership": ownership
        };
    }

    if (!candidate.sourceWindow)
        return { "accept": false, "reason": "no-source", "entry": existing || null };

    var rect = normalizeRect(
        candidate.rect.x,
        candidate.rect.y,
        candidate.rect.width,
        candidate.rect.height
    );

    var entry = {
        "toplevel": candidate.toplevel,
        "sourceWindow": candidate.sourceWindow,
        "dockScreen": candidate.dockScreen,
        "rect": rect,
        "force": !!candidate.force,
        "key": toplevelObjectId(candidate.toplevel)
    };

    // Always replace pending for this handle (last candidate wins within the frame).
    return { "accept": true, "reason": "accepted", "entry": entry, "ownership": ownership };
}

/**
 * Whether a pending entry is ready for wire publish.
 * Actual setRectangle must run in QML (this library is pure JS).
 */
function canPublish(entry) {
    return !!(entry
        && entry.toplevel
        && entry.toplevel.setRectangle
        && entry.sourceWindow
        && entry.rect);
}
