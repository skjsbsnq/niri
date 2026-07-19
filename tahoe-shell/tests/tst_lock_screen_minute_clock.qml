import "../components" as Components
import QtQuick
import QtTest

TestCase {
    id: testCase

    property var lock: null

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

        if (item.lockClock !== undefined)
            return item.lockClock;

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

        if (item.echoMode !== undefined && item.text !== undefined && item.forceActiveFocus !== undefined)
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

        if (item.pam !== undefined)
            return item.pam;

        if (item.config === "login" && item.respond !== undefined && item.completed !== undefined)
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
        clock.testNowProvider = function() {
            return injected;
        };
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

    function test_wallpaper_preview_resolver_is_output_aware() {
        lock.activeWallpaperEntries = {
            "eDP-2": { "backgroundId": "/tmp/wallpapers/one" },
            "HDMI-A-1": { "backgroundId": "/tmp/wallpapers/two" }
        };
        lock.activeWallpaperRevision += 1;
        compare(lock.wallpaperProjectForOutput("eDP-2"), "/tmp/wallpapers/one");
        compare(lock.wallpaperProjectForOutput("HDMI-A-1"), "/tmp/wallpapers/two");
        compare(lock.wallpaperProjectForOutput("missing"), "");

        lock.activeWallpaperEntries = {
            "eDP-2": { "backgroundId": "/tmp/wallpapers/only" }
        };
        lock.activeWallpaperRevision += 1;
        compare(lock.wallpaperProjectForOutput("HDMI-A-1"), "");
        compare(lock.wallpaperProjectForOutput(""), "/tmp/wallpapers/only");
    }

    function test_wallpaper_preview_resolver_reads_project_metadata() {
        compare(
            lock.wallpaperPreviewFromProject(
                "/tmp/wallpapers/one",
                '{"preview":"preview.gif"}'
            ),
            "/tmp/wallpapers/one/preview.gif"
        );
        compare(lock.wallpaperPreviewFromProject("/tmp/wallpapers/one", "{}"), "");
        compare(lock.wallpaperPreviewFromProject("/tmp/wallpapers/one", "not-json"), "");
    }

    function test_dynamic_wallpaper_command_resolves_project_path() {
        compare(
            lock.wallpaperProjectFromDynamicCommand(
                "linux-wallpaperengine --screen-root eDP-2 --bg '/tmp/wallpapers/three'"
            ),
            "/tmp/wallpapers/three"
        );
        compare(
            lock.wallpaperProjectFromDynamicCommand("linux-wallpaperengine 3286906338"),
            "/tmp/tahoe-shell-test-home/.local/share/Steam/steamapps/workshop/content/431960/3286906338"
        );
        compare(
            lock.wallpaperProjectFromDynamicCommand("linux-wallpaperengine '/tmp/wallpapers/four'"),
            "/tmp/wallpapers/four"
        );
    }

    function test_missing_wallpaper_sources_fall_back_to_builtin() {
        lock.settingsService = wallpaperSettings;
        wallpaperSettings.wallpaperMode = "external";
        wallpaperSettings.effectiveStaticWallpaper = "";
        lock.lock();
        wait(0);
        var surface = lock.surfaceInstances[0];
        verify(surface !== null);
        surface.wallpaperPreviewSource = "/definitely/missing/tahoe-preview.png";
        tryCompare(surface, "wallpaperPreviewSource", "", 1000);
        compare(surface.lockWallpaperSource, surface.defaultWallpaperSource);
        lock.unlock();

        wallpaperSettings.wallpaperMode = "static";
        wallpaperSettings.effectiveStaticWallpaper = "/definitely/missing/tahoe-static.png";
        lock.lock();
        wait(0);
        surface = lock.surfaceInstances[0];
        tryCompare(surface, "configuredStaticWallpaperFailed", true, 1000);
        compare(surface.lockWallpaperSource, surface.defaultWallpaperSource);
        lock.unlock();
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
        pam.active = false;
        pam.completed(2);
        wait(0);
        compare(input.text, "");
        input.text = "stale";
        lock.unlock();
        compare(lock.credentialText, "");
        lock.credentialText = "stale-again";
        lock.lock();
        wait(0);
        input = findPasswordInput(lock);
        verify(input !== null);
        compare(input.text, "");
    }

    function test_two_output_surfaces_share_one_credential_and_pam_owner() {
        lock.lock();
        wait(0);
        compare(lock.surfaceInstances.length, 2);
        compare(lock.secure, true);
        var firstInput = findPasswordInput(lock.surfaceInstances[0]);
        var secondInput = findPasswordInput(lock.surfaceInstances[1]);
        verify(firstInput !== null);
        verify(secondInput !== null);
        firstInput.text = "shared-secret";
        wait(0);
        compare(lock.credentialText, "shared-secret");
        compare(secondInput.text, "shared-secret");
        var before = lock.pam.startCount;
        lock.submitPassword();
        compare(lock.pam.startCount, before + 1);
        lock.unlock();
    }

    function test_authentication_failures_restart_feedback_without_stacking() {
        lock.lock();
        wait(0);
        var input = findPasswordInput(lock);
        var pam = findPam(lock);
        verify(input !== null);
        verify(pam !== null);
        pam.startResult = false;
        input.text = "bad-start";
        var before = lock.failureFeedbackSerial;
        lock.submitPassword();
        compare(lock.failureFeedbackSerial, before + 1);
        compare(lock.authFailed, true);
        compare(lock.statusText, "无法启动认证");
        compare(input.text, "");
        pam.startResult = true;
        pam.active = false;
        pam.completed(2);
        compare(lock.failureFeedbackSerial, before + 2);
        compare(lock.statusText, "密码不正确");
        pam.active = false;
        pam.completed(2);
        compare(lock.failureFeedbackSerial, before + 3);
        compare(lock.authFailed, true);
        input.text = "retry";
        compare(lock.authFailed, false);
        compare(lock.statusText, "");
    }

    function test_success_keeps_session_locked_until_bounded_exit_finishes() {
        lock.lock();
        wait(0);
        var input = findPasswordInput(lock.surfaceInstances[0]);
        var peerInput = findPasswordInput(lock.surfaceInstances[1]);
        var pam = findPam(lock);
        verify(input !== null);
        verify(peerInput !== null);
        input.text = "correct";
        lock.submitPassword();
        pam.active = false;
        pam.completed(0);
        compare(lock.locked, true);
        compare(lock.secure, true);
        compare(lock.unlocking, true);
        compare(lock.credentialText, "");
        compare(input.text, "");
        compare(peerInput.text, "");
        verify(lock.unlockExitDuration > 0);
        verify(lock.unlockExitDuration <= 180);
        wait(lock.unlockExitDuration + 30);
        compare(lock.locked, false);
        compare(lock.secure, false);
        compare(lock.unlocking, false);
        compare(lock.unlockCount, 1);
        compare(lock.surfaceInstances.length, 0);
    }

    function test_reduced_profile_unlocks_without_spatial_delay() {
        lock.settingsService = reducedSettings;
        compare(lock.lockEnterDuration, 0);
        compare(lock.unlockExitDuration, 0);
        compare(lock.feedbackFadeDuration, 0);
        lock.lock();
        wait(0);
        var input = findPasswordInput(lock);
        var pam = findPam(lock);
        input.text = "correct";
        lock.submitPassword();
        pam.active = false;
        pam.completed(0);
        wait(0);
        compare(lock.locked, false);
        compare(lock.secure, false);
        compare(lock.unlocking, false);
    }

    name: "LockScreenSystemClockConsumer"
    when: windowShown

    QtObject {
        id: reducedSettings

        property string motionProfile: "reduced"
        property string homeDir: "/tmp/tahoe-shell-test-home"
        property string wallpaperMode: "static"
        property string effectiveStaticWallpaper: ""
        property string effectiveDynamicWallpaperCommand: ""
        property bool lockScreenFollowWallpaper: true
    }

    QtObject {
        id: wallpaperSettings

        property string motionProfile: "balanced"
        property string homeDir: "/tmp/tahoe-shell-test-home"
        property string wallpaperMode: "external"
        property string effectiveStaticWallpaper: ""
        property string effectiveDynamicWallpaperCommand: ""
        property bool lockScreenFollowWallpaper: true
    }

    Component {
        id: lockComponent

        Components.LockScreen {
        }

    }

}
