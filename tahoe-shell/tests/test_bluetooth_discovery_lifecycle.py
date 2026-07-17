from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTROLS = ROOT / "services" / "Controls.qml"
CONTROL_CENTER = ROOT / "components" / "ControlCenter.qml"
BLUETOOTH_PAGE = ROOT / "components" / "settings" / "pages" / "BluetoothPage.qml"
SETTINGS_PANEL = ROOT / "components" / "SettingsPanel.qml"


class BluetoothDiscoveryLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.controls = CONTROLS.read_text(encoding="utf-8")
        cls.control_center = CONTROL_CENTER.read_text(encoding="utf-8")
        cls.bluetooth_page = BLUETOOTH_PAGE.read_text(encoding="utf-8")
        cls.settings_panel = SETTINGS_PANEL.read_text(encoding="utf-8")

    def test_controls_is_the_single_discovery_owner_with_timeout(self) -> None:
        self.assertIn("property var bluetoothDiscoveryOwners", self.controls)
        self.assertIn("readonly property int bluetoothDiscoveryTimeoutMs: 15000", self.controls)
        self.assertIn("function setBluetoothDiscoveryActive(owner, active)", self.controls)
        self.assertIn("function stopAllBluetoothDiscovery()", self.controls)
        self.assertIn("onTriggered: root.stopAllBluetoothDiscovery()", self.controls)
        self.assertEqual(len(re.findall(r"id:\s*bluetoothDiscoveryTimeout\b", self.controls)), 1)
        self.assertNotIn("function setBluetoothDiscovering", self.controls)
        self.assertNotIn("function toggleBluetoothDiscovering", self.controls)

    def test_control_center_releases_discovery_on_all_close_paths(self) -> None:
        self.assertIn('readonly property string bluetoothDiscoveryOwner: "control-center"', self.control_center)
        self.assertIn(
            "root.controlsService.setBluetoothDiscoveryActive(root.bluetoothDiscoveryOwner, true)",
            self.control_center,
        )
        self.assertGreaterEqual(
            self.control_center.count(
                "root.controlsService.setBluetoothDiscoveryActive(root.bluetoothDiscoveryOwner, false)"
            ),
            2,
        )
        self.assertIn(
            "mp.controls.toggleBluetoothDiscovery(root.bluetoothDiscoveryOwner)",
            self.control_center,
        )

    def test_settings_page_releases_its_owner_when_hidden(self) -> None:
        self.assertIn('readonly property string discoveryOwner: "settings-bluetooth"', self.bluetooth_page)
        self.assertIn("onActiveChanged", self.bluetooth_page)
        self.assertIn("Component.onDestruction", self.bluetooth_page)
        self.assertGreaterEqual(
            self.bluetooth_page.count(
                "page.controlsService.setBluetoothDiscoveryActive(page.discoveryOwner, false)"
            ),
            2,
        )
        self.assertIn('active: root.open && root.currentPageId === "bluetooth"', self.settings_panel)


if __name__ == "__main__":
    unittest.main()
