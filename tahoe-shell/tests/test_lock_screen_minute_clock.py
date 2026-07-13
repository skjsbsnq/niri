#!/usr/bin/env python3
"""Task 22: LockScreen HH:mm clock must update on minute boundaries, not every second.

Root waste (old code):
  - Timer { interval: 1000; running: true; repeat: true; onTriggered: now = new Date() }
  - Display is only Qt.formatDateTime(now, "HH:mm") — second-resolution poll is pure waste
  - ~3600 Date allocations per idle lock hour for a display that changes 60 times

Fix contract:
  - Single Timer aligned to next minute edge (msecsToNextMinute)
  - On fire: set now, recompute interval for following edge
  - lock() / ApplicationActive / surface completed re-sync wall time (wake/show)
  - No second parallel Timer; no 1s standing poll
  - Date line still reads the same clockText.now owner

Regression strategy:
  1. Static contract extraction from LockScreen.qml
  2. Budget model: 1s poll vs minute-edge ticks per hour
  3. Interval math for mid-minute and minute-edge cases
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
LOCK_SCREEN = SHELL_ROOT / "components" / "LockScreen.qml"


def _timer_block(src: str, timer_id: str) -> str:
    m = re.search(rf"Timer\s*\{{\s*id:\s*{re.escape(timer_id)}\b", src)
    if not m:
        return ""
    start = m.start()
    depth = 0
    i = start
    begun = False
    while i < len(src):
        if src[i] == "{":
            depth += 1
            begun = True
        elif src[i] == "}":
            depth -= 1
            if begun and depth == 0:
                return src[start : i + 1]
        i += 1
    return ""


def _extract_function_body(src: str, name: str) -> str:
    m = re.search(rf"function\s+{re.escape(name)}\s*\([^)]*\)\s*\{{", src)
    if not m:
        return ""
    start = m.end()
    depth = 1
    i = start
    while i < len(src) and depth:
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return src[start : i - 1]


@dataclass(frozen=True)
class LockMinuteClockContract:
    no_1s_standing_poll: bool
    has_msecs_to_next_minute: bool
    timer_uses_minute_alignment: bool
    timer_rearms_interval_on_trigger: bool
    single_minute_timer: bool
    lock_syncs_clock: bool
    application_active_resync: bool
    hhmm_format_only_display: bool
    single_now_owner: bool

    @property
    def complete(self) -> bool:
        return all(getattr(self, name) for name in self.__annotations__)


def extract_contract(src: str) -> LockMinuteClockContract:
    timer = _timer_block(src, "minuteTimer")
    timers = re.findall(r"Timer\s*\{\s*id:\s*(\w+)", src)
    lock_body = _extract_function_body(src, "lock")
    msecs_body = _extract_function_body(src, "msecsToNextMinute")
    sync_body = _extract_function_body(src, "syncLockClock")

    standing_1s = bool(
        re.search(
            r"id:\s*minuteTimer[\s\S]{0,200}?interval:\s*1000\b",
            src,
        )
    ) or bool(
        re.search(
            r"interval:\s*1000\s*\n\s*running:\s*true\s*\n\s*repeat:\s*true",
            src,
        )
    )

    return LockMinuteClockContract(
        no_1s_standing_poll=not standing_1s
        and not re.search(r"interval:\s*1000\b", timer),
        has_msecs_to_next_minute=bool(
            re.search(r"function\s+msecsToNextMinute\s*\(", src)
            and re.search(r"60000", msecs_body)
            and re.search(r"getSeconds|getMilliseconds", msecs_body)
        ),
        timer_uses_minute_alignment=bool(
            re.search(r"msecsToNextMinute", timer)
            and re.search(r"interval:", timer)
        ),
        timer_rearms_interval_on_trigger=bool(
            re.search(r"onTriggered", timer)
            and re.search(r"msecsToNextMinute", timer)
            and (
                re.search(r"interval\s*=", timer)
                or re.search(r"restart\s*\(", timer)
            )
        ),
        single_minute_timer=timers.count("minuteTimer") == 1
        and len([t for t in timers if "minute" in t.lower() or "clock" in t.lower()])
        == 1,
        lock_syncs_clock=bool(
            re.search(r"syncLockClock", lock_body)
            or re.search(r"clockText\.now\s*=\s*new Date", lock_body)
        ),
        application_active_resync=bool(
            re.search(r"Qt\.application", src)
            and re.search(r"ApplicationActive", src)
            and re.search(r"syncLockClock", src)
        ),
        hhmm_format_only_display=bool(
            re.search(r'formatDateTime\([^,]+,\s*"HH:mm"\)', src)
        ),
        single_now_owner=bool(
            re.search(r"property\s+date\s+clockNow\b", src)
        )
        and src.count("property date clockNow") == 1
        and bool(sync_body)
        and not re.search(r"property\s+date\s+now\b", src),
    )


def msecs_to_next_minute(seconds: int, milliseconds: int) -> int:
    """Mirror LockScreen.msecsToNextMinute math for unit checks."""
    return max(250, 60000 - (seconds * 1000 + milliseconds))


class MinuteClockBudgetSim:
    def __init__(self, interval_ms: int | None, minute_edge: bool = False) -> None:
        self.interval_ms = interval_ms
        self.minute_edge = minute_edge
        self.ticks = 0
        self.t = 0

    def advance_idle_ms(self, ms: int, start_offset_ms: int = 0) -> None:
        """Advance wall time; count timer fires.

        start_offset_ms: ms into the current minute when the sim starts
        (only used for minute_edge mode).
        """
        end = self.t + ms
        if self.interval_ms is not None:
            while self.t + self.interval_ms <= end:
                self.t += self.interval_ms
                self.ticks += 1
            self.t = end
            return
        if self.minute_edge:
            # First fire at end of current partial minute, then every 60000.
            next_fire = self.t + (60000 - (start_offset_ms % 60000))
            if next_fire == self.t:
                next_fire += 60000
            while next_fire <= end:
                self.ticks += 1
                next_fire += 60000
            self.t = end
        else:
            self.t = end


class LockScreenMinuteClockTests(unittest.TestCase):
    def test_source_contract_is_complete(self) -> None:
        contract = extract_contract(LOCK_SCREEN.read_text(encoding="utf-8"))
        missing = [
            name
            for name in LockMinuteClockContract.__annotations__
            if not getattr(contract, name)
        ]
        self.assertEqual(
            missing,
            [],
            f"lock minute-clock contract incomplete: {missing}",
        )

    def test_old_1s_poll_is_3600_per_idle_hour(self) -> None:
        old = MinuteClockBudgetSim(interval_ms=1000)
        old.advance_idle_ms(3_600_000)
        self.assertEqual(old.ticks, 3600)

    def test_minute_edge_idle_hour_is_about_60(self) -> None:
        # Start 30s into a minute → first edge in 30s, then 59 more ≈ 60.
        fixed = MinuteClockBudgetSim(interval_ms=None, minute_edge=True)
        fixed.advance_idle_ms(3_600_000, start_offset_ms=30_000)
        self.assertEqual(fixed.ticks, 60)
        self.assertLess(fixed.ticks * 20, 3600)

    def test_msecs_to_next_minute_mid_minute(self) -> None:
        # 12:34:25.500 → 34500 ms to next minute
        self.assertEqual(msecs_to_next_minute(25, 500), 34500)

    def test_msecs_to_next_minute_near_edge_has_floor(self) -> None:
        # Exactly on edge → full minute; sub-250ms remainder is floored to 250.
        self.assertEqual(msecs_to_next_minute(0, 0), 60000)
        self.assertEqual(msecs_to_next_minute(59, 900), 250)
        self.assertEqual(msecs_to_next_minute(59, 0), 1000)

    def test_no_interval_1000_on_minute_timer(self) -> None:
        src = LOCK_SCREEN.read_text(encoding="utf-8")
        timer = _timer_block(src, "minuteTimer")
        self.assertNotRegex(timer, r"interval:\s*1000\b")
        self.assertIn("msecsToNextMinute", timer)

    def test_single_timer_in_lock_screen(self) -> None:
        src = LOCK_SCREEN.read_text(encoding="utf-8")
        # Task 22: only one Timer (minuteTimer); no parallel second clock Timer.
        self.assertEqual(len(re.findall(r"\bTimer\s*\{", src)), 1)

    def test_hhmm_display_still_present(self) -> None:
        src = LOCK_SCREEN.read_text(encoding="utf-8")
        self.assertIn('"HH:mm"', src)
        self.assertIn("clockText", src)


if __name__ == "__main__":
    unittest.main()
