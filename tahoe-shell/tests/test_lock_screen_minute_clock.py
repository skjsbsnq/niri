#!/usr/bin/env python3
"""Task 22 + Task 12B: LockScreen consumes SystemClock Minutes owner.

Root waste (Task 22 old code):
  - Timer { interval: 1000 } while display is only HH:mm

Root gap (Task 12B):
  - LockScreen still owned date + minuteTimer instead of SystemClock
  - No SystemClock.resync on lock / ApplicationActive

Fix contract:
  - No parallel minuteTimer in LockScreen
  - SystemClock precision=Minutes is the sole wall-clock owner
  - unlocked → enabled=false; lock/ApplicationActive → resync()
  - UI HH:mm and date line both read SystemClock.date
  - No claim of sub-minute OS time-jump notification without resync
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
LOCK_SCREEN = SHELL_ROOT / "components" / "LockScreen.qml"
SHELL = SHELL_ROOT / "shell.qml"
WAYLAND_LOCK_MOCK = (
    SHELL_ROOT / "tests" / "qml_imports" / "Quickshell" / "Wayland" / "WlSessionLock.qml"
)
QML_TEST = Path(__file__).with_name("tst_lock_screen_minute_clock.qml")


def _extract_function_body(src: str, name: str) -> str:
    m = re.search(rf"function\s+{re.escape(name)}\s*\([^)]*\)\s*\{{", src)
    if not m:
        return ""
    start = m.end()
    depth = 1
    i = start
    while i < len(src) and depth:
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return src[start : i - 1]


class LockScreenSystemClockContractTests(unittest.TestCase):
    def test_no_parallel_minute_timer(self) -> None:
        src = LOCK_SCREEN.read_text(encoding="utf-8")
        self.assertNotIn("minuteTimer", src)
        self.assertNotIn("msecsToNextMinute", src)
        self.assertEqual(len(re.findall(r"\bTimer\s*\{", src)), 0)

    def test_uses_system_clock_minutes(self) -> None:
        src = LOCK_SCREEN.read_text(encoding="utf-8")
        self.assertIn("SystemClock", src)
        self.assertIn("precision: SystemClock.Minutes", src)
        self.assertIn("enabled: root.locked", src)
        self.assertIn("lockClock", src)

    def test_sync_calls_system_clock_resync(self) -> None:
        src = LOCK_SCREEN.read_text(encoding="utf-8")
        sync = _extract_function_body(src, "syncLockClock")
        self.assertIn("lockClock.resync()", sync)
        self.assertNotIn("new Date()", sync)
        lock = _extract_function_body(src, "lock")
        self.assertIn("syncLockClock", lock)

    def test_application_active_uses_same_resync(self) -> None:
        src = LOCK_SCREEN.read_text(encoding="utf-8")
        self.assertIn("ApplicationActive", src)
        self.assertIn("syncLockClock", src)
        # Single resync entry — no parallel refresh name.
        self.assertNotIn("updateNow", src)
        self.assertNotIn("refreshClock", src)

    def test_display_binds_clock_date(self) -> None:
        src = LOCK_SCREEN.read_text(encoding="utf-8")
        self.assertIn('Qt.formatDateTime(root.clockNow, "HH:mm")', src)
        self.assertIn("readonly property date clockNow: root.lockClock.date", src)
        # No local writable date owner (must be readonly binding to SystemClock).
        self.assertRegex(src, r"readonly\s+property\s+date\s+clockNow\s*:\s*root\.lockClock\.date")
        self.assertNotRegex(src, r"property\s+date\s+clockNow\s*:\s*new\s+Date")

    def test_process_wide_owners_are_not_captured_by_surface_component(self) -> None:
        src = LOCK_SCREEN.read_text(encoding="utf-8")
        self.assertRegex(src, r"property\s+SystemClock\s+lockClock\s*:\s*SystemClock")
        self.assertRegex(src, r"property\s+PamContext\s+pam\s*:\s*PamContext")
        self.assertIn("root.lockClock.resync()", src)
        self.assertIn("root.pam.start()", src)
        self.assertEqual(src.count('property string credentialText: ""'), 1)
        self.assertIn("onCredentialTextChanged", src)
        self.assertIn("passwordInput.text = root.credentialText", src)
        self.assertIn("root.pam.respond(root.credentialText)", src)
        self.assertNotIn("passwordInput.text", _extract_function_body(src, "resetPasswordInput"))
        self.assertNotIn("passwordInput.text", _extract_function_body(src, "submitPassword"))

    def test_r14_motion_feedback_and_bounded_secure_exit(self) -> None:
        src = LOCK_SCREEN.read_text(encoding="utf-8")
        shell = SHELL.read_text(encoding="utf-8")
        button_surface = (
            SHELL_ROOT / "components" / "controls" / "ButtonSurface.qml"
        ).read_text(encoding="utf-8")
        self.assertIn('import "Motion.js" as Motion', src)
        self.assertIn('import "controls" as Controls', src)
        self.assertIn("Controls.IconButton", src)
        self.assertIn("Motion.pressScaleFor", button_surface)
        self.assertIn("property bool unlocking", src)
        self.assertIn("Math.min(180, Motion.panelExit(settingsService))", src)
        self.assertIn("property SequentialAnimation unlockSequence", src)
        self.assertIn("root.beginUnlock()", src)
        self.assertNotIn("root.unlock();\n                return;", src)
        self.assertIn("failureFeedbackSerial", src)
        self.assertIn("triggerAuthenticationFailure", src)
        self.assertIn("Behavior on border.color", src)
        self.assertIn("id: failureShakeAnimation", src)
        self.assertIn("renderedText", src)
        self.assertNotIn("SpringAnimation", src)
        self.assertRegex(
            shell,
            r"LockScreen\s*\{[^}]*settingsService:\s*desktopSettings",
            re.DOTALL,
        )

    def test_wayland_mock_models_two_surfaces_and_secure_release(self) -> None:
        mock = WAYLAND_LOCK_MOCK.read_text(encoding="utf-8")
        self.assertIn("default property Component surface", mock)
        self.assertIn("property int screenCount: 2", mock)
        self.assertIn("surface.createObject(root)", mock)
        self.assertIn("root.secure = root.surfaceInstances.length === root.screenCount", mock)
        self.assertIn("root.secure = false", mock)
        self.assertIn("root.releaseSurfaces()", mock)

    def test_real_qml_lock_screen_system_clock(self) -> None:
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(runner, "Qt 6 qmltestrunner is required")
        env = os.environ.copy()
        env.setdefault("QT_QPA_PLATFORM", "offscreen")
        local_qml = Path.home() / ".local" / "lib" / "qt6" / "qml"
        test_qml = SHELL_ROOT / "tests" / "qml_imports"
        existing = env.get("QML2_IMPORT_PATH", "")
        # Test imports first so SystemClock/Wayland/Pam stubs load under runner.
        paths = [str(test_qml), str(local_qml)]
        if existing:
            paths.append(existing)
        env["QML2_IMPORT_PATH"] = ":".join(paths)
        result = subprocess.run(
            [runner, "-input", str(QML_TEST)],
            cwd=SHELL_ROOT,
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
