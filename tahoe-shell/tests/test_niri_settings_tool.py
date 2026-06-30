from __future__ import annotations

import importlib.util
import json
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "services" / "niri_settings_tool.py"
FIXTURES = Path(__file__).resolve().parent / "fixtures" / "niri-settings"

spec = importlib.util.spec_from_file_location("niri_settings_tool", TOOL_PATH)
assert spec and spec.loader
niri_settings_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(niri_settings_tool)


def read_fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def write_fake_niri(path: Path, exit_code: int, message: str) -> None:
    path.write_text(f"#!/bin/sh\necho {message!r}\nexit {exit_code}\n", encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class NiriSettingsToolTests(unittest.TestCase):
    def test_layout_write_matches_golden_and_preserves_unmanaged_block(self) -> None:
        original = read_fixture("managed.kdl")
        updated = niri_settings_tool.update_field(original, "layout.gaps", "24")

        self.assertEqual(updated, read_fixture("managed-gaps-24.kdl"))
        self.assertIn('custom-user-token "keep-me"', updated)
        self.assertEqual(
            original[original.index("window-rule {"): original.index("// tahoe-managed: begin animations")],
            updated[updated.index("window-rule {"): updated.index("// tahoe-managed: begin animations")],
        )

    def test_unmarked_target_block_is_rejected_with_recovery_hint(self) -> None:
        text = "\n".join(
            line for line in read_fixture("managed.kdl").splitlines()
            if not line.startswith("// tahoe-managed:")
        ) + "\n"

        with self.assertRaises(niri_settings_tool.KdlEditError) as raised:
            niri_settings_tool.update_field(text, "layout.gaps", "24")

        error = str(raised.exception)
        self.assertIn("refusing to edit layout.gaps", error)
        self.assertIn("layout block is not Tahoe-managed", error)
        self.assertIn("Recovery:", error)

    def test_duplicate_target_block_is_rejected(self) -> None:
        text = read_fixture("managed.kdl") + "\nlayout {\n    gaps 4\n}\n"

        with self.assertRaises(niri_settings_tool.KdlEditError) as raised:
            niri_settings_tool.update_field(text, "layout.gaps", "24")

        self.assertIn("expected exactly one top-level layout block, found 2", str(raised.exception))

    def test_cli_successful_write_uses_atomic_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = tmp_path / "config.kdl"
            config.write_text(read_fixture("managed.kdl"), encoding="utf-8")
            fake_niri = tmp_path / "niri-ok"
            write_fake_niri(fake_niri, 0, "config is valid")

            result = subprocess.run(
                [
                    sys.executable,
                    str(TOOL_PATH),
                    "write",
                    "--config",
                    str(config),
                    "--field",
                    "layout.gaps",
                    "--value",
                    "24",
                    "--niri-bin",
                    str(fake_niri),
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(result.stdout)
            self.assertTrue(payload["ok"])
            self.assertTrue(payload["changed"])
            self.assertEqual(payload["layout"]["gaps"], 24)
            self.assertEqual(config.read_text(encoding="utf-8"), read_fixture("managed-gaps-24.kdl"))
            self.assertEqual(list(tmp_path.glob(".config.kdl.*.tmp")), [])

    def test_validate_failure_preserves_live_config(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = tmp_path / "config.kdl"
            original = read_fixture("managed.kdl")
            config.write_text(original, encoding="utf-8")
            fake_niri = tmp_path / "niri-fail"
            write_fake_niri(fake_niri, 1, "bad config near layout")

            result = subprocess.run(
                [
                    sys.executable,
                    str(TOOL_PATH),
                    "write",
                    "--config",
                    str(config),
                    "--field",
                    "layout.gaps",
                    "--value",
                    "24",
                    "--niri-bin",
                    str(fake_niri),
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            payload = json.loads(result.stdout)
            self.assertFalse(payload["ok"])
            self.assertIn("niri validate failed", payload["error"])
            self.assertIn("bad config near layout", payload["error"])
            self.assertEqual(config.read_text(encoding="utf-8"), original)
            self.assertEqual(list(tmp_path.glob(".config.kdl.*.tmp")), [])


if __name__ == "__main__":
    unittest.main()
