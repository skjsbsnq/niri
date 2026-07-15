from __future__ import annotations

import json
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SELECTION = ROOT / "services" / "controls" / "MediaPlayerSelection.js"
CONTROLS_QML = ROOT / "services" / "Controls.qml"

# Mirror MprisPlaybackState enum values used by callers.
PLAYING = 1
PAUSED = 2
STOPPED = 0


NODE_HELPER = r"""
const fs = require("fs");
const vm = require("vm");
const modulePath = process.argv[1];
const source = fs.readFileSync(modulePath, "utf8").replace(/^\s*\.pragma library\s*\n/, "");
const context = {
  Array, Boolean, Date, JSON, Math, Number, Object, String, console, isFinite,
};
vm.createContext(context);
vm.runInContext(source, context, { filename: modulePath });
const request = JSON.parse(process.argv[2]);
const selected = context.selectActivePlayer(
  request.players || [],
  request.lastActiveDbusName || "",
  request.playingState
);
const result = {
  dbusName: selected ? String(selected.dbusName || "") : null,
  trackTitle: selected ? String(selected.trackTitle || "") : null,
  eligibleCount: context.collectEligiblePlayers(request.players || []).length,
};
process.stdout.write(JSON.stringify(result));
"""


def run_select(players: list[dict], last: str = "", playing_state=PLAYING) -> dict:
    if shutil.which("node") is None:
        raise unittest.SkipTest("node is required to execute MediaPlayerSelection.js")
    completed = subprocess.run(
        [
            "node",
            "-e",
            NODE_HELPER,
            str(SELECTION),
            json.dumps({
                "players": players,
                "lastActiveDbusName": last,
                "playingState": playing_state,
            }),
        ],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return json.loads(completed.stdout)


def player(
    dbus_name: str,
    *,
    state=PAUSED,
    title: str = "",
    can_play: bool = False,
    can_pause: bool = False,
    can_control: bool = False,
    is_playing: bool | None = None,
) -> dict:
    return {
        "dbusName": dbus_name,
        "playbackState": state,
        "trackTitle": title,
        "canPlay": can_play,
        "canPause": can_pause,
        "canTogglePlaying": can_play or can_pause,
        "canGoNext": False,
        "canGoPrevious": False,
        "canSeek": False,
        "canControl": can_control,
        "isPlaying": True if is_playing is True else (False if is_playing is False else (state == PLAYING)),
    }


class ControlsMprisSelectionTests(unittest.TestCase):
    def test_exports_and_controls_wiring(self) -> None:
        text = SELECTION.read_text(encoding="utf-8")
        for name in (
            "selectActivePlayer",
            "isPlayerEligible",
            "playerDbusName",
            "collectEligiblePlayers",
        ):
            self.assertIn(f"function {name}(", text)

        controls = CONTROLS_QML.read_text(encoding="utf-8")
        self.assertIn('import "controls/MediaPlayerSelection.js" as MediaPlayerSelection', controls)
        self.assertIn("property string lastActivePlayerDbusName", controls)
        self.assertIn("MediaPlayerSelection.selectActivePlayer", controls)
        self.assertIn("onActivePlayerChanged", controls)
        self.assertNotIn("IslandMprisController", controls)
        self.assertNotIn("MediaSession.qml", controls)

    def test_reorder_does_not_switch_remembered_paused(self) -> None:
        a = player("org.mpris.MediaPlayer2.A", state=PAUSED, title="Song A", can_play=True)
        b = player("org.mpris.MediaPlayer2.B", state=PAUSED, title="Song B", can_play=True)
        first = run_select([a, b], last="org.mpris.MediaPlayer2.B")
        self.assertEqual(first["dbusName"], "org.mpris.MediaPlayer2.B")
        reordered = run_select([b, a], last="org.mpris.MediaPlayer2.B")
        self.assertEqual(reordered["dbusName"], "org.mpris.MediaPlayer2.B")
        reordered2 = run_select([a, b], last="org.mpris.MediaPlayer2.B")
        self.assertEqual(reordered2["dbusName"], "org.mpris.MediaPlayer2.B")

    def test_playing_preempts_paused_remembered(self) -> None:
        paused = player("org.mpris.MediaPlayer2.A", state=PAUSED, title="A", can_play=True)
        playing = player("org.mpris.MediaPlayer2.B", state=PLAYING, title="B", can_pause=True)
        result = run_select([paused, playing], last="org.mpris.MediaPlayer2.A")
        self.assertEqual(result["dbusName"], "org.mpris.MediaPlayer2.B")

    def test_multiple_playing_prefers_remembered_then_stable_name(self) -> None:
        p_z = player("org.mpris.MediaPlayer2.Z", state=PLAYING, title="Z", can_pause=True)
        p_a = player("org.mpris.MediaPlayer2.A", state=PLAYING, title="A", can_pause=True)
        # No memory: stable dbusName → A before Z.
        result = run_select([p_z, p_a], last="")
        self.assertEqual(result["dbusName"], "org.mpris.MediaPlayer2.A")
        # Memory of Z while both playing keeps Z.
        result = run_select([p_z, p_a], last="org.mpris.MediaPlayer2.Z")
        self.assertEqual(result["dbusName"], "org.mpris.MediaPlayer2.Z")

    def test_current_player_disappear_selects_next(self) -> None:
        remaining = player("org.mpris.MediaPlayer2.B", state=PAUSED, title="B", can_play=True)
        result = run_select([remaining], last="org.mpris.MediaPlayer2.A")
        self.assertEqual(result["dbusName"], "org.mpris.MediaPlayer2.B")

    def test_metadata_late_arrival_becomes_eligible(self) -> None:
        bare = player("org.mpris.MediaPlayer2.A", state=STOPPED, title="", can_play=False)
        result = run_select([bare], last="")
        self.assertIsNone(result["dbusName"])
        self.assertEqual(result["eligibleCount"], 0)

        with_meta = player("org.mpris.MediaPlayer2.A", state=PAUSED, title="Late", can_play=False)
        result = run_select([with_meta], last="")
        self.assertEqual(result["dbusName"], "org.mpris.MediaPlayer2.A")

    def test_paused_player_with_track(self) -> None:
        no_title = player("org.mpris.MediaPlayer2.A", state=PAUSED, title="", can_play=True)
        with_title = player("org.mpris.MediaPlayer2.B", state=PAUSED, title="Track", can_play=False)
        # With no memory, prefer paused-with-track over controllable empty title
        # when both eligible: both eligible; pausedWithTrack path prefers title.
        result = run_select([no_title, with_title], last="")
        self.assertEqual(result["dbusName"], "org.mpris.MediaPlayer2.B")

    def test_no_players(self) -> None:
        result = run_select([], last="org.mpris.MediaPlayer2.A")
        self.assertIsNone(result["dbusName"])
        self.assertEqual(result["eligibleCount"], 0)

    def test_control_capability_without_title_is_eligible(self) -> None:
        ctrl = player("org.mpris.MediaPlayer2.A", state=STOPPED, title="", can_play=True)
        result = run_select([ctrl], last="")
        self.assertEqual(result["dbusName"], "org.mpris.MediaPlayer2.A")

    def test_ineligible_player_never_active(self) -> None:
        junk = player("org.mpris.MediaPlayer2.Junk", state=STOPPED, title="", can_play=False)
        good = player("org.mpris.MediaPlayer2.Good", state=PAUSED, title="Ok", can_play=True)
        result = run_select([junk, good], last="org.mpris.MediaPlayer2.Junk")
        self.assertEqual(result["dbusName"], "org.mpris.MediaPlayer2.Good")

    def test_remembered_invalid_name_clears_to_candidate(self) -> None:
        good = player("org.mpris.MediaPlayer2.Good", state=PAUSED, title="Ok", can_play=True)
        result = run_select([good], last="org.mpris.MediaPlayer2.Missing")
        self.assertEqual(result["dbusName"], "org.mpris.MediaPlayer2.Good")


if __name__ == "__main__":
    unittest.main()
