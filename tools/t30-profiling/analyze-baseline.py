#!/usr/bin/env python3
"""T-30 baseline analysis: summarize Tracy traces + niri telemetry logs.

Usage: analyze-baseline.py <outdir> [scenario ...]
"""
import csv
import io
import json
import os
import re
import subprocess
import sys

CSVEXPORT = os.environ.get("TRACY_CSVEXPORT", "/tmp/tracy-csvexport-0131/tracy-csvexport")
KEY_ZONES = [
    "Niri::redraw",
    "Niri::redraw_queued_outputs",
    "FramebufferEffectElement::capture_framebuffer",
    "Blur::render",
    "Blur::prepare_textures",
    "TahoeGlass::render_region",
    "TahoeGlass::render_regions_for_layer",
    "ShaderRenderElement::draw",
    "ShadowRenderElement::draw",
    "update_xray",
]


def csvexport(trace, *args):
    out = subprocess.run([CSVEXPORT, *args, trace], capture_output=True, text=True)
    if out.returncode != 0:
        return None
    return list(csv.DictReader(io.StringIO(out.stdout)))


def parse_telemetry(path):
    rows = []
    if not os.path.exists(path):
        return rows
    for line in open(path, errors="replace"):
        if "frame telemetry" not in line or "enabled" in line:
            continue
        fields = {}
        body = line.split("frame telemetry ", 1)[1]
        for tok in re.findall(r'(\w+)=("[^"]*"|[^\s]+)', body):
            k, v = tok
            fields[k] = v.strip('"')
        rows.append(fields)
    return rows


def parse_lifecycle(path):
    rows = []
    if not os.path.exists(path):
        return rows
    for line in open(path, errors="replace"):
        if "lifecycle-diag 5s delta" not in line:
            continue
        m = re.search(r"redraw_all \+(\d+) redraw \+(\d+) tahoe_capture \+(\d+) fb_capture \+(\d+) blur \+(\d+)", line)
        if m:
            rows.append(tuple(int(x) for x in m.groups()))
    return rows


def zone_stats(rows):
    out = {}
    for r in rows:
        # csvexport does not quote zone names containing commas (Rust generic
        # type names); such rows are misaligned and must be skipped.
        if not r.get("counts", "").isdigit():
            continue
        out[r["name"]] = {
            "counts": int(r["counts"]),
            "mean_ms": float(r["mean_ns"]) / 1e6,
            "p50_ms": None,
            "max_ms": float(r["max_ns"]) / 1e6,
            "total_ms": float(r["total_ns"]) / 1e6,
        }
    return out


def main():
    outdir = sys.argv[1]
    scenarios = sys.argv[2:] or ["A-idle-1", "A-idle-2", "A-idle-3", "A-cursor", "B-dock", "C-island", "D-overview"]
    captures = os.path.join(outdir, "captures")
    logs = os.path.join(outdir, "logs")

    summary = {}
    for s in scenarios:
        trace = os.path.join(captures, f"{s}.tracy")
        entry = {"telemetry": parse_telemetry(os.path.join(logs, f"session-{s}.log")),
                 "lifecycle": parse_lifecycle(os.path.join(logs, f"session-{s}.log"))}
        if os.path.exists(trace):
            agg = csvexport(trace)
            entry["zones"] = zone_stats(agg or [])
            entry["key_zones"] = {}
            for kz in KEY_ZONES:
                rows = csvexport(trace, "-f", kz)
                if rows:
                    entry["key_zones"][kz] = zone_stats(rows).get(kz)
            # fb capture / blur timestamps for activity distribution
            entry["fb_capture_ts"] = [int(r["ns_since_start"]) for r in
                                      (csvexport(trace, "-u", "-f", "FramebufferEffectElement::capture_framebuffer") or [])
                                      if r["name"] == "FramebufferEffectElement::capture_framebuffer"]
            entry["redraw_ts"] = [int(r["ns_since_start"]) for r in
                                  (csvexport(trace, "-u", "-f", "Niri::redraw") or [])
                                  if r["name"] == "Niri::redraw"]
        summary[s] = entry

    print(json.dumps(summary, indent=1, default=str))


if __name__ == "__main__":
    main()
