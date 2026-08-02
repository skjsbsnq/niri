#!/usr/bin/env python3
"""T-29 / F-11 + F-12: ControlCenter panel-level Escape and brightness error.

F-11: the panel had no root-level Escape — the only handler was the Wi-Fi PSK
field collapsing its row. The panel is now click-focusable while open and owns
QML focus, so Escape closes the panel (the PSK row still collapses first).
F-12: Controls.qml maintains brightnessErrorText, but no visible UI bound it;
in a VM / without a backlight the user only saw a disabled slider. The error
row now surfaces the service explanation.
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
CONTROL_CENTER = SHELL_ROOT / "components" / "ControlCenter.qml"
QML_PROBE = Path(__file__).with_name("tst_control_center_escape_brightness_error.qml")


class ControlCenterEscapeBrightnessStructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = CONTROL_CENTER.read_text(encoding="utf-8")

    def test_panel_is_click_focusable_while_open(self) -> None:
        self.assertIn("focusable: open", self.source)

    def test_panel_level_escape_catcher(self) -> None:
        self.assertIn('id: ccKeyboardFocusCatcher', self.source)
        self.assertIn('objectName: "controlCenterKeyboardFocusCatcher"', self.source)
        self.assertIn("focus: root.open", self.source)
        self.assertIn("Keys.onEscapePressed: root.closeRequested()", self.source)

    def test_wifi_psk_escape_still_collapses_row_first(self) -> None:
        # The focused PSK field keeps its own Escape: while it has focus its
        # handler runs first and accepts, so panel close only happens once the
        # row is closed — the panel-level handler must not replace it.
        self.assertIn("Keys.onEscapePressed: mp.expandedSsid = \"\"", self.source)

    def test_brightness_error_row_binds_service_text(self) -> None:
        self.assertIn("id: brightnessErrorText", self.source)
        self.assertIn('objectName: "brightnessErrorText"', self.source)
        self.assertIn("brightnessErrorText", self.source)
        self.assertIn(
            "String(root.controlsService.brightnessErrorText || \"\").length > 0",
            self.source,
        )
        self.assertIn('"亮度不可用："', self.source)

    def test_error_row_is_the_only_new_sibling_text(self) -> None:
        # The row must sit between the brightness and volume sliders and stay
        # out of the layout when there is nothing to explain.
        brightness = self.source.split('label: "显示"', 1)[1]
        volume = brightness.split('label: "声音"', 1)[0]
        self.assertIn("id: brightnessErrorText", volume)
        self.assertIn("visible:", volume)


class ControlCenterEscapeBrightnessRuntimeTests(unittest.TestCase):
    """Runs the production component under the Tahoe Quickshell runtime."""

    def _run_probe(self) -> subprocess.CompletedProcess:
        local_runner = Path.home() / ".local" / "bin" / "qs"
        runner = str(local_runner) if local_runner.is_file() else shutil.which("qs")
        self.assertIsNotNone(runner, "Tahoe Quickshell runtime is required")

        source = QML_PROBE.read_text(encoding="utf-8").replace(
            'property string panelSource: ""',
            f'property string panelSource: "{CONTROL_CENTER}"',
        )
        with tempfile.TemporaryDirectory(prefix="tahoe-cc-esc-") as tmp:
            probe = Path(tmp) / "shell.qml"
            probe.write_text(source, encoding="utf-8")
            return subprocess.run(
                [runner, "-p", str(probe)],
                cwd=SHELL_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=90,
                check=False,
            )

    def test_focusable_gate_and_brightness_error_row(self) -> None:
        result = self._run_probe()
        self.assertIn("CC_ESCAPE_BRIGHTNESS_OK", result.stdout, result.stdout)
        self.assertNotIn("CC_ESCAPE_BRIGHTNESS_FAIL", result.stdout, result.stdout)


if __name__ == "__main__":
    unittest.main()
