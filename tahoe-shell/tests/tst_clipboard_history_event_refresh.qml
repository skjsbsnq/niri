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
        property int revision: 1
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
        function dependencyDetail(name) { return ""; }
        function dependencyState(name) { return "ok"; }
        function runClipboardDeleteEntry(raw) { return { success: true }; }
        function runClipboardCopyEntry(raw, mimeType) { return { success: true }; }
        function runClipboardCopyText(text, mimeType) { return { success: true }; }
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

    function historyEntryById(entryId) {
        var values = clipboard ? clipboard.entries : [];
        for (var i = 0; i < values.length; i++) {
            if (String(values[i].entryId || "") === String(entryId || ""))
                return values[i];
        }
        return null;
    }

    function pinnedEntryByText(text) {
        var values = clipboard ? clipboard.pinnedEntries : [];
        for (var i = 0; i < values.length; i++) {
            if (String(values[i].text || "") === String(text || ""))
                return values[i];
        }
        return null;
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
        tryCompare(clipboard, "updating", false, 2000);
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

    function test_history_entries_merge_by_cliphist_id() {
        clipboard.clearEntries();
        clipboard.listLoaded = false;
        clipboard.lastListText = "";
        clipboard.parseList("10\talpha\n20\tbeta");
        compare(clipboard.entries.length, 2);
        var alpha = historyEntryById("10");
        var beta = historyEntryById("20");
        verify(alpha !== null);
        verify(beta !== null);
        compare(alpha.modelKey, "history:10");

        clipboard.parseList("20\tbeta updated\n10\talpha updated\n30\tgamma");
        compare(clipboard.entries.length, 3);
        compare(clipboard.entries[0], beta);
        compare(clipboard.entries[1], alpha);
        compare(historyEntryById("10"), alpha);
        compare(historyEntryById("20"), beta);
        compare(alpha.preview, "alpha updated");
        compare(beta.preview, "beta updated");

        clipboard.parseList("10\talpha final\n30\tgamma");
        compare(clipboard.entries.length, 2);
        compare(historyEntryById("10"), alpha);
        compare(alpha.preview, "alpha final");
        compare(clipboard.historyEntryCache["20"], undefined);
    }

    function test_failed_refresh_preserves_existing_entries() {
        clipboard.parseList("41\tkeep me\n42\tkeep me too");
        var first = historyEntryById("41");
        var second = historyEntryById("42");
        verify(first !== null);
        verify(second !== null);

        clipboard.pendingListText = "";
        clipboard.updating = true;
        clipboard.finishListProbe(1);
        compare(clipboard.entries.length, 2);
        compare(historyEntryById("41"), first);
        compare(historyEntryById("42"), second);
        verify(String(clipboard.statusText).indexOf("保留 2 项") >= 0);
    }

    function test_delete_optimistically_removes_only_target_id() {
        clipboard.parseList("51\talpha\n52\tbeta\n53\tgamma");
        var alpha = historyEntryById("51");
        var beta = historyEntryById("52");
        var gamma = historyEntryById("53");
        verify(alpha !== null);
        verify(beta !== null);
        verify(gamma !== null);

        clipboard.deleteEntry(beta);
        compare(clipboard.entries.length, 2);
        compare(historyEntryById("51"), alpha);
        compare(historyEntryById("52"), null);
        compare(historyEntryById("53"), gamma);
        compare(clipboard.historyEntryCache["52"], undefined);
        compare(clipboard.statusText, "2 项");
    }

    function test_pinned_entries_keep_identity_across_updates_and_moves() {
        clipboard.mergePinnedEntries([]);
        clipboard.mergePinnedEntries([
            { text: "alpha", preview: "Alpha", icon: "a", sourceRaw: "10\talpha", addedAt: "1" },
            { text: "beta", preview: "Beta", icon: "b", sourceRaw: "20\tbeta", addedAt: "2" }
        ]);
        var alpha = pinnedEntryByText("alpha");
        var beta = pinnedEntryByText("beta");
        verify(alpha !== null);
        verify(beta !== null);
        compare(alpha.modelKey, "pin:alpha");

        clipboard.mergePinnedEntries([
            { text: "beta", preview: "Beta updated", icon: "B", sourceRaw: "21\tbeta", addedAt: "3" },
            { text: "alpha", preview: "Alpha updated", icon: "A", sourceRaw: "11\talpha", addedAt: "4" }
        ]);
        compare(clipboard.pinnedEntries[0], beta);
        compare(clipboard.pinnedEntries[1], alpha);
        compare(pinnedEntryByText("alpha"), alpha);
        compare(pinnedEntryByText("beta"), beta);
        compare(alpha.preview, "Alpha updated");
        compare(beta.sourceRaw, "21\tbeta");

        clipboard.mergePinnedEntries([
            { text: "alpha", preview: "Alpha final", icon: "A", sourceRaw: "11\talpha", addedAt: "4" }
        ]);
        compare(clipboard.pinnedEntries.length, 1);
        compare(clipboard.pinnedEntries[0], alpha);
        compare(clipboard.pinnedEntryCache["beta"], undefined);
    }

    function test_pin_decode_failure_does_not_persist_partial_stdout() {
        clipboard.parseList("77\tpin failure source");
        var entry = historyEntryById("77");
        verify(entry !== null);
        TestIo.TestProcessRegistry.commandRules = [
            { match: "test-probe decode", delayMs: 20, payload: "partial decoded text", code: 1 }
        ];
        clipboard.pinEntry(entry);
        compare(clipboard.pinning, true);
        tryCompare(clipboard, "pinning", false, 2000);
        compare(pinnedEntryByText("partial decoded text"), null);
        compare(clipboard.statusText, "固定失败");
    }

    function test_pin_copy_and_unpin_keep_history_identity() {
        clipboard.mergePinnedEntries([]);
        clipboard.parseList("88\tpin success source");
        var history = historyEntryById("88");
        verify(history !== null);
        TestIo.TestProcessRegistry.commandRules = [
            { match: "test-probe decode", delayMs: 20, payload: "decoded pinned text", code: 0 }
        ];

        clipboard.pinEntry(history);
        compare(clipboard.pinning, true);
        tryCompare(clipboard, "pinning", false, 2000);
        var pin = pinnedEntryByText("decoded pinned text");
        verify(pin !== null);
        compare(pin.sourceRaw, "88\tpin success source");
        compare(clipboard.isEntryPinned(history), true);
        compare(historyEntryById("88"), history);

        clipboard.copyEntry(history);
        compare(clipboard.statusText, "已复制");
        clipboard.copyPinnedEntry(pin);
        compare(clipboard.statusText, "已复制固定项");

        clipboard.unpinPinnedEntry(pin);
        compare(pinnedEntryByText("decoded pinned text"), null);
        compare(clipboard.isEntryPinned(history), false);
        compare(historyEntryById("88"), history);
    }

    function test_idle_does_not_high_frequency_list() {
        wait(200);
        recountStartedLists();
        compare(startedListCount, 0);
        compare(clipboard.refreshPending, false);
    }
}
