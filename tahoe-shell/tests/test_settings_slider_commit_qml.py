#!/usr/bin/env python3

import os
import shutil
import subprocess
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
QML_TEST = Path(__file__).with_name("tst_settings_slider_commit.qml")


def test_real_qml_settings_slider_commit() -> None:
    qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
    runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
    assert runner is not None, "Qt 6 qmltestrunner is required for slider lifecycle coverage"
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
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, result.stdout
