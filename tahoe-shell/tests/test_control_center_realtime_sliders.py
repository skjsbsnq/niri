from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTROL_CENTER = ROOT / "components" / "ControlCenter.qml"
CONTROLS = ROOT / "services" / "Controls.qml"
THEME = ROOT / "components" / "settings" / "SettingsTheme.js"


class ControlCenterRealtimeSliderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.control_center = CONTROL_CENTER.read_text(encoding="utf-8")
        cls.controls = CONTROLS.read_text(encoding="utf-8")
        cls.theme = THEME.read_text(encoding="utf-8")

    def test_slider_paints_pointer_value_during_drag(self) -> None:
        self.assertIn("property bool userDragging", self.control_center)
        self.assertIn("property real userValue", self.control_center)
        self.assertIn("gs.userDragging ? gs.userValue : gs.sourceValue", self.control_center)
        self.assertIn("gs.userValue = v", self.control_center)
        self.assertIn("gs.userSet(v)", self.control_center)

    def test_volume_write_is_optimistic_and_rejects_stale_echo(self) -> None:
        self.assertIn("property bool volumeWritePending", self.controls)
        self.assertIn("property real requestedVolume", self.controls)
        self.assertIn("root.volume = v", self.controls)
        self.assertIn("v - root.requestedVolume", self.controls)
        self.assertIn("audioWriteGuard", self.controls)

    def test_control_center_slider_fill_keeps_existing_palette(self) -> None:
        match = re.search(r"function sliderFill\(darkMode\)\s*\{([^}]*)\}", self.theme)
        self.assertIsNotNone(match)
        body = match.group(1)
        self.assertIn('"#d8e4f0"', body)
        self.assertIn('"#f2ffffff"', body)


if __name__ == "__main__":
    unittest.main()
