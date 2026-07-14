import QtQuick
import QtTest
import "../services" as Services
import Quickshell.Io as TestIo

TestCase {
    id: testCase
    name: "WeatherGeocodeRequestIdentity"
    when: windowShown

    property var weather: null
    property int finishedCount: 0
    property int failedCount: 0
    property string lastFailedMessage: ""

    Component {
        id: weatherComponent
        Services.Weather {}
    }

    function geocodePayload(name) {
        return JSON.stringify({
            results: [{
                name: name,
                latitude: 31.2,
                longitude: 121.5,
                country: "China",
                admin1: "Shanghai"
            }]
        });
    }

    function init() {
        TestIo.TestProcessRegistry.reset();
        finishedCount = 0;
        failedCount = 0;
        lastFailedMessage = "";
        weather = weatherComponent.createObject(testCase);
        verify(weather !== null);
        // Stop any auto-started location/forecast processes from service init.
        weather.updating = false;
        weather.clearLocationSearch();
        wait(20);
        TestIo.TestProcessRegistry.reset();
        weather.locationSearchFinished.connect(function() { finishedCount += 1; });
        weather.locationSearchFailed.connect(function(msg) {
            failedCount += 1;
            lastFailedMessage = String(msg || "");
        });
    }

    function cleanup() {
        if (weather) {
            weather.destroy();
            weather = null;
        }
        TestIo.TestProcessRegistry.reset();
        wait(0);
    }

    function test_async_failed_to_start_finishes_and_clears_loading() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "name=Alpha", failStart: true, delayMs: 40 }
        ];
        weather.searchLocations("Alpha");
        compare(weather.locationSearching, true);
        compare(weather.geocodeInFlightGeneration > 0, true);

        // Running is still true until the async FailedToStart timer fires.
        tryCompare(weather, "locationSearching", false, 1000);
        compare(weather.geocodeInFlightGeneration, 0);
        compare(failedCount, 1);
        compare(weather.locationSearchError, "城市搜索失败");
        compare(weather.locationSearchResults.length, 0);
    }

    function test_failed_to_start_with_pending_b_starts_latest() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "name=Alpha", failStart: true, delayMs: 80 },
            { match: "name=Bravo", delayMs: 30, payload: geocodePayload("Bravo"), code: 0 }
        ];
        weather.searchLocations("Alpha");
        compare(weather.locationSearching, true);
        var genA = weather.geocodeGeneration;

        // While A is still "running", queue B as latest pending.
        wait(20);
        weather.searchLocations("Bravo");
        compare(weather.geocodePending, true);
        compare(weather.geocodePendingQuery, "Bravo");
        compare(weather.geocodeGeneration > genA, true);

        tryCompare(weather, "locationSearching", false, 2000);
        compare(weather.locationSearchResults.length, 1);
        compare(weather.locationSearchResults[0].name, "Bravo");
        compare(finishedCount, 1);
        // Superseded A must not write a failure into B's generation; only B's success applies.
        compare(failedCount, 0);
        compare(weather.geocodeInFlightGeneration, 0);
        compare(weather.geocodePending, false);
    }

    function test_normal_exit_then_running_changed_does_not_double_fail() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "name=Charlie", delayMs: 40, payload: geocodePayload("Charlie"), code: 0 }
        ];
        weather.searchLocations("Charlie");
        tryCompare(weather, "locationSearching", false, 1000);
        compare(finishedCount, 1);
        compare(failedCount, 0);
        compare(weather.locationSearchResults[0].name, "Charlie");

        // After success, a late runningChanged(false) must not re-enter finish as failure.
        // The fake already emits running=false after exited; give an extra settle beat.
        wait(50);
        compare(finishedCount, 1);
        compare(failedCount, 0);
        compare(weather.locationSearching, false);
        compare(weather.geocodeInFlightGeneration, 0);
    }

    function test_cancel_a_late_then_b_success() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "name=Alpha", delayMs: 200, payload: geocodePayload("Alpha"), code: 0 },
            { match: "name=Bravo", delayMs: 40, payload: geocodePayload("Bravo"), code: 0 }
        ];
        weather.searchLocations("Alpha");
        wait(20);
        weather.searchLocations("Bravo");
        // Cancelling A sets pending; B must become the only applied result.
        tryCompare(weather, "locationSearching", false, 2000);
        compare(weather.locationSearchResults.length, 1);
        compare(weather.locationSearchResults[0].name, "Bravo");
        compare(finishedCount, 1);
        compare(failedCount, 0);
    }
}
