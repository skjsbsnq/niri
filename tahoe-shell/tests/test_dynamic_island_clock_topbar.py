#!/usr/bin/env python3
"""T12: Resting clock scene, TopBar plain-time fallback, chip removal."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
CONTENT = SHELL_ROOT / "components" / "DynamicIslandContent.qml"
CLOCK = SHELL_ROOT / "components" / "DynamicIslandRestingClockView.qml"
CHIP = SHELL_ROOT / "components" / "DynamicIslandChip.qml"
TOPBAR = SHELL_ROOT / "components" / "TopBar.qml"
ISLAND = SHELL_ROOT / "services" / "DynamicIsland.qml"
MOTION = SHELL_ROOT / "components" / "DynamicIslandMotion.js"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _function_body(src: str, name: str) -> str:
    m = re.search(rf"function\s+{re.escape(name)}\s*\{{", src)
    if not m:
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


class DynamicIslandClockTopbarTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.overlay = _read(OVERLAY)
        cls.content = _read(CONTENT)
        cls.clock = _read(CLOCK)
        cls.topbar = _read(TOPBAR)
        cls.island = _read(ISLAND)
        cls.motion = _read(MOTION)

    def test_chip_file_deleted(self) -> None:
        self.assertFalse(CHIP.is_file(), "DynamicIslandChip.qml must be deleted in T12")

    def test_no_chip_production_references(self) -> None:
        self.assertNotIn("DynamicIslandChip", self.topbar)
        self.assertNotIn("DynamicIslandChip", self.overlay)
        self.assertNotIn("DynamicIslandChip", self.content)

    def test_resting_clock_view_layout(self) -> None:
        self.assertIn("weekdayText", self.clock)
        self.assertIn("timeText", self.clock)
        self.assertIn("font.letterSpacing: 0", self.clock)
        self.assertIn("font.weight: Font.DemiBold", self.clock)
        self.assertIn("contentWidth", self.clock)
        # Weekday is secondary; time is primary.
        self.assertIn("textSecondary", self.clock)
        self.assertIn("textPrimary", self.clock)

    def test_content_hosts_resting_clock(self) -> None:
        self.assertIn("DynamicIslandRestingClockView", self.content)
        self.assertIn("clockWeekdayText", self.content)
        self.assertIn("clockTimeText", self.content)
        self.assertIn("restingClockContentWidth", self.content)
        self.assertIn("restingClockActive", self.content)

    def test_service_splits_clock_labels(self) -> None:
        self.assertIn("clockWeekdayText", self.island)
        self.assertIn("clockTimeText", self.island)
        self.assertIn("formatClockWeekday", self.island)
        self.assertIn("formatClockTime", self.island)
        weekday = _function_body(self.island, "formatClockWeekday")
        time_body = _function_body(self.island, "formatClockTime")
        combined = _function_body(self.island, "timeText")
        self.assertIn('"ddd"', weekday)
        self.assertIn('"HH:mm"', time_body)
        # Combined plain text for TopBar / IPC still available.
        self.assertIn("formatClockWeekday", combined)
        self.assertIn("formatClockTime", combined)
        # Single now owner (no second Timer for clock).
        self.assertEqual(self.island.count("property date now:"), 1)

    def test_overlay_content_driven_clock_width(self) -> None:
        width_body = _function_body(self.overlay, "widthForState")
        self.assertIn("restingClockTargetWidth", width_body)
        target = _function_body(self.overlay, "restingClockTargetWidth")
        self.assertIn("v2ClockWidthMin", target)
        self.assertIn("v2ClockWidthMax", target)
        self.assertIn("restingClockContentWidth", target)
        self.assertIn("clockWeekdayText", self.overlay)
        self.assertIn("clockTimeText", self.overlay)

    def test_topbar_plain_text_fallback(self) -> None:
        self.assertIn("topbarTimeFallback", self.topbar)
        self.assertIn(
            "showTopbarTimeFallback: !dynamicIslandEnabled || !dynamicIslandHideTopbarTime",
            self.topbar,
        )
        self.assertIn("fallbackTimeText", self.topbar)
        # Ordinary Text, not a chip surface / soft shadow.
        self.assertIn("font.pixelSize: 13", self.topbar)
        self.assertNotIn("softShadow", self.topbar)
        # Click/hover compatibility when island enabled but Overlay does not own resting.
        self.assertIn("handleChipClick", self.topbar)
        self.assertIn("chipInteractive", self.topbar)
        self.assertIn("requestHoverExpand", self.topbar)
        # Expand/collapse pair (parity with Overlay hover lifecycle).
        self.assertIn("requestHoverCollapse", self.topbar)
        self.assertIn("hoverCollapseDelayMs", self.topbar)

    def test_center_reserve_covers_max_compact_media(self) -> None:
        self.assertIn(
            "centerReserveWidth: IslandMotion.v2CompactMediaWidthMax",
            self.topbar,
        )
        # Legacy thrash-prone fixed 168/184 gone.
        self.assertNotIn("root.width < 1500 ? 168 : 184", self.topbar)
        self.assertIn("var v2CompactMediaWidthMax = 224", self.motion)

    def test_enabled_hide_topbar_time_truth_table(self) -> None:
        # enabled + hideTopbarTime → Overlay owns resting; TopBar hides time.
        def show_fallback(enabled: bool, hide: bool) -> bool:
            return (not enabled) or (not hide)

        self.assertFalse(show_fallback(True, True))
        self.assertTrue(show_fallback(True, False))  # legacy hide=false
        self.assertTrue(show_fallback(False, True))  # disabled always shows time
        self.assertTrue(show_fallback(False, False))

    def test_no_show_v2_clock_flag(self) -> None:
        for src in (self.topbar, self.overlay, self.island, self.content):
            self.assertNotIn("showV2Clock", src)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
