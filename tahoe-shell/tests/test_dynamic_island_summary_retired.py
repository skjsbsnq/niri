#!/usr/bin/env python3
"""T18: retire expanded_summary; workspace scene; legacy IPC alias."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
ISLAND = SHELL / "services" / "DynamicIsland.qml"
REDUCER = SHELL / "services" / "DynamicIslandReducer.js"
OWNERSHIP = SHELL / "components" / "DynamicIslandOwnership.js"
CONTENT = SHELL / "components" / "DynamicIslandContent.qml"
OVERLAY = SHELL / "components" / "DynamicIslandOverlay.qml"
SETTINGS = SHELL / "services" / "DesktopSettings.qml"
PAGE = SHELL / "components" / "settings" / "pages" / "DynamicIslandPage.qml"
WORKSPACE = SHELL / "components" / "DynamicIslandWorkspaceView.qml"
SUMMARY = SHELL / "components" / "DynamicIslandSummaryView.qml"
SHELL_QML = SHELL / "shell.qml"


def _read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


class SummaryRetiredTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.island = _read(ISLAND)
        cls.reducer = _read(REDUCER)
        cls.ownership = _read(OWNERSHIP)
        cls.content = _read(CONTENT)
        cls.overlay = _read(OVERLAY)
        cls.settings = _read(SETTINGS)
        cls.page = _read(PAGE)
        cls.workspace = _read(WORKSPACE)
        cls.shell = _read(SHELL_QML)

    def test_summary_view_deleted(self) -> None:
        self.assertFalse(SUMMARY.exists())
        self.assertNotIn("DynamicIslandSummaryView", self.content)
        # Production VALID_STATES must not include expanded_summary.
        self.assertNotIn('"expanded_summary"', self.reducer)
        self.assertNotIn('"expanded_summary"', self.island)

    def test_show_expanded_summary_alias_opens_control_center(self) -> None:
        self.assertIn("function showExpandedSummary", self.island)
        self.assertIn("SHOW_EXPANDED_SUMMARY", self.island)
        self.assertIn('effect("openControlCenter")', self.reducer)
        self.assertIn('case "openControlCenter"', self.island)
        # Must not force expanded_summary state.
        self.assertNotIn('forcedState = "expanded_summary"', self.reducer)

    def test_ipc_name_preserved(self) -> None:
        self.assertIn("dynamicIslandShowExpandedSummary", self.shell)

    def test_legacy_summary_click_migrates(self) -> None:
        self.assertIn("normalizeDynamicIslandClickAction", self.settings)
        self.assertIn('v === "summary"', self.settings)
        self.assertIn("control_center", self.settings)
        self.assertNotIn('"summary"', self.page)
        # Runtime click path opens control center.
        self.assertIn('case "summary":', self.island)
        body = re.search(r'case "summary":([\s\S]*?)break;', self.island)
        self.assertIsNotNone(body)
        self.assertIn("openControlCenterRequested", body.group(1))

    def test_swipe_no_summary_page(self) -> None:
        self.assertNotIn("expanded_summary", self.ownership)
        self.assertIn("Left swipe no longer opens a duplicated summary page", self.ownership)

    def test_workspace_dedicated_scene(self) -> None:
        self.assertTrue(WORKSPACE.is_file())
        self.assertIn("DynamicIslandWorkspaceView", self.content)
        self.assertIn("workspaceActive", self.content)
        self.assertNotIn("id: detailRow", self.content)
        self.assertNotIn("standardDetailActive", self.content)
        self.assertNotIn("summaryExpandedContentVisible", self.content)
        self.assertNotIn("summaryBatteryPercent", self.content)
        self.assertNotIn("summaryBatteryPercent", self.overlay)
        self.assertNotIn("summaryBatteryPercent", self.island)
        self.assertIn("shouldShowWorkspaceTransient", self.island)
        self.assertIn("dynamicIslandWorkspaceFeedback", self.settings)
        # Opt-in must be readable on DesktopSettings root (not adapter-only).
        self.assertIn(
            "readonly property bool dynamicIslandWorkspaceFeedback:",
            self.settings,
        )
        self.assertIn("function setDynamicIslandWorkspaceFeedback", self.settings)
        self.assertIn("setDynamicIslandWorkspaceFeedback", self.page)
        self.assertIn("workspaceCount", self.island)
        self.assertIn("workspaceCount: root.workspaceCount", self.content)

    def test_summary_migration_marks_changed(self) -> None:
        # Migration must set changed=true so sanitize writes the adapter.
        self.assertIn(
            'settingsAdapter.dynamicIslandLeftClickAction = "control_center"',
            self.settings,
        )
        body = self.settings
        # After each summary assignment, changed = true appears nearby.
        self.assertRegex(
            body,
            r'dynamicIslandLeftClickAction === "summary"[\s\S]{0,120}?changed = true',
        )
        self.assertRegex(
            body,
            r'dynamicIslandRightClickAction === "summary"[\s\S]{0,120}?changed = true',
        )

    def test_workspace_direction_wired(self) -> None:
        self.assertIn("transientWorkspaceDirection", self.island)
        self.assertIn("workspaceDirection", self.overlay)
        self.assertIn("workspaceDirection", self.content)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
