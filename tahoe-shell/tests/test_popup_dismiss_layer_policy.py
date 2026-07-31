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


if __name__ == "__main__":
    unittest.main()
