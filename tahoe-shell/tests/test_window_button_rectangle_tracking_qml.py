#!/usr/bin/env python3
"""Run the WindowButton ancestor-geometry regression in real Qt Quick."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
QML_TEST = Path(__file__).with_name("tst_window_button_rectangle_tracking.qml")


def test_window_button_rectangle_tracks_ancestor_motion() -> None:
    qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
    runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
    assert runner is not None, "Qt 6 qmltestrunner is required for Dock rectangle coverage"

    env = os.environ.copy()
    env["QT_QPA_PLATFORM"] = "offscreen"
    env["QT_QUICK_BACKEND"] = "software"
    env.pop("QML2_IMPORT_PATH", None)

    result = subprocess.run(
        [runner, "-input", str(QML_TEST)],
        cwd=SHELL_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, result.stdout
