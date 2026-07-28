#!/usr/bin/env python3
"""R17 Dock layout/fullscreen motion source contracts."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = SHELL_ROOT / "components"
REPO_ROOT = SHELL_ROOT.parent


class R17DockLayoutMotionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.dock = (COMPONENTS / "Dock.qml").read_text(encoding="utf-8")
        cls.button = (COMPONENTS / "WindowButton.qml").read_text(encoding="utf-8")
        cls.shelf = (COMPONENTS / "DockMinimizedShelf.qml").read_text(encoding="utf-8")
        cls.preview = (COMPONENTS / "DockMinimizedWindow.qml").read_text(encoding="utf-8")
        cls.topbar = (COMPONENTS / "TopBar.qml").read_text(encoding="utf-8")
        cls.kdl = (REPO_ROOT / "config/niri/tahoe-phase0.kdl").read_text(encoding="utf-8")
        glass_root = REPO_ROOT / "quickshell/src/wayland/tahoe_glass"
        cls.glass_hpp = (glass_root / "qml.hpp").read_text(encoding="utf-8")
        cls.glass_cpp = (glass_root / "qml.cpp").read_text(encoding="utf-8")

    def test_dock_chrome_and_sections_share_eased_width_motion(self) -> None:
        self.assertIn("readonly property real dockChromeTargetWidth", self.dock)
        self.assertIn("width: root.dockChromeTargetWidth", self.dock)
        for section_id in ("pinnedSectionHost", "windowSectionHost", "minimizedSectionHost"):
            section = re.search(
                rf"id:\s*{section_id}.*?Behavior on width\s*\{{.*?\n\s*\}}",
                self.dock,
                re.S,
            )
            self.assertIsNotNone(section, section_id)
            assert section
            self.assertIn("Motion.elementResize", section.group(0))
            self.assertNotIn("SpringAnimation", section.group(0))

        chrome = re.search(r"id:\s*dockChrome.*?transform:\s*Translate", self.dock, re.S)
        self.assertIsNotNone(chrome)
        assert chrome
        self.assertIn("Behavior on width", chrome.group(0))
        self.assertIn("Motion.elementResize", chrome.group(0))
        self.assertNotIn("SpringAnimation", chrome.group(0))
        self.assertIn("regionWidth: Math.round(dockChrome.width)", self.dock)

    def test_pinned_identity_and_rest_slot_move_do_not_replace_wave(self) -> None:
        self.assertIn("readonly property var dockPinnedEntries", self.dock)
        self.assertIn("function buildDockPinnedEntries()", self.dock)
        self.assertIn("pinnedIdForVisualIndex(i, app)", self.dock)
        self.assertIn('objectProp: "modelKey"', self.dock)
        self.assertIn("values: root.dockPinnedEntries", self.dock)
        self.assertIn("readonly property var pinnedApp: modelData ? modelData.app : null", self.dock)
        self.assertNotIn('objectProp: "id"', self.dock)
        self.assertIn("x: root.pinnedRestX(pinnedButton.index)", self.dock)
        self.assertIn("Behavior on x", self.dock)
        self.assertIn("Motion.elementMove(root.settingsService)", self.dock)
        self.assertEqual(self.dock.count("Behavior on magnification"), 1)
        self.assertEqual(self.dock.count("Behavior on pushX"), 1)
        self.assertIn("SmoothedAnimation", self.dock)
        self.assertIn("transform: Translate {\n                                        x: pinnedButton.pushX", self.dock)

    def test_optional_section_spacing_animates_with_section_widths(self) -> None:
        dock_row = re.search(r"Row\s*\{\s*\n\s*id:\s*dockRow.*?\n\s*\}\s*// dockRow", self.dock, re.S)
        self.assertIsNotNone(dock_row)
        assert dock_row
        source = dock_row.group(0)
        self.assertIn("spacing: 0", source)
        self.assertIn("id: windowDividerHost", source)
        self.assertIn("id: windowDividerTrailingSpacer", source)
        self.assertIn("id: windowMinimizedSpacer", source)
        self.assertIn("id: windowSectionTrailingSpacer", source)
        self.assertIn("visible: width > 0", source)
        for item_id in (
            "windowDividerHost",
            "windowDividerTrailingSpacer",
            "windowMinimizedSpacer",
            "windowSectionTrailingSpacer",
        ):
            item = re.search(
                rf"id:\s*{item_id}.*?Behavior on width\s*\{{.*?Motion\.elementResize",
                source,
                re.S,
            )
            self.assertIsNotNone(item, item_id)

    def test_window_slots_and_indicators_animate_on_single_outlets(self) -> None:
        self.assertIn("x: slotXTarget", self.button)
        self.assertIn("width: slotWidthTarget", self.button)
        self.assertIn("Behavior on x", self.button)
        self.assertIn("Behavior on width", self.button)
        self.assertNotIn("onSlotXTargetChanged", self.button)
        self.assertNotIn("onSlotWidthTargetChanged", self.button)
        self.assertEqual(self.button.count("Behavior on magnification"), 1)
        self.assertEqual(self.button.count("Behavior on pushX"), 1)

        indicator = re.search(
            r"anchors\.horizontalCenter:\s*icon\.horizontalCenter.*?MouseArea\s*\{",
            self.button,
            re.S,
        )
        self.assertIsNotNone(indicator)
        assert indicator
        self.assertIn("Behavior on width", indicator.group(0))
        self.assertIn("Behavior on color", indicator.group(0))
        self.assertIn("Motion.elementResize", indicator.group(0))
        self.assertIn("Motion.fadeFast", indicator.group(0))

    def test_window_rectangle_tracks_ancestor_layout_motion(self) -> None:
        delegate_prefix = self.dock.split("delegate: WindowButton {", 1)[1].split(
            "onDockPointerMoved:", 1
        )[0]
        for axis in ("X", "Y"):
            self.assertIn(f"property real dockSceneOffset{axis}: 0", self.button)
            self.assertIn(
                f"onDockSceneOffset{axis}Changed: scheduleDockRectangleUpdate()",
                self.button,
            )
            self.assertIn(
                f"dockSceneOffset{axis}: root.windowSectionSceneOffset{axis}",
                delegate_prefix,
            )

        self.assertIn("property real dockFullscreenOffset: 0", self.button)
        self.assertIn("property bool dockFullscreenActive: false", self.button)
        self.assertIn("function dockRectanglePublishBlocked()", self.button)
        self.assertIn("return root.dockFullscreenActive;", self.button)
        # Must not gate on slide offset — that blocked minimize rects after exit.
        self.assertNotIn("dockFullscreenOffset > 0.5", self.button)
        self.assertIn("updateDockRectangle(true)", self.button)
        self.assertIn("onDockFullscreenOffsetChanged: scheduleDockRectangleUpdate()", self.button)
        self.assertIn("onDockFullscreenActiveChanged:", self.button)
        self.assertIn(
            "dockFullscreenOffset: root.fullscreenTransition * root.dockSurfaceHeight",
            delegate_prefix,
        )
        self.assertIn(
            "dockFullscreenActive: root.fullscreenActive",
            delegate_prefix,
        )
        self.assertIn(
            "- root.dockSlideOffset - root.dockFullscreenOffset",
            self.button,
        )

        scene_x = re.search(
            r"readonly property real windowSectionSceneOffsetX:(?P<body>.*?)\n\s*readonly property real windowSectionSceneOffsetY:",
            self.dock,
            re.S,
        )
        self.assertIsNotNone(scene_x)
        assert scene_x
        for dependency in (
            "dockChrome.x",
            "dockRow.x",
            "windowSectionHost.x",
            "windowViewport.x",
            "windowRow.x",
            "windowViewport.contentX",
        ):
            self.assertIn(dependency, scene_x.group("body"))

        scene_y = re.search(
            r"readonly property real windowSectionSceneOffsetY:(?P<body>.*?)\n\s*// Wave section:",
            self.dock,
            re.S,
        )
        self.assertIsNotNone(scene_y)
        assert scene_y
        for dependency in (
            "dockChrome.y",
            "dockRow.y",
            "windowSectionHost.y",
            "windowViewport.y",
            "windowRow.y",
            "windowViewport.contentY",
        ):
            self.assertIn(dependency, scene_y.group("body"))

    def test_minimized_shelf_has_real_lifecycle_and_displacement(self) -> None:
        self.assertIn("ListView {", self.shelf)
        self.assertIn('objectProp: "modelKey"', self.shelf)
        for transition in ("add", "remove", "move", "displaced"):
            self.assertIn(f"{transition}: Transition", self.shelf)
        self.assertIn('property: "lifecycleOpacity"', self.shelf)
        self.assertIn('property: "lifecycleScale"', self.shelf)
        self.assertIn("visible: hasWindows || opacity > 0.01", self.shelf)
        self.assertIn("scale: hasWindows ? 1 : 0.9", self.shelf)
        self.assertIn("property real lifecycleOpacity: 1", self.preview)
        self.assertIn("property real lifecycleScale: 1", self.preview)
        self.assertIn("scale: lifecycleScale * pressScale", self.preview)
        self.assertIn("opacity: lifecycleOpacity * pressOpacity", self.preview)
        self.assertIn("Behavior on border.color", self.preview)

    def test_unified_hover_label_moves_instead_of_teleporting(self) -> None:
        label = re.search(r"id:\s*dockHoverLabel.*?\n\s*\}\n\s*\}\s*// dockChrome", self.dock, re.S)
        self.assertIsNotNone(label)
        assert label
        source = label.group(0)
        self.assertNotIn("Behavior on x", source)
        self.assertIn("Behavior on y", source)
        self.assertIn("Motion.elementMove", source)
        center_motion = re.search(
            r"Behavior on dockHoverLabelCenterX\s*\{.*?Motion\.elementMove",
            self.dock,
            re.S,
        )
        self.assertIsNotNone(center_motion)

    def test_unified_hover_label_uses_output_bounds_not_dynamic_dock_width(self) -> None:
        label = re.search(r"id:\s*dockHoverLabel.*?\n\s*\}\n\s*\}\s*// dockChrome", self.dock, re.S)
        self.assertIsNotNone(label)
        assert label
        source = label.group(0)

        # The capsule may paint outside dockChrome because it is unclipped. Its
        # width and global bounds therefore belong to the output coordinate
        # space; tying either to the dynamic chrome width elides long titles as
        # pinned/window counts change.
        self.assertIn("Math.max(1, root.width - labelScreenMargin * 2)", source)
        self.assertIn("labelScreenMargin - dockChrome.x", source)
        self.assertIn("root.width - dockChrome.x - width - labelScreenMargin", source)
        self.assertNotIn("dockChrome.width - 12", source)
        self.assertNotIn("Behavior on x", source)

        def capsule_geometry(
            output_width: float,
            chrome_x: float,
            natural_text_width: float,
            center_x: float,
        ) -> tuple[float, float]:
            margin = 6.0
            max_width = max(1.0, output_width - margin * 2.0)
            width = min(max(natural_text_width + 18.0, 48.0), max_width)
            local_min = margin - chrome_x
            local_max = output_width - chrome_x - width - margin
            local_x = max(local_min, min(local_max, center_x - width / 2.0))
            return chrome_x + local_x, width

        # Direct x clamping must stay valid on every animation frame, including
        # fractional chrome positions, overlong text, and pathological outputs.
        for output_width, chrome_x, text_width, center_x in (
            (1366.0, 503.0, 720.0, 12.0),
            (1366.0, 503.5, 720.0, 350.0),
            (320.0, 92.25, 900.0, 130.0),
            (59.0, 7.5, 90.0, 20.0),
        ):
            global_x, width = capsule_geometry(
                output_width, chrome_x, text_width, center_x
            )
            self.assertGreaterEqual(global_x, 6.0)
            self.assertLessEqual(global_x + width, output_width - 6.0)

    def test_dock_replays_compositor_slide_for_each_surface_mapping(self) -> None:
        self.assertIn(
            "Q_PROPERTY(quint64 mappingGeneration READ mappingGeneration "
            "NOTIFY mappingGenerationChanged)",
            self.glass_hpp,
        )
        surface_created = re.search(
            r"void TahoeGlass::waylandSurfaceCreated\(\)\s*\{(?P<body>.*?)\n\}",
            self.glass_cpp,
            re.S,
        )
        self.assertIsNotNone(surface_created)
        assert surface_created
        lifecycle = surface_created.group("body")
        self.assertIn("this->advanceMappingGeneration();", lifecycle)
        self.assertLess(
            lifecycle.index("this->setAvailable(this->surface != nullptr);"),
            lifecycle.index("this->advanceMappingGeneration();"),
            "mapping notification must observe the new protocol surface as available",
        )

        self.assertIn(
            "readonly property real tahoeGlassMappingGeneration: "
            "root.TahoeGlass.mappingGeneration",
            self.dock,
        )
        self.assertIn("onTahoeGlassMappingGenerationChanged:", self.dock)
        self.assertIn("root.replayCompositorSlideForMapping()", self.dock)

        replay = re.search(
            r"function replayCompositorSlideForMapping\(\)\s*\{(?P<body>.*?)\n\s*\}",
            self.dock,
            re.S,
        )
        self.assertIsNotNone(replay)
        assert replay
        body = replay.group("body")
        self.assertIn("root.visible", body)
        self.assertIn("root.compositorSlide", body)
        self.assertIn("root.TahoeGlass.sendTransform(0, root.dockSlideTarget, 1, 1)", body)
        # A remap starts at identity in niri. Replaying as an animation would
        # briefly expose hidden chrome while its input mask is already empty.
        self.assertNotIn("sendTransformTarget", body)

    def test_fullscreen_qml_transitions_keep_intentional_surface_lifecycles(self) -> None:
        for name, source in (("Dock.qml", self.dock), ("TopBar.qml", self.topbar)):
            self.assertIn("property real fullscreenTransition: fullscreenActive ? 1 : 0", source, name)
            self.assertIn("Behavior on fullscreenTransition", source, name)
            self.assertIn("Motion.elementResize(root.settingsService)", source, name)
        self.assertIn("visible: !root.fullscreenActive || dockChrome.opacity > 0.01", self.dock)
        self.assertIn("visible: !root.fullscreenActive", self.topbar)
        self.assertNotIn("visible: !root.fullscreenActive || barSurface.opacity > 0.01", self.topbar)
        self.assertIn("Hard unmap with fullscreen chrome hide", self.topbar)
        self.assertIn("y: root.fullscreenTransition * root.dockSurfaceHeight", self.dock)
        self.assertIn("materialAlpha: 1.0 - root.fullscreenTransition", self.dock)
        self.assertIn("y: -root.fullscreenTransition * root.height", self.topbar)
        self.assertIn("opacity: 1 - root.fullscreenTransition", self.topbar)
        self.assertNotIn('match namespace="^tahoe-dock$"', self.kdl)
        self.assertNotIn('match namespace="^tahoe-topbar$"', self.kdl)

    def test_dock_menu_keeps_existing_pointer_origin_rule(self) -> None:
        self.assertIn('match namespace="^tahoe-dock-app-menu$"', self.kdl)
        self.assertIn('match namespace="^tahoe-dock-window-menu$"', self.kdl)
        menu_block = re.search(
            r"layer-rule\s*\{(?P<body>.*?tahoe-dock-app-menu.*?origin\s+\"pointer\".*?)\n\}",
            self.kdl,
            re.S,
        )
        self.assertIsNotNone(menu_block)


if __name__ == "__main__":
    unittest.main()
