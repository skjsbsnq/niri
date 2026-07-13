#!/usr/bin/env python3
"""Task 12: InputMethod languageLabel must not label all IME as Chinese.

Root cause: languageLabel() returned \"中\" on both branches, so Japanese,
Korean, and unknown engines all displayed as Chinese.

Tests parse the live QML if-blocks (indexOf / equality / regex / returns)
so removing or relocating engine tokens in the QML fails the suite.
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass, field
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
INPUT_METHOD = SHELL_ROOT / "services" / "InputMethod.qml"


def extract_language_label_body(src: str) -> str:
    match = re.search(
        r"function languageLabel\(name\)\s*\{([\s\S]*?)\n    \}",
        src,
    )
    if not match:
        raise AssertionError("languageLabel function not found")
    return match.group(1)


def extract_display_text_binding(src: str) -> str:
    match = re.search(
        r"readonly property string displayText:\s*([^\n]+)",
        src,
    )
    if not match:
        raise AssertionError("displayText binding not found")
    return match.group(1)


def decode_qml_string(literal: str) -> str:
    """Decode a QML/JS string literal content (handles \\uXXXX)."""
    out: list[str] = []
    i = 0
    while i < len(literal):
        if literal[i] == "\\" and i + 1 < len(literal):
            nxt = literal[i + 1]
            if nxt == "u" and i + 5 < len(literal):
                out.append(chr(int(literal[i + 2 : i + 6], 16)))
                i += 6
                continue
            if nxt in "nrt\\\"'":
                out.append({"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"', "'": "'"}[nxt])
                i += 2
                continue
        out.append(literal[i])
        i += 1
    return "".join(out)


@dataclass
class PredicateBranch:
    """One if-branch extracted from languageLabel."""

    condition: str
    return_glyph: str
    indexof_needles: list[str] = field(default_factory=list)
    equality_values: list[str] = field(default_factory=list)
    startswith_needles: list[str] = field(default_factory=list)  # indexOf(x) === 0
    regex_patterns: list[re.Pattern[str]] = field(default_factory=list)


def _extract_balanced_paren(text: str, open_idx: int) -> tuple[str, int]:
    """Given index of '(', return (inside, index_after_closing_paren)."""
    if open_idx >= len(text) or text[open_idx] != "(":
        raise AssertionError("expected '(' for balanced extract")
    depth = 0
    i = open_idx
    while i < len(text):
        ch = text[i]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return text[open_idx + 1 : i], i + 1
        i += 1
    raise AssertionError("unbalanced parentheses in languageLabel condition")


def parse_branches(body: str) -> tuple[str | None, list[PredicateBranch], str]:
    """Parse empty early-return, ordered if-branches, and final fallback from QML body."""
    empty_match = re.search(
        r'if\s*\(\s*text\.length\s*===\s*0\s*\)\s*\n\s*return\s+"([^"]+)"\s*;',
        body,
    )
    empty_glyph = decode_qml_string(empty_match.group(1)) if empty_match else None

    branches: list[PredicateBranch] = []
    pos = 0
    while True:
        m = re.search(r"\bif\s*\(", body[pos:])
        if not m:
            break
        abs_open = pos + m.end() - 1  # index of '('
        cond, after_cond = _extract_balanced_paren(body, abs_open)
        # Allow trailing comments on the if-line before the return.
        ret = re.match(
            r'(?:[ \t]*//[^\n]*)?\s*\n\s*return\s+"([^"]+)"\s*;',
            body[after_cond:],
        )
        if not ret:
            pos = after_cond
            continue
        glyph = decode_qml_string(ret.group(1))
        pos = after_cond + ret.end()

        # Skip empty-length guard (spaces may be stripped in check).
        compact_cond = re.sub(r"\s+", "", cond)
        if "text.length===0" in compact_cond:
            continue

        indexof_needles: list[str] = []
        startswith_needles: list[str] = []
        for im in re.finditer(
            r'(?:text|raw)\.indexOf\(\s*"([^"]+)"\s*\)\s*(?P<eq>===\s*0)?',
            cond,
        ):
            needle = decode_qml_string(im.group(1))
            if im.group("eq"):
                startswith_needles.append(needle)
            else:
                indexof_needles.append(needle)

        equality_values: list[str] = []
        for em in re.finditer(r'text\s*===\s*"([^"]+)"', cond):
            equality_values.append(decode_qml_string(em.group(1)))

        regex_patterns: list[re.Pattern[str]] = []
        for rm in re.finditer(r"/(\[[^\n]+?\])/\.test\(\s*raw\s*\)", cond):
            pat = rm.group(1)
            try:
                regex_patterns.append(re.compile(pat))
            except re.error as exc:
                raise AssertionError(f"invalid regex in QML condition: {pat}") from exc

        branches.append(
            PredicateBranch(
                condition=cond,
                return_glyph=glyph,
                indexof_needles=indexof_needles,
                equality_values=equality_values,
                startswith_needles=startswith_needles,
                regex_patterns=regex_patterns,
            )
        )

    all_returns = list(re.finditer(r'return\s+"([^"]+)"\s*;', body))
    if not all_returns:
        raise AssertionError("no return statements in languageLabel")
    final_glyph = decode_qml_string(all_returns[-1].group(1))
    return empty_glyph, branches, final_glyph


def branch_matches(branch: PredicateBranch, raw: str, text: str) -> bool:
    for needle in branch.indexof_needles:
        if needle.lower() in text or needle in raw:
            return True
    for value in branch.equality_values:
        if text == value.lower() or text == value:
            return True
    for needle in branch.startswith_needles:
        if text.startswith(needle.lower()) or text.startswith(needle):
            return True
    for pattern in branch.regex_patterns:
        if pattern.search(raw):
            return True
    return False


def evaluate_from_qml(name: str | None, body: str) -> str:
    """Evaluate languageLabel using predicates extracted from the QML if-blocks."""
    empty_glyph, branches, final_glyph = parse_branches(body)
    raw = str(name or "")
    text = raw.lower().strip()
    if len(text) == 0:
        if empty_glyph is None:
            raise AssertionError("empty-name early return missing in source")
        return empty_glyph

    for branch in branches:
        if branch_matches(branch, raw, text):
            return branch.return_glyph
    return final_glyph


class TestLanguageLabelSource(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.src = INPUT_METHOD.read_text(encoding="utf-8")
        cls.body = extract_language_label_body(cls.src)
        cls.display = extract_display_text_binding(cls.src)
        cls.empty, cls.branches, cls.final = parse_branches(cls.body)

    def test_single_language_label_entry(self) -> None:
        self.assertEqual(self.src.count("function languageLabel"), 1)
        self.assertIn("languageLabel(currentName)", self.display)
        self.assertNotIn("function safeLanguageLabel", self.src)
        self.assertNotIn("function languageLabel2", self.src)

    def test_parsed_branch_order_and_glyphs(self) -> None:
        glyphs = [b.return_glyph for b in self.branches]
        self.assertEqual(self.empty, "Aa")
        self.assertEqual(self.final, "Aa")
        # Expect JA, KO, ZH, EN as the four language if-branches.
        self.assertEqual(glyphs, ["あ", "한", "中", "EN"])

    def test_japanese_branch_predicates_include_mozc(self) -> None:
        ja = self.branches[0]
        self.assertEqual(ja.return_glyph, "あ")
        self.assertIn("mozc", ja.indexof_needles)
        self.assertIn("anthy", ja.indexof_needles)
        self.assertTrue(any(p.pattern for p in ja.regex_patterns))

    def test_korean_branch_predicates_include_hangul(self) -> None:
        ko = self.branches[1]
        self.assertEqual(ko.return_glyph, "한")
        self.assertIn("hangul", ko.indexof_needles)
        self.assertIn("korean", ko.indexof_needles)

    def test_chinese_branch_predicates_include_pinyin(self) -> None:
        zh = self.branches[2]
        self.assertEqual(zh.return_glyph, "中")
        self.assertIn("pinyin", zh.indexof_needles)
        self.assertIn("rime", zh.indexof_needles)
        # Bounded cn: equality or startswith, not bare indexOf("cn").
        self.assertIn("cn", zh.equality_values)
        self.assertTrue(any(n in ("cn-", "cn_") for n in zh.startswith_needles))
        self.assertNotIn("cn", zh.indexof_needles)

    def test_no_bare_zh_indexof_in_source(self) -> None:
        # Old over-match: indexOf("zh") without delimiter.
        self.assertNotRegex(self.body, r'indexOf\("zh"\)')
        self.assertIn('indexOf("zh-")', self.body)
        self.assertIn('text === "zh"', self.body)

    def test_display_text_keeps_en_when_inactive(self) -> None:
        self.assertIn('active ? languageLabel(currentName) : "EN"', self.display)
        compact = re.sub(r"\s+", "", self.display)
        self.assertIn('!available?"--"', compact)

    def test_removing_mozc_from_ja_if_fails_matrix(self) -> None:
        """Attack A: drop mozc from the JA condition — suite must fail."""
        corrupted = self.body.replace('indexOf("mozc") !== -1 || ', "")
        self.assertNotEqual(corrupted, self.body)
        # Parser should no longer list mozc in JA needles.
        _, branches, _ = parse_branches(corrupted)
        self.assertNotIn("mozc", branches[0].indexof_needles)
        self.assertNotEqual(evaluate_from_qml("mozc", corrupted), "あ")

    def test_moving_mozc_into_chinese_branch_fails_matrix(self) -> None:
        """Attack B: mozc only in ZH branch — evaluator must return 中 for mozc."""
        # Remove from JA, inject into ZH condition string.
        without = self.body.replace('indexOf("mozc") !== -1 || ', "")
        corrupted = without.replace(
            'indexOf("pinyin") !== -1',
            'indexOf("mozc") !== -1 || indexOf("pinyin") !== -1',
            1,
        )
        self.assertEqual(evaluate_from_qml("mozc", corrupted), "中")


class TestLanguageLabelFromQml(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.body = extract_language_label_body(INPUT_METHOD.read_text(encoding="utf-8"))

    def test_chinese_engines(self) -> None:
        for name in (
            "pinyin",
            "Pinyin",
            "rime",
            "wubi",
            "zhuyin",
            "chinese",
            "zh-cn",
            "中文",
            "拼音",
        ):
            with self.subTest(name=name):
                self.assertEqual(evaluate_from_qml(name, self.body), "中")

    def test_japanese_engines(self) -> None:
        for name in ("mozc", "Mozc", "anthy", "skk", "kkc", "japanese", "ja", "あ", "日本語"):
            with self.subTest(name=name):
                self.assertEqual(evaluate_from_qml(name, self.body), "あ")

    def test_korean_engines(self) -> None:
        for name in ("hangul", "libhangul", "korean", "ko", "ko-kr", "한글"):
            with self.subTest(name=name):
                self.assertEqual(evaluate_from_qml(name, self.body), "한")

    def test_english_engines(self) -> None:
        for name in ("english", "keyboard-us", "en", "us", "en-US"):
            with self.subTest(name=name):
                self.assertEqual(evaluate_from_qml(name, self.body), "EN")

    def test_unknown_and_empty_not_chinese(self) -> None:
        for name in ("", None, "foo-bar", "vietnamese", "thai", "unknown-ime", "console"):
            with self.subTest(name=name):
                label = evaluate_from_qml(name, self.body)  # type: ignore[arg-type]
                self.assertNotEqual(label, "中")
                self.assertEqual(label, "Aa")

    def test_old_bug_would_label_non_chinese_as_chinese(self) -> None:
        def old_language_label(name: str) -> str:
            text = str(name or "").lower()
            if (
                "pinyin" in text
                or "rime" in text
                or "wubi" in text
                or "zh" in text
                or re.search(r"[\u4e00-\u9fff]", text)
            ):
                return "中"
            return "中"

        self.assertEqual(old_language_label("mozc"), "中")
        self.assertEqual(old_language_label("hangul"), "中")
        self.assertEqual(evaluate_from_qml("mozc", self.body), "あ")
        self.assertEqual(evaluate_from_qml("hangul", self.body), "한")
        self.assertEqual(evaluate_from_qml("日本語", self.body), "あ")


class TestToggleSurfaceUnchanged(unittest.TestCase):
    def test_toggle_still_uses_fcitx5_remote(self) -> None:
        src = INPUT_METHOD.read_text(encoding="utf-8")
        self.assertIn("function toggle()", src)
        self.assertIn("fcitx5-remote", src)
        self.assertIn("function applyProbe", src)
        self.assertEqual(len(re.findall(r"function languageLabel\(", src)), 1)


if __name__ == "__main__":
    unittest.main()
