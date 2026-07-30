#!/usr/bin/env python3
"""T-23 / S-M2: ControlCenter module morph keeps the panel height monotonic.

Root cause: the morph animated four properties through four independent
Behaviors (morphHost preferred height, both crossfade opacities, sibling top
margin) while the sibling stack's height was switched with no animation at all.
On the first morph frame the sibling stack dropped straight to 0 while morphHost
was still growing, so the glass panel's bottom edge dived ~180px and then climbed
back — measured at 312 → 132 → 317 → 300 on the pre-fix tree.

Fix: one morph clock (`root.morphProgress`) that every morph-coupled geometry and
opacity value reads as a linear function, so the panel height travels straight
between its endpoints.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
CONTROL_CENTER = SHELL_ROOT / "components" / "ControlCenter.qml"
QML_PROBE = Path(__file__).with_name("tst_control_center_morph_monotonic.qml")


class ControlCenterMorphStructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = CONTROL_CENTER.read_text(encoding="utf-8")

    def test_single_morph_clock_owns_every_coupled_value(self) -> None:
        source = self.source
        self.assertIn("property real morphProgress: root.moduleExpanded ? 1 : 0", source)

        # Geometry and opacity are linear in the one clock, not independently
        # animated. Each of these was its own Behavior before the fix.
        self.assertIn(
            "Layout.preferredHeight: root.collapsedTopHeight\n"
            "                    + (root.expandedTopHeight - root.collapsedTopHeight)"
            " * root.morphProgress",
            source,
        )
        self.assertIn("opacity: 1 - root.morphProgress", source)
        self.assertIn("opacity: root.morphProgress", source)
        self.assertIn("Motion.ccMorphSiblingOffsetPx * root.morphProgress", source)

    def test_only_the_clock_carries_a_morph_behavior(self) -> None:
        source = self.source
        self.assertIn("Behavior on morphProgress", source)

        # The retired per-property morph Behaviors must not come back: a second
        # animator on any morph-coupled value re-creates the desync.
        self.assertNotIn("Behavior on Layout.topMargin", source)
        morph_host = source.split("id: morphHost", 1)[1].split("id: collapsedRow", 1)[0]
        self.assertNotIn("Behavior on", morph_host)
        collapsed_row = source.split("id: collapsedRow", 1)[1].split("ConnectivityTile", 1)[0]
        self.assertNotIn("Behavior on opacity", collapsed_row)
        module_panel = source.split("id: modulePanel", 1)[1].split("// ---- Sliders", 1)[0]
        self.assertNotIn("Behavior on opacity", module_panel)

        # The sibling clip host must stay animator-free too. A Behavior here
        # would lag the collapse behind the morph clock and resurrect the
        # T11-fix3 bug (68b042f: sliders visibly jump down when 「编辑控制项」
        # collapses). The runtime probe cannot catch it — it samples after the
        # animation would have settled — so this is the only guard.
        sibling_host = source.split("id: siblingHost", 1)[1].split("id: siblingColumn", 1)[0]
        self.assertNotIn("Behavior on", sibling_host)

        # Glass region geometry stays on eased NumberAnimation — never Spring.
        self.assertNotIn("SpringAnimation", source)
        self.assertIn("Motion.emphasizedDecel", source)

    def test_sibling_gap_collapses_with_the_stack(self) -> None:
        source = self.source
        # The 12px inter-section gap used to be ColumnLayout spacing, which is
        # dropped in a single frame when the stack stops being laid out. It now
        # belongs to the collapsing host so it shrinks continuously.
        self.assertIn("readonly property int siblingGap: 12", source)
        self.assertIn("id: siblingHost", source)
        self.assertIn(
            "Layout.preferredHeight: (siblingHost.travelHeight + root.siblingGap)\n"
            "                    * (1 - root.morphProgress)",
            source,
        )
        content_block = re.search(
            r"ColumnLayout \{\s*id: content.*?// ---- Morph host",
            source,
            re.S,
        )
        self.assertIsNotNone(content_block)
        assert content_block
        self.assertIn("spacing: 0", content_block.group(0))

        # The retired hard height switch must not return.
        self.assertNotIn("Layout.preferredHeight: root.moduleExpanded ? 0 : -1", source)
        self.assertNotIn("Layout.maximumHeight: root.moduleExpanded ? 0 : -1", source)

    def test_natural_height_is_latched_while_the_morph_runs(self) -> None:
        source = self.source
        # siblingColumn.implicitHeight re-resolves by a pixel or two as its
        # children relayout under the shrinking clip; feeding that live value
        # into the collapse makes the panel edge wobble.
        self.assertIn("property real travelHeight", source)
        self.assertIn("readonly property real naturalHeight", source)
        self.assertIn("onNaturalHeightChanged", source)
        self.assertIn("function onMorphProgressChanged()", source)

    def test_dismissal_snaps_the_clock_instead_of_freezing_it(self) -> None:
        source = self.source
        # The P02 freeze gate stops animation ticks the moment the surface
        # unmaps, so a morph left in flight would hold a partial progress and
        # the next open would resume from there. The suspend must be imperative
        # and must precede the state clear — a Behavior `enabled:` binding is
        # not guaranteed to re-evaluate before onOpenChanged runs.
        self.assertIn("property bool morphAnimatable: true", source)
        self.assertIn("enabled: root.morphAnimatable", source)

        handler = source.split("onOpenChanged: {", 1)[1].split("\n    }", 1)[0]
        self.assertIn("root.morphAnimatable = false;", handler)
        self.assertIn('root.expandedModule = "";', handler)
        self.assertLess(
            handler.index("root.morphAnimatable = false;"),
            handler.index('root.expandedModule = "";'),
            "morph clock must be suspended before the module state is cleared",
        )
        self.assertIn("root.morphAnimatable = true;", handler)


class ControlCenterMorphRuntimeTests(unittest.TestCase):
    """Runs the production component under the Tahoe Quickshell runtime.

    qmltestrunner cannot load the Quickshell plugins this component needs
    (PanelWindow / ScriptModel / TahoeGlassRegion), so the probe is a ShellRoot
    driven by `qs -p`, matching tst_notification_center_stable_rows.qml.
    """

    def _run_probe(self, panel_path: Path, timeout: int = 90) -> subprocess.CompletedProcess:
        local_runner = Path.home() / ".local" / "bin" / "qs"
        runner = str(local_runner) if local_runner.is_file() else shutil.which("qs")
        self.assertIsNotNone(runner, "Tahoe Quickshell runtime is required")

        source = QML_PROBE.read_text(encoding="utf-8").replace(
            'property string panelSource: ""',
            f'property string panelSource: "{panel_path}"',
        )
        with tempfile.TemporaryDirectory(prefix="tahoe-cc-morph-") as tmp:
            probe = Path(tmp) / "shell.qml"
            probe.write_text(source, encoding="utf-8")
            # No QT_QPA_PLATFORM override: PanelWindow is a layer-shell surface
            # and refuses to instantiate under the offscreen platform ("No
            # PanelWindow backend loaded"), so this probe needs the session's
            # real Wayland display — same as tst_notification_center_stable_rows.
            return subprocess.run(
                [runner, "-p", str(probe)],
                cwd=SHELL_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=timeout,
                check=False,
            )

    def test_panel_height_travels_straight_across_a_morph(self) -> None:
        result = self._run_probe(CONTROL_CENTER)
        self.assertIn("CONTROL_CENTER_MORPH_OK", result.stdout, result.stdout)
        self.assertNotIn("CONTROL_CENTER_MORPH_FAIL", result.stdout, result.stdout)


if __name__ == "__main__":
    unittest.main()
