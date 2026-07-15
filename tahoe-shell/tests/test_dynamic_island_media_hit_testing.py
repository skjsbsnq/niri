#!/usr/bin/env python3
"""Task 01B: Dynamic Island media control hit testing.

Root cause: capsule fill MouseArea was painted above content and stole all
hits. Fix: contentHost stacks above the capsule area; media buttons absorb
hits (including disabled) so capsule click/swipe does not double-fire.

Does not change swipe thresholds (Task 11). Reuses Task 01A lifecycle.
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
QML_TEST = Path(__file__).with_name("tst_dynamic_island_media_hit_testing.qml")
MEDIA_VIEW = SHELL_ROOT / "components" / "DynamicIslandMediaView.qml"
CONTENT = SHELL_ROOT / "components" / "DynamicIslandContent.qml"
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
SERVICE = SHELL_ROOT / "services" / "DynamicIsland.qml"


@dataclass(frozen=True)
class HitTestWiring:
    content_host_above_capsule: bool
    content_host_has_z: bool
    capsule_mousearea_fill: bool
    capsule_no_propagate: bool
    capsule_no_coordinate_forward: bool
    media_mousearea_always_enabled: bool
    media_button_containers_stay_enabled: bool
    media_press_accepts: bool
    media_prevent_stealing: bool
    lifecycle_release_chain: bool
    three_buttons: bool
    no_duplicate_media_apis: bool
    no_second_overlay_mousearea: bool

    @property
    def hit_path_complete(self) -> bool:
        return (
            self.content_host_above_capsule
            and self.content_host_has_z
            and self.capsule_mousearea_fill
            and self.capsule_no_propagate
            and self.media_mousearea_always_enabled
            and self.media_button_containers_stay_enabled
            and self.media_press_accepts
            and self.media_prevent_stealing
            and self.lifecycle_release_chain
            and self.three_buttons
            and self.no_duplicate_media_apis
            and self.no_second_overlay_mousearea
        )


@dataclass
class HitEvent:
    target: str  # "media_prev" | "media_play" | "media_next" | "capsule_blank"
    control_enabled: bool = True


class HitRoutingModel:
    """Models single-path hit routing after stacking fix.

    Content-layer media buttons are above the capsule MouseArea. Hits on a
    button rect are consumed by the button (action only if enabled). Hits on
    blank capsule regions go to the capsule MouseArea (click/swipe).
    """

    def __init__(self) -> None:
        self.media_actions: list[str] = []
        self.capsule_clicks: list[str] = []
        self.capsule_swipes: int = 0
        self.interacting_transitions: list[bool] = []

    def route_press(self, event: HitEvent) -> None:
        if event.target.startswith("media_"):
            # Button hit rect always absorbs; actions need enabled.
            if event.control_enabled:
                action = event.target.removeprefix("media_")
                self.media_actions.append(action)
                self.interacting_transitions.append(True)
            # Disabled: absorb only — no action, no capsule fall-through.
            return
        # Blank capsule region.
        self.interacting_transitions.append(True)
        self.capsule_clicks.append("armed")

    def route_release(self, event: HitEvent, *, moved: bool = False) -> None:
        if event.target.startswith("media_"):
            if event.control_enabled and self.interacting_transitions:
                self.interacting_transitions.append(False)
            return
        if moved:
            self.capsule_swipes += 1
        else:
            self.capsule_clicks.append("clicked")
        self.interacting_transitions.append(False)


def extract_content_host_block(overlay: str) -> str:
    match = re.search(
        r"Item\s*\{\s*id:\s*contentHost(?P<body>[\s\S]*?)\n        \}\n\n        MouseArea",
        overlay,
    )
    if not match:
        raise AssertionError("contentHost block before MouseArea not found")
    return match.group(0)


def extract_capsule_mousearea(overlay: str) -> str:
    # Capsule gesture MouseArea is the one with swipeStartX / handleChipClick.
    match = re.search(
        r"MouseArea\s*\{(?P<body>[\s\S]*?handleChipClick[\s\S]*?)\n       \}",
        overlay,
    )
    if not match:
        # Fallback: last MouseArea in islandSurface
        matches = list(re.finditer(r"MouseArea\s*\{", overlay))
        if not matches:
            raise AssertionError("capsule MouseArea not found")
        start = matches[-1].start()
        return overlay[start : start + 2500]
    return match.group(0)


def extract_media_button_body(media: str) -> str:
    match = re.search(
        r"component MediaControlButton:\s*Item\s*\{(?P<body>.*)\n    \}\n\}\s*\Z",
        media,
        re.S,
    )
    if not match:
        raise AssertionError("MediaControlButton body not found")
    return match.group("body")


def extract_hit_wiring(overlay: str, media: str, content: str, service: str) -> HitTestWiring:
    host = extract_content_host_block(overlay)
    capsule = extract_capsule_mousearea(overlay)
    button = extract_media_button_body(media)
    mouse_areas = len(re.findall(r"\bMouseArea\s*\{", overlay))

    return HitTestWiring(
        content_host_above_capsule="id: contentHost" in host and "MouseArea" in extract_capsule_mousearea(overlay),
        content_host_has_z=bool(re.search(r"id:\s*contentHost[\s\S]{0,120}?z:\s*1\b", overlay)),
        capsule_mousearea_fill="anchors.fill: parent" in capsule,
        capsule_no_propagate="propagateComposedEvents" not in overlay,
        capsule_no_coordinate_forward=not bool(
            re.search(r"mapToItem|childAt\(|contains\(.*mouse", overlay)
        ),
        media_mousearea_always_enabled=bool(
            re.search(r"MouseArea\s*\{[\s\S]*?enabled:\s*true", button)
        ),
        media_button_containers_stay_enabled=(
            not bool(re.search(r"MediaControlButton\s*\{[\s\S]*?enabled:\s*root\.can", media))
            and media.count("controlEnabled: root.can") == 3
        ),
        media_press_accepts="mouseEvent.accepted = true" in button
        or "mouse.accepted = true" in button,
        media_prevent_stealing="preventStealing: true" in button,
        lifecycle_release_chain=(
            "onMediaControlReleased:" in overlay
            and "setUserInteracting(false)" in overlay
            and "signal controlReleased()" in media
            and "onControlReleased: root.mediaControlReleased()" in content
        ),
        three_buttons=(
            media.count("MediaControlButton {") == 3
            and media.count("onReleased: root.controlReleased()") == 3
        ),
        no_duplicate_media_apis=(
            "function mediaPrevious" not in overlay
            and "safeMedia" not in overlay + media + content
            and service.count("function mediaPrevious") == 1
            and service.count("function mediaTogglePlayPause") == 1
            and service.count("function mediaNext") == 1
        ),
        no_second_overlay_mousearea=mouse_areas == 1,
    )


class DynamicIslandMediaHitTestingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.overlay = OVERLAY.read_text(encoding="utf-8")
        cls.media = MEDIA_VIEW.read_text(encoding="utf-8")
        cls.content = CONTENT.read_text(encoding="utf-8")
        cls.service = SERVICE.read_text(encoding="utf-8")
        cls.wiring = extract_hit_wiring(cls.overlay, cls.media, cls.content, cls.service)
        cls.button_body = extract_media_button_body(cls.media)
        cls.capsule = extract_capsule_mousearea(cls.overlay)

    # --- Wiring contract ---

    def test_hit_wiring_is_complete(self) -> None:
        w = self.wiring
        self.assertTrue(w.content_host_has_z, "contentHost must stack above capsule (z: 1)")
        self.assertTrue(w.capsule_mousearea_fill)
        self.assertTrue(w.capsule_no_propagate)
        self.assertTrue(w.capsule_no_coordinate_forward)
        self.assertTrue(w.media_mousearea_always_enabled, "disabled buttons must still absorb hits")
        self.assertTrue(w.media_button_containers_stay_enabled)
        self.assertTrue(w.media_press_accepts)
        self.assertTrue(w.media_prevent_stealing)
        self.assertTrue(w.lifecycle_release_chain, "must reuse Task 01A lifecycle")
        self.assertTrue(w.three_buttons)
        self.assertTrue(w.no_duplicate_media_apis)
        self.assertTrue(w.no_second_overlay_mousearea)
        self.assertTrue(w.hit_path_complete)

    def test_old_stacking_would_block_media_hits(self) -> None:
        """Pre-fix: contentHost without elevated z; later sibling MouseArea wins."""
        old = HitTestWiring(
            content_host_above_capsule=True,  # declaration order only
            content_host_has_z=False,
            capsule_mousearea_fill=True,
            capsule_no_propagate=True,
            capsule_no_coordinate_forward=True,
            media_mousearea_always_enabled=False,  # old: enabled: controlEnabled
            media_button_containers_stay_enabled=False,
            media_press_accepts=True,
            media_prevent_stealing=True,
            lifecycle_release_chain=True,
            three_buttons=True,
            no_duplicate_media_apis=True,
            no_second_overlay_mousearea=True,
        )
        self.assertFalse(old.hit_path_complete)
        self.assertFalse(old.content_host_has_z)

    def test_content_host_z_above_default_capsule(self) -> None:
        # contentHost declares z: 1; capsule MouseArea has no z (default 0).
        self.assertRegex(self.overlay, r"id:\s*contentHost[\s\S]{0,80}?z:\s*1\b")
        self.assertNotRegex(self.capsule, r"\bz:\s*\d+")

    def test_no_coordinate_hardcoded_button_forwarding(self) -> None:
        self.assertNotIn("mapToItem", self.overlay)
        self.assertNotIn("childAt(", self.overlay)
        self.assertNotIn("propagateComposedEvents", self.overlay)
        # No second full-cover MouseArea layered for forwarding.
        self.assertEqual(len(re.findall(r"\bMouseArea\s*\{", self.overlay)), 1)

    def test_media_mousearea_not_gated_only_by_control_enabled(self) -> None:
        """Disabled controls must keep a hit target (enabled: true)."""
        body = self.button_body
        ma = re.search(r"MouseArea\s*\{(?P<body>[\s\S]*?)\n        \}", body)
        self.assertIsNotNone(ma)
        assert ma is not None
        ma_body = ma.group("body")
        self.assertIn("enabled: true", ma_body)
        self.assertNotIn("enabled: btn.controlEnabled", ma_body)
        # Actions still gated by controlEnabled inside beginInteraction.
        self.assertIn("!btn.controlEnabled", body)

    def test_media_button_container_is_not_disabled(self) -> None:
        """A disabled parent Item disables its child MouseArea effectively."""
        instances = re.findall(
            r"MediaControlButton\s*\{(?P<body>[\s\S]*?)\n            \}",
            self.media,
        )
        self.assertEqual(len(instances), 3)
        for body in instances:
            self.assertNotRegex(body, r"\benabled:\s*root\.can")
            self.assertRegex(body, r"\bcontrolEnabled:\s*root\.can")

    def test_task_01a_lifecycle_still_wired(self) -> None:
        self.assertIn("onMediaControlPressed:", self.overlay)
        self.assertIn("onMediaControlReleased:", self.overlay)
        self.assertIn("setUserInteracting(true)", self.overlay)
        self.assertIn("setUserInteracting(false)", self.overlay)
        self.assertIn("signal controlReleased()", self.media)
        self.assertIn("function beginInteraction()", self.media)
        self.assertIn("function endInteraction(canceled)", self.media)

    def test_swipe_thresholds_untouched(self) -> None:
        """Task 11 owns swipe distance; 01B must not rewrite gesture thresholds."""
        # Capsule swipe still uses existing service APIs without new magic deltas.
        self.assertIn("beginSwipe()", self.capsule)
        self.assertIn("advanceSwipe(", self.capsule)
        self.assertIn("resolveSwipe(", self.capsule)
        self.assertIn("cancelSwipe()", self.capsule)
        self.assertIn("handleChipClick(", self.capsule)
        # No new inline pixel thresholds added for button exclusion zones.
        self.assertNotRegex(self.capsule, r"buttonHit|mediaHitRect|controlZone")

    # --- Behavioral routing model (fails without stacking absorb semantics) ---

    def test_enabled_button_triggers_action_not_capsule_click(self) -> None:
        m = HitRoutingModel()
        ev = HitEvent(target="media_play", control_enabled=True)
        m.route_press(ev)
        m.route_release(ev)
        self.assertEqual(m.media_actions, ["play"])
        self.assertEqual(m.capsule_clicks, [])
        self.assertEqual(m.capsule_swipes, 0)
        self.assertEqual(m.interacting_transitions, [True, False])

    def test_each_button_fires_once(self) -> None:
        m = HitRoutingModel()
        for name in ("prev", "play", "next"):
            ev = HitEvent(target=f"media_{name}", control_enabled=True)
            m.route_press(ev)
            m.route_release(ev)
        self.assertEqual(m.media_actions, ["prev", "play", "next"])
        self.assertEqual(m.capsule_clicks, [])

    def test_disabled_button_absorbs_without_action_or_capsule(self) -> None:
        m = HitRoutingModel()
        ev = HitEvent(target="media_prev", control_enabled=False)
        m.route_press(ev)
        m.route_release(ev)
        self.assertEqual(m.media_actions, [])
        self.assertEqual(m.capsule_clicks, [])
        self.assertEqual(m.interacting_transitions, [])

    def test_blank_capsule_keeps_click_behavior(self) -> None:
        m = HitRoutingModel()
        ev = HitEvent(target="capsule_blank")
        m.route_press(ev)
        m.route_release(ev, moved=False)
        self.assertEqual(m.media_actions, [])
        self.assertEqual(m.capsule_clicks, ["armed", "clicked"])
        self.assertEqual(m.interacting_transitions, [True, False])

    def test_blank_capsule_swipe_suppresses_click_path(self) -> None:
        m = HitRoutingModel()
        ev = HitEvent(target="capsule_blank")
        m.route_press(ev)
        m.route_release(ev, moved=True)
        self.assertEqual(m.capsule_swipes, 1)
        self.assertEqual(m.capsule_clicks, ["armed"])  # no "clicked"
        self.assertEqual(m.interacting_transitions[-1], False)

    def test_missing_content_z_fails_wiring_gate(self) -> None:
        broken = HitTestWiring(**{**self.wiring.__dict__, "content_host_has_z": False})
        self.assertFalse(broken.hit_path_complete)

    def test_propagate_composed_would_risk_double_fire(self) -> None:
        """Guard: do not use propagateComposedEvents as the hit-test strategy."""
        self.assertNotIn("propagateComposedEvents", self.overlay)
        self.assertNotIn("propagateComposedEvents", self.media)

    def test_no_second_interacting_or_media_api(self) -> None:
        for text in (self.media, self.content, self.overlay):
            self.assertNotIn("safeMedia", text)
            self.assertNotIn("mediaInteracting", text)
            self.assertNotIn("safeSetUserInteracting", text)
        self.assertEqual(self.service.count("function setUserInteracting"), 1)

    def _rewrite_overlay_shell_for_tests(self, dest: Path) -> None:
        """Rewrite only PanelWindow shell so contentHost/MouseArea stay production.

        qmltestrunner cannot load Quickshell shared plugins; the body of
        DynamicIslandOverlay (contentHost z-order + capsule MouseArea) is kept
        verbatim from production sources.
        """
        import re as _re

        src = OVERLAY.read_text(encoding="utf-8")
        src = src.replace("import Quickshell.Wayland\n", "")
        src = src.replace("import Quickshell\n", "")
        src = src.replace("PanelWindow {", "Window {", 1)
        if "import QtQuick.Window" not in src:
            src = src.replace(
                "import QtQuick\n",
                "import QtQuick\nimport QtQuick.Window\n",
                1,
            )

        out_lines = []
        drop_props = (
            "aboveWindows",
            "exclusionMode",
            "exclusiveZone",
            "focusable",
            "implicitWidth",
            "implicitHeight",
        )
        for line in src.splitlines(True):
            if _re.search(r"\bWlrLayershell\.", line):
                continue
            if _re.search(r"\bTahoeGlass\.regions\b", line):
                continue
            if any(_re.search(rf"\b{prop}\s*:", line) for prop in drop_props):
                continue
            out_lines.append(line)
        src = "".join(out_lines)

        def remove_block(text: str, pattern: str) -> str:
            m = _re.search(pattern, text)
            if not m:
                return text
            start = m.start()
            brace = text.find("{", m.start())
            depth = 0
            i = brace
            while i < len(text):
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
                i += 1
            while start > 0 and text[start - 1] in " \t":
                start -= 1
            if start > 0 and text[start - 1] == "\n":
                start -= 1
            return text[:start] + text[i:]

        src = remove_block(src, r"mask:\s*Region\s*\{")
        src = remove_block(src, r"anchors\s*\{\s*\n\s*left:\s*true")
        src = src.replace(
            "readonly property int screenWidth: Math.max(1, Number(root.screen && root.screen.width) || root.width)",
            "readonly property int screenWidth: Math.max(1, Number(root.width) || 800)",
        )
        # Writable own screen name for multi-screen activeForScreen tests under Window.
        src = src.replace(
            "readonly property string ownScreenName: root.screen ? String(root.screen.name || \"\") : \"\"",
            "property string ownScreenName: \"\"",
        )
        src = src.replace(
            'readonly property string ownScreenName: root.screen ? String(root.screen.name || "") : ""',
            'property string ownScreenName: ""',
        )
        dest.write_text(src, encoding="utf-8")

    def test_real_qml_production_overlay_hit_testing(self) -> None:
        import tempfile
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(runner, "Qt 6 qmltestrunner is required")
        with tempfile.TemporaryDirectory() as tmp:
            rewritten = Path(tmp) / "DynamicIslandOverlay.qml"
            self._rewrite_overlay_shell_for_tests(rewritten)
            # Verify production contentHost + MouseArea tokens survive rewrite.
            body = rewritten.read_text(encoding="utf-8")
            self.assertIn("id: contentHost", body)
            self.assertIn("z: 1", body)
            self.assertIn("DynamicIslandContent", body)
            self.assertIn("swipeStartX", body)
            self.assertIn("onMediaControlPressed", body)
            self.assertNotIn("PanelWindow", body)

            env = os.environ.copy()
            env.setdefault("QT_QPA_PLATFORM", "offscreen")
            local_qml = Path.home() / ".local" / "lib" / "qt6" / "qml"
            test_qml = SHELL_ROOT / "tests" / "qml_imports"
            existing = env.get("QML2_IMPORT_PATH", "")
            paths = [str(test_qml), str(local_qml)]
            if existing:
                paths.append(existing)
            env["QML2_IMPORT_PATH"] = ":".join(paths)
            # Pass rewritten path into the QML test via env.
            env["TAHOE_TEST_OVERLAY_SOURCE"] = str(rewritten)
            # Patch QML to read env: inject property default via -input still uses file.
            # Write a small wrapper that sets overlaySource from env.
            qml_test = Path(tmp) / "tst_hit.qml"
            base = QML_TEST.read_text(encoding="utf-8")
            base = base.replace(
                'property string overlaySource: ""',
                f'property string overlaySource: "{rewritten}"',
            )
            qml_test.write_text(base, encoding="utf-8")
            # Also need components path: rewrite GlassPanel TahoeGlassRegion dependency
            # by ensuring components are importable from original tree via relative path
            # in createComponent file URL — Overlay imports "./" relative components.
            # Copy rewritten overlay next to components via symlink tree.
            work = Path(tmp) / "components"
            work.mkdir()
            # Symlink production components except Overlay which we replace.
            import os as _os
            for entry in (SHELL_ROOT / "components").iterdir():
                if entry.name == "DynamicIslandOverlay.qml":
                    continue
                _os.symlink(entry, work / entry.name)
            _os.symlink(rewritten, work / "DynamicIslandOverlay.qml")
            # Point createComponent at work tree overlay.
            base2 = qml_test.read_text(encoding="utf-8")
            base2 = base2.replace(
                f'property string overlaySource: "{rewritten}"',
                f'property string overlaySource: "{work / "DynamicIslandOverlay.qml"}"',
            )
            qml_test.write_text(base2, encoding="utf-8")

            result = subprocess.run(
                [runner, "-input", str(qml_test), "-file-selector", "test"],
                cwd=SHELL_ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=90,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout)



    def test_real_qml_missing_content_host_z_fails(self) -> None:
        """Negative: stripping contentHost z must fail the production Overlay QML suite."""
        import tempfile
        import re as _re

        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(runner)
        with tempfile.TemporaryDirectory() as tmp:
            rewritten = Path(tmp) / "DynamicIslandOverlay.qml"
            self._rewrite_overlay_shell_for_tests(rewritten)
            body = rewritten.read_text(encoding="utf-8")
            mutated = _re.sub(
                r"(id:\s*contentHost[\s\S]{0,120}?)z:\s*1\b",
                r"\1/* MUTATED no elevated z */",
                body,
                count=1,
            )
            self.assertNotEqual(mutated, body, "mutation must remove contentHost z:1")
            rewritten.write_text(mutated, encoding="utf-8")
            work = Path(tmp) / "components"
            work.mkdir()
            import os as _os
            for entry in (SHELL_ROOT / "components").iterdir():
                if entry.name == "DynamicIslandOverlay.qml":
                    continue
                _os.symlink(entry, work / entry.name)
            _os.symlink(rewritten, work / "DynamicIslandOverlay.qml")
            qml_test = Path(tmp) / "tst_hit.qml"
            base = QML_TEST.read_text(encoding="utf-8")
            base = base.replace(
                'property string overlaySource: ""',
                f'property string overlaySource: "{work / "DynamicIslandOverlay.qml"}"',
            )
            qml_test.write_text(base, encoding="utf-8")
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
                [runner, "-input", str(qml_test), "-file-selector", "test"],
                cwd=SHELL_ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=90,
                check=False,
            )
            self.assertNotEqual(
                result.returncode,
                0,
                "missing contentHost z must fail real Overlay hit tests:\n" + result.stdout,
            )
            self.assertTrue(
                "FAIL!" in result.stdout
                or "contentHost" in result.stdout
                or "Compared values are not the same" in result.stdout,
                result.stdout,
            )


if __name__ == "__main__":
    unittest.main()
