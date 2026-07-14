#!/usr/bin/env python3
"""Task 21 + Task 08: visualizer cadence and multi-screen ownership.

Root waste (old cadence):
  - visualizerTimer interval: 64ms while Behavior height duration: 120ms
  - Every tick retargets five NumberAnimations before they settle

Root waste (multi-screen, Task 08):
  - mediaContentVisible only checked global contentState
  - every output's MediaView became visible in expanded_media and ran Timer
  - only the target screen capsule was actually shown

Fix contract:
  - Single visualizerPhase owner; interval aligned via motion tokens
  - Timer only when isPlaying && visible && !reducedMotion
  - mediaContentVisible / expanded content gated with activeForScreen
  - Two MediaView instances: only the visible (target) phase advances
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import unittest
from dataclasses import dataclass
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
MEDIA_VIEW = SHELL_ROOT / "components" / "DynamicIslandMediaView.qml"
MOTION = SHELL_ROOT / "components" / "DynamicIslandMotion.js"
CONTENT = SHELL_ROOT / "components" / "DynamicIslandContent.qml"
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
QML_TEST = Path(__file__).with_name("tst_dynamic_island_visualizer_animation_align.qml")


def _timer_block(src: str, timer_id: str) -> str:
    m = re.search(rf"Timer\s*\{{\s*id:\s*{re.escape(timer_id)}\b", src)
    if not m:
        return ""
    start = m.start()
    depth = 0
    i = start
    begun = False
    while i < len(src):
        if src[i] == "{":
            depth += 1
            begun = True
        elif src[i] == "}":
            depth -= 1
            if begun and depth == 0:
                return src[start : i + 1]
        i += 1
    return ""


def _js_number(src: str, name: str) -> int | float | None:
    m = re.search(rf"var\s+{re.escape(name)}\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*;", src)
    if not m:
        return None
    raw = m.group(1)
    return float(raw) if "." in raw else int(raw)


@dataclass(frozen=True)
class VisualizerAlignContract:
    single_phase_owner: bool
    single_visualizer_timer: bool
    timer_gated_on_playing_visible_and_reduced: bool
    interval_uses_motion_token: bool
    phase_step_uses_motion_token: bool
    playing_duration_uses_motion_token: bool
    update_ms_gte_playing_duration: bool
    not_sub_animation_hardcoded_64: bool
    no_second_visualizer_timer: bool
    no_per_bar_phase: bool
    visualizer_still_present: bool
    reduced_motion_gates_timer: bool
    reduced_motion_static_bars: bool
    settings_wired_from_overlay: bool
    phase_angular_velocity_near_legacy: bool
    media_content_gated_by_active_for_screen: bool
    no_second_media_visibility_state: bool

    @property
    def complete(self) -> bool:
        return all(getattr(self, name) for name in self.__annotations__)


def extract_contract(
    media_src: str,
    motion_src: str,
    content_src: str = "",
    overlay_src: str = "",
) -> VisualizerAlignContract:
    timer = _timer_block(media_src, "visualizerTimer")
    timers = re.findall(r"Timer\s*\{\s*id:\s*(\w+)", media_src)
    visualizer_timers = [t for t in timers if "visualizer" in t.lower()]

    update_ms = _js_number(motion_src, "visualizerUpdateMs")
    playing_dur = _js_number(motion_src, "visualizerPlayingDuration")
    phase_step = _js_number(motion_src, "visualizerPhaseStep")

    hardcoded_64 = bool(
        re.search(
            r"id:\s*visualizerTimer[\s\S]{0,200}?interval:\s*64\b",
            media_src,
        )
    )

    # Legacy 0.18 rad / 64 ms; new step/period must keep |ω| within 5%.
    omega_ok = False
    if update_ms is not None and phase_step is not None and float(update_ms) > 0:
        legacy_omega = 0.18 / 64.0
        new_omega = float(phase_step) / float(update_ms)
        omega_ok = abs(new_omega - legacy_omega) / legacy_omega < 0.05

    return VisualizerAlignContract(
        single_phase_owner=bool(
            re.search(r"property\s+real\s+visualizerPhase\b", media_src)
        )
        and media_src.count("visualizerPhase") >= 2
        and not re.search(r"property\s+real\s+visualizerPhase\d", media_src),
        single_visualizer_timer=len(visualizer_timers) == 1
        and visualizer_timers[0] == "visualizerTimer",
        timer_gated_on_playing_visible_and_reduced=bool(
            re.search(
                r"running:\s*root\.isPlaying\s*&&\s*root\.visible\s*&&\s*!root\.reducedMotion",
                timer,
            )
        ),
        interval_uses_motion_token=bool(
            re.search(r"interval:\s*IslandMotion\.visualizerUpdateMs", timer)
        ),
        phase_step_uses_motion_token=bool(
            re.search(
                r"visualizerPhase\s*\+=\s*IslandMotion\.visualizerPhaseStep",
                timer,
            )
        ),
        playing_duration_uses_motion_token=bool(
            re.search(
                r"IslandMotion\.visualizerPlayingDuration",
                media_src,
            )
        )
        and bool(re.search(r"IslandMotion\.visualizerPausedDuration", media_src)),
        update_ms_gte_playing_duration=(
            update_ms is not None
            and playing_dur is not None
            and float(update_ms) >= float(playing_dur)
        ),
        not_sub_animation_hardcoded_64=not hardcoded_64
        and (update_ms is None or float(update_ms) >= 100),
        no_second_visualizer_timer=len(visualizer_timers) == 1,
        no_per_bar_phase=not bool(
            re.search(r"barPhase|phasePerBar|visualizerPhases\b", media_src)
        ),
        visualizer_still_present=bool(
            re.search(r"function\s+visualizerLevel\s*\(", media_src)
            and re.search(r"function\s+pausedLevel\s*\(", media_src)
            and re.search(r"id:\s*visualizerBox\b", media_src)
        ),
        reduced_motion_gates_timer=bool(
            re.search(r"!root\.reducedMotion", timer)
            and re.search(r"Motion\.reducedMotion", media_src)
        ),
        reduced_motion_static_bars=bool(
            re.search(r"reducedMotion", media_src)
            and re.search(r"pausedLevel", media_src)
            and re.search(
                r"duration:\s*root\.reducedMotion\s*\?\s*0",
                media_src,
            )
        ),
        settings_wired_from_overlay=bool(
            content_src
            and overlay_src
            and re.search(r"property\s+var\s+settingsService\b", content_src)
            and re.search(
                r"settingsService:\s*root\.settingsService",
                content_src,
            )
            and re.search(
                r"settingsService:\s*root\.settingsService",
                overlay_src,
            )
            and re.search(r"property\s+var\s+settingsService\b", media_src)
        ),
        phase_angular_velocity_near_legacy=omega_ok,
        media_content_gated_by_active_for_screen=bool(
            overlay_src
            and re.search(
                r"mediaContentVisible\s*:\s*contentState\s*===\s*[\"']expanded_media[\"']\s*&&\s*activeForScreen",
                overlay_src,
            )
        ),
        no_second_media_visibility_state=bool(
            overlay_src
            and not re.search(
                r"property\s+bool\s+(mediaVisibleForScreen|visualizerScreenActive|secondMediaVisible)\b",
                overlay_src,
            )
            and re.search(r"activeForScreen", overlay_src)
            and re.search(r"capsuleShown", overlay_src)
        ),
    )


class VisualizerRetargetBudget:
    """Models animation retarget pressure under update vs settle timing."""

    def __init__(self, update_ms: float, anim_ms: float, bars: int = 5) -> None:
        self.update_ms = update_ms
        self.anim_ms = anim_ms
        self.bars = bars

    @property
    def updates_per_second(self) -> float:
        return 1000.0 / self.update_ms

    @property
    def retargets_before_settle(self) -> float:
        # How many new targets arrive during one animation window.
        return self.anim_ms / self.update_ms

    @property
    def interrupted_bar_updates_per_second(self) -> float:
        return self.updates_per_second * self.bars


class DynamicIslandVisualizerAlignTests(unittest.TestCase):
    def test_source_contract_is_complete(self) -> None:
        contract = extract_contract(
            MEDIA_VIEW.read_text(encoding="utf-8"),
            MOTION.read_text(encoding="utf-8"),
            CONTENT.read_text(encoding="utf-8"),
            OVERLAY.read_text(encoding="utf-8"),
        )
        missing = [
            name
            for name in VisualizerAlignContract.__annotations__
            if not getattr(contract, name)
        ]
        self.assertEqual(
            missing,
            [],
            f"visualizer animation align contract incomplete: {missing}",
        )

    def test_old_64ms_into_120ms_constantly_redirects(self) -> None:
        old = VisualizerRetargetBudget(update_ms=64, anim_ms=120)
        # Animation never settles: >1 retarget per settle window.
        self.assertGreater(old.retargets_before_settle, 1.0)
        self.assertGreater(old.interrupted_bar_updates_per_second, 70)

    def test_aligned_update_allows_settle(self) -> None:
        motion = MOTION.read_text(encoding="utf-8")
        update = _js_number(motion, "visualizerUpdateMs")
        playing = _js_number(motion, "visualizerPlayingDuration")
        self.assertIsNotNone(update)
        self.assertIsNotNone(playing)
        assert update is not None and playing is not None
        fixed = VisualizerRetargetBudget(update_ms=float(update), anim_ms=float(playing))
        self.assertLessEqual(fixed.retargets_before_settle, 1.0)
        self.assertLess(fixed.interrupted_bar_updates_per_second, 50)
        # Workload clearly below old 64ms path (~78 bar updates/s).
        old = VisualizerRetargetBudget(update_ms=64, anim_ms=120)
        self.assertLess(
            fixed.interrupted_bar_updates_per_second,
            old.interrupted_bar_updates_per_second * 0.75,
        )

    def test_no_hardcoded_interval_64_on_visualizer_timer(self) -> None:
        src = MEDIA_VIEW.read_text(encoding="utf-8")
        self.assertIsNone(
            re.search(
                r"id:\s*visualizerTimer[\s\S]{0,200}?interval:\s*64\b",
                src,
            )
        )

    def test_timer_stops_when_not_playing(self) -> None:
        src = MEDIA_VIEW.read_text(encoding="utf-8")
        timer = _timer_block(src, "visualizerTimer")
        self.assertIn("isPlaying", timer)
        self.assertIn("visible", timer)
        self.assertIn("reducedMotion", timer)
        # Must not run unconditionally.
        self.assertNotRegex(
            timer,
            r"running:\s*true\b",
        )

    def test_reduced_motion_freezes_visualizer(self) -> None:
        src = MEDIA_VIEW.read_text(encoding="utf-8")
        timer = _timer_block(src, "visualizerTimer")
        self.assertRegex(
            timer,
            r"running:\s*root\.isPlaying\s*&&\s*root\.visible\s*&&\s*!root\.reducedMotion",
        )
        self.assertIn("Motion.reducedMotion", src)
        self.assertRegex(src, r"duration:\s*root\.reducedMotion\s*\?\s*0")

    def test_phase_angular_velocity_within_5_percent_of_legacy(self) -> None:
        motion = MOTION.read_text(encoding="utf-8")
        update = _js_number(motion, "visualizerUpdateMs")
        step = _js_number(motion, "visualizerPhaseStep")
        self.assertIsNotNone(update)
        self.assertIsNotNone(step)
        assert update is not None and step is not None
        legacy = 0.18 / 64.0
        new = float(step) / float(update)
        self.assertLess(abs(new - legacy) / legacy, 0.05)

    def test_single_phase_and_single_timer(self) -> None:
        src = MEDIA_VIEW.read_text(encoding="utf-8")
        self.assertEqual(len(re.findall(r"property\s+real\s+visualizerPhase\b", src)), 1)
        self.assertEqual(
            len(re.findall(r"id:\s*visualizerTimer\b", src)),
            1,
        )

    def test_motion_tokens_define_aligned_numbers(self) -> None:
        motion = MOTION.read_text(encoding="utf-8")
        for name in (
            "visualizerUpdateMs",
            "visualizerPhaseStep",
            "visualizerPlayingDuration",
            "visualizerPausedDuration",
        ):
            self.assertIsNotNone(_js_number(motion, name), f"missing token {name}")
        update = _js_number(motion, "visualizerUpdateMs")
        playing = _js_number(motion, "visualizerPlayingDuration")
        assert update is not None and playing is not None
        self.assertGreaterEqual(float(update), float(playing))

    def test_overlay_media_content_requires_active_for_screen(self) -> None:
        src = OVERLAY.read_text(encoding="utf-8")
        self.assertRegex(
            src,
            r"mediaContentVisible\s*:\s*contentState\s*===\s*[\"']expanded_media[\"']\s*&&\s*activeForScreen",
        )
        # Must not leave expanded_media visible on every output.
        self.assertNotRegex(
            src,
            r"mediaContentVisible\s*:\s*contentState\s*===\s*[\"']expanded_media[\"']\s*$",
            re.MULTILINE,
        )

    def test_real_qml_only_target_screen_phase_advances(self) -> None:
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
        # Prefer +test TahoeSymbol so media controls do not need icon fonts.
        env["QML_FILE_SELECTORS"] = "test"
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
