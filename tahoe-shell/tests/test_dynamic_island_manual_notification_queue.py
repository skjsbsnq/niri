#!/usr/bin/env python3
"""Task 04: Dynamic Island manual IPC notifications must queue on the live FIFO."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
ISLAND = SHELL_ROOT / "services" / "DynamicIsland.qml"
QML_TEST = Path(__file__).with_name("tst_dynamic_island_manual_notification_queue.qml")


class DynamicIslandManualNotificationQueueTests(unittest.TestCase):
    def test_source_uses_single_tagged_fifo_for_manual(self) -> None:
        src = ISLAND.read_text(encoding="utf-8")
        show = re.search(
            r"function\s+showTransientNotification\s*\([^)]*\)\s*\{([\s\S]*?)\n    \}",
            src,
        )
        self.assertIsNotNone(show)
        body = show.group(1)
        self.assertIn("enqueuePendingNotificationEntry", body)
        self.assertIn('"kind": "manual"', body.replace("'", '"') if False else body)
        self.assertIn('kind": "manual"', body)
        # Must not early-return on busy without enqueue.
        self.assertNotRegex(
            body,
            r"if\s*\(\s*blocksTransientNotification\s*\(\s*\)\s*\)\s*\n\s*return\s*;",
        )
        # Single FIFO property only (no pendingManualNotifications).
        self.assertNotIn("pendingManualNotifications", src)
        self.assertEqual(len(re.findall(r"property\s+var\s+pendingNotificationIds\b", src)), 1)
        self.assertIn("function enqueuePendingNotificationEntry", src)
        self.assertIn('kind === "manual"', src)

    def test_real_qml_manual_notification_queue(self) -> None:
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(runner, "Qt 6 qmltestrunner is required")
        env = os.environ.copy()
        env.setdefault("QT_QPA_PLATFORM", "offscreen")
        local_qml = Path.home() / ".local" / "lib" / "qt6" / "qml"
        test_qml = SHELL_ROOT / "tests" / "qml_imports"
        existing = env.get("QML2_IMPORT_PATH", "")
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
