#!/usr/bin/env python3
"""Task 07: Apps model must refresh on identity/metadata changes, not count only.

Root bug (old code):
  refreshDesktopEntries compared only DesktopEntries.applications.values.length.
  Equal-count install/uninstall swaps and in-place .desktop Name/Icon/Exec/NoDisplay
  edits left desktopEntriesRevision unchanged, so realApplications / pinnedApps /
  launchpad search kept stale objects and metadata.

Fix contract:
  - Single Apps-owned refresh path: refreshDesktopEntries(force)
  - Gate rebuilds with a lightweight identity+metadata fingerprint (not count)
  - Fingerprint covers stable desktop id and UI/launch fields: name, genericName,
    icon, execString, command, startupClass, noDisplay
  - DesktopEntries.applicationsChanged drives the same refresh path
  - Recovery Timer (if present) must call the same refreshDesktopEntries — not a
    second competing refresh system
  - Unchanged fingerprint must not bump desktopEntriesRevision
  - Force rebuild still works for initial load

Regression strategy:
  1. Static contract extraction from Apps.qml (fails on old count-only gate).
  2. Behavioral simulation of equal-count replace, metadata edit, count change,
     no-op poll, and signal-driven refresh using the extracted fingerprint logic.
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SHELL_ROOT = Path(__file__).resolve().parents[1]
APPS = SHELL_ROOT / "services" / "Apps.qml"


@dataclass(frozen=True)
class DesktopEntriesRefreshContract:
    """Wiring discovered in source. Missing edges reproduce the old count-only bug."""

    has_fingerprint_property: bool
    has_fingerprint_function: bool
    fingerprint_covers_id: bool
    fingerprint_covers_name: bool
    fingerprint_covers_icon: bool
    fingerprint_covers_exec: bool
    fingerprint_covers_command: bool
    fingerprint_covers_no_display: bool
    fingerprint_covers_startup_class: bool
    refresh_uses_fingerprint: bool
    refresh_does_not_gate_on_count_only: bool
    no_desktop_entries_count_property: bool
    connects_applications_changed: bool
    applications_changed_calls_refresh: bool
    timer_calls_same_refresh: bool
    single_refresh_function: bool
    no_parallel_fingerprint_pipeline: bool
    no_second_desktop_entries_model: bool
    real_applications_bound_to_revision: bool
    pinned_apps_bound_to_desktop_revision: bool

    @property
    def identity_path_complete(self) -> bool:
        return all(
            getattr(self, name)
            for name in DesktopEntriesRefreshContract.__annotations__
        )


def _extract_function_body(src: str, name: str) -> str:
    m = re.search(
        rf"function\s+{re.escape(name)}\s*\([^)]*\)\s*\{{",
        src,
    )
    if not m:
        return ""
    start = m.end()
    depth = 1
    i = start
    while i < len(src) and depth:
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return src[start : i - 1]


def _extract_connections_block(src: str, target: str) -> str:
    # Match Connections { target: DesktopEntries ... }
    pattern = rf"Connections\s*\{{\s*target:\s*{re.escape(target)}"
    m = re.search(pattern, src)
    if not m:
        return ""
    start = m.start()
    depth = 0
    i = start
    begun = False
    while i < len(src):
        if src[i] == "{":
            depth += 1
            begun = True
        elif src[i] == "}":
            depth -= 1
            if begun and depth == 0:
                return src[start : i + 1]
        i += 1
    return ""


def _extract_timer_block(src: str, timer_id: str) -> str:
    m = re.search(rf"Timer\s*\{{\s*id:\s*{re.escape(timer_id)}", src)
    if not m:
        return ""
    start = m.start()
    depth = 0
    i = start
    begun = False
    while i < len(src):
        if src[i] == "{":
            depth += 1
            begun = True
        elif src[i] == "}":
            depth -= 1
            if begun and depth == 0:
                return src[start : i + 1]
        i += 1
    return ""


def extract_contract(src: str) -> DesktopEntriesRefreshContract:
    refresh_fn = _extract_function_body(src, "refreshDesktopEntries")
    fingerprint_fn = _extract_function_body(src, "desktopEntriesFingerprintOf")
    de_connections = _extract_connections_block(src, "DesktopEntries")
    timer = _extract_timer_block(src, "desktopEntriesRefreshTimer")

    has_fingerprint_property = bool(
        re.search(r"property\s+string\s+desktopEntriesFingerprint\b", src)
    )
    has_fingerprint_function = bool(fingerprint_fn.strip())

    # Fingerprint must read identity and launch/UI metadata fields.
    fingerprint_covers_id = bool(
        re.search(r"\bapp\.id\b|\.id\b", fingerprint_fn)
    )
    fingerprint_covers_name = bool(re.search(r"\bapp\.name\b|\.name\b", fingerprint_fn))
    fingerprint_covers_icon = bool(re.search(r"\bapp\.icon\b|\.icon\b", fingerprint_fn))
    fingerprint_covers_exec = bool(
        re.search(r"\bapp\.execString\b|execString", fingerprint_fn)
    )
    fingerprint_covers_command = bool(
        re.search(r"\bapp\.command\b|command", fingerprint_fn)
    )
    fingerprint_covers_no_display = bool(
        re.search(r"\bnoDisplay\b", fingerprint_fn)
    )
    fingerprint_covers_startup_class = bool(
        re.search(r"\bstartupClass\b", fingerprint_fn)
    )

    refresh_uses_fingerprint = bool(
        re.search(r"desktopEntriesFingerprintOf\s*\(", refresh_fn)
        and re.search(r"desktopEntriesFingerprint", refresh_fn)
        and re.search(r"desktopEntriesRevision\s*\+=\s*1", refresh_fn)
    )

    # Old bug signature: gate only on length/count equality.
    old_count_only_gate = bool(
        re.search(
            r"count\s*===\s*desktopEntriesCount|desktopEntriesCount\s*===\s*count",
            refresh_fn,
        )
        or (
            re.search(r"\.length", refresh_fn)
            and re.search(r"desktopEntriesCount", refresh_fn)
            and not re.search(r"Fingerprint", refresh_fn)
        )
    )
    refresh_does_not_gate_on_count_only = not old_count_only_gate
    no_desktop_entries_count_property = not bool(
        re.search(r"property\s+int\s+desktopEntriesCount\b", src)
    )

    connects_applications_changed = bool(de_connections.strip()) and bool(
        re.search(r"onApplicationsChanged\s*:", de_connections)
        or re.search(r"function\s+onApplicationsChanged\s*\(", de_connections)
    )
    applications_changed_calls_refresh = bool(
        re.search(r"refreshDesktopEntries\s*\(", de_connections)
    )

    # Timer is optional recovery; if present it must share the same refresh path.
    if timer.strip():
        timer_calls_same_refresh = bool(
            re.search(r"refreshDesktopEntries\s*\(\s*false\s*\)", timer)
        )
    else:
        timer_calls_same_refresh = True

    single_refresh_function = len(re.findall(r"function\s+refreshDesktopEntries\s*\(", src)) == 1
    no_parallel_fingerprint_pipeline = not bool(
        re.search(
            r"function\s+(safeRefreshDesktopEntries|refreshDesktopEntries2|newRefreshDesktopEntries)\s*\(",
            src,
        )
    )
    no_second_desktop_entries_model = not bool(
        re.search(
            r"property\s+var\s+(cachedApplications|applicationsCache|desktopEntriesModel)\b",
            src,
        )
    )

    real_applications_bound_to_revision = bool(
        re.search(
            r"realApplications\s*:\s*buildApplications\s*\(\s*desktopEntriesRevision\s*\)",
            src,
        )
    )
    pinned_apps_bound_to_desktop_revision = bool(
        re.search(
            r"pinnedApps\s*:\s*buildPinnedApps\s*\([^)]*desktopEntriesRevision",
            src,
        )
    )

    return DesktopEntriesRefreshContract(
        has_fingerprint_property=has_fingerprint_property,
        has_fingerprint_function=has_fingerprint_function,
        fingerprint_covers_id=fingerprint_covers_id,
        fingerprint_covers_name=fingerprint_covers_name,
        fingerprint_covers_icon=fingerprint_covers_icon,
        fingerprint_covers_exec=fingerprint_covers_exec,
        fingerprint_covers_command=fingerprint_covers_command,
        fingerprint_covers_no_display=fingerprint_covers_no_display,
        fingerprint_covers_startup_class=fingerprint_covers_startup_class,
        refresh_uses_fingerprint=refresh_uses_fingerprint,
        refresh_does_not_gate_on_count_only=refresh_does_not_gate_on_count_only,
        no_desktop_entries_count_property=no_desktop_entries_count_property,
        connects_applications_changed=connects_applications_changed,
        applications_changed_calls_refresh=applications_changed_calls_refresh,
        timer_calls_same_refresh=timer_calls_same_refresh,
        single_refresh_function=single_refresh_function,
        no_parallel_fingerprint_pipeline=no_parallel_fingerprint_pipeline,
        no_second_desktop_entries_model=no_second_desktop_entries_model,
        real_applications_bound_to_revision=real_applications_bound_to_revision,
        pinned_apps_bound_to_desktop_revision=pinned_apps_bound_to_desktop_revision,
    )


# ---------------------------------------------------------------------------
# Behavioral simulation (mirrors Apps.qml fingerprint + refresh semantics)
# ---------------------------------------------------------------------------


def fingerprint_of(entries: list[dict[str, Any]]) -> str:
    """Python mirror of Apps.desktopEntriesFingerprintOf (stable, sorted)."""
    parts: list[str] = []
    for app in entries:
        if not app:
            continue
        command = ""
        cmd = app.get("command")
        if isinstance(cmd, (list, tuple)) and len(cmd) > 0:
            command = "\u001f".join(str(x) for x in cmd)
        parts.append(
            "\u001e".join(
                [
                    str(app.get("id") or "").strip(),
                    str(app.get("name") or "").strip(),
                    str(app.get("genericName") or "").strip(),
                    str(app.get("icon") or "").strip(),
                    str(app.get("execString") or "").strip(),
                    command,
                    str(app.get("startupClass") or "").strip(),
                    "1" if app.get("noDisplay") else "0",
                ]
            )
        )
    parts.sort()
    return "\u001d".join(parts)


class AppsDesktopEntriesRefreshSimulator:
    """Minimal owner state for refreshDesktopEntries identity gate."""

    def __init__(self) -> None:
        self.desktop_entries: list[dict[str, Any]] = []
        self.desktop_entries_fingerprint = ""
        self.desktop_entries_revision = 0
        self.pinned_revision = 0
        self.rebuild_count = 0
        # Old path for contrast assertions
        self.desktop_entries_count = -1
        self.old_revision = 0

    def set_entries(self, entries: list[dict[str, Any]]) -> None:
        self.desktop_entries = [dict(e) for e in entries]

    def refresh(self, force: bool = False) -> bool:
        """Return True if revision bumped (rebuild scheduled)."""
        fp = fingerprint_of(self.desktop_entries)
        if not force and fp == self.desktop_entries_fingerprint:
            return False
        self.desktop_entries_fingerprint = fp
        self.desktop_entries_revision += 1
        self.pinned_revision += 1
        self.rebuild_count += 1
        return True

    def refresh_old_count_only(self, force: bool = False) -> bool:
        """Reproduce the old count-only gate for regression contrast."""
        count = len(self.desktop_entries)
        if not force and count == self.desktop_entries_count:
            return False
        self.desktop_entries_count = count
        self.old_revision += 1
        return True

    def on_applications_changed(self) -> bool:
        return self.refresh(False)


def _app(
    app_id: str,
    *,
    name: str | None = None,
    icon: str = "app",
    exec_string: str | None = None,
    command: list[str] | None = None,
    no_display: bool = False,
    startup_class: str = "",
    generic_name: str = "",
) -> dict[str, Any]:
    return {
        "id": app_id,
        "name": name if name is not None else app_id,
        "genericName": generic_name,
        "icon": icon,
        "execString": exec_string if exec_string is not None else app_id,
        "command": command if command is not None else [app_id],
        "startupClass": startup_class or app_id,
        "noDisplay": no_display,
    }


class AppsDesktopEntriesIdentityRefreshTests(unittest.TestCase):
    def setUp(self) -> None:
        self.src = APPS.read_text(encoding="utf-8")
        self.contract = extract_contract(self.src)

    def test_static_contract_complete(self) -> None:
        incomplete = [
            name
            for name in DesktopEntriesRefreshContract.__annotations__
            if not getattr(self.contract, name)
        ]
        self.assertEqual(
            incomplete,
            [],
            "Apps desktop-entries identity refresh contract incomplete:\n"
            + "\n".join(f"  - {n}" for n in incomplete),
        )
        self.assertTrue(self.contract.identity_path_complete)

    def test_old_count_only_gate_absent_from_refresh(self) -> None:
        body = _extract_function_body(self.src, "refreshDesktopEntries")
        self.assertNotRegex(
            body,
            r"desktopEntriesCount",
            "refreshDesktopEntries must not gate on desktopEntriesCount",
        )
        self.assertRegex(body, r"desktopEntriesFingerprintOf")
        self.assertRegex(body, r"desktopEntriesFingerprint")

    def test_equal_count_replace_refreshes_new_path_not_old(self) -> None:
        sim = AppsDesktopEntriesRefreshSimulator()
        sim.set_entries([_app("firefox"), _app("code")])
        self.assertTrue(sim.refresh(force=True))
        rev_after_init = sim.desktop_entries_revision

        # Equal-count swap: uninstall firefox, install chromium (count stays 2).
        sim.set_entries([_app("chromium"), _app("code")])
        self.assertTrue(
            sim.refresh(False),
            "equal-count identity swap must bump revision under fingerprint gate",
        )
        self.assertEqual(sim.desktop_entries_revision, rev_after_init + 1)

        # Old path would miss this.
        sim_old = AppsDesktopEntriesRefreshSimulator()
        sim_old.set_entries([_app("firefox"), _app("code")])
        self.assertTrue(sim_old.refresh_old_count_only(force=True))
        sim_old.set_entries([_app("chromium"), _app("code")])
        self.assertFalse(
            sim_old.refresh_old_count_only(False),
            "old count-only gate must fail equal-count swap (proves regression value)",
        )

    def test_inplace_name_icon_exec_nodisplay_refresh(self) -> None:
        sim = AppsDesktopEntriesRefreshSimulator()
        sim.set_entries([_app("editor", name="Editor", icon="edit", exec_string="editor")])
        self.assertTrue(sim.refresh(force=True))
        base = sim.desktop_entries_revision

        # Name change
        sim.set_entries([_app("editor", name="Editor Pro", icon="edit", exec_string="editor")])
        self.assertTrue(sim.refresh(False))
        self.assertEqual(sim.desktop_entries_revision, base + 1)

        # Icon change
        sim.set_entries(
            [_app("editor", name="Editor Pro", icon="edit-pro", exec_string="editor")]
        )
        self.assertTrue(sim.refresh(False))
        self.assertEqual(sim.desktop_entries_revision, base + 2)

        # Exec / command change
        sim.set_entries(
            [
                _app(
                    "editor",
                    name="Editor Pro",
                    icon="edit-pro",
                    exec_string="editor --new",
                    command=["editor", "--new"],
                )
            ]
        )
        self.assertTrue(sim.refresh(False))
        self.assertEqual(sim.desktop_entries_revision, base + 3)

        # NoDisplay flip (entry still present in raw DesktopEntries.values)
        sim.set_entries(
            [
                _app(
                    "editor",
                    name="Editor Pro",
                    icon="edit-pro",
                    exec_string="editor --new",
                    command=["editor", "--new"],
                    no_display=True,
                )
            ]
        )
        self.assertTrue(sim.refresh(False))
        self.assertEqual(sim.desktop_entries_revision, base + 4)

        # Old count-only path would miss all of the above after initial force.
        sim_old = AppsDesktopEntriesRefreshSimulator()
        sim_old.set_entries([_app("editor", name="Editor")])
        self.assertTrue(sim_old.refresh_old_count_only(force=True))
        sim_old.set_entries([_app("editor", name="Editor Pro")])
        self.assertFalse(sim_old.refresh_old_count_only(False))

    def test_count_change_still_refreshes(self) -> None:
        sim = AppsDesktopEntriesRefreshSimulator()
        sim.set_entries([_app("a")])
        self.assertTrue(sim.refresh(force=True))
        sim.set_entries([_app("a"), _app("b")])
        self.assertTrue(sim.refresh(False))
        sim.set_entries([])
        self.assertTrue(sim.refresh(False))

    def test_no_change_does_not_rebuild(self) -> None:
        sim = AppsDesktopEntriesRefreshSimulator()
        entries = [_app("firefox"), _app("code")]
        sim.set_entries(entries)
        self.assertTrue(sim.refresh(force=True))
        rev = sim.desktop_entries_revision
        rebuilds = sim.rebuild_count

        # Same identity/metadata, possibly different list order — fingerprint is sorted.
        sim.set_entries([_app("code"), _app("firefox")])
        self.assertFalse(sim.refresh(False))
        self.assertEqual(sim.desktop_entries_revision, rev)
        self.assertEqual(sim.rebuild_count, rebuilds)

        # Poll / signal with no change.
        self.assertFalse(sim.on_applications_changed())
        self.assertEqual(sim.desktop_entries_revision, rev)

    def test_force_rebuilds_even_when_fingerprint_unchanged(self) -> None:
        sim = AppsDesktopEntriesRefreshSimulator()
        sim.set_entries([_app("a")])
        self.assertTrue(sim.refresh(force=True))
        rev = sim.desktop_entries_revision
        self.assertTrue(sim.refresh(force=True))
        self.assertEqual(sim.desktop_entries_revision, rev + 1)

    def test_applications_changed_uses_same_path(self) -> None:
        sim = AppsDesktopEntriesRefreshSimulator()
        sim.set_entries([_app("old")])
        self.assertTrue(sim.refresh(force=True))
        sim.set_entries([_app("new")])
        self.assertTrue(sim.on_applications_changed())
        self.assertEqual(sim.desktop_entries_revision, 2)

    def test_fingerprint_is_order_independent(self) -> None:
        a = [_app("z"), _app("a"), _app("m")]
        b = [_app("a"), _app("m"), _app("z")]
        self.assertEqual(fingerprint_of(a), fingerprint_of(b))

    def test_fingerprint_differs_on_each_tracked_field(self) -> None:
        base = _app(
            "x",
            name="N",
            icon="I",
            exec_string="E",
            command=["E"],
            startup_class="S",
            generic_name="G",
            no_display=False,
        )
        variants = [
            {**base, "id": "y"},
            {**base, "name": "N2"},
            {**base, "icon": "I2"},
            {**base, "execString": "E2"},
            {**base, "command": ["E2"]},
            {**base, "startupClass": "S2"},
            {**base, "genericName": "G2"},
            {**base, "noDisplay": True},
        ]
        base_fp = fingerprint_of([base])
        for variant in variants:
            self.assertNotEqual(
                fingerprint_of([variant]),
                base_fp,
                f"fingerprint must change for field mutation {variant}",
            )

    def test_no_parallel_refresh_apis_in_source(self) -> None:
        self.assertEqual(
            len(re.findall(r"function\s+refreshDesktopEntries\s*\(", self.src)),
            1,
        )
        for forbidden in (
            "safeRefreshDesktopEntries",
            "refreshDesktopEntries2",
            "newRefreshDesktopEntries",
            "desktopEntriesCount",
        ):
            self.assertNotIn(forbidden, self.src)


if __name__ == "__main__":
    unittest.main()
