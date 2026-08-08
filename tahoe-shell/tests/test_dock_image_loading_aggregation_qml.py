#!/usr/bin/env python3
"""Run the Dock async-icon freeze-gate aggregation in real Qt Quick.

Regression: WeChat's desktop entry uses an absolute-path Icon, so its dock
icon decodes asynchronously; a decode finishing while the autohide-hidden
dock is frozen (P02 updatesEnabled gate) used to drop the texture frame and
leave the icon invisible until hover. The dock must stay hot while any async
image is loading, and cool back down exactly when the last one finishes.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
QML_TEST = Path(__file__).with_name("tst_dock_image_loading_aggregation.qml")


def test_dock_image_loading_aggregation() -> None:
    qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
    runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
    assert runner is not None, "Qt 6 qmltestrunner is required for dock aggregation coverage"

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
