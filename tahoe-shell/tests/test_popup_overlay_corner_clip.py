#!/usr/bin/env python3
"""Overlay fills inside rounded glass cards must round to the card silhouette.

Regression guard: MenuPopup's power-confirm scrim was an `anchors.fill: parent`
Rectangle with no radius. `menuSurface.clip` is a rectangular scissor and a
Rectangle's own `radius` does not clip its children, so the square scrim painted
dark blocks into the four corner notches outside the glass card. Verified by
offscreen pixel grab: a square 50% black child over a red backdrop leaves
(128,0,0) in the notch, versus (255,0,0) once the child carries the radius.

niri does not help here: for layer surfaces `geometry_corner_radius` only shapes
the shadow and the background/blur region (src/layer/mapped.rs), never the
client texture, so the rounded silhouette is entirely the client's job.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ROOT / "components"
MENU_POPUP = COMPONENTS / "MenuPopup.qml"


def block_at(text: str, opening: int) -> str:
    """Return the brace-balanced body starting at the `{` located at `opening`."""
    if text[opening] != "{":
        raise AssertionError(f"index {opening} is not an opening brace")
    depth = 1
    index = opening + 1
    while index < len(text) and depth:
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        index += 1
    if depth:
        raise AssertionError(f"unbalanced block at offset {opening}")
    return text[opening + 1 : index - 1]


def extract_block(text: str, start_pattern: str) -> str:
    """Body of the block whose header/first line matches `start_pattern`."""
    match = re.search(start_pattern, text, re.MULTILINE)
    if match is None:
        raise AssertionError(f"block pattern not found: {start_pattern}")
    opening = text.rfind("{", 0, match.end())
    if opening == -1:
        raise AssertionError(f"no opening brace before match: {start_pattern}")
    return block_at(text, opening)


def own_property(body: str, name: str) -> str | None:
    """Value of a property declared directly on this block, ignoring children.

    Scanning the raw body would attribute a nested child's `color:`/`radius:` to
    the parent, which is exactly how a square overlay could slip back in.
    """
    depth = 0
    index = 0
    pattern = re.compile(rf"^[ \t]*{name}:[ \t]*(.+?)[ \t]*$", re.MULTILINE)
    for line in body.split("\n"):
        if depth == 0:
            found = pattern.match(line)
            if found:
                return found.group(1)
        depth += line.count("{") - line.count("}")
        index += 1
    return None


def fills_parent(body: str) -> bool:
    """True for `anchors.fill: parent` and the grouped `anchors { fill: parent }`."""
    if own_property(body, r"anchors\.fill") == "parent":
        return True
    grouped = re.search(r"^[ \t]*anchors\s*\{", body, re.MULTILINE)
    if grouped:
        opening = body.index("{", grouped.start())
        return re.search(r"\bfill:\s*parent\b", block_at(body, opening)) is not None
    return False


class PopupOverlayCornerClipTests(unittest.TestCase):
    def setUp(self) -> None:
        self.menu = MENU_POPUP.read_text(encoding="utf-8")

    def test_confirm_scrim_rounds_to_the_glass_card(self) -> None:
        scrim = extract_block(self.menu, r"^\s*id:\s*confirmScrim\b")

        # It still covers the whole card (that is the point of a scrim)...
        self.assertTrue(fills_parent(scrim), "confirmScrim must still cover the card")
        # ...but it must not paint into the corner notches.
        radius = own_property(scrim, "radius")
        self.assertIsNotNone(
            radius,
            "confirmScrim needs a radius or it paints dark square corners "
            "outside the rounded glass card",
        )
        # Tracking the surface, not a hard-coded literal, so a RadiusMenu token
        # change cannot silently desync the scrim from the card.
        self.assertEqual(radius, "menuSurface.radius")

    def test_glass_surface_radius_stays_token_driven(self) -> None:
        surface = extract_block(self.menu, r"^\s*id:\s*menuSurface\b")
        self.assertEqual(own_property(surface, "radius"), "GlassStyle.RadiusMenu")

    def test_no_squarecornered_fill_overlay_inside_the_menu_card(self) -> None:
        """Any visible fill-parent Rectangle in MenuPopup must carry a radius."""
        offenders: list[str] = []
        # Scan by match position: re-searching by the matched text would rescan
        # the first of two identically-indented blocks and skip the second.
        for match in re.finditer(r"^[ \t]*Rectangle\s*\{", self.menu, re.MULTILINE):
            body = block_at(self.menu, self.menu.index("{", match.start()))
            if not fills_parent(body):
                continue
            color = own_property(body, "color")
            paints = own_property(body, "gradient") is not None or (
                color is not None and color != '"transparent"'
            )
            if not paints:
                continue
            radius = own_property(body, "radius")
            if radius is not None and radius != "0":
                continue
            line = self.menu[: match.start()].count("\n") + 1
            offenders.append(f"{MENU_POPUP.name}:{line} color={color}")
        self.assertEqual(offenders, [], f"square fill overlays: {offenders}")


if __name__ == "__main__":
    unittest.main()
