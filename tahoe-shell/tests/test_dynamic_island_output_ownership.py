#!/usr/bin/env python3
"""T08: event/session output ownership and per-screen resting clocks."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ISLAND = ROOT / "services" / "DynamicIsland.qml"
OWNERSHIP = ROOT / "components" / "DynamicIslandOwnership.js"
OVERLAY = ROOT / "components" / "DynamicIslandOverlay.qml"
TOPBAR = ROOT / "components" / "TopBar.qml"
TOAST = ROOT / "components" / "NotificationToast.qml"
EXPECTED = ROOT / "tests" / "test_dynamic_island_v2_expected_failures.py"
QML_TEST = Path(__file__).with_name("tst_dynamic_island_output_ownership.qml")


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
const op = request.op;
let result;
if (op === "resolve") {
  result = { owner: context.resolvePresentationOwner(request.pins || {}, request.live || {}) };
} else if (op === "sanitize") {
  result = context.sanitizeOwnerPins(request.pins || {}, request.available || []);
} else if (op === "role") {
  result = context.screenPresentationRole(
    request.screen, request.owner, request.presentation, request.flags || {});
} else {
  throw new Error("unknown op");
}
process.stdout.write(JSON.stringify(result));
"""


def run_node(request: dict) -> dict:
    if shutil.which("node") is None:
        raise unittest.SkipTest("node required")
    completed = subprocess.run(
        ["node", "-e", NODE_HELPER, str(OWNERSHIP), json.dumps(request)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return json.loads(completed.stdout)


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


class OutputOwnershipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.island = ISLAND.read_text(encoding="utf-8")
        cls.overlay = OVERLAY.read_text(encoding="utf-8")
        cls.topbar = TOPBAR.read_text(encoding="utf-8")
        cls.toast = TOAST.read_text(encoding="utf-8")
        cls.expected = EXPECTED.read_text(encoding="utf-8")

    def test_resolve_priority_session_over_event_over_focus(self) -> None:
        out = run_node({
            "op": "resolve",
            "pins": {"sessionOwnerOutput": "HDMI-A-1", "eventOwnerOutput": "eDP-2"},
            "live": {"focusedOutput": "DP-1", "firstOutput": "eDP-2"},
        })
        self.assertEqual(out["owner"], "HDMI-A-1")

        out = run_node({
            "op": "resolve",
            "pins": {"sessionOwnerOutput": "", "eventOwnerOutput": "eDP-2"},
            "live": {"focusedOutput": "HDMI-A-1", "firstOutput": "eDP-2"},
        })
        self.assertEqual(out["owner"], "eDP-2")

        out = run_node({
            "op": "resolve",
            "pins": {},
            "live": {"focusedOutput": "HDMI-A-1", "firstOutput": "eDP-2"},
        })
        self.assertEqual(out["owner"], "HDMI-A-1")

        out = run_node({
            "op": "resolve",
            "pins": {},
            "live": {"focusedOutput": "", "firstOutput": "eDP-2"},
        })
        self.assertEqual(out["owner"], "eDP-2")

    def test_sanitize_drops_removed_outputs(self) -> None:
        out = run_node({
            "op": "sanitize",
            "pins": {"eventOwnerOutput": "HDMI-A-1", "sessionOwnerOutput": "eDP-2"},
            "available": ["eDP-2"],
        })
        self.assertEqual(out["eventOwnerOutput"], "")
        self.assertEqual(out["sessionOwnerOutput"], "eDP-2")

    def test_non_owner_keeps_resting_when_hide_topbar_time(self) -> None:
        owner = run_node({
            "op": "role",
            "screen": "eDP-2",
            "owner": "eDP-2",
            "presentation": "transient_notification",
            "flags": {"islandEnabled": True, "hideTopbarTime": True},
        })
        self.assertTrue(owner["showIslandCapsule"])
        self.assertTrue(owner["showActivity"])
        self.assertFalse(owner["showTopbarTime"])

        non = run_node({
            "op": "role",
            "screen": "HDMI-A-1",
            "owner": "eDP-2",
            "presentation": "transient_notification",
            "flags": {"islandEnabled": True, "hideTopbarTime": True},
        })
        self.assertTrue(non["showIslandCapsule"])
        self.assertTrue(non["showIslandRestingClock"])
        self.assertFalse(non["showActivity"])
        self.assertFalse(non["showTopbarTime"])

    def test_owner_compact_media_is_activity(self) -> None:
        owner = run_node({
            "op": "role",
            "screen": "eDP-2",
            "owner": "eDP-2",
            "presentation": "resting_media",
            "flags": {"islandEnabled": True, "hideTopbarTime": True},
        })
        self.assertTrue(owner["showActivity"])
        self.assertFalse(owner["showIslandRestingClock"])

        non = run_node({
            "op": "role",
            "screen": "HDMI-A-1",
            "owner": "eDP-2",
            "presentation": "resting_media",
            "flags": {"islandEnabled": True, "hideTopbarTime": True},
        })
        self.assertFalse(non["showActivity"])
        self.assertTrue(non["showIslandRestingClock"])

    def test_hide_topbar_false_resting_overlay_hidden(self) -> None:
        role = run_node({
            "op": "role",
            "screen": "eDP-2",
            "owner": "eDP-2",
            "presentation": "resting_time",
            "flags": {"islandEnabled": True, "hideTopbarTime": False},
        })
        self.assertFalse(role["showIslandCapsule"])
        self.assertTrue(role["showTopbarTime"])

        activity = run_node({
            "op": "role",
            "screen": "eDP-2",
            "owner": "eDP-2",
            "presentation": "transient_osd",
            "flags": {"islandEnabled": True, "hideTopbarTime": False},
        })
        self.assertTrue(activity["showIslandCapsule"])
        self.assertTrue(activity["showActivity"])

    def test_production_pins_and_target_screen(self) -> None:
        self.assertIn("property string eventOwnerOutput", self.island)
        self.assertIn("property string sessionOwnerOutput", self.island)
        compute = _function_body(self.island, "computeTargetScreenName")
        self.assertIn("eventOwnerOutput", compute)
        self.assertIn("sessionOwnerOutput", compute)
        self.assertIn("resolvePresentationOwner", compute)
        self.assertIn("IslandOwnership", self.island)
        show = _function_body(self.island, "showTransient")
        self.assertIn("captureEventOwnerOutput", show)
        capture = _function_body(self.island, "captureEventOwnerOutput")
        # In-lease refresh must keep existing pin (H1).
        self.assertIn("existing", capture)
        self.assertIn("return existing", capture)
        # Abort paths clear event owner (H2).
        self.assertIn("clearEventOwner", self.island)
        self.assertIn("clearEventOwnerOutput", _function_body(self.island, "handleDndChanged")
                      or self.island)
        resolve = _function_body(self.island, "resolveSwipe")
        self.assertIn("screenName", resolve)
        self.assertIn("clearSessionOwnerOutput", resolve)
        media = _function_body(self.island, "handleMediaAvailabilityChanged")
        self.assertIn("claimSessionOwnerForScreen", media)

    def test_overlay_uses_screen_role(self) -> None:
        self.assertIn("IslandOwnership.screenPresentationRole", self.overlay)
        self.assertIn("DynamicIslandOwnership.js", self.overlay)
        self.assertIn("effectiveGeometryState", self.overlay)
        self.assertIn("effectiveContentState", self.overlay)
        self.assertIn("handleChipClick(mouse.button, root.ownScreenName)", self.overlay)

    def test_topbar_non_owner_clock_contract(self) -> None:
        # Must not use V1 global blanking: showTopbarTimeFallback is not solely
        # !overlayHandlesResting when that blanks non-owner.
        self.assertIn(
            "showTopbarTimeFallback: !dynamicIslandEnabled || !dynamicIslandHideTopbarTime",
            self.topbar,
        )
        # Notification badge/history still present regardless of owner.
        self.assertIn("notificationCount", self.topbar)

    def test_toast_suppressed_when_island_enabled(self) -> None:
        self.assertIn("suppressedByDynamicIsland", self.toast)
        self.assertIn("islandEnabled", self.toast)

    def test_t02_output_xfails_removed(self) -> None:
        self.assertNotRegex(
            self.expected,
            r"@pytest\.mark\.xfail\([\s\S]*?target T08",
        )

    def test_qml_multi_output_sim(self) -> None:
        if not QML_TEST.is_file():
            self.skipTest("qml harness missing")
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        self.assertIsNotNone(runner, "Qt 6 qmltestrunner is required")
        env = os.environ.copy()
        env.setdefault("QT_QPA_PLATFORM", "offscreen")
        local_qml = Path.home() / ".local" / "lib" / "qt6" / "qml"
        test_qml = ROOT / "tests" / "qml_imports"
        existing = env.get("QML2_IMPORT_PATH", "")
        paths = [str(test_qml), str(local_qml)]
        if existing:
            paths.append(existing)
        env["QML2_IMPORT_PATH"] = ":".join(paths)
        result = subprocess.run(
            [runner, "-input", str(QML_TEST)],
            cwd=str(ROOT),
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
