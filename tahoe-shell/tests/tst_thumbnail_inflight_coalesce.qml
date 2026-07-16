import QtQuick
import QtTest
import "../services" as Services
import Quickshell.Io as TestIo

TestCase {
    id: testCase
    name: "ThumbnailInflightCoalesce"
    when: windowShown

    property var provider: null

    QtObject {
        id: windows
        // Membership only used by prune; keep empty so cleanup does not wipe test keys mid-case.
        property var windowList: []
    }

    Component {
        id: providerComponent
        Services.ThumbnailProvider {}
    }

    function captureStarts() {
        var ids = TestIo.TestProcessRegistry.startedIds || [];
        return ids.length;
    }

    function waitUntilIdle(timeoutMs) {
        var deadline = timeoutMs === undefined ? 3000 : timeoutMs;
        tryCompare(provider, "running", false, deadline);
        // activeJob may lag one frame after running drops.
        tryVerify(function() {
            return provider.activeJob === null || provider.activeJob === undefined;
        }, deadline);
    }

    function init() {
        TestIo.TestProcessRegistry.reset();
        // Match any thumbnailProcess command (sh -c ... window-thumbnail ...).
        TestIo.TestProcessRegistry.commandRules = [
            { match: "window-thumbnail", delayMs: 80, payload: "", code: 0 }
        ];
        provider = providerComponent.createObject(testCase, {
            windowsService: windows,
            maxCacheAgeMs: 60000
        });
        verify(provider !== null);
        wait(0);
        TestIo.TestProcessRegistry.reset();
        TestIo.TestProcessRegistry.commandRules = [
            { match: "window-thumbnail", delayMs: 80, payload: "", code: 0 }
        ];
    }

    function cleanup() {
        if (provider) {
            provider.destroy();
            provider = null;
        }
        TestIo.TestProcessRegistry.reset();
        wait(0);
    }

    function test_same_smaller_nonforce_is_single_capture() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "window-thumbnail", delayMs: 120, payload: "", code: 0 }
        ];
        compare(provider.requestThumbnail(42, 320, 220, "a", false), true);
        wait(20);
        compare(provider.running, true);
        // Same size while loading.
        compare(provider.requestThumbnail(42, 320, 220, "b", false), true);
        // Smaller while loading.
        compare(provider.requestThumbnail(42, 200, 150, "c", false), true);
        var st = provider.thumbnailStateForWindow(42, provider.revision);
        verify(st !== null);
        compare(st.refreshPending, false);

        waitUntilIdle(3000);
        compare(captureStarts(), 1);
        st = provider.thumbnailStateForWindow(42, provider.revision);
        compare(st.ready, true);
        compare(st.status, "ready");
    }

    function test_larger_while_loading_adds_at_most_one_followup() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "window-thumbnail", delayMs: 100, payload: "", code: 0 }
        ];
        compare(provider.requestThumbnail(9, 200, 150, "a", false), true);
        wait(20);
        compare(provider.running, true);
        compare(provider.requestThumbnail(9, 640, 480, "b", false), true);
        var st = provider.thumbnailStateForWindow(9, provider.revision);
        compare(st.refreshPending, true);

        waitUntilIdle(4000);
        // First capture + one upgrade follow-up.
        compare(captureStarts(), 2);
        st = provider.thumbnailStateForWindow(9, provider.revision);
        compare(st.ready, true);
        compare(st.maxWidth >= 640, true);
        compare(st.maxHeight >= 480, true);
    }

    function test_force_while_loading_adds_followup() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "window-thumbnail", delayMs: 100, payload: "", code: 0 }
        ];
        compare(provider.requestThumbnail(3, 320, 220, "a", false), true);
        wait(20);
        compare(provider.running, true);
        compare(provider.requestThumbnail(3, 320, 220, "force", true), true);
        var st = provider.thumbnailStateForWindow(3, provider.revision);
        compare(st.refreshPending, true);

        waitUntilIdle(4000);
        compare(captureStarts(), 2);
        st = provider.thumbnailStateForWindow(3, provider.revision);
        compare(st.ready, true);
        compare(st.generation >= 2, true);
    }

    function test_multiple_consumers_share_single_capture() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "window-thumbnail", delayMs: 100, payload: "", code: 0 }
        ];
        compare(provider.requestThumbnail(11, 320, 220, "c1", false), true);
        wait(20);
        for (var i = 0; i < 4; i++)
            compare(provider.requestThumbnail(11, 320, 220, "c" + i, false), true);
        var st = provider.thumbnailStateForWindow(11, provider.revision);
        compare(st.refreshPending, false);

        waitUntilIdle(3000);
        compare(captureStarts(), 1);
        st = provider.thumbnailStateForWindow(11, provider.revision);
        compare(st.ready, true);
        // All consumers read the same state object identity by key.
        var st2 = provider.thumbnailStateForWindow(11, provider.revision);
        compare(st, st2);
    }

    function test_failure_allows_retry() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "window-thumbnail", delayMs: 50, payload: "", code: 1 }
        ];
        compare(provider.requestThumbnail(5, 320, 220, "a", false), true);
        // Allow pumpTimer(0) to start the single Process.
        tryCompare(provider, "running", true, 1000);
        waitUntilIdle(2000);
        compare(captureStarts() >= 1, true);
        compare(provider.failureCount, 1);
        var st = provider.thumbnailStateForWindow(5, provider.revision);
        compare(st.failed, true);

        var startsAfterFail = captureStarts();
        TestIo.TestProcessRegistry.commandRules = [
            { match: "window-thumbnail", delayMs: 50, payload: "", code: 0 }
        ];
        compare(provider.requestThumbnail(5, 320, 220, "retry", false), true);
        tryCompare(provider, "running", true, 1000);
        waitUntilIdle(2000);
        compare(captureStarts() > startsAfterFail, true);
        st = provider.thumbnailStateForWindow(5, provider.revision);
        compare(st.ready, true);
        compare(st.failed, false);
        compare(provider.successCount >= 1, true);
    }

    function test_window_close_clears_active_and_pending() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "window-thumbnail", delayMs: 200, payload: "", code: 0 }
        ];
        compare(provider.requestThumbnail(77, 320, 220, "a", false), true);
        tryCompare(provider, "running", true, 1000);
        // Force a pending follow-up, then drop the window key.
        compare(provider.requestThumbnail(77, 320, 220, "force", true), true);
        var st = provider.thumbnailStateForWindow(77, provider.revision);
        compare(st.refreshPending, true);
        var startsBeforeCleanup = captureStarts();

        provider.cleanupCachedKey("77");
        wait(0);
        // Do not call thumbnailStateForWindow (create=true would re-insert).
        compare(provider.cache.hasOwnProperty("77"), false);

        waitUntilIdle(3000);
        // First start already recorded; follow-up must not start for cleaned key.
        compare(captureStarts(), startsBeforeCleanup);
        compare(provider.pendingCount, 0);
        compare(provider.activeJob === null || provider.activeJob === undefined, true);
    }

    function test_overview_batch_is_bounded_and_paced() {
        provider.overviewBatchLimit = 4;
        provider.overviewMinIntervalMs = 40;
        TestIo.TestProcessRegistry.commandRules = [
            { match: "window-thumbnail", delayMs: 1, payload: "", code: 0 }
        ];
        var windows = [];
        for (var i = 0; i < 12; i++)
            windows.push({ "id": 100 + i });

        var startedAt = Date.now();
        provider.requestThumbnails(windows, 480, 300, "window-overview", false);
        compare(provider.pendingCount <= provider.overviewBatchLimit, true);
        tryCompare(provider, "running", true, 1000);
        tryVerify(function() {
            return captureStarts() === provider.overviewBatchLimit
                && provider.pendingCount === 0
                && !provider.running
                && (provider.activeJob === null || provider.activeJob === undefined);
        }, 4000);

        compare(captureStarts(), provider.overviewBatchLimit);
        compare(Date.now() - startedAt >= 90, true);
    }

    function test_cancel_overview_preserves_shared_active_request() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "window-thumbnail", delayMs: 100, payload: "", code: 0 }
        ];
        compare(provider.requestThumbnail(201, 320, 220, "window-overview", false), true);
        tryCompare(provider, "running", true, 1000);
        compare(provider.requestThumbnail(201, 320, 220, "dock", false), true);

        provider.cancelRequests("window-overview");
        compare(provider.activeJob.cancelled, false);
        compare(provider.activeJob.requesters["dock"], true);
        waitUntilIdle(3000);
        compare(captureStarts(), 1);
    }

    function test_new_consumer_reclaims_cancelled_active_request() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "window-thumbnail", delayMs: 100, payload: "", code: 0 }
        ];
        compare(provider.requestThumbnail(202, 320, 220, "window-overview", false), true);
        tryCompare(provider, "running", true, 1000);
        provider.cancelRequests("window-overview");
        compare(provider.activeJob.cancelled, true);

        compare(provider.requestThumbnail(202, 320, 220, "dock", false), true);
        compare(provider.activeJob.cancelled, false);
        compare(provider.activeJob.requesters["dock"], true);
        waitUntilIdle(3000);
        var state = provider.thumbnailStateForWindow(202, provider.revision);
        compare(state.ready, true);
        compare(captureStarts(), 1);
    }

    function test_cancel_overview_drops_its_queued_requests() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "window-thumbnail", delayMs: 120, payload: "", code: 0 }
        ];
        compare(provider.requestThumbnail(301, 320, 220, "dock", false), true);
        tryCompare(provider, "running", true, 1000);
        compare(provider.requestThumbnail(302, 320, 220, "window-overview", false), true);
        compare(provider.requestThumbnail(303, 320, 220, "window-overview", false), true);
        compare(provider.pendingCount, 2);

        provider.cancelRequests("window-overview");
        compare(provider.pendingCount, 0);
        waitUntilIdle(3000);
        compare(captureStarts(), 1);
    }
}
