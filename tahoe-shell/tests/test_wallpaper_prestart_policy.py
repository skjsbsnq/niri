from __future__ import annotations

import json
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
PRESTART = SHELL_ROOT / "scripts" / "prestart-wallpaper.sh"
START = SHELL_ROOT / "scripts" / "start-quickshell.sh"


class WallpaperPrestartPolicyTests(unittest.TestCase):
    def run_external_prestart(
        self, pause_when_fullscreen: bool
    ) -> tuple[list[str], Path, dict[str, object]]:
        temp = tempfile.TemporaryDirectory(prefix="tahoe-wallpaper-prestart-")
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        home = root / "home"
        state = root / "state"
        bin_dir = root / "bin"
        arg_log = root / "wallpaper-args.json"
        bin_dir.mkdir(parents=True)
        state.mkdir(parents=True)

        settings = {
            "wallpaperMode": "external",
            "wallpaperEngineFps": 12,
            "wallpaperEngineIdleFps": 8,
            "wallpaperPauseWhenFullscreen": pause_when_fullscreen,
        }
        (state / "desktop-settings.json").write_text(
            json.dumps(settings), encoding="utf-8"
        )

        active_dir = home / ".config" / "Linux Wallpaper Engine"
        active_dir.mkdir(parents=True)
        (active_dir / "active-wallpapers.json").write_text(
            json.dumps(
                {
                    "activeWallpapers": {
                        "eDP-2": {
                            "backgroundId": "/wallpapers/example",
                            "screen": "eDP-2",
                            "scaling": "fill",
                            "fps": 30,
                            "silent": True,
                        }
                    }
                }
            ),
            encoding="utf-8",
        )

        niri = bin_dir / "niri"
        niri.write_text(
            "#!/usr/bin/env python3\n"
            "import json\n"
            'print(json.dumps({"eDP-2": {}}))\n',
            encoding="utf-8",
        )
        niri.chmod(0o755)

        wallpaper = bin_dir / "linux-wallpaperengine"
        wallpaper.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys, time\n"
            'open(os.environ["ARG_LOG"], "w", encoding="utf-8").write('
            "json.dumps(sys.argv[1:]))\n"
            "time.sleep(0.4)\n",
            encoding="utf-8",
        )
        wallpaper.chmod(0o755)

        env = os.environ.copy()
        env.update(
            {
                "HOME": str(home),
                "TAHOE_STATE_DIR": str(state),
                "ARG_LOG": str(arg_log),
                "PATH": str(bin_dir) + os.pathsep + env.get("PATH", ""),
            }
        )
        subprocess.run(["bash", str(PRESTART)], env=env, check=True, timeout=10)

        deadline = time.monotonic() + 2
        while not arg_log.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(arg_log.exists(), "fake wallpaper engine did not start")
        record_path = state / "wallpaper-prestart" / "eDP-2.json"
        while not record_path.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(record_path.exists(), "per-output adoption record was not written")
        return (
            json.loads(arg_log.read_text(encoding="utf-8")),
            state,
            json.loads(record_path.read_text(encoding="utf-8")),
        )

    def test_external_prestart_captures_full_size_frame_per_output(self) -> None:
        args, state, record = self.run_external_prestart(True)
        self.assertIn("--screenshot", args)
        capture_index = args.index("--screenshot")
        self.assertEqual(
            args[capture_index + 1], str(state / "lock-wallpaper" / "eDP-2.png")
        )
        self.assertIn("--screenshot-delay", args)
        self.assertEqual(args[args.index("--screenshot-delay") + 1], "5")
        self.assertNotIn("--no-fullscreen-pause", args)
        self.assertEqual(record["output"], "eDP-2")
        self.assertEqual(record["mode"], "external")
        self.assertIsInstance(record["pid"], int)
        self.assertRegex(str(record["token"]), r"^[0-9a-f]{32}$")
        self.assertRegex(str(record["startTime"]), r"^[0-9]+$")
        self.assertIn("lock-wallpaper/eDP-2.png", str(record["command"]))
        record_path = state / "wallpaper-prestart" / "eDP-2.json"
        deadline = time.monotonic() + 2
        while record_path.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertFalse(record_path.exists(), "supervisor left a stale adoption record")

    def test_external_prestart_can_disable_native_fullscreen_pause(self) -> None:
        args, _, record = self.run_external_prestart(False)
        self.assertEqual(args.count("--no-fullscreen-pause"), 1)
        self.assertEqual(str(record["command"]).count("--no-fullscreen-pause"), 1)

    def test_external_prestart_honors_explicit_effect_flags(self) -> None:
        """UX false for disableParallax/Particles must match Wallpaper.qml exactly."""
        with tempfile.TemporaryDirectory(prefix="tahoe-wallpaper-effects-") as temp:
            root = Path(temp)
            home = root / "home"
            state = root / "state"
            bin_dir = root / "bin"
            arg_log = root / "wallpaper-args.json"
            bin_dir.mkdir(parents=True)
            state.mkdir(parents=True)
            (state / "desktop-settings.json").write_text(
                json.dumps(
                    {
                        "wallpaperMode": "external",
                        "wallpaperEngineFps": 12,
                        "wallpaperEngineIdleFps": 8,
                        "wallpaperPauseWhenFullscreen": True,
                    }
                ),
                encoding="utf-8",
            )
            active_dir = home / ".config" / "Linux Wallpaper Engine"
            active_dir.mkdir(parents=True)
            (active_dir / "active-wallpapers.json").write_text(
                json.dumps(
                    {
                        "activeWallpapers": {
                            "eDP-2": {
                                "backgroundId": "/wallpapers/example",
                                "screen": "eDP-2",
                                "scaling": "fill",
                                "fps": 30,
                                "silent": True,
                                "disableParallax": False,
                                "disableParticles": False,
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            niri = bin_dir / "niri"
            niri.write_text(
                "#!/usr/bin/env python3\n"
                "import json\n"
                'print(json.dumps({"eDP-2": {}}))\n',
                encoding="utf-8",
            )
            niri.chmod(0o755)
            wallpaper = bin_dir / "linux-wallpaperengine"
            wallpaper.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys, time\n"
                'open(os.environ["ARG_LOG"], "w", encoding="utf-8").write('
                "json.dumps(sys.argv[1:]))\n"
                "time.sleep(0.4)\n",
                encoding="utf-8",
            )
            wallpaper.chmod(0o755)
            env = os.environ.copy()
            env.update(
                {
                    "HOME": str(home),
                    "TAHOE_STATE_DIR": str(state),
                    "ARG_LOG": str(arg_log),
                    "PATH": str(bin_dir) + os.pathsep + env.get("PATH", ""),
                }
            )
            subprocess.run(["bash", str(PRESTART)], env=env, check=True, timeout=10)
            deadline = time.monotonic() + 2
            while not arg_log.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(arg_log.exists())
            args = json.loads(arg_log.read_text(encoding="utf-8"))
            self.assertNotIn("--disable-parallax", args)
            self.assertNotIn("--disable-particles", args)

    def test_prestart_without_announced_outputs_defers_to_quickshell(self) -> None:
        with tempfile.TemporaryDirectory(prefix="tahoe-wallpaper-no-output-") as temp:
            root = Path(temp)
            home = root / "home"
            state = root / "state"
            bin_dir = root / "bin"
            marker = root / "started"
            state.mkdir(parents=True)
            bin_dir.mkdir(parents=True)
            (state / "desktop-settings.json").write_text(
                json.dumps(
                    {
                        "wallpaperMode": "dynamic",
                        "dynamicWallpaperCommand": "linux-wallpaperengine demo",
                    }
                ),
                encoding="utf-8",
            )
            niri = bin_dir / "niri"
            niri.write_text("#!/bin/sh\nprintf '{}\\n'\n", encoding="utf-8")
            niri.chmod(0o755)
            wallpaper = bin_dir / "linux-wallpaperengine"
            wallpaper.write_text(
                "#!/bin/sh\nprintf started >\"$MARKER\"\n", encoding="utf-8"
            )
            wallpaper.chmod(0o755)
            env = os.environ.copy()
            env.update(
                {
                    "HOME": str(home),
                    "TAHOE_STATE_DIR": str(state),
                    "MARKER": str(marker),
                    "PATH": str(bin_dir) + os.pathsep + env.get("PATH", ""),
                }
            )
            subprocess.run(["bash", str(PRESTART)], env=env, check=True, timeout=10)
            self.assertFalse(marker.exists())
            self.assertEqual(list((state / "wallpaper-prestart").glob("*.json")), [])

    def test_nested_launcher_never_touches_live_wallpaper_state(self) -> None:
        with tempfile.TemporaryDirectory(prefix="tahoe-wallpaper-nested-") as temp:
            root = Path(temp)
            config = root / "config"
            scripts = config / "scripts"
            state = root / "state"
            prestart_marker = root / "prestarted"
            quickshell_marker = root / "quickshell"
            scripts.mkdir(parents=True)
            state.mkdir(parents=True)
            fake_prestart = scripts / "prestart-wallpaper.sh"
            fake_prestart.write_text(
                "#!/bin/sh\nprintf prestarted >\"$PRESTART_MARKER\"\n",
                encoding="utf-8",
            )
            fake_prestart.chmod(0o755)
            fake_quickshell = root / "quickshell"
            fake_quickshell.write_text(
                "#!/bin/sh\nprintf quickshell >\"$QUICKSHELL_MARKER\"\n",
                encoding="utf-8",
            )
            fake_quickshell.chmod(0o755)
            env = os.environ.copy()
            env.update(
                {
                    "TAHOE_CONFIG_DIR": str(config),
                    "TAHOE_STATE_DIR": str(state),
                    "TAHOE_QUICKSHELL_BIN": str(fake_quickshell),
                    "TAHOE_NESTED_SESSION": "1",
                    "PRESTART_MARKER": str(prestart_marker),
                    "QUICKSHELL_MARKER": str(quickshell_marker),
                }
            )
            subprocess.run(["bash", str(START)], env=env, check=True, timeout=10)
            self.assertFalse(prestart_marker.exists())
            self.assertTrue(quickshell_marker.exists())

    def test_stale_record_never_kills_a_reused_pid(self) -> None:
        with tempfile.TemporaryDirectory(prefix="tahoe-wallpaper-stale-") as temp:
            root = Path(temp)
            state = root / "state"
            records = state / "wallpaper-prestart"
            records.mkdir(parents=True)
            (state / "desktop-settings.json").write_text(
                json.dumps({"wallpaperMode": "static"}), encoding="utf-8"
            )
            sleeper = subprocess.Popen(["sleep", "10"])
            try:
                (records / "eDP-2.json").write_text(
                    json.dumps(
                        {
                            "pid": sleeper.pid,
                            "token": "0" * 32,
                            "startTime": "0",
                            "output": "eDP-2",
                            "mode": "external",
                            "command": "linux-wallpaperengine demo",
                        },
                        separators=(",", ":"),
                    ),
                    encoding="utf-8",
                )
                env = os.environ.copy()
                env.update(
                    {
                        "HOME": str(root / "home"),
                        "TAHOE_STATE_DIR": str(state),
                    }
                )
                subprocess.run(["bash", str(PRESTART)], env=env, check=True, timeout=10)
                self.assertIsNone(sleeper.poll(), "stale record killed an unrelated process")
                self.assertFalse((records / "eDP-2.json").exists())
            finally:
                sleeper.terminate()
                sleeper.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
