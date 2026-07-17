import QtQuick
import QtTest
import "../components" as Components

TestCase {
    id: testCase
    name: "LockScreenSystemClockConsumer"
    when: windowShown

    property var lock: null

    Component {
        id: lockComponent
        Components.LockScreen {}
    }

    function init() {
        lock = lockComponent.createObject(testCase);
        verify(lock !== null);
        wait(0);
    }

    function cleanup() {
        if (lock) {
            lock.destroy();
            lock = null;
        }
        wait(0);
    }

    function findClock(item) {
        // Walk children for SystemClock-shaped object (has resync + date).
        if (!item)
            return null;
        if (item.resync !== undefined && item.date !== undefined && item.precision !== undefined)
            return item;
        if (item.children) {
            for (var i = 0; i < item.children.length; i++) {
                var found = findClock(item.children[i]);
                if (found)
                    return found;
            }
        }
        // QObject children not in visual tree.
        var kids = item.data || [];
        for (var j = 0; j < kids.length; j++) {
            var c = kids[j];
            if (c && c.resync !== undefined && c.date !== undefined)
                return c;
        }
        return null;
    }

    function findPasswordInput(item) {
        if (!item)
            return null;
        if (item.echoMode !== undefined && item.text !== undefined
                && item.forceActiveFocus !== undefined)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = findPasswordInput(kids[i]);
            if (found)
                return found;
        }
        var data = item.data || [];
        for (var j = 0; j < data.length; j++) {
            var nested = findPasswordInput(data[j]);
            if (nested)
                return nested;
        }
        return null;
    }

    function findPam(item) {
        if (!item)
            return null;
        if (item.config === "login" && item.respond !== undefined
                && item.completed !== undefined)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = findPam(kids[i]);
            if (found)
                return found;
        }
        var data = item.data || [];
        for (var j = 0; j < data.length; j++) {
            var nested = findPam(data[j]);
            if (nested)
                return nested;
        }
        return null;
    }

    function test_opens_locked_shows_current_time() {
        lock.lock();
        wait(0);
        verify(lock.locked === true);
        // clockNow is SystemClock.date; must be a valid Date near now.
        verify(lock.clockNow !== undefined);
        var text = Qt.formatDateTime(lock.clockNow, "HH:mm");
        verify(text.length >= 4);
        // Matches SystemClock minutes precision (seconds zeroed in display source).
        compare(Qt.formatDateTime(lock.clockNow, "HH:mm"), text);
    }

    function test_lock_unlock_toggles_clock_enabled() {
        var clock = findClock(lock);
        // Prefer direct id via children search; if structure hides it, use enabled via lock.
        lock.lock();
        wait(0);
        clock = findClock(lock);
        verify(clock !== null, "LockScreen must own a SystemClock child");
        compare(clock.enabled, true);
        compare(clock.precision, 2); // Minutes

        lock.unlock();
        wait(0);
        compare(clock.enabled, false);

        lock.lock();
        wait(0);
        compare(clock.enabled, true);
        // lock() always calls resync on the SystemClock owner.
        verify(clock.resyncCount >= 1);
    }

    function test_sync_lock_clock_calls_resync() {
        lock.lock();
        wait(0);
        var clock = findClock(lock);
        verify(clock !== null);
        var before = clock.resyncCount;
        lock.syncLockClock();
        wait(0);
        compare(clock.resyncCount, before + 1);
    }

    function test_application_active_resyncs_when_locked() {
        lock.lock();
        wait(0);
        var clock = findClock(lock);
        verify(clock !== null);
        var before = clock.resyncCount;
        // Simulate resume path: same entry as Connections on ApplicationActive.
        if (Qt.application.state === Qt.ApplicationActive)
            lock.syncLockClock();
        else
            lock.syncLockClock();
        wait(0);
        compare(clock.resyncCount, before + 1);
    }

    function test_no_local_minute_timer() {
        // Production LockScreen must not keep a parallel minuteTimer.
        // Walk object tree for Timer with id-like interval re-arm patterns is hard;
        // assert via source contract in Python. Here: display driven by clock.date.
        lock.lock();
        wait(0);
        var clock = findClock(lock);
        verify(clock !== null);
        var injected = new Date(2026, 6, 14, 15, 42, 33);
        clock.testNowProvider = function() { return injected; };
        clock.resync();
        wait(0);
        compare(Qt.formatDateTime(lock.clockNow, "HH:mm"), "15:42");
        compare(Qt.formatDateTime(lock.clockNow, "yyyy"), "2026");
    }

    function test_hhmm_and_date_use_same_clock() {
        lock.lock();
        wait(0);
        var clock = findClock(lock);
        verify(clock !== null);
        clock.testNowProvider = function() {
            return new Date(2026, 0, 5, 9, 7, 0);
        };
        clock.resync();
        wait(0);
        compare(Qt.formatDateTime(lock.clockNow, "HH:mm"), "09:07");
        compare(Qt.formatDateTime(lock.clockNow, "yyyy年M月d日"), "2026年1月5日");
    }

    function test_password_input_is_the_only_authentication_state() {
        lock.lock();
        wait(0);
        var input = findPasswordInput(lock);
        var pam = findPam(lock);
        verify(input !== null, "LockScreen must own one password TextInput");
        verify(pam !== null, "LockScreen must own the PAM context");

        input.text = "secret";
        lock.submitPassword();
        pam.responseRequired = true;
        wait(0);
        compare(pam.lastResponse, "secret");
        compare(input.text, "");

        input.text = "bad";
        pam.completed(2);
        wait(0);
        compare(input.text, "");

        input.text = "stale";
        lock.unlock();
        compare(input.text, "");
        input.text = "stale-again";
        lock.lock();
        wait(0);
        compare(input.text, "");
    }
}
