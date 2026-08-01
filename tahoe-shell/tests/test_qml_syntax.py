#!/usr/bin/env python3
"""QML syntax guardrail: every production .qml file must parse cleanly.

Text-contract tests cannot catch brace/paren imbalances (T-31's async
Wallpaper rewrite shipped a `}` missing its `)` and the health Timer's
closing brace, which quickshell reported as "Expected token `)'" and the
shell failed to load — a dead desktop that looked like a compositor freeze).
qmllint is the authoritative parser; only [syntax]/[error] lines fail.
"""

from __future__ import annotations

import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _runner() -> str:
    qt6 = Path("/usr/lib/qt6/bin/qmllint")
    if qt6.is_file():
        return str(qt6)
    found = shutil.which("qmllint")
    assert found is not None, "qmllint is required for QML syntax coverage"
    return found


class QmlSyntaxTests(unittest.TestCase):
    def test_all_production_qml_files_parse(self) -> None:
        runner = _runner()
        qml_files = sorted(ROOT.rglob("*.qml"))
        self.assertTrue(qml_files, "no QML files found")
        failures = []
        for qml in qml_files:
            proc = subprocess.run(
                [runner, str(qml)],
                capture_output=True,
                text=True,
                timeout=60,
                check=False,
            )
            out = (proc.stdout or "") + (proc.stderr or "")
            bad = [ln for ln in out.splitlines() if "[syntax]" in ln or "[error]" in ln]
            if bad:
                failures.append(f"{qml.relative_to(ROOT)}:\n" + "\n".join(bad))
        self.assertEqual(failures, [])


if __name__ == "__main__":
    unittest.main()
