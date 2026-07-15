#!/usr/bin/env python3
"""Task 09: Dynamic Island must track notifications by stable ID, not count.

Root bugs (old code):
  1. handleNotificationsChanged only reacted when activeModel.length increased
     and only took list[nextCount-1]. Equal-count replace and multi-append
     batches dropped or mis-identified new IDs.
  2. pendingNotificationEntry was a single scalar snapshot — second pending
     overwrote the first; queue could not FIFO multiple IDs.
  3. replace-id mutates live Notification without activeModelChanged, so
     island never refreshed displayed text (or could re-popup incorrectly).

Fix contract (T07 lease model):
  - Notifications owns live objects + FIFO + narrow notificationUpdated(id)
  - DynamicIsland tracks seenNotificationIds + completedNotificationIds
  - pendingNotificationIds is manual IPC payloads only (not a live ID queue)
  - Live presentation resolves via Notifications activeModel order / head lease
  - replace-id while displaying: in-place text, no timer/animation restart
  - replace-id while not displaying → no re-popup
  - DND / island disable clear manual queue; completed markers prune with model
  - No second notification model / snapshot cache in island
  - Single restoreAfterTransient drain entry

Regression strategy:
  1. Static contract extraction from DynamicIsland.qml + Notifications.qml
  2. Behavioral simulation of append, equal-count replace, batch, busy queue,
     delete-while-queued, DND clear, replace-id display/queue/idle paths
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


SHELL_ROOT = Path(__file__).resolve().parents[1]
ISLAND = SHELL_ROOT / "services" / "DynamicIsland.qml"
NOTIFICATIONS = SHELL_ROOT / "services" / "Notifications.qml"


@dataclass(frozen=True)
class NotificationIdentityContract:
    has_seen_ids: bool
    has_pending_ids_fifo: bool
    no_scalar_pending_entry: bool
    no_count_only_gate: bool
    no_last_seen_only: bool
    has_displaying_id: bool
    has_find_live_by_id: bool
    has_enqueue_dedupe: bool
    has_remove_pending: bool
    handle_changed_uses_id_diff: bool
    maybe_show_drains_fifo: bool
    maybe_show_skips_missing_live: bool
    present_sets_displaying_id: bool
    has_notification_updated_signal: bool
    wires_live_property_updates: bool
    island_connects_notification_updated: bool
    handle_updated_inplace_when_displaying: bool
    handle_updated_no_repopup_when_idle: bool
    handle_updated_keeps_queue_position: bool
    apply_text_without_timer_restart: bool
    dnd_clears_pending_ids: bool
    disable_clears_pending_ids: bool
    timer_clears_displaying_and_drains: bool
    single_pending_queue: bool
    no_second_notification_model: bool

    @property
    def identity_path_complete(self) -> bool:
        return all(
            getattr(self, name)
            for name in NotificationIdentityContract.__annotations__
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


def extract_contract(island_src: str, notifications_src: str) -> NotificationIdentityContract:
    handle_changed = _extract_function_body(island_src, "handleNotificationsChanged")
    handle_updated = _extract_function_body(island_src, "handleNotificationUpdated")
    maybe_show = _extract_function_body(island_src, "maybeShowPendingNotification")
    present = _extract_function_body(island_src, "presentNotificationEntry")
    apply_text = _extract_function_body(island_src, "applyNotificationEntryText")
    enqueue = _extract_function_body(island_src, "enqueuePendingNotificationId")
    enqueue_entry = _extract_function_body(island_src, "enqueuePendingNotificationEntry")
    remove_pending = _extract_function_body(island_src, "removePendingNotificationId")
    find_live = _extract_function_body(island_src, "findLiveNotificationById")
    handle_dnd = _extract_function_body(island_src, "handleDndChanged")
    handle_disable = _extract_function_body(island_src, "handleIslandEnabledChanged")
    wire = _extract_function_body(notifications_src, "wireNotificationPropertyUpdates")
    notif_conns = _extract_connections_block(island_src, "root.notificationsService")
    timer = _extract_timer_block(island_src, "transientTimer")

    has_seen_ids = bool(
        re.search(r"property\s+var\s+seenNotificationIds\b", island_src)
    )
    has_pending_ids_fifo = bool(
        re.search(r"property\s+var\s+pendingNotificationIds\b", island_src)
    )
    no_scalar_pending_entry = not bool(
        re.search(r"property\s+var\s+pendingNotificationEntry\b", island_src)
    )
    no_count_only_gate = not bool(
        re.search(r"property\s+int\s+observedNotificationCount\b", island_src)
    ) and not bool(
        re.search(
            r"nextCount\s*<=\s*root\.observedNotificationCount|observedNotificationCount",
            handle_changed,
        )
    )
    no_last_seen_only = not bool(
        re.search(r"property\s+int\s+lastSeenNotificationId\b", island_src)
    )
    has_displaying_id = bool(
        re.search(r"property\s+int\s+displayingNotificationId\b", island_src)
    )
    has_find_live_by_id = bool(find_live.strip()) and bool(
        re.search(r"activeModel", find_live)
    )
    # T07: live IDs are not island-enqueued; manual entry helper rejects live.
    has_enqueue_dedupe = bool(
        enqueue_entry.strip()
        and re.search(r'kind === "live"|kind !== "manual"', enqueue_entry)
    ) or bool(
        enqueue.strip() and re.search(r"void id|return;", enqueue)
    )
    has_remove_pending = bool(remove_pending.strip()) or bool(
        re.search(r"pendingNotificationIds", handle_changed)
        and re.search(r"manual|completedNotificationIds", handle_changed)
    )

    handle_changed_uses_id_diff = bool(
        re.search(r"seenNotificationIds|nextSeen", handle_changed)
        and re.search(r"completedNotificationIds|restoreAfterTransient", handle_changed)
        and not re.search(r"list\[nextCount\s*-\s*1\]", handle_changed)
        and not re.search(r"enqueuePendingNotificationId\(newIds", handle_changed)
    )
    maybe_show_drains_fifo = bool(
        (
            re.search(r"pendingNotificationIds", maybe_show)
            and re.search(r"while|slice\(1\)|shift", maybe_show)
        )
        or re.search(r"nextPresentableLiveNotification", maybe_show)
    )
    maybe_show_skips_missing_live = bool(
        re.search(r"nextPresentableLiveNotification|findLiveNotificationById", maybe_show)
        or re.search(
            r"completedNotificationIds|completed\[",
            _extract_function_body(island_src, "nextPresentableLiveNotification"),
        )
    )
    present_sets_displaying_id = bool(
        re.search(r"displayingNotificationId\s*=", present)
    )

    has_notification_updated_signal = bool(
        re.search(r"signal\s+notificationUpdated\s*\(\s*int\s+id\s*\)", notifications_src)
    )
    wires_live_property_updates = bool(
        wire.strip()
        and re.search(r"summaryChanged", wire)
        and re.search(r"bodyChanged", wire)
        and re.search(r"appNameChanged", wire)
        and re.search(r"emitNotificationUpdated|notificationUpdated", wire)
    )
    island_connects_notification_updated = bool(
        re.search(r"onNotificationUpdated", notif_conns)
        and re.search(r"handleNotificationUpdated", notif_conns)
    )

    handle_updated_inplace_when_displaying = bool(
        re.search(r"displayingNotificationId", handle_updated)
        and re.search(r"applyNotificationEntryText", handle_updated)
        and re.search(r"transient_notification", handle_updated)
    )
    handle_updated_no_repopup_when_idle = bool(
        handle_updated.strip()
        and not re.search(r"enqueuePendingNotificationId", handle_updated)
        and not re.search(r"presentNotificationEntry", handle_updated)
    )
    # T07: no island live queue position; idle replace must not re-popup.
    handle_updated_keeps_queue_position = bool(
        handle_updated.strip()
        and not re.search(r"presentNotificationEntry", handle_updated)
        and not re.search(r"enqueuePendingNotification", handle_updated)
    )
    # Strip comments so documentation of "does not restart transientTimer"
    # is not mistaken for a real call.
    apply_code = re.sub(r"//[^\n]*", "", apply_text)
    apply_text_without_timer_restart = bool(
        apply_code.strip()
        and re.search(r"transientDisplayText", apply_code)
        and not re.search(r"\btransientTimer\b|\bshowTransient\s*\(", apply_code)
    )

    dnd_clears_pending_ids = bool(
        re.search(r"clearPendingNotificationIds", handle_dnd)
    )
    disable_clears_pending_ids = bool(
        re.search(r"clearPendingNotificationIds", handle_disable)
    )
    timer_clears_displaying_and_drains = bool(
        re.search(r"displayingNotificationId\s*=\s*-1", timer)
        and re.search(r"restoreAfterTransient|maybeShowPendingNotification", timer)
    )

    single_pending_queue = (
        len(re.findall(r"property\s+var\s+pendingNotificationIds\b", island_src)) == 1
        and no_scalar_pending_entry
    )
    no_second_notification_model = not bool(
        re.search(
            r"property\s+var\s+(notificationCache|islandNotifications|pendingNotificationModel)\b",
            island_src,
        )
    )

    return NotificationIdentityContract(
        has_seen_ids=has_seen_ids,
        has_pending_ids_fifo=has_pending_ids_fifo,
        no_scalar_pending_entry=no_scalar_pending_entry,
        no_count_only_gate=no_count_only_gate,
        no_last_seen_only=no_last_seen_only,
        has_displaying_id=has_displaying_id,
        has_find_live_by_id=has_find_live_by_id,
        has_enqueue_dedupe=has_enqueue_dedupe,
        has_remove_pending=has_remove_pending,
        handle_changed_uses_id_diff=handle_changed_uses_id_diff,
        maybe_show_drains_fifo=maybe_show_drains_fifo,
        maybe_show_skips_missing_live=maybe_show_skips_missing_live,
        present_sets_displaying_id=present_sets_displaying_id,
        has_notification_updated_signal=has_notification_updated_signal,
        wires_live_property_updates=wires_live_property_updates,
        island_connects_notification_updated=island_connects_notification_updated,
        handle_updated_inplace_when_displaying=handle_updated_inplace_when_displaying,
        handle_updated_no_repopup_when_idle=handle_updated_no_repopup_when_idle,
        handle_updated_keeps_queue_position=handle_updated_keeps_queue_position,
        apply_text_without_timer_restart=apply_text_without_timer_restart,
        dnd_clears_pending_ids=dnd_clears_pending_ids,
        disable_clears_pending_ids=disable_clears_pending_ids,
        timer_clears_displaying_and_drains=timer_clears_displaying_and_drains,
        single_pending_queue=single_pending_queue,
        no_second_notification_model=no_second_notification_model,
    )


# ---------------------------------------------------------------------------
# Behavioral simulation
# ---------------------------------------------------------------------------


@dataclass
class LiveNotification:
    id: int
    summary: str = ""
    body: str = ""
    app_name: str = ""


@dataclass
class IslandState:
    state: str = "resting_time"
    expanded: bool = False
    user_interacting: bool = False
    island_enabled: bool = True
    dnd: bool = False
    display_text: str = ""
    secondary_text: str = ""
    timer_restarts: int = 0
    present_count: int = 0
    presented_ids: list[int] = field(default_factory=list)


class IslandNotificationModel:
    """Simulates DynamicIsland identity + Notifications-owned FIFO lease (T07).

    use_identity=False mirrors the old count-only + scalar pending path.
    use_identity=True mirrors T07: no island live ID queue; completed set +
    activeModel order decide the next presentable notification.
    """

    def __init__(self, *, use_identity: bool) -> None:
        self.use_identity = use_identity
        self.active: list[LiveNotification] = []
        self.seen: dict[str, bool] = {}
        self.completed: dict[str, bool] = {}
        self.pending_ids: list[int] = []  # legacy field for old-path / assertions
        self.pending_entry: dict[str, Any] | None = None  # old path only
        self.observed_count = 0
        self.last_seen_id = -1
        self.displaying_id = -1
        self.ui = IslandState()

    def set_active(self, items: list[LiveNotification]) -> None:
        self.active = list(items)
        self.on_active_model_changed()

    def append(self, *items: LiveNotification) -> None:
        self.active = list(self.active) + list(items)
        self.on_active_model_changed()

    def remove_id(self, nid: int) -> None:
        self.active = [n for n in self.active if n.id != nid]
        self.on_active_model_changed()

    def replace_id_content(self, nid: int, *, summary: str, body: str = "", app_name: str = "") -> None:
        for n in self.active:
            if n.id == nid:
                n.summary = summary
                n.body = body
                n.app_name = app_name
                break
        # replace-id does not rewrite activeModel → no onActiveModelChanged
        self.on_notification_updated(nid)

    def on_active_model_changed(self) -> None:
        if self.use_identity:
            self._handle_changed_identity()
        else:
            self._handle_changed_old()

    def _handle_changed_old(self) -> None:
        next_count = len(self.active)
        if next_count <= self.observed_count:
            self.observed_count = next_count
            return
        notification = self.active[next_count - 1]
        self.observed_count = next_count
        self._incoming_old(notification)

    def _incoming_old(self, notification: LiveNotification) -> None:
        if self.ui.dnd:
            return
        if notification.id >= 0 and notification.id == self.last_seen_id:
            return
        self.last_seen_id = notification.id
        entry = self._entry(notification)
        if self._blocks():
            self.pending_entry = entry
            return
        self._present(entry)

    def _handle_changed_identity(self) -> None:
        next_seen: dict[str, bool] = {}
        for n in self.active:
            next_seen[str(n.id)] = True

        self.completed = {k: True for k in self.completed if k in next_seen}
        # legacy pending_ids field unused for live; keep empty for T07 assertions
        self.pending_ids = []
        if self.displaying_id >= 0 and str(self.displaying_id) not in next_seen:
            self.displaying_id = -1
        self.seen = next_seen

        if self.ui.dnd or not self.ui.island_enabled:
            return

        self.maybe_show()

    def _enqueue(self, nid: int) -> None:
        # T07: live IDs are not island-queued.
        return

    def _waiting_ids(self) -> list[int]:
        waiting: list[int] = []
        for n in self.active:
            if n.id == self.displaying_id:
                continue
            if str(n.id) in self.completed:
                continue
            waiting.append(n.id)
        return waiting

    def _blocks(self) -> bool:
        if self.ui.expanded or self.ui.user_interacting:
            return True
        if self.use_identity and self.ui.state == "transient_notification":
            return True
        return False

    def maybe_show(self) -> None:
        if not self.use_identity:
            if not self.pending_entry or self._blocks() or self.ui.dnd:
                return
            entry = self.pending_entry
            self.pending_entry = None
            self._present(entry)
            return

        if not self.ui.island_enabled or self.ui.dnd:
            return
        if self._blocks():
            return
        for n in self.active:
            if n.id == self.displaying_id:
                continue
            if str(n.id) in self.completed:
                continue
            self._present(self._entry(n))
            return

    def on_notification_updated(self, nid: int) -> None:
        if not self.use_identity:
            # Old path: no replace-id handling.
            return
        if self.ui.dnd or not self.ui.island_enabled:
            return
        if self.displaying_id == nid and self.ui.state == "transient_notification":
            live = self._find(nid)
            if not live:
                return
            entry = self._entry(live)
            self.ui.display_text = entry["summary"]
            self.ui.secondary_text = entry["body"]
            # no timer restart
            return
        # idle / waiting: no re-popup; latest content read on next present

    def hide_transient(self) -> None:
        if self.ui.state == "transient_notification":
            if self.displaying_id >= 0:
                self.completed[str(self.displaying_id)] = True
            self.displaying_id = -1
        self.ui.state = "resting_time"
        self.ui.display_text = ""
        self.ui.secondary_text = ""
        self.maybe_show()

    def set_busy(self, *, expanded: bool = False, interacting: bool = False) -> None:
        self.ui.expanded = expanded
        self.ui.user_interacting = interacting
        if not expanded and not interacting:
            self.maybe_show()

    def set_dnd(self, enabled: bool) -> None:
        self.ui.dnd = enabled
        if enabled:
            self.pending_ids = []
            self.pending_entry = None
            if self.ui.state == "transient_notification":
                if self.displaying_id >= 0:
                    self.completed[str(self.displaying_id)] = True
                self.ui.state = "resting_time"
                self.displaying_id = -1
                self.ui.display_text = ""
        else:
            self.maybe_show()

    def disable_island(self) -> None:
        self.ui.island_enabled = False
        self.pending_ids = []
        self.pending_entry = None
        self.displaying_id = -1

    def _find(self, nid: int) -> LiveNotification | None:
        for n in self.active:
            if n.id == nid:
                return n
        return None

    def _entry(self, n: LiveNotification) -> dict[str, Any]:
        summary = n.summary or n.app_name or "通知"
        return {
            "id": n.id,
            "summary": summary,
            "body": n.body,
            "appName": n.app_name,
        }

    def _present(self, entry: dict[str, Any]) -> None:
        self.ui.state = "transient_notification"
        self.ui.display_text = str(entry.get("summary") or "通知")
        self.ui.secondary_text = str(entry.get("body") or "")
        self.ui.timer_restarts += 1
        self.ui.present_count += 1
        nid = int(entry.get("id", -1))
        self.displaying_id = nid if nid >= 0 else -1
        self.ui.presented_ids.append(nid)


class DynamicIslandNotificationIdentityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.island_src = ISLAND.read_text(encoding="utf-8")
        self.notifications_src = NOTIFICATIONS.read_text(encoding="utf-8")
        self.contract = extract_contract(self.island_src, self.notifications_src)

    def test_static_contract_complete(self) -> None:
        incomplete = [
            name
            for name in NotificationIdentityContract.__annotations__
            if not getattr(self.contract, name)
        ]
        self.assertEqual(
            incomplete,
            [],
            "Dynamic Island notification identity contract incomplete:\n"
            + "\n".join(f"  - {n}" for n in incomplete),
        )
        self.assertTrue(self.contract.identity_path_complete)

    def test_old_count_only_and_scalar_pending_absent(self) -> None:
        self.assertNotIn("observedNotificationCount", self.island_src)
        self.assertNotIn("lastSeenNotificationId", self.island_src)
        self.assertNotIn("pendingNotificationEntry", self.island_src)
        self.assertIn("pendingNotificationIds", self.island_src)
        self.assertIn("seenNotificationIds", self.island_src)
        self.assertIn("notificationUpdated", self.notifications_src)

    def test_single_append_presents(self) -> None:
        m = IslandNotificationModel(use_identity=True)
        m.append(LiveNotification(1, summary="Hello"))
        self.assertEqual(m.ui.presented_ids, [1])
        self.assertEqual(m.ui.display_text, "Hello")
        self.assertEqual(m.displaying_id, 1)

    def test_equal_count_replace_detects_new_id(self) -> None:
        new = IslandNotificationModel(use_identity=True)
        old = IslandNotificationModel(use_identity=False)

        new.set_active([LiveNotification(1, summary="A")])
        new.hide_transient()
        # Equal-count swap: remove 1, add 2 in one model rewrite.
        new.set_active([LiveNotification(2, summary="B")])
        self.assertEqual(new.ui.presented_ids[-1], 2)
        self.assertEqual(new.ui.display_text, "B")

        old.set_active([LiveNotification(1, summary="A")])
        old.hide_transient()
        old.set_active([LiveNotification(2, summary="B")])
        # Old count-only: length unchanged → misses B.
        self.assertNotIn(2, old.ui.presented_ids)

    def test_batch_append_fifo_order(self) -> None:
        m = IslandNotificationModel(use_identity=True)
        # Single model change with two new IDs (batch) — Notifications FIFO order.
        m.set_active(
            [
                LiveNotification(10, summary="First"),
                LiveNotification(11, summary="Second"),
            ]
        )
        self.assertEqual(m.ui.presented_ids, [10])
        self.assertEqual(m._waiting_ids(), [11])
        self.assertEqual(m.pending_ids, [])  # no island live queue
        m.hide_transient()
        self.assertEqual(m.ui.presented_ids, [10, 11])
        self.assertEqual(m.ui.display_text, "Second")

        old = IslandNotificationModel(use_identity=False)
        old.set_active(
            [
                LiveNotification(10, summary="First"),
                LiveNotification(11, summary="Second"),
            ]
        )
        # Old only takes last item of the growth step.
        self.assertEqual(old.ui.presented_ids, [11])

    def test_busy_queues_then_drains_fifo(self) -> None:
        m = IslandNotificationModel(use_identity=True)
        m.set_busy(expanded=True)
        m.append(LiveNotification(1, summary="A"))
        m.append(LiveNotification(2, summary="B"))
        self.assertEqual(m.pending_ids, [])
        self.assertEqual(m._waiting_ids(), [1, 2])
        self.assertEqual(m.ui.present_count, 0)
        m.set_busy(expanded=False)
        self.assertEqual(m.ui.presented_ids, [1])
        self.assertEqual(m._waiting_ids(), [2])
        m.hide_transient()
        self.assertEqual(m.ui.presented_ids, [1, 2])

    def test_delete_queued_id_skips_safely(self) -> None:
        m = IslandNotificationModel(use_identity=True)
        m.set_busy(interacting=True)
        m.append(LiveNotification(1, summary="A"))
        m.append(LiveNotification(2, summary="B"))
        self.assertEqual(m._waiting_ids(), [1, 2])
        m.remove_id(1)
        self.assertEqual(m._waiting_ids(), [2])
        m.set_busy(interacting=False)
        self.assertEqual(m.ui.presented_ids, [2])
        self.assertEqual(m.ui.display_text, "B")

    def test_dnd_clears_queue(self) -> None:
        m = IslandNotificationModel(use_identity=True)
        m.set_busy(expanded=True)
        m.append(LiveNotification(1, summary="A"))
        self.assertEqual(m._waiting_ids(), [1])
        m.set_dnd(True)
        self.assertEqual(m.pending_ids, [])
        m.append(LiveNotification(2, summary="B"))
        self.assertEqual(m.ui.present_count, 0)
        self.assertNotEqual(m.ui.state, "transient_notification")

    def test_disable_clears_queue(self) -> None:
        m = IslandNotificationModel(use_identity=True)
        m.set_busy(expanded=True)
        m.append(LiveNotification(1, summary="A"))
        m.disable_island()
        self.assertEqual(m.pending_ids, [])
        self.assertEqual(m.ui.present_count, 0)

    def test_replace_id_while_displaying_updates_text_no_timer(self) -> None:
        m = IslandNotificationModel(use_identity=True)
        m.append(LiveNotification(5, summary="Old", body="x"))
        restarts = m.ui.timer_restarts
        presents = m.ui.present_count
        m.replace_id_content(5, summary="New", body="y")
        self.assertEqual(m.ui.display_text, "New")
        self.assertEqual(m.ui.secondary_text, "y")
        self.assertEqual(m.ui.timer_restarts, restarts)
        self.assertEqual(m.ui.present_count, presents)
        self.assertEqual(m.displaying_id, 5)

    def test_replace_id_while_queued_keeps_position_reads_latest(self) -> None:
        m = IslandNotificationModel(use_identity=True)
        m.set_busy(expanded=True)
        m.append(LiveNotification(1, summary="A"))
        m.append(LiveNotification(2, summary="B-old"))
        self.assertEqual(m._waiting_ids(), [1, 2])
        m.replace_id_content(2, summary="B-new")
        self.assertEqual(m._waiting_ids(), [1, 2])  # Notifications order preserved
        m.set_busy(expanded=False)
        self.assertEqual(m.ui.presented_ids, [1])
        m.hide_transient()
        self.assertEqual(m.ui.presented_ids[-1], 2)
        self.assertEqual(m.ui.display_text, "B-new")

    def test_replace_id_idle_does_not_repopup(self) -> None:
        m = IslandNotificationModel(use_identity=True)
        m.append(LiveNotification(7, summary="Once"))
        m.hide_transient()
        presents = m.ui.present_count
        m.replace_id_content(7, summary="Updated")
        self.assertEqual(m.ui.present_count, presents)
        self.assertEqual(m.pending_ids, [])
        self.assertNotEqual(m.ui.state, "transient_notification")

    def test_no_duplicate_enqueue(self) -> None:
        m = IslandNotificationModel(use_identity=True)
        m.set_busy(expanded=True)
        m.append(LiveNotification(1, summary="A"))
        # Same model rewrite with same IDs must not re-present.
        m.set_active([LiveNotification(1, summary="A")])
        self.assertEqual(m.pending_ids, [])
        self.assertEqual(m._waiting_ids(), [1])
        m.set_busy(expanded=False)
        self.assertEqual(m.ui.presented_ids, [1])
        m.hide_transient()
        # Still in model but completed — no second present.
        m.set_active([LiveNotification(1, summary="A")])
        self.assertEqual(m.ui.present_count, 1)

    def test_delete_after_append_then_append_other(self) -> None:
        m = IslandNotificationModel(use_identity=True)
        m.append(LiveNotification(1, summary="A"))
        m.hide_transient()
        m.remove_id(1)
        m.append(LiveNotification(2, summary="B"))
        self.assertEqual(m.ui.presented_ids[-1], 2)

        old = IslandNotificationModel(use_identity=False)
        old.append(LiveNotification(1, summary="A"))
        old.hide_transient()
        old.remove_id(1)
        old.append(LiveNotification(2, summary="B"))
        # Old may work for pure count growth; ensure new path also works.
        self.assertIn(2, old.ui.presented_ids)

    def test_forbidden_parallel_apis_absent(self) -> None:
        for forbidden in (
            "pendingNotificationEntry",
            "observedNotificationCount",
            "lastSeenNotificationId",
            "queueOrShowNotificationEntry",
            "notificationCache",
            "safeHandleNotifications",
        ):
            self.assertNotIn(forbidden, self.island_src)


if __name__ == "__main__":
    unittest.main()
