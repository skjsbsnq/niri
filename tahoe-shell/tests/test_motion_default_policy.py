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
LAYER_ROADMAP = REPO_ROOT / "docs" / "old" / "layer-animation-motion-v2-roadmap.md"
TOOL_PATH = SHELL_ROOT / "services" / "niri_settings_tool.py"

spec = importlib.util.spec_from_file_location("niri_settings_tool", TOOL_PATH)
assert spec and spec.loader
niri_settings_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(niri_settings_tool)


class MotionDefaultPolicyTests(unittest.TestCase):
    def read(self, path: Path) -> str:
        return path.read_text(encoding="utf-8")

    def test_policy_documents_single_outer_animation_owner(self) -> None:
        text = self.read(POLICY)

        for needle in (
            "| Default motion profile | `balanced` |",
            "| Tahoe surface outer animation owner | niri layer animation / default-on |",
            "| Conservative user profile | `reduced` |",
            "QML outer fallback for migrated Tahoe surfaces",
            "Remove",
            "--field animations.layer_animations_enabled --value false",
            "--field animations.profile --value balanced",
        ):
            self.assertIn(needle, text)

    def test_source_defaults_match_policy(self) -> None:
        desktop = self.read(DESKTOP_SETTINGS)
        niri = self.read(NIRI_SETTINGS)
        motion = self.read(MOTION_JS)

        self.assertNotIn("compositorLayerAnimations", desktop)
        self.assertIn("property bool layerAnimationsEnabled: true", niri)
        self.assertIn("function setLayerAnimationsEnabled(enabled)", niri)
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
        self.assertIn("Tahoe surface 的打开/关闭由 niri 统一处理", text)
        self.assertIn("关闭时外层显隐即时完成", text)
        self.assertNotIn("QML 外层 fallback", text)

    def test_balanced_profile_carries_motion_2_timings(self) -> None:
        motion = self.read(MOTION_JS)

        self.assertIn("var menuEnterDuration = 180;", motion)
        self.assertIn("var menuExitDuration = 160;", motion)
        self.assertIn("var panelEnterDuration = 320;", motion)
        self.assertIn("var panelExitDuration = 200;", motion)

    def test_reduced_profile_stays_minimal(self) -> None:
        motion = self.read(MOTION_JS)

        block = re.search(r'"reduced":\s*\{(.*?)\}', motion, re.S)
        self.assertIsNotNone(block)
        assert block
        values = [int(v) for v in re.findall(r":\s*(\d+)", block.group(1))]
        self.assertTrue(values)
        self.assertTrue(
            all(v <= 80 for v in values),
            f"reduced profile must stay minimal, got {values}",
        )

    def test_layer_roadmap_points_to_policy_decision(self) -> None:
        text = self.read(LAYER_ROADMAP)

        self.assertIn("2026-07-06 GOAL-10 decision", text)
        self.assertIn("Default motion profile remains `balanced`", text)
        self.assertIn("tahoe-shell/docs/tahoe-motion-default-policy.md", text)


if __name__ == "__main__":
    unittest.main()
