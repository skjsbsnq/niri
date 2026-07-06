from __future__ import annotations

import importlib.util
import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
COMPONENTS_ROOT = SHELL_ROOT / "components"
MOTION_JS = COMPONENTS_ROOT / "Motion.js"
DESKTOP_SETTINGS_QML = SHELL_ROOT / "services" / "DesktopSettings.qml"
NIRI_SETTINGS_TOOL = SHELL_ROOT / "services" / "niri_settings_tool.py"

spec = importlib.util.spec_from_file_location("niri_settings_tool", NIRI_SETTINGS_TOOL)
assert spec and spec.loader
niri_settings_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(niri_settings_tool)


def qml_files() -> list[Path]:
    return sorted(COMPONENTS_ROOT.rglob("*.qml"))


class MotionTokenConvergenceTests(unittest.TestCase):
    def test_qml_components_do_not_inline_out_cubic_easing(self) -> None:
        offenders = [
            str(path.relative_to(SHELL_ROOT))
            for path in qml_files()
            if "Easing.OutCubic" in path.read_text(encoding="utf-8")
        ]

        self.assertEqual(offenders, [])

    def test_no_private_motion_token_files_were_added(self) -> None:
        token_like_files = sorted(
            path.relative_to(COMPONENTS_ROOT).as_posix()
            for path in COMPONENTS_ROOT.rglob("*.js")
            if re.search(r"(motion|animation|easing|transition)", path.name, re.IGNORECASE)
        )

        self.assertEqual(token_like_files, ["DynamicIslandMotion.js", "Motion.js"])

    def test_qml_motion_profiles_match_kdl_profile_names(self) -> None:
        motion_text = MOTION_JS.read_text(encoding="utf-8")
        desktop_text = DESKTOP_SETTINGS_QML.read_text(encoding="utf-8")
        profile_names = re.findall(r'"(fast|balanced|liquid|reduced)"\s*:', motion_text)

        self.assertEqual(set(profile_names), set(niri_settings_tool.MOTION_PROFILE_NAMES))
        self.assertIn('property string motionProfile: "balanced"', desktop_text)
        self.assertIn("function setMotionProfile(profile)", desktop_text)


if __name__ == "__main__":
    unittest.main()
