#!/usr/bin/env python3
"""Task 18: ClipboardHistory must not poll cliphist list every 4 seconds.

Root waste (old code):
  - Timer { interval: 4000; running: true; repeat: true; onTriggered: refresh() }
  - Shell lifetime ≈ 900 full `cliphist list` process starts per idle hour
  - Even while wl-paste --watch cliphist store already handles clipboard writes

Fix contract:
  - Primary refresh authority is event-driven: watcher stores then emits a line;
    ClipboardHistory SplitParser schedules the existing refresh() path
  - Popup open / delete / clear / manual refresh keep using refresh/scheduleRefresh
  - Optional low-frequency health recovery only (minutes, not 4s)
  - Single watcher Process; no second watcher; no permanent dual poll authority
  - Initial load via detectTools / applyCommandRunnerTools still calls refresh

Regression strategy:
  1. Static contract extraction from ClipboardHistory.qml + CommandRunner.qml
  2. Behavioral sim: idle hour process budget under event vs old 4s poll
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from dataclasses import dataclass
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
CLIPBOARD = SHELL_ROOT / "services" / "ClipboardHistory.qml"
COMMAND_RUNNER = SHELL_ROOT / "services" / "CommandRunner.qml"
CLIPBOARD_POPUP = SHELL_ROOT / "components" / "ClipboardPopup.qml"
QML_TEST = Path(__file__).with_name("tst_clipboard_history_event_refresh.qml")


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


def _timer_blocks(src: str) -> list[str]:
    blocks: list[str] = []
    for m in re.finditer(r"\bTimer\s*\{", src):
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
                    blocks.append(src[start : i + 1])
                    break
            i += 1
    return blocks


def _process_block(src: str, process_id: str) -> str:
    m = re.search(rf"Process\s*\{{\s*id:\s*{re.escape(process_id)}\b", src)
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


@dataclass(frozen=True)
class ClipboardEventRefreshContract:
    no_4s_unconditional_poll: bool
    watcher_emits_change_marker: bool
    watcher_has_split_parser: bool
    watcher_parser_schedules_refresh: bool
    has_schedule_refresh: bool
    health_recovery_if_present_is_slow: bool
    single_clipboard_watcher_process: bool
    command_runner_watch_emits_marker: bool
    popup_refreshes_on_open: bool
    delete_and_clear_still_schedule: bool
    no_second_watcher: bool
    has_refresh_pending: bool
    refresh_sets_pending_when_running: bool
    finish_list_probe_replays_pending: bool
    list_probe_running_changed_fallback: bool
    no_parallel_refresh_api: bool

    @property
    def complete(self) -> bool:
        return all(getattr(self, name) for name in self.__annotations__)


def extract_contract(clipboard_src: str, runner_src: str, popup_src: str) -> ClipboardEventRefreshContract:
    watcher = _process_block(clipboard_src, "clipboardWatcher")
    timers = _timer_blocks(clipboard_src)
    delete_body = _extract_function_body(clipboard_src, "deleteEntry")
    clear_body = _extract_function_body(clipboard_src, "clearHistory")
    watch_cmd_body = _extract_function_body(runner_src, "clipboardWatchCommand")

    poll_4s = False
    health_ok = True
    for block in timers:
        interval_m = re.search(r"interval:\s*(\d+)", block)
        if not interval_m:
            continue
        interval = int(interval_m.group(1))
        is_repeat = bool(re.search(r"repeat:\s*true", block))
        triggers_refresh = bool(
            re.search(r"onTriggered:.*\brefresh\s*\(", block, re.DOTALL)
        )
        if is_repeat and triggers_refresh and interval <= 4000 and interval > 0:
            # Standing high-rate list poll (old bug).
            if "healthRecovery" not in block and "health" not in block.lower():
                poll_4s = True
            # Named health recovery at <=4s is still too fast.
            if "healthRecovery" in block or re.search(r"id:\s*health", block):
                health_ok = False
        if is_repeat and triggers_refresh and "healthRecovery" in block:
            # Recovery must be multi-minute class, not near-poll.
            if interval < 60_000:
                health_ok = False

    marker_in_watcher = bool(
        re.search(r"printf|changed|echo", watcher)
        or re.search(r"cliphist store;", watcher)
    )
    marker_in_runner = bool(
        re.search(r"printf|changed", watch_cmd_body)
        and re.search(r"cliphist store", watch_cmd_body)
    )

    refresh_fn = _extract_function_body(clipboard_src, "refresh")
    finish_fn = _extract_function_body(clipboard_src, "finishListProbe")
    list_probe = _process_block(clipboard_src, "listProbe")
    has_refresh_pending = bool(
        re.search(r"property\s+bool\s+refreshPending\b", clipboard_src)
    )
    refresh_sets_pending_when_running = bool(
        re.search(r"listProbe\.running", refresh_fn)
        and re.search(r"refreshPending\s*=\s*true", refresh_fn)
    )
    finish_list_probe_replays_pending = bool(
        finish_fn
        and re.search(r"refreshPending", finish_fn)
        and re.search(r"Qt\.callLater\s*\(\s*root\.refresh", finish_fn)
    )
    list_probe_running_changed_fallback = bool(
        re.search(r"onRunningChanged\s*:", list_probe)
        and re.search(r"finishListProbe", list_probe)
    )
    no_parallel_refresh_api = not bool(
        re.search(r"function\s+(refreshNow|refreshSafe|safeRefresh)\s*\(", clipboard_src)
    )

    return ClipboardEventRefreshContract(
        no_4s_unconditional_poll=not poll_4s
        and not re.search(
            r"interval:\s*4000\s*\n\s*running:\s*true\s*\n\s*repeat:\s*true",
            clipboard_src,
        ),
        watcher_emits_change_marker=marker_in_watcher,
        watcher_has_split_parser="SplitParser" in watcher,
        watcher_parser_schedules_refresh=bool(
            re.search(r"scheduleRefresh\s*\(", watcher)
        ),
        has_schedule_refresh="function scheduleRefresh" in clipboard_src,
        health_recovery_if_present_is_slow=health_ok,
        single_clipboard_watcher_process=len(
            re.findall(r"id:\s*clipboardWatcher\b", clipboard_src)
        )
        == 1,
        command_runner_watch_emits_marker=marker_in_runner,
        popup_refreshes_on_open=bool(
            re.search(r"onOpenChanged", popup_src)
            and re.search(r"\.refresh\s*\(", popup_src)
        ),
        delete_and_clear_still_schedule=bool(
            re.search(r"scheduleRefresh", delete_body)
            and re.search(r"scheduleRefresh", clear_body)
        ),
        no_second_watcher=not re.search(
            r"clipboardWatcher2|secondWatcher|safeStartWatcher", clipboard_src
        ),
        has_refresh_pending=has_refresh_pending,
        refresh_sets_pending_when_running=refresh_sets_pending_when_running,
        finish_list_probe_replays_pending=finish_list_probe_replays_pending,
        list_probe_running_changed_fallback=list_probe_running_changed_fallback,
        no_parallel_refresh_api=no_parallel_refresh_api,
    )


class ClipboardEventSim:
    """Counts list refreshes under event-driven vs old poll models."""

    def __init__(self, poll_interval_ms: int | None = None, health_ms: int | None = 300_000) -> None:
        self.poll_interval_ms = poll_interval_ms
        self.health_ms = health_ms
        self.list_starts = 0
        self.t = 0

    def on_clipboard_changed(self) -> None:
        # Event path: watcher store marker → scheduleRefresh → refresh.
        self.list_starts += 1

    def on_popup_open(self) -> None:
        self.list_starts += 1

    def on_delete_or_clear(self) -> None:
        self.list_starts += 1

    def advance_idle_ms(self, ms: int) -> None:
        end = self.t + ms
        if self.poll_interval_ms:
            # Old unconditional poll.
            while self.t + self.poll_interval_ms <= end:
                self.t += self.poll_interval_ms
                self.list_starts += 1
            self.t = end
            return
        # Event-driven: only optional health recovery fires while idle.
        if self.health_ms:
            while self.t + self.health_ms <= end:
                self.t += self.health_ms
                self.list_starts += 1
            self.t = end
        else:
            self.t = end


class ClipboardHistoryEventRefreshTests(unittest.TestCase):
    def test_source_contract_is_complete(self) -> None:
        contract = extract_contract(
            CLIPBOARD.read_text(encoding="utf-8"),
            COMMAND_RUNNER.read_text(encoding="utf-8"),
            CLIPBOARD_POPUP.read_text(encoding="utf-8"),
        )
        missing = [
            name
            for name in ClipboardEventRefreshContract.__annotations__
            if not getattr(contract, name)
        ]
        self.assertEqual(missing, [], f"clipboard event-refresh contract incomplete: {missing}")

    def test_old_4s_poll_budget_is_about_900_per_idle_hour(self) -> None:
        old = ClipboardEventSim(poll_interval_ms=4000, health_ms=None)
        old.advance_idle_ms(3_600_000)
        # 3600/4 = 900
        self.assertEqual(old.list_starts, 900)

    def test_event_driven_idle_hour_is_far_below_old_poll(self) -> None:
        fixed = ClipboardEventSim(poll_interval_ms=None, health_ms=300_000)
        fixed.advance_idle_ms(3_600_000)
        # 3600/300 = 12 health recoveries max; << 900
        self.assertEqual(fixed.list_starts, 12)
        self.assertLess(fixed.list_starts, 50)
        self.assertLess(fixed.list_starts * 20, 900)

    def test_copy_events_refresh_without_poll(self) -> None:
        fixed = ClipboardEventSim(poll_interval_ms=None, health_ms=300_000)
        for _ in range(5):
            fixed.on_clipboard_changed()
        fixed.on_popup_open()
        fixed.on_delete_or_clear()
        # No idle advance: only explicit events.
        self.assertEqual(fixed.list_starts, 7)

    def test_no_interval_4000_standing_refresh_timer_in_source(self) -> None:
        src = CLIPBOARD.read_text(encoding="utf-8")
        # Explicit negative: the historical unconditional block must be gone.
        self.assertIsNone(
            re.search(
                r"interval:\s*4000\s*\n\s*running:\s*true\s*\n\s*repeat:\s*true\s*\n\s*onTriggered:\s*root\.refresh\s*\(\s*\)",
                src,
            )
        )

    def test_health_recovery_timer_is_not_sub_minute(self) -> None:
        src = CLIPBOARD.read_text(encoding="utf-8")
        m = re.search(
            r"id:\s*healthRecoveryTimer\s*.*?interval:\s*(\d+)",
            src,
            re.DOTALL,
        )
        self.assertIsNotNone(m, "health recovery timer should exist for missed events")
        assert m is not None
        self.assertGreaterEqual(int(m.group(1)), 60_000)

    def test_watcher_command_still_stores_via_cliphist(self) -> None:
        runner = COMMAND_RUNNER.read_text(encoding="utf-8")
        body = _extract_function_body(runner, "clipboardWatchCommand")
        self.assertIn("cliphist store", body)
        self.assertIn("wl-paste", body)
        self.assertRegex(body, r"printf|echo")


    def test_source_has_refresh_pending_coalesce(self) -> None:
        contract = extract_contract(
            CLIPBOARD.read_text(encoding="utf-8"),
            COMMAND_RUNNER.read_text(encoding="utf-8"),
            CLIPBOARD_POPUP.read_text(encoding="utf-8"),
        )
        self.assertTrue(contract.has_refresh_pending)
        self.assertTrue(contract.refresh_sets_pending_when_running)
        self.assertTrue(contract.finish_list_probe_replays_pending)
        self.assertTrue(contract.list_probe_running_changed_fallback)
        self.assertTrue(contract.no_parallel_refresh_api)

    def test_stable_entry_caches_and_failed_refresh_retention(self) -> None:
        src = CLIPBOARD.read_text(encoding="utf-8")
        self.assertIn("property var historyEntryCache: Object.create(null)", src)
        self.assertIn("property var pinnedEntryCache: Object.create(null)", src)
        self.assertIn("function cliphistEntryId(raw)", src)
        self.assertIn("function mergeHistoryEntries(candidates)", src)
        self.assertIn("function mergePinnedEntries(values)", src)
        self.assertIn('entry.modelKey = "history:" + entryId', src)
        self.assertIn('entry.modelKey = "pin:" + text', src)
        self.assertIn("root.pendingListText = listProbeOut.text", src)
        self.assertIn("root.pendingPinText = pinDecodeOut.text", src)
        finish = _extract_function_body(src, "finishListProbe")
        self.assertIn("root.parseList(output)", finish)
        self.assertNotIn("root.clearEntries()", finish)
        self.assertIn("刷新失败，保留", finish)
        pin_process = _process_block(src, "pinDecodeProcess")
        self.assertIn("if (code === 0)", pin_process)
        self.assertIn("root.finishPinDecode(root.pendingPinText)", pin_process)
        self.assertIn("FailedToStart", pin_process)

    def test_popup_stable_models_transitions_and_eased_height(self) -> None:
        popup = CLIPBOARD_POPUP.read_text(encoding="utf-8")
        self.assertEqual(popup.count('objectProp: "modelKey"'), 2)
        self.assertEqual(popup.count("add: Transition"), 2)
        self.assertEqual(popup.count("remove: Transition"), 2)
        self.assertEqual(popup.count("displaced: Transition"), 2)
        self.assertGreaterEqual(
            popup.count("Motion.elementResize(root.settingsService)"), 5
        )
        self.assertIn("Behavior on height", popup)
        self.assertIn("Behavior on Layout.preferredHeight", popup)
        self.assertNotIn("SpringAnimation", popup)

    def test_clipboard_row_owns_hover_and_press_feedback_only(self) -> None:
        popup = CLIPBOARD_POPUP.read_text(encoding="utf-8")
        row = re.search(
            r"component ClipboardRow: Item \{(?P<body>[\s\S]*?)\n    component SectionHeader",
            popup,
        )
        self.assertIsNotNone(row)
        assert row
        body = row.group("body")
        self.assertIn("Motion.pressScaleFor(root.settingsService, rowMouse.pressed)", body)
        self.assertIn("Motion.pressDurationFor(root.settingsService)", body)
        self.assertIn("Behavior on color", body)
        self.assertIn("ColorAnimation", body)
        self.assertIn("Motion.fadeFast(root.settingsService)", body)

    def test_real_quickshell_scriptmodel_preserves_clipboard_delegates(self) -> None:
        local_runner = Path.home() / ".local" / "bin" / "qs"
        runner = str(local_runner) if local_runner.is_file() else shutil.which("qs")
        self.assertIsNotNone(runner, "Tahoe Quickshell runtime is required")

        qml = r'''pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "__SERVICE_IMPORT__" as Services

ShellRoot {
    id: root

    property int historyCreated: 0
    property int historyDestroyed: 0
    property int pinnedCreated: 0
    property int pinnedDestroyed: 0
    property var alphaHistoryDelegate: null
    property var betaHistoryDelegate: null
    property var alphaPinnedDelegate: null
    property var betaPinnedDelegate: null

    QtObject {
        id: fakeRunner
        property int revision: 1
        function commandAvailable(name) { return false; }
        function dependencyDetail(name) { return ""; }
        function dependencyState(name) { return "missing"; }
        function refreshDependencies() {}
    }

    Services.ClipboardHistory {
        id: clipboard
        commandRunner: fakeRunner
        loadingPinnedState: true
    }

    Item {
        Repeater {
            id: historyRows
            model: ScriptModel {
                objectProp: "modelKey"
                values: clipboard.entries
            }
            delegate: Item {
                required property var modelData
                Component.onCompleted: root.historyCreated += 1
                Component.onDestruction: root.historyDestroyed += 1
            }
        }

        Repeater {
            id: pinnedRows
            model: ScriptModel {
                objectProp: "modelKey"
                values: clipboard.pinnedEntries
            }
            delegate: Item {
                required property var modelData
                Component.onCompleted: root.pinnedCreated += 1
                Component.onDestruction: root.pinnedDestroyed += 1
            }
        }
    }

    Timer {
        id: settleTimer
        interval: 5
        repeat: false
        property var callback: null
        onTriggered: callback()
    }

    function afterModelSettles(callback) {
        settleTimer.callback = callback;
        settleTimer.restart();
    }

    function fail(message) {
        console.error("CLIPBOARD_STABLE_ROWS_FAIL: " + message);
        Qt.quit();
    }

    function require(condition, message) {
        if (!condition) {
            fail(message);
            return false;
        }
        return true;
    }

    function historyDelegate(entryId) {
        for (var i = 0; i < historyRows.count; i++) {
            var item = historyRows.itemAt(i);
            if (item && String(item.modelData.entryId) === String(entryId))
                return item;
        }
        return null;
    }

    function pinnedDelegate(text) {
        for (var i = 0; i < pinnedRows.count; i++) {
            var item = pinnedRows.itemAt(i);
            if (item && String(item.modelData.text) === String(text))
                return item;
        }
        return null;
    }

    function startProbe() {
        clipboard.clearEntries();
        clipboard.mergePinnedEntries([]);
        clipboard.listLoaded = false;
        clipboard.lastListText = "";
        clipboard.parseList("10\talpha\n20\tbeta");
        clipboard.mergePinnedEntries([
            { text: "alpha", preview: "Alpha", icon: "a", sourceRaw: "10\talpha", addedAt: "1" },
            { text: "beta", preview: "Beta", icon: "b", sourceRaw: "20\tbeta", addedAt: "2" }
        ]);
        afterModelSettles(checkInitialRows);
    }

    function checkInitialRows() {
        alphaHistoryDelegate = historyDelegate("10");
        betaHistoryDelegate = historyDelegate("20");
        alphaPinnedDelegate = pinnedDelegate("alpha");
        betaPinnedDelegate = pinnedDelegate("beta");
        if (!require(historyRows.count === 2 && pinnedRows.count === 2,
                "initial row counts")
                || !require(historyCreated === 2 && pinnedCreated === 2,
                    "initial delegate creation")
                || !require(alphaHistoryDelegate && betaHistoryDelegate
                    && alphaPinnedDelegate && betaPinnedDelegate,
                    "initial delegates missing"))
            return;

        clipboard.parseList("20\tbeta updated\n10\talpha updated\n30\tgamma");
        clipboard.mergePinnedEntries([
            { text: "beta", preview: "Beta updated", icon: "B", sourceRaw: "21\tbeta", addedAt: "3" },
            { text: "alpha", preview: "Alpha updated", icon: "A", sourceRaw: "11\talpha", addedAt: "4" }
        ]);
        afterModelSettles(checkMovedRows);
    }

    function checkMovedRows() {
        if (!require(historyRows.count === 3 && pinnedRows.count === 2,
                "moved row counts")
                || !require(historyCreated === 3 && historyDestroyed === 0
                    && pinnedCreated === 2 && pinnedDestroyed === 0,
                    "surviving delegates recreated")
                || !require(historyDelegate("10") === alphaHistoryDelegate
                    && historyDelegate("20") === betaHistoryDelegate,
                    "history delegate identity changed")
                || !require(pinnedDelegate("alpha") === alphaPinnedDelegate
                    && pinnedDelegate("beta") === betaPinnedDelegate,
                    "pinned delegate identity changed")
                || !require(alphaHistoryDelegate.modelData.preview === "alpha updated"
                    && betaPinnedDelegate.modelData.preview === "Beta updated",
                    "latest fields not delivered")
                || !require(historyRows.itemAt(0) === betaHistoryDelegate
                    && pinnedRows.itemAt(0) === betaPinnedDelegate,
                    "delegates did not move in place"))
            return;

        clipboard.parseList("10\talpha final\n30\tgamma");
        clipboard.mergePinnedEntries([
            { text: "alpha", preview: "Alpha final", icon: "A", sourceRaw: "11\talpha", addedAt: "4" }
        ]);
        afterModelSettles(checkRemovedRows);
    }

    function checkRemovedRows() {
        if (!require(historyRows.count === 2 && pinnedRows.count === 1,
                "final row counts")
                || !require(historyDestroyed === 1 && pinnedDestroyed === 1,
                    "removed delegates were not destroyed once")
                || !require(historyDelegate("10") === alphaHistoryDelegate
                    && pinnedDelegate("alpha") === alphaPinnedDelegate,
                    "surviving delegate changed on removal"))
            return;
        console.log("CLIPBOARD_STABLE_ROWS_OK");
        Qt.quit();
    }

    Timer {
        interval: 20
        running: true
        repeat: false
        onTriggered: root.startProbe()
    }
}
'''.replace("__SERVICE_IMPORT__", (SHELL_ROOT / "services").as_uri())

        with tempfile.TemporaryDirectory(prefix="tahoe-clipboard-stable-") as temp_dir:
            config = Path(temp_dir) / "shell.qml"
            config.write_text(qml, encoding="utf-8")
            completed = subprocess.run(
                [runner, "-p", str(config)],
                text=True,
                capture_output=True,
                timeout=20,
                check=False,
            )

        output = completed.stdout + completed.stderr
        self.assertEqual(completed.returncode, 0, output)
        self.assertIn("CLIPBOARD_STABLE_ROWS_OK", output, output)
        self.assertNotIn("CLIPBOARD_STABLE_ROWS_FAIL", output, output)

    def test_real_qml_lossless_refresh(self) -> None:
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(runner, "Qt 6 qmltestrunner is required for ClipboardHistory coverage")
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
            [runner, "-input", str(QML_TEST)],
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
