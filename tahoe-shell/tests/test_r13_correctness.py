#!/usr/bin/env python3
"""R13 notification, lock-screen, and startup correctness contracts."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NOTIFICATIONS = ROOT / "services" / "Notifications.qml"
TOAST = ROOT / "components" / "NotificationToast.qml"
CENTER = ROOT / "components" / "NotificationCenter.qml"
LOCK = ROOT / "components" / "LockScreen.qml"
STARTUP = ROOT / "components" / "settings" / "pages" / "StartupPage.qml"
SHELL = ROOT / "shell.qml"
QML_TEST = Path(__file__).with_name("tst_r13_notification_lifecycle.qml")


class R13CorrectnessTests(unittest.TestCase):
    def test_notifications_own_interaction_deadlines_and_dnd_withdrawal(self) -> None:
        service = NOTIFICATIONS.read_text(encoding="utf-8")
        self.assertIn("property var pausedExpireMap", service)
        self.assertIn("property var toastInteractionMap", service)
        self.assertRegex(service, r"function\s+setToastInteraction\s*\(")
        dnd_handler = re.search(
            r"onDndEnabledChanged:\s*\{(?P<body>.*?)\n\s*\}", service, re.DOTALL
        )
        self.assertIsNotNone(dnd_handler)
        self.assertIn("clearAll()", dnd_handler.group("body"))

    def test_toast_only_reports_interaction_to_notification_owner(self) -> None:
        toast = TOAST.read_text(encoding="utf-8")
        self.assertIn("setToastInteraction", toast)
        self.assertIn("onInteractionActiveChanged", toast)
        self.assertIn("Component.onDestruction", toast)
        self.assertNotIn("property var expireMap", toast)
        self.assertNotIn("Timer {\n            id: expireTimer", toast)

    def test_closed_notification_center_unloads_heavy_content(self) -> None:
        center = CENTER.read_text(encoding="utf-8")
        self.assertRegex(center, r"Loader\s*\{[^}]*id:\s*panelLoader", re.DOTALL)
        self.assertIn("active: root.open", center)
        self.assertIn("sourceComponent: panelComponent", center)
        self.assertRegex(center, r"Component\s*\{\s*id:\s*panelComponent", re.DOTALL)

    def test_lock_screen_has_one_password_state_and_clock_is_declared_first(self) -> None:
        lock = LOCK.read_text(encoding="utf-8")
        self.assertNotRegex(lock, r"property\s+string\s+password\b")
        self.assertEqual(lock.count('property string credentialText: ""'), 1)
        self.assertIn("root.pam.respond(root.credentialText)", lock)
        self.assertIn('root.credentialText = ""', lock)
        self.assertLess(
            lock.index("property SystemClock lockClock"),
            lock.index("clockNow: root.lockClock.date"),
        )

    def test_reported_startup_reference_errors_are_removed(self) -> None:
        shell = SHELL.read_text(encoding="utf-8")
        startup = STARTUP.read_text(encoding="utf-8")
        self.assertNotRegex(shell, r"Qt\.application\.font\s*=")
        self.assertIn('property string monoFontFamily: "Noto Sans Mono CJK SC"', shell)
        self.assertIn("id: addApplicationRow", startup)
        self.assertIn("addApplicationRow.modelData", startup)
        self.assertNotIn("addCandidateRow.modelData", startup)

    def test_real_qml_notification_lifecycle(self) -> None:
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


if __name__ == "__main__":
    unittest.main()
