import QtQuick
import QtTest
import "../services" as Services
import Quickshell.Io as TestIo

TestCase {
    id: testCase
    name: "AppsDefaultsFingerprint"
    when: windowShown

    property var settings: null
    property string fingerprint: "fp-a"

    QtObject {
        id: runner
        property int revision: 1
        function refreshDependencies() {}
        function appsDefaultsFingerprintCommand() {
            return ["test-defaults", "fingerprint", "0",
                JSON.stringify({ status: "ok", complete: true, fingerprint: testCase.fingerprint }), "0"];
        }
        function appsDefaultsProbeCommand() {
            return ["test-defaults", "probe", "0",
                JSON.stringify({
                    status: "ok",
                    detail: "full-" + testCase.fingerprint,
                    fingerprint: testCase.fingerprint,
                    categories: [{ id: "web" }],
                    desktopMeta: {}
                }), "0"];
        }
        function appsPermissionsCommand(desktopId) {
            return ["test-permissions", String(desktopId || "")];
        }
    }

    Component {
        id: settingsComponent
        Services.AppsSettings {}
    }

    function init() {
        fingerprint = "fp-a";
        TestIo.TestProcessRegistry.reset();
        settings = settingsComponent.createObject(testCase, {
            active: true,
            appsService: null,
            commandRunner: runner
        });
        verify(settings !== null);
        tryCompare(settings, "defaultsRefreshing", false, 2000);
        compare(settings.defaultsHavePayload, true);
        compare(TestIo.TestProcessRegistry.startedIds.join(","), "fingerprint,probe");
    }

    function cleanup() {
        if (settings) {
            settings.destroy();
            settings = null;
        }
        TestIo.TestProcessRegistry.reset();
        wait(0);
    }

    function test_same_fingerprint_skips_full_probe() {
        TestIo.TestProcessRegistry.startedIds = [];
        settings.refreshDefaults();
        tryCompare(settings, "defaultsRefreshing", false, 1000);
        compare(TestIo.TestProcessRegistry.startedIds.join(","), "fingerprint");
        compare(settings.defaultsDetail, "full-fp-a");
    }

    function test_changed_fingerprint_runs_one_full_probe() {
        TestIo.TestProcessRegistry.startedIds = [];
        fingerprint = "fp-b";
        settings.refreshDefaults();
        tryCompare(settings, "defaultsRefreshing", false, 2000);
        compare(TestIo.TestProcessRegistry.startedIds.join(","), "fingerprint,probe");
        compare(settings.defaultsFingerprint, "fp-b");
        compare(settings.defaultsDetail, "full-fp-b");
    }

    function test_inactive_cancels_fingerprint_probe() {
        TestIo.TestProcessRegistry.startedIds = [];
        TestIo.TestProcessRegistry.commandRules = [
            { match: "fingerprint", delayMs: 300,
              payload: JSON.stringify({ status: "ok", complete: true, fingerprint: "fp-c" }), code: 0 }
        ];
        fingerprint = "fp-c";
        settings.refreshDefaults();
        compare(settings.defaultsRefreshing, true);
        settings.active = false;
        compare(settings.defaultsRefreshing, false);
        compare(settings.defaultsProbeMode, "");
        wait(350);
        compare(settings.defaultsFingerprint, "fp-a");
        compare(TestIo.TestProcessRegistry.startedIds.join(","), "fingerprint");
    }
}
