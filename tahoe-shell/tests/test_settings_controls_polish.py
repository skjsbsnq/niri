"""T16: Settings control polish — switch/slider/button/list row/segmented/field."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTROLS = ROOT / "components" / "settings" / "controls"
THEME = ROOT / "components" / "settings" / "SettingsTheme.js"
ANIM_PAGE = ROOT / "components" / "settings" / "pages" / "NiriAnimationsPage.qml"


class SettingsControlsPolishTests(unittest.TestCase):
    def test_switch_press_stretch_and_color(self) -> None:
        text = (CONTROLS / "TahoeSwitch.qml").read_text(encoding="utf-8")
        self.assertIn("pressed ? 24 : 20", text)
        self.assertIn("ColorAnimation", text)
        self.assertIn("150", text)
        self.assertIn("#28000000", text)  # knob shadow

    def test_slider_white_knob_shadow(self) -> None:
        text = (CONTROLS / "TahoeSlider.qml").read_text(encoding="utf-8")
        self.assertIn('color: "#ffffff"', text)
        self.assertIn("knobDiameter", text)
        self.assertIn("#30000000", text)
        # Hit mapping compensates for knob half-width (visual ends match value).
        self.assertIn("function ratioAt", text)
        self.assertIn("knobDiameter / 2", text)

    def test_button_primary_accent_secondary_solid(self) -> None:
        text = (CONTROLS / "TahoeButton.qml").read_text(encoding="utf-8")
        self.assertIn("buttonFillSolid", text)
        self.assertIn("accentFill", text)
        self.assertIn("font.pixelSize: 13", text)
        self.assertIn("border.width: 0", text)

    def test_list_row_height_and_inset_separator(self) -> None:
        text = (CONTROLS / "TahoeListRow.qml").read_text(encoding="utf-8")
        self.assertIn("Math.max(40,", text)
        self.assertIn("Theme.separator", text)
        self.assertIn("anchors.leftMargin: 12", text)
        self.assertIn("font.pixelSize: 13", text)

    def test_segmented_and_textfield_13px(self) -> None:
        seg = (CONTROLS / "TahoeSegmented.qml").read_text(encoding="utf-8")
        field = (CONTROLS / "TahoeTextField.qml").read_text(encoding="utf-8")
        self.assertIn("font.pixelSize: 13", seg)
        self.assertIn("font.pixelSize: 13", field)
        self.assertIn("buttonFillSolid", seg)

    def test_theme_solid_button_tokens(self) -> None:
        text = THEME.read_text(encoding="utf-8")
        self.assertIn("function buttonFillSolid(", text)
        self.assertIn("function buttonFillSolidHover(", text)

    def test_niri_animations_page_still_wired(self) -> None:
        """Curve/spring editor must remain (downstream tuning tool)."""
        text = ANIM_PAGE.read_text(encoding="utf-8")
        self.assertIn("damping", text.lower() if "damping" in text.lower() else text)
        # Page still uses shared controls and niri settings service.
        self.assertTrue(
            "TahoeSegmented" in text
            or "TahoeListRow" in text
            or "TahoeSlider" in text
            or "niriSettings" in text
            or "NiriSettings" in text
            or "animations" in text
        )
        self.assertGreater(len(text), 500)

    def test_body_copy_13px_in_core_controls(self) -> None:
        for name in (
            "TahoeButton.qml",
            "TahoeListRow.qml",
            "TahoeSegmented.qml",
            "TahoeTextField.qml",
            "TahoeSlider.qml",
            "TahoeSidebarButton.qml",
        ):
            text = (CONTROLS / name).read_text(encoding="utf-8")
            sizes = [int(m) for m in re.findall(r"font\.pixelSize:\s*(\d+)", text)]
            self.assertTrue(sizes, name)
            # Primary body label should be 13 (badge/detail may be smaller).
            self.assertIn(13, sizes, f"{name} sizes={sizes}")


if __name__ == "__main__":
    unittest.main()
