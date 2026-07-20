from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "shell.qml"
SERVICES = ROOT / "services"


class ServicePollingActivityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.shell = SHELL.read_text(encoding="utf-8")
        cls.sources = {
            name: (SERVICES / f"{name}.qml").read_text(encoding="utf-8")
            for name in (
                "CommandRunner",
                "Controls",
                "FanControl",
                "InputMethod",
                "NetworkSettings",
                "PowerProfiles",
                "Sound",
                "SystemFeatures",
            )
        }

    def test_shell_owns_one_shared_activity_condition(self) -> None:
        self.assertEqual(self.shell.count("readonly property bool servicePollingActive:"), 1)
        for surface in (
            "controlCenterOpen",
            "appMenuOpen",
            "applicationMenuOpen",
            "batteryPopupOpen",
            "wifiPopupOpen",
            "fanPopupOpen",
            "clipboardPopupOpen",
            "settingsPanelOpen",
            "leftSidebarOpen",
            "spotlightOpen",
            "launchpadOpen",
        ):
            self.assertIn(surface, self.shell)

        self.assertEqual(
            len(re.findall(r"^\s*CommandRunner\s*\{", self.shell, flags=re.MULTILINE)),
            1,
        )
        self.assertEqual(
            self.shell.count("pollingActive: shell.servicePollingActive"),
            len(self.sources),
        )

    def test_periodic_process_probes_are_activity_gated(self) -> None:
        timer_ids = {
            "CommandRunner": ("dependencyPollTimer",),
            "Controls": ("brightnessFallbackTimer", "wifiRefreshTimer"),
            "FanControl": ("statusRefreshTimer",),
            "InputMethod": ("statusPollTimer",),
            "NetworkSettings": ("vpnRefreshTimer",),
            "PowerProfiles": ("profileRefreshTimer",),
            "Sound": ("deviceRefreshTimer",),
            "SystemFeatures": ("featureRefreshTimer",),
        }

        for service, ids in timer_ids.items():
            source = self.sources[service]
            self.assertIn("property bool pollingActive", source, service)
            for timer_id in ids:
                self.assertRegex(
                    source,
                    rf"id:\s*{timer_id}\b[\s\S]{{0,220}}running:\s*root\.pollingActive",
                    service,
                )

        input_method = self.sources["InputMethod"]
        self.assertNotIn("root.pollingActive ? 1800 : 10000", input_method)
        self.assertNotRegex(
            input_method,
            r"id:\s*statusPollTimer\b[\s\S]{0,220}running:\s*true",
        )

    def test_closing_activity_cancels_inflight_probes(self) -> None:
        cancellation_markers = {
            "CommandRunner": "dependencyProbe.running = false",
            "Controls": "knownWifiProbe.running = false",
            "FanControl": "statusProbe.running = false",
            "InputMethod": "probe.running = false",
            "NetworkSettings": "vpnProbe.running = false",
            "PowerProfiles": "busProfileProbe.running = false",
            "Sound": "deviceProbe.running = false",
            "SystemFeatures": "probe.running = false",
        }
        for service, marker in cancellation_markers.items():
            source = self.sources[service]
            self.assertIn("onPollingActiveChanged", source, service)
            self.assertIn(marker, source, service)

        self.assertIn(
            "root.pollingActive && code !== 0 && !cliProfileProbe.running",
            self.sources["PowerProfiles"],
        )
        self.assertIn(
            'root.pollingActive && code !== 0 && root.deviceStatus !== "ok"',
            self.sources["Sound"],
        )

    def test_fan_control_bootstraps_availability_without_popup(self) -> None:
        """Top-bar fan icon must not stay grey until the popup opens.

        Continuous 5s polling stays gated on shell.servicePollingActive, but a
        one-shot bootstrap probe chain must run at startup so available/control
        state is known without user interaction.
        """
        fan = self.sources["FanControl"]
        self.assertIn("property bool bootstrapPending: true", fan)
        self.assertIn("readonly property bool canProbe: root.pollingActive || root.bootstrapPending", fan)
        self.assertIn("function finishBootstrap()", fan)
        # Continuous timer remains activity-gated (not canProbe).
        self.assertRegex(
            fan,
            r"id:\s*statusRefreshTimer\b[\s\S]{0,220}running:\s*root\.pollingActive",
        )
        # Startup always begins detectBackend when canProbe (bootstrap).
        self.assertIn("root.detectBackend()", fan)
        self.assertIn("if (root.canProbe)", fan)
        # Closing activity must not cancel an in-flight bootstrap chain.
        self.assertIn("else if (!root.bootstrapPending)", fan)
        # Probe gates use canProbe rather than only pollingActive.
        self.assertGreaterEqual(fan.count("root.canProbe"), 6)
        # Bootstrap must terminate on every probe terminal path + watchdog.
        for marker in (
            "bootstrapWatchdog",
            "bootstrapServiceRetryTimer",
            'state === "activating"',
            "root.finishBootstrap()",
        ):
            self.assertIn(marker, fan, marker)
        self.assertGreaterEqual(fan.count("root.finishBootstrap()"), 5)
        self.assertIn('name: "fan"', (ROOT / "components" / "TopBar.qml").read_text(encoding="utf-8"))

    def test_search_and_apps_follow_their_ui_lifecycle(self) -> None:
        self.assertIn("active: shell.spotlightOpen", self.shell)
        self.assertIn("active: shell.settingsPanelOpen", self.shell)


if __name__ == "__main__":
    unittest.main()
