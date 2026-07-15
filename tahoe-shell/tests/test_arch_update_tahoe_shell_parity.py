"""T01: Tahoe shell source/runtime parity gate in scripts/arch-update.sh."""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SHELL_ROOT.parent
ARCH_UPDATE = REPO_ROOT / "scripts" / "arch-update.sh"
COMPAT_SCRIPT = REPO_ROOT / "scripts" / "check-xwayland-satellite-compat.sh"


class ArchUpdateTahoeShellParityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.assertTrue(ARCH_UPDATE.is_file(), f"missing {ARCH_UPDATE}")
        self.assertTrue(os.access(ARCH_UPDATE, os.X_OK), f"not executable: {ARCH_UPDATE}")
        self._tmpdir = tempfile.TemporaryDirectory(prefix="tahoe-shell-parity-")
        self.root = Path(self._tmpdir.name)
        self.source = self.root / "source"
        self.dest = self.root / "dest"
        self.state = self.root / "state"
        self.overlay = self.root / "overlay" / "check-xwayland-satellite-compat.sh"
        self.state.mkdir()
        self._build_minimal_source()

    def tearDown(self) -> None:
        self._tmpdir.cleanup()

    def _build_minimal_source(self) -> None:
        (self.source / "components").mkdir(parents=True)
        (self.source / "services").mkdir(parents=True)
        (self.source / "scripts").mkdir(parents=True)
        (self.source / "shell.qml").write_text("// shell\n", encoding="utf-8")
        (self.source / "components" / "DynamicIsland.qml").write_text(
            "// island\n", encoding="utf-8"
        )
        (self.source / "services" / "DynamicIsland.qml").write_text(
            "// service\n", encoding="utf-8"
        )
        # Cache noise that must be excluded from desired tree and ignored at dest.
        pycache = self.source / "services" / "__pycache__"
        pycache.mkdir()
        (pycache / "noise.cpython-314.pyc").write_bytes(b"\0\1\2")
        (self.source / "services" / "stale.pyc").write_bytes(b"pyc")
        pytest_cache = self.source / ".pytest_cache"
        pytest_cache.mkdir()
        (pytest_cache / "v").write_text("cache\n", encoding="utf-8")

        self.overlay.parent.mkdir(parents=True)
        self.overlay.write_text("#!/usr/bin/env bash\necho ok\n", encoding="utf-8")
        self.overlay.chmod(self.overlay.stat().st_mode | stat.S_IXUSR)

    def _env(self) -> dict[str, str]:
        env = os.environ.copy()
        env.update(
            {
                "REPO_DIR": str(self.root / "repo"),
                "TAHOE_SHELL_DIR": str(self.source),
                "TAHOE_CONFIG_DIR": str(self.dest),
                "TAHOE_STATE_DIR": str(self.state),
                "XWAYLAND_SATELLITE_COMPAT_CHECK_SCRIPT": str(self.overlay),
                "TAHOE_XWAYLAND_COMPAT_CHECK_TARGET": str(
                    self.dest / "scripts" / "check-xwayland-satellite-compat.sh"
                ),
            }
        )
        # Avoid accidental git/repo assumptions for deploy-only mode.
        return env

    def _run(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(ARCH_UPDATE), *args],
            env=self._env(),
            text=True,
            capture_output=True,
            check=False,
        )

    def test_deploy_and_verify_pass_when_consistent(self) -> None:
        deploy = self._run("--deploy-tahoe-shell")
        self.assertEqual(
            deploy.returncode,
            0,
            msg=f"stdout:\n{deploy.stdout}\nstderr:\n{deploy.stderr}",
        )
        self.assertTrue((self.dest / "shell.qml").is_file())
        self.assertTrue(
            (self.dest / "scripts" / "check-xwayland-satellite-compat.sh").is_file()
        )
        # Cache artifacts must not be required / synced as desired content.
        self.assertFalse((self.dest / "services" / "__pycache__").exists())
        self.assertFalse((self.dest / "services" / "stale.pyc").exists())
        self.assertFalse((self.dest / ".pytest_cache").exists())

        # State files recorded under TAHOE_STATE_DIR only.
        self.assertTrue((self.state / "tahoe-shell-deployed-manifest.sha256").is_file())
        self.assertTrue((self.state / "tahoe-shell-deployed-root-commit").is_file())
        self.assertTrue((self.state / "tahoe-shell-deployed-manifest.txt").is_file())

        verify = self._run("--verify-tahoe-shell")
        self.assertEqual(
            verify.returncode,
            0,
            msg=f"stdout:\n{verify.stdout}\nstderr:\n{verify.stderr}",
        )
        self.assertIn("parity OK", verify.stdout)

    def test_verify_fails_when_target_file_modified(self) -> None:
        self.assertEqual(self._run("--deploy-tahoe-shell").returncode, 0)
        target = self.dest / "shell.qml"
        target.write_text("// tampered\n", encoding="utf-8")
        verify = self._run("--verify-tahoe-shell")
        self.assertNotEqual(verify.returncode, 0)
        combined = verify.stdout + verify.stderr
        self.assertIn("content differs", combined)
        self.assertIn("shell.qml", combined)

    def test_verify_fails_when_target_file_deleted(self) -> None:
        self.assertEqual(self._run("--deploy-tahoe-shell").returncode, 0)
        (self.dest / "components" / "DynamicIsland.qml").unlink()
        verify = self._run("--verify-tahoe-shell")
        self.assertNotEqual(verify.returncode, 0)
        combined = verify.stdout + verify.stderr
        self.assertIn("missing deployed file", combined)
        self.assertIn("DynamicIsland.qml", combined)

    def test_verify_fails_when_extra_source_file_not_deployed(self) -> None:
        self.assertEqual(self._run("--deploy-tahoe-shell").returncode, 0)
        (self.source / "components" / "NewOnlyInSource.qml").write_text(
            "// new\n", encoding="utf-8"
        )
        verify = self._run("--verify-tahoe-shell")
        self.assertNotEqual(verify.returncode, 0)
        combined = verify.stdout + verify.stderr
        self.assertIn("missing deployed file", combined)
        self.assertIn("NewOnlyInSource.qml", combined)

    def test_verify_fails_when_extra_file_present_at_destination(self) -> None:
        self.assertEqual(self._run("--deploy-tahoe-shell").returncode, 0)
        (self.dest / "extra-stale.qml").write_text("// extra\n", encoding="utf-8")
        verify = self._run("--verify-tahoe-shell")
        self.assertNotEqual(verify.returncode, 0)
        combined = verify.stdout + verify.stderr
        self.assertIn("extra deployed file", combined)
        self.assertIn("extra-stale.qml", combined)

    def test_allowed_runtime_cache_does_not_fail_verify(self) -> None:
        self.assertEqual(self._run("--deploy-tahoe-shell").returncode, 0)
        cache_dir = self.dest / "services" / "__pycache__"
        cache_dir.mkdir(parents=True, exist_ok=True)
        (cache_dir / "runtime.cpython-314.pyc").write_bytes(b"\x00")
        (self.dest / "services" / "runtime.pyc").write_bytes(b"\x01")
        pytest_cache = self.dest / ".pytest_cache"
        pytest_cache.mkdir(exist_ok=True)
        (pytest_cache / "v").write_text("ok\n", encoding="utf-8")
        verify = self._run("--verify-tahoe-shell")
        self.assertEqual(
            verify.returncode,
            0,
            msg=f"stdout:\n{verify.stdout}\nstderr:\n{verify.stderr}",
        )

    def test_verify_is_read_only(self) -> None:
        self.assertEqual(self._run("--deploy-tahoe-shell").returncode, 0)
        before = {
            p.relative_to(self.dest): p.read_bytes()
            for p in self.dest.rglob("*")
            if p.is_file()
        }
        verify = self._run("--verify-tahoe-shell")
        self.assertEqual(verify.returncode, 0)
        after = {
            p.relative_to(self.dest): p.read_bytes()
            for p in self.dest.rglob("*")
            if p.is_file()
        }
        self.assertEqual(before, after)

    def test_arch_update_documents_parity_modes(self) -> None:
        text = ARCH_UPDATE.read_text(encoding="utf-8")
        for needle in (
            "--verify-tahoe-shell",
            "--deploy-tahoe-shell",
            "write_tahoe_shell_desired_manifest",
            "verify_tahoe_shell_parity_from_manifest",
            "TAHOE_SHELL_RSYNC_EXCLUDES",
            "sync_tahoe_shell_tree",
            "record_tahoe_shell_deploy_state",
        ):
            self.assertIn(needle, text)

    def test_no_parallel_deploy_script_added(self) -> None:
        scripts = REPO_ROOT / "scripts"
        banned = list(scripts.glob("*dynamic-island*deploy*")) + list(
            scripts.glob("deploy-dynamic-island*")
        )
        self.assertEqual(banned, [])

    def test_production_shell_has_no_git_deploy_reader(self) -> None:
        island = SHELL_ROOT / "services" / "DynamicIsland.qml"
        text = island.read_text(encoding="utf-8")
        self.assertNotIn("git rev-parse", text)
        self.assertNotIn("deployed-manifest", text)


if __name__ == "__main__":
    unittest.main()
