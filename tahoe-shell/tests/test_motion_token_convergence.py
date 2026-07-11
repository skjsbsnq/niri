from __future__ import annotations

import importlib.util
import re
import unittest
from pathlib import Path


SHELL_ROOT = Path(__file__).resolve().parents[1]
COMPONENTS_ROOT = SHELL_ROOT / "components"
MOTION_JS = COMPONENTS_ROOT / "Motion.js"
DESKTOP_SETTINGS_QML = SHELL_ROOT / "services" / "DesktopSettings.qml"
NIRI_SETTINGS_TOOL = SHELL_ROOT / "services" / "niri_settings_tool.py"

spec = importlib.util.spec_from_file_location("niri_settings_tool", NIRI_SETTINGS_TOOL)
assert spec and spec.loader
niri_settings_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(niri_settings_tool)


def qml_files() -> list[Path]:
    return sorted(COMPONENTS_ROOT.rglob("*.qml"))


class MotionTokenConvergenceTests(unittest.TestCase):
    def test_qml_components_do_not_inline_out_cubic_easing(self) -> None:
        offenders = [
            str(path.relative_to(SHELL_ROOT))
            for path in qml_files()
            if "Easing.OutCubic" in path.read_text(encoding="utf-8")
        ]

        self.assertEqual(offenders, [])

    def test_no_private_motion_token_files_were_added(self) -> None:
        token_like_files = sorted(
            path.relative_to(COMPONENTS_ROOT).as_posix()
            for path in COMPONENTS_ROOT.rglob("*.js")
            if re.search(r"(motion|animation|easing|transition)", path.name, re.IGNORECASE)
        )

        self.assertEqual(token_like_files, ["DynamicIslandMotion.js", "Motion.js"])

    def test_qml_motion_profiles_match_kdl_profile_names(self) -> None:
        motion_text = MOTION_JS.read_text(encoding="utf-8")
        desktop_text = DESKTOP_SETTINGS_QML.read_text(encoding="utf-8")
        profile_names = re.findall(r'"(fast|balanced|liquid|reduced)"\s*:', motion_text)

        self.assertEqual(set(profile_names), set(niri_settings_tool.MOTION_PROFILE_NAMES))
        self.assertIn('property string motionProfile: "balanced"', desktop_text)
        self.assertIn("function setMotionProfile(profile)", desktop_text)

    def test_motion_exports_tahoe_motion_2_spring_vocabulary(self) -> None:
        text = MOTION_JS.read_text(encoding="utf-8")

        expected = {
            "springSnappy": ("4.2", "0.30", "damping-ratio=0.88 stiffness=500"),
            "springSmooth": ("3.0", "0.40", "damping-ratio=1.0 stiffness=250"),
            "springPanel": ("2.5", "0.28", "damping-ratio=0.85 stiffness=160"),
            "springBouncy": ("2.5", "0.22", "damping-ratio=0.70 stiffness=160"),
        }
        for token, (spring, damping, niri_params) in expected.items():
            block = re.search(rf"var {token} = \{{(.*?)\}};", text, re.S)
            self.assertIsNotNone(block, f"missing spring token {token}")
            assert block
            body = block.group(1)
            self.assertIn(f"spring: {spring}", body, token)
            self.assertIn(f"damping: {damping}", body, token)
            # The niri-side KDL annotation must stay in sync with the QML group.
            self.assertIn(niri_params, body, token)

    def test_motion_exports_press_tokens_as_single_outlet(self) -> None:
        text = MOTION_JS.read_text(encoding="utf-8")

        self.assertIn("var pressDuration = 120;", text)
        self.assertIn("var pressScale = 0.96;", text)
        self.assertIn("var pressEasing = QtQuick.Easing.OutQuad;", text)
        self.assertIn('return normalizedProfileName(settingsService) === "reduced";', text)
        self.assertIn("function pressDurationFor(settingsService)", text)
        self.assertIn("function pressScaleFor(settingsService, pressed)", text)

    def test_motion_exports_menu_flash_tokens(self) -> None:
        text = MOTION_JS.read_text(encoding="utf-8")

        self.assertIn("var menuFlashInterval = 70;", text)
        self.assertIn("var menuFlashCount = 2;", text)

    def test_motion_exports_dock_magnification_tokens(self) -> None:
        text = MOTION_JS.read_text(encoding="utf-8")

        self.assertIn("var dockMagPeak = 1.55;", text)
        self.assertIn("var dockMagRangeIcons = 2.5;", text)
        self.assertIn("var dockMagSpring = {", text)
        self.assertIn("function dockCosineScale(distancePx, iconSizePx)", text)
        # Cosine-bell formula must stay the single outlet.
        self.assertIn("Math.cos(Math.PI * d / (2 * R))", text)
        self.assertIn("(dockMagPeak - 1.0) * c * c", text)
        block = re.search(r"var dockMagSpring = \{(.*?)\};", text, re.S)
        self.assertIsNotNone(block)
        assert block
        body = block.group(1)
        self.assertIn("spring: 3.2", body)
        self.assertIn("damping: 0.42", body)
        self.assertIn("epsilon: 0.001", body)

    def test_motion_exports_dock_launch_and_autohide_tokens(self) -> None:
        text = MOTION_JS.read_text(encoding="utf-8")

        self.assertIn("var dockLaunchBounceHeightFactor = 0.7;", text)
        self.assertIn("var dockLaunchBouncePeriodMs = 550;", text)
        self.assertIn("var dockLaunchBounceTimeoutMs = 10000;", text)
        self.assertIn("var dockRevealDebounceMs = 40;", text)
        self.assertIn("var dockAutohideSlidePx = 88;", text)
        self.assertIn("function dockLaunchBounceHeight(iconSizePx)", text)
        self.assertIn("dockLaunchBounceHeightFactor", text)

    def test_dock_uses_analytical_cosine_wave_and_unified_label(self) -> None:
        dock = (COMPONENTS_ROOT / "Dock.qml").read_text(encoding="utf-8")
        window_button = (COMPONENTS_ROOT / "WindowButton.qml").read_text(encoding="utf-8")

        # Cosine-bell via Motion token; no legacy linear triangle.
        self.assertIn("Motion.dockCosineScale", dock)
        self.assertIn("function pinnedScaleAt(index)", dock)
        self.assertIn("function pinnedItemXAt(index)", dock)
        self.assertIn("function pinnedItemWidthAt(index)", dock)
        self.assertIn("function windowScaleAt(index)", dock)
        self.assertNotIn("1 - distance / 135", dock)
        self.assertNotIn("influence * 0.34", dock)

        # Analytical push: explicit x/width targets on pinned delegates, not Row auto-layout.
        self.assertIn("readonly property real xTarget: root.pinnedItemXAt(pinnedButton.index)", dock)
        self.assertIn("readonly property real widthTarget: root.pinnedItemWidthAt(pinnedButton.index)", dock)
        self.assertIn("readonly property real magnificationTarget: root.pinnedScaleAt(pinnedButton.index)", dock)
        self.assertIn("id: pinnedRow", dock)
        # Pinned container is Item (explicit x), not Row.
        self.assertIn("Item {\n                        id: pinnedRow", dock)

        # Icon base 48 (T08-fix from T07's 56) + exclusiveZone/surface recompute.
        self.assertIn("readonly property int dockIconSize: 48", dock)
        self.assertIn("exclusiveZone: 100", dock)
        self.assertIn("height: root.dockSurfaceHeight", dock)
        self.assertIn("dockSlideDistance", dock)
        self.assertIn("function pinnedWaveLeftExtra()", dock)
        self.assertIn("function dockWaveSurfaceBias()", dock)
        self.assertIn("function syncPinnedViewportToCursor()", dock)
        # T08-fix4: surface stays rest-width / centered (no live wave expansion).
        self.assertIn("anchors.horizontalCenter: parent.horizontalCenter", dock)
        self.assertNotIn("return (rightExtra - leftExtra) / 2;", dock)

        # Unified hover label: one capsule, 13px, no y-slide Behavior.
        self.assertIn("id: dockHoverLabel", dock)
        self.assertIn("function showDockHoverLabel", dock)
        self.assertIn("font.pixelSize: 13", dock)
        self.assertEqual(dock.count("id: hoverLabel"), 0)
        self.assertEqual(dock.count("id: toolLabel"), 0)
        self.assertEqual(dock.count("id: windowHoverLabel"), 0)
        # No y Behavior on the unified label (instant appear).
        hover_block = re.search(
            r"id: dockHoverLabel.*?Behavior on opacity \{.*?\}",
            dock,
            re.S,
        )
        self.assertIsNotNone(hover_block)
        assert hover_block
        self.assertNotIn("Behavior on y", hover_block.group(0))

        # useSpring dual branch still present for mag + bounce via explicit
        # SpringAnimation / NumberAnimation (dual Behavior{} is unsupported).
        self.assertIn("root.useSpring", dock)
        self.assertIn("Motion.dockMagSpring", dock)
        self.assertIn("id: magSpring", dock)
        self.assertIn("id: magEase", dock)
        self.assertIn("id: bounceSpring", dock)
        self.assertIn("Motion.dockMagSpring", window_button)
        self.assertIn("magnificationTarget", window_button)
        self.assertIn("slotWidthTarget", window_button)
        self.assertIn("slotXTarget", window_button)
        self.assertIn("width: showTitle ? 132 : 60", window_button)
        # Window half analytical push helpers (T08-fix2).
        self.assertIn("function windowItemWidthAt(index)", dock)
        self.assertIn("function windowItemXAt(index)", dock)
        self.assertIn("function windowWaveContentWidth()", dock)
        self.assertIn("function syncWindowViewportToCursor()", dock)
        # Outer section widths are rest-sized (T08-fix4); wave only inside Flickable.
        self.assertIn("readonly property int windowViewportWidth: hasNonMinimizedWindows", dock)
        self.assertNotIn("windowDisplayedWidth", dock)
        # T08-fix3: scale from icon feet so mag does not float icons mid-air.
        self.assertIn("transformOrigin: Item.Bottom", dock)
        self.assertIn("transformOrigin: Item.Bottom", window_button)
        self.assertNotIn("transformOrigin: Item.Center", dock)
        self.assertNotIn("transformOrigin: Item.Center", window_button)
        # T08-fix4: edge reveal debounce must not restart on every move.
        self.assertIn("if (!dockRevealDebounceTimer.running)", dock)
        self.assertNotIn("dockRevealDebounceTimer.restart()", dock)
        # No dual Behavior on the same property (T00 interceptor 待办 closed).
        self.assertEqual(dock.count("Behavior on magnification"), 0)
        self.assertEqual(dock.count("Behavior on bounceOffset"), 0)
        self.assertEqual(window_button.count("Behavior on magnification"), 0)
        self.assertEqual(window_button.count("Behavior on bounceOffset"), 0)

    def test_dock_launch_bounce_and_autohide_spring(self) -> None:
        dock = (COMPONENTS_ROOT / "Dock.qml").read_text(encoding="utf-8")
        window_button = (COMPONENTS_ROOT / "WindowButton.qml").read_text(encoding="utf-8")

        # Launching state machine: start on cold launch, stop on running / timeout.
        self.assertIn("property bool launching: false", dock)
        self.assertIn("function startLaunchBounce()", dock)
        self.assertIn("function stopLaunchBounce()", dock)
        self.assertIn("id: launchBounceLoop", dock)
        self.assertIn("id: launchBounceTimeout", dock)
        self.assertIn("Motion.dockLaunchBounceTimeoutMs", dock)
        self.assertIn("Motion.dockLaunchBounceHeight(root.dockIconSize)", dock)
        self.assertIn("Motion.dockLaunchBouncePeriodMs", dock)
        self.assertIn("Easing.InQuad", dock)
        self.assertIn("Easing.OutQuad", dock)
        self.assertIn("loops: Animation.Infinite", dock)
        # Re-click while launching does not stack; running apps get single bounce.
        self.assertIn("if (!pinnedButton.running && !pinnedButton.launching)", dock)
        self.assertIn("pinnedButton.startLaunchBounce()", dock)
        self.assertIn("onRunningChanged", dock)
        self.assertIn("pinnedButton.stopLaunchBounce()", dock)

        # Autohide: springSmooth dual branch + 150ms reveal debounce; no Behavior interceptor.
        self.assertIn("Motion.springSmooth", dock)
        self.assertIn("id: dockSlideSpring", dock)
        self.assertIn("id: dockSlideEase", dock)
        self.assertIn("function animateDockSlideTo(value)", dock)
        self.assertIn("id: dockRevealDebounceTimer", dock)
        self.assertIn("Motion.dockRevealDebounceMs", dock)
        self.assertIn("Motion.dockAutohideSlidePx", dock)
        self.assertIn("dockSlideDistance", dock)
        self.assertEqual(dock.count("Behavior on dockSlideOffset"), 0)
        # T08-fix: glass stays active during slide-out (no immediate dockGlassActive=false).
        self.assertIn("onDockVisibleHeightChanged", dock)
        self.assertNotIn("dockGlassActive = false;\n            dockVisualHidden = true", dock)

        # Running indicator 2px glow (sibling halo, no GraphicalEffects).
        self.assertIn("id: runningDot", dock)
        self.assertIn("parent.width + 4", dock)
        self.assertIn("parent.width + 4", window_button)

    def test_phase_b_press_feedback_uses_motion_single_outlet(self) -> None:
        # T06 moved menu press feedback into the shared MenuRow.qml outlet.
        required_counts = {
            "TopBar.qml": 11,
            "Tray.qml": 1,
            "Dock.qml": 2,
            "WindowButton.qml": 1,
            "DockMinimizedWindow.qml": 1,
            "ControlCenter.qml": 8,
            "Spotlight.qml": 2,
            "Launchpad.qml": 2,
            "MenuRow.qml": 1,
            "settings/controls/TahoeButton.qml": 1,
            "settings/controls/TahoeListRow.qml": 1,
            "settings/controls/TahoeSidebarButton.qml": 1,
            "settings/controls/TahoeSegmented.qml": 1,
        }

        for relative, expected_count in required_counts.items():
            with self.subTest(component=relative):
                text = (COMPONENTS_ROOT / relative).read_text(encoding="utf-8")
                self.assertEqual(text.count("Motion.pressScaleFor"), expected_count)
                self.assertIn("Motion.pressDurationFor", text)

        # Parent menus must not re-introduce private pressScale paths.
        for relative in (
            "MenuPopup.qml",
            "AppMenuPopup.qml",
            "TrayMenu.qml",
            "DockAppMenu.qml",
            "DockWindowMenu.qml",
            "ProcessMenu.qml",
        ):
            with self.subTest(parent_menu=relative):
                text = (COMPONENTS_ROOT / relative).read_text(encoding="utf-8")
                self.assertEqual(text.count("Motion.pressScaleFor"), 0)
                self.assertNotIn("component MenuRow", text)

    def test_shared_menu_row_macos_signatures(self) -> None:
        row = (COMPONENTS_ROOT / "MenuRow.qml").read_text(encoding="utf-8")
        separator = (COMPONENTS_ROOT / "MenuSeparator.qml").read_text(encoding="utf-8")

        self.assertIn("radius: 6", row)
        self.assertIn("header ? 22 : 26", row)
        self.assertIn("font.pixelSize: row.header ? 11 : 13", row)
        self.assertIn('darkMode ? "#0a84ff" : "#007aff"', row)
        self.assertIn("Motion.menuFlashInterval", row)
        self.assertIn("Motion.menuFlashCount", row)
        self.assertIn("function requestActivate()", row)
        self.assertIn("Motion.reducedMotion(settingsService)", row)
        self.assertIn('"#1a000000"', row)
        self.assertIn('"#1a000000"', separator)
        self.assertIn("anchors.leftMargin: 10", separator)
        self.assertIn("anchors.rightMargin: 10", separator)

        # All six menus must consume the shared row (no inline component MenuRow).
        consumers = (
            "MenuPopup.qml",
            "AppMenuPopup.qml",
            "TrayMenu.qml",
            "DockAppMenu.qml",
            "DockWindowMenu.qml",
            "ProcessMenu.qml",
        )
        for relative in consumers:
            with self.subTest(consumer=relative):
                text = (COMPONENTS_ROOT / relative).read_text(encoding="utf-8")
                self.assertIn("MenuRow {", text)
                self.assertNotIn("component MenuRow", text)
                self.assertNotIn("component MenuEntry", text)
                self.assertNotIn("component NativeMenuRow", text)
                # Dark mode must be wired through so accent/text resolve correctly.
                self.assertIn("property bool darkMode", text)
                self.assertIn("darkMode: root.darkMode", text)

    def test_glass_panel_press_drives_material_interaction(self) -> None:
        text = (COMPONENTS_ROOT / "GlassPanel.qml").read_text(encoding="utf-8")

        self.assertIn("property bool pressInteractionEnabled: true", text)
        self.assertIn("PointHandler {", text)
        self.assertIn("target: null", text)
        self.assertIn("Math.max(root.interaction, pressHandler.active ? 1 : 0)", text)

    def test_topbar_hover_capsules_do_not_use_outline_token(self) -> None:
        text = (COMPONENTS_ROOT / "TopBar.qml").read_text(encoding="utf-8")

        self.assertNotIn("buttonBorder", text)


if __name__ == "__main__":
    unittest.main()
