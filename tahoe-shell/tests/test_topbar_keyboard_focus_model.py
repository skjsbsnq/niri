#!/usr/bin/env python3
"""T-29 / F-10: TopBar keyboard focus model.

The bar is click-focusable (OnDemand layer interactivity); once focused,
Tab/Backtab/arrows walk the visible interactive entries in visual order and
Return/Enter/Space activate the current one (same action path as the mouse).
The runtime probe exercises the chain under the Tahoe Quickshell runtime.
"""

from __future__ import annotations

import re
import subprocess
import tempfile
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
TOPBAR = SHELL_ROOT / "components" / "TopBar.qml"
TRAY = SHELL_ROOT / "components" / "Tray.qml"
QML_PROBE = Path(__file__).with_name("tst_topbar_keyboard_focus_model.qml")

# Fixed entries in the keyboard chain (visual order). Service-gated entries
# and Repeater/ListView entries are inserted at their declared slots.
ENTRY_IDS = [
    "niriMenuButton",
    "leftSidebarButton",
    "applicationMenuButton",
    "notificationButton",
    "clipboardButton",
    "fanButton",
    "batteryButton",
    "wifiButton",
    "spotlightButton",
    "statusButton",
]
ENTRY_NAMES = {
    "niriMenuButton": "topbarEntryNiriMenu",
    "leftSidebarButton": "topbarEntryLeftSidebar",
    "applicationMenuButton": "topbarEntryAppMenu",
    "notificationButton": "topbarEntryNotifications",
    "clipboardButton": "topbarEntryClipboard",
    "fanButton": "topbarEntryFan",
    "batteryButton": "topbarEntryBattery",
    "wifiButton": "topbarEntryWifi",
    "spotlightButton": "topbarEntrySpotlight",
    "statusButton": "topbarEntryStatus",
}
ENTRY_ACTIONS = {
    "niriMenuButton": "toggleAppMenu",
    "leftSidebarButton": "toggleLeftSidebar",
    "applicationMenuButton": "toggleApplicationMenu",
    "notificationButton": "toggleNotifications",
    "clipboardButton": "toggleClipboard",
    "fanButton": "toggleFan",
    "batteryButton": "toggleBattery",
    "wifiButton": "toggleWifi",
    "spotlightButton": "toggleSpotlight",
    "statusButton": "toggleControlCenter",
}


def _function_body(src: str, name: str) -> str:
    m = re.search(rf"function\s+{re.escape(name)}\s*\([^)]*\)\s*\{{", src)
    if not m:
        m = re.search(rf"function\s+{re.escape(name)}\s*\{{", src)
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


class TopBarKeyboardStructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.topbar = TOPBAR.read_text(encoding="utf-8")
        cls.tray = TRAY.read_text(encoding="utf-8")

    def test_surface_is_click_focusable(self) -> None:
        self.assertIn("focusable: true", self.topbar)

    def test_single_focus_catcher_owns_keys(self) -> None:
        self.assertIn("id: topbarKeyboardFocusCatcher", self.topbar)
        self.assertIn('objectName: "topbarKeyboardFocusCatcher"', self.topbar)
        self.assertIn("focus: true", self.topbar)
        for key in ("Tab", "Backtab", "Right", "Left", "Return", "Enter", "Space"):
            self.assertIn(f"Keys.on{key}Pressed", self.topbar)

    def test_keyboard_model_functions_exist(self) -> None:
        for fn in (
            "function keyboardEntryList()",
            "function keyboardIndexOf(entry)",
            "function keyboardStep(delta)",
            "function engageKeyboardEntry(entry)",
            "function activateKeyboardCurrent()",
        ):
            self.assertIn(fn, self.topbar)

    def test_entries_are_pushed_in_visual_order(self) -> None:
        body = self.topbar.split("function keyboardEntryList()", 1)[1].split(
            "function keyboardIndexOf", 1
        )[0]
        positions = [body.index(f"push({entry});") for entry in ENTRY_IDS]
        self.assertEqual(
            positions, sorted(positions), "entries must be pushed in visual order"
        )
        self.assertIn("push(workspaceRepeater.itemAt(i));", body)
        self.assertIn("push(topbarTimeFallback);", body)
        self.assertIn("push(tray.keyboardItemAt(j));", body)

    def test_every_entry_has_identity_activation_and_indicator(self) -> None:
        for entry in ENTRY_IDS:
            name = ENTRY_NAMES[entry]
            self.assertIn(f'objectName: "{name}"', self.topbar, entry)
            self.assertIn("function keyboardActivate()", self.topbar, entry)
            self.assertIn(f"root.keyboardCurrent === {entry}", self.topbar, entry)
            self.assertIn(f"root.engageKeyboardEntry({entry});", self.topbar, entry)

    def test_keyboard_activation_reuses_mouse_action_path(self) -> None:
        # keyboardActivate must call the same action as the MouseArea — no
        # second API/activation channel. Each entry's own function body is the
        # first keyboardActivate occurrence after its id declaration.
        for entry, action in ENTRY_ACTIONS.items():
            id_pos = self.topbar.index(f"id: {entry}")
            first = re.search(r"function keyboardActivate\(\)", self.topbar[id_pos:])
            self.assertIsNotNone(first, entry)
            kb = _function_body(self.topbar[id_pos + first.start() :], "keyboardActivate")
            self.assertIn(action, kb, entry)
            # The same action must remain wired to the entry's MouseArea.
            self.assertIn(action, self.topbar[id_pos:], entry)

    def test_workspace_delegate_joins_the_chain(self) -> None:
        self.assertIn("id: workspaceRepeater", self.topbar)
        self.assertIn("id: workspaceEntry", self.topbar)
        self.assertIn('objectName: "topbarEntryWorkspace"', self.topbar)
        self.assertIn("root.keyboardCurrent === workspaceEntry", self.topbar)
        self.assertIn("root.engageKeyboardEntry(workspaceEntry);", self.topbar)
        self.assertIn("modelData.canActivate", self.topbar)
        self.assertIn("activateWorkspace", self.topbar)

    def test_island_chip_joins_the_chain(self) -> None:
        self.assertIn('objectName: "topbarEntryIslandChip"', self.topbar)
        self.assertIn("root.keyboardCurrent === topbarTimeFallback", self.topbar)
        self.assertIn("root.engageKeyboardEntry(topbarTimeFallback);", self.topbar)
        self.assertIn("handleChipClick", self.topbar)

    def test_tray_exposes_keyboard_entries(self) -> None:
        self.assertIn("function keyboardItemCount()", self.tray)
        self.assertIn("function keyboardItemAt(index)", self.tray)
        self.assertIn('objectName: "topbarEntryTrayItem"', self.tray)
        self.assertIn("function keyboardActivate()", self.tray)
        self.assertIn("root.panelWindow.keyboardCurrent === trayItem", self.tray)
        self.assertIn("root.panelWindow.engageKeyboardEntry(trayItem);", self.tray)


class TopBarKeyboardRuntimeTests(unittest.TestCase):
    """Drives the production TopBar under the Tahoe Quickshell runtime."""

    def _run_probe(self) -> subprocess.CompletedProcess:
        local_runner = Path.home() / ".local" / "bin" / "qs"
        runner = str(local_runner) if local_runner.is_file() else shutil.which("qs")
        self.assertIsNotNone(runner, "Tahoe Quickshell runtime is required")

        source = QML_PROBE.read_text(encoding="utf-8").replace(
            'property string panelSource: ""',
            f'property string panelSource: "{TOPBAR}"',
        )
        with tempfile.TemporaryDirectory(prefix="tahoe-topbar-kb-") as tmp:
            probe = Path(tmp) / "shell.qml"
            probe.write_text(source, encoding="utf-8")
            return subprocess.run(
                [runner, "-p", str(probe)],
                cwd=SHELL_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=90,
                check=False,
            )

    def test_keyboard_chain_traverses_and_activates(self) -> None:
        result = self._run_probe()
        self.assertIn("TOPBAR_KEYBOARD_OK", result.stdout, result.stdout)
        self.assertNotIn("TOPBAR_KEYBOARD_FAIL", result.stdout, result.stdout)


if __name__ == "__main__":
    unittest.main()
