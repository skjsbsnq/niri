#!/usr/bin/env python3
"""T22: dead-path removal and heavy-scene lifecycle hardening."""

from __future__ import annotations

import os
import shutil
import subprocess
import unittest
from pathlib import Path


SHELL = Path(__file__).resolve().parents[1]
COMPONENTS = SHELL / "components"
CONTENT = COMPONENTS / "DynamicIslandContent.qml"
OVERLAY = COMPONENTS / "DynamicIslandOverlay.qml"
MOTION = COMPONENTS / "DynamicIslandMotion.js"
MEDIA = COMPONENTS / "DynamicIslandMediaView.qml"
ISLAND = SHELL / "services" / "DynamicIsland.qml"
SHELL_QML = SHELL / "shell.qml"
QML_TEST = Path(__file__).with_name("tst_dynamic_island_runtime_hardening.qml")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class DynamicIslandRuntimeHardeningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.content = read(CONTENT)
        cls.overlay = read(OVERLAY)
        cls.motion = read(MOTION)
        cls.media = read(MEDIA)
        cls.island = read(ISLAND)
        cls.shell = read(SHELL_QML)

    def test_retired_files_and_generic_scene_are_gone(self) -> None:
        self.assertFalse((COMPONENTS / "DynamicIslandChip.qml").exists())
        self.assertFalse((COMPONENTS / "DynamicIslandSummaryView.qml").exists())
        self.assertNotIn("id: detailRow", self.content)
        self.assertNotIn("standardDetailActive", self.content)
        self.assertNotIn("id: progressTrack", self.content)

    def test_retired_summary_plumbing_is_gone(self) -> None:
        for text in (self.island, self.overlay, self.content):
            self.assertNotIn("summaryBatteryPercent", text)
            self.assertNotIn("summaryBatteryCharging", text)
            self.assertNotIn("summaryWorkspaceLabel", text)
            self.assertNotIn("summaryExpandedContentVisible", text)
        self.assertNotIn("property var batteryService", self.island)
        dynamic_block = self.shell.split("DynamicIsland {", 1)[1].split("\n    }", 1)[0]
        self.assertNotIn("batteryService: battery", dynamic_block)

    def test_notification_and_media_are_loader_owned(self) -> None:
        self.assertIn('objectName: "notificationLoader"', self.content)
        self.assertIn("active: root.notificationLoaderActive", self.content)
        self.assertIn("sourceComponent: notificationSceneComponent", self.content)
        self.assertIn('objectName: "mediaLoader"', self.content)
        self.assertIn("active: root.mediaLoaderActive", self.content)
        self.assertEqual(self.content.count("DynamicIslandNotificationView {"), 1)
        self.assertEqual(self.content.count("DynamicIslandMediaView {"), 1)
        self.assertNotIn("Flickable {", self.content)

    def test_hidden_media_has_no_timer_or_canvas(self) -> None:
        self.assertNotIn("Timer {", self.media)
        self.assertNotIn("Canvas {", self.media)
        self.assertNotIn("visualizer", self.media.lower())

    def test_non_owner_heavy_image_inputs_are_empty(self) -> None:
        self.assertIn("activeForScreen && dynamicIslandService", self.overlay)
        self.assertIn("mediaArtUrl", self.overlay)
        self.assertIn("contentNotificationIconUrl", self.overlay)
        self.assertIn("bluetoothDeviceIcon", self.overlay)

    def test_unused_motion_aliases_are_removed(self) -> None:
        for token in (
            "chipColorDuration",
            "chipScaleDuration",
            "chipContentDuration",
            "chipColorEasing",
            "chipSettleEasing",
            "overlayContentDuration",
            "overlayExpandedExitFadeMs",
            "overlayExpandedEnterFadeMs",
            "overlayMorphDuration",
            "overlayMorphEasing",
        ):
            self.assertNotIn(token, self.motion)

    def test_single_surface_and_governed_region(self) -> None:
        self.assertEqual(self.overlay.count("PanelWindow {"), 1)
        self.assertIn("TahoeGlass.regions: [islandSurface.region]", self.overlay)
        self.assertEqual(self.overlay.count("SpringAnimation {"), 0)
        self.assertIn("exclusiveZone: 0", self.overlay)

    def test_real_qml_loader_lifecycle(self) -> None:
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(runner, "Qt 6 qmltestrunner is required")
        env = os.environ.copy()
        env.setdefault("QT_QPA_PLATFORM", "offscreen")
        local_qml = Path.home() / ".local" / "lib" / "qt6" / "qml"
        test_qml = SHELL / "tests" / "qml_imports"
        existing = env.get("QML2_IMPORT_PATH", "")
        paths = [str(test_qml), str(local_qml)]
        if existing:
            paths.append(existing)
        env["QML2_IMPORT_PATH"] = ":".join(paths)
        result = subprocess.run(
            [runner, "-input", str(QML_TEST)],
            cwd=SHELL,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
