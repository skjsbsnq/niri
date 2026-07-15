from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ISLAND = ROOT / "services" / "DynamicIsland.qml"
CONTROLS = ROOT / "services" / "Controls.qml"


def _function_body(src: str, name: str) -> str:
    marker = f"function {name}("
    start = src.find(marker)
    if start < 0:
        raise AssertionError(f"missing function {name}")
    brace = src.find("{", start)
    if brace < 0:
        raise AssertionError(f"missing body for {name}")
    depth = 0
    for index in range(brace, len(src)):
        char = src[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return src[brace : index + 1]
    raise AssertionError(f"unclosed function {name}")


def _compact(text: str) -> str:
    return re.sub(r"\s+", "", text)


class BrightnessZeroTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.island = ISLAND.read_text(encoding="utf-8")
        cls.controls = CONTROLS.read_text(encoding="utf-8")

    def test_handle_accepts_zero_and_rejects_nan(self) -> None:
        body = _function_body(self.island, "handleBrightnessChange")
        compact = _compact(body)
        self.assertIn("isFinite(brightnessSample)", compact)
        self.assertNotIn("if(!(brightness>0))return", compact)
        # Zero may present; disabled still updates baseline.
        self.assertIn("if(!root.islandEnabled)return", compact)
        self.assertIn('"kind": "brightness"', body)

    def test_capture_baseline_keeps_zero(self) -> None:
        body = _function_body(self.island, "captureOsdBaselines")
        compact = _compact(body)
        self.assertNotIn("lastBrightness=1.0", compact)
        self.assertIn("isFinite(brightnessSample)", compact)
        self.assertIn("Math.max(0,Math.min(1,brightnessSample))", compact)

    def test_set_brightness_allows_zero_percent_command(self) -> None:
        body = _function_body(self.controls, "setBrightness")
        compact = _compact(body)
        self.assertNotIn("Math.max(0.05", body)
        self.assertIn("Math.max(0,Math.min(1,sample))", compact)
        self.assertIn('brightnessctl","set",pct+"%"', compact)
        # Non-finite becomes 0 after clamp path.
        self.assertIn("if(!isFinite(sample))sample=0", compact)

    def test_set_brightness_value_accepts_zero(self) -> None:
        body = _function_body(self.controls, "setBrightnessValue")
        compact = _compact(body)
        self.assertIn("Math.max(0,Math.min(1,sample))", compact)
        self.assertIn("if(!isFinite(sample))sample=0", compact)

    def test_first_sample_and_unavailable_are_baseline_only(self) -> None:
        body = _function_body(self.island, "handleBrightnessChange")
        self.assertIn("brightnessTrackingReady = true", body)
        self.assertIn("brightnessAvailable", body)
        # presentOsdEntry only after tracking ready and island enabled.
        present_index = body.find("presentOsdEntry")
        ready_index = body.find("brightnessTrackingReady = true")
        self.assertGreater(present_index, ready_index)
        self.assertIn("if (!root.islandEnabled)", body)

    def test_repeated_same_value_deduped(self) -> None:
        body = _function_body(self.island, "handleBrightnessChange")
        self.assertIn("Math.abs(brightness - root.lastBrightness) < 0.005", body)

    def test_no_parallel_brightness_service(self) -> None:
        self.assertNotIn("BrightnessService", self.island)
        self.assertIn("controlsService.brightness", self.island)


if __name__ == "__main__":
    unittest.main()
