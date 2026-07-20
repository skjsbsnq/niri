#!/usr/bin/env python3
"""Compact media title cleaner: primary name in the pill, full title when expanded.

Locks Task A+safety:
- compactPrimaryTitle strips trailing version/remix/DJ bracket tags
- empty / over-aggressive clean falls back to original
- displayTitle uses cleaned only while compact (pArt < 0.45)
- expanded keeps full resolvedTitle
- pure string helper on MediaView — no second media controller
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
VIEW = SHELL / "components" / "DynamicIslandMediaView.qml"
CONTENT = SHELL / "components" / "DynamicIslandContent.qml"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _function_body(src: str, name: str) -> str:
    m = re.search(rf"function\s+{re.escape(name)}\s*\([^)]*\)\s*\{{", src)
    if not m:
        return ""
    start = m.end()
    depth = 1
    i = start
    while i < len(src) and depth:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
        i += 1
    return src[start : i - 1]


class DynamicIslandCompactTitleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.view = _read(VIEW)
        cls.content = _read(CONTENT)
        cls.cleaner = _function_body(cls.view, "compactPrimaryTitle")

    def test_cleaner_exists_and_is_pure(self) -> None:
        self.assertIn("function compactPrimaryTitle", self.view)
        self.assertTrue(len(self.cleaner) > 40)
        # No MPRIS / player walk inside the cleaner.
        self.assertNotIn("Mpris", self.cleaner)
        self.assertNotIn("activePlayer", self.cleaner)
        self.assertNotIn("controlsService", self.cleaner)

    def test_strips_trailing_version_brackets(self) -> None:
        # Bracket peel helpers for "琵琶曲(DJKK0.9X版)" → "琵琶曲".
        self.assertIn("function stripTrailingBracketGroup", self.view)
        self.assertIn("function stripTrailingDashTag", self.view)
        self.assertIn("isOpenBracket", self.view)
        self.assertIn("isCloseBracket", self.view)
        # Multiple peel passes for nested tags.
        self.assertIn("pass < 4", self.cleaner)
        # Remix / remaster / live / official dash suffixes.
        body = _function_body(self.view, "stripTrailingDashTag")
        self.assertIn("remix", body.lower())
        self.assertIn("remaster", body.lower())
        self.assertIn("official", body.lower())

    def test_safety_fallbacks(self) -> None:
        self.assertIn("正在播放", self.cleaner)
        self.assertIn("return original", self.cleaner)
        # Must not return empty after over-strip.
        self.assertIn("s.length === 0", self.cleaner)
        # Prefix / relatedness check against unrelated rewrites.
        self.assertIn("indexOf", self.cleaner)
        self.assertIn("stripTrailingBracketGroup", self.cleaner)

    def test_display_title_compact_vs_expanded(self) -> None:
        self.assertIn("compactDisplayTitle", self.view)
        self.assertIn("displayTitle", self.view)
        self.assertIn("compactPrimaryTitle(root.resolvedTitle)", self.view)
        # Compact path uses cleaned title.
        self.assertRegex(
            self.view,
            r"displayTitle:.*pArt\s*<\s*0\.45[\s\S]*?compactDisplayTitle",
        )
        # Title label binds displayTitle (not raw trackTitle alone).
        self.assertIn("text: root.displayTitle", self.view)
        # Full title still available as resolvedTitle for expanded.
        self.assertIn("resolvedTitle", self.view)

    def test_compact_width_uses_cleaned_measure(self) -> None:
        # Pill width reserve must not measure the dirty long title.
        self.assertIn("compactTitleMeasure", self.view)
        self.assertIn("text: root.compactDisplayTitle", self.view)
        self.assertIn("compactTitleMeasure.implicitWidth", self.view)

    def test_no_second_media_owner(self) -> None:
        code = re.sub(r"//[^\n]*", "", self.view)
        self.assertNotIn("IslandMprisController", code)
        self.assertNotIn("Mpris.players", code)
        # Content still forwards mediaTrackTitle from service only.
        self.assertIn("mediaTrackTitle", self.content)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
