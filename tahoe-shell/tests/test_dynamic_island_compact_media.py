#!/usr/bin/env python3
"""T16: compact media scene — art, title, play/pause, progress, width reserve."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
VIEW = SHELL_ROOT / "components" / "DynamicIslandCompactMediaView.qml"
CONTENT = SHELL_ROOT / "components" / "DynamicIslandContent.qml"
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
ISLAND = SHELL_ROOT / "services" / "DynamicIsland.qml"
CONTROLS = SHELL_ROOT / "services" / "Controls.qml"
MOTION = SHELL_ROOT / "components" / "DynamicIslandMotion.js"
TOPBAR = SHELL_ROOT / "components" / "TopBar.qml"
MEDIA_VIEW = SHELL_ROOT / "components" / "DynamicIslandMediaView.qml"


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


class DynamicIslandCompactMediaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.view = _read(VIEW)
        cls.content = _read(CONTENT)
        cls.overlay = _read(OVERLAY)
        cls.island = _read(ISLAND)
        cls.controls = _read(CONTROLS)
        cls.motion = _read(MOTION)
        cls.topbar = _read(TOPBAR)
        cls.media_view = _read(MEDIA_VIEW)

    def test_view_layout_tokens(self) -> None:
        self.assertIn("artSize: 22", self.view)
        self.assertIn("rowSpacing: 8", self.view)
        self.assertIn("height: 2", self.view)  # optional progress
        self.assertIn("ElideRight", self.view)
        self.assertIn("maximumLineCount: 1", self.view)
        self.assertIn("font.letterSpacing: 0", self.view)
        self.assertIn("font.pixelSize: 13", self.view)
        self.assertIn("font.weight: Font.DemiBold", self.view)
        # Trailing play/pause via TahoeSymbol (not Canvas).
        self.assertIn("TahoeSymbol", self.view)
        self.assertIn("isPlaying", self.view)
        self.assertIn('\\ue034"', self.view)  # pause while playing
        self.assertIn('\\ue037"', self.view)  # play when paused

    def test_no_artist_in_compact(self) -> None:
        # Standalone CompactMediaView must not render artist (expanded-only).
        self.assertNotIn("trackArtist", self.view)
        self.assertNotIn("property string artist", self.view)
        # Production Content no longer hosts CompactMediaView; unified MediaView
        # shows artist only via expandProgress (pArtist).

    def test_no_fake_visualizer(self) -> None:
        # No bar spectrum / sine fake audio (comments may mention the ban).
        self.assertNotIn("visualizerPhase", self.view)
        self.assertNotIn("visualizerLevel", self.view)
        self.assertNotIn("Math.sin", self.view)
        self.assertNotIn("Repeater", self.view)
        # Compact must not own a media Timer (position comes from Controls).
        self.assertNotIn("Timer {", self.view)
        self.assertNotIn("activePlayer", self.view)

    def test_art_gated_on_visibility(self) -> None:
        # Hidden / non-owner outputs must not load album art.
        self.assertIn('source: (root.visible && root.showArt) ? root.safeArtUrl : ""', self.view)
        self.assertIn("asynchronous: true", self.view)
        self.assertIn("safeArtUrl", self.view)
        self.assertIn("http://", self.view)
        self.assertIn("file://", self.view)

    def test_progress_optional_and_supported(self) -> None:
        # Standalone compact view still has optional progress rail.
        self.assertIn("progressSupported", self.view)
        self.assertIn("showProgress", self.view)
        self.assertIn("visible: root.showProgress", self.view)
        # Production unified media uses positionSupported + duration for rails.
        self.assertIn("positionSupported", self.media_view)
        self.assertIn("mediaPositionSupported", self.content)

    def test_content_hosts_compact_media_not_plain_label(self) -> None:
        # Production: unified DynamicIslandMediaView owns compact+expanded.
        self.assertIn("DynamicIslandMediaView", self.content)
        self.assertIn("compactMediaContentWidth", self.content)
        self.assertIn("mediaExpandProgress", self.content)
        self.assertIn("expandProgress", self.content)
        # Old single-line compactLabel path is gone.
        self.assertNotIn("id: compactLabel", self.content)
        # Clock still crossfades; media is Loader-hosted unified scene.
        self.assertIn("opacity: root.restingClockActive && root.compactContentVisible ? 1 : 0", self.content)
        self.assertIn("mediaLoaderActive", self.content)
        # CompactMediaView is not hosted in production Content.
        self.assertNotRegex(
            self.content,
            r"DynamicIslandCompactMediaView\s*\{",
        )

    def test_media_title_not_bound_to_display_text_or_clock(self) -> None:
        # Overlay must mirror Controls title, not contentDisplayText / fallbackTimeText.
        self.assertIn("dynamicIslandService.mediaTrackTitle", self.overlay)
        self.assertNotIn("mediaTrackTitle: contentDisplayText", self.overlay)
        # Unified media scene never feeds displayText into track title.
        media_block = re.search(
            r"DynamicIslandMediaView\s*\{[\s\S]*?\n        \}",
            self.content,
        )
        self.assertIsNotNone(media_block)
        block = re.sub(r"//[^\n]*", "", media_block.group(0))
        self.assertNotIn("displayText", block)
        self.assertNotIn("fallbackTimeText", block)
        self.assertIn("trackTitle:", block)
        self.assertIn("mediaTrackTitle", block)
        # Service exposes stable Controls field.
        self.assertIn("mediaTrackTitle:", self.island)
        self.assertIn("controlsService.trackTitle", self.island)
        # Exit latch so player disappear keeps last title during fade.
        self.assertIn("latchedCompactMediaTitle", self.content)
        self.assertIn("latchedCompactMediaWidth", self.content)

    def test_reduced_motion_uses_token(self) -> None:
        # T19: content helpers encapsulate reduced motion (v2ReducedContentMs).
        self.assertIn("contentExitMs", self.content)
        self.assertIn("contentTravelPx", self.content)
        self.assertIn("compactContentMotionMs", self.content)

    def test_overlay_content_driven_width_and_reserve(self) -> None:
        body = _function_body(self.overlay, "compactMediaTargetWidth")
        self.assertIn("compactMediaContentWidth", body)
        self.assertIn("v2CompactMediaWidthMin", body)
        self.assertIn("v2CompactMediaWidthMax", body)
        self.assertIn("return compactMediaTargetWidth()", self.overlay)
        # TopBar reserve still covers max compact media (T12 freeze).
        self.assertIn(
            "centerReserveWidth: IslandMotion.v2CompactMediaWidthMax",
            self.topbar,
        )
        self.assertIn("var v2CompactMediaWidthMax = 224", self.motion)
        self.assertIn("var v2CompactMediaWidthMin = 200", self.motion)
        self.assertIn("var v2CompactMediaHeight = 36", self.motion)

    def test_title_width_capped_for_geometry_stability(self) -> None:
        self.assertIn("titleMaxWidth", self.view)
        self.assertIn("v2CompactMediaWidthMax", self.view)
        self.assertIn("contentWidth", self.view)
        # Clamp expression keeps capsule within 200–224.
        body = _function_body(self.overlay, "compactMediaTargetWidth")
        self.assertIn("clampInt", body)

    def test_player_selection_stays_in_controls(self) -> None:
        # Compact path must not re-implement MPRIS selection in code.
        for src in (self.view, self.content):
            # Strip comments so documentation bans do not trip the check.
            code = re.sub(r"//[^\n]*", "", src)
            self.assertNotIn("Mpris.players", code)
            self.assertNotIn("lastActivePlayerDbusName", code)
            self.assertNotIn("selectActivePlayer", code)
        # Controls remains the owner of selection + track fields.
        self.assertIn("lastActivePlayerDbusName", self.controls)
        self.assertIn("trackArtUrl", self.controls)
        self.assertIn("trackTitle", self.controls)
        self.assertIn("isPlaying", self.controls)
        # Island only mirrors Controls presentation fields.
        self.assertIn("mediaArtUrl: controlsService", self.island)
        self.assertIn("mediaPlaying: controlsService", self.island)

    def test_accent_from_theme_not_hardcoded_purple(self) -> None:
        self.assertIn("Theme.accent", self.overlay)
        self.assertIn("islandProgressTrack", self.overlay)
        self.assertNotIn("#b56cff", self.view)
        self.assertNotIn("#b56cff", self.content)

    def test_progress_fill_is_monochrome_not_accent(self) -> None:
        # Compact bottom progress shares islandProgressFill with expanded/OSD.
        self.assertIn("progressFillColor", self.view)
        self.assertIn("color: root.progressFillColor", self.view)
        self.assertIn("progressFillColor: root.progressFillColor", self.content)
        self.assertIn("Theme.islandProgressFill", self.overlay)
        # Progress paint path must not use accentColor.
        progress = re.search(
            r"id:\s*progressTrack[\s\S]*?\n    \}",
            self.view,
        )
        self.assertIsNotNone(progress)
        self.assertIn("progressFillColor", progress.group(0))
        self.assertNotIn("accentColor", progress.group(0))

    def test_media_unavailable_smooth_clock_restore_path(self) -> None:
        # R07: clock and media crossfade in place (opacity swap), so media→clock
        # is not a hard cut black frame. Latched title/width keep the fading
        # media scene stable while the player disappears.
        self.assertIn("latchedCompactMediaTitle", self.content)
        self.assertIn("latchedCompactMediaWidth", self.content)
        self.assertIn("contentExitMs", self.content)
        # Reducer drops media presentation when hasMedia is false (existing).
        self.assertIn("resting_media", self.island)

    def test_expanded_media_still_present_for_t17(self) -> None:
        # T16 must not delete expanded media path.
        self.assertIn("DynamicIslandMediaView", self.content)
        self.assertIn("mediaLoaderActive", self.content)
        self.assertTrue(MEDIA_VIEW.is_file())


if __name__ == "__main__":
    raise SystemExit(unittest.main())
