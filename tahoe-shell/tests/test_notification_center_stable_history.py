#!/usr/bin/env python3
"""R10 notification history identity and row-motion contracts."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NOTIFICATIONS = ROOT / "services" / "Notifications.qml"
CENTER = ROOT / "components" / "NotificationCenter.qml"
QML_TEST = Path(__file__).with_name("tst_notification_center_stable_history.qml")
ROW_QML_TEST = Path(__file__).with_name("tst_notification_center_stable_rows.qml")


class NotificationCenterStableHistoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.service = NOTIFICATIONS.read_text(encoding="utf-8")
        cls.center = CENTER.read_text(encoding="utf-8")

    def test_service_uses_stable_entry_and_group_caches(self) -> None:
        self.assertIn("property var historyEntryCache: Object.create(null)", self.service)
        self.assertIn("property var historyGroupCache: Object.create(null)", self.service)
        self.assertIn('"modelKey": "history:" + key', self.service)
        self.assertIn('"modelKey": "history-group:" + appName', self.service)
        self.assertRegex(self.service, r"function\s+reconcileHistoryCaches\s*\(")
        self.assertRegex(self.service, r"function\s+rebuildGroupedHistory\s*\(")
        self.assertIn("onHistoryModelChanged: root.reconcileHistoryCaches()", self.service)
        self.assertNotRegex(self.service, r"function\s+groupedHistory\s*\(")
        self.assertNotRegex(
            self.service,
            r"groups\.push\s*\(\s*\{\s*\"appName\"",
        )

    def test_center_consumes_two_stable_script_models(self) -> None:
        self.assertIn("notificationsService.groupedHistoryModel", self.center)
        self.assertGreaterEqual(self.center.count('objectProp: "modelKey"'), 2)
        self.assertNotIn("notificationsService.groupedHistory()", self.center)

    def test_new_rows_slide_and_fade_in(self) -> None:
        self.assertIn("property bool enterComplete: false", self.center)
        self.assertIn("Motion.toastEnterOffsetPx", self.center)
        self.assertIn("row.enterComplete && !flyOut ? 1 : 0", self.center)
        self.assertIn("root.claimHistoryEntryAnimation(row.entry.id)", self.center)
        self.assertIn("row.motionReady = true", self.center)
        self.assertIn("Qt.callLater(function()", self.center)
        self.assertNotIn("SpringAnimation", self.center)

    def test_single_delete_flies_out_then_collapses_before_service_removal(self) -> None:
        self.assertRegex(self.center, r"function\s+beginRemoval\s*\(")
        self.assertIn("id: removalExitTimer", self.center)
        self.assertIn("id: removalCollapseTimer", self.center)
        self.assertIn("row.collapsing = true", self.center)
        self.assertIn("root.completeHistoryRemoval(row.entry.id)", self.center)
        self.assertIn("onClicked: row.beginRemoval()", self.center)
        self.assertNotRegex(
            self.center,
            r"onClicked:\s*\{[^}]*removeHistoryItem",
        )

    def test_real_qml_history_identity(self) -> None:
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(runner, "Qt 6 qmltestrunner is required")
        env = os.environ.copy()
        env.setdefault("QT_QPA_PLATFORM", "offscreen")
        local_qml = Path.home() / ".local" / "lib" / "qt6" / "qml"
        test_qml = ROOT / "tests" / "qml_imports"
        paths = [str(test_qml), str(local_qml)]
        existing = env.get("QML2_IMPORT_PATH", "")
        if existing:
            paths.append(existing)
        env["QML2_IMPORT_PATH"] = ":".join(paths)
        result = subprocess.run(
            [runner, "-input", str(QML_TEST)],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_real_qs_row_entry_and_single_delete(self) -> None:
        local_runner = Path.home() / ".local" / "bin" / "qs"
        runner = str(local_runner) if local_runner.is_file() else shutil.which("qs")
        self.assertIsNotNone(runner, "Tahoe Quickshell runtime is required")
        template = ROW_QML_TEST.read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory(prefix="tahoe-notification-center-") as tmp:
            for profile in ("balanced", "reduced"):
                qml_test = Path(tmp) / f"shell-{profile}.qml"
                source = template.replace(
                    'property string centerSource: ""',
                    f'property string centerSource: "{CENTER}"',
                ).replace(
                    'property string motionProfile: "balanced"',
                    f'property string motionProfile: "{profile}"',
                )
                qml_test.write_text(source, encoding="utf-8")
                result = subprocess.run(
                    [runner, "-p", str(qml_test)],
                    cwd=ROOT,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    timeout=30,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertIn("NOTIFICATION_CENTER_OK", result.stdout)


if __name__ == "__main__":
    unittest.main()
