#!/usr/bin/env python3
"""BatteryWidget layout regression guard.

A8：电池小部件全面重做为 macOS Sonoma 布局 —— 居中列
（电池图标 → 大百分比 → 状态说明），颜色随深浅外观自适应
（充电绿 / 低电量红 / 常规主色），图标与百分比随卡片宽度缩放
（small ~27/34px、medium/large 封顶 40/44px）。
锁点：
- 居中列锚链（Column 整体 centerIn，不再用 cellSize 绝对偏移）。
- 数据逻辑（latchSnapshot / live 门控 / available/charging/onBattery）
  保持 A2–A3 既有语义。
- 视觉块不得出现 cellSize 绝对偏移或硬编码白字。
"""

from __future__ import annotations

import unittest
from pathlib import Path

SHELL_ROOT = Path(__file__).resolve().parents[1]
WIDGET = SHELL_ROOT / "components" / "widgets" / "BatteryWidget.qml"


class BatteryWidgetLayoutTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = WIDGET.read_text(encoding="utf-8")

    def test_macos_centered_column_icon_percent_caption(self) -> None:
        text = self.text
        # 居中列：图标 → 大百分比 → 状态说明（A8 macOS 布局）。
        self.assertIn("Column {", text)
        self.assertIn("anchors.centerIn: parent", text)
        # 电池轮廓 + bolt 叠加（字形不变，尺寸随宽度缩放）。
        self.assertIn('name: "\\ue1db"', text)
        self.assertIn('name: root.charging ? "\\ue1a3" : "\\ue1a4"', text)
        self.assertIn("readonly property real iconSize: Math.min(40, Math.max(26, Math.round(root.width * 0.16)))", text)
        # 大百分比 Semibold，随宽度缩放封顶 44。
        self.assertIn("readonly property real percentSize: Math.min(44, Math.max(30, Math.round(root.width * 0.2)))", text)
        self.assertIn("font.weight: Font.DemiBold", text)
        # 状态说明 12px secondary（不再按 cellSize 缩放）。
        self.assertIn("font.pixelSize: 12", text)
        self.assertIn("color: root.textSecondary", text)

    def test_adaptive_colors(self) -> None:
        text = self.text
        # 低电量红 / 充电绿 / 常规主色，深浅外观各一套（macOS 系统色）。
        self.assertIn('root.darkMode ? "#ff453a" : "#ff3b30"', text)
        self.assertIn('root.darkMode ? "#30d158" : "#34c759"', text)
        self.assertIn("return root.textPrimary;", text)
        # 不得硬编码白字（浅色外观下会白字白底不可读）。
        self.assertNotIn('color: "#ffffff"', text)

    def test_data_logic_preserved(self) -> None:
        text = self.text
        # A2/A3 快照/门控语义保持不变。
        self.assertIn("readonly property bool live: root.dataRefreshActive", text)
        self.assertIn("function latchSnapshot()", text)
        self.assertIn("onLiveChanged", text)
        self.assertIn("readonly property int percentage:", text)
        self.assertIn("readonly property bool charging:", text)
        self.assertIn("readonly property bool onBattery:", text)

    def test_no_cell_size_absolute_offsets_in_visual_block(self) -> None:
        # 旧实现用 cellSize 绝对偏移把元素推到一起；A8 改为居中列 +
        # 宽度比例缩放，视觉块不得再出现 cellSize / verticalCenterOffset。
        visual = self.text[self.text.index("// ---- 视觉"):]
        for fragment in ("cellSize * 0.42", "cellSize * 0.45", "cellSize * 0.15",
                         "cellSize * 0.62", "cellSize * 0.22", "cellSize * 0.36",
                         "verticalCenterOffset", "root.cellSize"):
            self.assertNotIn(fragment, visual, msg=fragment)


if __name__ == "__main__":
    unittest.main()
