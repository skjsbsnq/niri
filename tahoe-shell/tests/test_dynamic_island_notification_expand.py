#!/usr/bin/env python3
"""T15: notification expand chevron + shared actions (no NotificationCenter copy)."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
VIEW = SHELL_ROOT / "components" / "DynamicIslandNotificationView.qml"
CONTENT = SHELL_ROOT / "components" / "DynamicIslandContent.qml"
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
ISLAND = SHELL_ROOT / "services" / "DynamicIsland.qml"


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


class DynamicIslandNotificationExpandTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.view = _read(VIEW)
        cls.content = _read(CONTENT)
        cls.overlay = _read(OVERLAY)
        cls.island = _read(ISLAND)

    def test_chevron_only_when_overflow(self) -> None:
        self.assertIn("expandToggleRequested", self.view)
        self.assertIn("visible: root.hasOverflow", self.view)
        self.assertIn("width: 44", self.view)
        # Chevron click must not call bodyClicked.
        self.assertIn("expandToggleRequested", self.view)
        # Body click area reserves trailing 44 when overflow; chevron z above body.
        self.assertIn("anchors.rightMargin: root.hasOverflow ? 44 : 0", self.view)
        self.assertIn("id: expandChevron", self.view)
        self.assertIn("expandedAbsorb", self.view)

    def test_expanded_absorbs_blank_hits(self) -> None:
        self.assertIn("id: expandedAbsorb", self.view)
        self.assertIn("visible: root.expanded", self.view)

    def test_dnd_clears_expanded_interaction(self) -> None:
        dnd = _function_body(self.island, "handleDndChanged")
        self.assertIn("transientNotificationExpanded = false", dnd)
        self.assertIn("setUserInteracting(false)", dnd)

    def test_action_requires_known_id(self) -> None:
        inv = _function_body(self.island, "invokeNotificationAction")
        self.assertIn("known", inv)
        self.assertIn("transientNotificationActions", inv)

    def test_body_click_still_default_action(self) -> None:
        self.assertIn("onBodyClicked: root.notificationBodyClicked()", self.content)
        self.assertIn("invokeNotificationDefaultAction", self.overlay)
        invoke = _function_body(self.island, "invokeNotificationDefaultAction")
        self.assertIn('"default"', invoke)
        # T14 freeze: still only default id.
        self.assertNotIn("default_action", invoke)

    def test_expanded_geometry_caps(self) -> None:
        width = _function_body(self.overlay, "notificationCompactTargetWidth")
        height = _function_body(self.overlay, "notificationCompactTargetHeight")
        self.assertIn("v2NotificationExpandedWidthMax", width)
        self.assertIn("v2NotificationExpandedHeightMax", height)
        self.assertIn("v2NotificationExpandedHeightMin", height)
        self.assertIn("transientNotificationExpanded", width)

    def test_actions_filter_default_and_cap_three(self) -> None:
        extract = _function_body(self.island, "extractNotificationActions")
        self.assertIn('lower === "default"', extract)
        self.assertIn("out.length < 3", extract)
        self.assertIn("打开", extract)
        self.assertIn("open", extract.lower())

    def test_toggle_pauses_timer(self) -> None:
        toggle = _function_body(self.island, "toggleNotificationExpanded")
        self.assertIn("transientNotificationHasOverflow", toggle)
        self.assertIn("setUserInteracting(true)", toggle)
        self.assertIn("transientTimer.stop()", toggle)
        self.assertIn("transientTimer.restart()", toggle)

    def test_action_uses_notifications_invoke(self) -> None:
        inv = _function_body(self.island, "invokeNotificationAction")
        self.assertIn("invokeAction", inv)
        self.assertIn("displayingNotificationId", inv)
        self.assertIn("restoreAfterTransient", inv)

    def test_removed_while_expanded_clears(self) -> None:
        changed = _function_body(self.island, "handleNotificationsChanged")
        self.assertIn("transientNotificationExpanded = false", changed)
        self.assertIn("clearTransientFields", changed)

    def test_no_notification_center_copy(self) -> None:
        self.assertNotIn("NotificationCenter", self.view)
        self.assertNotIn("historyModel", self.view)
        self.assertNotIn("historyModel", self.content)

    def test_expanded_body_max_three_lines(self) -> None:
        self.assertIn("maximumLineCount: 3", self.view)
        self.assertIn("Flickable", self.view)
        self.assertIn("Flickable.VerticalFlick", self.view)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
