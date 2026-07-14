import QtQuick
import QtTest
import "../services" as Services
import Quickshell

TestCase {
    id: testCase
    name: "AppsDesktopEntriesIdentityRefresh"
    when: windowShown

    property var apps: null
    property int fingerprintCalls: 0

    Component {
        id: appsComponent
        Services.Apps {}
    }

    function appObj(id, name, icon, execString, noDisplay) {
        return {
            "id": id,
            "name": name || id,
            "genericName": "",
            "icon": icon || "app",
            "execString": execString || id,
            "command": [execString || id],
            "startupClass": id,
            "noDisplay": !!noDisplay,
            "categories": "",
            "keywords": ""
        };
    }

    function init() {
        DesktopEntries.reset();
        DesktopEntries.setApplications([
            appObj("firefox", "Firefox"),
            appObj("code", "Code")
        ]);
        apps = appsComponent.createObject(testCase, {});
        verify(apps !== null);
        // Initial force refresh already ran in Component.onCompleted.
        verify(apps.desktopEntriesRevision >= 1);
        verify(apps.desktopEntriesFingerprint.length > 0);
    }

    function cleanup() {
        if (apps) {
            apps.destroy();
            apps = null;
        }
        DesktopEntries.reset();
    }

    function test_no_periodic_timer() {
        // Task 07B: event-driven only — no 2s desktopEntriesRefreshTimer.
        var timer = apps.children;
        for (var i = 0; i < timer.length; i++) {
            if (timer[i] && timer[i].interval === 2000 && timer[i].repeat === true)
                fail("periodic desktopEntriesRefreshTimer must be removed");
        }
        // Also assert idle wait does not recompute fingerprint / bump revision.
        var rev = apps.desktopEntriesRevision;
        var fp = apps.desktopEntriesFingerprint;
        wait(250);
        compare(apps.desktopEntriesRevision, rev);
        compare(apps.desktopEntriesFingerprint, fp);
    }

    function test_applications_changed_equal_count_replace() {
        var rev = apps.desktopEntriesRevision;
        DesktopEntries.setApplications([
            appObj("chromium", "Chromium"),
            appObj("code", "Code")
        ]);
        compare(apps.desktopEntriesRevision, rev + 1);
        verify(apps.realApplications.length >= 1);
    }

    function test_name_icon_exec_nodisplay_changes() {
        var rev = apps.desktopEntriesRevision;

        DesktopEntries.setApplications([
            appObj("editor", "Editor", "edit", "editor", false)
        ]);
        compare(apps.desktopEntriesRevision, rev + 1);
        rev = apps.desktopEntriesRevision;

        DesktopEntries.setApplications([
            appObj("editor", "Editor Pro", "edit", "editor", false)
        ]);
        compare(apps.desktopEntriesRevision, rev + 1);
        rev = apps.desktopEntriesRevision;

        DesktopEntries.setApplications([
            appObj("editor", "Editor Pro", "edit-pro", "editor", false)
        ]);
        compare(apps.desktopEntriesRevision, rev + 1);
        rev = apps.desktopEntriesRevision;

        DesktopEntries.setApplications([
            appObj("editor", "Editor Pro", "edit-pro", "editor --new", false)
        ]);
        compare(apps.desktopEntriesRevision, rev + 1);
        rev = apps.desktopEntriesRevision;

        DesktopEntries.setApplications([
            appObj("editor", "Editor Pro", "edit-pro", "editor --new", true)
        ]);
        compare(apps.desktopEntriesRevision, rev + 1);
    }

    function test_unchanged_signal_does_not_rebuild() {
        var rev = apps.desktopEntriesRevision;
        var fp = apps.desktopEntriesFingerprint;
        // Re-emit with identical content (order swap only — fingerprint sorted).
        DesktopEntries.setApplications([
            appObj("code", "Code"),
            appObj("firefox", "Firefox")
        ]);
        // Same fingerprint → no revision bump.
        compare(apps.desktopEntriesRevision, rev);
        compare(apps.desktopEntriesFingerprint, fp);
    }

    function test_silent_value_change_without_signal_does_not_poll() {
        // Proves no 2s timer: mutate model without applicationsChanged.
        var rev = apps.desktopEntriesRevision;
        DesktopEntries.replaceApplicationsSilent([
            appObj("sneaky", "Sneaky")
        ]);
        wait(250);
        compare(apps.desktopEntriesRevision, rev);
    }

    function test_large_model_only_on_real_change() {
        var many = [];
        for (var i = 0; i < 500; i++)
            many.push(appObj("app" + i, "App " + i));
        DesktopEntries.setApplications(many);
        var rev = apps.desktopEntriesRevision;
        // No-op identical signal
        DesktopEntries.setApplications(many.slice());
        compare(apps.desktopEntriesRevision, rev);
        // Real change on one entry
        many[0] = appObj("app0", "App 0 Renamed");
        DesktopEntries.setApplications(many);
        compare(apps.desktopEntriesRevision, rev + 1);
    }
}
