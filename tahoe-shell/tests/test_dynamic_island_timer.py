#!/usr/bin/env python3
"""T20: single Timer owner, scene, IPC, click-action, completion priority."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
TIMER = SHELL / "services" / "IslandTimer.qml"
ISLAND = SHELL / "services" / "DynamicIsland.qml"
REDUCER = SHELL / "services" / "DynamicIslandReducer.js"
CONTENT = SHELL / "components" / "DynamicIslandContent.qml"
VIEW = SHELL / "components" / "DynamicIslandTimerView.qml"
SHELL_QML = SHELL / "shell.qml"
SETTINGS = SHELL / "services" / "DesktopSettings.qml"
PAGE = SHELL / "components" / "settings" / "pages" / "DynamicIslandPage.qml"


def _read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


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


class DynamicIslandTimerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.timer = _read(TIMER)
        cls.island = _read(ISLAND)
        cls.reducer = _read(REDUCER)
        cls.content = _read(CONTENT)
        cls.view = _read(VIEW)
        cls.shell = _read(SHELL_QML)
        cls.settings = _read(SETTINGS)
        cls.page = _read(PAGE)

    def test_single_timer_owner_file(self) -> None:
        self.assertTrue(TIMER.is_file())
        self.assertIn("ElapsedTimer", self.timer)
        self.assertIn("function start", self.timer)
        self.assertIn("function pause", self.timer)
        self.assertIn("function resume", self.timer)
        self.assertIn("function cancel", self.timer)
        # No wall-clock countdown.
        code = re.sub(r"//[^\n]*", "", self.timer)
        self.assertNotIn("Date.now", code)
        self.assertNotIn("new Date", code)
        # Reload policy documented: no persistence.
        self.assertIn("do NOT restore", self.timer)
        self.assertIn("No FileView", self.timer)

    def test_validation_and_repeat_start(self) -> None:
        body = _function_body(self.timer, "start")
        self.assertIn("sec <= 0", body)
        self.assertIn("return false", body)
        # Repeated start replaces.
        self.assertIn("durationSec = sec", body)

    def test_suspend_pauses_without_wall_clock(self) -> None:
        self.assertIn("ApplicationSuspended", self.timer)
        self.assertIn("pauseInternal", self.timer)
        self.assertIn("resumeInternal", self.timer)
        self.assertIn("pausedBySession", self.timer)

    def test_display_timer_only_for_ui(self) -> None:
        self.assertIn("displayPulse", self.timer)
        self.assertIn("interval: 250", self.timer)
        self.assertIn("mono.elapsed", self.timer)

    def test_reducer_timer_states_and_priority(self) -> None:
        self.assertIn('"resting_timer"', self.reducer)
        self.assertIn('"expanded_timer"', self.reducer)
        self.assertIn('"transient_timer_complete"', self.reducer)
        self.assertIn("timer_completion", self.reducer)
        self.assertIn("SHOW_TIMER_COMPLETION", self.reducer)
        self.assertIn("SHOW_TIMER_EXPANDED", self.reducer)

    def test_island_subscribes_not_owns_countdown(self) -> None:
        self.assertIn("property var timerService", self.island)
        self.assertIn("function timerStart", self.island)
        self.assertIn("handleTimerCompleted", self.island)
        # No second ElapsedTimer in island.
        self.assertNotIn("ElapsedTimer", self.island)
        code = re.sub(r"//[^\n]*", "", self.island)
        self.assertNotIn("Date.now", code)

    def test_ipc_four_functions(self) -> None:
        self.assertIn("dynamicIslandTimerStart", self.shell)
        self.assertIn("dynamicIslandTimerPause", self.shell)
        self.assertIn("dynamicIslandTimerResume", self.shell)
        self.assertIn("dynamicIslandTimerCancel", self.shell)
        # Same tahoe IpcHandler target, not a second target name.
        self.assertIn("timerService: islandTimer", self.shell)

    def test_click_action_timer(self) -> None:
        self.assertIn('"timer"', self.settings)
        self.assertIn("计时器", self.settings)
        self.assertIn('value: "timer"', self.page)
        body = re.search(r'case "timer":([\s\S]*?)break;', self.island)
        self.assertIsNotNone(body)
        text = body.group(1)
        self.assertIn("showTimerExpanded", text)
        self.assertIn("showTimerSetupDefault", text)


    def test_inactive_pauses(self) -> None:
        self.assertIn("ApplicationInactive", self.timer)
        self.assertIn("ApplicationSuspended", self.timer)

    def test_completion_yields_to_notification(self) -> None:
        self.assertIn("queueTimerCompletion", self.reducer)
        self.assertIn("PRIORITY.timer_completion", self.reducer)
        self.assertIn("blocksCandidate", self.reducer)
        self.assertIn("pendingTimerCompletion", self.island)
        self.assertIn("maybeRestoreTimerPresentation", self.island)
        # Queue drain must not re-dispatch while still blocked (no stack blowup).
        body = _function_body(self.island, "maybeShowPendingTimerCompletion")
        self.assertIn("blocksCandidate", body)
        self.assertIn("return;", body)
        self.assertIn("handleTimerCompleted", body)

    def test_osd_return_allows_expanded_timer(self) -> None:
        self.assertIn('returnState !== "expanded_media" && returnState !== "expanded_timer"', self.island)

    def test_timer_view_compact_and_expanded(self) -> None:
        self.assertIn("DynamicIslandTimerView", self.content)
        self.assertIn("remainingLabel", self.view)
        self.assertIn("font.pixelSize: 30", self.view)
        self.assertIn("pauseResumeRequested", self.view)
        self.assertIn("cancelRequested", self.view)
        self.assertNotIn("Date.now", self.view)

    def test_timer_progress_fill_is_monochrome_not_accent(self) -> None:
        # Timer rails share islandProgressFill; accent is not used for bar paint.
        self.assertIn("progressFillColor", self.view)
        self.assertIn("progressFillColor: root.progressFillColor", self.content)
        fills = re.findall(r"color:\s*root\.(accentColor|progressFillColor)", self.view)
        self.assertIn("progressFillColor", fills)
        # Progress fill rectangles must not use accent.
        for m in re.finditer(
            r"width:\s*parent\.width\s*\*\s*root\.safeProgress[\s\S]{0,120}?color:\s*([^\n]+)",
            self.view,
        ):
            self.assertIn("progressFillColor", m.group(1))
            self.assertNotIn("accentColor", m.group(1))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
