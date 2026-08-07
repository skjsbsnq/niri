#!/usr/bin/env python3
"""T09 TahoeGlass completion/rejection feedback source contracts."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SHELL_ROOT = REPO_ROOT / "tahoe-shell"


class TahoeGlassFeedbackContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.protocol = (REPO_ROOT / "protocols/tahoe-glass-v1.xml").read_text(encoding="utf-8")
        cls.qml_hpp = (
            REPO_ROOT / "quickshell/src/wayland/tahoe_glass/qml.hpp"
        ).read_text(encoding="utf-8")
        cls.qml_cpp = (
            REPO_ROOT / "quickshell/src/wayland/tahoe_glass/qml.cpp"
        ).read_text(encoding="utf-8")
        cls.dock = (SHELL_ROOT / "components/Dock.qml").read_text(encoding="utf-8")
        cls.overlay = (SHELL_ROOT / "components/DynamicIslandOverlay.qml").read_text(
            encoding="utf-8"
        )
        cls.motion = (SHELL_ROOT / "components/DynamicIslandMotion.js").read_text(
            encoding="utf-8"
        )

    def test_v5_protocol_has_capability_serial_and_terminal_feedback(self) -> None:
        self.assertRegex(
            self.protocol,
            r'<interface name="tahoe_glass_surface_v1" version="5">',
        )
        self.assertRegex(self.protocol, r'<request name="set_transform_serial" since="5">')
        self.assertRegex(self.protocol, r'<event name="capabilities" since="5">')
        self.assertRegex(self.protocol, r'<event name="transform_feedback" since="5">')
        self.assertRegex(
            self.protocol,
            r'<entry name="invalid_serial" value="1" since="5"',
        )
        for status in ("completed", "rejected", "superseded", "cancelled"):
            self.assertRegex(self.protocol, rf'<entry name="{status}" value="\d+"')

    def test_quickshell_exposes_one_feedback_authority(self) -> None:
        self.assertIn(
            "Q_PROPERTY(bool feedbackAvailable READ feedbackAvailable NOTIFY feedbackAvailableChanged)",
            self.qml_hpp,
        )
        self.assertIn(
            "Q_PROPERTY(bool transformInFlight READ transformInFlight NOTIFY transformInFlightChanged)",
            self.qml_hpp,
        )
        self.assertIn("void transformFinished(quint32 serial, quint32 status);", self.qml_hpp)
        self.assertIn("handleTransformFeedback", self.qml_cpp)
        self.assertNotIn("TahoeGlassV5", self.qml_hpp + self.qml_cpp)

    def test_shell_gates_compositor_paths_on_feedback_capability(self) -> None:
        self.assertIn(
            "readonly property bool compositorSlide: root.TahoeGlass.feedbackAvailable",
            self.dock,
        )
        self.assertIn(
            "readonly property bool compositorMorph: root.TahoeGlass.feedbackAvailable",
            self.overlay,
        )

    def test_dynamic_island_mask_releases_from_matching_terminal_event(self) -> None:
        self.assertNotIn("morphMaskHoldTimer", self.overlay)
        self.assertNotIn("v2CompositorMorphMaskHoldMs", self.motion)
        self.assertIn("property real morphMaskSerial: 0", self.overlay)
        self.assertIn("function onTransformFinished(serial, status)", self.overlay)
        self.assertRegex(
            self.overlay,
            re.compile(
                r"if \(serial !== root\.morphMaskSerial\)\s*return;.*?"
                r"if \(root\.TahoeGlass\.transformInFlight\).*?"
                r"root\.morphMaskSerial = root\.TahoeGlass\.activeTransformSerial;.*?"
                r"root\.releaseMorphMask\(\)",
                re.S,
            ),
        )

    def test_dynamic_island_mask_serial_preserves_full_uint32_domain(self) -> None:
        self.assertNotIn("property int morphMaskSerial", self.overlay)
        self.assertIn("property real morphMaskSerial: 0", self.overlay)
        for serial in (0x7FFFFFFF, 0x80000000, 0xFFFFFFFF):
            stored = float(serial)
            self.assertEqual(int(stored), serial)
            self.assertEqual(stored, float(serial))


if __name__ == "__main__":
    unittest.main()
