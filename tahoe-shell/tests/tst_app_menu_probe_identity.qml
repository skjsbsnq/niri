import QtQuick
import QtTest
import "../services" as Services
import Quickshell.Io as TestIo

TestCase {
    id: testCase
    name: "AppMenuProbeIdentity"

    property var service: null
    property real delayA: 0.12
    property real delayB: 0.20
    property real delayC: 0.01

    QtObject {
        id: windows
        property var focusedWindow: null
    }

    QtObject { id: windowA; property string id: "A"; property int pid: 101; property string appId: "app.A"; property string title: "Window A" }
    QtObject { id: windowB; property string id: "B"; property int pid: 202; property string appId: "app.B"; property string title: "Window B" }
    QtObject { id: windowC; property string id: "C"; property int pid: 303; property string appId: "app.C"; property string title: "Window C" }

    QtObject {
        id: apps
        function windowAppLabel(window) { return window ? window.appId : "desktop"; }
        function toplevelLabel(window) { return window ? window.title : "desktop"; }
    }

    QtObject {
        id: runner
        property int revision: -1
        property string failedStartId: ""

        function delayFor(id) {
            if (id === "A") return testCase.delayA;
            if (id === "B") return testCase.delayB;
            return testCase.delayC;
        }

        function appMenuProbeCommand(windowId, pid, appId, title) {
            if (String(windowId) === failedStartId)
                return ["test-failed-start", String(windowId),
                    String(Math.round(delayFor(String(windowId)) * 1000))];
            var payload = JSON.stringify({
                registrarAvailable: true,
                registrarOwner: "registrar",
                menuService: "svc." + windowId,
                menuPath: "/Menu/" + windowId,
                items: [{ id: 1, label: String(windowId), kind: "item", enabled: true }],
                status: "menu " + windowId,
                detail: "detail " + windowId
            });
            return ["test-probe", String(windowId),
                String(Math.round(delayFor(String(windowId)) * 1000)), payload, "0"];
        }
    }

    Component {
        id: serviceComponent
        Services.AppMenu {}
    }

    function windowObject(id) {
        return id === "A" ? windowA : id === "B" ? windowB : windowC;
    }

    function init() {
        delayA = 0.12;
        delayB = 0.20;
        delayC = 0.01;
        TestIo.TestProcessRegistry.reset();
        runner.failedStartId = "";
        windows.focusedWindow = windowObject("A");
        service = serviceComponent.createObject(testCase, {
            windowsService: windows,
            appsService: apps,
            commandRunner: runner
        });
        verify(service !== null);
        tryCompare(service, "probing", true, 1000);
    }

    function cleanup() {
        if (service) {
            service.destroy();
            service = null;
        }
        windows.focusedWindow = null;
        wait(0);
    }

    function test_stale_a_is_hidden_and_only_latest_b_applies() {
        delayB = 0.60;
        windows.focusedWindow = windowObject("B");
        wait(0);
        service.refresh();
        tryCompare(service, "probeTargetIdentity", JSON.stringify(["B", "202", "app.B"]), 1000);
        compare(service.nativeMenuAvailable, false);
        compare(service.nativeMenuService, "");
        compare(service.nativeMenuItems.length, 0);

        // A has exited and B is now in flight.  A must not clear B's loading.
        wait(180);
        compare(TestIo.TestProcessRegistry.startedIds.join(","), "A,B");
        compare(service.probing, true);
        compare(service.nativeMenuAvailable, false);

        tryCompare(service, "nativeMenuService", "svc.B", 1000);
        compare(service.nativeMenuItems[0].label, "B");
        compare(service.nativeMenuAvailable, true);
        compare(service.probing, false);
    }

    function test_a_to_b_to_c_runs_only_latest_pending_target() {
        windows.focusedWindow = windowObject("B");
        windows.focusedWindow = windowObject("C");
        wait(0);
        service.refresh();
        wait(0);
        compare(service.nativeMenuAvailable, false);
        tryCompare(service, "nativeMenuService", "svc.C", 1000);
        compare(TestIo.TestProcessRegistry.startedIds.join(","), "A,C");
        compare(service.nativeMenuItems[0].label, "C");
    }

    function test_same_target_refresh_coalesces_slow_probe() {
        var generation = service.probeGeneration;
        service.refresh();
        service.refresh();
        service.refresh();
        compare(service.probeGeneration, generation);
        compare(TestIo.TestProcessRegistry.startedIds.join(","), "A");
        tryCompare(service, "nativeMenuService", "svc.A", 1000);
        compare(service.nativeMenuAvailable, true);
    }

    function test_applied_a_is_invalidated_immediately_on_focus_b() {
        tryCompare(service, "nativeMenuService", "svc.A", 1000);
        compare(service.nativeMenuAvailable, true);

        windows.focusedWindow = windowObject("B");
        wait(0);
        service.refresh();
        tryCompare(service, "probeTargetIdentity", JSON.stringify(["B", "202", "app.B"]), 1000);
        compare(service.nativeMenuAvailable, false);
        compare(service.nativeMenuService, "");
        compare(service.nativeMenuPath, "");
        compare(service.nativeMenuItems.length, 0);
    }

    function test_failed_start_of_a_still_runs_latest_b() {
        service.destroy();
        TestIo.TestProcessRegistry.reset();
        runner.failedStartId = "A";
        windows.focusedWindow = windowObject("A");
        service = serviceComponent.createObject(testCase, {
            windowsService: windows,
            appsService: apps,
            commandRunner: runner
        });
        tryCompare(service, "probing", true, 1000);
        windows.focusedWindow = windowObject("B");
        wait(0);
        service.refresh();
        tryCompare(service, "nativeMenuService", "svc.B", 1000);
        compare(TestIo.TestProcessRegistry.startedIds.join(","), "A,B");
        compare(service.nativeMenuItems[0].label, "B");
        compare(service.probing, false);
    }

    function test_explicit_demand_same_identity_supersedes_inflight_probe() {
        // Recreate with a slow initial probe so demand lands while still in-flight.
        service.destroy();
        TestIo.TestProcessRegistry.reset();
        delayA = 0.50;
        windows.focusedWindow = windowObject("A");
        service = serviceComponent.createObject(testCase, {
            windowsService: windows,
            appsService: apps,
            commandRunner: runner
        });
        tryCompare(service, "probing", true, 1000);
        var genBefore = service.probeGeneration;
        service.refresh(true);
        compare(service.probePending, true);
        compare(service.probeGeneration > genBefore, true);
        // Multiple explicit demands coalesce to one pending follow-up generation.
        var genDemand = service.probeGeneration;
        service.refresh(true);
        service.refresh(true);
        compare(service.probeGeneration, genDemand);
        compare(service.probePending, true);

        tryCompare(service, "nativeMenuService", "svc.A", 3000);
        compare(service.nativeMenuItems[0].label, "A");
        compare(service.probePending, false);
        // Initial A + one demand follow-up (not one per demand).
        compare(TestIo.TestProcessRegistry.startedIds.join(","), "A,A");
        compare(service.probing, false);
    }

    function test_explicit_demand_during_a_then_focus_c_lands_on_c() {
        delayA = 0.50;
        delayC = 0.05;
        tryCompare(service, "probing", true, 1000);
        service.refresh(true);
        compare(service.probePending, true);
        windows.focusedWindow = windowObject("C");
        wait(0);
        service.refresh();
        tryCompare(service, "nativeMenuService", "svc.C", 2000);
        compare(service.nativeMenuItems[0].label, "C");
        compare(service.nativeMenuAvailable, true);
        // Final applied menu must be C, never a stale A demand result.
        verify(TestIo.TestProcessRegistry.startedIds.indexOf("C") >= 0);
    }

    function test_non_demand_same_identity_still_coalesces() {
        // Health/focus refresh without demand must not force pending follow-up.
        delayA = 0.30;
        tryCompare(service, "probing", true, 1000);
        var genBefore = service.probeGeneration;
        service.refresh();
        service.refresh();
        compare(service.probeGeneration, genBefore);
        compare(service.probePending, false);
        tryCompare(service, "nativeMenuService", "svc.A", 2000);
        compare(TestIo.TestProcessRegistry.startedIds.join(","), "A");
    }
}
