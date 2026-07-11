"""T20: TaskSwitcher instant open + spring selection; WindowOverview flight motion."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class TaskOverviewMotionTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_task_switcher_instant_open_no_entrance_scale(self) -> None:
        text = self.read("components/TaskSwitcher.qml")
        # No entrance scale Behavior (macOS cmd+tab is instant).
        self.assertNotIn("Behavior on scale", text)
        self.assertNotIn("scale: root.open ? 1 : 0.98", text)
        # Instant visibility tied to open.
        self.assertIn("visible: open", text)
        self.assertIn("visible: root.open", text)
        # Selection frame spring + useSpring dual branch (Spotlight pattern).
        self.assertIn("property bool useSpring", text)
        self.assertIn("highlightSpring", text)
        self.assertIn("Motion.springSnappy", text)
        self.assertIn("syncSelectionHighlight", text)
        self.assertIn("root.useSpring && !Motion.reducedMotion", text)
        # Still uses shared thumbnail contract.
        self.assertIn("thumbnailProvider.requestThumbnails", text)
        self.assertIn("WindowPreviewFallback", text)

    def test_window_overview_flight_spring_and_cleanup(self) -> None:
        text = self.read("components/WindowOverview.qml")
        self.assertIn("property bool useSpring", text)
        self.assertIn("flightPhase", text)
        self.assertIn("flightOffsetForCard", text)
        self.assertIn("prepareEnter", text)
        self.assertIn("prepareLeave", text)
        self.assertIn("Motion.springPanel", text)
        self.assertIn("Motion.springSmooth", text)
        self.assertIn("leaveWatchdog", text)
        self.assertIn("enterWatchdog", text)
        # Content-layer transform flight, not glass region geometry spring.
        self.assertIn("flyTranslate", text)
        self.assertNotIn("Behavior on scale", text)
        # No free-standing clone factory; cards transform in place and reset.
        self.assertNotIn("createObject", text)
        self.assertIn("Component.onDestruction", text)
        self.assertIn("stopFlightAnims", text)
        # Thumbnail contract retained.
        self.assertIn("thumbnailProvider.requestThumbnails", text)
        self.assertIn("WindowPreviewFallback", text)
        # useSpring dual branch for flight.
        self.assertIn("shouldAnimateFlight", text)
        self.assertIn("root.useSpring && !Motion.reducedMotion", text)

    def test_shell_forwards_use_spring(self) -> None:
        text = self.read("shell.qml")
        self.assertIn("TaskSwitcher {", text)
        self.assertIn("WindowOverview {", text)
        # Count useSpring: shell.useSpring near both components (Spotlight also has it).
        self.assertGreaterEqual(text.count("useSpring: shell.useSpring"), 2)
        # Explicit pins so TaskSwitcher / WindowOverview both forward the gate.
        task_idx = text.find("TaskSwitcher {")
        overview_idx = text.find("WindowOverview {")
        self.assertGreaterEqual(task_idx, 0)
        self.assertGreaterEqual(overview_idx, 0)
        task_slice = text[task_idx : task_idx + 800]
        overview_slice = text[overview_idx : overview_idx + 800]
        self.assertIn("useSpring: shell.useSpring", task_slice)
        self.assertIn("useSpring: shell.useSpring", overview_slice)


if __name__ == "__main__":
    unittest.main()
