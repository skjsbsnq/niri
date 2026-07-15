pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// Single shared countdown owner (T20).
// Monotonic elapsed via Quickshell ElapsedTimer (QElapsedTimer).
// QML Timer only refreshes display at low frequency — never drives countdown
// with Date.now / wall-clock deltas.
//
// Product policies (fixed):
// - suspend / session inactive: pause consumption; resume keeps remaining.
// - shell reload: do NOT restore an active timer (no persistence). Documented.
Item {
    id: root
    visible: false

    // Total duration requested at start (seconds).
    property real durationSec: 0
    // Remaining display value (seconds, fractional ok; UI floors).
    property real remainingSec: 0
    property bool running: false
    property bool paused: false
    property bool finished: false
    // True while a timer exists (running, paused, or just finished awaiting clear).
    readonly property bool active: root.durationSec > 0 && !root.cleared
    property bool cleared: true

    readonly property real progress: {
        if (root.durationSec <= 0)
            return 0;
        return Math.max(0, Math.min(1, 1 - (root.remainingSec / root.durationSec)));
    }

    readonly property string remainingLabel: root.formatRemaining(root.remainingSec)

    signal started(real seconds)
    signal pausedByUser()
    signal resumedByUser()
    signal cancelled()
    signal completed()
    // Fired after remaining is updated while running (UI refresh).
    signal tick()

    // Accumulated monotonic seconds consumed while running segments.
    property real consumedSec: 0
    // Seconds already remaining when the current running segment started.
    property real segmentRemainingSec: 0

    ElapsedTimer {
        id: mono
    }

    // Low-frequency display refresh only.
    Timer {
        id: displayPulse
        interval: 250
        repeat: true
        running: root.running
        onTriggered: root.refreshRemaining()
    }

    // Pause when session is suspended or inactive (no wall-clock catch-up).
    Connections {
        target: Qt.application
        function onStateChanged() {
            root.handleApplicationState(Qt.application.state);
        }
    }

    property bool pausedBySession: false

    function handleApplicationState(state) {
        // Suspend / inactive / hidden: stop consuming (no wall-clock catch-up).
        if (state === Qt.ApplicationSuspended
                || state === Qt.ApplicationInactive
                || state === Qt.ApplicationHidden) {
            if (root.running)
                root.pauseInternal(true);
            return;
        }
        if (state === Qt.ApplicationActive && root.pausedBySession)
            root.resumeInternal(true);
    }

    function formatRemaining(seconds) {
        var total = Math.max(0, Math.ceil(Number(seconds) || 0));
        var h = Math.floor(total / 3600);
        var m = Math.floor((total % 3600) / 60);
        var s = total % 60;
        function two(n) { return (n < 10 ? "0" : "") + n; }
        if (h > 0)
            return h + ":" + two(m) + ":" + two(s);
        return m + ":" + two(s);
    }

    function refreshRemaining() {
        if (!root.running)
            return;
        var elapsed = Math.max(0, Number(mono.elapsed()) || 0);
        var next = Math.max(0, root.segmentRemainingSec - elapsed);
        if (Math.abs(next - root.remainingSec) >= 0.05 || next <= 0)
            root.remainingSec = next;
        root.tick();
        if (next <= 0)
            root.finish();
    }

    function start(seconds) {
        var sec = Number(seconds);
        if (!isFinite(sec) || sec <= 0)
            return false;
        // Repeated start: replace active timer (product policy).
        root.durationSec = sec;
        root.remainingSec = sec;
        root.consumedSec = 0;
        root.segmentRemainingSec = sec;
        root.finished = false;
        root.cleared = false;
        root.paused = false;
        root.pausedBySession = false;
        root.running = true;
        mono.restart();
        root.started(sec);
        return true;
    }

    function pause() {
        return root.pauseInternal(false);
    }

    function pauseInternal(fromSession) {
        if (!root.running)
            return false;
        root.refreshRemaining();
        var elapsed = Math.max(0, Number(mono.elapsed()) || 0);
        root.consumedSec += elapsed;
        root.segmentRemainingSec = root.remainingSec;
        root.running = false;
        root.paused = true;
        root.pausedBySession = !!fromSession;
        if (!fromSession)
            root.pausedByUser();
        return true;
    }

    function resume() {
        return root.resumeInternal(false);
    }

    function resumeInternal(fromSession) {
        if (root.cleared || root.finished)
            return false;
        if (root.running)
            return true;
        if (root.remainingSec <= 0) {
            root.finish();
            return false;
        }
        root.paused = false;
        root.pausedBySession = false;
        root.segmentRemainingSec = root.remainingSec;
        root.running = true;
        mono.restart();
        if (!fromSession)
            root.resumedByUser();
        return true;
    }

    function cancel() {
        if (root.cleared && !root.running && !root.paused && !root.finished)
            return false;
        root.running = false;
        root.paused = false;
        root.finished = false;
        root.pausedBySession = false;
        root.durationSec = 0;
        root.remainingSec = 0;
        root.consumedSec = 0;
        root.segmentRemainingSec = 0;
        root.cleared = true;
        root.cancelled();
        return true;
    }

    function finish() {
        if (root.finished || root.cleared)
            return;
        root.running = false;
        root.paused = false;
        root.pausedBySession = false;
        root.remainingSec = 0;
        root.finished = true;
        root.completed();
    }

    function clearFinished() {
        if (!root.finished)
            return;
        root.finished = false;
        root.durationSec = 0;
        root.remainingSec = 0;
        root.cleared = true;
    }

    // Reload policy: no persistence; active timer does not survive shell reload.
    // (No FileView / settings write of remaining.)
}
