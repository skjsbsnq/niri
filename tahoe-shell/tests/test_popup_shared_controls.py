#!/usr/bin/env python3
"""R13 shared popup-control convergence and runtime contracts."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ROOT / "components"
CONTROLS = COMPONENTS / "controls"
QML_TEST = Path(__file__).with_name("tst_popup_shared_controls.qml")


class PopupSharedControlTests(unittest.TestCase):
    def test_inline_parallel_controls_are_retired(self) -> None:
        pattern = re.compile(
            r"component\s+(IconButton|PillButton|TextButton|ToggleSwitch|ConfirmButton)\b"
        )
        leftovers: list[str] = []
        for path in COMPONENTS.glob("*.qml"):
            if pattern.search(path.read_text(encoding="utf-8")):
                leftovers.append(path.name)
        self.assertEqual(leftovers, [])

    def test_target_surfaces_use_the_shared_suite(self) -> None:
        expectations = {
            "ClipboardPopup.qml": ("Controls.IconButton", "Controls.TextButton"),
            "WifiPopup.qml": ("Controls.ToggleSwitch", "Controls.TextButton"),
            "BatteryPopup.qml": ("Controls.ButtonSurface",),
            "FanPopup.qml": (
                "Controls.IconButton",
                "Controls.TextButton",
                "Controls.ToggleSwitch",
            ),
            "MenuPopup.qml": ("Controls.TextButton",),
            "NotificationCenter.qml": (
                "Controls.IconButton",
                "Controls.TextButton",
                "Controls.ToggleSwitch",
            ),
            "LeftSidebarWeather.qml": ("Controls.IconButton",),
        }
        for name, required in expectations.items():
            with self.subTest(component=name):
                text = (COMPONENTS / name).read_text(encoding="utf-8")
                self.assertIn('import "controls" as Controls', text)
                for signature in required:
                    self.assertIn(signature, text)

    def test_button_interaction_has_one_shared_owner(self) -> None:
        surface = (CONTROLS / "ButtonSurface.qml").read_text(encoding="utf-8")
        self.assertEqual(surface.count("MouseArea {"), 1)
        self.assertIn("Motion.pressScaleFor", surface)
        self.assertIn("Motion.pressDurationFor", surface)
        self.assertIn("Behavior on opacity", surface)
        self.assertIn("Behavior on color", surface)
        self.assertIn("ColorAnimation", surface)
        self.assertIn("property bool active", surface)
        self.assertIn("property bool prominent", surface)
        self.assertIn("property bool flat", surface)

        for name in ("IconButton.qml", "TextButton.qml"):
            text = (CONTROLS / name).read_text(encoding="utf-8")
            self.assertIn("ButtonSurface {", text)
            self.assertNotIn("MouseArea {", text)

    def test_switch_track_and_knob_share_motion_timing(self) -> None:
        switch = (CONTROLS / "ToggleSwitch.qml").read_text(encoding="utf-8")
        self.assertIn("Behavior on color", switch)
        self.assertIn("Behavior on x", switch)
        self.assertEqual(switch.count("Motion.elementMove(control.settingsService)"), 2)
        self.assertIn("Behavior on opacity", switch)
        self.assertIn("Motion.pressScaleFor", switch)
        self.assertIn("property bool interactive", switch)

    def test_battery_and_fan_value_changes_are_interpolated(self) -> None:
        battery = (COMPONENTS / "BatteryPopup.qml").read_text(encoding="utf-8")
        fan = (COMPONENTS / "FanPopup.qml").read_text(encoding="utf-8")
        self.assertIn("id: batteryFill", battery)
        self.assertIn("Behavior on width", battery)
        self.assertIn("Behavior on color", battery)
        self.assertIn("Math.max(4,", battery)
        self.assertIn("id: sliderFill", fan)
        self.assertIn("property bool userDragging", fan)
        self.assertIn("displayValue: userDragging ? userValue : sourceValue", fan)
        self.assertIn("enabled: !dragArea.pressed && !slider.userDragging", fan)
        self.assertIn("fillFollowAnimation.stop()", fan)

    def test_real_qml_controls_honor_enabled_and_emit_once(self) -> None:
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(runner, "Qt 6 qmltestrunner is required")
        env = os.environ.copy()
        env.setdefault("QT_QPA_PLATFORM", "offscreen")
        local_qml = Path.home() / ".local" / "lib" / "qt6" / "qml"
        test_qml = ROOT / "tests" / "qml_imports"
        paths = [str(test_qml), str(local_qml)]
        existing = env.get("QML2_IMPORT_PATH", "")
        if existing:
            paths.append(existing)
        env["QML2_IMPORT_PATH"] = ":".join(paths)
        result = subprocess.run(
            [runner, "-input", str(QML_TEST)],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    unittest.main()
