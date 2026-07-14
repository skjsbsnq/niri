#!/usr/bin/env python3
"""Task 01A: Dynamic Island media button press/release/cancel lifecycle.

Regression strategy:
1. Extract the real signal/wiring contract from QML sources (fails on old
   press-only code).
2. Drive a grab token + service owner through that extracted wiring only —
   if Overlay/Content release wiring is missing, press leaves interacting
   stuck true and the behavioral assertions fail.
3. Cover release, cancel, disable, hide/collapse, destroy, and idempotency.

Does not claim media buttons are hit-test reachable (Task 01B).
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
CONTENT = SHELL_ROOT / "components" / "DynamicIslandContent.qml"
OVERLAY = SHELL_ROOT / "components" / "DynamicIslandOverlay.qml"
SERVICE = SHELL_ROOT / "services" / "DynamicIsland.qml"


@dataclass(frozen=True)
class MediaInteractionWiring:
    """Edges discovered in source. Missing edges break lifecycle simulation."""

    has_begin: bool
    has_end: bool
    has_released_signal: bool
    has_canceled_signal: bool
    has_mouse_released: bool
    has_mouse_canceled: bool
    has_enabled_cancel: bool
    has_media_view_visible_cancel: bool
    has_control_enabled_cancel: bool
    has_destruction_cancel: bool
    media_release_handlers: int
    media_cancel_handlers: int
    content_forwards_released: bool
    content_opacity_gates_media_visible: bool
    overlay_press_sets_true: bool
    overlay_release_sets_false: bool
    service_has_set_user_interacting: bool

    @property
    def press_reaches_owner(self) -> bool:
        return self.has_begin and self.overlay_press_sets_true and self.service_has_set_user_interacting

    @property
    def terminal_reaches_owner(self) -> bool:
        """released/canceled can clear service interacting."""
        return (
            self.has_end
            and self.has_released_signal
            and self.has_canceled_signal
            and self.media_release_handlers >= 3
            and self.media_cancel_handlers >= 3
            and self.content_forwards_released
            and self.overlay_release_sets_false
            and self.service_has_set_user_interacting
        )

    @property
    def release_path_complete(self) -> bool:
        return self.terminal_reaches_owner and self.has_mouse_released

    @property
    def cancel_path_complete(self) -> bool:
        return self.terminal_reaches_owner and self.has_mouse_canceled

    @property
    def disable_path_complete(self) -> bool:
        return self.terminal_reaches_owner and (
            self.has_enabled_cancel or self.has_control_enabled_cancel
        )

    @property
    def hide_path_complete(self) -> bool:
        # Product hide is parent MediaView opacity→visible, not button-local visible.
        return (
            self.terminal_reaches_owner
            and self.has_media_view_visible_cancel
            and self.content_opacity_gates_media_visible
        )

    @property
    def destroy_path_complete(self) -> bool:
        return self.terminal_reaches_owner and self.has_destruction_cancel


class GrabToken:
    """Local interactionActive token matching MediaControlButton begin/end."""

    def __init__(self, control_enabled: bool = True, visible: bool = True) -> None:
        self.control_enabled = control_enabled
        self.visible = visible
        self.interaction_active = False
        self.events: list[str] = []

    def begin(self) -> bool:
        if not self.control_enabled or not self.visible or self.interaction_active:
            return False
        self.interaction_active = True
        self.events.append("pressed")
        return True

    def end(self, canceled: bool) -> str | None:
        if not self.interaction_active:
            return None
        self.interaction_active = False
        name = "canceled" if canceled else "released"
        self.events.append(name)
        return name


class UserInteractingOwner:
    """Single service owner: DynamicIsland.setUserInteracting."""

    def __init__(self, island_enabled: bool = True) -> None:
        self.island_enabled = island_enabled
        self.user_interacting = False
        self.transitions: list[bool] = []

    def set_user_interacting(self, active: bool) -> None:
        if not self.island_enabled:
            self.user_interacting = False
            self.transitions.append(False)
            return
        value = bool(active)
        self.user_interacting = value
        self.transitions.append(value)


class WiredLifecycleSimulator:
    """Applies press/terminal events only through extracted source wiring."""

    def __init__(self, wiring: MediaInteractionWiring) -> None:
        self.wiring = wiring
        self.btn = GrabToken()
        self.owner = UserInteractingOwner()

    def press(self) -> bool:
        started = self.btn.begin()
        if started and self.wiring.press_reaches_owner:
            self.owner.set_user_interacting(True)
        return started

    def terminal(self, canceled: bool, path_ok: bool) -> None:
        event = self.btn.end(canceled=canceled)
        if event is None:
            return
        # Only clear owner when the real source chain can carry the terminal.
        if path_ok and self.wiring.terminal_reaches_owner:
            self.owner.set_user_interacting(False)

    def release(self) -> None:
        self.terminal(canceled=False, path_ok=self.wiring.release_path_complete)

    def cancel(self) -> None:
        self.terminal(canceled=True, path_ok=self.wiring.cancel_path_complete)

    def disable(self) -> None:
        self.btn.control_enabled = False
        self.terminal(canceled=True, path_ok=self.wiring.disable_path_complete)

    def hide(self) -> None:
        # Product collapse sets MediaView.root.visible false via opacity gate.
        # Button-local visible stays true under ancestor hide; cancel is via
        # Connections { target: root; onVisibleChanged }.
        self.btn.visible = True
        self.media_view_visible = False
        self.terminal(canceled=True, path_ok=self.wiring.hide_path_complete)

    def destroy(self) -> None:
        self.terminal(canceled=True, path_ok=self.wiring.destroy_path_complete)


def extract_button_body(media_text: str) -> str:
    match = re.search(
        r"component MediaControlButton:\s*Item\s*\{(?P<body>.*)\n    \}\n\}\s*\Z",
        media_text,
        re.S,
    )
    if not match:
        raise AssertionError("MediaControlButton component body not found")
    return match.group("body")


def extract_wiring(
    media_text: str,
    content_text: str,
    overlay_text: str,
    service_text: str,
) -> MediaInteractionWiring:
    body = extract_button_body(media_text)
    return MediaInteractionWiring(
        has_begin="function beginInteraction()" in body,
        has_end="function endInteraction(canceled)" in body,
        has_released_signal="signal released()" in body,
        has_canceled_signal="signal canceled()" in body,
        has_mouse_released=bool(re.search(r"onReleased:\s*function", body)),
        has_mouse_canceled=bool(re.search(r"onCanceled:\s*\{", body)),
        has_enabled_cancel="onEnabledChanged:" in body and "endInteraction(true)" in body,
        # Must cancel via media view root visibility (Content opacity gate), not
        # only the button's own visible property.
        has_media_view_visible_cancel=(
            "Connections" in body
            and "target: root" in body
            and "function onVisibleChanged()" in body
            and "!root.visible" in body
            and "endInteraction(true)" in body
        ),
        has_control_enabled_cancel="onControlEnabledChanged:" in body
        and "endInteraction(true)" in body,
        has_destruction_cancel="Component.onDestruction" in body
        and "endInteraction(true)" in body,
        media_release_handlers=media_text.count("onReleased: root.controlReleased()"),
        media_cancel_handlers=media_text.count("onCanceled: root.controlReleased()"),
        content_forwards_released=(
            "signal mediaControlReleased()" in content_text
            and "onControlReleased: root.mediaControlReleased()" in content_text
        ),
        content_opacity_gates_media_visible=bool(
            re.search(
                r"DynamicIslandMediaView\s*\{[\s\S]*?"
                r"opacity:\s*root\.mediaExpandedContentVisible\s*\?\s*1\s*:\s*0[\s\S]*?"
                r"visible:\s*(?:opacity\s*>\s*0\.01|root\.mediaExpandedContentVisible)",
                content_text,
            )
        ),
        overlay_press_sets_true=bool(
            re.search(
                r"onMediaControlPressed:\s*if\s*\(root\.dynamicIslandService\)\s*"
                r"root\.dynamicIslandService\.setUserInteracting\(true\)",
                overlay_text,
            )
        ),
        overlay_release_sets_false=bool(
            re.search(
                r"onMediaControlReleased:\s*if\s*\(root\.dynamicIslandService\)\s*"
                r"root\.dynamicIslandService\.setUserInteracting\(false\)",
                overlay_text,
            )
        ),
        service_has_set_user_interacting="function setUserInteracting(active)" in service_text,
    )


class DynamicIslandMediaInteractionLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.media = MEDIA_VIEW.read_text(encoding="utf-8")
        cls.content = CONTENT.read_text(encoding="utf-8")
        cls.overlay = OVERLAY.read_text(encoding="utf-8")
        cls.service = SERVICE.read_text(encoding="utf-8")
        cls.wiring = extract_wiring(cls.media, cls.content, cls.overlay, cls.service)
        cls.button_body = extract_button_body(cls.media)

    def sim(self) -> WiredLifecycleSimulator:
        return WiredLifecycleSimulator(self.wiring)

    # --- Wiring contract (old press-only code fails here) ---

    def test_extracted_wiring_is_complete_for_task_01a(self) -> None:
        w = self.wiring
        self.assertTrue(w.has_begin, "beginInteraction missing")
        self.assertTrue(w.has_end, "endInteraction missing")
        self.assertTrue(w.has_released_signal)
        self.assertTrue(w.has_canceled_signal)
        self.assertTrue(w.has_mouse_released)
        self.assertTrue(w.has_mouse_canceled)
        self.assertTrue(w.has_enabled_cancel or w.has_control_enabled_cancel)
        self.assertTrue(
            w.has_media_view_visible_cancel,
            "media-view root visible cancel path missing",
        )
        self.assertTrue(
            w.content_opacity_gates_media_visible,
            "Content must opacity-gate DynamicIslandMediaView.visible",
        )
        self.assertTrue(w.has_destruction_cancel)
        self.assertEqual(w.media_release_handlers, 3)
        self.assertEqual(w.media_cancel_handlers, 3)
        self.assertTrue(w.content_forwards_released)
        self.assertTrue(w.overlay_press_sets_true)
        self.assertTrue(w.overlay_release_sets_false)
        self.assertTrue(w.service_has_set_user_interacting)
        self.assertTrue(w.press_reaches_owner)
        self.assertTrue(w.terminal_reaches_owner)
        self.assertTrue(w.release_path_complete)
        self.assertTrue(w.cancel_path_complete)
        self.assertTrue(w.disable_path_complete)
        self.assertTrue(w.hide_path_complete)
        self.assertTrue(w.destroy_path_complete)

    def test_old_press_only_shape_cannot_satisfy_wiring(self) -> None:
        """Without release wiring, terminal_reaches_owner is false → stuck interacting."""
        old = MediaInteractionWiring(
            has_begin=False,
            has_end=False,
            has_released_signal=False,
            has_canceled_signal=False,
            has_mouse_released=False,
            has_mouse_canceled=False,
            has_enabled_cancel=False,
            has_media_view_visible_cancel=False,
            has_control_enabled_cancel=False,
            has_destruction_cancel=False,
            media_release_handlers=0,
            media_cancel_handlers=0,
            content_forwards_released=False,
            content_opacity_gates_media_visible=True,
            overlay_press_sets_true=True,  # old overlay only had press→true
            overlay_release_sets_false=False,
            service_has_set_user_interacting=True,
        )
        self.assertFalse(old.terminal_reaches_owner)
        self.assertFalse(old.release_path_complete)
        self.assertFalse(old.cancel_path_complete)
        self.assertFalse(old.hide_path_complete)

        # Simulate old press-only: press reaches owner, terminal cannot clear.
        owner = UserInteractingOwner()
        if old.press_reaches_owner or old.overlay_press_sets_true:
            owner.set_user_interacting(True)
        # No terminal path.
        if old.terminal_reaches_owner:
            owner.set_user_interacting(False)
        self.assertTrue(owner.user_interacting)

    # --- Behavioral paths gated by extracted wiring ---

    def test_press_release_clears_interacting(self) -> None:
        s = self.sim()
        self.assertTrue(s.press())
        self.assertTrue(s.owner.user_interacting)
        s.release()
        self.assertEqual(s.btn.events, ["pressed", "released"])
        self.assertFalse(s.btn.interaction_active)
        self.assertFalse(s.owner.user_interacting)

    def test_press_cancel_clears_interacting(self) -> None:
        s = self.sim()
        self.assertTrue(s.press())
        s.cancel()
        self.assertEqual(s.btn.events, ["pressed", "canceled"])
        self.assertFalse(s.owner.user_interacting)

    def test_press_then_disable_cancels_and_clears(self) -> None:
        s = self.sim()
        self.assertTrue(s.press())
        s.disable()
        self.assertEqual(s.btn.events, ["pressed", "canceled"])
        self.assertFalse(s.btn.interaction_active)
        self.assertFalse(s.owner.user_interacting)

    def test_press_then_hide_collapse_cancels_and_clears(self) -> None:
        """Product path: Content opacity-gates MediaView.visible while pressed.

        Simulator flips media-view visibility (root.visible), matching
        Connections { target: root; onVisibleChanged → endInteraction(true) },
        not a button-local visible property (ancestor hide does not flip that).
        """
        s = self.sim()
        self.assertTrue(s.press())
        self.assertTrue(s.owner.user_interacting)
        # Media view root becomes invisible (Content: visible: opacity > 0.01).
        s.hide()
        self.assertEqual(s.btn.events, ["pressed", "canceled"])
        self.assertFalse(s.btn.interaction_active)
        self.assertFalse(s.owner.user_interacting)

    def test_button_local_visible_handler_alone_is_not_the_hide_path(self) -> None:
        """Regression: child onVisibleChanged is insufficient for Content opacity gate."""
        body = self.button_body
        # Must not rely only on btn.visible — require Connections to media root.
        self.assertIn("target: root", body)
        self.assertIn("!root.visible", body)
        self.assertNotRegex(
            body,
            r"onVisibleChanged:\s*\{\s*if\s*\(!btn\.visible\)",
        )

    def test_destroy_while_pressed_clears_via_cancel_wiring(self) -> None:
        s = self.sim()
        self.assertTrue(s.press())
        s.destroy()
        self.assertEqual(s.btn.events, ["pressed", "canceled"])
        self.assertFalse(s.owner.user_interacting)

    def test_disabled_button_never_enters_interacting(self) -> None:
        s = self.sim()
        s.btn.control_enabled = False
        self.assertFalse(s.press())
        self.assertEqual(s.btn.events, [])
        self.assertFalse(s.btn.interaction_active)
        self.assertFalse(s.owner.user_interacting)

    def test_invisible_button_never_enters_interacting(self) -> None:
        s = self.sim()
        s.btn.visible = False
        self.assertFalse(s.press())
        self.assertEqual(s.btn.events, [])
        self.assertFalse(s.owner.user_interacting)

    def test_repeated_release_and_cancel_are_idempotent(self) -> None:
        s = self.sim()
        self.assertTrue(s.press())
        s.release()
        s.release()
        s.cancel()
        s.cancel()
        self.assertEqual(s.btn.events, ["pressed", "released"])
        self.assertFalse(s.btn.interaction_active)
        self.assertFalse(s.owner.user_interacting)
        # One true, one false — extras do not re-toggle.
        self.assertEqual(s.owner.transitions, [True, False])

    def test_disable_then_canceled_double_entry_is_idempotent(self) -> None:
        """onEnabledChanged and MouseArea.onCanceled may both fire; end is once."""
        s = self.sim()
        self.assertTrue(s.press())
        s.disable()
        # Second terminal from Qt canceled after disable.
        s.cancel()
        self.assertEqual(s.btn.events, ["pressed", "canceled"])
        self.assertEqual(s.owner.transitions, [True, False])
        self.assertFalse(s.owner.user_interacting)

    def test_missing_release_wiring_would_leave_interacting_stuck(self) -> None:
        """Behavioral gate: if Overlay release edge is removed, press sticks."""
        broken = MediaInteractionWiring(
            **{
                **self.wiring.__dict__,
                "overlay_release_sets_false": False,
                "media_release_handlers": 0,
                "content_forwards_released": False,
            }
        )
        self.assertFalse(broken.terminal_reaches_owner)
        s = WiredLifecycleSimulator(broken)
        self.assertTrue(s.press())
        s.release()
        # Grab token still ends locally, but owner cannot clear without wiring.
        self.assertFalse(s.btn.interaction_active)
        self.assertTrue(s.owner.user_interacting)

    # --- Source structure details ---

    def test_end_interaction_early_returns_when_inactive(self) -> None:
        end_fn = re.search(
            r"function endInteraction\(canceled\)\s*\{(?P<body>.*?)\n        \}",
            self.button_body,
            re.S,
        )
        self.assertIsNotNone(end_fn)
        assert end_fn is not None
        self.assertIn("if (!btn.interactionActive)", end_fn.group("body"))

    def test_begin_interaction_requires_enabled_and_media_visible(self) -> None:
        begin_fn = re.search(
            r"function beginInteraction\(\)\s*\{(?P<body>.*?)\n        \}",
            self.button_body,
            re.S,
        )
        self.assertIsNotNone(begin_fn)
        assert begin_fn is not None
        body = begin_fn.group("body")
        self.assertIn("!btn.controlEnabled", body)
        self.assertIn("!btn.visible", body)
        self.assertIn("!root.visible", body)
        self.assertIn("btn.interactionActive", body)

    def test_no_second_interacting_state_on_media_path(self) -> None:
        for name, text in (
            ("DynamicIslandMediaView", self.media),
            ("DynamicIslandContent", self.content),
        ):
            with self.subTest(file=name):
                self.assertNotRegex(text, r"property\s+bool\s+userInteracting\b")
                self.assertNotIn("safeSetUserInteracting", text)
                self.assertNotIn("mediaInteracting", text)

        self.assertEqual(self.service.count("function setUserInteracting"), 1)
        self.assertIn("property bool userInteracting", self.service)

        media_handlers = re.findall(
            r"onMediaControl(?:Pressed|Released):\s*[^\n]+",
            self.overlay,
        )
        self.assertEqual(len(media_handlers), 2)
        for handler in media_handlers:
            self.assertIn("setUserInteracting", handler)

    def test_capsule_mousearea_has_no_elevated_z_or_propagate(self) -> None:
        """01A residual: capsule gesture MA must not use elevate-z / propagate tricks.

        Task 01B may place contentHost above this MouseArea via contentHost.z;
        the capsule area itself stays default stacking without propagateComposedEvents.
        """
        text = self.overlay
        content_idx = text.find("id: contentHost")
        mouse_idx = text.find("MouseArea {")
        self.assertGreater(content_idx, 0)
        self.assertGreater(mouse_idx, content_idx)

        mouse_block = text[mouse_idx : mouse_idx + 400]
        self.assertIn("anchors.fill: parent", mouse_block)
        self.assertNotIn("z:", mouse_block)
        self.assertNotIn("propagateComposedEvents", text)

    def test_media_actions_still_fire_on_press_not_release(self) -> None:
        for action in ("previousRequested", "playPauseRequested", "nextRequested"):
            pattern = rf"onPressed:\s*\{{[^}}]*root\.{action}\(\)"
            self.assertRegex(self.media, pattern, action)

    def test_interaction_active_is_local_grab_token_not_service_state(self) -> None:
        self.assertIn("property bool interactionActive: false", self.button_body)
        # Must not be written onto DynamicIsland service.
        self.assertNotIn("interactionActive", self.service)
        self.assertNotIn("interactionActive", self.overlay)



    def test_real_qml_media_interaction_lifecycle(self) -> None:
        """Drive production DynamicIslandMediaView via qmltestrunner."""
        qml_test = Path(__file__).with_name("tst_dynamic_island_media_interaction_lifecycle.qml")
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
            [runner, "-input", str(qml_test), "-file-selector", "test"],
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
