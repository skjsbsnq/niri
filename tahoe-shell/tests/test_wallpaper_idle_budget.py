from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
WALLPAPER = SHELL_ROOT / "components" / "Wallpaper.qml"
SETTINGS = SHELL_ROOT / "services" / "DesktopSettings.qml"
PAGE = SHELL_ROOT / "components" / "settings" / "pages" / "WallpaperPage.qml"
LOCK_SCREEN = SHELL_ROOT / "components" / "LockScreen.qml"
PRESTART = SHELL_ROOT / "scripts" / "prestart-wallpaper.sh"
START = SHELL_ROOT / "scripts" / "start-quickshell.sh"
SESSION = SHELL_ROOT.parent / "scripts" / "run-tahoe-session.sh"
NIRI_CONFIG = SHELL_ROOT.parent / "config" / "niri" / "tahoe-phase0.kdl"


class WallpaperIdleBudgetTests(unittest.TestCase):
    def test_desktop_settings_exposes_fps_budget(self) -> None:
        text = SETTINGS.read_text(encoding="utf-8")
        self.assertIn("property int wallpaperEngineFps: 15", text)
        self.assertIn("property int wallpaperEngineIdleFps: 8", text)
        self.assertIn("property int wallpaperEngineIdleSeconds: 60", text)
        self.assertIn("property bool wallpaperPauseWhenIdle: false", text)
        self.assertIn("property bool wallpaperPauseWhenFullscreen: true", text)
        self.assertIn("function setWallpaperEngineFps(", text)
        self.assertIn("function setWallpaperEngineIdleFps(", text)
        self.assertIn("function setWallpaperPauseWhenIdle(", text)
        self.assertIn("function setWallpaperPauseWhenFullscreen(", text)
        # Active fps hard-capped at 20 (glass sampling budget).
        self.assertIn("clampInt(value, 1, 20, 15)", text)

    def test_desktop_settings_and_page_expose_lock_screen_follow(self) -> None:
        settings = SETTINGS.read_text(encoding="utf-8")
        page = PAGE.read_text(encoding="utf-8")
        self.assertIn("property bool lockScreenFollowWallpaper: true", settings)
        self.assertIn("readonly property bool lockScreenFollowWallpaper", settings)
        self.assertIn("function setLockScreenFollowWallpaper(", settings)
        self.assertIn("锁屏跟随壁纸", page)
        self.assertIn("动态壁纸使用引擎渲染的高清静态帧", page)
        self.assertIn("setLockScreenFollowWallpaper", page)

    def test_lock_screen_uses_renderer_capture_without_crop(self) -> None:
        text = LOCK_SCREEN.read_text(encoding="utf-8")
        self.assertIn('Quickshell.stateDir + "/lock-wallpaper"', text)
        self.assertIn("function lockWallpaperCapturePath(", text)
        self.assertIn("source: surface.captureLoadSource", text)
        self.assertIn("capturedWallpaperReady", text)
        self.assertIn("requestCapturedWallpaperReload", text)
        # Capture and static fallback both crop to fill; no letterbox black bars.
        self.assertIn("fillMode: Image.PreserveAspectCrop", text)
        self.assertNotIn("fillMode: Image.PreserveAspectFit", text)
        # Capture Image uses cache so unlock preload and lock surface share a
        # decoded pixmap (cache:false would force a cold 4K decode on every lock).
        self.assertIn("id: capturedWallpaperImage", text)
        self.assertNotIn("project.json", text)
        self.assertNotIn("metadata.preview", text)
        self.assertIn("status !== Image.Error", text)
        self.assertIn("surface.configuredStaticWallpaperFailed = true", text)
        # Same-path Error retries blank to re-fetch; Ready re-lock keeps frame.
        self.assertIn("surface.captureLoadSource === nextSource", text)
        self.assertIn("surface.captureLoadSource = \"\"", text)
        self.assertIn("expectCapturedWallpaper", text)
        self.assertIn("showStaticUnderlay", text)
        self.assertIn("asynchronous: false", text)
        self.assertIn("opacity: 1", text)
        # Live follow must not always paint fallback underlay first.
        self.assertIn("visible: surface.showStaticUnderlay", text)
        # Warm decode + sized load so lock enter is not a gray flash.
        self.assertIn("property Instantiator capturePreloaders", text)
        self.assertIn("function captureDecodeSize(", text)
        self.assertIn("sourceSize: surface.captureSourceSize", text)
        self.assertIn("cache: true", text)
        # Dim full on map; only fades out on unlock (no brightness pop).
        self.assertIn("opacity: root.unlocking ? 0 : 1", text)

    def test_wallpaper_idle_monitor_and_fps_rewrite(self) -> None:
        text = WALLPAPER.read_text(encoding="utf-8")
        self.assertIn("IdleMonitor", text)
        self.assertIn("wallpaperIdleMonitor", text)
        self.assertIn("property bool sessionIdle:", text)
        self.assertIn("effectiveWallpaperFps", text)
        self.assertIn("prestartStateLoaded", text)
        self.assertIn("prestartedWallpaperStopPending", text)
        self.assertIn("reloadPrestartedWallpaperState", text)
        self.assertIn("prestartedWallpaperRecordPath", text)
        self.assertIn("prestartedRecordProcessMatches", text)
        self.assertIn("prestartedWallpaperHealthTimer", text)
        self.assertIn("nestedSession", text)
        self.assertRegex(text, re.compile(r"dynamicDesired:.*?&& !nestedSession", re.S))
        self.assertRegex(text, re.compile(r"externalDesired:.*?&& !nestedSession", re.S))
        self.assertIn('nestedSession ? ""', text)
        self.assertIn("watchChanges: true", text)
        self.assertIn("onFileChanged: reload()", text)
        self.assertIn("property int appliedWallpaperFps:", text)
        self.assertIn("liveWallpaperAllowed", text)
        self.assertIn("function applyWallpaperFpsBudget(", text)
        self.assertIn("function prepareWallpaperProcessStart(", text)
        self.assertIn("wallpaperPauseWhenIdle", text)
        self.assertIn("wallpaperPauseWhenFullscreen", text)
        self.assertIn("liveWallpaperReadyTimer", text)
        self.assertNotIn("prestartedWallpaperTakeoverTimer", text)
        self.assertNotIn("function takeOverPrestartedWallpaper(", text)
        self.assertNotIn("prestartedWallpaperCleanupTimer", text)
        self.assertNotIn('Quickshell.stateDir + "/wallpaper-prestart.pids"', text)
        self.assertIn("dynamicActive = true", text)
        self.assertIn("already owns a mapped background surface", text)
        self.assertIn("kill -KILL", text)
        self.assertNotIn("onSessionIdleChanged:", text)
        self.assertNotIn("onEffectiveWallpaperFpsChanged:", text)
        self.assertIn("root.appliedWallpaperFps", text)
        # Idle path must stop live engine when pause is enabled.
        self.assertIn("&& liveWallpaperAllowed", text)

    def test_external_sync_waits_for_command_and_screen(self) -> None:
        text = WALLPAPER.read_text(encoding="utf-8")
        sync = re.search(
            r"function syncExternalProcess\(\) \{(.*?)\n    \}",
            text,
            re.S,
        )
        self.assertIsNotNone(sync)
        body = sync.group(1)
        self.assertIn("if (screenName().length === 0)", body)
        self.assertIn("if (externalCommand.length === 0)", body)
        self.assertIn("if (!externalStateLoaded || !prestartStateLoaded)", body)
        # Empty-command path must not release prestart while state is still loading.
        self.assertIn("externalStateLoaded", body)
        self.assertIn("tryAdoptPrestartedWallpaper(\"external\")", body)
        self.assertIn("if ((dynamicDesired || externalDesired)", text)
        self.assertIn("showRestartCover()", text)
        # Adopting prestart must not raise restart cover over a live surface.
        adopt = re.search(
            r"function tryAdoptPrestartedWallpaper\(mode\) \{(.*?)\n    \}",
            text,
            re.S,
        )
        self.assertIsNotNone(adopt)
        self.assertIn("restartCoverVisible = false", adopt.group(1))
        self.assertNotIn("restartCoverVisible = true", adopt.group(1))
        # Restart cover must not paint the configured static wallpaper.
        cover = re.search(r"id: restartCover(.*?)// Live wallpapers", text, re.S)
        self.assertIsNotNone(cover)
        self.assertNotIn("staticWallpaperSource()", cover.group(1))
        self.assertIn("coverCapturePath", cover.group(1))
        self.assertIn("&& !restartCoverVisible", text)
        # Unexpected process exit must drop the cover so static can fall back.
        self.assertIn("!root.dynamicRestartPending", text)
        self.assertIn("!root.externalRestartPending", text)
        self.assertIn("root.restartCoverVisible = false", text)
        # Valid prestart record reloads clear the sticky released flag.
        self.assertIn("prestartedWallpaperReleased = false", text)

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
            r"readonly property bool liveModePending:",
            text,
            re.S,
        )

        self.assertIsNotNone(dynamic_suppression)
        self.assertIsNotNone(external_suppression)
        self.assertNotIn("dynamicActive", dynamic_suppression.group(1))
        self.assertIn("!externalLaunchFailed", external_suppression.group(1))
        # Boot race: empty command while screen/prestart still resolving must
        # still suppress static (not only "command non-empty").
        self.assertIn("screenName().length === 0", external_suppression.group(1))
        self.assertIn("!prestartStateLoaded", external_suppression.group(1))
        self.assertIn("!dynamicLaunchFailed", dynamic_suppression.group(1))
        # Binding-order race: settingsReady→externalDesired evaluates before
        # onExternalDesiredChanged can refreshExternalCommand. Without a
        # sync-settled gate, showStaticWallpaper is true for one frame and
        # paints the default iridescence over the live engine.
        self.assertIn("!externalSyncSettled", external_suppression.group(1))
        self.assertIn("!dynamicSyncSettled", dynamic_suppression.group(1))
        self.assertIn("property bool externalSyncSettled: false", text)
        self.assertIn("property bool dynamicSyncSettled: false", text)
        self.assertIn("externalSyncSettled = false", text)
        self.assertIn("dynamicSyncSettled = false", text)
        self.assertIn("externalSyncSettled = true", text)
        self.assertIn("dynamicSyncSettled = true", text)
        self.assertIn("liveModePending", text)
        # Hard policy: static plate only for explicit static mode, live launch
        # failure, or intentional idle pause — never for mid-boot live gaps.
        self.assertIn("configuredWallpaperMode", text)
        self.assertIn("liveModeConfigured", text)
        self.assertIn("prestartLivePainting", text)
        self.assertIn("coverPlateVisible", text)
        self.assertIn("liveLaunchFailed", text)
        # Permanent auto-boot cover was the black-screen regression: it stacked
        # above linux-wallpaperengine and never cleared without adopt.
        self.assertNotIn("liveBootCoverDesired", text)
        show_static = re.search(
            r"readonly property bool showStaticWallpaper:(.*?)"
            r"readonly property bool liveWallpaperVisible:",
            text,
            re.S,
        )
        self.assertIsNotNone(show_static)
        body = show_static.group(1)
        self.assertIn("configuredWallpaperMode === \"static\"", body)
        self.assertIn("liveLaunchFailed", body)
        self.assertIn("!liveWallpaperAllowed", body)
        self.assertIn("!coverPlateVisible", body)
        self.assertIn("!prestartLivePainting", body)
        # Cover is only the sticky restart latch — never a permanent boot plate.
        cover_prop = re.search(
            r"readonly property bool coverPlateVisible:(.*)",
            text,
        )
        self.assertIsNotNone(cover_prop)
        self.assertIn("restartCoverVisible", cover_prop.group(1))
        self.assertNotIn("liveBootCoverDesired", cover_prop.group(1))
        cover = re.search(r"id: restartCover(.*?)// Live wallpapers", text, re.S)
        self.assertIsNotNone(cover)
        cover_body = cover.group(1)
        self.assertIn("root.coverPlateVisible", cover_body)
        self.assertIn("coverCapturePath", cover_body)
        self.assertNotIn("staticWallpaperSource()", cover_body)
        # Layer must stay transparent while live paint is expected so the engine
        # under tahoe-wallpaper remains visible.
        self.assertIn('color: yieldToDynamicWallpaper ? "transparent"', text)
        self.assertNotIn("color: coverPlateVisible", text)
        # No opacity fade of the static wallpaper plate over live — unmount.
        static_layer = re.search(r"id: staticLayer(.*?)// Intentional command", text, re.S)
        self.assertIsNotNone(static_layer)
        body = static_layer.group(1)
        self.assertIn("visible: root.showStaticWallpaper", body)
        self.assertIn("opacity: 1", body)
        self.assertNotIn("opacity: root.showStaticWallpaper", body)

    def test_wallpaper_page_exposes_budget_controls(self) -> None:
        text = PAGE.read_text(encoding="utf-8")
        self.assertIn("活动帧率", text)
        self.assertIn("空闲帧率", text)
        self.assertIn("空闲暂停", text)
        self.assertIn("setWallpaperEngineFps", text)
        self.assertIn("setWallpaperEngineIdleFps", text)
        self.assertIn("setWallpaperPauseWhenIdle", text)
        self.assertIn("全屏时暂停动态壁纸", text)
        self.assertIn("setWallpaperPauseWhenFullscreen", text)
        self.assertIn("checkable: true", text)

    def test_prestart_respects_settings_fps_budget(self) -> None:
        text = PRESTART.read_text(encoding="utf-8")
        self.assertIn("wallpaperEngineFps", text)
        self.assertIn("inject_fps", text)
        self.assertIn("settings_fps_budget", text)
        self.assertIn("terminate_recorded_wallpapers", text)
        self.assertIn('record_dir="$state_dir/wallpaper-prestart"', text)
        self.assertIn("spawn_supervised", text)
        self.assertIn("process_start_time", text)
        self.assertIn('"startTime"', text)
        self.assertIn('"token"', text)
        self.assertIn("if not outputs:", text)
        self.assertNotIn('inject_lock_capture(prepared, "default")', text)
        self.assertIn("wallpaperPauseWhenFullscreen", text)
        self.assertIn("--no-fullscreen-pause", text)
        self.assertIn("--screenshot", text)
        self.assertIn("--screenshot-delay", text)
        self.assertIn("lock_capture_path", text)
        self.assertIn("kill -KILL", text)
        self.assertRegex(text, r"min\(20")

    def test_wallpaper_prestart_is_serialized_before_quickshell(self) -> None:
        start = START.read_text(encoding="utf-8")
        session = SESSION.read_text(encoding="utf-8")
        config = NIRI_CONFIG.read_text(encoding="utf-8")
        self.assertIn("prestart_wallpaper()", start)
        self.assertIn("prestart_wallpaper\nexec", start)
        self.assertIn("TAHOE_SKIP_WALLPAPER_PRESTART", start)
        self.assertIn("TAHOE_NESTED_SESSION", start)
        self.assertIn('shell_args=("bash" "$TAHOE_CONFIG_DIR/scripts/start-quickshell.sh")', session)
        self.assertEqual(config.count("prestart-wallpaper.sh"), 0)


if __name__ == "__main__":
    unittest.main()
