#!/usr/bin/env python3
"""T-22: island exit-field latch — fading scenes keep their content.

Root bug (S-M1): when a transient lease (notification / bluetooth / workspace)
ends, the service clears transient fields the instant the dismiss / hide
timer fires. The scene's exit fade (contentExitMs ~110ms) is still animating
during that window, so the fading card rebinds its text to the now-empty
fields and flashes to the clock / "通知" fallback string. Media already
avoids this via latchedCompactMediaTitle + mediaUnloadHold (T16); the three
transient scenes lacked the equivalent latch.

Fix contract (T-22): DynamicIslandContent now mirrors the media pattern for
notification, bluetooth and workspace:
  - latched* fields freeze the last non-empty content seen while the scene
    is active (plus a hold window after it goes inactive, matching the exit
    fade duration + padding).
  - scene bindings (summary / body / appName / icon / urgency / overflow /
    expanded / actions for notification; kind / deviceName / deviceIcon for
    bluetooth; label / direction for workspace) read live while active and
    fall back to the latch while the scene is still fading out.
  - hold timers (notificationExitHold / bluetoothExitHold / workspaceExitHold)
    clear the latch only once the exit fade is guaranteed finished.
  - on re-entry within the hold (reused loader instance) the latch is cleared
    before seeding so a new lease with an empty field does not bleed the
    previous scene's content.

These are pure presentation-layer latches inside DynamicIslandContent; the
service transient-field contract and the Overlay→Content binding interface
are unchanged (no parallel API).
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
CONTENT = SHELL_ROOT / "components" / "DynamicIslandContent.qml"


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


class DynamicIslandExitLatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.content = _read(CONTENT)

    # -- Notification latch -------------------------------------------------

    def test_notification_latched_fields_exist(self) -> None:
        for prop in (
            "latchedNotificationSummary",
            "latchedNotificationBody",
            "latchedNotificationAppName",
            "latchedNotificationIconUrl",
            "latchedNotificationUrgency",
            "latchedNotificationHasOverflow",
            "latchedNotificationExpanded",
            "latchedNotificationActions",
        ):
            self.assertIn(f"property ", self.content)
            self.assertIn(prop, self.content, f"missing {prop}")

    def test_notification_bindings_fall_back_to_latch(self) -> None:
        # Each binding is a readonly property whose body returns live while
        # active, latch otherwise.
        for binding in (
            "notificationSummaryBinding",
            "notificationBodyBinding",
            "notificationAppNameBinding",
            "notificationIconUrlBinding",
        ):
            m = re.search(
                rf"readonly property string {re.escape(binding)}:\s*\{{(?P<b>[\s\S]*?)\n    \}}",
                self.content,
            )
            self.assertIsNotNone(m, f"missing binding property {binding}")
            block = m.group("b")
            # Must reference the live field AND the latched counterpart.
            self.assertIn("notificationActive", block, f"{binding} missing active gate")
            self.assertIn("latched", block, f"{binding} missing latch fallback")
        # Boolean/var bindings use ternary form (no block body).
        self.assertRegex(self.content, r"notificationUrgencyBinding:\s*\n?\s*root\.notificationActive\s*\?")
        self.assertRegex(self.content, r"notificationHasOverflowBinding:\s*\n?\s*root\.notificationActive\s*\?")
        self.assertRegex(self.content, r"notificationExpandedBinding:\s*\n?\s*root\.notificationActive\s*\?")
        self.assertRegex(self.content, r"notificationActionsBinding:\s*\n?\s*root\.notificationActive\s*\?")

    def test_notification_scene_uses_latched_bindings(self) -> None:
        # The DynamicIslandNotificationView inside the Component must bind to
        # the *Binding accessors, not the raw transient fields — that is the
        # whole point of the latch.
        notif_block = re.search(
            r"DynamicIslandNotificationView\s*\{(?P<b>[\s\S]*?)\n\s{12}\}",
            self.content,
        )
        self.assertIsNotNone(notif_block, "DynamicIslandNotificationView block not found")
        body = notif_block.group("b")
        self.assertIn("appName: root.notificationAppNameBinding", body)
        self.assertIn("summary: root.notificationSummaryBinding", body)
        self.assertIn("body: root.notificationBodyBinding", body)
        self.assertIn("iconUrl: root.notificationIconUrlBinding", body)
        self.assertIn("urgency: root.notificationUrgencyBinding", body)
        self.assertIn("hasOverflow: root.notificationHasOverflowBinding", body)
        self.assertIn("expanded: root.notificationExpandedBinding", body)
        self.assertIn("actions: root.notificationActionsBinding", body)
        # Must NOT bind the raw transient fields directly anymore.
        self.assertNotRegex(body, r"summary:\s*root\.displayText\b")
        self.assertNotRegex(body, r"body:\s*root\.secondaryText\b")
        self.assertNotRegex(body, r"appName:\s*root\.notificationAppName\b(?!\w)")

    def test_notification_exit_hold_timer_clears_latch(self) -> None:
        self.assertIn("id: notificationExitHold", self.content)
        body = _function_body(self.content, "") or ""
        # The hold timer clears the latch fields on trigger.
        hold = re.search(
            r"id:\s*notificationExitHold\s*\n(?:[^\n]*\n)*?\s*onTriggered:\s*\{(?P<b>[\s\S]*?)\n\s{12}\}",
            self.content,
        )
        self.assertIsNotNone(hold, "notificationExitHold onTriggered not found")
        hbody = hold.group("b")
        for prop in (
            "latchedNotificationSummary",
            "latchedNotificationBody",
            "latchedNotificationAppName",
            "latchedNotificationIconUrl",
            "latchedNotificationUrgency",
            "latchedNotificationHasOverflow",
            "latchedNotificationExpanded",
            "latchedNotificationActions",
        ):
            self.assertIn(prop, hbody, f"{prop} not cleared in hold timer")
        self.assertIn("notificationExiting", hbody)

    def test_notification_reentry_clears_latch_before_seed(self) -> None:
        # On becoming active again (reused loader within the hold window),
        # the latch is cleared before seeding so a new lease with an empty
        # field does not bleed the previous notification's content.
        active = re.search(
            r"onNotificationActiveChanged:\s*\{(?P<b>[\s\S]*?)\n    \}",
            self.content,
        )
        self.assertIsNotNone(active)
        body = active.group("b")
        # Active branch must clear latch then re-seed.
        self.assertIn("notificationExitHold.stop()", body)
        self.assertIn("latchedNotificationSummary = \"\"", body)
        self.assertIn("latchNotificationContent()", body)

    # -- Bluetooth latch -----------------------------------------------------

    def test_bluetooth_latched_fields_and_bindings(self) -> None:
        for prop in (
            "latchedBluetoothKind",
            "latchedBluetoothDeviceName",
            "latchedBluetoothDeviceIcon",
        ):
            self.assertIn(prop, self.content)
        bt_block = re.search(
            r"DynamicIslandBluetoothView\s*\{(?P<b>[\s\S]*?)\n    \}",
            self.content,
        )
        self.assertIsNotNone(bt_block, "DynamicIslandBluetoothView block not found")
        body = bt_block.group("b")
        self.assertIn("kind: root.bluetoothKindBinding", body)
        self.assertIn("deviceName: root.bluetoothDeviceNameBinding", body)
        self.assertIn("deviceIcon: root.bluetoothDeviceIconBinding", body)
        # Must not bind raw transient bluetooth fields directly.
        self.assertNotRegex(body, r"kind:\s*root\.bluetoothKind\b(?!\w)")
        self.assertIn("id: bluetoothExitHold", self.content)

    def test_bluetooth_exit_hold_clears_latch(self) -> None:
        hold = re.search(
            r"id:\s*bluetoothExitHold\s*\n(?:[^\n]*\n)*?\s*onTriggered:\s*\{(?P<b>[\s\S]*?)\n    \}",
            self.content,
        )
        self.assertIsNotNone(hold)
        hbody = hold.group("b")
        for prop in (
            "latchedBluetoothKind",
            "latchedBluetoothDeviceName",
            "latchedBluetoothDeviceIcon",
        ):
            self.assertIn(prop, hbody)
        self.assertIn("bluetoothExiting", hbody)

    # -- Workspace latch ----------------------------------------------------

    def test_workspace_latched_fields_and_bindings(self) -> None:
        for prop in ("latchedWorkspaceLabel", "latchedWorkspaceDirection"):
            self.assertIn(prop, self.content)
        ws_block = re.search(
            r"DynamicIslandWorkspaceView\s*\{(?P<b>[\s\S]*?)\n    \}",
            self.content,
        )
        self.assertIsNotNone(ws_block, "DynamicIslandWorkspaceView block not found")
        body = ws_block.group("b")
        self.assertIn("workspaceLabelBinding", body)
        self.assertIn("workspaceDirectionBinding", body)
        self.assertIn("id: workspaceExitHold", self.content)

    def test_workspace_exit_hold_clears_latch(self) -> None:
        hold = re.search(
            r"id:\s*workspaceExitHold\s*\n(?:[^\n]*\n)*?\s*onTriggered:\s*\{(?P<b>[\s\S]*?)\n    \}",
            self.content,
        )
        self.assertIsNotNone(hold)
        hbody = hold.group("b")
        self.assertIn("latchedWorkspaceLabel", hbody)
        self.assertIn("latchedWorkspaceDirection", hbody)
        self.assertIn("workspaceExiting", hbody)

    # -- Shared hold-window contract ---------------------------------------

    def test_hold_window_outlives_exit_fade(self) -> None:
        # sceneExitHoldMs must reuse expandedUnloadHoldMs (exit fade + padding)
        # so the latch never clears before the scene is done fading.
        self.assertIn("sceneExitHoldMs: root.expandedUnloadHoldMs", self.content)
        self.assertIn("expandedUnloadHoldMs: IslandMotion.contentExitMs", self.content)

    def test_no_parallel_service_interface_added(self) -> None:
        # The latch is presentation-only: Content must NOT introduce a second
        # service channel. No clearTransientFields override (that belongs to the
        # service), no dynamicIslandService dependency, no IPC. The pre-existing
        # view→overlay signals (notificationBodyClicked etc.) are unchanged and
        # are not a new channel.
        self.assertNotIn("clearTransientFields", self.content)
        self.assertNotIn("dynamicIslandService", self.content)
        self.assertNotIn("IpcHandler", self.content)
        self.assertNotIn("IpcCall", self.content)
        # No new signal was introduced as part of the latch: the latch uses
        # property changes + timers only, so none of the latched*/Exiting
        # fields have an accompanying `signal ` declaration.
        for name in (
            "notificationExiting",
            "bluetoothExiting",
            "workspaceExiting",
            "latchedNotificationSummary",
            "latchedBluetoothKind",
            "latchedWorkspaceLabel",
        ):
            self.assertNotIn(f"signal {name}", self.content)
        # The existing view-facing signals are still present (unchanged API).
        self.assertIn("signal notificationBodyClicked()", self.content)
        self.assertIn("signal mediaPlayPauseRequested()", self.content)

    def test_latch_only_seeds_non_empty_while_active(self) -> None:
        body = _function_body(self.content, "latchNotificationContent")
        self.assertIn("v.length > 0", body)
        # Every string field is guarded by a non-empty check.
        self.assertEqual(body.count(".length > 0") >= 4, True)
        bt = _function_body(self.content, "latchBluetoothContent")
        self.assertGreaterEqual(bt.count(".length > 0"), 3)
        ws = _function_body(self.content, "latchWorkspaceContent")
        self.assertIn(".length > 0", ws)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
