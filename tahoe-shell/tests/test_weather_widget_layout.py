#!/usr/bin/env python3
"""WeatherWidget vertical layout regression guard.

A3 部署反馈：「今日 x° ~ y°」行被顶部 Column 溢出压进/贴上底部逐时条。
修复锁点：
- 内容高度自适应（tempRowH 在 [28,38] 内 clamp，总高 = fixedRowsH +
  tempRowH 恒 ≤ topAreaH），任意屏高（含 1366×768/1280×720）都不重叠、
  不把「今日」行裁没（审查 C1）。
- 承重值（contentMargin / hourlyH / spacing / 行高）直接断言，防止静默
  回退后测试仍绿（审查 C2）。
- 用与 WidgetHost 相同的网格公式做几何不等式实测（node 同款纯计算）。
"""

from __future__ import annotations

import math
import re
import unittest
from pathlib import Path

SHELL_ROOT = Path(__file__).resolve().parents[1]
WIDGET = SHELL_ROOT / "components" / "widgets" / "WeatherWidget.qml"
GRID = SHELL_ROOT / "components" / "widgets" / "WidgetGrid.js"
HOST = SHELL_ROOT / "components" / "widgets" / "WidgetHost.qml"


def extract_value(text: str, pattern: str) -> float:
    m = re.search(pattern, text)
    if not m:
        raise AssertionError(f"pattern not found: {pattern}")
    return float(m.group(1))


class WeatherWidgetLayoutTests(unittest.TestCase):
    def test_load_bearing_values_are_locked(self) -> None:
        text = WIDGET.read_text(encoding="utf-8")
        self.assertIn("readonly property real hourlyH: 46", text)
        self.assertIn("readonly property real contentMargin: 12", text)
        self.assertIn("readonly property real tempRowMinH: 26", text)
        self.assertIn("readonly property real tempRowMaxH: 36", text)
        self.assertIn("anchors.margins: root.contentMargin", text)
        self.assertIn("spacing: 2", text)
        # 三行文本均为 14px 行高（13px 字号），今日行不再独小。
        self.assertGreaterEqual(text.count("height: 14"), 3)
        self.assertIn("height: root.tempRowH", text)
        # 自适应公式：温度行高度 = clamp(topAreaH - fixed, min, max)。
        self.assertIn("root.tempRowH", text)
        self.assertIn("Math.max(root.tempRowMinH, Math.min(root.tempRowMaxH, root.topAreaH - root.fixedRowsH))", text)
        self.assertIn("font.pixelSize: Math.min(34, Math.max(24, root.tempRowH - 4))", text)
        self.assertIn("height: root.topAreaH", text)
        self.assertIn("clip: true", text)

    def test_geometry_fits_all_supported_screens(self) -> None:
        """用宿主同款网格公式验证：任意屏高下 Column 总高 ≤ topAreaH。"""
        widget_text = WIDGET.read_text(encoding="utf-8")
        grid_text = GRID.read_text(encoding="utf-8")
        host_text = HOST.read_text(encoding="utf-8")

        gap = extract_value(grid_text, r"var GAP_PX = (\d+);")
        hourly_h = extract_value(widget_text, r"readonly property real hourlyH: (\d+)")
        margin = extract_value(widget_text, r"readonly property real contentMargin: (\d+)")
        # 只取顶部 Column（topArea 段）的 spacing，避免与温度 Row / 逐时条
        # 的 spacing 混淆（位置敏感，审查 P-2）。
        top_section = widget_text[widget_text.index("// 顶部：当前天气。"):widget_text.index("// 底部：逐时条")]
        spacing = extract_value(top_section, r"spacing: (\d+)")
        loc_h = 14
        cond_h = 14
        today_h = 14
        temp_min = extract_value(widget_text, r"readonly property real tempRowMinH: (\d+)")
        temp_max = extract_value(widget_text, r"readonly property real tempRowMaxH: (\d+)")
        top_gap = 4

        # WidgetHost 网格公式（A6 部署反馈版本）。
        top_reserved = extract_value(host_text, r"readonly property int topReserved: (\d+)")
        screens = [
            (2048, 1280),  # 部署机 eDP-2 2560x1600@1.25
            (1920, 1080),
            (1536, 864),
            (1366, 768),
            (1280, 720),
        ]
        for width, height in screens:
            self.assert_geometry_fits(width, height, top_reserved, gap, hourly_h,
                                      margin, spacing, loc_h, cond_h, today_h,
                                      temp_min, temp_max, top_gap)

    def assert_geometry_fits(self, width: int, height: int, top_reserved: float,
                             gap: float, hourly_h: float, margin: float,
                             spacing: float, loc_h: float, cond_h: float,
                             today_h: float, temp_min: float, temp_max: float,
                             top_gap: float) -> None:
        with self.subTest(screen=f"{width}x{height}"):
            # 与 WidgetHost 同款公式，且实例高按宿主 Math.round 取整
            # （审查 P-3：未取整版本会漏掉 761/762 这类四舍五入边界）。
            desired = min(max(1, width / 4), 90)
            usable = max(1, height - top_reserved)
            rows = max(6, math.ceil(usable / desired))
            cell = min(desired, usable / rows)
            widget_h = math.floor(2 * cell - gap + 0.5)  # Math.round
            top_area_h = widget_h - 2 * margin - hourly_h - top_gap
            fixed = loc_h + cond_h + today_h + spacing * 3
            temp_row_h = max(temp_min, min(temp_max, top_area_h - fixed))
            content_h = fixed + temp_row_h
            self.assertLessEqual(
                content_h, top_area_h + 1e-6,
                f"content {content_h} > topArea {top_area_h}",
            )

    def test_geometry_fits_all_logical_heights_720_to_1600(self) -> None:
        """全高度扫描：逻辑高 720–1600 每 1px 都要满足不等式（审查 C-1
        的 761/762 边界必须被抓住）。"""
        widget_text = WIDGET.read_text(encoding="utf-8")
        grid_text = GRID.read_text(encoding="utf-8")
        host_text = HOST.read_text(encoding="utf-8")
        gap = extract_value(grid_text, r"var GAP_PX = (\d+);")
        hourly_h = extract_value(widget_text, r"readonly property real hourlyH: (\d+)")
        margin = extract_value(widget_text, r"readonly property real contentMargin: (\d+)")
        top_section = widget_text[widget_text.index("// 顶部：当前天气。"):widget_text.index("// 底部：逐时条")]
        spacing = extract_value(top_section, r"spacing: (\d+)")
        temp_min = extract_value(widget_text, r"readonly property real tempRowMinH: (\d+)")
        temp_max = extract_value(widget_text, r"readonly property real tempRowMaxH: (\d+)")
        top_reserved = extract_value(host_text, r"readonly property int topReserved: (\d+)")
        for height in range(720, 1601):
            self.assert_geometry_fits(1920, height, top_reserved, gap, hourly_h,
                                      margin, spacing, 14, 14, 14, temp_min,
                                      temp_max, 4)

    def test_today_line_is_preserved(self) -> None:
        text = WIDGET.read_text(encoding="utf-8")
        self.assertIn('return "今日 " + root.fmtTemp(root.currentLowC, false)', text)
        self.assertIn("visible: text.length > 0", text)


if __name__ == "__main__":
    unittest.main()
