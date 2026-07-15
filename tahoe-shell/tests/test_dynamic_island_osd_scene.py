#!/usr/bin/env python3
"""T13: V2 OSD scene — horizontal bar, no ring, presentation clamp."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
OSD = SHELL_ROOT / "components" / "DynamicIslandOsdView.qml"
CONTENT = SHELL_ROOT / "components" / "DynamicIslandContent.qml"
ISLAND = SHELL_ROOT / "services" / "DynamicIsland.qml"
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _function_body(src: str, name: str) -> str:
    m = re.search(rf"function\s+{re.escape(name)}\s*\([^)]*\)\s*\{{", src)
    if not m:
        return ""
    start = m.end()
    depth = 1
    i = start
    while i < len(src) and depth:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
        i += 1
    return src[start : i - 1]


class DynamicIslandOsdSceneTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.osd = _read(OSD)
        cls.content = _read(CONTENT)
        cls.island = _read(ISLAND)
        cls.overlay = _read(OVERLAY)

    def test_osd_view_layout_contract(self) -> None:
        self.assertIn("TahoeSymbol", self.osd)
        self.assertIn("size: 20", self.osd)
        self.assertIn("width: 118", self.osd)  # horizontal bar fits 230 mid-band
        self.assertIn("height: 6", self.osd)
        self.assertIn("barProgress", self.osd)
        self.assertIn("clampedProgress", self.osd)
        self.assertIn("font.letterSpacing: 0", self.osd)
        # No ring / Canvas.
        self.assertNotIn("Canvas", self.osd)
        self.assertNotIn("arc(", self.osd)

    def test_muted_is_neutral_not_danger_red(self) -> None:
        self.assertIn('root.muted ? 0 : root.clampedProgress', self.osd)
        # Muted fill stays neutral white alpha, not statusAttention/red.
        self.assertIn('#70ffffff', self.osd)
        self.assertNotIn("statusAttention", self.osd)
        self.assertNotIn("#ff453a", self.osd)
        self.assertNotIn("#ff3b30", self.osd)

    def test_content_hosts_osd_view_without_ring(self) -> None:
        self.assertIn("DynamicIslandOsdView", self.content)
        self.assertIn("osdSceneVisible", self.content)
        self.assertIn("osdMuted", self.content)
        self.assertNotIn("showOsRing", self.content)
        self.assertNotIn("osdRing", self.content)
        # Canvas may exist elsewhere later; OSD path must not paint a ring.
        self.assertNotIn("id: osdRing", self.content)
        # Progress opacity is scene-level only (not progress-driven re-enter).
        self.assertIn("opacity: root.osdSceneVisible ? 1 : 0", self.content)
        # No locale string probe for muted.
        self.assertNotIn('displayText === "静音"', self.content)

    def test_service_exposes_transient_osd_muted(self) -> None:
        self.assertIn("transientOsdMuted", self.island)
        show = _function_body(self.island, "showTransientOsdWithIcon")
        self.assertIn("osdMuted", show)
        present = _function_body(self.island, "presentOsdEntry")
        compact = re.sub(r"\s+", "", present)
        self.assertIn("volumeValue,muted)", compact)
        self.assertIn(',false);', compact)

    def test_progress_bar_has_width_behavior_only(self) -> None:
        self.assertIn("Behavior on width", self.osd)
        self.assertIn("overlayProgressDuration", self.osd)
        # OsdView itself should not Behavior on opacity (host does once).
        self.assertNotIn("Behavior on opacity", self.osd)

    def test_service_clamps_and_formats_value(self) -> None:
        present = _function_body(self.island, "presentOsdEntry")
        show = _function_body(self.island, "showTransientOsdWithIcon")
        self.assertIn("Math.max(0, Math.min(1", present)
        self.assertIn("静音", present)
        self.assertIn("亮度", present)
        self.assertIn("volumeValue", present)
        self.assertIn("isFinite", show)
        self.assertIn("valueText", show)

    def test_brightness_zero_path_still_present(self) -> None:
        body = _function_body(self.island, "handleBrightnessChange")
        self.assertIn("Math.max(0, Math.min(1, brightnessSample))", body)
        self.assertIn('"kind": "brightness"', body)
        present = _function_body(self.island, "presentOsdEntry")
        self.assertIn("brightnessProgress", present)

    def test_volume_muted_forces_zero_progress(self) -> None:
        present = _function_body(self.island, "presentOsdEntry")
        self.assertIn("muted ? 0", present)
        sync = _function_body(self.island, "syncVolumeOsdFromControls")
        self.assertIn('"progress": muted ? 0 : volume', sync)

    def test_overlay_forwards_accent(self) -> None:
        self.assertIn("accentColor", self.overlay)
        self.assertIn("Theme.accent", self.overlay)
        self.assertIn("darkMode: root.darkMode", self.overlay)

    def test_no_pipewire_or_backlight_in_osd_view(self) -> None:
        for needle in ("PipeWire", "brightnessctl", "backlight", "pw-cli"):
            self.assertNotIn(needle, self.osd)
            self.assertNotIn(needle, self.content)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
