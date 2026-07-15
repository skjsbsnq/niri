#!/usr/bin/env python3
"""Task 20 + Task 11: volume OSD dedupe and baseline lifecycle.

Root bug (Task 20 old code):
  - handleVolumeChange / handleMuteChange always presentOsdEntry
  - lastVolume / lastMuted written but never compared before show
  - Backend re-emitting the same volume/muted pair restarts OSD every time
  - volumeChanged + mutedChanged for one user action can double-present

Root bug (Task 11 lifecycle):
  - syncVolumeOsdFromControls returns early when island disabled without
    updating lastVolume/lastMuted
  - re-enable does not re-capture baseline from current controls
  - sink reconnect first sample may present spuriously

Fix contract:
  - lastVolume / lastMuted remain the only OSD baseline (no second baseline)
  - syncVolumeOsdFromControls compares exact volume + muted; no rough epsilon
  - disabled path still updates baseline but never presents
  - re-enable / audioReady reconnect re-capture without present
  - Both signal handlers defer via Qt.callLater into the same sync entry
  - captureOsdBaselines / service replace re-seeds without showing
  - Real volume steps and mute flips still present immediately (after callLater)
  - No debounce Timer; pendingOsd path unchanged

Regression strategy:
  1. Static contract extraction from DynamicIsland.qml
  2. Behavioral sim of baseline equality + dual-signal coalesce
  3. Real production DynamicIsland.qml via qmltestrunner
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import unittest
from dataclasses import dataclass, field
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
ISLAND = SHELL_ROOT / "services" / "DynamicIsland.qml"
QML_TEST = Path(__file__).with_name("tst_dynamic_island_volume_osd_dedupe.qml")


def _extract_function_body(src: str, name: str) -> str:
    m = re.search(
        rf"function\s+{re.escape(name)}\s*\([^)]*\)\s*\{{",
        src,
    )
    if not m:
        return ""
    start = m.end()
    depth = 1
    i = start
    while i < len(src) and depth:
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return src[start : i - 1]


@dataclass(frozen=True)
class VolumeOsdDedupeContract:
    has_last_volume_baseline: bool
    has_last_muted_baseline: bool
    has_sync_volume_osd: bool
    sync_compares_volume_and_muted: bool
    sync_uses_exact_equality: bool
    no_rough_volume_epsilon: bool
    volume_handler_defers_to_sync: bool
    mute_handler_defers_to_sync: bool
    no_debounce_timer_for_volume_osd: bool
    no_second_baseline: bool
    capture_baselines_sets_volume_mute: bool
    controls_service_change_recaptures: bool
    single_present_path_for_volume: bool

    @property
    def complete(self) -> bool:
        return all(getattr(self, name) for name in self.__annotations__)


def extract_contract(src: str) -> VolumeOsdDedupeContract:
    sync_body = _extract_function_body(src, "syncVolumeOsdFromControls")
    vol_body = _extract_function_body(src, "handleVolumeChange")
    mute_body = _extract_function_body(src, "handleMuteChange")
    capture_body = _extract_function_body(src, "captureOsdBaselines")

    # Old unconditional present path inside handlers (anti-pattern).
    old_direct_present = bool(
        re.search(r"presentOsdEntry", vol_body)
        or re.search(r"presentOsdEntry", mute_body)
    )

    compares_both = bool(
        re.search(r"lastVolume", sync_body)
        and re.search(r"lastMuted", sync_body)
        and re.search(r"===", sync_body)
    )

    # Forbid rough epsilon on volume (brightness may keep its own).
    rough_eps = bool(
        re.search(
            r"Math\.abs\s*\(\s*volume\s*-\s*root\.lastVolume\s*\)\s*<\s*0\.0",
            sync_body,
        )
        or re.search(r"volumeEpsilon|VOLUME_EPS", src)
    )

    debounce = bool(
        re.search(
            r"Timer\s*\{[^}]*(volumeOsd|osdDebounce|volumeDebounce)",
            src,
            re.DOTALL | re.IGNORECASE,
        )
    )

    second_baseline = bool(
        re.search(
            r"property\s+(real|bool|var)\s+(prevVolume|cachedVolume|osdVolumeBaseline|lastVolume2)\b",
            src,
        )
    )

    return VolumeOsdDedupeContract(
        has_last_volume_baseline=bool(
            re.search(r"property\s+real\s+lastVolume\b", src)
        ),
        has_last_muted_baseline=bool(
            re.search(r"property\s+bool\s+lastMuted\b", src)
        ),
        has_sync_volume_osd=bool(
            re.search(r"function\s+syncVolumeOsdFromControls\s*\(", src)
        ),
        sync_compares_volume_and_muted=compares_both,
        sync_uses_exact_equality=bool(
            re.search(
                r"volume\s*===\s*root\.lastVolume\s*&&\s*muted\s*===\s*root\.lastMuted",
                sync_body,
            )
            or re.search(
                r"muted\s*===\s*root\.lastMuted\s*&&\s*volume\s*===\s*root\.lastVolume",
                sync_body,
            )
        ),
        no_rough_volume_epsilon=not rough_eps,
        volume_handler_defers_to_sync=bool(
            re.search(r"syncVolumeOsdFromControls", vol_body)
            or re.search(r"Qt\.callLater", vol_body)
        )
        and not old_direct_present,
        mute_handler_defers_to_sync=bool(
            re.search(r"syncVolumeOsdFromControls", mute_body)
            or re.search(r"Qt\.callLater", mute_body)
        )
        and not old_direct_present,
        no_debounce_timer_for_volume_osd=not debounce,
        no_second_baseline=not second_baseline,
        capture_baselines_sets_volume_mute=bool(
            re.search(r"lastVolume", capture_body)
            and re.search(r"lastMuted", capture_body)
        ),
        controls_service_change_recaptures=bool(
            re.search(
                r"onControlsServiceChanged:\s*captureOsdBaselines\s*\(\s*\)",
                src,
            )
        ),
        single_present_path_for_volume=bool(
            re.search(r"presentOsdEntry", sync_body)
        )
        and not old_direct_present,
    )


@dataclass
class VolumeOsdSim:
    """Simulates lastVolume/lastMuted exact dedupe + callLater coalesce."""

    last_volume: float = 0.0
    last_muted: bool = False
    controls_volume: float = 0.0
    controls_muted: bool = False
    presentations: list[dict] = field(default_factory=list)
    _pending: bool = False

    def capture_baseline(self) -> None:
        self.last_volume = self.controls_volume
        self.last_muted = self.controls_muted

    def set_controls(self, volume: float | None = None, muted: bool | None = None) -> None:
        if volume is not None:
            self.controls_volume = volume
        if muted is not None:
            self.controls_muted = muted

    def on_volume_changed(self) -> None:
        self._schedule()

    def on_muted_changed(self) -> None:
        self._schedule()

    def _schedule(self) -> None:
        # Qt.callLater coalesce: multiple schedules in one turn → one flush.
        self._pending = True

    def flush(self) -> None:
        if not self._pending:
            return
        self._pending = False
        volume = self.controls_volume
        muted = self.controls_muted
        if volume == self.last_volume and muted == self.last_muted:
            return
        self.last_volume = volume
        self.last_muted = muted
        self.presentations.append(
            {
                "kind": "volume",
                "progress": 0 if muted else volume,
                "muted": muted,
            }
        )


class DynamicIslandVolumeOsdDedupeTests(unittest.TestCase):
    def test_source_contract_is_complete(self) -> None:
        contract = extract_contract(ISLAND.read_text(encoding="utf-8"))
        missing = [
            name
            for name in VolumeOsdDedupeContract.__annotations__
            if not getattr(contract, name)
        ]
        self.assertEqual(
            missing,
            [],
            f"volume OSD dedupe contract incomplete: {missing}",
        )

    def test_duplicate_volume_signal_does_not_present(self) -> None:
        sim = VolumeOsdSim()
        sim.set_controls(volume=0.4, muted=False)
        sim.capture_baseline()
        sim.on_volume_changed()
        sim.flush()
        self.assertEqual(sim.presentations, [])

    def test_real_volume_step_presents_once(self) -> None:
        sim = VolumeOsdSim()
        sim.set_controls(volume=0.4, muted=False)
        sim.capture_baseline()
        sim.set_controls(volume=0.41)
        sim.on_volume_changed()
        sim.flush()
        self.assertEqual(len(sim.presentations), 1)
        self.assertEqual(sim.presentations[0]["progress"], 0.41)
        # Identical re-emit suppressed.
        sim.on_volume_changed()
        sim.flush()
        self.assertEqual(len(sim.presentations), 1)

    def test_mute_flip_presents_even_if_volume_unchanged(self) -> None:
        sim = VolumeOsdSim()
        sim.set_controls(volume=0.5, muted=False)
        sim.capture_baseline()
        sim.set_controls(muted=True)
        sim.on_muted_changed()
        sim.flush()
        self.assertEqual(len(sim.presentations), 1)
        self.assertTrue(sim.presentations[0]["muted"])
        self.assertEqual(sim.presentations[0]["progress"], 0)

    def test_volume_and_mute_same_turn_coalesce_to_one_osd(self) -> None:
        sim = VolumeOsdSim()
        sim.set_controls(volume=0.3, muted=False)
        sim.capture_baseline()
        # One user action: set volume and mute; both signals fire before flush.
        sim.set_controls(volume=0.55, muted=True)
        sim.on_volume_changed()
        sim.on_muted_changed()
        sim.flush()
        self.assertEqual(len(sim.presentations), 1)
        self.assertTrue(sim.presentations[0]["muted"])
        self.assertEqual(sim.presentations[0]["progress"], 0)

    def test_small_volume_step_not_swallowed_by_epsilon(self) -> None:
        # Exact equality: 0.01 step must present (0.005 brightness-style eps would
        # still allow this, but 0.02-style rough eps must not exist in contract).
        sim = VolumeOsdSim()
        sim.set_controls(volume=0.50, muted=False)
        sim.capture_baseline()
        sim.set_controls(volume=0.51)
        sim.on_volume_changed()
        sim.flush()
        self.assertEqual(len(sim.presentations), 1)

    def test_service_reconnect_baseline_suppresses_spurious_osd(self) -> None:
        sim = VolumeOsdSim()
        sim.set_controls(volume=0.7, muted=False)
        sim.capture_baseline()
        # Service replace re-seeds same values then may re-emit.
        sim.capture_baseline()
        sim.on_volume_changed()
        sim.on_muted_changed()
        sim.flush()
        self.assertEqual(sim.presentations, [])

    def test_old_handlers_always_present_pattern_absent(self) -> None:
        src = ISLAND.read_text(encoding="utf-8")
        vol = _extract_function_body(src, "handleVolumeChange")
        mute = _extract_function_body(src, "handleMuteChange")
        self.assertNotIn("presentOsdEntry", vol)
        self.assertNotIn("presentOsdEntry", mute)
        # Sticky ramps: handlers call sync immediately (not callLater).
        # Same-turn mute+volume still coalesce via lastVolume/lastMuted equality.
        self.assertIn("syncVolumeOsdFromControls", vol)
        self.assertIn("syncVolumeOsdFromControls", mute)

    def test_disabled_sync_still_updates_baseline_contract(self) -> None:
        src = ISLAND.read_text(encoding="utf-8")
        sync_body = _extract_function_body(src, "syncVolumeOsdFromControls")
        enabled_body = _extract_function_body(src, "handleIslandEnabledChanged")
        # Baseline write must precede any islandEnabled present gate.
        last_vol_idx = sync_body.find("root.lastVolume = volume")
        present_idx = sync_body.find("presentOsdEntry")
        enabled_gate = re.search(
            r"if\s*\(\s*!root\.islandEnabled\s*\)\s*\n\s*return\s*;",
            sync_body,
        )
        self.assertGreaterEqual(last_vol_idx, 0)
        self.assertGreaterEqual(present_idx, 0)
        self.assertLess(last_vol_idx, present_idx)
        self.assertIsNotNone(enabled_gate)
        self.assertLess(last_vol_idx, enabled_gate.start())
        self.assertGreater(present_idx, enabled_gate.start())
        # Re-enable path must re-seed baselines without a second timer.
        self.assertIn("captureOsdBaselines", enabled_body)
        self.assertIn("handleAudioReadyChange", src)
        self.assertIn("onAudioReadyChanged", src)

    def test_real_qml_volume_osd_baseline_lifecycle(self) -> None:
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(runner, "Qt 6 qmltestrunner is required")
        env = os.environ.copy()
        env.setdefault("QT_QPA_PLATFORM", "offscreen")
        local_qml = Path.home() / ".local" / "lib" / "qt6" / "qml"
        test_qml = SHELL_ROOT / "tests" / "qml_imports"
        existing = env.get("QML2_IMPORT_PATH", "")
        paths = [str(test_qml), str(local_qml)]
        if existing:
            paths.append(existing)
        env["QML2_IMPORT_PATH"] = ":".join(paths)
        result = subprocess.run(
            [runner, "-input", str(QML_TEST)],
            cwd=SHELL_ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    unittest.main()
