#!/usr/bin/env python3
"""T06: pure DynamicIslandReducer.js determinism and presentation parity."""

from __future__ import annotations

import json
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REDUCER = ROOT / "services" / "DynamicIslandReducer.js"
ISLAND = ROOT / "services" / "DynamicIsland.qml"


NODE_HELPER = r"""
const fs = require("fs");
const vm = require("vm");
const modulePath = process.argv[1];
const request = JSON.parse(process.argv[2]);
const source = fs.readFileSync(modulePath, "utf8").replace(/^\s*\.pragma library\s*\n/, "");
const context = {
  Array, Boolean, Date, JSON, Math, Number, Object, String, console, isFinite,
};
vm.createContext(context);
vm.runInContext(source, context, { filename: modulePath });

function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const key of Object.keys(value))
      deepFreeze(value[key]);
  }
  return value;
}

const op = request.op;
let result;
if (op === "reduce") {
  const state = request.state || context.createInitialState();
  const frozen = deepFreeze(JSON.parse(JSON.stringify(state)));
  const event = context.createEvent(request.kind, request.payload);
  const ctx = context.createContext(request.context || {});
  const outcome = context.reduce(frozen, event, ctx);
  // Input must not be mutated in place.
  const mutated = JSON.stringify(frozen) !== JSON.stringify(state);
  result = {
    state: outcome.state,
    effects: (outcome.effects || []).map((e) => e.type),
    presentation: context.presentationState(outcome.state, ctx),
    inputMutated: mutated,
  };
} else if (op === "presentation") {
  const state = request.state || context.createInitialState();
  const ctx = context.createContext(request.context || {});
  result = {
    presentation: context.presentationState(state, ctx),
    resting: context.restingState(state, ctx),
    valid: context.isValidState(request.candidate),
  };
} else if (op === "determinism") {
  const state = request.state || context.createInitialState();
  const event = context.createEvent(request.kind, request.payload);
  const ctx = context.createContext(request.context || {});
  const a = context.reduce(state, event, ctx);
  const b = context.reduce(state, event, ctx);
  result = {
    equal: JSON.stringify(a) === JSON.stringify(b),
    a, b,
  };
} else {
  throw new Error("unknown op " + op);
}
process.stdout.write(JSON.stringify(result));
"""


def run_node(request: dict) -> dict:
    if shutil.which("node") is None:
        raise unittest.SkipTest("node is required to execute DynamicIslandReducer.js")
    completed = subprocess.run(
        ["node", "-e", NODE_HELPER, str(REDUCER), json.dumps(request)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return json.loads(completed.stdout)


def reduce_ev(kind: str, state: dict | None = None, context: dict | None = None, payload=None) -> dict:
    return run_node({
        "op": "reduce",
        "kind": kind,
        "state": state or {},
        "context": context or {},
        "payload": payload,
    })


class DynamicIslandReducerTests(unittest.TestCase):
    def test_wiring_in_production_orchestrator(self) -> None:
        text = ISLAND.read_text(encoding="utf-8")
        self.assertIn('import "DynamicIslandReducer.js" as IslandReducer', text)
        self.assertIn("function dispatchPresentation", text)
        self.assertIn("IslandReducer.reduce", text)
        self.assertIn("IslandReducer.restingState", text)
        self.assertIn("IslandReducer.presentationState", text)
        # Migrated call sites must not keep parallel old decisions.
        self.assertNotRegex(
            text,
            r"function\s+restingState\s*\(\s*\)\s*\{\s*if\s*\(\s*!root\.islandEnabled\s*\)",
        )
        self.assertIn('dispatchPresentation("SHOW_TIME")', text)
        self.assertIn('dispatchPresentation("TOGGLE_EXPANDED")', text)
        self.assertIn('dispatchPresentation("MEDIA_AVAILABILITY_CHANGED")', text)

    def test_initial_resting_clock_and_media(self) -> None:
        clock = run_node({
            "op": "presentation",
            "state": {"forcedState": "", "preferMediaWhenAvailable": True},
            "context": {"islandEnabled": True, "hasMedia": False},
        })
        self.assertEqual(clock["resting"], "resting_time")
        self.assertEqual(clock["presentation"], "resting_time")

        media = run_node({
            "op": "presentation",
            "state": {"forcedState": "", "preferMediaWhenAvailable": True},
            "context": {"islandEnabled": True, "hasMedia": True},
        })
        self.assertEqual(media["resting"], "resting_media")
        self.assertEqual(media["presentation"], "resting_media")

        prefer_time = run_node({
            "op": "presentation",
            "state": {"forcedState": "", "preferMediaWhenAvailable": False},
            "context": {"islandEnabled": True, "hasMedia": True},
        })
        self.assertEqual(prefer_time["resting"], "resting_time")

    def test_show_time_and_media(self) -> None:
        out = reduce_ev("SHOW_TIME", context={"islandEnabled": True, "hasMedia": True})
        self.assertFalse(out["state"]["preferMediaWhenAvailable"])
        self.assertEqual(out["state"]["forcedState"], "")
        self.assertEqual(out["presentation"], "resting_time")
        self.assertIn("stopTransientTimer", out["effects"])
        self.assertIn("endNotificationLease", out["effects"])
        self.assertNotIn("maybeShowPendingNotification", out["effects"])

        media = reduce_ev(
            "SHOW_MEDIA",
            state={"preferMediaWhenAvailable": False},
            context={"islandEnabled": True, "hasMedia": True},
        )
        self.assertTrue(media["state"]["preferMediaWhenAvailable"])
        self.assertEqual(media["state"]["forcedState"], "resting_media")
        self.assertEqual(media["presentation"], "resting_media")

        no_media = reduce_ev(
            "SHOW_MEDIA",
            context={"islandEnabled": True, "hasMedia": False},
        )
        self.assertEqual(no_media["state"]["forcedState"], "")
        self.assertEqual(no_media["presentation"], "resting_time")

    def test_expand_collapse_parity(self) -> None:
        expanded = reduce_ev(
            "SHOW_EXPANDED_MEDIA",
            context={"islandEnabled": True, "hasMedia": True},
        )
        self.assertEqual(expanded["state"]["forcedState"], "expanded_media")
        self.assertEqual(expanded["presentation"], "expanded_media")

        fallback = reduce_ev(
            "SHOW_EXPANDED_MEDIA",
            context={"islandEnabled": True, "hasMedia": False},
        )
        self.assertEqual(fallback["state"]["forcedState"], "")

        summary = reduce_ev(
            "SHOW_EXPANDED_SUMMARY",
            context={"islandEnabled": True, "hasMedia": True},
        )
        self.assertEqual(summary["state"]["forcedState"], "")
        self.assertIn("openControlCenter", summary["effects"])

        collapsed = reduce_ev(
            "TOGGLE_EXPANDED",
            state={"forcedState": "expanded_media", "preferMediaWhenAvailable": True},
            context={"islandEnabled": True, "hasMedia": True},
        )
        self.assertEqual(collapsed["state"]["forcedState"], "")
        self.assertIn("endNotificationLease", collapsed["effects"])

        open_media = reduce_ev(
            "TOGGLE_EXPANDED",
            state={"forcedState": ""},
            context={"islandEnabled": True, "hasMedia": True},
        )
        self.assertEqual(open_media["state"]["forcedState"], "expanded_media")

        open_summary = reduce_ev(
            "TOGGLE_EXPANDED",
            state={"forcedState": ""},
            context={"islandEnabled": True, "hasMedia": False},
        )
        self.assertEqual(open_summary["state"]["forcedState"], "")

        # Collapse ends any notification lease; orchestrator drains once after apply.
        click_collapse = reduce_ev(
            "COLLAPSE",
            state={"forcedState": "expanded_media", "hoverExpanded": True},
            context={"islandEnabled": True, "hasMedia": True},
        )
        self.assertEqual(click_collapse["state"]["forcedState"], "")
        self.assertFalse(click_collapse["state"]["hoverExpanded"])
        self.assertEqual(click_collapse["effects"], ["endNotificationLease"])

    def test_media_availability_and_auto_expand(self) -> None:
        lost = reduce_ev(
            "MEDIA_AVAILABILITY_CHANGED",
            state={"forcedState": "expanded_media", "hoverExpanded": True},
            context={"islandEnabled": True, "hasMedia": False},
        )
        self.assertEqual(lost["state"]["forcedState"], "")
        self.assertFalse(lost["state"]["hoverExpanded"])

        auto = reduce_ev(
            "MEDIA_AVAILABILITY_CHANGED",
            state={"forcedState": ""},
            context={
                "islandEnabled": True,
                "hasMedia": True,
                "autoExpandMedia": True,
                "userInteracting": False,
            },
        )
        self.assertEqual(auto["state"]["forcedState"], "expanded_media")

        blocked = reduce_ev(
            "MEDIA_AVAILABILITY_CHANGED",
            state={"forcedState": ""},
            context={
                "islandEnabled": True,
                "hasMedia": True,
                "autoExpandMedia": True,
                "userInteracting": True,
            },
        )
        self.assertEqual(blocked["state"]["forcedState"], "")

    def test_disabled_and_reset(self) -> None:
        disabled = reduce_ev(
            "SHOW_EXPANDED_MEDIA",
            state={"forcedState": "expanded_media"},
            context={"islandEnabled": False, "hasMedia": True},
        )
        self.assertEqual(disabled["state"]["forcedState"], "expanded_media")
        self.assertEqual(disabled["effects"], [])
        self.assertEqual(disabled["presentation"], "resting_time")

        # Disable preserves preferMediaWhenAvailable (showTime preference survives).
        off = reduce_ev(
            "ISLAND_DISABLED",
            state={
                "forcedState": "expanded_media",
                "preferMediaWhenAvailable": False,
                "hoverExpanded": True,
            },
            context={"islandEnabled": False, "hasMedia": True},
        )
        self.assertEqual(off["state"]["forcedState"], "")
        self.assertFalse(off["state"]["preferMediaWhenAvailable"])
        self.assertFalse(off["state"]["hoverExpanded"])
        self.assertIn("clearSwipe", off["effects"])
        self.assertIn("stopTransientTimer", off["effects"])
        self.assertIn("clearTransientFields", off["effects"])

        reset = reduce_ev(
            "RESET",
            state={"forcedState": "expanded_media", "preferMediaWhenAvailable": False, "hoverExpanded": True},
            context={"islandEnabled": True, "hasMedia": True},
        )
        self.assertEqual(reset["state"]["forcedState"], "")
        self.assertTrue(reset["state"]["preferMediaWhenAvailable"])
        self.assertFalse(reset["state"]["hoverExpanded"])
        self.assertNotIn("clearSwipe", reset["effects"])

        reset_while_disabled = reduce_ev(
            "RESET",
            state={"forcedState": "expanded_media", "preferMediaWhenAvailable": False},
            context={"islandEnabled": False, "hasMedia": True},
        )
        self.assertTrue(reset_while_disabled["state"]["preferMediaWhenAvailable"])
        self.assertNotIn("clearSwipe", reset_while_disabled["effects"])

    def test_show_time_ends_notification_lease_before_clear(self) -> None:
        # Abort paths must end the notification lease before/with cleanup so
        # displayingNotificationId cannot stick after SHOW_TIME.
        out = reduce_ev("SHOW_TIME", context={"islandEnabled": True, "hasMedia": True})
        effects = out["effects"]
        stop_i = effects.index("stopTransientTimer")
        lease_i = effects.index("endNotificationLease")
        clear_i = effects.index("clearTransientFields")
        self.assertLess(stop_i, clear_i)
        self.assertLess(lease_i, clear_i)
        self.assertNotIn("maybeShowPendingNotification", effects)

    def test_apply_order_helpers_exist_in_orchestrator(self) -> None:
        text = ISLAND.read_text(encoding="utf-8")
        # Cleanup effects must be applied before forcedState assignment.
        apply = text[text.find("function applyReducerResult") : text.find("function dispatchPresentation")]
        self.assertIn("cleanupTypes", apply)
        forced_pos = apply.find("root.forcedState")
        cleanup_loop = apply.find("cleanupTypes[String(effects[i].type")
        self.assertGreater(forced_pos, 0)
        self.assertGreater(cleanup_loop, 0)
        self.assertLess(cleanup_loop, forced_pos)

    def test_hover_expand_collapse(self) -> None:
        expand = reduce_ev(
            "HOVER_EXPAND",
            state={"forcedState": ""},
            context={"islandEnabled": True, "hasMedia": True, "userInteracting": False},
        )
        self.assertTrue(expand["state"]["hoverExpanded"])
        self.assertEqual(expand["state"]["forcedState"], "expanded_media")

        collapse = reduce_ev(
            "HOVER_COLLAPSE",
            state={"forcedState": "expanded_media", "hoverExpanded": True},
            context={"islandEnabled": True, "hasMedia": True},
        )
        self.assertFalse(collapse["state"]["hoverExpanded"])
        self.assertEqual(collapse["state"]["forcedState"], "")
        self.assertIn("endNotificationLease", collapse["effects"])
        self.assertNotIn("maybeShowPendingNotification", collapse["effects"])

    def test_determinism_and_immutability(self) -> None:
        det = run_node({
            "op": "determinism",
            "kind": "SHOW_MEDIA",
            "state": {"forcedState": "", "preferMediaWhenAvailable": False, "hoverExpanded": False},
            "context": {"islandEnabled": True, "hasMedia": True},
        })
        self.assertTrue(det["equal"])

        out = reduce_ev(
            "SHOW_TIME",
            state={"forcedState": "expanded_media", "preferMediaWhenAvailable": True, "hoverExpanded": True},
            context={"islandEnabled": True, "hasMedia": True},
        )
        self.assertFalse(out["inputMutated"])

    def test_invalid_forced_falls_back_to_resting(self) -> None:
        out = run_node({
            "op": "presentation",
            "state": {"forcedState": "not_a_state", "preferMediaWhenAvailable": True},
            "context": {"islandEnabled": True, "hasMedia": True},
            "candidate": "not_a_state",
        })
        self.assertFalse(out["valid"])
        self.assertEqual(out["presentation"], "resting_media")

        media_without = run_node({
            "op": "presentation",
            "state": {"forcedState": "expanded_media", "preferMediaWhenAvailable": True},
            "context": {"islandEnabled": True, "hasMedia": False},
        })
        self.assertEqual(media_without["presentation"], "resting_time")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
