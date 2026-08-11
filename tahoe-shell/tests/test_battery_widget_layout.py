#!/usr/bin/env python3
"""BatteryWidget layout regression guard.

部署反馈：gap 内缩后电池小部件图标与百分比卡在一起。修复锁点 ——
锚链顺序排布：半透明电池轮廓贴顶（bolt 叠加其中心）、百分比锚在轮廓
下沿、状态文本贴底，任意实例高度下三者互不重叠；所有尺寸以 width/height
为界，不再用 cellSize 绝对偏移把元素挤向彼此。
"""

from __future__ import annotations

import unittest
from pathlib import Path

SHELL_ROOT = Path(__file__).resolve().parents[1]
WIDGET = SHELL_ROOT / "components" / "widgets" / "BatteryWidget.qml"


class BatteryWidgetLayoutTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = WIDGET.read_text(encoding="utf-8")

    def test_anchor_chain_shell_icon_percent_status(self) -> None:
        text = self.text
        # 轮廓贴顶，尺寸以宽为界（不随 cellSize 绝对放大）。
        self.assertIn("id: batteryShell", text)
        self.assertIn("anchors.top: parent.top", text)
        self.assertIn("Math.max(4, Math.round(root.height * 0.05))", text)
        self.assertIn("size: Math.min(52, Math.round(root.width * 0.58))", text)
        self.assertIn("opacity: 0.5", text)
        # bolt 叠加在轮廓中心。
        self.assertIn("anchors.centerIn: batteryShell", text)
        self.assertIn("size: Math.min(40, Math.round(root.width * 0.46))", text)
        # 百分比锚在轮廓下沿 + 固定间隙，永远在图标之下。
        self.assertIn("anchors.top: batteryShell.bottom", text)
        self.assertIn("Math.max(2, Math.round(root.height * 0.04))", text)
        self.assertIn("font.pixelSize: Math.min(26, Math.round(root.width * 0.26))", text)
        # 状态文本贴底。
        self.assertIn("anchors.bottom: parent.bottom", text)
        self.assertIn("anchors.bottomMargin: 2", text)

    def test_no_cell_size_absolute_offsets_in_visual_block(self) -> None:
        # 旧实现用 cellSize 绝对偏移（0.42/0.45/0.15/0.62/0.22/0.36 +
        # verticalCenterOffset）把元素推到一起，必须整体移除。切片覆盖
        # 整个视觉块（注释 → 百分比 Text），止于状态文本（stateText 字号
        # 按 cellSize 缩放属既有行为，不在此列，单独断言仍在）。
        visual = self.text[self.text.index("// ---- 视觉"):]
        visual = visual[: visual.index("anchors.bottom: parent.bottom")]
        for fragment in ("cellSize * 0.42", "cellSize * 0.45", "cellSize * 0.15",
                         "cellSize * 0.62", "cellSize * 0.22", "cellSize * 0.36",
                         "verticalCenterOffset"):
            self.assertNotIn(fragment, visual, msg=fragment)
        # 状态文本仍按 cellSize 缩放（既有行为，未被误删）。
        self.assertIn("Math.max(10, Math.round(root.cellSize * 0.16))", self.text)


if __name__ == "__main__":
    unittest.main()
