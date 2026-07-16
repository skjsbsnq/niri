#!/usr/bin/env python3
"""T21: shared Bluetooth lifecycle snapshots and island transient."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path


SHELL = Path(__file__).resolve().parents[1]
CONTROLS = SHELL / "services" / "Controls.qml"
ISLAND = SHELL / "services" / "DynamicIsland.qml"
REDUCER = SHELL / "services" / "DynamicIslandReducer.js"
CONTENT = SHELL / "components" / "DynamicIslandContent.qml"
OVERLAY = SHELL / "components" / "DynamicIslandOverlay.qml"
VIEW = SHELL / "components" / "DynamicIslandBluetoothView.qml"
QML_TEST = Path(__file__).with_name("tst_dynamic_island_bluetooth.qml")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class DynamicIslandBluetoothTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.controls = read(CONTROLS)
        cls.island = read(ISLAND)
        cls.reducer = read(REDUCER)
        cls.content = read(CONTENT)
        cls.overlay = read(OVERLAY)
        cls.view = read(VIEW)

    def test_controls_is_shared_owner_without_polling(self) -> None:
        self.assertIn("signal bluetoothConnectionEvent(var event)", self.controls)
        self.assertIn("bluetoothDeviceObservers", self.controls)
        self.assertIn("onStateChanged()", self.controls)
        self.assertIn('"connecting"', self.controls)
        self.assertIn('"connected"', self.controls)
        self.assertIn('"failed"', self.controls)
        self.assertIn('"disconnected"', self.controls)
        self.assertNotIn("bluetoothctl", self.controls)
        self.assertNotIn("BluetoothConnectionTracker", self.controls)

    def test_user_intent_is_recorded_before_connect_or_disconnect(self) -> None:
        connect = self.controls.index("function connectBluetoothDevice")
        disconnect = self.controls.index("function disconnectBluetoothDevice")
        self.assertLess(self.controls.index('setBluetoothConnectionIntent(d, "connect")', connect),
                        self.controls.index("d.connect", connect))
        self.assertLess(self.controls.index('setBluetoothConnectionIntent(d, "disconnect")', disconnect),
                        self.controls.index("d.disconnect", disconnect))

    def test_device_removal_uses_scalar_snapshot(self) -> None:
        destruction = re.search(
            r"Component\.onDestruction:\s*\{([\s\S]*?)\n\s*\}", self.controls
        )
        self.assertIsNotNone(destruction)
        body = destruction.group(1)
        self.assertIn("snapshotKey", body)
        self.assertIn("emitBluetoothConnectionSnapshot", body)
        self.assertNotIn("emitBluetoothConnectionEvent", body)
        self.assertNotIn("modelData", body)

    def test_reducer_has_bluetooth_priority_and_queue(self) -> None:
        self.assertIn('"transient_bluetooth"', self.reducer)
        self.assertIn('"bluetooth": 60', self.reducer)
        self.assertIn('case "SHOW_BLUETOOTH"', self.reducer)
        self.assertIn('effect("queueBluetoothEvent"', self.reducer)
        self.assertIn("function blocksBluetooth", self.reducer)

    def test_island_coalesces_same_device_and_pins_output(self) -> None:
        self.assertIn("function handleBluetoothConnectionEvent", self.island)
        self.assertIn("transientBluetoothDeviceKey === entry.deviceKey", self.island)
        self.assertIn("setEventOwnerOutput(entry.output", self.island)
        self.assertIn("entry.output = root.liveFocusedOutputName()", self.island)
        self.assertIn("root.eventOwnerOutput || entry.output", self.island)
        self.assertIn("pendingBluetoothEvent", self.island)
        self.assertIn("maybeShowPendingBluetooth", self.island)
        self.assertIn("!root.transientBluetoothUserInitiated", self.island)
        self.assertIn("function queueBluetoothEvent", self.island)
        self.assertIn("current.deviceKey === next.deviceKey", self.island)
        self.assertIn("never inherit the preempted Bluetooth", self.island)
        self.assertIn("onBluetoothConnectionEvent(event)", self.island)
        self.assertIn('case "transient_bluetooth"', self.island)

    def test_notification_priority_is_higher_than_bluetooth(self) -> None:
        values = {
            name: int(value)
            for name, value in re.findall(r'"([a-z_]+)":\s*(\d+)', self.reducer)
        }
        self.assertGreater(values["notification"], values["bluetooth"])
        self.assertGreater(values["timer_completion"], values["bluetooth"])

    def test_scene_is_single_event_not_device_list(self) -> None:
        self.assertIn("DynamicIslandBluetoothView", self.content)
        self.assertIn("bluetoothActive", self.content)
        self.assertIn("Quickshell.iconPath", self.view)
        self.assertIn("deviceName", self.view)
        self.assertNotIn("bluetoothDeviceEntries", self.view)
        self.assertNotIn("Repeater", self.view)

    def test_overlay_geometry_and_owner_binding(self) -> None:
        self.assertIn('case "transient_bluetooth"', self.overlay)
        self.assertIn("bluetoothDeviceName", self.overlay)
        self.assertIn("bluetoothDeviceIcon", self.overlay)
        self.assertIn("bluetoothKind: root.bluetoothKind", self.overlay)
        self.assertIn("transient_bluetooth", self.overlay)

    def test_reset_clears_pending_bluetooth(self) -> None:
        reset = re.search(r'case "RESET":([\s\S]*?)case "SHOW_TIME"', self.reducer)
        self.assertIsNotNone(reset)
        self.assertIn('effect("clearPendingBluetooth")', reset.group(1))

    def test_no_live_device_object_crosses_into_island(self) -> None:
        # The event payload contains scalar identity/display fields only.
        emit = re.search(r"function emitBluetoothConnectionEvent[\s\S]*?\n    }", self.controls)
        self.assertIsNotNone(emit)
        self.assertNotIn('"device":', emit.group(0))
        self.assertNotIn("modelData", self.island)

    def test_real_qml_bluetooth_arbitration_and_owner(self) -> None:
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(runner, "Qt 6 qmltestrunner is required")
        env = os.environ.copy()
        env.setdefault("QT_QPA_PLATFORM", "offscreen")
        local_qml = Path.home() / ".local" / "lib" / "qt6" / "qml"
        test_qml = SHELL / "tests" / "qml_imports"
        existing = env.get("QML2_IMPORT_PATH", "")
        paths = [str(test_qml), str(local_qml)]
        if existing:
            paths.append(existing)
        env["QML2_IMPORT_PATH"] = ":".join(paths)
        result = subprocess.run(
            [runner, "-input", str(QML_TEST)],
            cwd=SHELL,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
