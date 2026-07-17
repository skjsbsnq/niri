import QtQuick
import QtTest
import "../services" as Services
import Quickshell.Io as TestIo

TestCase {
    id: testCase
    name: "SearchLatestQuery"
    when: windowShown

    property var search: null

    QtObject {
        id: runner
        property int revision: 1
        function commandAvailable(name) { return true; }
    }

    Component {
        id: searchComponent
        Services.Search {}
    }

    function resultPayload(query) {
        return JSON.stringify([{
            kind: "recent-file",
            path: "/tmp/" + query + ".txt",
            title: query,
            subtitle: query,
            mtime: 1
        }]);
    }

    function init() {
        TestIo.TestProcessRegistry.reset();
        TestIo.TestProcessRegistry.commandRules = [
            { match: "alpha", delayMs: 300, payload: resultPayload("alpha"), code: 0 },
            { match: "beta", delayMs: 20, payload: resultPayload("beta"), code: 0 },
            { match: "gamma", delayMs: 300, payload: resultPayload("gamma"), code: 0 }
        ];
        search = searchComponent.createObject(testCase, {
            active: true,
            commandRunner: runner
        });
        verify(search !== null);
    }

    function cleanup() {
        if (search) {
            search.destroy();
            search = null;
        }
        TestIo.TestProcessRegistry.reset();
        wait(0);
    }

    function test_new_query_cancels_old_and_only_latest_applies() {
        search.resultsForQuery("alpha", 6);
        tryCompare(search, "activeTaskQuery", "alpha", 1000);

        search.resultsForQuery("beta", 6);
        compare(search.latestTaskQuery, "beta");
        tryCompare(search, "cachedTaskQuery", "beta", 2000);
        compare(search.cachedTaskEntries.length, 1);
        compare(search.cachedTaskEntries[0].title, "beta");
        compare(search.providerRevision, 1);

        wait(350);
        compare(search.cachedTaskQuery, "beta");
        compare(search.providerRevision, 1);
    }

    function test_closing_ui_cancels_scan_and_blocks_late_publish() {
        search.resultsForQuery("beta", 6);
        tryCompare(search, "cachedTaskQuery", "beta", 2000);
        var revision = search.providerRevision;

        search.resultsForQuery("gamma", 6);
        tryCompare(search, "activeTaskQuery", "gamma", 1000);
        search.active = false;
        compare(search.pendingTaskQuery, "");
        compare(search.latestTaskQuery, "");
        tryCompare(search, "activeTaskQuery", "", 1000);

        wait(350);
        compare(search.cachedTaskQuery, "beta");
        compare(search.providerRevision, revision);
    }
}
