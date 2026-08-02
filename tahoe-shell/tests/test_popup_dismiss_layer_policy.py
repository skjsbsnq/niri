#!/usr/bin/env python3
"""T-29 / F-13: PopupDismissLayer wheel/right-click handling policy.

Before the fix the full-screen input region only handled default left-click:
wheel and right-click were swallowed by the layer with no feedback and no
effect. Policy now: left-click and right-click are both explicit dismiss
gestures (right-click = universal cancel), wheel is deliberately inert — a
scroll must never close a popup, and since the layer owns the input region it
cannot reach the window underneath either.
"""

from __future__ import annotations

import json
import re
import subprocess
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
POPUP_DISMISS = SHELL_ROOT / "components" / "PopupDismissLayer.qml"


class PopupDismissLayerPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = POPUP_DISMISS.read_text(encoding="utf-8")

    def test_right_click_is_an_explicit_dismiss_gesture(self) -> None:
        self.assertIn("acceptedButtons: Qt.LeftButton | Qt.RightButton", self.source)
        # One shared dismiss decision for both buttons (afterimage suppress
        # still applies to right-click on a just-closed footprint).
        self.assertIn("function dismissFor(mouse)", self.source)
        self.assertIn("if (root.dismissFor(mouse))", self.source)

    def test_dismiss_for_is_defined_on_the_root_it_is_called_on(self) -> None:
        """1d5a90c regression: dismissFor was defined on the MouseArea but
        called as root.dismissFor(mouse) — every click threw TypeError, so
        closeRequested never ran and the full-screen layer silently
        swallowed all outside clicks (popups stopped dismissing, windows
        became unclickable)."""
        definition = self.source.index("function dismissFor(mouse)")
        mouse_area = self.source.index("MouseArea {")
        self.assertLess(
            definition,
            mouse_area,
            "dismissFor must be defined on the PanelWindow root scope that "
            "the onClicked handler qualifies its call with",
        )

    def test_wheel_is_deliberately_inert(self) -> None:
        handler = "onWheel: function(wheel) {\n"
        self.assertIn(handler, self.source)
        self.assertIn("wheel.accepted = true;", self.source)
        # The wheel handler must never dismiss: no closeRequested in the rest
        # of the MouseArea after onWheel.
        tail = self.source.split(handler, 1)[1]
        self.assertNotIn("closeRequested", tail)

    def test_afterimage_suppression_survives_inside_dismiss_for(self) -> None:
        body = self.source.split("function dismissFor(mouse)", 1)[1]
        self.assertIn("root.suppressAfterimage", body)
        self.assertIn("root.lastClosedRect", body)
        self.assertIn("return false;", body)
        self.assertIn("return true;", body)

    def test_surface_stays_keyboard_passive(self) -> None:
        # F-13 note: the dismiss surface must never take keyboard focus.
        self.assertIn("focusable: false", self.source)

    def test_dismiss_for_logic_runs_and_gates_afterimage(self) -> None:
        """Execute the extracted dismissFor body (node, wallpaper-test
        precedent): the decision logic itself must run and gate correctly —
        a structural scope lock alone cannot prove the body is executable."""
        match = re.search(
            r"function dismissFor\(mouse\) \{(.*?)\n    \}", self.source, re.S
        )
        self.assertIsNotNone(match)

        def run(suppress: bool, x: int, y: int) -> bool:
            helper = (
                "const root = {suppressAfterimage: %s, cutoutPadding: 8, "
                "lastClosedRect: {x: 100, y: 100, width: 50, height: 50}};\n"
                "function dismissFor(mouse) {%s}\n"
                "console.log(JSON.stringify(dismissFor({x: %d, y: %d})));"
            ) % (json.dumps(suppress), match.group(1), x, y)
            result = subprocess.run(
                ["node", "-e", helper], capture_output=True, text=True, check=True
            )
            return json.loads(result.stdout)

        self.assertFalse(
            run(True, 120, 120), "afterimage click inside footprint must be ignored"
        )
        self.assertTrue(
            run(True, 400, 400), "afterimage window must not eat clicks elsewhere"
        )
        self.assertTrue(run(False, 120, 120), "no suppress window → always dismiss")


if __name__ == "__main__":
    unittest.main()
