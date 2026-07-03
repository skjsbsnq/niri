#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path


SCHEMA_VERSION = 1


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))


def parse_bool(value: str | None) -> bool:
    return str(value or "").strip().lower() == "true"


def split_semicolon(value: str | None) -> list[str]:
    return [item for item in str(value or "").split(";") if item]


def config_home() -> Path:
    value = os.environ.get("XDG_CONFIG_HOME")
    if value:
        return Path(value).expanduser()
    return Path.home() / ".config"


def user_autostart_dir() -> Path:
    return config_home() / "autostart"


def config_dirs() -> list[Path]:
    raw = os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg"
    return [Path(item).expanduser() for item in raw.split(":") if item]


def system_autostart_dirs() -> list[Path]:
    return [root / "autostart" for root in config_dirs()]


def desktop_roots() -> list[Path]:
    roots = []
    data_home = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    roots.append(Path(data_home).expanduser() / "applications")
    for item in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
        if item:
            roots.append(Path(item).expanduser() / "applications")
    return roots


def locale_score(key: str) -> tuple[int, str]:
    if "[" not in key or not key.endswith("]"):
        return 1, key

    base, locale = key[:-1].split("[", 1)
    lang = (os.environ.get("LANG") or "").split(".", 1)[0]
    if not lang:
        return 0, base
    if locale == lang:
        return 4, base
    if locale.split("_", 1)[0] == lang.split("_", 1)[0]:
        return 3, base
    return 0, base


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def parse_desktop(path: Path, desktop_id: str) -> dict:
    text = ""
    values: dict[str, str] = {}
    scores: dict[str, int] = {}
    group = ""
    has_desktop_entry = False
    issues: list[str] = []

    try:
        text = read_text(path)
    except OSError as exc:
        issues.append(f"cannot-read: {exc}")

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            group = line[1:-1]
            if group == "Desktop Entry":
                has_desktop_entry = True
            continue
        if group != "Desktop Entry" or "=" not in line:
            continue

        key, value = line.split("=", 1)
        score, base = locale_score(key)
        if base not in values or score >= scores.get(base, -1):
            values[base] = value
            scores[base] = score

    entry_type = values.get("Type", "")
    exec_line = values.get("Exec", "")
    name = values.get("Name", "") or desktop_id.removesuffix(".desktop")

    if not has_desktop_entry:
        issues.append("missing [Desktop Entry]")
    if entry_type != "Application":
        issues.append("Type is not Application")
    if not exec_line:
        issues.append("missing Exec")
    if not values.get("Name"):
        issues.append("missing Name")

    hidden = parse_bool(values.get("Hidden"))
    only_show_in = split_semicolon(values.get("OnlyShowIn"))
    not_show_in = split_semicolon(values.get("NotShowIn"))
    session_eligible = autostart_session_eligible(only_show_in, not_show_in)
    valid = len(issues) == 0
    enabled = valid and not hidden and session_eligible
    if not valid:
        status = "invalid"
    elif hidden:
        status = "disabled"
    elif not session_eligible:
        status = "inactive-session"
    else:
        status = "enabled"

    return {
        "desktopId": desktop_id,
        "fileName": desktop_id if desktop_id.endswith(".desktop") else path.name,
        "name": name,
        "comment": values.get("Comment", ""),
        "icon": values.get("Icon", ""),
        "exec": exec_line,
        "tryExec": values.get("TryExec", ""),
        "type": entry_type,
        "hidden": hidden,
        "enabled": enabled,
        "sessionEligible": session_eligible,
        "status": status,
        "statusText": status_text(status),
        "noDisplay": parse_bool(values.get("NoDisplay")),
        "terminal": parse_bool(values.get("Terminal")),
        "onlyShowIn": only_show_in,
        "notShowIn": not_show_in,
        "valid": valid,
        "validationIssues": issues,
        "path": str(path),
    }


def status_text(status: str) -> str:
    if status == "enabled":
        return "已启用"
    if status == "disabled":
        return "已停用"
    if status == "inactive-session":
        return "不适用于当前会话"
    if status == "invalid":
        return "无效"
    return "未知"


def current_desktops() -> set[str]:
    values: list[str] = []
    for name in ("XDG_CURRENT_DESKTOP", "DESKTOP_SESSION"):
        raw = os.environ.get(name) or ""
        values.extend([part for part in raw.split(":") if part])
    values.extend(["niri", "tahoe"])
    return {value.lower() for value in values if value}


def autostart_session_eligible(only_show_in: list[str], not_show_in: list[str]) -> bool:
    desktops = current_desktops()
    only = {item.lower() for item in only_show_in}
    excluded = {item.lower() for item in not_show_in}
    if only and desktops.isdisjoint(only):
        return False
    if excluded and not desktops.isdisjoint(excluded):
        return False
    return True


def desktop_id_for_path(root: Path, path: Path) -> str:
    try:
        relative = path.relative_to(root)
    except ValueError:
        return path.name
    return str(relative.with_suffix("")).replace(os.sep, "-") + ".desktop"


def normalized_desktop_id(value: str) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    text = text.replace("\\", "/").split("/")[-1]
    if not text.endswith(".desktop"):
        text += ".desktop"
    return text


def normalized_token(value: str) -> str:
    text = normalized_desktop_id(value).lower()
    if text.endswith(".desktop"):
        text = text[:-8]
    return text.replace("_", "-")


def first_exec_token(exec_line: str) -> str:
    text = str(exec_line or "").strip()
    if not text:
        return ""
    token = text.split()[0]
    return Path(token).name


def scan_applications() -> dict[str, dict]:
    entries: dict[str, dict] = {}
    for root in desktop_roots():
        if not root.is_dir():
            continue
        for path in root.rglob("*.desktop"):
            desktop_id = desktop_id_for_path(root, path)
            if desktop_id in entries:
                continue
            parsed = parse_desktop(path, desktop_id)
            if parsed.get("valid") and parsed.get("exec") and not parsed.get("hidden"):
                parsed["sourcePath"] = str(path)
                entries[desktop_id] = parsed
    return entries


def scan_autostart() -> tuple[dict[str, dict], dict[str, Path], dict[str, Path]]:
    user_dir = user_autostart_dir()
    user_paths = {path.name: path for path in user_dir.glob("*.desktop")} if user_dir.is_dir() else {}
    system_paths: dict[str, Path] = {}
    for root in system_autostart_dirs():
        if not root.is_dir():
            continue
        for path in root.glob("*.desktop"):
            system_paths.setdefault(path.name, path)

    entries: dict[str, dict] = {}
    for file_name in sorted(set(user_paths) | set(system_paths)):
        user_path = user_paths.get(file_name)
        system_path = system_paths.get(file_name)
        path = user_path or system_path
        if path is None:
            continue

        entry = parse_desktop(path, file_name)
        has_user = user_path is not None
        has_system = system_path is not None
        entry.update(
            {
                "desktopId": file_name,
                "fileName": file_name,
                "source": "user-override" if has_user and has_system else ("user" if has_user else "system"),
                "sourcePath": str(path),
                "userPath": str(user_path or (user_dir / file_name)),
                "systemPath": str(system_path or ""),
                "hasUserOverride": has_user,
                "canToggle": True,
                "canRemove": has_user or has_system,
                "actionScope": "user-autostart",
            }
        )
        entries[file_name] = entry

    return entries, user_paths, system_paths


def list_autostart() -> dict:
    entries, _user_paths, _system_paths = scan_autostart()
    values = sorted(entries.values(), key=lambda item: (item["status"] != "enabled", item["name"].lower(), item["desktopId"].lower()))
    enabled = sum(1 for item in values if item.get("status") == "enabled")
    invalid = sum(1 for item in values if item.get("status") == "invalid")
    detail = f"{len(values)} 个启动项，{enabled} 个已启用"
    if invalid:
        detail += f"，{invalid} 个无效"
    return {
        "schemaVersion": SCHEMA_VERSION,
        "mode": "autostart",
        "status": "ok",
        "detail": detail,
        "userDir": str(user_autostart_dir()),
        "entries": values,
    }


def desktop_entry_bounds(lines: list[str]) -> tuple[int, int] | None:
    start = None
    end = len(lines)
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if stripped == "[Desktop Entry]":
                start = index
                end = len(lines)
            elif start is not None:
                end = index
                break
    if start is None:
        return None
    return start, end


def set_desktop_key(text: str, key: str, value: str) -> str:
    lines = text.splitlines()
    trailing_newline = text.endswith("\n")
    bounds = desktop_entry_bounds(lines)
    if bounds is None:
        lines.insert(0, "[Desktop Entry]")
        bounds = (0, len(lines))

    start, end = bounds
    replacement = f"{key}={value}"
    for index in range(start + 1, end):
        raw_key = lines[index].split("=", 1)[0].strip() if "=" in lines[index] else ""
        if raw_key == key:
            lines[index] = replacement
            break
    else:
        lines.insert(end, replacement)

    return "\n".join(lines) + ("\n" if trailing_newline or not lines or lines[-1] else "")


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.chmod(tmp_path, mode)
        os.replace(tmp_path, path)
    finally:
        try:
            tmp_path.unlink()
        except FileNotFoundError:
            pass


def source_text_for_autostart(desktop_id: str, entries: dict[str, dict], user_paths: dict[str, Path], system_paths: dict[str, Path]) -> str:
    file_name = normalized_desktop_id(desktop_id)
    path = user_paths.get(file_name) or system_paths.get(file_name)
    if path is not None:
        return read_text(path)

    app = resolve_application(desktop_id)
    if app:
        return read_text(Path(app["sourcePath"]))

    raise SystemExit(f"unknown autostart item: {desktop_id}")


def resolve_application(value: str) -> dict | None:
    target = normalized_token(value)
    if not target:
        return None

    for desktop_id, entry in scan_applications().items():
        candidates = {
            normalized_token(desktop_id),
            normalized_token(entry.get("desktopId", "")),
            normalized_token(entry.get("fileName", "")),
            normalized_token(entry.get("name", "")),
            normalized_token(first_exec_token(entry.get("exec", ""))),
        }
        if target in candidates:
            return entry
    return None


def set_enabled(desktop_id: str, enabled: bool) -> dict:
    file_name = normalized_desktop_id(desktop_id)
    entries, user_paths, system_paths = scan_autostart()
    if file_name not in entries and enabled:
        return add_application(desktop_id)
    if file_name not in entries:
        raise SystemExit(f"unknown autostart item: {desktop_id}")

    text = source_text_for_autostart(file_name, entries, user_paths, system_paths)
    text = set_desktop_key(text, "Hidden", "false" if enabled else "true")
    if enabled:
        text = set_desktop_key(text, "X-GNOME-Autostart-enabled", "true")
    target = user_autostart_dir() / file_name
    atomic_write(target, text)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "mode": "set-enabled",
        "status": "ok",
        "desktopId": file_name,
        "enabled": enabled,
        "message": "启动项已启用" if enabled else "启动项已停用",
        "path": str(target),
    }


def add_application(desktop_id: str) -> dict:
    app = resolve_application(desktop_id)
    if not app:
        raise SystemExit(f"unknown application: {desktop_id}")

    file_name = normalized_desktop_id(app.get("desktopId") or desktop_id)
    text = read_text(Path(app["sourcePath"]))
    text = set_desktop_key(text, "Hidden", "false")
    text = set_desktop_key(text, "X-GNOME-Autostart-enabled", "true")
    target = user_autostart_dir() / file_name
    atomic_write(target, text)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "mode": "add",
        "status": "ok",
        "desktopId": file_name,
        "enabled": True,
        "message": f"{app.get('name') or file_name} 已加入启动项",
        "path": str(target),
    }


def remove_autostart(desktop_id: str) -> dict:
    file_name = normalized_desktop_id(desktop_id)
    _entries, user_paths, system_paths = scan_autostart()
    user_path = user_paths.get(file_name)
    if user_path is not None:
        user_path.unlink(missing_ok=True)
        if file_name in system_paths:
            # Removing a user override exposes the system entry again, so keep
            # the user-visible effect as "not autostarting" by writing Hidden.
            return set_enabled(file_name, False)
        return {
            "schemaVersion": SCHEMA_VERSION,
            "mode": "remove",
            "status": "ok",
            "desktopId": file_name,
            "message": "用户启动项已移除",
            "path": str(user_path),
        }

    if file_name in system_paths:
        return set_enabled(file_name, False)

    raise SystemExit(f"unknown autostart item: {desktop_id}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Tahoe XDG autostart manager")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("list")

    add_parser = subparsers.add_parser("add")
    add_parser.add_argument("desktop_id")

    enable_parser = subparsers.add_parser("set-enabled")
    enable_parser.add_argument("desktop_id")
    enable_parser.add_argument("enabled", choices=("true", "false", "1", "0", "yes", "no"))

    remove_parser = subparsers.add_parser("remove")
    remove_parser.add_argument("desktop_id")

    args = parser.parse_args(argv)

    try:
        if args.command == "list":
            emit(list_autostart())
        elif args.command == "add":
            emit(add_application(args.desktop_id))
        elif args.command == "set-enabled":
            emit(set_enabled(args.desktop_id, args.enabled in ("true", "1", "yes")))
        elif args.command == "remove":
            emit(remove_autostart(args.desktop_id))
        else:
            parser.error("unknown command")
    except SystemExit as exc:
        if isinstance(exc.code, str):
            emit({"schemaVersion": SCHEMA_VERSION, "mode": args.command, "status": "error", "message": exc.code})
            return 1
        raise
    except Exception as exc:
        emit({"schemaVersion": SCHEMA_VERSION, "mode": args.command, "status": "error", "message": str(exc)})
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
