#!/usr/bin/env python3
"""Full media timeline seek: Controls MPRIS + island scrubber wiring.

Locks Task 3:
- canSeek / setTrackPosition / optimistic display on Controls (single MPRIS owner)
- DynamicIsland media*Seek helpers (no second controller)
- Overlay/Content signal plumbing
- Expanded MediaView MouseArea scrub with preventStealing
- Width Behavior disabled while scrubbing
- No parallel IslandMprisController / playerctl path
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
CONTROLS = SHELL / "services" / "Controls.qml"
ISLAND = SHELL / "services" / "DynamicIsland.qml"
OVERLAY = SHELL / "components" / "DynamicIslandOverlay.qml"
CONTENT = SHELL / "components" / "DynamicIslandContent.qml"
VIEW = SHELL / "components" / "DynamicIslandMediaView.qml"
COMPACT = SHELL / "components" / "DynamicIslandCompactMediaView.qml"


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


class DynamicIslandMediaSeekTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.controls = _read(CONTROLS)
        cls.island = _read(ISLAND)
        cls.overlay = _read(OVERLAY)
        cls.content = _read(CONTENT)
        cls.view = _read(VIEW)
        cls.compact = _read(COMPACT)

    def test_controls_can_seek_and_set_position(self) -> None:
        self.assertIn("readonly property bool canSeek", self.controls)
        self.assertIn("canSeek", self.controls)
        self.assertIn("function setTrackPosition", self.controls)
        self.assertIn("function beginTrackSeek", self.controls)
        self.assertIn("function previewTrackProgress", self.controls)
        self.assertIn("function commitTrackProgress", self.controls)
        self.assertIn("function cancelTrackSeek", self.controls)
        body = _function_body(self.controls, "setTrackPosition")
        self.assertIn("p.position", body)
        self.assertIn("canSeek", body)
        # Optimistic scrub state.
        self.assertIn("trackSeeking", self.controls)
        self.assertIn("trackPositionDisplay", self.controls)
        self.assertIn("trackProgressDisplay", self.controls)
        # Poll pauses while seeking so the bar does not fight the finger.
        self.assertIn("!root.trackSeeking", self.controls)

    def test_single_active_player_changed_merges_memory_and_seek(self) -> None:
        # QML does not stack duplicate onActivePlayerChanged — exactly one.
        self.assertEqual(self.controls.count("onActivePlayerChanged:"), 1)
        # Merged body keeps player memory and cancels seek on loss/switch.
        m = re.search(
            r"onActivePlayerChanged:\s*\{([\s\S]*?)\n    \}",
            self.controls,
        )
        self.assertIsNotNone(m)
        body = m.group(1)
        self.assertIn("lastActivePlayerDbusName", body)
        self.assertIn("cancelTrackSeek", body)
        self.assertIn("trackSeeking", body)

    def test_island_mirrors_seek_without_owning_mpris(self) -> None:
        self.assertIn("canSeek", self.island)
        self.assertIn("mediaSeeking", self.island)
        self.assertIn("function mediaBeginSeek", self.island)
        self.assertIn("function mediaPreviewSeekProgress", self.island)
        self.assertIn("function mediaCommitSeekProgress", self.island)
        self.assertIn("function mediaCancelSeek", self.island)
        # Prefer display fields while seeking.
        self.assertIn("trackPositionDisplay", self.island)
        self.assertIn("trackProgressDisplay", self.island)
        code = re.sub(r"//[^\n]*", "", self.island)
        self.assertNotIn("Mpris.players", code)
        self.assertNotIn("IslandMprisController", code)

    def test_overlay_content_plumbing(self) -> None:
        self.assertIn("canSeek: root.canSeek", self.overlay)
        self.assertIn("mediaSeeking: root.mediaSeeking", self.overlay)
        self.assertIn("onMediaSeekBeginRequested", self.overlay)
        self.assertIn("onMediaSeekPreviewRequested", self.overlay)
        self.assertIn("onMediaSeekCommitRequested", self.overlay)
        self.assertIn("onMediaSeekCancelRequested", self.overlay)
        self.assertIn("mediaBeginSeek", self.overlay)
        self.assertIn("mediaCommitSeekProgress", self.overlay)
        self.assertIn("setUserInteracting(true)", self.overlay)
        # Content signals.
        self.assertIn("signal mediaSeekBeginRequested", self.content)
        self.assertIn("signal mediaSeekPreviewRequested", self.content)
        self.assertIn("signal mediaSeekCommitRequested", self.content)
        self.assertIn("signal mediaSeekCancelRequested", self.content)
        self.assertIn("canSeek: root.canSeek", self.content)
        self.assertIn("seeking: root.mediaSeeking", self.content)

    def test_view_scrubber_interaction(self) -> None:
        self.assertIn("id: seekArea", self.view)
        self.assertIn("scrubInteractive", self.view)
        self.assertIn("preventStealing: true", self.view)
        self.assertIn("function ratioAt", self.view)
        self.assertIn("function beginSeek", self.view)
        self.assertIn("function endSeek", self.view)
        self.assertIn("localSeeking", self.view)
        self.assertIn("localSeekRatio", self.view)
        # Behavior off while scrubbing AND while expand morph is in flight
        # (morph re-tween of pixel width looked like progress catching up).
        self.assertIn("!root.localSeeking", self.view)
        self.assertIn("!root.seeking", self.view)
        self.assertIn("root.p >= 0.98", self.view)
        self.assertIn("root.pTimeline >= 0.98", self.view)
        # Only interactive when canSeek.
        self.assertIn("root.canSeek", self.view)
        self.assertIn("root.scrubInteractive", self.view)
        # Cleanup on hide / destroy / canSeek loss.
        self.assertIn("onVisibleChanged", self.view)
        self.assertIn("onCanSeekChanged", self.view)
        self.assertIn("Component.onDestruction", self.view)

    def test_compact_progress_remains_display_only(self) -> None:
        # Compact 2px rail stays non-interactive (expanded owns scrub).
        code = re.sub(r"//[^\n]*", "", self.compact)
        self.assertNotIn("seekArea", code)
        self.assertNotIn("seekBeginRequested", code)
        self.assertNotIn("MouseArea", code)

    def test_no_parallel_seek_owner(self) -> None:
        for src in (self.view, self.content, self.overlay, self.island):
            code = re.sub(r"//[^\n]*", "", src)
            self.assertNotIn("IslandMprisController", code)
            self.assertNotIn("playerctl", code.lower())
        # Single Controls owner for MPRIS writes.
        self.assertIn("p.position = sec", self.controls)
        self.assertNotIn("function setTrackPosition", self.island)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
