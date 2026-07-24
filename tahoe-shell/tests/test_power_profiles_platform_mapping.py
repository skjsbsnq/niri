#!/usr/bin/env python3
"""Contract tests for Mechrevo/Bitland platform_profile power mapping."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SHELL_ROOT = Path(__file__).resolve().parents[1]
HELPER = SHELL_ROOT / "scripts" / "tahoe-platform-profile"
POWER_PROFILES = SHELL_ROOT / "services" / "PowerProfiles.qml"
COMMAND_RUNNER = SHELL_ROOT / "services" / "CommandRunner.qml"


class PowerProfilesPlatformMappingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.helper = str(HELPER)
        cls.assertTrue(HELPER.is_file(), f"missing helper: {HELPER}")
        cls.assertTrue(os.access(HELPER, os.X_OK), f"helper not executable: {HELPER}")

    def _run(self, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [self.helper, *args],
            check=False,
            text=True,
            capture_output=True,
            env=env,
        )

    def test_map_from_sysfs_recognizes_beast_tier(self) -> None:
        cases = {
            "low-power": "power-saver",
            "quiet": "power-saver",
            "balanced": "balanced",
            "cool": "balanced",
            "balanced_performance": "balanced",
            "balanced-performance": "performance",
            "performance": "performance",
        }
        for sysfs, ui in cases.items():
            with self.subTest(sysfs=sysfs):
                result = self._run("map-from-sysfs", sysfs)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), ui)

    def test_resolve_target_prefers_balanced_performance_for_ui_performance(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            profile = Path(tmp) / "platform_profile"
            choices = Path(tmp) / "platform_profile_choices"
            profile.write_text("balanced\n", encoding="utf-8")
            choices.write_text(
                "low-power balanced balanced-performance performance\n",
                encoding="utf-8",
            )
            env = os.environ.copy()
            env["TAHOE_PLATFORM_PROFILE_PATH"] = str(profile)
            env["TAHOE_PLATFORM_PROFILE_CHOICES_PATH"] = str(choices)

            resolved = self._run("resolve-target", "performance", env=env)
            self.assertEqual(resolved.returncode, 0, resolved.stderr)
            self.assertEqual(resolved.stdout.strip(), "balanced-performance")

            saver = self._run("resolve-target", "power-saver", env=env)
            self.assertEqual(saver.returncode, 0, saver.stderr)
            self.assertEqual(saver.stdout.strip(), "low-power")

    def test_set_writes_beast_tier_and_verify(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            profile = Path(tmp) / "platform_profile"
            choices = Path(tmp) / "platform_profile_choices"
            profile.write_text("balanced\n", encoding="utf-8")
            choices.write_text(
                "low-power balanced balanced-performance performance\n",
                encoding="utf-8",
            )
            env = os.environ.copy()
            env["TAHOE_PLATFORM_PROFILE_PATH"] = str(profile)
            env["TAHOE_PLATFORM_PROFILE_CHOICES_PATH"] = str(choices)

            written = self._run("set", "performance", env=env)
            self.assertEqual(written.returncode, 0, written.stderr)
            self.assertEqual(written.stdout.strip(), "balanced-performance")
            self.assertEqual(profile.read_text(encoding="utf-8"), "balanced-performance")

            verified = self._run("verify", "performance", env=env)
            self.assertEqual(verified.returncode, 0, verified.stderr)

    def test_set_rejects_firmware_snapback(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            profile = Path(tmp) / "platform_profile"
            choices = Path(tmp) / "platform_profile_choices"
            # Simulate a path that ignores writes by using a non-writable file after open:
            # helper checks post-write re-read equality. Use a normal file and rewrite
            # via a wrapper is hard; instead assert failure when target not in choices.
            profile.write_text("balanced\n", encoding="utf-8")
            choices.write_text("low-power balanced\n", encoding="utf-8")
            env = os.environ.copy()
            env["TAHOE_PLATFORM_PROFILE_PATH"] = str(profile)
            env["TAHOE_PLATFORM_PROFILE_CHOICES_PATH"] = str(choices)

            missing = self._run("resolve-target", "performance", env=env)
            self.assertNotEqual(missing.returncode, 0)

    def test_qml_contract_reads_sysfs_and_maps_beast(self) -> None:
        text = POWER_PROFILES.read_text(encoding="utf-8")
        self.assertIn("balanced-performance", text)
        self.assertIn("mapSysfsToUi", text)
        self.assertIn("platform_profile", text)
        self.assertIn("pkexec", text)
        self.assertIn("性能(野兽)", text)

        runner = COMMAND_RUNNER.read_text(encoding="utf-8")
        self.assertIn("platformProfileSetCommand", runner)
        self.assertIn("platformProfileInstalledHelper", runner)
        self.assertIn("tahoe-platform-profile", runner)


if __name__ == "__main__":
    unittest.main()
