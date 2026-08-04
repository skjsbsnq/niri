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
from typing import NamedTuple


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


def paints_into_corners(body: str) -> bool:
    """True when a full-fill child would paint outside a rounded silhouette.

    Presence of `radius` is not enough: `radius: 4` inside an 18-radius card
    still notches, and `radius: 0.0` is a zero that string comparison misses.
    """
    radius = own_property(body, "radius")
    if radius is None:
        return True
    try:
        return float(radius) == 0.0
    except ValueError:
        # A binding (e.g. `menuSurface.radius`) tracks the container; the
        # dedicated scrim test pins that the binding is the right one.
        return False


class Child(NamedTuple):
    type: str
    body: str


def paints_a_fill(child: "Child") -> bool:
    """True when this child actually rasterizes pixels across its whole box.

    Layout and input types (RowLayout, MouseArea, Item…) paint nothing, so a
    missing radius on them is irrelevant. Only fills that rasterize can notch.
    """
    if child.type == "Rectangle":
        color = own_property(child.body, "color")
        if own_property(child.body, "gradient") is not None:
            return True
        return color is not None and color != '"transparent"'
    if child.type in ("Image", "AnimatedImage", "ShaderEffect", "ShaderEffectSource"):
        return True
    # A component instantiation paints only if it is handed a visible fill.
    background = own_property(child.body, "backgroundColor")
    return background is not None and background != '"transparent"'


def direct_children(body: str) -> list["Child"]:
    """Immediate child element blocks, skipping grandchildren and groups."""
    children: list[Child] = []
    for match in re.finditer(r"^([ \t]*)([A-Z][A-Za-z0-9_.]*)\s*\{", body, re.MULTILINE):
        prefix = body[: match.start()]
        if prefix.count("{") - prefix.count("}") != 0:
            continue
        children.append(Child(match.group(2), block_at(body, body.index("{", match.start()))))
    return children


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
            if radius is not None and not paints_into_corners(body):
                continue
            line = self.menu[: match.start()].count("\n") + 1
            offenders.append(f"{MENU_POPUP.name}:{line} color={color}")
        self.assertEqual(offenders, [], f"square fill overlays: {offenders}")


class RoundedClipMisconceptionTests(unittest.TestCase):
    """Repo-wide: `clip: true` on a rounded card does NOT round its children.

    This is the misconception itself rather than one instance of it. Every
    known real occurrence sets `clip: true` on a rounded Rectangle and then
    fills it with an un-rounded child, so the signature is the guard.

    Entries in ALLOWED are corner-safe for a stated reason. A child inset by
    M inside a card of radius R never reaches a notch when M >= R*(1-1/sqrt2).
    """

    # path:line -> why it is not fixed here. These are pre-existing thumbnail
    # and album-art plates: their notches expose the parent card rather than
    # the wallpaper, so they read as "square art", not as dark blocks. Listed
    # so the guard still fails on any NEW occurrence. Remove an entry when the
    # site is fixed; do not add one without a reason.
    ALLOWED: dict[str, str] = {
        "ControlCenter.qml:1383": "album art plate, notch shows the panel",
        "DockMinimizedWindow.qml:329": "dock thumbnail + opaque fallback bg",
        "DynamicIslandCompactMediaView.qml:87": "art plate; view is not hosted",
        "DynamicIslandMediaView.qml:347": "art plate, notch shows the pill",
        "TaskSwitcher.qml:603": "window thumbnail, notch shows the card",
        "WindowOverview.qml:1106": "window thumbnail, notch shows the card",
    }

    def test_rounded_clipping_cards_do_not_rely_on_clip_to_round_children(self) -> None:
        offenders: list[str] = []
        for path in sorted(COMPONENTS.rglob("*.qml")):
            if "+test" in str(path):
                continue
            src = path.read_text(encoding="utf-8")
            for match in re.finditer(r"^[ \t]*Rectangle\s*\{", src, re.MULTILINE):
                body = block_at(src, src.index("{", match.start()))
                if own_property(body, "clip") != "true":
                    continue
                radius = own_property(body, "radius")
                if radius is None or radius == "0":
                    continue
                line = src[: match.start()].count("\n") + 1
                key = f"{path.relative_to(COMPONENTS)}:{line}"
                if key in self.ALLOWED:
                    continue
                for child in direct_children(body):
                    if not fills_parent(child.body):
                        continue
                    if not paints_a_fill(child):
                        continue
                    if not paints_into_corners(child.body):
                        continue
                    offenders.append(f"{key} <- {child.type}(fills, no radius)")
        self.assertEqual(
            offenders,
            [],
            "clip: true is a rectangular scissor; these children paint into "
            f"the card's corner notches: {offenders}",
        )


if __name__ == "__main__":
    unittest.main()
