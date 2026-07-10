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

    def test_motion_exports_tahoe_motion_2_spring_vocabulary(self) -> None:
        text = MOTION_JS.read_text(encoding="utf-8")

        expected = {
            "springSnappy": ("4.2", "0.30", "damping-ratio=0.88 stiffness=500"),
            "springSmooth": ("3.0", "0.40", "damping-ratio=1.0 stiffness=250"),
            "springPanel": ("2.5", "0.28", "damping-ratio=0.85 stiffness=160"),
            "springBouncy": ("2.5", "0.22", "damping-ratio=0.70 stiffness=160"),
        }
        for token, (spring, damping, niri_params) in expected.items():
            block = re.search(rf"var {token} = \{{(.*?)\}};", text, re.S)
            self.assertIsNotNone(block, f"missing spring token {token}")
            assert block
            body = block.group(1)
            self.assertIn(f"spring: {spring}", body, token)
            self.assertIn(f"damping: {damping}", body, token)
            # The niri-side KDL annotation must stay in sync with the QML group.
            self.assertIn(niri_params, body, token)

    def test_motion_exports_press_tokens_as_single_outlet(self) -> None:
        text = MOTION_JS.read_text(encoding="utf-8")

        self.assertIn("var pressDuration = 120;", text)
        self.assertIn("var pressScale = 0.96;", text)
        self.assertIn("var pressEasing = QtQuick.Easing.OutQuad;", text)
        self.assertIn('return normalizedProfileName(settingsService) === "reduced";', text)
        self.assertIn("function pressDurationFor(settingsService)", text)
        self.assertIn("function pressScaleFor(settingsService, pressed)", text)

    def test_phase_b_press_feedback_uses_motion_single_outlet(self) -> None:
        required_counts = {
            "TopBar.qml": 11,
            "Tray.qml": 1,
            "Dock.qml": 2,
            "WindowButton.qml": 1,
            "DockMinimizedWindow.qml": 1,
            "ControlCenter.qml": 8,
            "Spotlight.qml": 2,
            "Launchpad.qml": 2,
            "MenuPopup.qml": 1,
            "AppMenuPopup.qml": 2,
            "TrayMenu.qml": 1,
            "DockAppMenu.qml": 1,
            "DockWindowMenu.qml": 1,
            "ProcessMenu.qml": 1,
            "settings/controls/TahoeButton.qml": 1,
            "settings/controls/TahoeListRow.qml": 1,
            "settings/controls/TahoeSidebarButton.qml": 1,
            "settings/controls/TahoeSegmented.qml": 1,
        }

        for relative, expected_count in required_counts.items():
            with self.subTest(component=relative):
                text = (COMPONENTS_ROOT / relative).read_text(encoding="utf-8")
                self.assertEqual(text.count("Motion.pressScaleFor"), expected_count)
                self.assertIn("Motion.pressDurationFor", text)

    def test_glass_panel_press_drives_material_interaction(self) -> None:
        text = (COMPONENTS_ROOT / "GlassPanel.qml").read_text(encoding="utf-8")

        self.assertIn("property bool pressInteractionEnabled: true", text)
        self.assertIn("PointHandler {", text)
        self.assertIn("target: null", text)
        self.assertIn("Math.max(root.interaction, pressHandler.active ? 1 : 0)", text)

    def test_topbar_hover_capsules_do_not_use_outline_token(self) -> None:
        text = (COMPONENTS_ROOT / "TopBar.qml").read_text(encoding="utf-8")

        self.assertNotIn("buttonBorder", text)


if __name__ == "__main__":
    unittest.main()
