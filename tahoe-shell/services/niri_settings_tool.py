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
MANAGED_BEGIN_RE = re.compile(r"^\s*//\s*tahoe-managed:\s*begin\s+([A-Za-z0-9_-]+)\s*$")
MANAGED_END_RE = re.compile(r"^\s*//\s*tahoe-managed:\s*end\s+([A-Za-z0-9_-]+)\s*$")


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


def find_top_level_blocks(lines: list[str], name: str) -> list[tuple[int, int]]:
    blocks: list[tuple[int, int]] = []
    start_re = re.compile(rf"^\s*{re.escape(name)}\b[^\n{{]*\{{\s*$")
    depth = 0
    index = 0
    while index < len(lines):
        body = uncommented_body(lines[index])
        if depth == 0 and start_re.match(body):
            local_depth = 0
            for end in range(index, len(lines)):
                local_depth += brace_delta(lines[end])
                if local_depth == 0:
                    blocks.append((index, end))
                    index = end + 1
                    break
            else:
                raise KdlEditError(f"unterminated top-level {name} block")
            continue
        depth += brace_delta(lines[index])
        index += 1
    return blocks


def previous_content_line(lines: list[str], index: int) -> tuple[int, str] | None:
    for cursor in range(index - 1, -1, -1):
        if lines[cursor].strip():
            return cursor, lines[cursor]
    return None


def next_content_line(lines: list[str], index: int) -> tuple[int, str] | None:
    for cursor in range(index + 1, len(lines)):
        if lines[cursor].strip():
            return cursor, lines[cursor]
    return None


def managed_block_for_field(field: str) -> str:
    if field.startswith("layout."):
        return "layout"
    if field.startswith("glass."):
        return "tahoe-glass"
    if field.startswith("blur."):
        return "blur"
    if field.startswith("input."):
        return "input"
    if field.startswith("animations."):
        return "animations"
    raise KdlEditError(f"unsupported field: {field}")


def managed_recovery_message(block_name: str) -> str:
    return (
        f"Recovery: re-deploy config/niri/tahoe-phase0.kdl or wrap the {block_name} block with "
        f"// tahoe-managed: begin {block_name} and // tahoe-managed: end {block_name}. "
        "The live config was not changed."
    )


def assert_managed_write_target(text: str, field: str) -> None:
    block_name = managed_block_for_field(field)
    lines = text.splitlines(True)
    blocks = find_top_level_blocks(lines, block_name)
    if len(blocks) != 1:
        raise KdlEditError(
            f"refusing to edit {field}: expected exactly one top-level {block_name} block, "
            f"found {len(blocks)}. {managed_recovery_message(block_name)}"
        )

    start, end = blocks[0]
    before = previous_content_line(lines, start)
    after = next_content_line(lines, end)
    begin_ok = bool(before and (match := MANAGED_BEGIN_RE.match(before[1])) and match.group(1) == block_name)
    end_ok = bool(after and (match := MANAGED_END_RE.match(after[1])) and match.group(1) == block_name)
    if not begin_ok or not end_ok:
        missing: list[str] = []
        if not begin_ok:
            missing.append(f"// tahoe-managed: begin {block_name}")
        if not end_ok:
            missing.append(f"// tahoe-managed: end {block_name}")
        raise KdlEditError(
            f"refusing to edit {field}: {block_name} block is not Tahoe-managed "
            f"(missing {' and '.join(missing)} near lines {start + 1}-{end + 1}). "
            f"{managed_recovery_message(block_name)}"
        )


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


def update_output_text(text: str, field: str, raw_value: str) -> str:
    if field != "output.scale":
        raise KdlEditError(f"unsupported output field: {field}")
    lines = text.splitlines(True)
    outputs = find_top_level_blocks(lines, "output")
    if len(outputs) != 1:
        raise KdlEditError(
            f"refusing to edit {field}: expected exactly one top-level output block, found {len(outputs)}. "
            "Edit config.kdl by hand for multi-monitor layouts."
        )
    set_leaf_value(lines, outputs[0], "scale", format_float(bounded_number(raw_value, 0.5, 4.0)))
    return "".join(lines)


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
# rewrite when the target param is unchanged. The bounded window-open/close
# lifecycle timing and scale are intentionally never touched by the GUI; the
# T04 window-minimize/window-restore genie nodes are likewise not profile-managed.
#
# T03: the layer-rule profile tables additionally manage the layer-open
# main-channel spring line (rewritten in place) and use `None` values to keep
# the open transform override channel absent, so the transform inherits the
# spring. Only `reduced` writes `transform-duration-ms 0` back in; switching
# away removes that leaf again, keeping profile round-trips byte-identical.

ANIM_ACTIONS = ["workspace-switch", "window-movement", "window-resize", "overview-open-close"]
ANIM_SPRING_PARAMS = ["damping-ratio", "stiffness", "epsilon"]
MOTION_PROFILE_NAMES = ["fast", "balanced", "liquid", "reduced"]
MOTION_PROFILE_SPRINGS = {
    "fast": {
        "workspace-switch": {"damping-ratio": 1.0, "stiffness": 860, "epsilon": 0.0001},
        "window-movement": {"damping-ratio": 0.9, "stiffness": 700, "epsilon": 0.001},
        "window-resize": {"damping-ratio": 1.0, "stiffness": 760, "epsilon": 0.0005},
        "overview-open-close": {"damping-ratio": 0.98, "stiffness": 820, "epsilon": 0.0005},
    },
    "balanced": {
        "workspace-switch": {"damping-ratio": 0.92, "stiffness": 420, "epsilon": 0.0001},
        "window-movement": {"damping-ratio": 0.8, "stiffness": 480, "epsilon": 0.001},
        "window-resize": {"damping-ratio": 0.96, "stiffness": 700, "epsilon": 0.0005},
        "overview-open-close": {"damping-ratio": 0.95, "stiffness": 760, "epsilon": 0.0005},
    },
    "liquid": {
        "workspace-switch": {"damping-ratio": 0.92, "stiffness": 680, "epsilon": 0.0001},
        "window-movement": {"damping-ratio": 0.82, "stiffness": 560, "epsilon": 0.001},
        "window-resize": {"damping-ratio": 0.92, "stiffness": 620, "epsilon": 0.0005},
        "overview-open-close": {"damping-ratio": 0.9, "stiffness": 680, "epsilon": 0.0005},
    },
    "reduced": {
        "workspace-switch": {"damping-ratio": 1.0, "stiffness": 1000, "epsilon": 0.001},
        "window-movement": {"damping-ratio": 1.0, "stiffness": 1000, "epsilon": 0.001},
        "window-resize": {"damping-ratio": 1.0, "stiffness": 1000, "epsilon": 0.001},
        "overview-open-close": {"damping-ratio": 1.0, "stiffness": 1000, "epsilon": 0.001},
    },
}
LAYER_PROFILE_GROUPS = {
    "control_center": ("tahoe-control-center",),
    "notification_center": ("tahoe-notification-center",),
    "left_sidebar": ("tahoe-left-sidebar",),
    "spotlight": ("tahoe-spotlight",),
    # T04-fix2 / T21: status popups and tray menus stay edge-reveal; app and
    # shell menus share one pop-slide layer-rule (pointer origin). Keep these
    # tuples equal to the namespace sets of their animation rules.
    "small_popup": (
        "tahoe-battery-popup",
        "tahoe-wifi-popup",
        "tahoe-fan-popup",
        "tahoe-clipboard-popup",
        "tahoe-tray-menu",
    ),
    "menu": (
        "tahoe-menu-popup",
        "tahoe-application-menu",
        "tahoe-process-menu",
        "tahoe-dock-app-menu",
        "tahoe-dock-window-menu",
    ),
    "toast": ("tahoe-notification-toast",),
}
LAYER_PHASES = ("layer-open", "layer-close")


def layer_phase(
    transform_ms: int,
    opacity_ms: int,
    opacity_key: str,
    opacity_value: float,
    opacity_curve: str | None = None,
) -> dict[str, int | float | str | dict[str, float] | None]:
    values: dict[str, int | float | str | dict[str, float] | None] = {
        "transform-duration-ms": transform_ms,
        "opacity-duration-ms": opacity_ms,
        opacity_key: opacity_value,
    }
    if opacity_curve is not None:
        values["opacity-curve"] = opacity_curve
    return values


def spring_phase(
    damping_ratio: float,
    stiffness: float,
    epsilon: float,
    opacity_ms: int,
    opacity_key: str,
    opacity_value: float,
    opacity_curve: str | None = None,
) -> dict[str, int | float | str | dict[str, float] | None]:
    """Phase whose main channel is a spring (T03 vocabulary).

    The transform override channel must stay ABSENT so it inherits the
    main-channel spring: `None` means "remove this leaf if present" for the
    writer and "this leaf must be absent" for profile detection. Only the
    `reduced` profile writes `transform-duration-ms 0` back in (its transform
    override wins over the inert spring line, which stays untouched).
    """
    values: dict[str, int | float | str | dict[str, float] | None] = {
        "spring": {
            "damping-ratio": damping_ratio,
            "stiffness": stiffness,
            "epsilon": epsilon,
        },
        "transform-duration-ms": None,
        "opacity-duration-ms": opacity_ms,
        opacity_key: opacity_value,
    }
    if opacity_curve is not None:
        values["opacity-curve"] = opacity_curve
    return values


MOTION_PROFILE_LAYERS = {
    "balanced": {
        "control_center": {
            "layer-open": spring_phase(0.85, 380, 0.0005, 110, "opacity-from", 0.84, "standard-decel"),
            "layer-close": {**layer_phase(210, 0, "opacity-to", 1.0), "opacity-curve": None},
        },
        "notification_center": {
            "layer-open": spring_phase(0.85, 380, 0.0005, 100, "opacity-from", 0.86, "standard-decel"),
            "layer-close": {**layer_phase(210, 0, "opacity-to", 1.0), "opacity-curve": None},
        },
        "left_sidebar": {
            "layer-open": spring_phase(0.85, 380, 0.0005, 0, "opacity-from", 1.0),
            "layer-close": layer_phase(180, 0, "opacity-to", 1.0),
        },
        "spotlight": {
            "layer-open": spring_phase(0.88, 500, 0.001, 120, "opacity-from", 0.0, "standard-decel"),
            "layer-close": layer_phase(110, 80, "opacity-to", 0.0, "emphasized-accel"),
        },
        "small_popup": {
            "layer-open": spring_phase(0.85, 380, 0.0005, 110, "opacity-from", 0.84, "standard-decel"),
            "layer-close": {**layer_phase(210, 0, "opacity-to", 1.0), "opacity-curve": None},
        },
        "menu": {
            "layer-open": spring_phase(0.88, 500, 0.001, 90, "opacity-from", 0.0, "standard-decel"),
            "layer-close": layer_phase(180, 180, "opacity-to", 0.0, "emphasized-accel"),
        },
        "toast": {
            "layer-open": spring_phase(0.8, 320, 0.0005, 100, "opacity-from", 0.75, "standard-decel"),
            "layer-close": layer_phase(110, 80, "opacity-to", 0.0, "emphasized-accel"),
        },
    },
    "fast": {
        "control_center": {
            "layer-open": spring_phase(0.9, 520, 0.0005, 80, "opacity-from", 0.84, "standard-decel"),
            "layer-close": {**layer_phase(140, 0, "opacity-to", 1.0), "opacity-curve": None},
        },
        "notification_center": {
            "layer-open": spring_phase(0.9, 520, 0.0005, 80, "opacity-from", 0.86, "standard-decel"),
            "layer-close": {**layer_phase(140, 0, "opacity-to", 1.0), "opacity-curve": None},
        },
        "left_sidebar": {
            "layer-open": spring_phase(0.9, 520, 0.0005, 0, "opacity-from", 1.0),
            "layer-close": layer_phase(140, 0, "opacity-to", 1.0),
        },
        "spotlight": {
            "layer-open": spring_phase(0.95, 750, 0.001, 80, "opacity-from", 0.0, "standard-decel"),
            "layer-close": layer_phase(90, 60, "opacity-to", 0.0, "emphasized-accel"),
        },
        "small_popup": {
            "layer-open": spring_phase(0.9, 520, 0.0005, 80, "opacity-from", 0.84, "standard-decel"),
            "layer-close": {**layer_phase(140, 0, "opacity-to", 1.0), "opacity-curve": None},
        },
        "menu": {
            "layer-open": spring_phase(0.95, 750, 0.001, 70, "opacity-from", 0.0, "standard-decel"),
            "layer-close": layer_phase(140, 140, "opacity-to", 0.0, "emphasized-accel"),
        },
        "toast": {
            "layer-open": spring_phase(0.85, 450, 0.0005, 80, "opacity-from", 0.75, "standard-decel"),
            "layer-close": layer_phase(90, 60, "opacity-to", 0.0, "emphasized-accel"),
        },
    },
    "liquid": {
        "control_center": {
            "layer-open": spring_phase(0.82, 300, 0.0005, 130, "opacity-from", 0.84, "standard-decel"),
            "layer-close": {**layer_phase(210, 0, "opacity-to", 1.0), "opacity-curve": None},
        },
        "notification_center": {
            "layer-open": spring_phase(0.82, 300, 0.0005, 130, "opacity-from", 0.86, "standard-decel"),
            "layer-close": {**layer_phase(210, 0, "opacity-to", 1.0), "opacity-curve": None},
        },
        "left_sidebar": {
            "layer-open": spring_phase(0.82, 300, 0.0005, 0, "opacity-from", 1.0),
            "layer-close": layer_phase(210, 0, "opacity-to", 1.0),
        },
        "spotlight": {
            "layer-open": spring_phase(0.82, 420, 0.001, 130, "opacity-from", 0.0, "standard-decel"),
            "layer-close": layer_phase(150, 90, "opacity-to", 0.0, "emphasized-accel"),
        },
        "small_popup": {
            "layer-open": spring_phase(0.82, 300, 0.0005, 130, "opacity-from", 0.84, "standard-decel"),
            "layer-close": {**layer_phase(210, 0, "opacity-to", 1.0), "opacity-curve": None},
        },
        "menu": {
            "layer-open": spring_phase(0.82, 420, 0.001, 110, "opacity-from", 0.0, "standard-decel"),
            "layer-close": layer_phase(210, 210, "opacity-to", 0.0, "emphasized-accel"),
        },
        "toast": {
            "layer-open": spring_phase(0.78, 260, 0.0005, 120, "opacity-from", 0.75, "standard-decel"),
            "layer-close": layer_phase(150, 90, "opacity-to", 0.0, "emphasized-accel"),
        },
    },
    "reduced": {
        "control_center": {
            "layer-open": layer_phase(0, 80, "opacity-from", 0.0, "standard-decel"),
            "layer-close": layer_phase(0, 60, "opacity-to", 0.0, "emphasized-accel"),
        },
        "notification_center": {
            "layer-open": layer_phase(0, 80, "opacity-from", 0.0, "standard-decel"),
            "layer-close": layer_phase(0, 60, "opacity-to", 0.0, "emphasized-accel"),
        },
        "left_sidebar": {
            "layer-open": layer_phase(0, 0, "opacity-from", 1.0),
            "layer-close": layer_phase(0, 0, "opacity-to", 1.0),
        },
        "spotlight": {
            "layer-open": layer_phase(0, 80, "opacity-from", 0.0, "standard-decel"),
            "layer-close": layer_phase(0, 60, "opacity-to", 0.0, "emphasized-accel"),
        },
        "small_popup": {
            "layer-open": layer_phase(0, 80, "opacity-from", 0.0, "standard-decel"),
            "layer-close": layer_phase(0, 60, "opacity-to", 0.0, "emphasized-accel"),
        },
        "menu": {
            "layer-open": layer_phase(0, 70, "opacity-from", 0.0, "standard-decel"),
            "layer-close": layer_phase(0, 60, "opacity-to", 0.0, "emphasized-accel"),
        },
        "toast": {
            "layer-open": layer_phase(0, 80, "opacity-from", 0.0, "standard-decel"),
            "layer-close": layer_phase(0, 60, "opacity-to", 0.0, "emphasized-accel"),
        },
    },
}


def build_writable_field_specs() -> dict[str, dict[str, str]]:
    rollback = (
        "guardrails + temporary file + fsync + niri validate + atomic replace; "
        "on validation/guardrail failure the live config is unchanged"
    )
    bool_validation = "parse_bool: 1/0, true/false, yes/no, on/off, enabled/disabled"
    specs: dict[str, dict[str, str]] = {}

    def add(
        field: str,
        kdl_path: str,
        range_text: str,
        validation: str,
        managed_block: str,
    ) -> None:
        specs[field] = {
            "field": field,
            "kdlPath": kdl_path,
            "range": range_text,
            "validation": validation,
            "managedBlock": managed_block,
            "rollback": rollback,
        }

    for field, path, range_text, validation in [
        ("layout.gaps", "layout.gaps", "0..65535", "bounded_number"),
        ("layout.focus_ring.enabled", "layout.focus-ring.on/off", "boolean", bool_validation),
        ("layout.border.enabled", "layout.border.on/off", "boolean", bool_validation),
        ("layout.shadow.enabled", "layout.shadow.on/off", "boolean", bool_validation),
        ("layout.shadow.softness", "layout.shadow.softness", "0..1024", "bounded_number"),
        ("layout.shadow.spread", "layout.shadow.spread", "-1024..1024", "bounded_number"),
        ("layout.shadow.offset_x", "layout.shadow.offset.x", "-65535..65535", "bounded_number"),
        ("layout.shadow.offset_y", "layout.shadow.offset.y", "-65535..65535", "bounded_number"),
        ("layout.snap_assist.enabled", "layout.snap-assist.on/off", "boolean", bool_validation),
        ("layout.snap_assist.threshold", "layout.snap-assist.threshold", "0..65535", "bounded_number"),
    ]:
        add(field, path, range_text, validation, "layout")

    for material in GLASS_MATERIAL_NAMES:
        for field_kdl in GLASS_MATERIAL_FIELDS:
            add(
                f"glass.{material}.{field_kdl.replace('-', '_')}",
                f'tahoe-glass.material["{material}"].{field_kdl}',
                "0..1000",
                "bounded_number; material and field are both whitelisted",
                "tahoe-glass",
            )

    for field, path, range_text, validation in [
        ("blur.enabled", "blur.on/off", "boolean", bool_validation),
        ("blur.passes", "blur.passes", "0..255", "bounded_number"),
        ("blur.offset", "blur.offset", "0..100", "bounded_number"),
        ("blur.noise", "blur.noise", "0..1000", "bounded_number"),
        ("blur.saturation", "blur.saturation", "0..1000", "bounded_number"),
    ]:
        add(field, path, range_text, validation, "blur")

    for field, path, range_text, validation in [
        ("input.keyboard.repeat_rate", "input.keyboard.repeat-rate", "0..255", "bounded_number"),
        ("input.keyboard.repeat_delay", "input.keyboard.repeat-delay", "0..65535", "bounded_number"),
        ("input.keyboard.numlock", "input.keyboard.numlock", "boolean", bool_validation),
        ("input.touchpad.tap", "input.touchpad.tap", "boolean", bool_validation),
        ("input.touchpad.natural_scroll", "input.touchpad.natural-scroll", "boolean", bool_validation),
        ("input.touchpad.dwt", "input.touchpad.dwt", "boolean", bool_validation),
        ("input.touchpad.accel_speed", "input.touchpad.accel-speed", "-1..1", "bounded_number"),
    ]:
        add(field, path, range_text, validation, "input")

    add(
        "output.scale",
        "output.<single-output>.scale",
        "0.5..4.0",
        "bounded_number; exactly one top-level output block is required",
        "single output block",
    )

    add(
        "animations.layer_animations_enabled",
        "tahoe layer-rule animations.layer-open/layer-close.off",
        "boolean",
        bool_validation,
        "animations + tahoe layer-rule animations",
    )

    add(
        "animations.profile",
        "animations + tahoe layer-rule animations",
        ", ".join(MOTION_PROFILE_NAMES),
        "motion profile name whitelist; applies a managed multi-field profile",
        "animations",
    )

    for action in ANIM_ACTIONS:
        action_field = action.replace("-", "_")
        for param in ANIM_SPRING_PARAMS:
            field_param = param.replace("-", "_")
            if param == "damping-ratio":
                range_text = "0.1..10"
            elif param == "stiffness":
                range_text = "1..100000"
            else:
                range_text = "0.00001..0.1"
            add(
                f"animations.{action_field}.{field_param}",
                f"animations.{action}.spring.{param}",
                range_text,
                "bounded_number; action and spring param are both whitelisted",
                "animations",
            )

    return specs


WRITABLE_FIELD_SPECS = build_writable_field_specs()


def writable_field_spec(field: str) -> dict[str, str]:
    try:
        return WRITABLE_FIELD_SPECS[field]
    except KeyError as exc:
        raise KdlEditError(f"unsupported field: {field}") from exc


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
    return {
        "actions": actions,
        "layerAnimationsEnabled": layer_animations_enabled_text(text),
        "profile": detect_motion_profile(text),
        "availableProfiles": MOTION_PROFILE_NAMES,
    }


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


def valid_motion_profile(raw_value: str) -> str:
    profile = str(raw_value).strip().lower()
    if profile not in MOTION_PROFILE_NAMES:
        raise KdlEditError(f"unsupported motion profile: {raw_value}")
    return profile


def layer_rule_namespaces(lines: list[str], block: tuple[int, int]) -> tuple[str, ...]:
    namespaces: list[str] = []
    for index in iter_depth_lines(lines, block[0], block[1], 1):
        body = uncommented_body(lines[index])
        match = re.match(r'^\s*match\s+namespace\s*=\s*"([^"]+)"\s*$', body)
        if not match:
            continue
        namespace = match.group(1)
        if namespace.startswith("^"):
            namespace = namespace[1:]
        if namespace.endswith("$"):
            namespace = namespace[:-1]
        namespaces.append(namespace)
    return tuple(namespaces)


def find_layer_rule_for_group(lines: list[str], group: str) -> tuple[int, int]:
    expected = LAYER_PROFILE_GROUPS[group]
    matches = [
        block
        for block in find_top_level_blocks(lines, "layer-rule")
        if layer_rule_namespaces(lines, block) == expected
        and find_child_block(lines, block[0], block[1], "animations") is not None
    ]
    if len(matches) != 1:
        raise KdlEditError(
            f"refusing profile write: expected exactly one layer-rule for {group}, found {len(matches)}"
        )
    return matches[0]


def find_layer_phase_block(lines: list[str], layer_rule: tuple[int, int], phase: str) -> tuple[int, int]:
    anim = find_child_block(lines, layer_rule[0], layer_rule[1], "animations")
    if anim is None:
        raise KdlEditError(f"layer-rule {layer_rule_namespaces(lines, layer_rule)} has no animations block")
    block = find_child_block(lines, anim[0], anim[1], phase)
    if block is None:
        raise KdlEditError(f"layer-rule {layer_rule_namespaces(lines, layer_rule)} has no {phase} block")
    return block


def phase_has_off(lines: list[str], block: tuple[int, int]) -> bool:
    return any(
        uncommented_body(lines[index]).strip() == "off"
        for index in iter_depth_lines(lines, block[0], block[1], 1)
    )


def set_phase_off(lines: list[str], block: tuple[int, int], disabled: bool) -> None:
    indices = [
        index
        for index in iter_depth_lines(lines, block[0], block[1], 1)
        if uncommented_body(lines[index]).strip() == "off"
    ]
    if disabled:
        if not indices:
            lines.insert(block[0] + 1, f"{block_child_indent(lines, block)}off\n")
        return
    for index in reversed(indices):
        del lines[index]


def layer_animations_enabled_text(text: str) -> bool:
    lines = text.splitlines(True)
    try:
        for group in LAYER_PROFILE_GROUPS:
            layer_rule = find_layer_rule_for_group(lines, group)
            for phase in LAYER_PHASES:
                if phase_has_off(lines, find_layer_phase_block(lines, layer_rule, phase)):
                    return False
    except KdlEditError:
        return False
    return True


def update_layer_animations_enabled_text(text: str, raw_value: str) -> str:
    enabled = parse_bool(raw_value)
    lines = text.splitlines(True)

    for group in LAYER_PROFILE_GROUPS:
        layer_rule = find_layer_rule_for_group(lines, group)
        for phase in LAYER_PHASES:
            find_layer_phase_block(lines, layer_rule, phase)

    for group in LAYER_PROFILE_GROUPS:
        for phase in LAYER_PHASES:
            layer_rule = find_layer_rule_for_group(lines, group)
            block = find_layer_phase_block(lines, layer_rule, phase)
            set_phase_off(lines, block, disabled=not enabled)

    return "".join(lines)


def phase_number(lines: list[str], block: tuple[int, int], key: str) -> float | None:
    node_re = re.compile(rf"^\s*{re.escape(key)}\b\s+(.+?)\s*$")
    for index in iter_depth_lines(lines, block[0], block[1], 1):
        body = uncommented_body(lines[index])
        if "{" in body:
            continue
        match = node_re.match(body)
        if match:
            return parse_number(match.group(1), default=float("nan"))
    return None


def phase_string(lines: list[str], block: tuple[int, int], key: str) -> str | None:
    node_re = re.compile(rf'^\s*{re.escape(key)}\b\s+"([^"]+)"\s*$')
    for index in iter_depth_lines(lines, block[0], block[1], 1):
        body = uncommented_body(lines[index])
        match = node_re.match(body)
        if match:
            return match.group(1)
    return None


def phase_leaf_index(lines: list[str], block: tuple[int, int], key: str) -> int | None:
    node_re = re.compile(rf"^\s*{re.escape(key)}\b\s+")
    for index in iter_depth_lines(lines, block[0], block[1], 1):
        body = uncommented_body(lines[index])
        if "{" in body:
            continue
        if node_re.match(body):
            return index
    return None


def remove_leaf(lines: list[str], block: tuple[int, int], name: str) -> None:
    index = phase_leaf_index(lines, block, name)
    if index is not None:
        del lines[index]


def phase_spring(lines: list[str], block: tuple[int, int]) -> dict[str, float] | None:
    for index in iter_depth_lines(lines, block[0], block[1], 1):
        body = uncommented_body(lines[index])
        if re.match(r"^\s*spring\b", body):
            return parse_spring_line(body)
    return None


def set_phase_spring(lines: list[str], block: tuple[int, int], vals: dict[str, float]) -> None:
    for index in iter_depth_lines(lines, block[0], block[1], 1):
        body = uncommented_body(lines[index])
        if not re.match(r"^\s*spring\b", body):
            continue
        current = parse_spring_line(body)
        if all(abs(current[param] - vals[param]) <= 1e-9 for param in ANIM_SPRING_PARAMS):
            return  # unchanged: preserve original token
        merged = dict(current)
        merged.update(vals)
        _, comment, newline = split_line_comment(lines[index])
        indent = leading_indent(lines[index])
        gap = " " if comment else ""
        lines[index] = f"{indent}{format_spring(merged)}{gap}{comment}{newline}"
        return
    indent = block_child_indent(lines, block)
    lines.insert(block[1], f"{indent}{format_spring(vals)}\n")


def format_layer_profile_value(value: int | float | str) -> str:
    if isinstance(value, str):
        return f'"{value}"'
    if isinstance(value, int):
        return str(value)
    return format_float(value)


def apply_layer_profile(lines: list[str], profile: str) -> None:
    # Re-find the rule and phase block for every key: `spring`/`None` writes can
    # insert or delete lines, which would leave previously computed block
    # bounds stale within the same profile application.
    for group, phase_values in MOTION_PROFILE_LAYERS[profile].items():
        for phase, values in phase_values.items():
            for key, value in values.items():
                layer_rule = find_layer_rule_for_group(lines, group)
                block = find_layer_phase_block(lines, layer_rule, phase)
                if key == "spring":
                    set_phase_spring(lines, block, value)
                elif value is None:
                    remove_leaf(lines, block, key)
                else:
                    set_leaf_value(lines, block, key, format_layer_profile_value(value))


def profile_springs_match(lines: list[str], anim: tuple[int, int], profile: str) -> bool:
    for action, expected in MOTION_PROFILE_SPRINGS[profile].items():
        block = find_child_block(lines, anim[0], anim[1], action)
        if block is None:
            return False
        actual: dict[str, float] | None = None
        for index in iter_depth_lines(lines, block[0], block[1], 2):
            body = uncommented_body(lines[index])
            if re.match(r"^\s*spring\b", body):
                actual = parse_spring_line(body)
                break
        if actual is None:
            return False
        for param, value in expected.items():
            if abs(actual[param] - value) > 1e-9:
                return False
    return True


def profile_layers_match(lines: list[str], profile: str) -> bool:
    try:
        for group, phase_values in MOTION_PROFILE_LAYERS[profile].items():
            layer_rule = find_layer_rule_for_group(lines, group)
            for phase, values in phase_values.items():
                block = find_layer_phase_block(lines, layer_rule, phase)
                for key, expected in values.items():
                    if key == "spring":
                        actual_spring = phase_spring(lines, block)
                        if actual_spring is None:
                            return False
                        for param, value in expected.items():
                            if abs(actual_spring[param] - value) > 1e-9:
                                return False
                    elif expected is None:
                        if phase_leaf_index(lines, block, key) is not None:
                            return False
                    elif isinstance(expected, str):
                        if phase_string(lines, block, key) != expected:
                            return False
                    else:
                        actual = phase_number(lines, block, key)
                        if actual is None or abs(actual - float(expected)) > 1e-9:
                            return False
        return True
    except KdlEditError:
        return False


def detect_motion_profile(text: str) -> str:
    lines = text.splitlines(True)
    anim = find_top_level_block_or_none(lines, "animations")
    if anim is None:
        return "custom"
    for profile in MOTION_PROFILE_NAMES:
        if profile_springs_match(lines, anim, profile) and profile_layers_match(lines, profile):
            return profile
    return "custom"


def update_motion_profile_text(text: str, raw_value: str) -> str:
    profile = valid_motion_profile(raw_value)
    lines = text.splitlines(True)
    anim = find_top_level_block(lines, "animations")

    for action, values in MOTION_PROFILE_SPRINGS[profile].items():
        for param, value in values.items():
            set_anim_spring(lines, anim, action, param, value)

    apply_layer_profile(lines, profile)
    return "".join(lines)


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
    writable_field_spec(field)

    if field.startswith("output."):
        return update_output_text(text, field, raw_value)

    assert_managed_write_target(text, field)

    if field.startswith("layout."):
        return update_layout_text(text, field, raw_value)

    lines = text.splitlines(True)

    if field.startswith("glass."):
        parts = field.split(".")
        if len(parts) != 3:
            raise KdlEditError(f"unsupported glass field: {field}")
        material_name, field_raw = parts[1], parts[2]
        field_kdl = field_raw.replace("_", "-")
        if material_name not in GLASS_MATERIAL_NAMES or field_kdl not in GLASS_MATERIAL_FIELDS:
            raise KdlEditError(f"unsupported glass field: {field}")
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
        if field == "animations.layer_animations_enabled":
            return update_layer_animations_enabled_text(text, raw_value)
        if field == "animations.profile":
            return update_motion_profile_text(text, raw_value)

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
    # Any uncommented variable-refresh-rate line is rejected (VRR stays off).
    active_vrr = re.findall(r"(?m)^[ \t]*variable-refresh-rate[^\n]*$", text)
    if active_vrr:
        raise KdlEditError(
            "guardrail failed: variable-refresh-rate must stay disabled (commented out or absent)"
        )
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
