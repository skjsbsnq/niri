#!/usr/bin/env python3
"""R14 direct-scanout and background budget contracts."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SHELL_ROOT.parent
WINDOW_MODEL = SHELL_ROOT / "services" / "windows" / "WindowModel.js"
WINDOWS = SHELL_ROOT / "services" / "Windows.qml"
SHELL = SHELL_ROOT / "shell.qml"
TOPBAR = SHELL_ROOT / "components" / "TopBar.qml"
DOCK = SHELL_ROOT / "components" / "Dock.qml"
ISLAND = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
WALLPAPER = SHELL_ROOT / "components" / "Wallpaper.qml"
PRESTART = SHELL_ROOT / "scripts" / "prestart-wallpaper.sh"
SIDEBAR = SHELL_ROOT / "components" / "LeftSidebar.qml"
WEATHER = SHELL_ROOT / "components" / "LeftSidebarWeather.qml"
RUN_SESSION = REPO_ROOT / "scripts" / "run-tahoe-session.sh"
LOGIN_SESSION = REPO_ROOT / "scripts" / "tahoe-niri-session.sh"
SCRIPTS_README = REPO_ROOT / "scripts" / "README.md"
FRAME_CLOCK = REPO_ROOT / "niri" / "src" / "frame_clock.rs"
TTY = REPO_ROOT / "niri" / "src" / "backend" / "tty.rs"


def function_body(source: str, name: str) -> str:
    match = re.search(rf"function\s+{re.escape(name)}\s*\([^)]*\)\s*\{{", source)
    if not match:
        return ""
    depth = 1
    index = match.end()
    while index < len(source) and depth:
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
        index += 1
    return source[match.end() : index - 1]


def shell_function_body(source: str, name: str) -> str:
    match = re.search(rf"(?m)^{re.escape(name)}\(\)\s*\{{", source)
    if not match:
        return ""
    depth = 1
    index = match.end()
    while index < len(source) and depth:
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
        index += 1
    return source[match.end() : index - 1]


class R14DirectScanoutBudgetTests(unittest.TestCase):
    def test_fullscreen_outputs_come_from_toplevel_state(self) -> None:
        model = WINDOW_MODEL.read_text(encoding="utf-8")
        windows = WINDOWS.read_text(encoding="utf-8")
        self.assertIn("function fullscreenOutputNames(", model)
        self.assertIn("readonly property var fullscreenOutputNames", windows)
        self.assertIn("function fullscreenOnOutput(", windows)
        self.assertIn("readonly property bool anyFullscreen", windows)
        self.assertNotIn("tile_size", function_body(model, "fullscreenOutputNames"))

    @unittest.skipUnless(shutil.which("node"), "node is required")
    def test_fullscreen_output_helper_is_exact_and_deduplicated(self) -> None:
        runner = r'''
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(process.argv[1], "utf8").replace(/^\s*\.pragma library\s*\n/, "");
const context = { Array, Boolean, Date, JSON, Math, Number, Object, String, console, isFinite };
vm.createContext(context);
vm.runInContext(source, context, { filename: process.argv[1] });
const names = context.fullscreenOutputNames([
  { fullscreen: false, screens: [{ name: "eDP-2" }] },
  { fullscreen: true, screens: [{ name: "HDMI-A-1" }, { name: "eDP-2" }] },
  { fullscreen: true, screens: [{ name: "eDP-2" }] },
  { fullscreen: true, screens: [] },
]);
process.stdout.write(JSON.stringify(names));
'''
        result = subprocess.run(
            ["node", "-e", runner, str(WINDOW_MODEL)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        )
        self.assertEqual(json.loads(result.stdout), ["HDMI-A-1", "eDP-2"])

    def test_persistent_top_layers_unmap_on_their_fullscreen_output(self) -> None:
        shell = SHELL.read_text(encoding="utf-8")
        for path in (TOPBAR, DOCK):
            source = path.read_text(encoding="utf-8")
            self.assertIn("property bool fullscreenActive: false", source, path.name)
            self.assertIn("property real fullscreenTransition: fullscreenActive ? 1 : 0", source, path.name)
            self.assertRegex(
                source,
                r"visible:\s*!root\.fullscreenActive\s*\|\|\s*\w+\.opacity\s*>\s*0\.01",
                path.name,
            )
            self.assertIn("Behavior on fullscreenTransition", source, path.name)
            self.assertIn("Motion.elementResize(root.settingsService)", source, path.name)
        island = ISLAND.read_text(encoding="utf-8")
        self.assertIn("property bool fullscreenActive: false", island)
        self.assertIn("visible: !root.fullscreenActive", island)
        self.assertGreaterEqual(shell.count("fullscreenActive: niri.fullscreenOnOutput(modelData)"), 3)
        self.assertIn("function onAnyFullscreenChanged()", shell)
        self.assertRegex(
            shell,
            r"onAnyFullscreenChanged\(\)\s*\{\s*if \(niri\.anyFullscreen\)\s*"
            r"shell\.closeMotionSamplingSurfaces\(\);",
        )

    def test_wallpaper_keeps_surface_while_renderer_handles_fullscreen_pause(self) -> None:
        wallpaper = WALLPAPER.read_text(encoding="utf-8")
        shell = SHELL.read_text(encoding="utf-8")
        sidebar = SIDEBAR.read_text(encoding="utf-8")
        weather = WEATHER.read_text(encoding="utf-8")
        prestart = PRESTART.read_text(encoding="utf-8")
        self.assertIn("property bool fullscreenActive: false", wallpaper)
        self.assertIn("property bool onBattery: false", wallpaper)
        live_gate = re.search(
            r"readonly property bool liveWallpaperAllowed:(.*?)\n\s*readonly property bool dynamicDesired:",
            wallpaper,
            re.DOTALL,
        )
        self.assertIsNotNone(live_gate)
        self.assertNotIn("fullscreenActive", live_gate.group(1))
        self.assertIn("wallpaperPauseWhenIdle", live_gate.group(1))
        self.assertRegex(wallpaper, r"sessionIdle\s*\|\|\s*onBattery")
        self.assertIn("fullscreenActive: niri.anyFullscreen", shell)
        self.assertIn("onBattery: battery.onBattery", shell)
        self.assertIn("property bool backgroundEffectsAllowed: true", sidebar)
        self.assertIn("backgroundEffectsAllowed: root.backgroundEffectsAllowed", sidebar)
        self.assertIn("property bool backgroundEffectsAllowed: true", weather)
        self.assertIn("&& root.backgroundEffectsAllowed", weather)
        self.assertIn("def system_on_battery():", prestart)
        self.assertIn("startup_fps_budget()", prestart)
        self.assertIn("Fullscreen does not own the live process lifecycle", wallpaper)
        self.assertIn("wallpaperPauseWhenFullscreen", wallpaper)
        self.assertIn("function applyWallpaperFullscreenPause(", wallpaper)
        self.assertIn("--no-fullscreen-pause", wallpaper)
        self.assertIn("settings_pause_when_fullscreen", prestart)
        self.assertIn("--no-fullscreen-pause", prestart)

    def test_auto_power_policy_never_defaults_to_performance(self) -> None:
        for path in (RUN_SESSION, LOGIN_SESSION):
            source = path.read_text(encoding="utf-8")
            body = shell_function_body(source, "resolve_power_profile_target")
            self.assertIn("printf 'balanced", body, path.name)
            self.assertIn("printf 'power-saver", body, path.name)
            auto = re.search(r"auto\)(?P<body>.*?)\n\s*;;", body, re.DOTALL)
            self.assertIsNotNone(auto, path.name)
            self.assertNotIn("performance", auto.group("body"), path.name)
        readme = SCRIPTS_README.read_text(encoding="utf-8")
        self.assertIn("balanced", readme)
        self.assertIn("power-saver", readme)
        self.assertNotIn("ask `power-profiles-daemon` for the `performance` profile", readme)

    def test_existing_frame_telemetry_reports_actual_primary_scanout(self) -> None:
        frame_clock = FRAME_CLOCK.read_text(encoding="utf-8")
        tty = TTY.read_text(encoding="utf-8")
        self.assertIn("direct_scanout_frames", frame_clock)
        self.assertIn("direct_scanout_percent", frame_clock)
        self.assertIn("record_direct_scanout", frame_clock)
        self.assertIn("PrimaryPlaneElement::Element", tty)
        self.assertIn("record_direct_scanout", tty)


if __name__ == "__main__":
    unittest.main()
