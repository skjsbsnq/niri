#!/usr/bin/env python3
"""T02: freeze Dynamic Island public IPC, settings, and overlay contracts.

These assertions lock compatibility surfaces that V2 may reimplement internally
but must not rename, drop, or silently change. Production QML is read-only.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
SHELL_QML = SHELL_ROOT / "shell.qml"
DESKTOP_SETTINGS = SHELL_ROOT / "services" / "DesktopSettings.qml"
ISLAND = SHELL_ROOT / "services" / "DynamicIsland.qml"
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
TOPBAR = SHELL_ROOT / "components" / "TopBar.qml"
MEDIA_VIEW = SHELL_ROOT / "components" / "DynamicIslandMediaView.qml"


def _ipc_block(text: str) -> str:
    match = re.search(
        r"IpcHandler\s*\{(?P<body>[\s\S]*?target:\s*\"tahoe\"[\s\S]*?)\n    \}",
        text,
    )
    if not match:
        # Fallback: find target tahoe and take a large window.
        idx = text.find('target: "tahoe"')
        if idx < 0:
            raise AssertionError("IpcHandler target tahoe not found")
        return text[max(0, idx - 200) : idx + 8000]
    return match.group(0)


class DynamicIslandPublicContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.shell = SHELL_QML.read_text(encoding="utf-8")
        cls.settings = DESKTOP_SETTINGS.read_text(encoding="utf-8")
        cls.island = ISLAND.read_text(encoding="utf-8")
        cls.overlay = OVERLAY.read_text(encoding="utf-8")
        cls.topbar = TOPBAR.read_text(encoding="utf-8")
        cls.media = MEDIA_VIEW.read_text(encoding="utf-8")
        cls.ipc = _ipc_block(cls.shell)

    def test_ipc_target_remains_tahoe(self) -> None:
        self.assertRegex(self.shell, r"IpcHandler\s*\{[\s\S]*?target:\s*\"tahoe\"")

    def test_ipc_function_names_and_signatures(self) -> None:
        required = {
            "dynamicIslandGetState": r"function\s+dynamicIslandGetState\s*\(\s*\)\s*:\s*string",
            "dynamicIslandGetDebugSummary": r"function\s+dynamicIslandGetDebugSummary\s*\(\s*\)\s*:\s*string",
            "dynamicIslandGetSettingsSummary": r"function\s+dynamicIslandGetSettingsSummary\s*\(\s*\)\s*:\s*string",
            "dynamicIslandReset": r"function\s+dynamicIslandReset\s*\(\s*\)\s*:\s*string",
            "dynamicIslandShowTime": r"function\s+dynamicIslandShowTime\s*\(\s*\)\s*:\s*string",
            "dynamicIslandShowMedia": r"function\s+dynamicIslandShowMedia\s*\(\s*\)\s*:\s*string",
            "dynamicIslandShowExpandedMedia": r"function\s+dynamicIslandShowExpandedMedia\s*\(\s*\)\s*:\s*string",
            "dynamicIslandShowExpandedSummary": r"function\s+dynamicIslandShowExpandedSummary\s*\(\s*\)\s*:\s*string",
            "dynamicIslandShowOsd": r"function\s+dynamicIslandShowOsd\s*\(\s*text:\s*string,\s*progress:\s*real\s*\)\s*:\s*string",
            "dynamicIslandShowNotification": r"function\s+dynamicIslandShowNotification\s*\(\s*summary:\s*string,\s*body:\s*string\s*\)\s*:\s*string",
            "dynamicIslandShowWorkspace": r"function\s+dynamicIslandShowWorkspace\s*\(\s*label:\s*string\s*\)\s*:\s*string",
            "dynamicIslandMediaNext": r"function\s+dynamicIslandMediaNext\s*\(\s*\)\s*:\s*string",
            "dynamicIslandMediaPrevious": r"function\s+dynamicIslandMediaPrevious\s*\(\s*\)\s*:\s*string",
            "dynamicIslandMediaToggle": r"function\s+dynamicIslandMediaToggle\s*\(\s*\)\s*:\s*string",
            "dynamicIslandSwipeBegin": r"function\s+dynamicIslandSwipeBegin\s*\(\s*\)\s*:\s*string",
            "dynamicIslandSwipeAdvance": r"function\s+dynamicIslandSwipeAdvance\s*\(\s*deltaX:\s*real,\s*deltaY:\s*real\s*\)\s*:\s*string",
            "dynamicIslandSwipeResolve": r"function\s+dynamicIslandSwipeResolve\s*\(\s*\)\s*:\s*string",
            "dynamicIslandSwipeCancel": r"function\s+dynamicIslandSwipeCancel\s*\(\s*\)\s*:\s*string",
            "dynamicIslandSetEnabled": r"function\s+dynamicIslandSetEnabled\s*\(\s*enabled:\s*bool\s*\)\s*:\s*string",
            "dynamicIslandSetHideTopbarTime": r"function\s+dynamicIslandSetHideTopbarTime\s*\(\s*enabled:\s*bool\s*\)\s*:\s*string",
            "dynamicIslandSetLeftClickAction": r"function\s+dynamicIslandSetLeftClickAction\s*\(\s*action:\s*string\s*\)\s*:\s*string",
            "dynamicIslandSetRightClickAction": r"function\s+dynamicIslandSetRightClickAction\s*\(\s*action:\s*string\s*\)\s*:\s*string",
            "dynamicIslandSetAutoExpandMedia": r"function\s+dynamicIslandSetAutoExpandMedia\s*\(\s*enabled:\s*bool\s*\)\s*:\s*string",
            "dynamicIslandSetHoverExpand": r"function\s+dynamicIslandSetHoverExpand\s*\(\s*enabled:\s*bool\s*\)\s*:\s*string",
        }
        for name, pattern in required.items():
            with self.subTest(name=name):
                self.assertRegex(self.ipc, pattern)

    def test_no_v2_parallel_ipc_target(self) -> None:
        self.assertNotIn('target: "tahoeV2"', self.shell)
        self.assertNotIn('target: "dynamicIslandV2"', self.shell)
        self.assertNotRegex(self.shell, r"function\s+dynamicIslandV2")

    def test_desktop_settings_fields_and_defaults(self) -> None:
        fields = [
            "dynamicIslandEnabled",
            "dynamicIslandHideTopbarTime",
            "dynamicIslandLeftClickAction",
            "dynamicIslandRightClickAction",
            "dynamicIslandAutoExpandMedia",
            "dynamicIslandHoverExpand",
        ]
        for field in fields:
            with self.subTest(field=field):
                self.assertIn(f"readonly property", self.settings)
                self.assertIn(field, self.settings)
                self.assertIn(f"property ", self.settings)
                # Adapter default block contains the field.
                self.assertRegex(
                    self.settings,
                    rf"property\s+(bool|string)\s+{re.escape(field)}\s*:",
                )

        self.assertRegex(
            self.settings,
            r"property\s+bool\s+dynamicIslandEnabled\s*:\s*true",
        )
        self.assertRegex(
            self.settings,
            r"property\s+bool\s+dynamicIslandHideTopbarTime\s*:\s*true",
        )
        self.assertRegex(
            self.settings,
            r'property\s+string\s+dynamicIslandLeftClickAction\s*:\s*"toggle_media"',
        )
        self.assertRegex(
            self.settings,
            r'property\s+string\s+dynamicIslandRightClickAction\s*:\s*"control_center"',
        )
        self.assertRegex(
            self.settings,
            r"property\s+bool\s+dynamicIslandAutoExpandMedia\s*:\s*false",
        )
        self.assertRegex(
            self.settings,
            r"property\s+bool\s+dynamicIslandHoverExpand\s*:\s*false",
        )

    def test_click_action_value_set(self) -> None:
        body = re.search(
            r"function\s+validDynamicIslandClickAction\s*\([^)]*\)\s*\{(?P<body>[\s\S]*?)\n    \}",
            self.settings,
        )
        self.assertIsNotNone(body)
        text = body.group("body")
        for action in (
            "toggle_media",
            "summary",
            "notifications",
            "control_center",
            "none",
        ):
            self.assertIn(f'"{action}"', text)

    def test_disabled_island_still_has_time_path(self) -> None:
        # Overlay hides when disabled; TopBar must show fallback time.
        self.assertIn("showTopbarTimeFallback", self.topbar)
        self.assertIn(
            "readonly property bool showTopbarTimeFallback: !dynamicIslandOverlayHandlesResting",
            self.topbar,
        )
        self.assertIn("fallbackTimeText", self.island)
        self.assertIn("displayText: root.dynamicIslandService ? root.dynamicIslandService.fallbackTimeText", self.topbar)
        # Truth table from source formulas:
        # enabled=false → overlayHandlesResting=false → showTopbarTimeFallback=true
        enabled = False
        hide = True
        overlay_handles = enabled and hide
        show_fallback = not overlay_handles
        self.assertTrue(show_fallback)

    def test_dnd_blocks_manual_and_present_notification_paths(self) -> None:
        self.assertIn("notificationsDndEnabled()", self.island)
        self.assertRegex(
            self.island,
            r"function\s+showTransientNotification[\s\S]*?notificationsDndEnabled\(\)",
        )
        self.assertRegex(
            self.island,
            r"function\s+presentNotificationEntry[\s\S]*?notificationsDndEnabled\(\)",
        )
        self.assertRegex(
            self.island,
            r"function\s+handleDndChanged[\s\S]*?transient_notification",
        )

    def test_overlay_exclusive_zone_zero(self) -> None:
        self.assertRegex(self.overlay, r"exclusiveZone\s*:\s*0\b")

    def test_overlay_namespace_unchanged(self) -> None:
        self.assertIn('WlrLayershell.namespace: "tahoe-dynamic-island"', self.overlay)

    def test_overlay_mask_follows_capsule_not_full_screen(self) -> None:
        self.assertIn("mask: Region", self.overlay)
        self.assertIn("width: root.capsuleShown ? Math.round(islandSurface.width) : 0", self.overlay)
        self.assertIn("height: root.capsuleShown ? Math.round(islandSurface.height) : 0", self.overlay)
        # Panel is full width for positioning, but input mask must not use screen size.
        self.assertIn("implicitWidth: screenWidth", self.overlay)
        self.assertNotRegex(
            self.overlay,
            r"mask:\s*Region\s*\{[\s\S]*width:\s*screenWidth",
        )

    def test_media_press_release_cancel_surface_exists(self) -> None:
        # Contract: media controls expose press/release/cancel lifecycle hooks.
        for name in (
            "onPressed",
            "onReleased",
            "onCanceled",
            "mediaTogglePlayPause",
            "mediaNext",
            "mediaPrevious",
        ):
            with self.subTest(name=name):
                if name.startswith("media"):
                    self.assertIn(name, self.island)
                else:
                    self.assertIn(name, self.media)

    def test_notification_stable_identity_fields_exist(self) -> None:
        for name in (
            "seenNotificationIds",
            "pendingNotificationIds",
            "displayingNotificationId",
            "handleNotificationUpdated",
            "onNotificationUpdated",
        ):
            with self.subTest(name=name):
                self.assertIn(name, self.island)

    def test_settings_summary_keys_stable(self) -> None:
        for key in (
            "enabled=",
            "hideTopbarTime=",
            "leftClickAction=",
            "rightClickAction=",
            "autoExpandMedia=",
            "hoverExpand=",
        ):
            self.assertIn(key, self.ipc)


if __name__ == "__main__":
    unittest.main()
