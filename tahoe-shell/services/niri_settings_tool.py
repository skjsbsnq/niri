#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path
from typing import Any


NUMBER_RE = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)"


class KdlEditError(RuntimeError):
    pass


def json_out(payload: dict[str, Any], code: int = 0) -> None:
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    raise SystemExit(code)


def split_newline(line: str) -> tuple[str, str]:
    if line.endswith("\n"):
        return line[:-1], "\n"
    return line, ""


def split_line_comment(line: str) -> tuple[str, str, str]:
    body, newline = split_newline(line)
    in_string = False
    escaped = False
    for index in range(len(body) - 1):
        char = body[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
            continue
        if char == "/" and body[index + 1] == "/":
            return body[:index].rstrip(), body[index:], newline
    return body.rstrip(), "", newline


def uncommented_body(line: str) -> str:
    return split_line_comment(line)[0]


def brace_delta(line: str) -> int:
    body = uncommented_body(line)
    in_string = False
    escaped = False
    delta = 0
    for char in body:
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            delta += 1
        elif char == "}":
            delta -= 1
    return delta


def leading_indent(line: str) -> str:
    return re.match(r"^(\s*)", line).group(1)


def find_top_level_block(lines: list[str], name: str) -> tuple[int, int]:
    depth = 0
    start_re = re.compile(rf"^\s*{re.escape(name)}\b[^\n{{]*\{{\s*$")
    for index, line in enumerate(lines):
        body = uncommented_body(line)
        if depth == 0 and start_re.match(body):
            local_depth = 0
            for end in range(index, len(lines)):
                local_depth += brace_delta(lines[end])
                if local_depth == 0:
                    return index, end
            break
        depth += brace_delta(line)
    raise KdlEditError(f"missing top-level {name} block")


def find_child_block(lines: list[str], parent_start: int, parent_end: int, name: str) -> tuple[int, int] | None:
    depth = 1
    start_re = re.compile(rf"^\s*{re.escape(name)}\b[^\n{{]*\{{\s*$")
    for index in range(parent_start + 1, parent_end):
        body = uncommented_body(lines[index])
        if depth == 1 and start_re.match(body):
            local_depth = 0
            for end in range(index, parent_end + 1):
                local_depth += brace_delta(lines[end])
                if local_depth == 0:
                    return index, end
            raise KdlEditError(f"unterminated {name} block")
        depth += brace_delta(lines[index])
    return None


def iter_depth_lines(lines: list[str], start: int, end: int, depth: int) -> list[int]:
    current = depth
    found: list[int] = []
    for index in range(start + 1, end):
        if current == depth:
            found.append(index)
        current += brace_delta(lines[index])
    return found


def parse_number(text: str, default: float) -> float:
    match = re.search(NUMBER_RE, text)
    if not match:
        return default
    return float(match.group(0))


def normalize_number(value: float) -> int | float:
    if float(value).is_integer():
        return int(value)
    return round(float(value), 6)


def format_number(value: float) -> str:
    if float(value).is_integer():
        return str(int(value))
    return f"{float(value):.6f}".rstrip("0").rstrip(".")


def parse_bool(value: str) -> bool:
    text = str(value).strip().lower()
    if text in {"1", "true", "yes", "on", "enabled"}:
        return True
    if text in {"0", "false", "no", "off", "disabled"}:
        return False
    raise KdlEditError(f"invalid boolean value: {value}")


def bounded_number(value: str, minimum: float, maximum: float) -> float:
    try:
        parsed = float(value)
    except ValueError as exc:
        raise KdlEditError(f"invalid numeric value: {value}") from exc
    if parsed < minimum or parsed > maximum:
        raise KdlEditError(f"value {value} outside allowed range {minimum:g}..{maximum:g}")
    return parsed


def simple_field_number(lines: list[str], start: int, end: int, name: str, default: float) -> float:
    node_re = re.compile(rf"^\s*{re.escape(name)}\b\s+(.+?)\s*$")
    for index in iter_depth_lines(lines, start, end, 1):
        body = uncommented_body(lines[index])
        if "{" in body:
            continue
        match = node_re.match(body)
        if match:
            return parse_number(match.group(1), default)
    return default


def child_field_number(lines: list[str], block: tuple[int, int] | None, name: str, default: float) -> float:
    if block is None:
        return default
    node_re = re.compile(rf"^\s*{re.escape(name)}\b\s+(.+?)\s*$")
    for index in iter_depth_lines(lines, block[0], block[1], 2):
        body = uncommented_body(lines[index])
        if "{" in body:
            continue
        match = node_re.match(body)
        if match:
            return parse_number(match.group(1), default)
    return default


def offset_value(lines: list[str], block: tuple[int, int] | None, key: str, default: float) -> float:
    if block is None:
        return default
    for index in iter_depth_lines(lines, block[0], block[1], 2):
        body = uncommented_body(lines[index])
        if not re.match(r"^\s*offset\b", body):
            continue
        match = re.search(rf"\b{re.escape(key)}=({NUMBER_RE})", body)
        if match:
            return float(match.group(1))
    return default


def block_toggle(
    lines: list[str],
    block: tuple[int, int] | None,
    absent_default: bool,
    empty_default: bool,
    on_wins: bool,
) -> bool:
    if block is None:
        return absent_default
    saw_on = False
    saw_off = False
    for index in iter_depth_lines(lines, block[0], block[1], 2):
        body = uncommented_body(lines[index]).strip()
        if body == "on":
            saw_on = True
        elif body == "off":
            saw_off = True
    if saw_on and on_wins:
        return True
    if saw_off:
        return False
    if saw_on:
        return True
    return empty_default


def read_layout_text(text: str) -> dict[str, Any]:
    lines = text.splitlines(True)
    layout = find_top_level_block(lines, "layout")
    focus = find_child_block(lines, layout[0], layout[1], "focus-ring")
    border = find_child_block(lines, layout[0], layout[1], "border")
    shadow = find_child_block(lines, layout[0], layout[1], "shadow")
    snap = find_child_block(lines, layout[0], layout[1], "snap-assist")

    return {
        "gaps": normalize_number(simple_field_number(lines, layout[0], layout[1], "gaps", 16)),
        "focusRing": {
            "enabled": block_toggle(lines, focus, absent_default=True, empty_default=True, on_wins=True),
        },
        "border": {
            "enabled": block_toggle(lines, border, absent_default=False, empty_default=True, on_wins=True),
        },
        "shadow": {
            "enabled": block_toggle(lines, shadow, absent_default=False, empty_default=False, on_wins=False),
            "softness": normalize_number(child_field_number(lines, shadow, "softness", 30)),
            "spread": normalize_number(child_field_number(lines, shadow, "spread", 5)),
            "offsetX": normalize_number(offset_value(lines, shadow, "x", 0)),
            "offsetY": normalize_number(offset_value(lines, shadow, "y", 5)),
        },
        "snapAssist": {
            "enabled": block_toggle(lines, snap, absent_default=False, empty_default=False, on_wins=True),
            "threshold": normalize_number(child_field_number(lines, snap, "threshold", 36)),
        },
    }


def child_indent(lines: list[str], block_start: int, block_end: int, parent_indent: str) -> str:
    for index in range(block_start + 1, block_end):
        body = uncommented_body(lines[index]).strip()
        if body:
            return leading_indent(lines[index])
    return parent_indent + "    "


def layout_child_indent(lines: list[str], layout: tuple[int, int]) -> str:
    parent_indent = leading_indent(lines[layout[0]])
    for index in range(layout[0] + 1, layout[1]):
        body = uncommented_body(lines[index]).strip()
        if body:
            return leading_indent(lines[index])
    return parent_indent + "    "


def replace_simple_line(lines: list[str], index: int, name: str, value: str) -> None:
    _, comment, newline = split_line_comment(lines[index])
    indent = leading_indent(lines[index])
    gap = " " if comment else ""
    lines[index] = f"{indent}{name} {value}{gap}{comment}{newline}"


def replace_flag_line(lines: list[str], index: int, enabled: bool) -> None:
    _, comment, newline = split_line_comment(lines[index])
    indent = leading_indent(lines[index])
    gap = " " if comment else ""
    lines[index] = f"{indent}{'on' if enabled else 'off'}{gap}{comment}{newline}"


def set_layout_number(lines: list[str], layout: tuple[int, int], name: str, value: float) -> None:
    node_re = re.compile(rf"^\s*{re.escape(name)}\b\s+")
    for index in iter_depth_lines(lines, layout[0], layout[1], 1):
        body = uncommented_body(lines[index])
        if "{" in body:
            continue
        if node_re.match(body):
            replace_simple_line(lines, index, name, format_number(value))
            return
    indent = layout_child_indent(lines, layout)
    lines.insert(layout[1], f"{indent}{name} {format_number(value)}\n")


def create_child_block(lines: list[str], layout: tuple[int, int], name: str, body_lines: list[str]) -> tuple[int, int]:
    indent = layout_child_indent(lines, layout)
    inner = indent + "    "
    block = [f"{indent}{name} {{\n"]
    block.extend(f"{inner}{line}\n" for line in body_lines)
    block.append(f"{indent}}}\n")
    insert_at = layout[1]
    lines[insert_at:insert_at] = block
    return insert_at, insert_at + len(block) - 1


def set_child_toggle(lines: list[str], layout: tuple[int, int], name: str, enabled: bool) -> None:
    block = find_child_block(lines, layout[0], layout[1], name)
    if block is None:
        create_child_block(lines, layout, name, ["on" if enabled else "off"])
        return

    flag_re = re.compile(r"^\s*(?:on|off)\s*$")
    first: int | None = None
    remove: list[int] = []
    for index in iter_depth_lines(lines, block[0], block[1], 2):
        body = uncommented_body(lines[index])
        if not flag_re.match(body):
            continue
        if first is None:
            first = index
        else:
            remove.append(index)

    if first is None:
        indent = child_indent(lines, block[0], block[1], leading_indent(lines[block[0]]))
        lines.insert(block[0] + 1, f"{indent}{'on' if enabled else 'off'}\n")
        return

    replace_flag_line(lines, first, enabled)
    for index in reversed(remove):
        del lines[index]


def set_child_number(lines: list[str], layout: tuple[int, int], block_name: str, name: str, value: float) -> None:
    block = find_child_block(lines, layout[0], layout[1], block_name)
    if block is None:
        create_child_block(lines, layout, block_name, [f"{name} {format_number(value)}"])
        return

    node_re = re.compile(rf"^\s*{re.escape(name)}\b\s+")
    for index in iter_depth_lines(lines, block[0], block[1], 2):
        body = uncommented_body(lines[index])
        if "{" in body:
            continue
        if node_re.match(body):
            replace_simple_line(lines, index, name, format_number(value))
            return

    indent = child_indent(lines, block[0], block[1], leading_indent(lines[block[0]]))
    lines.insert(block[1], f"{indent}{name} {format_number(value)}\n")


def set_shadow_offset(lines: list[str], layout: tuple[int, int], key: str, value: float) -> None:
    block = find_child_block(lines, layout[0], layout[1], "shadow")
    if block is None:
        x_value = value if key == "x" else 0
        y_value = value if key == "y" else 5
        create_child_block(lines, layout, "shadow", [f"offset x={format_number(x_value)} y={format_number(y_value)}"])
        return

    for index in iter_depth_lines(lines, block[0], block[1], 2):
        body = uncommented_body(lines[index])
        if not re.match(r"^\s*offset\b", body):
            continue
        current_x = offset_value(lines, block, "x", 0)
        current_y = offset_value(lines, block, "y", 5)
        if key == "x":
            current_x = value
        else:
            current_y = value
        _, comment, newline = split_line_comment(lines[index])
        indent = leading_indent(lines[index])
        gap = " " if comment else ""
        lines[index] = (
            f"{indent}offset x={format_number(current_x)} y={format_number(current_y)}{gap}{comment}{newline}"
        )
        return

    indent = child_indent(lines, block[0], block[1], leading_indent(lines[block[0]]))
    x_value = value if key == "x" else 0
    y_value = value if key == "y" else 5
    lines.insert(block[1], f"{indent}offset x={format_number(x_value)} y={format_number(y_value)}\n")


def update_layout_text(text: str, field: str, raw_value: str) -> str:
    lines = text.splitlines(True)
    layout = find_top_level_block(lines, "layout")

    if field == "layout.gaps":
        set_layout_number(lines, layout, "gaps", bounded_number(raw_value, 0, 65535))
    elif field == "layout.focus_ring.enabled":
        set_child_toggle(lines, layout, "focus-ring", parse_bool(raw_value))
    elif field == "layout.border.enabled":
        set_child_toggle(lines, layout, "border", parse_bool(raw_value))
    elif field == "layout.shadow.enabled":
        set_child_toggle(lines, layout, "shadow", parse_bool(raw_value))
    elif field == "layout.shadow.softness":
        set_child_number(lines, layout, "shadow", "softness", bounded_number(raw_value, 0, 1024))
    elif field == "layout.shadow.spread":
        set_child_number(lines, layout, "shadow", "spread", bounded_number(raw_value, -1024, 1024))
    elif field == "layout.shadow.offset_x":
        set_shadow_offset(lines, layout, "x", bounded_number(raw_value, -65535, 65535))
    elif field == "layout.shadow.offset_y":
        set_shadow_offset(lines, layout, "y", bounded_number(raw_value, -65535, 65535))
    elif field == "layout.snap_assist.enabled":
        set_child_toggle(lines, layout, "snap-assist", parse_bool(raw_value))
    elif field == "layout.snap_assist.threshold":
        set_child_number(lines, layout, "snap-assist", "threshold", bounded_number(raw_value, 0, 65535))
    else:
        raise KdlEditError(f"unsupported field: {field}")

    return "".join(lines)


def config_guardrails(text: str) -> None:
    if re.search(r"(?m)^[ \t]*variable-refresh-rate(?:[ \t]|$)", text):
        raise KdlEditError("guardrail failed: variable-refresh-rate must stay disabled by default")
    if re.search(r'namespace[ \t]*=[ \t]*"\^quickshell"', text):
        raise KdlEditError('guardrail failed: broad namespace="^quickshell" rule is not allowed')
    if not re.search(r'match[ \t]+namespace[ \t]*=[ \t]*"\^tahoe-', text):
        raise KdlEditError("guardrail failed: explicit tahoe-* namespace rules are required")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def find_niri_bin(explicit: str | None) -> str:
    if explicit:
        return explicit
    env_bin = os.environ.get("NIRI_BIN")
    if env_bin:
        return env_bin
    found = shutil.which("niri")
    if found:
        return found
    repo_bin = repo_root() / "niri" / "target" / "release" / "niri"
    if repo_bin.exists():
        return str(repo_bin)
    raise KdlEditError("niri binary not found; refusing unvalidated write")


def validate_config(path: Path, explicit_niri_bin: str | None) -> None:
    niri_bin = find_niri_bin(explicit_niri_bin)
    result = subprocess.run(
        [niri_bin, "validate", "-c", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stdout.strip() or f"exit {result.returncode}"
        raise KdlEditError(f"niri validate failed: {detail}")


def atomic_write(path: Path, text: str, explicit_niri_bin: str | None, skip_guardrails: bool) -> None:
    if not skip_guardrails:
        config_guardrails(text)

    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp_path, mode)
        validate_config(tmp_path, explicit_niri_bin)
        os.replace(tmp_path, path)
        os.utime(path, None)
    except Exception:
        try:
            tmp_path.unlink()
        except FileNotFoundError:
            pass
        raise


def read_command(args: argparse.Namespace) -> None:
    config_path = Path(args.config).expanduser()
    text = config_path.read_text(encoding="utf-8")
    json_out({"ok": True, "config": str(config_path), "layout": read_layout_text(text)})


def write_command(args: argparse.Namespace) -> None:
    config_path = Path(args.config).expanduser()
    text = config_path.read_text(encoding="utf-8")
    updated = update_layout_text(text, args.field, args.value)
    changed = updated != text
    if changed:
        atomic_write(config_path, updated, args.niri_bin, args.skip_guardrails)
    layout = read_layout_text(updated)
    json_out({"ok": True, "changed": changed, "config": str(config_path), "layout": layout})


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Tahoe niri settings KDL reader/writer")
    subparsers = parser.add_subparsers(dest="command", required=True)

    read_parser = subparsers.add_parser("read")
    read_parser.add_argument("--config", required=True)
    read_parser.set_defaults(func=read_command)

    write_parser = subparsers.add_parser("write")
    write_parser.add_argument("--config", required=True)
    write_parser.add_argument("--field", required=True)
    write_parser.add_argument("--value", required=True)
    write_parser.add_argument("--niri-bin")
    write_parser.add_argument("--skip-guardrails", action="store_true")
    write_parser.set_defaults(func=write_command)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    try:
        args.func(args)
    except (OSError, subprocess.SubprocessError, KdlEditError) as exc:
        json_out({"ok": False, "error": str(exc)}, 1)


if __name__ == "__main__":
    main()
