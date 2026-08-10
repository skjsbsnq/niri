#!/usr/bin/env python3
"""D1 contract tests: Dock compact geometry tier.

Source-level guards (same style as test_dock_rectangle_rest_geometry.py) for the
compact-mode remediation. Three things must hold:

1. The STANDARD tier is byte-for-byte the pre-D1 geometry. Every tier-switched
   token must still yield its historical literal when ``dockCompact`` is false,
   so enabling the feature cannot regress the default look.
2. The COMPACT tier is internally consistent: nothing taller than the shelf it
   sits in (the vertical centring at dockRow clamps to 0 and overflows the glass
   otherwise), full-output width, and flush corners.
3. The input mask stays honest. The chrome spans the whole output in compact,
   but the transparent magnification headroom above the bar must NOT swallow
   pointer events, and the standard tier's mask must be unchanged.

These are text guards, not a running QML scene: they pin the shape of the
bindings so a later edit cannot quietly reintroduce a literal.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOCK = ROOT / "components" / "Dock.qml"
WINDOW_BUTTON = ROOT / "components" / "WindowButton.qml"
DESKTOP_SETTINGS = ROOT / "services" / "DesktopSettings.qml"
DOCK_PAGE = ROOT / "components" / "settings" / "pages" / "DockPage.qml"


def code_only(text: str) -> str:
    """Strip // line comments so prose naming a token cannot false-positive."""
    return "\n".join(line.split("//", 1)[0] for line in text.splitlines())


def slice_between(text: str, start: str, end: str) -> str:
    i = text.index(start)
    j = text.index(end, i)
    return text[i:j]


# Every geometry token that gained a tier switch, with the literal it MUST still
# produce in the standard tier (the pre-D1 value) and its compact counterpart.
# standard values verified against git HEAD~ of Dock.qml before the D1 edit.
TIER_TOKENS = {
    "dockIconSize": (48, 36),
    "dockOuterMargin": (28, 0),
    "dockSurfacePadding": (32, 12),
    "dockItemSpacing": (8, 6),
    "dockPinnedButtonWidth": (64, 48),
    "dockWindowTitleWidth": (132, 120),
    "dockWindowIconWidth": (60, 46),
    "dockMinimizedThumbnailWidth": (112, 84),
    "dockMinimizedMinimumWidth": (76, 60),
    "dockToolButtonWidth": (56, 44),
    "dockSurfaceHeight": (84, 56),
    "dockPinnedRowHeight": (70, 52),
    "dockWindowRowHeight": (60, 48),
    "dockTitledIconSize": (40, 30),
    "dockMinimizedThumbnailHeight": (62, 44),
    "dockToolIconSize": (40, 32),
}


class CompactTierTokenTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = DOCK.read_text(encoding="utf-8")
        self.code = code_only(self.text)

    def test_every_token_is_a_single_tier_switch(self) -> None:
        # Form-agnostic on whitespace, strict on values: each token must be a
        # ternary on dockCompact with exactly (compact, standard) as its arms.
        # A second declaration of the same token (a parallel interface) would
        # break the count assertion below.
        for token, (standard, compact) in TIER_TOKENS.items():
            with self.subTest(token=token):
                decls = re.findall(
                    rf"readonly\s+property\s+int\s+{token}\s*:([^\n]*)",
                    self.code,
                )
                self.assertEqual(
                    len(decls), 1, f"{token} must be declared exactly once"
                )
                body = decls[0]
                m = re.search(
                    r"dockCompact\s*\?\s*(\d+)\s*:\s*(\d+)", body
                )
                self.assertIsNotNone(
                    m, f"{token} must be a dockCompact ternary, got: {body.strip()}"
                )
                self.assertEqual(
                    (int(m.group(1)), int(m.group(2))),
                    (compact, standard),
                    f"{token} tier values wrong",
                )

    def test_tier_flag_reads_the_settings_service(self) -> None:
        self.assertRegex(
            self.code,
            r"readonly\s+property\s+bool\s+dockCompact:\s*!!\(settingsService\s*&&\s*settingsService\.dockCompact\)",
        )

    def test_compact_rows_fit_inside_the_compact_shelf(self) -> None:
        # dockRow centres with (dockSurfaceHeight - dockPinnedRowHeight) / 2,
        # which Math.max clamps to 0 — a row taller than the shelf silently
        # overflows the glass instead of erroring.
        shelf_std, shelf_compact = TIER_TOKENS["dockSurfaceHeight"]
        for token in ("dockPinnedRowHeight", "dockWindowRowHeight"):
            std, compact = TIER_TOKENS[token]
            with self.subTest(token=token):
                self.assertLessEqual(compact, shelf_compact, f"{token} overflows compact shelf")
                self.assertLessEqual(std, shelf_std, f"{token} overflows standard shelf")

    def test_compact_icon_fits_inside_the_compact_row(self) -> None:
        self.assertLessEqual(
            TIER_TOKENS["dockIconSize"][1], TIER_TOKENS["dockWindowRowHeight"][1]
        )

    def test_shelf_thumbnail_height_tracks_the_tier(self) -> None:
        # The shelf's own default (62) is taller than the compact window row,
        # so Dock must drive it down or minimized thumbnails clip. The tier
        # values themselves are pinned by TIER_TOKENS above.
        self.assertIn("thumbnailHeight: root.dockMinimizedThumbnailHeight", self.code)
        self.assertLessEqual(
            TIER_TOKENS["dockMinimizedThumbnailHeight"][1],
            TIER_TOKENS["dockWindowRowHeight"][1],
        )

    def test_window_button_row_height_is_driven_not_hardcoded(self) -> None:
        wb = code_only(WINDOW_BUTTON.read_text(encoding="utf-8"))
        # The pre-D1 literal `height: 60` on the delegate root is gone.
        self.assertNotRegex(wb, r"\n    height:\s*60\b")
        self.assertRegex(wb, r"property\s+int\s+rowHeight:\s*60")
        self.assertRegex(wb, r"\n    height:\s*rowHeight\b")
        self.assertIn("rowHeight: root.dockWindowRowHeight", self.code)


class CompactWidthAndRadiusTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = DOCK.read_text(encoding="utf-8")
        self.code = code_only(self.text)

    def test_chrome_width_spans_output_only_in_compact(self) -> None:
        m = re.search(
            r"readonly\s+property\s+real\s+dockChromeTargetWidth:\s*root\.dockCompact\s*"
            r"\?\s*root\.width\s*:\s*Math\.min\(dockSurfaceMaxWidth,\s*dockRowTargetWidth\s*\+\s*dockSurfacePadding\)",
            self.code,
        )
        self.assertIsNotNone(
            m, "compact must span root.width; standard must keep the clamped content width"
        )

    def test_glass_is_flush_in_compact_and_rounded_in_standard(self) -> None:
        # Radius follows the LIVE width, not the tier flag, so corners change
        # in step with the width Behavior instead of a frame ahead of it.
        m = re.search(
            r"radius:\s*dockChrome\.width\s*>=\s*root\.width\s*-\s*0\.5\s*\?\s*0\s*:\s*GlassStyle\.RadiusMenu",
            self.code,
        )
        self.assertIsNotNone(m, "compact glass must go flush only once it spans the output")
        self.assertNotIn("radius: root.dockCompact ? 0", self.code)

    def test_glass_region_still_tracks_the_chrome(self) -> None:
        # Region geometry follows the chrome in both tiers; nothing about D1
        # may introduce a second glass region or a wave-driven extent.
        self.assertIn("regionX: Math.round(dockChrome.x)", self.code)
        self.assertIn("regionWidth: Math.round(dockChrome.width)", self.code)
        self.assertEqual(self.code.count("TahoeGlass.regions:"), 1)
        self.assertEqual(self.code.count("GlassPanel {"), 1)

    def test_no_spring_on_glass_or_tier_geometry(self) -> None:
        # P-1: glass region geometry must never be spring-driven. The two
        # pre-existing springs drive content offsets (dockSlideOffset, the
        # launch bounceOffset), which is allowed; assert D1 added none and that
        # no spring targets a region/radius/width property.
        self.assertEqual(self.code.count("SpringAnimation {"), 2)
        for m in re.finditer(r"SpringAnimation\s*\{(.*?)\n\s*\}", self.code, re.S):
            body = m.group(1)
            prop = re.search(r'property:\s*"([^"]+)"', body)
            self.assertIsNotNone(prop, "spring must name its target property")
            self.assertIn(
                prop.group(1),
                ("dockSlideOffset", "bounceOffset"),
                "no spring may drive glass region geometry (P-1)",
            )

    def test_no_hardcoded_duration_literals(self) -> None:
        # P-3: Motion.js is the only source of durations.
        self.assertNotRegex(self.code, r"duration:\s*\d+")


class CompactInputMaskTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = DOCK.read_text(encoding="utf-8")
        self.code = code_only(self.text)
        self.mask = slice_between(self.code, "mask: Region {", "TahoeGlass.regions:")

    def test_content_box_collapses_to_chrome_in_standard(self) -> None:
        # Standard tier the content box IS the chrome, so the first mask region
        # is the pre-D1 region verbatim (same x, same width).
        m = re.search(
            r"readonly\s+property\s+real\s+dockContentBoxWidth:\s*root\.dockCompact\s*"
            r"\?\s*Math\.min\(dockChrome\.width,\s*dockRowTargetWidth\s*\+\s*dockSurfacePadding\)\s*"
            r":\s*dockChrome\.width",
            self.code,
        )
        self.assertIsNotNone(m, "standard tier content box must equal the chrome width")
        self.assertIn("dockContentBoxX: dockChrome.x", self.code)

    def test_content_region_uses_the_content_box(self) -> None:
        self.assertIn("x: Math.round(root.dockContentBoxX)", self.mask)
        self.assertIn("width: root.dockContentBoxWidth", self.mask)

    def test_full_width_strip_is_compact_only_and_excludes_headroom(self) -> None:
        # The bar-wide hit area must track the LIVE chrome width (it eases over
        # the tier switch), never the tier flag, and its height must be the
        # glass only (dockVisibleHeight) — never the chrome height, which would
        # swallow the transparent magnification headroom.
        self.assertIn("width: dockChrome.width", self.mask)
        strip = slice_between(self.mask, "width: dockChrome.width", "}")
        self.assertIn("root.dockVisibleHeight", strip)
        self.assertNotIn("dockMagHeadroom", strip)
        # No flag-driven strip may exist (instant full-output claim).
        self.assertNotIn("root.dockCompact ? root.width : 0", self.mask)

    def test_headroom_still_reachable_through_the_content_region(self) -> None:
        # Magnified icons paint above the glass; the content region keeps the
        # headroom so hovering a peaked icon still hits the Dock. Slice to the
        # start of the next region rather than a comment (code_only strips those).
        content = slice_between(
            self.mask,
            "x: Math.round(root.dockContentBoxX)",
            "x: Math.round(dockChrome.x)",
        )
        self.assertIn("root.dockMagHeadroom", content)

    def test_reveal_zone_region_unchanged(self) -> None:
        self.assertIn("height: root.dockAutoHide ? Math.max(2, root.dockRevealZoneHeight) : 0", self.mask)

    def test_mask_has_exactly_three_child_regions(self) -> None:
        # Content box, compact-only full-width strip, autohide reveal zone.
        # The slice starts at the outer "mask: Region {", hence 3 children + 1.
        self.assertEqual(self.mask.count("Region {"), 4)


class CompactSettingsPlumbingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.settings = code_only(DESKTOP_SETTINGS.read_text(encoding="utf-8"))
        self.page = code_only(DOCK_PAGE.read_text(encoding="utf-8"))

    def test_setting_is_declared_defaulted_and_settable(self) -> None:
        # All four sites, matching the five pre-existing dock keys.
        self.assertRegex(
            self.settings, r"readonly\s+property\s+bool\s+dockCompact:\s*settingsAdapter\.dockCompact"
        )
        self.assertRegex(self.settings, r"property\s+bool\s+dockCompact:\s*false")
        self.assertIn("function setDockCompact(enabled)", self.settings)

    def test_setter_persists_and_is_idempotent(self) -> None:
        fn = slice_between(self.settings, "function setDockCompact(enabled)", "\n    function ")
        self.assertIn("if (settingsAdapter.dockCompact === next)", fn)
        self.assertIn("return;", fn)
        self.assertIn("settingsFile.writeAdapter();", fn)

    def test_settings_page_exposes_the_toggle(self) -> None:
        self.assertIn("setDockCompact", self.page)
        self.assertIn("紧凑模式", self.page)


if __name__ == "__main__":
    unittest.main()
