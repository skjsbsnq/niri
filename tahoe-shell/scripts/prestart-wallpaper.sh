#!/usr/bin/env bash
set -euo pipefail

state_dir="${TAHOE_STATE_DIR:-"$HOME/.local/state/quickshell/by-shell/tahoe"}"
settings_file="$state_dir/desktop-settings.json"
legacy_pid_file="$state_dir/wallpaper-prestart.pids"
record_dir="$state_dir/wallpaper-prestart"
capture_dir="$state_dir/lock-wallpaper"

mkdir -p "$state_dir" "$record_dir" "$capture_dir"

terminate_recorded_wallpapers() {
  local -a pids=()
  local pid record token start_time current_start cmdline

  shopt -s nullglob
  for record in "$record_dir"/*.json; do
    pid="$(sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$record" | head -n 1)"
    token="$(sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([0-9a-f][0-9a-f]*\)".*/\1/p' "$record" | head -n 1)"
    start_time="$(sed -n 's/.*"startTime"[[:space:]]*:[[:space:]]*"\([0-9][0-9]*\)".*/\1/p' "$record" | head -n 1)"
    [[ "$pid" =~ ^[0-9]+$ && "$token" =~ ^[0-9a-f]{32}$ && "$start_time" =~ ^[0-9]+$ ]] \
      || continue
    [[ -r "/proc/$pid/stat" ]] || continue
    current_start="$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || true)"
    [[ "$current_start" == "$start_time" ]] || continue
    pids+=("$pid")
  done
  shopt -u nullglob

  if [[ -f "$legacy_pid_file" ]]; then
    while IFS= read -r pid; do
      [[ "$pid" =~ ^[0-9]+$ ]] || continue
      [[ -r "/proc/$pid/cmdline" ]] || continue
      cmdline="$(tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null || true)"
      [[ "$cmdline" == *linux-wallpaperengine* ]] || continue
      pids+=("$pid")
    done <"$legacy_pid_file"
  fi

  for pid in "${pids[@]}"; do
    kill -TERM -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
  done

  local attempt
  for attempt in {1..20}; do
    local alive=false
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        alive=true
        break
      fi
    done
    [[ "$alive" == false ]] && break
    sleep 0.05
  done

  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    fi
  done

  rm -f "$record_dir"/*.json "$legacy_pid_file"
}

terminate_recorded_wallpapers

command -v python3 >/dev/null 2>&1 || exit 0

python3 - "$settings_file" "$record_dir" "$capture_dir" <<'PY'
import json
import os
import re
import secrets
import shlex
import subprocess
import sys
import time

settings_file, record_dir, capture_dir = sys.argv[1], sys.argv[2], sys.argv[3]
home = os.environ.get("HOME", "")


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as file:
            return json.load(file)
    except Exception:
        return {}


def niri_outputs():
    for _ in range(5):
        try:
            raw = subprocess.check_output(
                ["niri", "msg", "--json", "outputs"],
                stderr=subprocess.DEVNULL,
                timeout=0.2,
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
        time.sleep(0.08)
    return []


def shell_quote(value):
    # Match Wallpaper.qml's conservative quoting for adoption comparisons.
    return "'" + str(value or "").replace("'", "'\\''") + "'"


def record_path(output):
    return os.path.join(record_dir, f"{safe_output_name(output)}.json")


def process_start_time(pid):
    try:
        with open(f"/proc/{pid}/stat", "r", encoding="utf-8") as file:
            text = file.read().strip()
        close = text.rfind(")")
        fields = text[close + 1 :].strip().split()
        # Fields now begin at proc stat field 3; starttime is field 22.
        return fields[19] if close >= 0 and len(fields) > 19 else ""
    except Exception:
        return ""


SUPERVISOR = r"""
record=$1
token=$2
shift 2

record_matches() {
    [ -r "$record" ] && grep -Fq "\"token\":\"$token\"" "$record"
}

i=0
while [ "$i" -lt 200 ] && ! record_matches; do
    sleep 0.01
    i=$((i + 1))
done
record_matches || exit 125

child=""
cleanup() {
    if record_matches; then
        rm -f -- "$record"
    fi
}

forward_signal() {
    trap - TERM INT HUP
    if [ -n "$child" ]; then
        kill -TERM "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
    fi
    cleanup
    exit 143
}

trap forward_signal TERM INT HUP
"$@" &
child=$!
wait "$child"
status=$?
cleanup
exit "$status"
"""


def spawn_supervised(args, output, mode, command):
    if not args:
        return

    record = record_path(output)
    token = secrets.token_hex(16)
    proc = subprocess.Popen(
        ["sh", "-c", SUPERVISOR, "sh", record, token, *args],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    start_time = process_start_time(proc.pid)
    if not start_time:
        proc.terminate()
        return
    payload = {
        "pid": proc.pid,
        "token": token,
        "startTime": start_time,
        "output": str(output),
        "mode": str(mode),
        "command": str(command),
    }
    temporary = f"{record}.tmp.{os.getpid()}"
    try:
        with open(temporary, "w", encoding="utf-8") as file:
            json.dump(payload, file, ensure_ascii=False, separators=(",", ":"))
        os.replace(temporary, record)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def spawn_shell(command, output, mode):
    command = str(command or "").strip()
    if not command:
        return
    recorded_command = f"mkdir -p {shell_quote(capture_dir)} && exec {command}"
    spawn_supervised(["sh", "-lc", command], output, mode, recorded_command)


def spawn_args(args, output, mode):
    if not args:
        return
    command = " ".join(shell_quote(arg) for arg in args)
    command = f"mkdir -p {shell_quote(capture_dir)} && exec {command}"
    spawn_supervised(args, output, mode, command)


def dynamic_command_for_output(command, output):
    quoted = shell_quote(output)
    return command.replace("{output}", quoted).replace("{screen}", quoted)


def safe_output_name(output):
    value = re.sub(r"[^A-Za-z0-9_.-]", "_", str(output or "").strip())
    return value or "default"


def lock_capture_path(output):
    return os.path.join(capture_dir, f"{safe_output_name(output)}.png")


def is_direct_wallpaperengine(command):
    try:
        tokens = shlex.split(str(command or ""), posix=True)
    except ValueError:
        return False
    return bool(tokens) and os.path.basename(tokens[0]) == "linux-wallpaperengine"


def apply_fullscreen_pause(command, pause_when_fullscreen):
    text = str(command or "").strip()
    if not is_direct_wallpaperengine(text):
        return text
    text = re.sub(r"(^|\s)--no-fullscreen-pause(?=\s|$)", r"\1", text)
    text = re.sub(r"\s+", " ", text).strip()
    if not pause_when_fullscreen:
        text += " --no-fullscreen-pause"
    return text


def inject_lock_capture(command, output):
    text = str(command or "").strip()
    if not is_direct_wallpaperengine(text):
        return text
    text = re.sub(
        r"(^|\s)--screenshot(?:\s+|=)(?:\"[^\"]*\"|'[^']*'|[^\s]+)",
        r"\1",
        text,
    )
    text = re.sub(r"(^|\s)--screenshot-delay(?:\s+|=)\d+", r"\1", text)
    text = re.sub(r"\s+", " ", text).strip()
    return (
        f"{text} --screenshot {shlex.quote(lock_capture_path(output))}"
        " --screenshot-delay 5"
    )


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
            default_fps = startup_fps_budget()
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
    ):
        if entry.get(key):
            args.append(option)

    # Default quieter for compositor cost unless UX explicitly enables effects.
    if entry.get("disableParallax", True):
        args.append("--disable-parallax")
    if entry.get("disableParticles", True):
        args.append("--disable-particles")

    if not settings_pause_when_fullscreen():
        args.append("--no-fullscreen-pause")

    args.extend([
        "--screenshot",
        lock_capture_path(screen),
        "--screenshot-delay",
        "5",
    ])

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


def settings_idle_fps_budget():
    try:
        value = int(round(float(settings.get("wallpaperEngineIdleFps", 8))))
        return max(1, min(settings_fps_budget(), value))
    except Exception:
        return min(settings_fps_budget(), 8)


def settings_pause_when_fullscreen():
    return settings.get("wallpaperPauseWhenFullscreen", True) is not False


def system_on_battery():
    power_root = "/sys/class/power_supply"
    has_battery = False
    external_online = False
    try:
        supplies = os.listdir(power_root)
    except Exception:
        return False

    for supply in supplies:
        base = os.path.join(power_root, supply)
        try:
            with open(os.path.join(base, "type"), "r", encoding="utf-8") as file:
                supply_type = file.read().strip()
        except Exception:
            continue
        if supply_type == "Battery":
            has_battery = True
        if supply_type in {"Mains", "USB", "USB_C", "USB_PD", "Wireless"}:
            try:
                with open(os.path.join(base, "online"), "r", encoding="utf-8") as file:
                    external_online = external_online or file.read().strip() == "1"
            except Exception:
                pass
    return has_battery and not external_online


def startup_fps_budget():
    return settings_idle_fps_budget() if system_on_battery() else settings_fps_budget()


def inject_fps(command, fps):
    text = str(command or "").strip()
    if not text:
        return text
    if re.search(r"(^|\s)--fps(\s|=)", text):
        return re.sub(r"(^|\s)--fps(\s+|=)\d+", rf"\1--fps\2{fps}", text)
    return f"{text} --fps {fps}"


if mode == "dynamic":
    command = str(settings.get("dynamicWallpaperCommand", "")).strip()
    if not command:
        sys.exit(0)

    outputs = niri_outputs()
    if not outputs:
        sys.exit(0)
    for output in outputs:
        prepared = dynamic_command_for_output(command, output)
        prepared = apply_fullscreen_pause(prepared, settings_pause_when_fullscreen())
        prepared = inject_lock_capture(prepared, output)
        spawn_shell(inject_fps(prepared, startup_fps_budget()), output, "dynamic")

elif mode == "external":
    state_path = os.path.join(home, ".config/Linux Wallpaper Engine/active-wallpapers.json")
    state = load_json(state_path)
    active = state.get("activeWallpapers", {})
    if not isinstance(active, dict):
        sys.exit(0)

    outputs = niri_outputs()
    if not outputs:
        sys.exit(0)
    for output in outputs:
        entry = active.get(output)
        if entry is not None:
            spawn_args(external_args(entry, output), output, "external")
PY
