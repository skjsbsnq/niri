#!/usr/bin/env python3
"""Task 02: swipe dismiss must bind to stable notification identity.

Root race (old code):
  1. User swipes notification A past threshold → Timer.pending = true
  2. While exit animation runs, A is closed externally; B promotes into stackIndex 0
  3. Timer fires and reads cardRoot.notification (now B) → dismisses B

Fix contract:
  - resolveSwipe captures notifId into Timer.pendingId at commit time
  - onTriggered dismisses only pendingId via dismissNotificationId
  - never re-reads stackIndex-bound notification on Timer fire
  - cancel / snap-back / new press clear pending identity

Regression strategy:
  1. Static contract extraction from NotificationToast.qml (fails on old Timer body).
  2. Behavioral simulation of A→external-close→B-rebind→Timer using only the
     extracted identity path (old dynamic-notification path fails assertions).
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass, field
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
TOAST = SHELL_ROOT / "components" / "NotificationToast.qml"
NOTIFICATIONS = SHELL_ROOT / "services" / "Notifications.qml"


@dataclass(frozen=True)
class SwipeDismissContract:
    """Wiring discovered in source. Missing edges reproduce the old race."""

    has_dismiss_notification_id: bool
    dismiss_notification_delegates_to_id: bool
    timer_has_pending_id: bool
    timer_dismisses_pending_id: bool
    timer_does_not_read_card_notification: bool
    resolve_captures_notif_id: bool
    resolve_sets_pending_id: bool
    clear_pending_exists: bool
    cancel_clears_pending: bool
    snap_back_clears_pending: bool
    begin_swipe_clears_pending: bool
    uses_notifications_dismiss_id: bool
    no_parallel_pending_model: bool
    no_index_as_identity: bool

    @property
    def identity_path_complete(self) -> bool:
        return (
            self.has_dismiss_notification_id
            and self.dismiss_notification_delegates_to_id
            and self.timer_has_pending_id
            and self.timer_dismisses_pending_id
            and self.timer_does_not_read_card_notification
            and self.resolve_captures_notif_id
            and self.resolve_sets_pending_id
            and self.clear_pending_exists
            and self.cancel_clears_pending
            and self.snap_back_clears_pending
            and self.begin_swipe_clears_pending
            and self.uses_notifications_dismiss_id
            and self.no_parallel_pending_model
            and self.no_index_as_identity
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


def _extract_timer_block(src: str) -> str:
    m = re.search(r"Timer\s*\{\s*id:\s*dismissAfterSwipe", src)
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


def extract_contract(toast_src: str, notifications_src: str) -> SwipeDismissContract:
    dismiss_id_fn = _extract_function_body(toast_src, "dismissNotificationId")
    dismiss_fn = _extract_function_body(toast_src, "dismissNotification")
    resolve_fn = _extract_function_body(toast_src, "resolveSwipe")
    begin_fn = _extract_function_body(toast_src, "beginSwipe")
    clear_fn = _extract_function_body(toast_src, "clearPendingDismiss")
    timer = _extract_timer_block(toast_src)

    # Timer onTriggered must not re-read the live binding.
    timer_on_triggered = ""
    tm = re.search(r"onTriggered:\s*\{", timer)
    if tm:
        depth = 1
        i = tm.end()
        while i < len(timer) and depth:
            if timer[i] == "{":
                depth += 1
            elif timer[i] == "}":
                depth -= 1
            i += 1
        timer_on_triggered = timer[tm.end() : i - 1]

    timer_reads_card_notification = bool(
        re.search(r"cardRoot\.notification", timer_on_triggered)
    )
    # Old bug signature: dismissNotification(cardRoot.notification) inside Timer.
    old_bug_signature = bool(
        re.search(
            r"dismissNotification\s*\(\s*cardRoot\.notification\s*\)",
            timer_on_triggered,
        )
    )

    # pendingId must not be confused with stackIndex storage as identity.
    resolve_uses_stack_index_as_pending = bool(
        re.search(r"pendingId\s*=\s*cardRoot\.stackIndex", resolve_fn)
        or re.search(r"pendingId\s*=\s*stackIndex", resolve_fn)
    )

    # No parallel pending notification object / model copy in toast.
    parallel_pending_model = bool(
        re.search(
            r"property\s+(var|QtObject)\s+pendingNotification\b",
            toast_src,
        )
        or re.search(r"pendingNotificationModel", toast_src)
        or re.search(r"pendingDismissNotification\b", toast_src)
    )

    return SwipeDismissContract(
        has_dismiss_notification_id=bool(
            re.search(r"function\s+dismissNotificationId\s*\(", toast_src)
        ),
        dismiss_notification_delegates_to_id=(
            "dismissNotificationId" in dismiss_fn
            and "dismissId" not in dismiss_fn  # object path delegates; id path owns service call
        )
        or (
            "dismissNotificationId" in dismiss_fn
        ),
        timer_has_pending_id=bool(
            re.search(r"property\s+int\s+pendingId", timer)
        ),
        timer_dismisses_pending_id=bool(
            re.search(r"dismissNotificationId\s*\(\s*id\s*\)", timer_on_triggered)
            or re.search(r"dismissNotificationId\s*\(\s*pendingId\s*\)", timer_on_triggered)
        ),
        timer_does_not_read_card_notification=(
            not timer_reads_card_notification and not old_bug_signature
        ),
        resolve_captures_notif_id=bool(
            re.search(r"notifId", resolve_fn)
            and re.search(r"pendingId", resolve_fn)
        ),
        resolve_sets_pending_id=bool(
            re.search(r"pendingId\s*=", resolve_fn)
        )
        and not resolve_uses_stack_index_as_pending,
        clear_pending_exists=bool(clear_fn)
        and "pendingId" in clear_fn
        and bool(re.search(r"pending\s*=\s*false", clear_fn)),
        cancel_clears_pending=bool(
            re.search(
                r"onCanceled:\s*\{[^}]*clearPendingDismiss",
                toast_src,
                re.DOTALL,
            )
        ),
        snap_back_clears_pending=(
            "clearPendingDismiss" in resolve_fn
            and "swipeX = 0" in resolve_fn
        ),
        begin_swipe_clears_pending="clearPendingDismiss" in begin_fn,
        uses_notifications_dismiss_id=bool(
            re.search(r"dismissId\s*\(", dismiss_id_fn)
            or re.search(
                r"notificationsService\.dismissId",
                dismiss_id_fn + dismiss_fn,
            )
        )
        and bool(re.search(r"function\s+dismissId\s*\(", notifications_src)),
        no_parallel_pending_model=not parallel_pending_model,
        no_index_as_identity=not resolve_uses_stack_index_as_pending,
    )


@dataclass
class FakeNotification:
    id: int
    closed: bool = False

    def dismiss(self) -> None:
        self.closed = True


@dataclass
class NotificationsOwner:
    """Minimal stand-in for Notifications.dismissId identity lookup."""

    active: list[FakeNotification] = field(default_factory=list)
    dismiss_calls: list[int] = field(default_factory=list)

    def dismiss_id(self, nid: int) -> None:
        self.dismiss_calls.append(int(nid))
        for n in list(self.active):
            if n.id == nid:
                n.dismiss()
                self.active = [x for x in self.active if x.id != nid]
                return
        # Already gone — idempotent no-op (matches service).


class ToastCardModel:
    """Simulates stackIndex-bound card + delayed dismiss identity.

    When use_stable_identity is False, mirrors the old Timer body that
    re-reads the live notification binding (the race under test).
    """

    def __init__(
        self,
        service: NotificationsOwner,
        *,
        use_stable_identity: bool,
    ) -> None:
        self.service = service
        self.use_stable_identity = use_stable_identity
        self.stack_index = 0
        self.stack_items: list[FakeNotification] = []
        self.swipe_dragging = False
        self.pending = False
        self.pending_id = -1
        self.timer_armed = False

    @property
    def notification(self) -> FakeNotification | None:
        if self.stack_index < 0 or self.stack_index >= len(self.stack_items):
            return None
        return self.stack_items[self.stack_index]

    @property
    def notif_id(self) -> int:
        n = self.notification
        return int(n.id) if n is not None else -1

    def rebind_stack(self, items: list[FakeNotification]) -> None:
        """Promote/demote: stackItems changes; stackIndex slot identity changes."""
        self.stack_items = list(items)

    def begin_swipe(self) -> None:
        self.swipe_dragging = True
        self.clear_pending()

    def clear_pending(self) -> None:
        self.timer_armed = False
        self.pending = False
        self.pending_id = -1

    def resolve_swipe_commit(self) -> None:
        """Past threshold: schedule delayed dismiss."""
        if not self.swipe_dragging:
            return
        self.swipe_dragging = False
        if self.use_stable_identity:
            nid = self.notif_id
            if nid < 0:
                self.clear_pending()
                return
            self.pending = True
            self.pending_id = nid
            self.timer_armed = True
        else:
            # Old path: only a boolean pending flag.
            self.pending = True
            self.pending_id = -1
            self.timer_armed = True

    def resolve_swipe_snap_back(self) -> None:
        if not self.swipe_dragging:
            return
        self.swipe_dragging = False
        self.clear_pending()

    def cancel(self) -> None:
        self.swipe_dragging = False
        self.clear_pending()

    def fire_timer(self) -> None:
        if not self.timer_armed:
            return
        self.timer_armed = False
        if self.use_stable_identity:
            was = self.pending
            nid = self.pending_id
            self.pending = False
            self.pending_id = -1
            if was and nid >= 0:
                self.service.dismiss_id(nid)
        else:
            # Old bug: re-read live binding at fire time.
            if self.pending and self.notification is not None:
                self.service.dismiss_id(self.notification.id)
            self.pending = False


class NotificationSwipeStableIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.toast_src = TOAST.read_text(encoding="utf-8")
        cls.notifications_src = NOTIFICATIONS.read_text(encoding="utf-8")
        cls.contract = extract_contract(cls.toast_src, cls.notifications_src)

    def test_source_contract_binds_timer_to_stable_id(self) -> None:
        c = self.contract
        self.assertTrue(
            c.identity_path_complete,
            msg=(
                "swipe dismiss identity contract incomplete: "
                f"{c}"
            ),
        )
        # Explicit old-bug guard: Timer must not dismiss via live notification.
        timer = _extract_timer_block(self.toast_src)
        self.assertNotIn(
            "cardRoot.notification",
            re.search(r"onTriggered:\s*\{.*", timer, re.DOTALL).group(0)
            if re.search(r"onTriggered:\s*\{", timer)
            else "",
        )

    def test_dismiss_notification_id_uses_service_dismiss_id(self) -> None:
        body = _extract_function_body(self.toast_src, "dismissNotificationId")
        self.assertIn("dismissId", body)
        self.assertRegex(body, r"Number\(id\)|id")

    def test_race_a_external_close_b_rebind_timer_must_not_dismiss_b(self) -> None:
        """Canonical failure order from the roadmap.

        A swiped → A closed externally → B occupies index 0 → Timer fires.
        Fixed path: only A is targeted (idempotent); B remains.
        Old path: B is dismissed.
        """
        a = FakeNotification(id=101)
        b = FakeNotification(id=202)
        service = NotificationsOwner(active=[a, b])

        fixed = ToastCardModel(service, use_stable_identity=True)
        fixed.rebind_stack([a, b])  # A on top (index 0)
        fixed.begin_swipe()
        fixed.resolve_swipe_commit()
        self.assertEqual(fixed.pending_id, 101)

        # External close of A; B promotes into stackIndex 0.
        service.dismiss_id(101)
        self.assertEqual([n.id for n in service.active], [202])
        fixed.rebind_stack(service.active)
        self.assertEqual(fixed.notif_id, 202)

        dismiss_before = list(service.dismiss_calls)
        fixed.fire_timer()
        # Idempotent attempt on A only — no new dismiss of B.
        self.assertEqual(service.dismiss_calls[len(dismiss_before) :], [101])
        self.assertEqual([n.id for n in service.active], [202])
        self.assertFalse(b.closed)

        # Old path would kill B:
        a2 = FakeNotification(id=101)
        b2 = FakeNotification(id=202)
        old_service = NotificationsOwner(active=[a2, b2])
        old = ToastCardModel(old_service, use_stable_identity=False)
        old.rebind_stack([a2, b2])
        old.begin_swipe()
        old.resolve_swipe_commit()
        old_service.dismiss_id(101)
        old.rebind_stack(old_service.active)
        old.fire_timer()
        self.assertIn(202, old_service.dismiss_calls)
        self.assertEqual(old_service.active, [])

    def test_timer_targets_captured_id_even_if_still_bound(self) -> None:
        a = FakeNotification(id=7)
        service = NotificationsOwner(active=[a])
        card = ToastCardModel(service, use_stable_identity=True)
        card.rebind_stack([a])
        card.begin_swipe()
        card.resolve_swipe_commit()
        card.fire_timer()
        self.assertEqual(service.dismiss_calls, [7])
        self.assertEqual(service.active, [])

    def test_consecutive_swipes_do_not_cross_contaminate(self) -> None:
        a = FakeNotification(id=1)
        b = FakeNotification(id=2)
        c = FakeNotification(id=3)
        service = NotificationsOwner(active=[a, b, c])
        card = ToastCardModel(service, use_stable_identity=True)

        # Swipe A, fire, then B, fire — each only its id.
        card.rebind_stack([a, b, c])
        card.begin_swipe()
        card.resolve_swipe_commit()
        card.fire_timer()
        self.assertEqual(service.dismiss_calls[-1:], [1])
        card.rebind_stack(service.active)
        self.assertEqual(card.notif_id, 2)

        card.begin_swipe()
        card.resolve_swipe_commit()
        card.fire_timer()
        self.assertEqual(service.dismiss_calls, [1, 2])
        self.assertEqual([n.id for n in service.active], [3])

    def test_cancel_and_snap_back_clear_pending_identity(self) -> None:
        a = FakeNotification(id=9)
        service = NotificationsOwner(active=[a])
        card = ToastCardModel(service, use_stable_identity=True)
        card.rebind_stack([a])

        card.begin_swipe()
        card.resolve_swipe_commit()
        self.assertTrue(card.pending)
        card.cancel()
        card.fire_timer()  # no-op
        self.assertEqual(service.dismiss_calls, [])
        self.assertEqual(service.active, [a])

        card.begin_swipe()
        card.resolve_swipe_commit()
        card.clear_pending()  # snap-back path
        card.fire_timer()
        self.assertEqual(service.dismiss_calls, [])

    def test_new_press_supersedes_prior_pending(self) -> None:
        a = FakeNotification(id=11)
        b = FakeNotification(id=12)
        service = NotificationsOwner(active=[a, b])
        card = ToastCardModel(service, use_stable_identity=True)
        card.rebind_stack([a, b])
        card.begin_swipe()
        card.resolve_swipe_commit()
        self.assertEqual(card.pending_id, 11)
        # New press before timer: clears prior pending (beginSwipe contract).
        card.begin_swipe()
        self.assertFalse(card.pending)
        self.assertEqual(card.pending_id, -1)
        card.fire_timer()
        self.assertEqual(service.dismiss_calls, [])

    def test_idempotent_double_fire_safe(self) -> None:
        a = FakeNotification(id=5)
        service = NotificationsOwner(active=[a])
        card = ToastCardModel(service, use_stable_identity=True)
        card.rebind_stack([a])
        card.begin_swipe()
        card.resolve_swipe_commit()
        card.fire_timer()
        card.fire_timer()
        self.assertEqual(service.dismiss_calls, [5])

    def test_contract_requires_stable_path_for_behavioral_model(self) -> None:
        """If source contract regresses, behavioral fixed-path must not be claimed."""
        self.assertTrue(self.contract.identity_path_complete)
        # Simulate with contract flag from source — guards against testing a
        # model that no longer matches QML.
        service = NotificationsOwner(active=[FakeNotification(1), FakeNotification(2)])
        card = ToastCardModel(
            service,
            use_stable_identity=self.contract.identity_path_complete,
        )
        a, b = service.active[0], service.active[1]
        card.rebind_stack([a, b])
        card.begin_swipe()
        card.resolve_swipe_commit()
        service.dismiss_id(1)
        card.rebind_stack(service.active)
        card.fire_timer()
        self.assertEqual([n.id for n in service.active], [2])


if __name__ == "__main__":
    unittest.main()
