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
        self.assertIn("gs.userPreview(v)", self.control_center)
        self.assertIn("gs.userCommit(value)", self.control_center)

    def test_external_value_follow_animates_without_drag_lag(self) -> None:
        slider = self.control_center.split("component GlassSlider: Item", 1)[1].split(
            "component UtilityButton: Item", 1
        )[0]
        fill = slider.split("id: sliderFillBar", 1)[1].split("TahoeSymbol {", 1)[0]
        shadow = slider.split("id: knobShadow", 1)[1].split("\n                    Rectangle {\n                        id: knob\n", 1)[0]

        for block, behavior in ((fill, "Behavior on width"), (shadow, "Behavior on x")):
            self.assertIn(behavior, block)
            self.assertIn("enabled: !dragArea.pressed && !gs.userDragging", block)
            self.assertIn("Motion.elementMove(root.settingsService)", block)
            self.assertIn("Motion.emphasizedDecel", block)

        self.assertIn("x: knobShadow.x", slider)
        self.assertIn("fillFollowAnimation.stop();", slider)
        self.assertIn("knobFollowAnimation.stop();", slider)
        self.assertLess(slider.index("fillFollowAnimation.stop();"), slider.index("gs.userDragging = true;"))
        self.assertLess(slider.index("knobFollowAnimation.stop();"), slider.index("gs.userDragging = true;"))

    def test_brightness_uses_preview_and_release_commit(self) -> None:
        self.assertIn("root.controlsService.previewBrightness(v)", self.control_center)
        self.assertIn("root.controlsService.commitBrightness(v)", self.control_center)
        self.assertNotIn("root.controlsService.setBrightness(v)", self.control_center)

    def test_brightness_hardware_writes_are_below_30_hz(self) -> None:
        self.assertIn("readonly property int brightnessWriteIntervalMs: 34", self.controls)
        self.assertIn("Date.now() - root.lastBrightnessWriteStartedAt", self.controls)
        self.assertIn("brightnessWriteThrottle.restart()", self.controls)
        self.assertEqual(self.controls.count("id: brightnessSetter"), 1)

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
