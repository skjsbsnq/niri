#!/usr/bin/env python3
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path


CATEGORIES = [
    {
        "id": "web",
        "title": "Web",
        "icon": "\ue80b",
        "mimes": ["x-scheme-handler/http", "x-scheme-handler/https", "text/html"],
    },
    {
        "id": "mail",
        "title": "Mail",
        "icon": "\ue0e1",
        "mimes": ["x-scheme-handler/mailto"],
    },
    {
        "id": "calendar",
        "title": "Calendar",
        "icon": "\ue935",
        "mimes": ["text/calendar", "x-scheme-handler/webcal"],
    },
    {
        "id": "music",
        "title": "Music",
        "icon": "\ue405",
        "mimes": ["audio/mpeg", "audio/mp4", "audio/ogg", "audio/flac", "audio/x-wav", "audio/aac"],
    },
    {
        "id": "video",
        "title": "Video",
        "icon": "\ue04b",
        "mimes": ["video/mp4", "video/x-matroska", "video/x-msvideo", "video/webm", "video/quicktime"],
    },
    {
        "id": "photos",
        "title": "Photos",
        "icon": "\ue3f4",
        "mimes": ["image/png", "image/jpeg", "image/gif", "image/webp", "image/tiff"],
    },
    {
        "id": "files",
        "title": "Files",
        "icon": "\ue2c7",
        "mimes": ["inode/directory"],
    },
    {
        "id": "removable",
        "title": "Removable Media",
        "icon": "\ue8b8",
        "mimes": [
            "x-content/audio-cdda",
            "x-content/video-dvd",
            "x-content/image-dcf",
            "x-content/unix-software",
            "x-content/blank-cd",
        ],
    },
]


PERMISSIONS = [
    {"id": "notifications", "title": "通知", "table": "notifications", "object": "app"},
    {"id": "background", "title": "后台运行", "table": "background", "object": "app"},
    {"id": "camera", "title": "摄像头", "table": "devices", "object": "camera"},
    {"id": "microphone", "title": "麦克风", "table": "devices", "object": "microphone"},
    {"id": "location", "title": "位置", "table": "location", "object": "app"},
    {"id": "screenshot", "title": "截图", "table": "screenshot", "object": "app"},
    {"id": "wallpaper", "title": "壁纸", "table": "wallpaper", "object": "app"},
    {"id": "shortcuts", "title": "快捷键抑制", "table": "shortcuts-inhibit", "object": "app"},
]

SCHEMA_VERSION = 1
DEFAULT_PROBE_BUDGET_MS = 2500
DEFAULT_FINGERPRINT_BUDGET_MS = 600
PERMISSIONS_PROBE_BUDGET_MS = 1600
MAX_DESKTOP_FILES = 5000
MAX_STORAGE_FILES = 4000

CONTROL_READONLY = "readonly"
CONTROL_WARNING = "warning"
CONTROL_EXTERNAL = "external"


class Budget:
    def __init__(self, limit_ms):
        self.limit_ms = max(1, int(limit_ms))
        self.started = time.monotonic()
        self.deadline = self.started + self.limit_ms / 1000.0

    def remaining(self):
        return max(0.0, self.deadline - time.monotonic())

    def expired(self):
        return self.remaining() <= 0

    def timeout(self, requested):
        remaining = self.remaining()
        if remaining <= 0:
            return 0.001
        return max(0.001, min(float(requested), remaining))

    def summary(self):
        elapsed = max(0, round((time.monotonic() - self.started) * 1000))
        return {
            "limitMs": self.limit_ms,
            "elapsedMs": elapsed,
            "expired": self.expired(),
        }


def emit(payload):
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))


def run(command, timeout=4, budget=None):
    if budget is not None and budget.expired():
        return subprocess.CompletedProcess(command, 124, "", "probe budget exhausted")
    try:
        effective_timeout = budget.timeout(timeout) if budget is not None else timeout
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=effective_timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(command, 124, "", "command timed out")
    except Exception as exc:
        return subprocess.CompletedProcess(command, 1, "", str(exc))


def schema_fields(mode):
    return {"schemaVersion": SCHEMA_VERSION, "mode": mode}


def control_model(control, reason, scope="portal-record", external_action=""):
    return {
        "control": control,
        "presentation": control,
        "canToggle": False,
        "readOnly": True,
        "readOnlyReason": reason,
        "scope": scope,
        "externalAction": external_action,
    }


def portal_permission_control(sandbox_type, portal_status):
    if portal_status != "ok":
        reason = "portal permission store 不可用；权限记录只能以降级状态显示"
        if sandbox_type == "none":
            reason += "，普通桌面应用也没有 Tahoe 可强制 sandbox"
        return control_model(CONTROL_WARNING, reason)

    if sandbox_type == "none":
        return control_model(
            CONTROL_READONLY,
            "普通桌面应用没有 Tahoe 可强制 sandbox；这里只显示 portal 记录",
        )

    return control_model(
        CONTROL_READONLY,
        "Tahoe 当前只读取 portal 权限记录；sandbox 边界由应用运行时强制",
    )


def external_permission_control(kind, status):
    if status == "unavailable":
        return control_model(
            CONTROL_WARNING,
            f"{kind} 权限信息不可读取；Tahoe 不会伪装为可控制开关",
            scope="runtime-metadata",
        )
    return control_model(
        CONTROL_EXTERNAL,
        f"{kind} 静态权限由对应运行时管理，Tahoe 当前只读展示",
        scope="runtime-metadata",
        external_action=kind,
    )


def apply_control(row, model):
    out = dict(row)
    out.update(model)
    return out


def desktop_roots():
    roots = []
    data_home = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    roots.append(Path(data_home) / "applications")
    for item in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
        if item:
            roots.append(Path(item) / "applications")
    return roots


def mimeapps_paths():
    home = Path.home()
    config_home = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
    data_home = Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share")
    paths = [config_home / "mimeapps.list", data_home / "applications" / "mimeapps.list"]
    for item in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
        if item:
            paths.append(Path(item) / "applications" / "mimeapps.list")
    unique = []
    seen = set()
    for path in paths:
        text = str(path)
        if text not in seen:
            seen.add(text)
            unique.append(path)
    return unique


def update_stat_fingerprint(hasher, label, path):
    try:
        stat = path.stat()
        value = f"{label}\0{path}\0{stat.st_mtime_ns}\0{stat.st_size}\0"
    except OSError:
        value = f"{label}\0{path}\0missing\0"
    hasher.update(value.encode("utf-8", errors="surrogateescape"))


def defaults_fingerprint(budget_ms=DEFAULT_FINGERPRINT_BUDGET_MS):
    budget = budget_ms if isinstance(budget_ms, Budget) else Budget(budget_ms)
    hasher = hashlib.sha256()
    hasher.update(f"schema={SCHEMA_VERSION}\0lang={os.environ.get('LANG', '')}\0".encode())
    hasher.update(f"xdg-mime={shutil.which('xdg-mime') or ''}\0".encode())
    file_count = 0
    truncated = False

    for root in desktop_roots():
        update_stat_fingerprint(hasher, "root", root)
        if budget.expired():
            truncated = True
            break
        if not root.is_dir():
            continue
        try:
            for current, dirs, files in os.walk(root):
                dirs.sort()
                files.sort()
                for name in files:
                    if not name.endswith(".desktop"):
                        continue
                    if budget.expired() or file_count >= MAX_DESKTOP_FILES:
                        truncated = True
                        break
                    update_stat_fingerprint(hasher, "desktop", Path(current) / name)
                    file_count += 1
                if truncated:
                    break
        except OSError:
            continue
        if truncated:
            break

    for path in mimeapps_paths():
        if budget.expired():
            truncated = True
            break
        update_stat_fingerprint(hasher, "mimeapps", path)

    return {
        **schema_fields("defaults-fingerprint"),
        "status": "warn" if truncated else "ok",
        "fingerprint": hasher.hexdigest(),
        "desktopFiles": file_count,
        "complete": not truncated,
        "budget": budget.summary(),
    }


def locale_score(key):
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


def parse_bool(value):
    return str(value or "").strip().lower() == "true"


def parse_desktop(path, desktop_id):
    group = ""
    values = {}
    scores = {}

    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            group = line[1:-1]
            continue
        if group != "Desktop Entry" or "=" not in line:
            continue

        key, value = line.split("=", 1)
        score, base = locale_score(key)
        if base not in values or score >= scores.get(base, -1):
            values[base] = value
            scores[base] = score

    if values.get("Type") != "Application":
        return None

    mime_types = [item for item in values.get("MimeType", "").split(";") if item]
    flatpak_id = values.get("X-Flatpak", "").strip()
    snap_id = values.get("X-SnapInstanceName", "").strip() or values.get("X-SnapAppName", "").strip()
    desktop_base = desktop_id[:-8] if desktop_id.endswith(".desktop") else desktop_id

    sandbox_type = "none"
    sandbox_id = desktop_base
    if flatpak_id:
        sandbox_type = "flatpak"
        sandbox_id = flatpak_id
    elif snap_id:
        sandbox_type = "snap"
        sandbox_id = snap_id

    return {
        "desktopId": desktop_id,
        "id": desktop_base,
        "name": values.get("Name", desktop_base),
        "genericName": values.get("GenericName", ""),
        "comment": values.get("Comment", ""),
        "icon": values.get("Icon", ""),
        "exec": values.get("Exec", ""),
        "noDisplay": parse_bool(values.get("NoDisplay")),
        "hidden": parse_bool(values.get("Hidden")),
        "mimeTypes": mime_types,
        "sandboxType": sandbox_type,
        "sandboxId": sandbox_id,
        "launchable": bool(values.get("Exec", "")),
        "path": str(path),
    }


def scan_desktop_entries(budget=None, max_files=MAX_DESKTOP_FILES):
    entries = {}
    scanned = 0
    for root in desktop_roots():
        if budget is not None and budget.expired():
            break
        if not root.is_dir():
            continue
        for path in root.rglob("*.desktop"):
            if (budget is not None and budget.expired()) or scanned >= max_files:
                return entries
            scanned += 1
            try:
                relative = path.relative_to(root)
            except ValueError:
                continue
            desktop_id = str(relative.with_suffix("")).replace(os.sep, "-") + ".desktop"
            if desktop_id in entries:
                continue
            parsed = parse_desktop(path, desktop_id)
            if parsed:
                entries[desktop_id] = parsed
    return entries


def query_default(mime, budget=None):
    xdg_mime = shutil.which("xdg-mime")
    if not xdg_mime:
        return ""
    result = run([xdg_mime, "query", "default", mime], budget=budget)
    if result.returncode != 0:
        return ""
    return result.stdout.strip().splitlines()[0] if result.stdout.strip() else ""


def current_default_for(values, mimes):
    ordered = [values.get(mime, "") for mime in mimes if values.get(mime, "")]
    if not ordered:
        return ""
    counts = Counter(ordered)
    return sorted(counts.items(), key=lambda item: (-item[1], ordered.index(item[0])))[0][0]


def candidate_entry(meta, category_mimes):
    supported = sorted(set(meta.get("mimeTypes", [])).intersection(category_mimes))
    out = {
        "desktopId": meta["desktopId"],
        "name": meta.get("name", ""),
        "genericName": meta.get("genericName", ""),
        "icon": meta.get("icon", ""),
        "noDisplay": bool(meta.get("noDisplay")),
        "sandboxType": meta.get("sandboxType", "none"),
        "sandboxId": meta.get("sandboxId", meta.get("id", "")),
        "supportedMimeTypes": supported,
        "supportedMimeCount": len(supported),
    }
    return out


def probe_defaults(budget_ms=DEFAULT_PROBE_BUDGET_MS):
    budget = budget_ms if isinstance(budget_ms, Budget) else Budget(budget_ms)
    fingerprint = defaults_fingerprint(min(DEFAULT_FINGERPRINT_BUDGET_MS, budget.limit_ms))
    meta = scan_desktop_entries(budget)
    xdg_mime = shutil.which("xdg-mime")
    status = "ok" if xdg_mime else "missing"
    detail = "xdg-mime 可用" if xdg_mime else "缺少 xdg-mime，无法读取或修改默认应用"
    rows = []

    for category in CATEGORIES:
        defaults = {
            mime: query_default(mime, budget)
            for mime in category["mimes"]
            if not budget.expired()
        } if xdg_mime else {}
        current = current_default_for(defaults, category["mimes"])
        current_set = set(value for value in defaults.values() if value)
        category_mimes = set(category["mimes"])
        candidates = []
        seen = set()

        for desktop_id, item in meta.items():
            if item.get("hidden") or not item.get("launchable"):
                continue
            supported = category_mimes.intersection(item.get("mimeTypes", []))
            if not supported:
                continue
            if item.get("noDisplay") and desktop_id not in current_set:
                continue
            seen.add(desktop_id)
            candidates.append(candidate_entry(item, category_mimes))

        if current and current in meta and current not in seen:
            candidates.append(candidate_entry(meta[current], category_mimes))

        candidates.sort(key=lambda item: (item["noDisplay"], item["name"].lower(), item["desktopId"].lower()))
        matched = sum(1 for value in defaults.values() if value and value == current)
        rows.append(
            {
                "id": category["id"],
                "title": category["title"],
                "icon": category["icon"],
                "mimes": category["mimes"],
                "defaults": defaults,
                "currentDesktopId": current,
                "currentName": meta.get(current, {}).get("name", current),
                "consistent": bool(current) and matched == len(category["mimes"]),
                "matchedMimeCount": matched,
                "mimeCount": len(category["mimes"]),
                "candidates": candidates,
            }
        )

    if budget.expired() and status == "ok":
        status = "warn"
        detail = "默认应用探测达到时间预算，结果可能不完整"

    return {
        **schema_fields("defaults"),
        "status": status,
        "detail": detail,
        "fingerprint": fingerprint["fingerprint"],
        "fingerprintComplete": fingerprint["complete"],
        "budget": budget.summary(),
        "xdgMime": {
            "status": status,
            "available": bool(xdg_mime),
            "canRead": bool(xdg_mime),
            "canWrite": bool(xdg_mime),
            "detail": detail,
        },
        "categories": rows,
        "desktopMeta": meta,
    }


def set_default(desktop_id, mimes):
    xdg_mime = shutil.which("xdg-mime")
    if not xdg_mime:
        return {
            **schema_fields("set-default"),
            "success": False,
            "message": "缺少 xdg-mime",
            "verified": {},
        }
    if not desktop_id or not mimes:
        return {
            **schema_fields("set-default"),
            "success": False,
            "message": "缺少 desktop id 或 MIME type",
            "verified": {},
        }

    result = run([xdg_mime, "default", desktop_id] + list(mimes))
    verified = {mime: query_default(mime) for mime in mimes}
    verified_count = sum(1 for value in verified.values() if value == desktop_id)
    success = result.returncode == 0 and verified_count == len(mimes)
    message = "默认应用已更新" if success else (result.stderr.strip() or "默认应用写入后未全部通过验证")
    return {
        **schema_fields("set-default"),
        "success": success,
        "message": message,
        "desktopId": desktop_id,
        "verified": verified,
        "verifiedCount": verified_count,
        "mimeCount": len(mimes),
        "exitCode": result.returncode,
    }


def permission_store_available(budget=None):
    busctl = shutil.which("busctl")
    if not busctl:
        return False, "missing", "缺少 busctl，无法读取 portal permission store"
    result = run(
        [busctl, "--user", "status", "org.freedesktop.impl.portal.PermissionStore"],
        timeout=2,
        budget=budget,
    )
    if result.returncode == 0:
        return True, "ok", "portal permission store 可读取"
    detail = (result.stderr or result.stdout).strip() or "未检测到 org.freedesktop.impl.portal.PermissionStore"
    return False, "missing", detail.splitlines()[0]


def lookup_permission(table, object_id, app_key, budget=None):
    busctl = shutil.which("busctl")
    if not busctl:
        return {"status": "unavailable", "detail": "缺少 busctl", "raw": ""}
    result = run(
        [
            busctl,
            "--user",
            "call",
            "org.freedesktop.impl.portal.PermissionStore",
            "/org/freedesktop/impl/portal/PermissionStore",
            "org.freedesktop.impl.portal.PermissionStore",
            "Lookup",
            "ss",
            table,
            object_id,
        ],
        timeout=2,
        budget=budget,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip() or "读取失败"
        if "No entry for" in detail:
            return {"status": "unrecorded", "detail": "portal 未记录", "raw": ""}
        return {"status": "unavailable", "detail": detail.splitlines()[0], "raw": ""}

    raw = result.stdout.strip()
    lower = raw.lower()
    app_lower = app_key.lower()
    if app_lower and app_lower in lower:
        if '"no"' in lower or " no" in lower:
            return {"status": "denied", "detail": "portal 记录为拒绝", "raw": raw[:240]}
        if '"yes"' in lower or " yes" in lower:
            return {"status": "allowed", "detail": "portal 记录为允许", "raw": raw[:240]}
        return {"status": "unknown", "detail": "portal 有记录，但状态无法解析", "raw": raw[:240]}
    if raw in ("", "a{sas} 0", "@a{sas} {}"):
        return {"status": "unrecorded", "detail": "portal 未记录", "raw": raw}
    return {"status": "unknown", "detail": "portal 返回了非空记录", "raw": raw[:240]}


def parse_flatpak_permissions(text):
    rows = []
    section = ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            rows.append(
                {
                    "id": f"flatpak:{section}:{key}",
                    "title": f"{section}.{key}" if section else key,
                    "detail": value,
                    "status": "declared",
                }
            )
        elif section:
            rows.append(
                {
                    "id": f"flatpak:{section}:{line}",
                    "title": section,
                    "detail": line,
                    "status": "declared",
                }
            )
    return rows


def static_permissions_for(item, sandbox, budget=None):
    sandbox_type = sandbox.get("type", "unknown")
    sandbox_id = sandbox.get("id", "")
    if sandbox_type != "flatpak":
        return []
    flatpak = shutil.which("flatpak")
    if not flatpak:
        row = {
            "id": "flatpak-missing",
            "title": "Flatpak permissions",
            "detail": "缺少 flatpak 命令，无法读取静态权限",
            "status": "unavailable",
        }
        return [apply_control(row, external_permission_control("Flatpak", row["status"]))]
    if budget is not None and budget.expired():
        row = {
            "id": "flatpak-budget",
            "title": "Flatpak permissions",
            "detail": "权限探测达到时间预算",
            "status": "unavailable",
        }
        return [apply_control(row, external_permission_control("Flatpak", row["status"]))]
    result = run(
        [flatpak, "info", "--show-permissions", sandbox_id],
        timeout=4,
        budget=budget,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip() or "flatpak info 读取失败"
        row = {
            "id": "flatpak-error",
            "title": "Flatpak permissions",
            "detail": detail.splitlines()[0],
            "status": "unavailable",
        }
        return [apply_control(row, external_permission_control("Flatpak", row["status"]))]
    rows = parse_flatpak_permissions(result.stdout)
    rows = rows or [
        {
            "id": "flatpak-empty",
            "title": "Flatpak permissions",
            "detail": "未声明额外静态权限",
            "status": "unrecorded",
        }
    ]
    return [apply_control(row, external_permission_control("Flatpak", row["status"])) for row in rows]


def snap_connections_for(item, sandbox, budget=None):
    sandbox_type = sandbox.get("type", "unknown")
    sandbox_id = sandbox.get("id", "")
    if sandbox_type != "snap":
        return []
    snap = shutil.which("snap")
    if not snap:
        row = {
            "id": "snap-missing",
            "title": "Snap connections",
            "detail": "缺少 snap 命令，无法读取权限连接",
            "status": "unavailable",
        }
        return [apply_control(row, external_permission_control("Snap", row["status"]))]
    if budget is not None and budget.expired():
        row = {
            "id": "snap-budget",
            "title": "Snap connections",
            "detail": "权限探测达到时间预算",
            "status": "unavailable",
        }
        return [apply_control(row, external_permission_control("Snap", row["status"]))]
    result = run([snap, "connections", sandbox_id], timeout=5, budget=budget)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip() or "snap connections 读取失败"
        row = {
            "id": "snap-error",
            "title": "Snap connections",
            "detail": detail.splitlines()[0],
            "status": "unavailable",
        }
        return [apply_control(row, external_permission_control("Snap", row["status"]))]
    rows = []
    for line in result.stdout.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 4:
            continue
        row = {
            "id": "snap:" + ":".join(parts[:2]),
            "title": parts[0],
            "detail": " ".join(parts[1:]),
            "status": "connected" if "-" not in parts[2:4] else "unconnected",
        }
        rows.append(apply_control(row, external_permission_control("Snap", row["status"])))
    return rows


def dir_size(path, limit_files=MAX_STORAGE_FILES, budget=None):
    total = 0
    count = 0
    try:
        for root, dirs, files in os.walk(path):
            dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
            for name in files:
                if budget is not None and budget.expired():
                    return total, True
                full = os.path.join(root, name)
                if os.path.islink(full):
                    continue
                try:
                    total += os.path.getsize(full)
                    count += 1
                except OSError:
                    continue
                if count >= limit_files:
                    return total, True
    except OSError:
        return 0, False
    return total, False


def human_bytes(value):
    number = float(value or 0)
    units = ["B", "KB", "MB", "GB", "TB"]
    index = 0
    while number >= 1024 and index < len(units) - 1:
        number /= 1024.0
        index += 1
    if index == 0:
        return f"{int(number)} {units[index]}"
    return f"{number:.1f} {units[index]}"


def storage_candidates(item, sandbox):
    home = Path.home()
    app_id = item.get("id", "")
    sandbox_id = sandbox.get("id", app_id)
    sandbox_type = sandbox.get("type", "none")
    paths = []
    if sandbox_type == "flatpak" and sandbox_id:
        paths.append(("Flatpak data", home / ".var/app" / sandbox_id))
    elif sandbox_type == "snap" and sandbox_id:
        paths.append(("Snap data", home / "snap" / sandbox_id))
    if app_id:
        data_home = Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share")
        cache_home = Path(os.environ.get("XDG_CACHE_HOME") or home / ".cache")
        config_home = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
        for root_name, root_path in (("Data", data_home), ("Cache", cache_home), ("Config", config_home)):
            paths.append((root_name, root_path / app_id))
    return paths


def storage_for(item, sandbox, budget=None):
    rows = []
    total = 0
    for title, path in storage_candidates(item, sandbox):
        if budget is not None and budget.expired():
            break
        if not path.exists():
            continue
        size, truncated = dir_size(path, budget=budget)
        total += size
        rows.append(
            {
                "id": str(path),
                "title": title,
                "path": str(path),
                "bytes": size,
                "size": human_bytes(size),
                "truncated": truncated,
            }
        )
    return {
        "totalBytes": total,
        "total": human_bytes(total),
        "items": rows,
        "budgetExpired": bool(budget is not None and budget.expired()),
    }


def permissions_for(desktop_id, budget_ms=PERMISSIONS_PROBE_BUDGET_MS):
    budget = budget_ms if isinstance(budget_ms, Budget) else Budget(budget_ms)
    meta = scan_desktop_entries(budget)
    item = meta.get(desktop_id, {})
    app_key = item.get("sandboxId") or desktop_id.removesuffix(".desktop")
    sandbox_type = item.get("sandboxType", "none")
    fully_enforceable = sandbox_type in ("flatpak", "snap")
    sandbox = {
        "type": sandbox_type,
        "sandboxType": sandbox_type,
        "id": app_key,
        "sandboxId": app_key,
        "fullyEnforceable": fully_enforceable,
        "desktopId": desktop_id,
        "writeScope": "none",
        "enforcementScope": "runtime-sandbox" if fully_enforceable else "none",
    }

    available, portal_status, portal_detail = permission_store_available(budget)
    capability = {
        "sandboxType": sandbox_type,
        "sandboxId": app_key,
        "fullyEnforceable": fully_enforceable,
        "portalStatus": portal_status,
        "defaultControl": CONTROL_WARNING if portal_status != "ok" else CONTROL_READONLY,
        "canTogglePortalPermissions": False,
        "canWriteStaticPermissions": False,
        "writeScope": "none",
        "ordinaryAppWarning": sandbox_type == "none",
        "staticPermissionScope": "runtime-metadata" if sandbox_type in ("flatpak", "snap") else "none",
    }
    rows = []
    for permission in PERMISSIONS:
        object_id = app_key if permission["object"] == "app" else permission["object"]
        if budget.expired():
            result = {
                "status": "unavailable",
                "detail": "权限探测达到时间预算",
                "raw": "",
            }
        elif available:
            result = lookup_permission(permission["table"], object_id, app_key, budget)
        else:
            result = {"status": "unavailable", "detail": portal_detail, "raw": ""}
        rows.append(
            {
                "id": permission["id"],
                "title": permission["title"],
                "table": permission["table"],
                "object": object_id,
                "status": result["status"],
                "detail": result["detail"],
                "raw": result["raw"],
                **portal_permission_control(sandbox_type, portal_status),
            }
        )

    if sandbox_type == "none":
        portal_detail = portal_detail + "；普通桌面应用的权限不能被 Tahoe 完整强制执行"

    return {
        **schema_fields("permissions"),
        "app": {
            "desktopId": desktop_id,
            "id": item.get("id", desktop_id.removesuffix(".desktop")),
            "name": item.get("name", desktop_id.removesuffix(".desktop")),
            "sandboxType": sandbox_type,
            "sandboxId": app_key,
        },
        "portal": {
            "status": portal_status,
            "portalStatus": portal_status,
            "detail": portal_detail,
            "available": available,
            "canRead": available,
            "canWrite": False,
        },
        "capability": capability,
        "sandbox": sandbox,
        "permissions": rows,
        "staticPermissions": static_permissions_for(item, sandbox, budget),
        "snapConnections": snap_connections_for(item, sandbox, budget),
        "storage": storage_for(item, sandbox, budget),
        "budget": budget.summary(),
    }


def budget_option(argv, default):
    try:
        index = argv.index("--budget-ms")
    except ValueError:
        return default
    if index + 1 >= len(argv):
        return default
    try:
        return max(1, int(argv[index + 1]))
    except (TypeError, ValueError):
        return default


def main(argv):
    mode = argv[1] if len(argv) > 1 else "probe"
    if mode == "probe":
        emit(probe_defaults(budget_option(argv, DEFAULT_PROBE_BUDGET_MS)))
    elif mode == "fingerprint":
        emit(defaults_fingerprint(budget_option(argv, DEFAULT_FINGERPRINT_BUDGET_MS)))
    elif mode == "set-default":
        emit(set_default(argv[2] if len(argv) > 2 else "", argv[3:]))
    elif mode == "permissions":
        emit(
            permissions_for(
                argv[2] if len(argv) > 2 else "",
                budget_option(argv, PERMISSIONS_PROBE_BUDGET_MS),
            )
        )
    else:
        emit({"success": False, "message": "unknown mode"})
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
