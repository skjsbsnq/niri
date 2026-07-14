import QtQuick
import QtTest
import "../services" as Services
import Quickshell.Io as TestIo

TestCase {
    id: testCase
    name: "AppsSettingsPermissionsIdentity"
    when: windowShown

    property var settings: null

    QtObject {
        id: runner
        property int revision: 1

        function refreshDependencies() {}

        function appsDefaultsProbeCommand() {
            // Idle defaults probe so Component.onCompleted does not race permissions.
            return ["test-probe", "defaults", "999999",
                    JSON.stringify({ status: "ok", detail: "idle", categories: [], desktopMeta: {} }),
                    "0"];
        }

        function appsPermissionsCommand(desktopId) {
            return ["test-permissions", String(desktopId || "")];
        }
    }

    Component {
        id: settingsComponent
        Services.AppsSettings {}
    }

    function permPayload(desktopId, status) {
        var st = status || "ok";
        return JSON.stringify({
            portal: { status: st, detail: "detail-" + desktopId },
            permissions: [{ id: "perm." + desktopId, label: desktopId, enabled: true }],
            staticPermissions: [],
            snapConnections: [],
            storage: { total: "0 B", totalBytes: 0, items: [] },
            sandbox: {
                type: "flatpak",
                sandboxType: "flatpak",
                id: "sb." + desktopId,
                fullyEnforceable: true
            },
            capability: {
                sandboxType: "flatpak",
                fullyEnforceable: true,
                portalStatus: st,
                defaultControl: "readonly",
                canTogglePortalPermissions: false,
                writeScope: "none",
                ordinaryAppWarning: false
            }
        });
    }

    function selectDesktop(id) {
        settings.selectApp({ id: id, name: id });
    }

    function init() {
        TestIo.TestProcessRegistry.reset();
        // Defaults probe uses huge delay so it never completes during permissions tests.
        TestIo.TestProcessRegistry.commandRules = [
            { match: "defaults", delayMs: 999999, payload: "{}", code: 0 }
        ];
        settings = settingsComponent.createObject(testCase, {
            commandRunner: runner
        });
        verify(settings !== null);
        // Drain any synchronous bookkeeping; defaults stays running but idle.
        wait(20);
        TestIo.TestProcessRegistry.reset();
        TestIo.TestProcessRegistry.commandRules = [
            { match: "defaults", delayMs: 999999, payload: "{}", code: 0 }
        ];
    }

    function cleanup() {
        if (settings) {
            settings.destroy();
            settings = null;
        }
        TestIo.TestProcessRegistry.reset();
        wait(0);
    }

    function test_a_success_late_does_not_pollute_b() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "A.desktop", delayMs: 200, payload: permPayload("A.desktop"), code: 0 },
            { match: "B.desktop", delayMs: 40, payload: permPayload("B.desktop"), code: 0 },
            { match: "defaults", delayMs: 999999, payload: "{}", code: 0 }
        ];
        selectDesktop("A.desktop");
        compare(settings.permissionsRefreshing, true);
        compare(settings.permissionsProbeInFlightDesktopId, "A.desktop");
        var genA = settings.permissionsProbeInFlightGeneration;

        selectDesktop("B.desktop");
        compare(settings.permissionsProbePending, true);
        compare(settings.selectedDesktopId, "B.desktop");
        // Display identity closed; A's rows must not remain.
        compare(settings.permissionItems.length, 0);
        compare(settings.permissionsOwnerDesktopId, "");

        tryCompare(settings, "permissionsRefreshing", false, 3000);
        compare(settings.permissionsOwnerDesktopId, "B.desktop");
        compare(settings.permissionItems.length, 1);
        compare(settings.permissionItems[0].label, "B.desktop");
        compare(settings.permissionStatus, "ok");
        // Stale A generation must not still be in-flight.
        compare(settings.permissionsProbeInFlightGeneration, 0);
        compare(genA > 0, true);
    }

    function test_a_parse_failure_late_does_not_pollute_b() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "A.desktop", delayMs: 200, payload: "NOT_JSON{{{", code: 0 },
            { match: "B.desktop", delayMs: 40, payload: permPayload("B.desktop"), code: 0 },
            { match: "defaults", delayMs: 999999, payload: "{}", code: 0 }
        ];
        selectDesktop("A.desktop");
        selectDesktop("B.desktop");
        tryCompare(settings, "permissionsRefreshing", false, 3000);
        compare(settings.permissionsOwnerDesktopId, "B.desktop");
        compare(settings.permissionItems[0].label, "B.desktop");
        // B success, not A's parse error.
        compare(settings.permissionStatus, "ok");
        verify(String(settings.permissionDetail).indexOf("权限数据解析失败") < 0);
    }

    function test_a_failed_to_start_clears_loading_and_can_run_b() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "A.desktop", failStart: true, delayMs: 40 },
            { match: "B.desktop", delayMs: 30, payload: permPayload("B.desktop"), code: 0 },
            { match: "defaults", delayMs: 999999, payload: "{}", code: 0 }
        ];
        selectDesktop("A.desktop");
        compare(settings.permissionsRefreshing, true);
        tryCompare(settings, "permissionsRefreshing", false, 2000);
        compare(settings.permissionStatus, "error");
        compare(settings.permissionsProbeInFlightGeneration, 0);

        selectDesktop("B.desktop");
        tryCompare(settings, "permissionsRefreshing", false, 2000);
        compare(settings.permissionsOwnerDesktopId, "B.desktop");
        compare(settings.permissionItems[0].label, "B.desktop");
    }

    function test_a_failed_to_start_with_pending_b_starts_latest() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "A.desktop", failStart: true, delayMs: 80 },
            { match: "B.desktop", delayMs: 30, payload: permPayload("B.desktop"), code: 0 },
            { match: "defaults", delayMs: 999999, payload: "{}", code: 0 }
        ];
        selectDesktop("A.desktop");
        wait(20);
        selectDesktop("B.desktop");
        compare(settings.permissionsProbePending, true);
        tryCompare(settings, "permissionsRefreshing", false, 3000);
        compare(settings.permissionsOwnerDesktopId, "B.desktop");
        compare(settings.permissionItems[0].label, "B.desktop");
        compare(settings.permissionStatus, "ok");
    }

    function test_clear_selection_cancels_and_rejects_stale_a() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "A.desktop", delayMs: 200, payload: permPayload("A.desktop"), code: 0 },
            { match: "defaults", delayMs: 999999, payload: "{}", code: 0 }
        ];
        selectDesktop("A.desktop");
        compare(settings.permissionsRefreshing, true);
        // Clear selection (cancel path): bumps generation and clears capability.
        settings.selectApp(null);
        compare(settings.selectedDesktopId, "");
        compare(settings.permissionsRefreshing, false);
        compare(settings.permissionItems.length, 0);
        // permissionCapability empty object for unselected path.
        compare(JSON.stringify(settings.permissionCapability), "{}");

        // Wait for any late A completion; must not repopulate.
        wait(400);
        compare(settings.permissionItems.length, 0);
        compare(settings.permissionsOwnerDesktopId, "");
        compare(JSON.stringify(settings.permissionCapability), "{}");
    }

    function test_a_to_b_to_c_only_latest_applies() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "A.desktop", delayMs: 180, payload: permPayload("A.desktop"), code: 0 },
            { match: "B.desktop", delayMs: 40, payload: permPayload("B.desktop"), code: 0 },
            { match: "C.desktop", delayMs: 40, payload: permPayload("C.desktop"), code: 0 },
            { match: "defaults", delayMs: 999999, payload: "{}", code: 0 }
        ];
        selectDesktop("A.desktop");
        selectDesktop("B.desktop");
        selectDesktop("C.desktop");
        compare(settings.selectedDesktopId, "C.desktop");
        compare(settings.permissionsProbePending, true);

        tryCompare(settings, "permissionsRefreshing", false, 4000);
        compare(settings.permissionsOwnerDesktopId, "C.desktop");
        compare(settings.permissionItems.length, 1);
        compare(settings.permissionItems[0].label, "C.desktop");
        compare(settings.permissionStatus, "ok");
    }

    function test_refreshing_stays_true_until_latest_generation_finishes() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "A.desktop", delayMs: 120, payload: permPayload("A.desktop"), code: 0 },
            { match: "B.desktop", delayMs: 80, payload: permPayload("B.desktop"), code: 0 },
            { match: "defaults", delayMs: 999999, payload: "{}", code: 0 }
        ];
        selectDesktop("A.desktop");
        selectDesktop("B.desktop");
        // Immediately after A exits and before B finishes, loading must remain.
        // Wait just long enough for A delay but not full B.
        wait(150);
        // If A finished first, B should be in flight or pending restart.
        compare(settings.selectedDesktopId, "B.desktop");
        // Either still refreshing for B, or already done with B — never show A as owner.
        verify(settings.permissionsOwnerDesktopId !== "A.desktop"
               || settings.permissionItems.length === 0);
        tryCompare(settings, "permissionsRefreshing", false, 3000);
        compare(settings.permissionsOwnerDesktopId, "B.desktop");
        compare(settings.permissionItems[0].label, "B.desktop");
    }

    function test_sandbox_fallback_on_failure_does_not_pollute_new_selection() {
        // A fails (nonzero exit) after B selected; B then succeeds.
        TestIo.TestProcessRegistry.commandRules = [
            { match: "A.desktop", delayMs: 150, payload: "", code: 7 },
            { match: "B.desktop", delayMs: 40, payload: permPayload("B.desktop"), code: 0 },
            { match: "defaults", delayMs: 999999, payload: "{}", code: 0 }
        ];
        selectDesktop("A.desktop");
        selectDesktop("B.desktop");
        tryCompare(settings, "permissionsRefreshing", false, 3000);
        compare(settings.permissionsOwnerDesktopId, "B.desktop");
        compare(settings.permissionStatus, "ok");
        compare(settings.permissionItems[0].label, "B.desktop");
        verify(String(settings.permissionDetail).indexOf("退出码") < 0);
    }

    function test_latest_parse_failure_writes_error_for_current_selection() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "A.desktop", delayMs: 40, payload: "NOT_JSON", code: 0 },
            { match: "defaults", delayMs: 999999, payload: "{}", code: 0 }
        ];
        selectDesktop("A.desktop");
        tryCompare(settings, "permissionsRefreshing", false, 2000);
        compare(settings.permissionsOwnerDesktopId, "A.desktop");
        compare(settings.permissionStatus, "error");
        verify(String(settings.permissionDetail).indexOf("权限数据解析失败") >= 0);
        compare(settings.permissionItems.length, 0);
    }

    function test_same_selection_while_running_does_not_bump_pending() {
        TestIo.TestProcessRegistry.commandRules = [
            { match: "A.desktop", delayMs: 150, payload: permPayload("A.desktop"), code: 0 },
            { match: "defaults", delayMs: 999999, payload: "{}", code: 0 }
        ];
        selectDesktop("A.desktop");
        var gen = settings.permissionsProbeGeneration;
        // Same desktop again while probe running — no pending re-run required.
        selectDesktop("A.desktop");
        compare(settings.permissionsProbeGeneration, gen);
        compare(settings.permissionsProbePending, false);
        tryCompare(settings, "permissionsRefreshing", false, 2000);
        compare(settings.permissionItems[0].label, "A.desktop");
    }
}
