from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAGES = ROOT / "components" / "settings" / "pages"
SLIDER = ROOT / "components" / "settings" / "controls" / "TahoeSlider.qml"
NIRI_SETTINGS = ROOT / "services" / "NiriSettings.qml"
APPEARANCE = ROOT / "services" / "Appearance.qml"

NIRI_SLIDER_PAGES = (
    "DisplaysPage.qml",
    "KeyboardPage.qml",
    "MouseTouchpadPage.qml",
    "NiriAnimationsPage.qml",
    "NiriGlassPage.qml",
    "NiriInputPage.qml",
    "NiriLayoutPage.qml",
)


def function_body(source: str, name: str) -> str:
    marker = f"function {name}("
    start = source.find(marker)
    if start < 0:
        raise AssertionError(f"missing function {name}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace : index + 1]
    raise AssertionError(f"unclosed function {name}")


class SettingsSliderCommitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.slider = SLIDER.read_text(encoding="utf-8")
        cls.niri = NIRI_SETTINGS.read_text(encoding="utf-8")
        cls.appearance = APPEARANCE.read_text(encoding="utf-8")

    def test_shared_slider_separates_preview_from_commit(self) -> None:
        self.assertIn("signal userPreview(real value)", self.slider)
        self.assertIn("signal userCommit(real value)", self.slider)
        self.assertIn("dragging ? dragValue : clampRatio(value)", self.slider)
        self.assertIn("slider.userPreview(slider.dragValue)", self.slider)
        self.assertEqual(self.slider.count("slider.userCommit(slider.dragValue)"), 2)
        self.assertNotIn("signal userSet", self.slider)

    def test_all_niri_slider_writes_are_commit_only(self) -> None:
        combined = "\n".join(
            (PAGES / name).read_text(encoding="utf-8") for name in NIRI_SLIDER_PAGES
        )
        self.assertNotIn("onUserSet", combined)
        self.assertNotRegex(
            combined,
            re.compile(r"onUserPreview\s*:[^{]*\{[^}]*page\.(?:svc|niri)\.set", re.S),
        )
        self.assertGreaterEqual(combined.count("onUserCommit"), 35)

    def test_niri_reload_remains_owned_by_single_writer_exit(self) -> None:
        writer_block = self.niri[self.niri.index("id: writer") :]
        self.assertEqual(len(re.findall(r"^\s*id:\s*writer\s*$", self.niri, re.M)), 1)
        self.assertEqual(writer_block.count("root.applyNiriConfig();"), 1)
        self.assertIn("Sliders own their drag preview", self.niri)

    def test_color_temperature_commits_once_and_night_mode_coalesces(self) -> None:
        displays = (PAGES / "DisplaysPage.qml").read_text(encoding="utf-8")
        self.assertIn("page.appearance.setColorTemperature", displays)
        self.assertIn("onUserCommit", displays)
        self.assertNotIn("onUserPreview", displays)

        apply_body = function_body(self.appearance, "applyNightMode")
        flush_body = function_body(self.appearance, "flushNightModeApply")
        self.assertNotIn("execDetached", apply_body)
        self.assertIn("requestedNightModeKey", apply_body)
        self.assertIn("nightModeProcess.running", flush_body)
        self.assertEqual(self.appearance.count("id: nightModeProcess"), 1)


if __name__ == "__main__":
    unittest.main()
