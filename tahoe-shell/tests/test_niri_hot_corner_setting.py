#!/usr/bin/env python3
"""Hot-corner overview setting contract tests.

用户需求（2026-08-12）：设置页加开关，暂时关闭「鼠标放到左上角自动打开
概览」。实现链路：
- niri 侧：`gestures.hot-corners`（top-left / off），由
  niri_settings_tool.py 读写（managed gestures 块）。
- shell 侧：NiriSettings.qml 镜像 `hotCornerOverviewEnabled` +
  `setHotCornerOverviewEnabled()` → writeField → helper 写 KDL →
  `niri msg action load-config-file` 热生效。
- UI 侧：MultitaskingPage（桌面与多任务）新增「概览」分区开关。

本文件锁定：QML 接线完整、配置源有 managed gestures 块、niri 侧热角
逻辑存在（防「开关写了但合成器不认」的假接线）。
"""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT.parent
NIRI_SETTINGS = ROOT / "services" / "NiriSettings.qml"
MULTITASKING = ROOT / "components" / "settings" / "pages" / "MultitaskingPage.qml"
PHASE0 = REPO_ROOT / "config" / "niri" / "tahoe-phase0.kdl"
NIRI_INPUT = REPO_ROOT / "niri" / "src" / "niri.rs"


class NiriHotCornerSettingContractTests(unittest.TestCase):
    def test_niri_settings_service_mirrors_and_writes(self) -> None:
        text = NIRI_SETTINGS.read_text(encoding="utf-8")
        self.assertIn("property bool hotCornerOverviewEnabled: true", text)
        self.assertIn("function setHotCornerOverviewEnabled(enabled)", text)
        # 写入走既有单一写路径（writeField → helper → niri reload）。
        self.assertIn('root.writeField("gestures.hot_corner_overview.enabled", next);', text)

    def test_niri_settings_applies_read_payload(self) -> None:
        text = NIRI_SETTINGS.read_text(encoding="utf-8")
        self.assertIn("function applyGestures(gestures)", text)
        self.assertIn("gestures.hot_corner_overview_enabled !== undefined", text)
        self.assertIn("root.hotCornerOverviewEnabled = !!gestures.hot_corner_overview_enabled;", text)
        # 读与写两条回灌路径都要消费 gestures 段。
        self.assertEqual(text.count("root.applyGestures(payload.gestures);"), 2)

    def test_multitasking_page_has_toggle_wired_to_service(self) -> None:
        text = MULTITASKING.read_text(encoding="utf-8")
        self.assertIn('title: "概览"', text)
        self.assertIn("左上角热区打开概览", text)
        self.assertIn("checkable: true", text)
        self.assertIn("checked: page.niri && page.niri.hotCornerOverviewEnabled", text)
        self.assertIn("page.niri.setHotCornerOverviewEnabled(checked)", text)
        self.assertIn("enabled: !!page.niri", text)

    def test_phase0_has_managed_gestures_block(self) -> None:
        text = PHASE0.read_text(encoding="utf-8")
        self.assertIn("// tahoe-managed: begin gestures", text)
        self.assertIn("// tahoe-managed: end gestures", text)
        self.assertIn("hot-corners {", text)
        self.assertIn("top-left", text)
        # 显式写角：避免 niri「无角时默认左上角」回退造成开关状态歧义。
        self.assertNotIn("hot-corners {", text.split("// tahoe-managed: end gestures", 1)[1])

    def test_niri_side_hot_corner_logic_exists(self) -> None:
        text = NIRI_INPUT.read_text(encoding="utf-8")
        self.assertIn("fn is_inside_hot_corner", text)
        self.assertIn("hot_corners.off", text)
        self.assertIn("hot_corners.top_left", text)


if __name__ == "__main__":
    unittest.main()
