#!/usr/bin/env bash
set -euo pipefail

state_dir="${TAHOE_STATE_DIR:-"$HOME/.local/state/quickshell/by-shell/tahoe"}"
settings_file="$state_dir/desktop-settings.json"
pid_file="$state_dir/wallpaper-prestart.pids"

mkdir -p "$state_dir"
: >"$pid_file"

command -v python3 >/dev/null 2>&1 || exit 0

python3 - "$settings_file" "$pid_file" <<'PY'
import json
import os
import shlex
import subprocess
import sys
import time

settings_file, pid_file = sys.argv[1], sys.argv[2]
home = os.environ.get("HOME", "")


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as file:
            return json.load(file)
    except Exception:
        return {}


def niri_outputs():
    for _ in range(10):
        try:
            raw = subprocess.check_output(
                ["niri", "msg", "--json", "outputs"],
                stderr=subprocess.DEVNULL,
                timeout=0.35,
                text=True,
            )
            data = json.loads(raw)
            if isinstance(data, dict):
                names = [str(name) for name in data.keys() if str(name)]
                if names:
                    return names
            if isinstance(data, list):
                names = [
                    str(item.get("name", ""))
                    for item in data
                    if isinstance(item, dict) and str(item.get("name", ""))
                ]
                if names:
                    return names
        except Exception:
            pass
        time.sleep(0.1)
    return []


def spawn_shell(command):
    if not command.strip():
        return
    proc = subprocess.Popen(
        ["sh", "-lc", command],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    with open(pid_file, "a", encoding="utf-8") as file:
        file.write(f"{proc.pid}\n")


def spawn_args(args):
    if not args:
        return
    proc = subprocess.Popen(
        args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    with open(pid_file, "a", encoding="utf-8") as file:
        file.write(f"{proc.pid}\n")


def dynamic_command_for_output(command, output):
    quoted = shlex.quote(output)
    return command.replace("{output}", quoted).replace("{screen}", quoted)


def external_args(entry, fallback_screen):
    if not isinstance(entry, dict):
        return []

    background_id = str(entry.get("backgroundId") or entry.get("id") or "").strip()
    screen = str(fallback_screen or entry.get("screen") or "").strip()
    if not background_id or not screen:
        return []

    args = [
        "linux-wallpaperengine",
        "--screen-root",
        screen,
        "--bg",
        background_id,
        "--layer",
        "background",
    ]

    for key, option in (
        ("scaling", "--scaling"),
        ("clamp", "--clamp"),
    ):
        value = str(entry.get(key) or "").strip()
        if value:
            args.extend([option, value])

    try:
        # Prefer desktop-settings budget; hard-cap 20 for background layer.
        default_fps = 15
        try:
            default_fps = max(1, min(20, int(round(float(settings.get("wallpaperEngineFps", 15))))))
        except Exception:
            default_fps = 15
        fps = max(1, min(20, round(float(entry.get("fps", default_fps)))))
        fps = min(fps, default_fps)
    except Exception:
        fps = 15
    args.extend(["--fps", str(fps)])

    if entry.get("silent"):
        args.append("--silent")
    else:
        try:
            volume = max(0, round(float(entry.get("volume", 15))))
        except Exception:
            volume = 15
        args.extend(["--volume", str(volume)])

    for key, option in (
        ("noAutomute", "--noautomute"),
        ("noAudioProcessing", "--no-audio-processing"),
        ("disableMouse", "--disable-mouse"),
        ("noFullscreenPause", "--no-fullscreen-pause"),
    ):
        if entry.get(key):
            args.append(option)

    # Default quieter for compositor cost unless UX explicitly enables effects.
    if entry.get("disableParallax", True):
        args.append("--disable-parallax")
    if entry.get("disableParticles", True):
        args.append("--disable-particles")

    assets_dir = os.path.join(
        home,
        ".local/share/Steam/steamapps/common/wallpaper_engine/assets",
    )
    if assets_dir:
        args.extend(["--assets-dir", assets_dir])

    return args


settings = load_json(settings_file)
mode = str(settings.get("wallpaperMode", "static")).strip()


def settings_fps_budget():
    try:
        return max(1, min(20, int(round(float(settings.get("wallpaperEngineFps", 15))))))
    except Exception:
        return 15


def inject_fps(command, fps):
    text = str(command or "").strip()
    if not text:
        return text
    import re

    if re.search(r"(^|\s)--fps(\s|=)", text):
        return re.sub(r"(^|\s)--fps(\s+|=)\d+", rf"\1--fps\2{fps}", text)
    return f"{text} --fps {fps}"


if mode == "dynamic":
    command = str(settings.get("dynamicWallpaperCommand", "")).strip()
    if not command:
        sys.exit(0)

    command = inject_fps(command, settings_fps_budget())
    outputs = niri_outputs()
    if not outputs:
        spawn_shell(command)
    else:
        for output in outputs:
            spawn_shell(dynamic_command_for_output(command, output))

elif mode == "external":
    state_path = os.path.join(home, ".config/Linux Wallpaper Engine/active-wallpapers.json")
    state = load_json(state_path)
    active = state.get("activeWallpapers", {})
    if not isinstance(active, dict):
        sys.exit(0)

    outputs = niri_outputs()
    if outputs:
        for output in outputs:
            entry = active.get(output)
            if entry is not None:
                spawn_args(external_args(entry, output))
    elif len(active) == 1:
        screen, entry = next(iter(active.items()))
        spawn_args(external_args(entry, screen))
PY
