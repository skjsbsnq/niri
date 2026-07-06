from __future__ import annotations

import importlib.util
import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SHELL_ROOT.parent
POLICY = SHELL_ROOT / "docs" / "tahoe-motion-default-policy.md"
DESKTOP_SETTINGS = SHELL_ROOT / "services" / "DesktopSettings.qml"
NIRI_SETTINGS = SHELL_ROOT / "services" / "NiriSettings.qml"
MOTION_JS = SHELL_ROOT / "components" / "Motion.js"
NIRI_ANIMATIONS_PAGE = SHELL_ROOT / "components" / "settings" / "pages" / "NiriAnimationsPage.qml"
LAYER_ROADMAP = REPO_ROOT / "docs" / "layer-animation-motion-v2-roadmap.md"
TOOL_PATH = SHELL_ROOT / "services" / "niri_settings_tool.py"

spec = importlib.util.spec_from_file_location("niri_settings_tool", TOOL_PATH)
assert spec and spec.loader
niri_settings_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(niri_settings_tool)


class MotionDefaultPolicyTests(unittest.TestCase):
    def read(self, path: Path) -> str:
        return path.read_text(encoding="utf-8")

    def test_policy_documents_conservative_defaults_and_fallbacks(self) -> None:
        text = self.read(POLICY)

        for needle in (
            "| Default motion profile | `balanced` |",
            "| New shell state default for compositor layer animations | `false` / opt-in |",
            "| Conservative user profile | `reduced` |",
            "Do not remove any fallback until a later, explicit goal",
            '"compositorLayerAnimations": false',
            '"motionProfile": "balanced"',
            "--field animations.profile --value balanced",
        ):
            self.assertIn(needle, text)

    def test_source_defaults_match_policy(self) -> None:
        desktop = self.read(DESKTOP_SETTINGS)
        niri = self.read(NIRI_SETTINGS)
        motion = self.read(MOTION_JS)

        self.assertIn("property bool compositorLayerAnimations: false", desktop)
        self.assertIn('property string motionProfile: "balanced"', desktop)
        self.assertIn('property string motionProfile: "balanced"', niri)
        self.assertEqual(
            set(re.findall(r'"(fast|balanced|liquid|reduced)"\s*:', motion)),
            set(niri_settings_tool.MOTION_PROFILE_NAMES),
        )

    def test_settings_page_exposes_rollback_semantics(self) -> None:
        text = self.read(NIRI_ANIMATIONS_PAGE)

        self.assertIn("默认平衡：Tahoe 当前 KDL/QML token timing，可作为回退基线", text)
        self.assertIn("保守回退：layer transform 归零，保留必要 opacity feedback", text)
        self.assertIn("关闭时保留 QML 外层 fallback", text)

    def test_layer_roadmap_points_to_policy_decision(self) -> None:
        text = self.read(LAYER_ROADMAP)

        self.assertIn("2026-07-06 GOAL-10 decision", text)
        self.assertIn("Default motion profile remains `balanced`", text)
        self.assertIn("tahoe-shell/docs/tahoe-motion-default-policy.md", text)


if __name__ == "__main__":
    unittest.main()
