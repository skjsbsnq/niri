.pragma library

// Unified render-activity policy for PanelWindow.updatesEnabled (P02).
//
// Extends the existing visible / pollingActive "only when needed" gate onto the
// scene-graph path. Not a second control plane: callers still own their
// visible:/open:/surfaceVisible bindings; updatesEnabled mirrors and narrows
// them so fully static or unmapped surfaces stop requesting frames.
//
// quickshell ProxyWindowBase::setUpdatesEnabled(true) schedules window->update()
// so a freeze→thaw transition paints dirty content immediately.

// Popup / overlay panels whose visible binding already tracks open + exit fade
// inline `updatesEnabled: visible` directly — the mirror IS the whole policy
// (an unmapped surface must not request frames), so no helper wraps it.

// Resident chrome that stays mapped (TopBar, Dock, Dynamic Island, Wallpaper):
// freeze only when the surface is unmapped OR proven fully static with no
// pending one-shot paint pulse (clock tick, first map, content swap).
function forResidentSurface(surfaceVisible, motionActive, paintPulse) {
    if (!surfaceVisible)
        return false;
    return !!motionActive || !!paintPulse;
}

// Brief pulse window after a discrete content change so one/two frames land
// before the surface re-freezes. 48ms ≈ one refresh at 30Hz+, two at 60Hz+.
var paintPulseMs = 48;

// Longer pulse for events that kick Behavior-driven transitions the motion
// predicate cannot observe directly (island fillColor ColorAnimation 260ms,
// content scene crossfades 170ms). Must cover the longest such chain with
// margin; a hot-but-static surface renders no frames, so over-covering is free.
var transitionPulseMs = 360;
