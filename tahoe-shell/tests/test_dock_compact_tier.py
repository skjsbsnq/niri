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

import math
import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path
from types import SimpleNamespace


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


# D2 changed the contract: SIZE comes from two settings sliders, SHAPE from the
# tier flag. Only these three keep a tier ternary — anything else regaining one
# would mean a size is being decided in two places.
SHAPE_TOKENS = {
    "dockOuterMargin": (28, 0),
    "dockSurfacePadding": (32, 12),
    "dockItemSpacing": (8, 6),
}

# Slider-derived geometry, evaluated directly from the QML. The formulas are
# tiny arithmetic expressions, so this parses each declaration and plugs the
# two slider values in rather than transcribing the formulas to Python — a
# transcription would silently go stale when the QML changes.
def extract_formula(code: str, token: str) -> str:
    m = re.search(
        rf"readonly\s+property\s+(?:real|int)\s+{token}\s*:\s*(.*?)(?=\n\s*(?:readonly|//|\n))",
        code,
        re.S,
    )
    assert m, f"{token} declaration not found"
    return m.group(1).strip()


def to_python(formula: str) -> str:
    """Translate the small QML expression subset used by the geometry block.

    Only the `cond ? a : b` form differs from Python; everything else is plain
    arithmetic and Math.* calls. Rewritten rather than transcribed so the test
    keeps reading the real QML.
    """
    flat = " ".join(formula.split())
    while "?" in flat:
        q = flat.index("?")
        # Find the matching ':' at the same paren depth.
        depth = 0
        colon = None
        for i in range(q + 1, len(flat)):
            c = flat[i]
            if c == "(":
                depth += 1
            elif c == ")":
                if depth == 0:
                    break
                depth -= 1
            elif c == ":" and depth == 0:
                colon = i
                break
        assert colon is not None, f"unbalanced ternary in: {formula}"
        # Condition extends back to the start or the enclosing '('.
        depth = 0
        start = 0
        for i in range(q - 1, -1, -1):
            c = flat[i]
            if c == ")":
                depth += 1
            elif c == "(":
                if depth == 0:
                    start = i + 1
                    break
                depth -= 1
        # Consequent ends at the matching ')' or end of string.
        depth = 0
        end = len(flat)
        for i in range(colon + 1, len(flat)):
            c = flat[i]
            if c == "(":
                depth += 1
            elif c == ")":
                if depth == 0:
                    end = i
                    break
                depth -= 1
        cond = flat[start:q].strip()
        then = flat[q + 1:colon].strip()
        other = flat[colon + 1:end].strip()
        flat = f"{flat[:start]}(({then}) if ({cond}) else ({other})){flat[end:]}"
    return flat


DERIVED_TOKENS = (
    "dockIconSizePref", "dockIconSize", "dockPinnedButtonWidth", "dockWindowTitleWidth",
    "dockWindowIconWidth", "dockMinimizedThumbnailWidth",
    "dockMinimizedMinimumWidth", "dockToolButtonWidth",
    "dockPinnedRowHeight", "dockWindowRowHeight", "dockTitledIconSize",
    "dockMinimizedThumbnailHeight", "dockToolIconSize",
)


class _Math:
    """The Math.* subset the geometry block uses, with JS argument semantics."""

    round = staticmethod(lambda v: math.floor(v + 0.5))
    min = staticmethod(lambda *a: min(a))
    max = staticmethod(lambda *a: max(a))
    ceil = staticmethod(math.ceil)
    floor = staticmethod(math.floor)


def derive(code: str, shelf: int, icon_pref: int) -> dict:
    """Solve the QML geometry formulas for one slider pair.

    Resolves by fixpoint so declaration order in the QML does not matter: a
    formula is evaluated once every name it references is known.
    """
    formulas = {t: to_python(extract_formula(code, t)) for t in DERIVED_TOKENS}
    solved = {"dockSurfaceHeight": shelf}
    env = {"Math": _Math, "settingsService": SimpleNamespace(dockIconSizePx=icon_pref)}
    for _ in range(len(formulas) + 1):
        for token, formula in formulas.items():
            if token in solved:
                continue
            try:
                value = eval(formula, {"__builtins__": {}}, {**env, **solved})
            except NameError:
                continue  # depends on a token not solved yet
            solved[token] = int(round(value))
        if all(t in solved for t in formulas):
            break
    missing = [t for t in formulas if t not in solved]
    assert not missing, f"unresolved formulas (cycle or unknown name): {missing}"
    return solved

def _settings_int(name: str) -> int:
    ds = code_only(DESKTOP_SETTINGS.read_text(encoding="utf-8"))
    m = re.search(rf"readonly\s+property\s+int\s+{name}\s*:\s*(\d+)", ds)
    assert m, f"{name} not found in DesktopSettings.qml"
    return int(m.group(1))


# The standard preset is a hard regression gate: these are the pre-D1 literals
# and every one must still be reproduced exactly at shelf=84 / icon=48.
STANDARD_PRESET = (84, 48)
HISTORICAL_STANDARD = {
    "dockIconSize": 48,
    "dockPinnedButtonWidth": 64,
    "dockWindowTitleWidth": 132,
    "dockWindowIconWidth": 60,
    "dockMinimizedThumbnailWidth": 112,
    "dockMinimizedMinimumWidth": 76,
    "dockToolButtonWidth": 56,
    "dockPinnedRowHeight": 70,
    "dockWindowRowHeight": 60,
    "dockTitledIconSize": 40,
    "dockMinimizedThumbnailHeight": 62,
    "dockToolIconSize": 40,
}

COMPACT_PRESET = (
    _settings_int("dockCompactSurfaceHeight"),
    _settings_int("dockCompactIconSize"),
)

# Slider bounds. Read from DesktopSettings rather than mirrored, so widening a
# bound there re-runs the coherence sweep over the NEW range instead of leaving
# this file silently guarding the old one. (A min of 24, say, would drive
# dockIconSize into its Math.max(16, ...) floor and put the window row above
# the pinned row — the sweep must see that.)
SURFACE_RANGE = (_settings_int("dockSurfaceHeightMin"), _settings_int("dockSurfaceHeightMax"))
ICON_RANGE = (_settings_int("dockIconSizeMin"), _settings_int("dockIconSizeMax"))


class CompactTierTokenTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = DOCK.read_text(encoding="utf-8")
        self.code = code_only(self.text)

    def test_shape_tokens_are_the_only_tier_switches(self) -> None:
        # Form-agnostic on whitespace, strict on values.
        for token, (standard, compact) in SHAPE_TOKENS.items():
            with self.subTest(token=token):
                decls = re.findall(
                    rf"readonly\s+property\s+int\s+{token}\s*:([^\n]*)",
                    self.code,
                )
                self.assertEqual(len(decls), 1, f"{token} must be declared exactly once")
                m = re.search(r"dockCompact\s*\?\s*(\d+)\s*:\s*(\d+)", decls[0])
                self.assertIsNotNone(m, f"{token} must be a dockCompact ternary")
                self.assertEqual((int(m.group(1)), int(m.group(2))), (compact, standard))

    def test_sizes_never_branch_on_the_tier(self) -> None:
        # D2's core invariant: a size must not be decided in two places. If any
        # slider-derived token regains a dockCompact ternary, the toggle and the
        # slider would both own it (G-6 parallel interface).
        for token in DERIVED_TOKENS:
            with self.subTest(token=token):
                formula = extract_formula(self.code, token)
                self.assertNotIn(
                    "dockCompact", formula,
                    f"{token} is a SIZE — it must derive from the sliders, not the tier",
                )

    def test_sizes_read_the_settings_sliders(self) -> None:
        self.assertRegex(
            self.code,
            r"readonly\s+property\s+int\s+dockSurfaceHeight:\s*settingsService\s*\n?\s*\?\s*settingsService\.dockSurfaceHeightPx",
        )
        self.assertIn("settingsService.dockIconSizePx", self.code)

    def test_standard_preset_reproduces_the_historical_geometry(self) -> None:
        # The shipped default must be byte-identical to the pre-D1 look; the
        # formulas are anchored so shelf=84 / icon=48 yields the T08-fix values.
        got = derive(self.code, *STANDARD_PRESET)
        for token, expected in HISTORICAL_STANDARD.items():
            with self.subTest(token=token):
                self.assertEqual(got[token], expected, f"{token} drifted from the pre-D1 value")

    def test_tier_flag_reads_the_settings_service(self) -> None:
        self.assertRegex(
            self.code,
            r"readonly\s+property\s+bool\s+dockCompact:\s*!!\(settingsService\s*&&\s*settingsService\.dockCompact\)",
        )

    def test_geometry_is_coherent_across_the_whole_slider_range(self) -> None:
        # dockRow centres with Math.max(0, (shelf - row) / 2): a row taller than
        # its shelf does not error, it silently spills out of the glass. Check
        # every reachable slider combination, not just the two presets.
        for shelf in range(SURFACE_RANGE[0], SURFACE_RANGE[1] + 1):
            for icon_pref in range(ICON_RANGE[0], ICON_RANGE[1] + 1):
                d = derive(self.code, shelf, icon_pref)
                icon = d["dockIconSize"]
                self.assertGreaterEqual(icon, 16, f"icon collapsed at {shelf}/{icon_pref}")
                self.assertLessEqual(
                    d["dockPinnedRowHeight"], shelf,
                    f"pinned row overflows shelf at {shelf}/{icon_pref}",
                )
                self.assertLessEqual(
                    d["dockWindowRowHeight"], shelf,
                    f"window row overflows shelf at {shelf}/{icon_pref}",
                )
                self.assertLessEqual(
                    icon, shelf,
                    f"icon taller than the shelf at {shelf}/{icon_pref}",
                )
                # The window section's host is dockPinnedRowHeight tall
                # (Dock.qml: "REST height only — center the window row inside
                # pinned row height"), so the window row must fit inside it,
                # not merely inside the shelf.
                self.assertLessEqual(
                    d["dockWindowRowHeight"], d["dockPinnedRowHeight"],
                    f"window row overflows its pinned-row host at {shelf}/{icon_pref}",
                )
                # WindowButton lays its glyph out at y = rowHeight - icon - 6.
                for glyph in (icon, d["dockTitledIconSize"]):
                    self.assertGreaterEqual(
                        d["dockWindowRowHeight"] - glyph - 6, 0,
                        f"WindowButton icon.y negative at {shelf}/{icon_pref}",
                    )
                # Slots must stay wide enough to seat the glyph they contain.
                self.assertGreater(d["dockPinnedButtonWidth"], icon)
                self.assertGreater(d["dockWindowIconWidth"], icon)
                self.assertGreater(d["dockToolButtonWidth"], d["dockToolIconSize"])

    def test_compact_preset_stays_compact(self) -> None:
        std = derive(self.code, *STANDARD_PRESET)
        cmp_ = derive(self.code, *COMPACT_PRESET)
        self.assertLess(COMPACT_PRESET[0], STANDARD_PRESET[0])
        self.assertLess(cmp_["dockIconSize"], std["dockIconSize"])
        self.assertLess(cmp_["dockPinnedRowHeight"], std["dockPinnedRowHeight"])

    def test_shelf_thumbnail_height_is_driven_from_dock(self) -> None:
        # The shelf's own default (62) is taller than a compact window row, so
        # Dock must drive it or minimized thumbnails clip.
        self.assertIn("thumbnailHeight: root.dockMinimizedThumbnailHeight", self.code)

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
        # Both arms must be GlassStyle tokens: scripts/check-tahoe-glass-guardrails.sh
        # requires glass-panel radii to come from the token table, and a naked
        # 0 here previously broke that guard.
        m = re.search(
            r"radius:\s*dockChrome\.width\s*>=\s*root\.width\s*-\s*0\.5\s*"
            r"\?\s*GlassStyle\.RadiusBackdrop\s*:\s*GlassStyle\.RadiusMenu",
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


    def test_compact_seed_guarded_by_stored_key(self) -> None:
        # Upgrade path: a pre-D2 config has dockCompact but no size keys. The
        # seed must (a) exist, (b) be gated on the keys being ABSENT (not just
        # "at default"), so a user's explicit size is never overwritten.
        ds = code_only(DESKTOP_SETTINGS.read_text(encoding="utf-8"))
        seed = slice_between(
            ds, "if (settingsAdapter.dockCompact\n", "\n        }\n"
        )
        self.assertIn("storedKey", seed)
        self.assertIn("dockCompactSurfaceHeight", seed)
        self.assertIn("dockCompactIconSize", seed)
        # The gate must check absence of BOTH keys.
        self.assertIn('storedKey("dockSurfaceHeightPx")', seed)
        self.assertIn('storedKey("dockIconSizePx")', seed)

    def test_stored_key_helper_treats_unreadable_as_present(self) -> None:
        # If the file cannot be parsed, storedKey must return true so the seed
        # never fires on an unreadable config (which would stomp it on retry).
        ds = code_only(DESKTOP_SETTINGS.read_text(encoding="utf-8"))
        body = slice_between(ds, "function storedKey(name)", "\n    function ")
        self.assertIn("JSON.parse(raw)[name] !== undefined", body)
        self.assertIn("catch", body)
        # The catch arm returns true (fail closed).
        self.assertRegex(body, r"catch\s*\(e\)\s*\{[^}]*return true;")


class CompactSettingsPlumbingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.settings = code_only(DESKTOP_SETTINGS.read_text(encoding="utf-8"))
        self.page = code_only(DOCK_PAGE.read_text(encoding="utf-8"))

    def test_adapter_defaults_match_the_declared_constants(self) -> None:
        # A JsonAdapter default cannot reference `root`, so these two literals
        # are the one place the defaults are restated. Without this guard,
        # retuning dockSurfaceHeightDefault would leave a FRESH config still
        # getting the old value from the adapter — and sanitizeState would not
        # correct it, because the stale value is still in range.
        adapter = slice_between(self.settings, "JsonAdapter {", "wallpaperMode:")
        for prop, const in (
            ("dockSurfaceHeightPx", "dockSurfaceHeightDefault"),
            ("dockIconSizePx", "dockIconSizeDefault"),
        ):
            with self.subTest(prop=prop):
                m = re.search(rf"property\s+int\s+{prop}\s*:\s*(\d+)", adapter)
                self.assertIsNotNone(m, f"{prop} must have a literal adapter default")
                self.assertEqual(
                    int(m.group(1)), _settings_int(const),
                    f"{prop} adapter default drifted from {const}",
                )

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


class QmlPropertyNamingTests(unittest.TestCase):
    """QML rejects property names starting with an upper-case letter.

    ``qmllint --bare`` does not report it, and the failure mode is the worst
    kind: the whole shell refuses to load at startup with
    "Property names cannot begin with an upper case letter". D2 hit this by
    naming slider bounds DOCK_SURFACE_HEIGHT_MIN, so guard every QML file the
    Dock feature touches (cheap enough to cover the whole tree).
    """

    def test_no_property_name_begins_with_an_upper_case_letter(self) -> None:
        offenders = []
        for path in sorted(ROOT.rglob("*.qml")):
            # Strip // comments: prose mentioning "property ... Reason" would
            # otherwise false-positive (same guard as code_only above).
            for lineno, line in enumerate(
                code_only(path.read_text(encoding="utf-8")).splitlines(), 1
            ):
                # finditer, not search: semicolon-chained declarations on one
                # line are an idiom here (see tst_app_menu_probe_identity.qml),
                # and search would only ever inspect the first of them.
                for m in re.finditer(
                    r"\bproperty\s+(?:readonly\s+)?[A-Za-z_][\w.<>]*\s+([A-Za-z_]\w*)", line
                ):
                    if m.group(1)[0].isupper():
                        offenders.append(f"{path.relative_to(ROOT)}:{lineno}: {m.group(1)}")
        self.assertEqual(offenders, [], "QML property names must start lower-case")


class SettingsServiceLoadsInARealEngineTests(unittest.TestCase):
    """Load DesktopSettings in a real QML engine.

    The static guards above cannot catch every load-time rejection, and a shell
    that will not start is the highest-cost regression in this repo.
    """

    def test_desktop_settings_instantiates(self) -> None:
        runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner_path = str(runner) if runner.is_file() else shutil.which("qmltestrunner")
        if runner_path is None:
            self.skipTest("qmltestrunner not available")

        probe = ROOT / "tests" / "tst_dock_settings_load_probe.qml"
        env = os.environ.copy()
        env.setdefault("QT_QPA_PLATFORM", "offscreen")
        env["QT_QUICK_BACKEND"] = "software"
        # Same import wiring as the other real-engine tests: local Quickshell
        # modules plus the in-repo stubs.
        local_qml = Path.home() / ".local" / "lib" / "qt6" / "qml"
        paths = [str(ROOT / "tests" / "qml_imports"), str(local_qml)]
        existing = env.get("QML2_IMPORT_PATH", "")
        if existing:
            paths.append(existing)
        env["QML2_IMPORT_PATH"] = ":".join(paths)
        result = subprocess.run(
            [runner_path, "-input", str(probe)],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("cannot begin with an upper case", result.stdout)


if __name__ == "__main__":
    unittest.main()
