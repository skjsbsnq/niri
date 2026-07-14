import QtQuick
import QtTest
import "../services" as Services
import Quickshell.Io as TestIo

TestCase {
    id: testCase
    name: "ClipboardHistoryLosslessRefresh"
    when: windowShown

    property var clipboard: null
    property int startedListCount: 0

    QtObject {
        id: runner
        // Stable command binding — never mutates on re-evaluation.
        function clipboardListCommand() {
            return ["cliphist", "list"];
        }
        function clipboardWatchCommand() {
            return ["test-probe", "watch", "999999", "", "0"];
        }
        function clipboardDecodeCommand(raw) {
            return ["test-probe", "decode", "1", String(raw || ""), "0"];
        }
        function commandAvailable(name) {
            return true;
        }
        function refreshDependencies() {}
    }

    Component {
        id: clipboardComponent
        Services.ClipboardHistory {}
    }

    function recountStartedLists() {
        var ids = TestIo.TestProcessRegistry.startedIds || [];
        var n = 0;
        for (var i = 0; i < ids.length; i++) {
            if (String(ids[i]).indexOf("list") >= 0 || String(ids[i]) === "cliphist")
                n += 1;
        }
        // record() for ["cliphist","list"] uses argv[1] => "list"
        startedListCount = n;
    }

    function init() {
        TestIo.TestProcessRegistry.reset();
        TestIo.TestProcessRegistry.commandRules = [
            { match: "cliphist list", delayMs: 100, payload: "1\talpha", code: 0 }
        ];
        clipboard = clipboardComponent.createObject(testCase, {
            commandRunner: runner,
            cliphistAvailable: true,
            wlCopyAvailable: true,
            wlPasteAvailable: true
        });
        verify(clipboard !== null);
        wait(0);
        TestIo.TestProcessRegistry.reset();
        TestIo.TestProcessRegistry.commandRules = [
            { match: "cliphist list", delayMs: 100, payload: "1\talpha", code: 0 }
        ];
    }

    function cleanup() {
        if (clipboard) {
            clipboard.destroy();
            clipboard = null;
        }
        TestIo.TestProcessRegistry.reset();
        wait(0);
    }

    function test_refresh_during_inflight_list_is_replayed_once() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "cliphist list", delayMs: 150, payload: "1\talpha\n2\tbravo", code: 0 }
        ];
        clipboard.refresh();
        compare(clipboard.updating, true);
        wait(30);
        // Direct refresh while listProbe is running must set pending, not drop.
        clipboard.refresh();
        compare(clipboard.refreshPending, true);
        compare(clipboard.updating, true);

        tryCompare(clipboard, "updating", false, 3000);
        tryCompare(clipboard, "refreshPending", false, 2000);
        tryVerify(function() {
            recountStartedLists();
            return startedListCount === 2;
        }, 2000);
        compare(clipboard.entries.length >= 1, true);
    }

    function test_multiple_events_while_running_coalesce_to_one_followup() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "cliphist list", delayMs: 180, payload: "1\ta\n2\tb\n3\tc", code: 0 }
        ];
        clipboard.refresh();
        wait(30);
        clipboard.refresh();
        clipboard.refresh();
        clipboard.scheduleRefresh();
        // scheduleRefresh is debounced; force pending via direct refresh intents.
        clipboard.refresh();
        compare(clipboard.refreshPending, true);

        tryCompare(clipboard, "updating", false, 3000);
        tryCompare(clipboard, "refreshPending", false, 2000);
        tryVerify(function() {
            recountStartedLists();
            // First run + exactly one coalesced follow-up.
            return startedListCount === 2;
        }, 2000);
    }

    function test_schedule_refresh_timer_during_inflight_sets_pending() {
        // Original bug path: listProbe in flight, 450ms refreshTimer fires, intent dropped.
        TestIo.TestProcessRegistry.commandRules = [
            { match: "cliphist list", delayMs: 700, payload: "1\told", code: 0 }
        ];
        clipboard.refresh();
        compare(clipboard.updating, true);
        wait(20);
        clipboard.scheduleRefresh();
        // Wait past 450ms debounce while listProbe still running (~700ms).
        wait(500);
        compare(clipboard.refreshPending, true);
        compare(clipboard.updating, true);

        tryCompare(clipboard, "updating", false, 3000);
        tryCompare(clipboard, "refreshPending", false, 2000);
        tryVerify(function() {
            recountStartedLists();
            return startedListCount === 2;
        }, 2000);
    }

    function test_failed_start_replays_pending() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "cliphist list", failStart: true, delayMs: 40 }
        ];
        clipboard.refresh();
        wait(5);
        // Second intent while first FailedToStart is still "running".
        clipboard.refresh();
        // After fail finishes, pending must re-run. Switch rule to success for follow-up.
        TestIo.TestProcessRegistry.commandRules = [
            { match: "cliphist list", delayMs: 30, payload: "1\trecovered", code: 0 }
        ];
        tryCompare(clipboard, "refreshPending", false, 2000);
        tryCompare(clipboard, "updating", false, 2000);
        tryVerify(function() {
            recountStartedLists();
            return startedListCount >= 2;
        }, 2000);
        compare(clipboard.entries.length >= 1, true);
    }

    function test_idle_does_not_high_frequency_list() {
        wait(200);
        recountStartedLists();
        compare(startedListCount, 0);
        compare(clipboard.refreshPending, false);
    }
}
