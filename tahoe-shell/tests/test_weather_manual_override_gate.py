#!/usr/bin/env python3
"""Weather manual-location persistence gate (A3 部署反馈).

Root cause of "设了城市仍按 IP 查天气": Weather.qml 的 Component.onCompleted
立刻 refresh()，但 DesktopSettings 的 desktop-settings.json 由 FileView
异步加载，此时 weatherManualOverride 还是默认 false → 走 IP 定位；设置
加载完成后没有任何路径重发刷新。本测试锁定「设置未就绪 → 挂起刷新/缓存；
onLoadedChanged → 重驱」的门控（P-7 双门：早退 + 完成回调重驱），以及
手动位置与缓存坐标不一致时丢弃缓存（不闪旧 IP 位置）。

除字符串存在性外，还用函数体内相对位置断言控制流顺序（审查 C1）：门控
早退必须在 manualOverride 分支 / detectLocation 之前；缓存不匹配检查必须
在 applyCachePayload 之前；重驱 refresh() 必须在 pendingSettingsRefresh
条件块内。
"""

from __future__ import annotations

import unittest
from pathlib import Path

SHELL_ROOT = Path(__file__).resolve().parents[1]
WEATHER = SHELL_ROOT / "services" / "Weather.qml"


class WeatherManualOverrideGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = WEATHER.read_text(encoding="utf-8")

    def _function_body(self, name: str) -> str:
        text = self.text
        start = text.index(f"function {name}(")
        body = text[start:]
        # 下一个顶层函数（4 空格缩进）为止。
        for marker in ("\n    function ", "\n    Connections ", "\n    FileView ", "\n    Process ", "\n    Timer "):
            idx = body.find(marker, len(f"function {name}("))
            if idx > 0:
                return body[:idx]
        return body

    def test_refresh_defers_until_settings_loaded_before_any_fetch(self) -> None:
        text = self.text
        self.assertIn("readonly property bool settingsReady:", text)
        self.assertIn("!!root.settingsService && !!root.settingsService.loaded", text)
        self.assertIn("property bool pendingSettingsRefresh: false", text)

        refresh = self._function_body("refresh")
        gate = refresh.index("if (root.settingsService && !root.settingsService.loaded) {")
        manual = refresh.index("if (manualOverrideEnabled() && canUseLocation(lat, lon)) {")
        detect = refresh.index("root.detectLocation();")
        # 控制流顺序：设置门 → 手动分支 → IP 兜底。若门被移到手动分支之后，
        # 设置未就绪时会先读默认值直接 detectLocation()，bug 回归而测试报警。
        self.assertLess(gate, manual)
        self.assertLess(manual, detect)
        # 门块内必须真正早退（挂起 + return），不能只设标志继续走。
        gate_block = refresh[gate:manual]
        self.assertIn("root.pendingSettingsRefresh = true;", gate_block)
        self.assertIn("return;", gate_block)

    def test_settings_loaded_completion_redrives_refresh(self) -> None:
        text = self.text
        self.assertIn("Connections {", text)
        self.assertIn("target: root.settingsService", text)
        conn = text[text.index("function onLoadedChanged() {"):]
        conn = conn[: conn.index("\n    Process {")]
        self.assertIn("if (!root.settingsReady)", conn)
        self.assertIn("root.loadCache(false);", conn)
        # 重驱 refresh() 必须在 pendingSettingsRefresh 条件块内：只在被挡时
        # 重驱，不能无条件刷新（P-7 第二门语义）。
        if_pos = conn.index("if (root.pendingSettingsRefresh) {")
        refresh_pos = conn.index("root.refresh();")
        self.assertLess(if_pos, refresh_pos)
        block = conn[if_pos : conn.index("}", if_pos)]
        self.assertIn("root.pendingSettingsRefresh = false;", block)
        self.assertIn("root.refresh();", block)

    def test_manual_override_still_consumed(self) -> None:
        text = self.text
        self.assertIn("if (manualOverrideEnabled() && canUseLocation(lat, lon)) {", text)
        self.assertIn("root.startWeatherFetch(lat, lon, manualLocationName() || \"手动位置\");", text)

    def test_cache_load_gated_and_mismatch_discarded_before_apply(self) -> None:
        text = self.text
        load = self._function_body("loadCache")
        self.assertIn("if (root.settingsService && !root.settingsService.loaded)", load)
        self.assertIn("function cacheMatchesLocation(cache, lat, lon) {", text)
        self.assertIn("if (manualOverrideEnabled() && canUseLocation(lat, lon)", load)
        mismatch = load.index("!root.cacheMatchesLocation(cache, lat, lon)")
        apply = load.index("return applyCachePayload(cache, stale);")
        # 不匹配检查必须先于应用缓存：先应用再丢弃会闪现旧 IP 位置。
        self.assertLess(mismatch, apply)
        # 设置就绪后补载被拒的缓存（P-7 重驱）已在 Connections 测试覆盖。


if __name__ == "__main__":
    unittest.main()
