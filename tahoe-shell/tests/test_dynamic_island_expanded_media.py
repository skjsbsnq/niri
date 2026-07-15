#!/usr/bin/env python3
"""T17: expanded media scene — art, timeline, TahoeSymbol controls, lifecycle."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
VIEW = SHELL_ROOT / "components" / "DynamicIslandMediaView.qml"
CONTENT = SHELL_ROOT / "components" / "DynamicIslandContent.qml"
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
ISLAND = SHELL_ROOT / "services" / "DynamicIsland.qml"
CONTROLS = SHELL_ROOT / "services" / "Controls.qml"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class DynamicIslandExpandedMediaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.view = _read(VIEW)
        cls.content = _read(CONTENT)
        cls.overlay = _read(OVERLAY)
        cls.island = _read(ISLAND)
        cls.controls = _read(CONTROLS)

    def test_layout_tokens(self) -> None:
        self.assertIn("badgeSize: 64", self.view)
        self.assertIn("playSize: 36", self.view)
        self.assertIn("skipSize: 32", self.view)
        self.assertIn("controlHit: 44", self.view)
        self.assertIn("font.pixelSize: 16", self.view)
        self.assertIn("font.pixelSize: 12", self.view)
        self.assertIn("font.letterSpacing: 0", self.view)
        self.assertIn("radius: 12", self.view)
        self.assertIn("formatTime", self.view)
        self.assertIn("--:--", self.view)

    def test_no_canvas_and_no_fake_visualizer(self) -> None:
        code = re.sub(r"//[^\n]*", "", self.view)
        self.assertNotIn("Canvas", code)
        self.assertNotIn("visualizerTimer", code)
        self.assertNotIn("visualizerPhase", code)
        self.assertNotIn("visualizerLevel", code)
        self.assertNotIn("Math.sin", code)
        self.assertNotIn("id: visualizerBox", code)
        self.assertNotIn("Timer {", code)
        # No second media controller / MPRIS walk.
        self.assertNotIn("Mpris.players", code)
        self.assertNotIn("activePlayer", code)

    def test_tahoesymbol_controls(self) -> None:
        self.assertIn("TahoeSymbol", self.view)
        self.assertEqual(self.view.count("MediaControlButton {"), 3)
        self.assertIn('role: "prev"', self.view)
        self.assertIn('role: "next"', self.view)
        self.assertIn("playPauseRequested", self.view)
        self.assertIn("previousRequested", self.view)
        self.assertIn("nextRequested", self.view)

    def test_media_glyphs_match_control_center(self) -> None:
        # ControlCenter media transport: prev e045, next e044, play e037, pause e034.
        self.assertIn('\\ue045"', self.view)
        self.assertIn('\\ue044"', self.view)
        self.assertIn('\\ue037"', self.view)
        self.assertIn('\\ue034"', self.view)
        # No hand-drawn pause bars or wrong play/skip remapping.
        code = re.sub(r"//[^\n]*", "", self.view)
        self.assertNotIn("width: 4", code)  # old pause-bar rectangles
        self.assertNotIn('\\ue029"', code)

    def test_disabled_absorbs_hits(self) -> None:
        self.assertIn("enabled: true", self.view)
        self.assertIn("preventStealing: true", self.view)
        self.assertIn("mouseEvent.accepted = true", self.view)
        self.assertIn("beginInteraction", self.view)
        self.assertIn("endInteraction", self.view)
        self.assertIn("Component.onDestruction", self.view)
        self.assertIn("onVisibleChanged", self.view)

    def test_art_gated_on_visibility(self) -> None:
        self.assertIn('source: (root.visible && root.showArt) ? root.safeArtUrl : ""', self.view)
        self.assertIn("asynchronous: true", self.view)
        self.assertNotIn("Blur", self.view)
        self.assertNotIn("MultiEffect", self.view)

    def test_accent_not_hardcoded_purple(self) -> None:
        self.assertNotIn("#b56cff", self.view)
        self.assertIn("accentColor", self.view)
        self.assertIn("accentColor: root.accentColor", self.content)

    def test_timeline_readonly_without_seek_api(self) -> None:
        # T17 optional scrubber only if Controls has seek — we keep read-only.
        self.assertNotIn("seek(", self.view)
        self.assertNotIn("setPosition", self.view)
        self.assertIn("safeProgress", self.view)
        self.assertIn("showTimeline", self.view)

    def test_no_second_media_controller(self) -> None:
        self.assertNotIn("IslandMprisController", self.view)
        self.assertNotIn("IslandMprisController", self.content)
        self.assertIn("mediaTogglePlayPause", self.island)
        self.assertIn("togglePlayPause", self.controls)

    def test_content_wires_controls_lifecycle(self) -> None:
        self.assertIn("onMediaControlPressed:", self.overlay)
        self.assertIn("setUserInteracting(true)", self.overlay)
        self.assertIn("onMediaControlReleased:", self.overlay)
        self.assertIn("setUserInteracting(false)", self.overlay)
        self.assertIn("mediaExpandedContentVisible", self.content)
        self.assertIn("mediaLoaderActive", self.content)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
