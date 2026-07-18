from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
WALLPAPER = SHELL_ROOT / "components" / "Wallpaper.qml"
SETTINGS = SHELL_ROOT / "services" / "DesktopSettings.qml"
PAGE = SHELL_ROOT / "components" / "settings" / "pages" / "WallpaperPage.qml"
PRESTART = SHELL_ROOT / "scripts" / "prestart-wallpaper.sh"


class WallpaperIdleBudgetTests(unittest.TestCase):
    def test_desktop_settings_exposes_fps_budget(self) -> None:
        text = SETTINGS.read_text(encoding="utf-8")
        self.assertIn("property int wallpaperEngineFps: 15", text)
        self.assertIn("property int wallpaperEngineIdleFps: 8", text)
        self.assertIn("property int wallpaperEngineIdleSeconds: 60", text)
        self.assertIn("property bool wallpaperPauseWhenIdle: false", text)
        self.assertIn("function setWallpaperEngineFps(", text)
        self.assertIn("function setWallpaperEngineIdleFps(", text)
        self.assertIn("function setWallpaperPauseWhenIdle(", text)
        # Active fps hard-capped at 20 (glass sampling budget).
        self.assertIn("clampInt(value, 1, 20, 15)", text)

    def test_wallpaper_idle_monitor_and_fps_rewrite(self) -> None:
        text = WALLPAPER.read_text(encoding="utf-8")
        self.assertIn("IdleMonitor", text)
        self.assertIn("wallpaperIdleMonitor", text)
        self.assertIn("property bool sessionIdle:", text)
        self.assertIn("effectiveWallpaperFps", text)
        self.assertIn("property int appliedWallpaperFps:", text)
        self.assertIn("liveWallpaperAllowed", text)
        self.assertIn("function applyWallpaperFpsBudget(", text)
        self.assertIn("function prepareWallpaperProcessStart(", text)
        self.assertIn("wallpaperPauseWhenIdle", text)
        self.assertIn("liveWallpaperReadyTimer", text)
        self.assertIn("prestartedWallpaperTakeoverTimer", text)
        self.assertIn("function takeOverPrestartedWallpaper(", text)
        self.assertIn("kill -KILL", text)
        self.assertNotIn("onSessionIdleChanged:", text)
        self.assertNotIn("onEffectiveWallpaperFpsChanged:", text)
        self.assertIn("root.appliedWallpaperFps", text)
        # Idle path must stop live engine when pause is enabled.
        self.assertIn("&& liveWallpaperAllowed", text)

    def test_live_wallpaper_startup_never_reveals_static_fallback(self) -> None:
        text = WALLPAPER.read_text(encoding="utf-8")
        dynamic_suppression = re.search(
            r"readonly property bool dynamicSuppressesStatic:(.*?)"
            r"readonly property bool externalSuppressesStatic:",
            text,
            re.S,
        )
        external_suppression = re.search(
            r"readonly property bool externalSuppressesStatic:(.*?)"
            r"readonly property bool showStaticWallpaper:",
            text,
            re.S,
        )

        self.assertIsNotNone(dynamic_suppression)
        self.assertIsNotNone(external_suppression)
        self.assertNotIn("dynamicActive", dynamic_suppression.group(1))
        self.assertNotIn("dynamicActive", external_suppression.group(1))
        self.assertIn("!dynamicLaunchFailed", dynamic_suppression.group(1))
        self.assertIn("!externalLaunchFailed", external_suppression.group(1))

    def test_wallpaper_page_exposes_budget_controls(self) -> None:
        text = PAGE.read_text(encoding="utf-8")
        self.assertIn("活动帧率", text)
        self.assertIn("空闲帧率", text)
        self.assertIn("空闲暂停", text)
        self.assertIn("setWallpaperEngineFps", text)
        self.assertIn("setWallpaperEngineIdleFps", text)
        self.assertIn("setWallpaperPauseWhenIdle", text)
        self.assertIn("checkable: true", text)

    def test_prestart_respects_settings_fps_budget(self) -> None:
        text = PRESTART.read_text(encoding="utf-8")
        self.assertIn("wallpaperEngineFps", text)
        self.assertIn("inject_fps", text)
        self.assertIn("settings_fps_budget", text)
        self.assertIn("terminate_recorded_wallpapers", text)
        self.assertIn("kill -KILL", text)
        self.assertRegex(text, r"min\(20")


if __name__ == "__main__":
    unittest.main()
