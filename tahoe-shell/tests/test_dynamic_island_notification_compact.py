#!/usr/bin/env python3
"""T14: compact notification scene with app identity and content-driven size."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
VIEW = SHELL_ROOT / "components" / "DynamicIslandNotificationView.qml"
CONTENT = SHELL_ROOT / "components" / "DynamicIslandContent.qml"
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
ISLAND = SHELL_ROOT / "services" / "DynamicIsland.qml"
NOTIFICATIONS = SHELL_ROOT / "services" / "Notifications.qml"


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


class DynamicIslandNotificationCompactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.view = _read(VIEW)
        cls.content = _read(CONTENT)
        cls.overlay = _read(OVERLAY)
        cls.island = _read(ISLAND)
        cls.notifications = _read(NOTIFICATIONS)

    def test_view_shows_app_identity(self) -> None:
        self.assertIn("appName", self.view)
        self.assertIn("summary", self.view)
        self.assertIn("body", self.view)
        self.assertIn("iconUrl", self.view)
        self.assertIn("safeIconUrl", self.view)
        self.assertIn("image://", self.view)
        self.assertIn("file://", self.view)
        self.assertIn("bodyClicked", self.view)
        self.assertIn("font.letterSpacing: 0", self.view)

    def test_no_generic_bell_only_path(self) -> None:
        # View may fall back to symbol when no icon AND no appName, but prefers app icon/initial.
        self.assertIn("compactImage", self.view)
        self.assertIn("charAt(0)", self.view)
        # Content hosts the dedicated view, not the old bell+title row.
        self.assertIn("DynamicIslandNotificationView", self.content)
        self.assertNotIn("id: notificationRow", self.content)

    def test_service_maps_icon_and_urgency(self) -> None:
        entry = _function_body(self.island, "notificationEntry")
        self.assertIn("iconUrlFor", entry)
        self.assertIn("urgency", entry)
        self.assertIn("critical", entry)
        apply = _function_body(self.island, "applyNotificationPresentation")
        self.assertIn("transientNotificationAppName", apply)
        self.assertIn("transientNotificationIconUrl", apply)
        self.assertIn("transientNotificationHasOverflow", apply)
        # replace-id path does not restart timer / showTransient.
        text_fn = _function_body(self.island, "applyNotificationEntryText")
        self.assertIn("transientNotificationAppName", text_fn)
        self.assertNotIn("transientTimer", re.sub(r"//[^\n]*", "", text_fn))
        self.assertNotIn("showTransient", re.sub(r"//[^\n]*", "", text_fn))

    def test_present_sets_lease_and_presentation(self) -> None:
        present = _function_body(self.island, "presentNotificationEntry")
        self.assertIn("displayingNotificationId", present)
        self.assertIn("applyNotificationPresentation(entry, true)", present)
        # No hard-coded generic bell as sole identity.
        self.assertNotIn('\\ue7f4", root.notificationHideMs', present)

    def test_default_action_and_dismiss_use_notifications_api(self) -> None:
        invoke = _function_body(self.island, "invokeNotificationDefaultAction")
        dismiss = _function_body(self.island, "dismissDisplayedNotification")
        self.assertIn("displayingNotificationId", invoke)
        self.assertIn("invokeAction", invoke)
        self.assertIn('"default"', invoke)
        # Single invoke only (no double default_action fire).
        self.assertEqual(invoke.count("invokeAction("), 1)
        self.assertNotIn("default_action", invoke)
        self.assertIn("dismissId", dismiss)
        self.assertIn("displayingNotificationId", dismiss)
        # Notifications remains the owner.
        self.assertIn("function invokeAction", self.notifications)
        self.assertIn("function dismissId", self.notifications)
        self.assertIn("function iconUrlFor", self.notifications)

    def test_swipe_dismiss_lives_in_notification_view(self) -> None:
        # contentHost sits above capsule MouseArea; swipe must be on the view.
        self.assertIn("dismissRequested", self.view)
        self.assertIn("swipeArmThresholdPx", self.view)
        self.assertIn("onPositionChanged", self.view)
        self.assertIn("bodyClicked", self.view)
        # Click suppressed after horizontal move.
        self.assertIn("if (moved || dismissed)", self.view)

    def test_overlay_content_driven_size_and_wiring(self) -> None:
        self.assertIn("notificationCompactTargetWidth", self.overlay)
        self.assertIn("notificationCompactTargetHeight", self.overlay)
        self.assertIn("v2NotificationCompactWidthMax", self.overlay)
        self.assertIn("v2NotificationCompactWidthMin", self.overlay)
        self.assertIn("invokeNotificationDefaultAction", self.overlay)
        self.assertIn("dismissDisplayedNotification", self.overlay)
        # Swipe dismiss path on notification state.
        self.assertIn("transient_notification", self.overlay)
        self.assertIn("dismissDisplayedNotification", self.overlay)

    def test_no_second_notification_model(self) -> None:
        # Presentation fields only — not a FIFO copy of Notifications.
        self.assertNotIn("property var notificationModel", self.island)
        self.assertNotIn("pendingNotificationModel", self.island)
        self.assertNotIn("dbus-monitor", self.island)
        self.assertNotIn("dbus-monitor", self.view)

    def test_overflow_heuristic(self) -> None:
        body = _function_body(self.island, "notificationHasOverflow")
        self.assertIn("length > 28", body)
        self.assertIn("length > 36", body)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
