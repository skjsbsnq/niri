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


# --- tahoe-glass + blur (S5.1) -------------------------------------------
# tahoe-glass materials are keyed by a string argument (material "panel" {}),
# one level deeper than the layout child blocks, so they need a dedicated
# string-arg finder. The per-field readers default to the compositor scene
# defaults when a block or field is absent so the GUI never hard-fails on an
# optional block. All glass/blur writes reuse the same atomic_write path
# (guardrails + niri validate) as layout.

GLASS_MATERIAL_NAMES = ["panel", "pill", "launcher", "dock", "menu", "toast", "backdrop"]
GLASS_MATERIAL_FIELDS = ["edge-highlight", "refraction", "inner-shadow", "chromatic", "lens-depth"]
GLASS_MATERIAL_DEFAULTS = {
    "panel": {"edge-highlight": 0.14, "refraction": 0.004, "inner-shadow": 0.06, "chromatic": 0.0, "lens-depth": 0.0},
    "pill": {"edge-highlight": 0.32, "refraction": 0.013, "inner-shadow": 0.07, "chromatic": 0.0, "lens-depth": 0.010},
    "launcher": {"edge-highlight": 0.15, "refraction": 0.004, "inner-shadow": 0.055, "chromatic": 0.0, "lens-depth": 0.003},
    "dock": {"edge-highlight": 0.18, "refraction": 0.007, "inner-shadow": 0.07, "chromatic": 0.0, "lens-depth": 0.006},
    "menu": {"edge-highlight": 0.26, "refraction": 0.004, "inner-shadow": 0.10, "chromatic": 0.0, "lens-depth": 0.0},
    "toast": {"edge-highlight": 0.24, "refraction": 0.005, "inner-shadow": 0.09, "chromatic": 0.0, "lens-depth": 0.0},
    "backdrop": {"edge-highlight": 0.05, "refraction": 0.002, "inner-shadow": 0.0, "chromatic": 0.0, "lens-depth": 0.0},
}


def find_top_level_block_or_none(lines: list[str], name: str) -> tuple[int, int] | None:
    try:
        return find_top_level_block(lines, name)
    except KdlEditError:
        return None


def block_child_indent(lines: list[str], block: tuple[int, int]) -> str:
    parent_indent = leading_indent(lines[block[0]])
    for index in range(block[0] + 1, block[1]):
        if uncommented_body(lines[index]).strip():
            return leading_indent(lines[index])
    return parent_indent + "    "


def find_material_block(lines: list[str], glass: tuple[int, int], name: str) -> tuple[int, int] | None:
    depth = 1
    start_re = re.compile(rf'^\s*material\s+"{re.escape(name)}"\s*\{{\s*$')
    for index in range(glass[0] + 1, glass[1]):
        body = uncommented_body(lines[index])
        if depth == 1 and start_re.match(body):
            local_depth = 0
            for end in range(index, glass[1] + 1):
                local_depth += brace_delta(lines[end])
                if local_depth == 0:
                    return index, end
            raise KdlEditError(f"unterminated material {name}")
        depth += brace_delta(lines[index])
    return None


def create_material_block(lines: list[str], glass: tuple[int, int], name: str, body_lines: list[str]) -> tuple[int, int]:
    indent = block_child_indent(lines, glass)
    inner = indent + "    "
    block = [f'{indent}material "{name}" {{\n']
    block.extend(f"{inner}{line}\n" for line in body_lines)
    block.append(f"{indent}}}\n")
    insert_at = glass[1]
    lines[insert_at:insert_at] = block
    return insert_at, insert_at + len(block) - 1


def set_leaf_value(lines: list[str], block: tuple[int, int], name: str, value_str: str) -> None:
    """Set a `name value` leaf among the direct children of block.

    value_str is the exact text to write after the name, so callers control
    int vs float formatting (glass/blur fields are floats in the source and
    must round-trip 0.0 -> 0.0, not 0.0 -> 0).
    """
    node_re = re.compile(rf"^\s*{re.escape(name)}\b\s+")
    for index in iter_depth_lines(lines, block[0], block[1], 1):
        body = uncommented_body(lines[index])
        if "{" in body:
            continue
        match = node_re.match(body)
        if match:
            # Preserve the original token when the value is unchanged: glass
            # floats are written with varying precision in the source (0.10,
            # 0.045, 0.4) and re-writing the same value should not normalize
            # 0.10 -> 0.1. Only lines whose value actually changes get the
            # canonical formatting.
            existing = parse_number(body[match.end():], default=float("nan"))
            try:
                desired = float(value_str)
            except ValueError:
                desired = float("nan")
            if existing == desired:
                return
            replace_simple_line(lines, index, name, value_str)
            return
    indent = block_child_indent(lines, block)
    lines.insert(block[1], f"{indent}{name} {value_str}\n")


def format_float(value: float) -> str:
    """Format a float preserving a decimal point (0 -> "0.0", 0.34 -> "0.34")."""
    v = float(value)
    if v == int(v):
        return f"{int(v)}.0"
    return f"{v:.6f}".rstrip("0")


def read_glass_text(text: str) -> dict[str, Any]:
    lines = text.splitlines(True)
    glass = find_top_level_block_or_none(lines, "tahoe-glass")
    materials: dict[str, Any] = {}
    for name in GLASS_MATERIAL_NAMES:
        material: dict[str, Any] = {}
        block = find_material_block(lines, glass, name) if glass else None
        for field in GLASS_MATERIAL_FIELDS:
            default = GLASS_MATERIAL_DEFAULTS[name][field]
            material[field.replace("-", "_")] = (
                normalize_number(child_field_number(lines, block, field, default)) if block else default
            )
        materials[name] = material
    return {"materials": materials}


def read_blur_text(text: str) -> dict[str, Any]:
    lines = text.splitlines(True)
    blur = find_top_level_block_or_none(lines, "blur")
    if blur is None:
        return {"enabled": True, "passes": 3, "offset": 3, "noise": 0.02, "saturation": 1.5}
    return {
        "enabled": block_toggle(lines, blur, absent_default=True, empty_default=True, on_wins=True),
        "passes": normalize_number(simple_field_number(lines, blur[0], blur[1], "passes", 3)),
        "offset": normalize_number(simple_field_number(lines, blur[0], blur[1], "offset", 3)),
        "noise": normalize_number(simple_field_number(lines, blur[0], blur[1], "noise", 0.02)),
        "saturation": normalize_number(simple_field_number(lines, blur[0], blur[1], "saturation", 1.5)),
    }


def set_blur_enabled(lines: list[str], enabled: bool) -> None:
    blur = find_top_level_block(lines, "blur")
    flag_re = re.compile(r"^\s*(?:on|off)\s*$")
    first: int | None = None
    remove: list[int] = []
    for index in iter_depth_lines(lines, blur[0], blur[1], 1):
        body = uncommented_body(lines[index])
        if flag_re.match(body):
            if first is None:
                first = index
            else:
                remove.append(index)
    if first is None:
        indent = block_child_indent(lines, blur)
        lines.insert(blur[0] + 1, f"{indent}{'on' if enabled else 'off'}\n")
        return
    replace_flag_line(lines, first, enabled)
    for index in reversed(remove):
        del lines[index]


# --- input (S5.2) --------------------------------------------------------
# keyboard repeat-rate/repeat-delay/numlock + touchpad tap/natural-scroll/
# dwt/accel-speed. tap/natural-scroll/dwt/numlock are bare flags (presence =
# on); the writer emits bare `name` for on and `name false` for off, and
# preserves the original token when the state is unchanged. output scale is
# read-only (display only) — the GUI never writes it, and VRR is never touched.

INPUT_KEYBOARD_FLAGS = ["numlock"]
INPUT_TOUCHPAD_FLAGS = ["tap", "natural-scroll", "dwt"]


def flag_state_in_block(lines: list[str], block: tuple[int, int] | None, name: str, default: bool) -> bool:
    if block is None:
        return default
    flag_re = re.compile(rf"^\s*{re.escape(name)}(?:\s+(true|false|on|off))?\s*$")
    for index in iter_depth_lines(lines, block[0], block[1], 1):
        body = uncommented_body(lines[index]).strip()
        m = flag_re.match(body)
        if not m:
            continue
        val = m.group(1)
        return val not in ("false", "off")
    return default


def set_flag_in_block(lines: list[str], block: tuple[int, int], name: str, enabled: bool) -> None:
    flag_re = re.compile(rf"^\s*{re.escape(name)}(?:\s+(?:true|false|on|off))?\s*$")
    for index in iter_depth_lines(lines, block[0], block[1], 1):
        body = uncommented_body(lines[index])
        if not flag_re.match(body.strip()):
            continue
        current = flag_state_in_block(lines, block, name, default=not enabled)
        if current == enabled:
            return  # preserve original token (bare stays bare)
        _, comment, newline = split_line_comment(lines[index])
        indent = leading_indent(lines[index])
        gap = " " if comment else ""
        token = name if enabled else f"{name} false"
        lines[index] = f"{indent}{token}{gap}{comment}{newline}"
        return
    # Absent: enabling inserts a bare flag; disabling is a no-op (absent = off).
    if enabled:
        indent = block_child_indent(lines, block)
        lines.insert(block[1], f"{indent}{name}\n")


def read_output_text(text: str) -> dict[str, Any]:
    lines = text.splitlines(True)
    start_re = re.compile(r'^\s*output\s+"([^"]+)"\s*\{\s*$')
    depth = 0
    for index, line in enumerate(lines):
        body = uncommented_body(line)
        if depth == 0 and start_re.match(body):
            name = start_re.match(body).group(1)
            local = 0
            for end in range(index, len(lines)):
                local += brace_delta(lines[end])
                if local == 0:
                    scale = simple_field_number(lines, index, end, "scale", 1.0)
                    return {"name": name, "scale": normalize_number(scale), "present": True}
            break
        depth += brace_delta(line)
    return {"name": "", "scale": 1.0, "present": False}


def read_input_text(text: str) -> dict[str, Any]:
    lines = text.splitlines(True)
    input_block = find_top_level_block_or_none(lines, "input")
    keyboard = {"repeat_rate": 25, "repeat_delay": 600, "numlock": False}
    touchpad = {"tap": False, "natural_scroll": False, "dwt": False, "accel_speed": 0.0}
    if input_block:
        keyboard_block = find_child_block(lines, input_block[0], input_block[1], "keyboard")
        if keyboard_block:
            keyboard["repeat_rate"] = normalize_number(child_field_number(lines, keyboard_block, "repeat-rate", 25))
            keyboard["repeat_delay"] = normalize_number(child_field_number(lines, keyboard_block, "repeat-delay", 600))
            keyboard["numlock"] = flag_state_in_block(lines, keyboard_block, "numlock", default=False)
        touchpad_block = find_child_block(lines, input_block[0], input_block[1], "touchpad")
        if touchpad_block:
            touchpad["tap"] = flag_state_in_block(lines, touchpad_block, "tap", default=False)
            touchpad["natural_scroll"] = flag_state_in_block(lines, touchpad_block, "natural-scroll", default=False)
            touchpad["dwt"] = flag_state_in_block(lines, touchpad_block, "dwt", default=False)
            touchpad["accel_speed"] = normalize_number(child_field_number(lines, touchpad_block, "accel-speed", 0.0))
    return {"keyboard": keyboard, "touchpad": touchpad, "output": read_output_text(text)}


# --- animations (S5.3) ----------------------------------------------------
# Spring params for the spring-based actions present in the config. Each action
# node holds a single `spring damping-ratio=X stiffness=Y epsilon=Z` line; the
# writer rewrites that whole line (preserving all three params) and skips the
# rewrite when the target param is unchanged. window-open/close carry custom
# GLSL shaders and are intentionally never touched by the GUI.

ANIM_ACTIONS = ["workspace-switch", "window-movement", "window-resize", "overview-open-close"]
ANIM_SPRING_PARAMS = ["damping-ratio", "stiffness", "epsilon"]


def parse_spring_line(body: str) -> dict[str, float]:
    vals = {"damping-ratio": 1.0, "stiffness": 1000.0, "epsilon": 0.0001}
    for param in ANIM_SPRING_PARAMS:
        m = re.search(rf"\b{re.escape(param)}=({NUMBER_RE})", body)
        if m:
            vals[param] = float(m.group(1))
    return vals


def format_spring(vals: dict[str, float]) -> str:
    return (
        f"spring damping-ratio={format_float(vals['damping-ratio'])} "
        f"stiffness={format_number(vals['stiffness'])} "
        f"epsilon={format_float(vals['epsilon'])}"
    )


def read_animations_text(text: str) -> dict[str, Any]:
    lines = text.splitlines(True)
    anim = find_top_level_block_or_none(lines, "animations")
    actions: dict[str, Any] = {}
    for action in ANIM_ACTIONS:
        block = find_child_block(lines, anim[0], anim[1], action) if anim else None
        vals: dict[str, float] | None = None
        if block:
            for index in iter_depth_lines(lines, block[0], block[1], 2):
                body = uncommented_body(lines[index])
                if re.match(r"^\s*spring\b", body):
                    vals = parse_spring_line(body)
                    break
        if vals is None:
            vals = {"damping-ratio": 1.0, "stiffness": 1000.0, "epsilon": 0.0001}
        actions[action.replace("-", "_")] = {
            "damping_ratio": normalize_number(vals["damping-ratio"]),
            "stiffness": normalize_number(vals["stiffness"]),
            "epsilon": normalize_number(vals["epsilon"]),
        }
    return {"actions": actions}


def set_anim_spring(lines: list[str], anim: tuple[int, int], action: str, param: str, value: float) -> None:
    block = find_child_block(lines, anim[0], anim[1], action)
    if block is None:
        vals = {"damping-ratio": 1.0, "stiffness": 1000.0, "epsilon": 0.0001}
        vals[param] = value
        create_child_block(lines, anim, action, [format_spring(vals)])
        return

    for index in iter_depth_lines(lines, block[0], block[1], 2):
        body = uncommented_body(lines[index])
        if not re.match(r"^\s*spring\b", body):
            continue
        vals = parse_spring_line(body)
        if vals[param] == value:
            return  # unchanged: preserve original token
        vals[param] = value
        _, comment, newline = split_line_comment(lines[index])
        indent = leading_indent(lines[index])
        gap = " " if comment else ""
        lines[index] = f"{indent}{format_spring(vals)}{gap}{comment}{newline}"
        return

    # Action block exists but has no spring line (e.g. an easing/shader action);
    # do not invent a spring line for it.
    raise KdlEditError(f"action {action} has no spring line to edit")


# --- binds (S5.4, read-only) ---------------------------------------------
# Enumerate the top-level `binds {}` block for a read-only viewer. Each child
# node is one keybind whose node-name IS the key combo; we capture the combo,
# the first action token, the full raw text, and whether it is one of the
# Tahoe task-switcher IPC binds (protected — guardrail 441b637). There is no
# write path: the GUI never edits binds.

PROTECTED_BIND_TOKENS = ("cycleTaskSwitcher", "toggleWindowOverview", "openWindowOverview")


def read_binds_text(text: str) -> dict[str, Any]:
    lines = text.splitlines(True)
    binds = find_top_level_block_or_none(lines, "binds")
    items: list[dict[str, Any]] = []
    if not binds:
        return {"items": items}

    for index in iter_depth_lines(lines, binds[0], binds[1], 1):
        body = uncommented_body(lines[index])
        if not body.strip():
            continue
        combo_match = re.match(r"^\s*(\S+)", body)
        combo = combo_match.group(1) if combo_match else "?"

        # Gather the full bind node (single line, or multi-line until braces balance).
        raw_lines = [lines[index].rstrip("\n")]
        depth = 0
        for j in range(index, binds[1] + 1):
            depth += brace_delta(lines[j])
            if j > index:
                raw_lines.append(lines[j].rstrip("\n"))
            if depth == 0:
                break
        raw = "\n".join(raw_lines).strip()

        first_action = ""
        action_match = re.search(r"\{[^;{}]*?([\w-]+)", raw)
        if action_match:
            first_action = action_match.group(1)

        protected = any(token in raw for token in PROTECTED_BIND_TOKENS)
        items.append({"combo": combo, "action": first_action, "raw": raw, "protected": protected})

    return {"items": items}


def update_field(text: str, field: str, raw_value: str) -> str:
    if field.startswith("layout."):
        return update_layout_text(text, field, raw_value)

    lines = text.splitlines(True)

    if field.startswith("glass."):
        parts = field.split(".")
        if len(parts) != 3:
            raise KdlEditError(f"unsupported glass field: {field}")
        material_name, field_raw = parts[1], parts[2]
        field_kdl = field_raw.replace("_", "-")
        glass = find_top_level_block(lines, "tahoe-glass")
        block = find_material_block(lines, glass, material_name)
        if block is None:
            block = create_material_block(lines, glass, material_name, [f"{field_kdl} 0.0"])
        set_leaf_value(lines, block, field_kdl, format_float(bounded_number(raw_value, 0, 1000)))
        return "".join(lines)

    if field.startswith("blur."):
        name = field.split(".", 1)[1]
        blur = find_top_level_block(lines, "blur")
        if name == "enabled":
            set_blur_enabled(lines, parse_bool(raw_value))
        elif name in {"passes", "offset"}:
            maximum = 100 if name == "offset" else 255
            set_leaf_value(lines, blur, name, format_number(bounded_number(raw_value, 0, maximum)))
        elif name in {"noise", "saturation"}:
            set_leaf_value(lines, blur, name, format_float(bounded_number(raw_value, 0, 1000)))
        else:
            raise KdlEditError(f"unsupported blur field: {field}")
        return "".join(lines)

    if field.startswith("input."):
        parts = field.split(".")
        if len(parts) != 3:
            raise KdlEditError(f"unsupported input field: {field}")
        section, key_raw = parts[1], parts[2]
        key_kdl = key_raw.replace("_", "-")
        input_block = find_top_level_block(lines, "input")
        child = find_child_block(lines, input_block[0], input_block[1], section)
        if child is None:
            child = create_child_block(lines, input_block, section, [])
        if key_raw in INPUT_KEYBOARD_FLAGS or (section == "touchpad" and key_raw in ("tap", "natural_scroll", "dwt")):
            set_flag_in_block(lines, child, key_kdl, parse_bool(raw_value))
        elif section == "keyboard" and key_raw == "repeat_rate":
            set_leaf_value(lines, child, key_kdl, format_number(bounded_number(raw_value, 0, 255)))
        elif section == "keyboard" and key_raw == "repeat_delay":
            set_leaf_value(lines, child, key_kdl, format_number(bounded_number(raw_value, 0, 65535)))
        elif section == "touchpad" and key_raw == "accel_speed":
            set_leaf_value(lines, child, key_kdl, format_float(bounded_number(raw_value, -1, 1)))
        else:
            raise KdlEditError(f"unsupported input field: {field}")
        return "".join(lines)

    if field.startswith("animations."):
        parts = field.split(".")
        if len(parts) != 3:
            raise KdlEditError(f"unsupported animations field: {field}")
        action_raw, param_raw = parts[1], parts[2]
        action_kdl = action_raw.replace("_", "-")
        param_kdl = param_raw.replace("_", "-")
        if action_kdl not in ANIM_ACTIONS or param_kdl not in ANIM_SPRING_PARAMS:
            raise KdlEditError(f"unsupported animations field: {field}")
        anim = find_top_level_block(lines, "animations")
        if param_kdl == "damping-ratio":
            value = bounded_number(raw_value, 0.1, 10)
        elif param_kdl == "stiffness":
            value = bounded_number(raw_value, 1, 100000)
        else:
            value = bounded_number(raw_value, 0.00001, 0.1)
        set_anim_spring(lines, anim, action_kdl, param_kdl, value)
        return "".join(lines)

    raise KdlEditError(f"unsupported field: {field}")


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
    json_out({
        "ok": True,
        "config": str(config_path),
        "layout": read_layout_text(text),
        "glass": read_glass_text(text),
        "blur": read_blur_text(text),
        "input": read_input_text(text),
        "animations": read_animations_text(text),
        "binds": read_binds_text(text),
    })


def write_command(args: argparse.Namespace) -> None:
    config_path = Path(args.config).expanduser()
    text = config_path.read_text(encoding="utf-8")
    updated = update_field(text, args.field, args.value)
    changed = updated != text
    if changed:
        atomic_write(config_path, updated, args.niri_bin, args.skip_guardrails)
    json_out({
        "ok": True,
        "changed": changed,
        "config": str(config_path),
        "layout": read_layout_text(updated),
        "glass": read_glass_text(updated),
        "blur": read_blur_text(updated),
        "input": read_input_text(updated),
        "animations": read_animations_text(updated),
        "binds": read_binds_text(updated),
    })


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
