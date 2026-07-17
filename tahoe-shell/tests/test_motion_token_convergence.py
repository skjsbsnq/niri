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

        self.assertIn("var dockMagPeak = 1.62;", text)
        self.assertIn("var dockMagFollowMs = 170;", text)
        self.assertIn("var dockMagRangeIcons = 3.2;", text)
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
        self.assertIn("damping: 0.52", body)
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

    def test_motion_exports_dock_click_bounce_tokens(self) -> None:
        text = MOTION_JS.read_text(encoding="utf-8")

        self.assertIn("var dockClickBounceHeightPx = 14;", text)
        self.assertIn("var dockClickBounceShelfHeightPx = 8;", text)
        self.assertIn("var dockClickBounceUpMs = 90;", text)
        self.assertIn("var dockClickBounceDownMs = 220;", text)

    def test_dock_click_bounce_sites_use_tokens(self) -> None:
        # R01 (#74/#75): all three bounce sites share one token set — no
        # per-site magic numbers, animated up leg, spring/ease down leg.
        components = MOTION_JS.parent
        for name in ("Dock.qml", "WindowButton.qml", "DockMinimizedWindow.qml"):
            text = (components / name).read_text(encoding="utf-8")
            self.assertIn("Motion.dockClickBounceUpMs", text, name)
            self.assertIn("Motion.dockClickBounceDownMs", text, name)
            self.assertNotIn("bounceOffset = 14", text, name)
            self.assertNotIn("bounceOffset = 8", text, name)
        dock = (components / "Dock.qml").read_text(encoding="utf-8")
        window_button = (components / "WindowButton.qml").read_text(encoding="utf-8")
        shelf_window = (components / "DockMinimizedWindow.qml").read_text(encoding="utf-8")
        self.assertIn("Motion.dockClickBounceHeightPx", dock)
        self.assertIn("Motion.dockClickBounceHeightPx", window_button)
        self.assertIn("Motion.dockClickBounceShelfHeightPx", shelf_window)

    def test_motion_exports_toast_stack_tokens(self) -> None:
        text = MOTION_JS.read_text(encoding="utf-8")

        self.assertIn("var toastStackMaxDefault = 3;", text)
        self.assertIn("var toastStackYStep = 8;", text)
        self.assertIn("var toastStackScaleStep = 0.04;", text)
        self.assertIn("var toastEnterOffsetPx = 60;", text)
        self.assertIn("var toastSwipeDismissPx = 96;", text)
        self.assertIn("var toastClearStaggerMs = 30;", text)
        self.assertIn("var toastClearStaggerBudgetMs = 450;", text)
        self.assertIn("var toastClearStaggerMaxItems = 40;", text)
        self.assertIn("function toastStackScaleForIndex(stackIndex)", text)
        self.assertIn("function toastStackYForIndex(stackIndex)", text)
        self.assertIn("function toastClearStaggerDelay(index, total)", text)

    def test_notification_toast_stack_and_swipe(self) -> None:
        toast = (COMPONENTS_ROOT / "NotificationToast.qml").read_text(encoding="utf-8")
        center = (COMPONENTS_ROOT / "NotificationCenter.qml").read_text(encoding="utf-8")
        service = (SHELL_ROOT / "services" / "Notifications.qml").read_text(encoding="utf-8")
        desktop = DESKTOP_SETTINGS_QML.read_text(encoding="utf-8")

        # DesktopSettings field for stack max.
        self.assertIn("property int notificationToastStackMax: 3", desktop)
        self.assertIn("function setNotificationToastStackMax(value)", desktop)
        self.assertIn("readonly property int notificationToastStackMax", desktop)

        # Service: multi-card stack + visible-only expire + grouping.
        self.assertIn("function visibleStack(maxCount)", service)
        self.assertIn("function groupedHistory()", service)
        self.assertIn("property var expireMap", service)
        self.assertIn("function armSoonestExpire()", service)
        self.assertIn("function rearmVisibleExpires()", service)
        self.assertIn("function scheduleExpire(id, expireMs)", service)
        self.assertIn("root.rearmVisibleExpires()", service)

        # Toast: 3 fixed slots, springPanel enter (useSpring dual branch), swipe.
        self.assertIn("id: stackSlot0", toast)
        self.assertIn("id: stackSlot1", toast)
        self.assertIn("id: stackSlot2", toast)
        self.assertIn("Motion.springPanel", toast)
        self.assertIn("function animateEnterTo(value)", toast)
        self.assertIn("root.useSpring && !Motion.reducedMotion", toast)
        self.assertIn("IslandMotion.swipeEnterThreshold", toast)
        self.assertIn("Motion.toastSwipeDismissPx", toast)
        self.assertIn("Motion.toastStackScaleForIndex", toast)
        self.assertIn("Motion.toastStackYForIndex", toast)
        self.assertIn("Motion.toastHoverLiftPx", toast)
        # Glass region geometry must not use SpringAnimation.
        glass_block = re.search(
            r"GlassPanel \{\s*id: glass.*?MouseArea \{\s*id: swipeArea",
            toast,
            re.S,
        )
        self.assertIsNotNone(glass_block, "expected glass panel block")
        assert glass_block
        self.assertNotIn("SpringAnimation", glass_block.group(0))
        # Enter spring targets content enterX, not glass x/y/width/height.
        self.assertIn('property: "enterX"', toast)
        self.assertIn('property: "contentScale"', toast)

        # Center: app grouping + clear-all stagger budget + post-fly hold.
        self.assertIn("groupedHistory", center)
        self.assertIn("function startClearAll()", center)
        self.assertIn("Motion.toastClearStaggerBudgetMs", center)
        self.assertIn("Motion.toastClearStaggerMaxItems", center)
        self.assertIn("id: clearFinishHold", center)
        self.assertIn("component AppGroup", center)
        # Toast: promotion must not re-enter (prevStackIds / isNewlyAppearedId).
        self.assertIn("function isNewlyAppearedId", toast)
        self.assertIn("property var prevStackIds", toast)
        self.assertIn("Behavior on stackY", toast)
        self.assertNotIn("Behavior on y {", toast)

    def test_motion_exports_control_center_feel_tokens(self) -> None:
        text = MOTION_JS.read_text(encoding="utf-8")

        self.assertIn("var ccPanelWidth = 330;", text)
        self.assertIn("var ccTilePressScale = 0.97;", text)
        self.assertIn("var ccSliderKnobDragScale = 1.15;", text)
        self.assertIn("var ccToggleBounceMs = 200;", text)
        self.assertIn("var ccToggleColorMs = 200;", text)

    def test_control_center_dechrome_and_control_feel(self) -> None:
        cc = (COMPONENTS_ROOT / "ControlCenter.qml").read_text(encoding="utf-8")

        # T10: no title chrome / close X; width token 330.
        self.assertIn("Motion.ccPanelWidth", cc)
        self.assertNotIn('text: "控制中心"', cc)
        self.assertNotIn("id: closeButton", cc)
        self.assertNotIn("onClicked: root.closeRequested()", cc)

        # Slider white circular knob + drag scale 1.15.
        self.assertIn("id: knob", cc)
        self.assertIn("id: knobShadow", cc)
        self.assertIn("Motion.ccSliderKnobDragScale", cc)
        self.assertIn('color: "#ffffff"', cc)

        # Tile hover/press feel via ccTilePressScale (not generic pressScale 0.96).
        self.assertIn("Motion.ccTilePressScale", cc)
        self.assertIn("tileFillHover", cc)
        self.assertIn("tileFillPressed", cc)

        # ToggleCircle bounce 1→0.9→1 + ColorAnimation token.
        self.assertIn("id: toggleBounce", cc)
        self.assertIn("bounceScale", cc)
        self.assertIn("Motion.ccToggleBounceMs", cc)
        self.assertIn("Motion.ccToggleColorMs", cc)
        self.assertIn("SequentialAnimation", cc)

        # Glass region height still uses eased NumberAnimation only.
        self.assertNotIn("SpringAnimation", cc)
        self.assertIn("emphasizedDecel", cc)

    def test_motion_exports_control_center_morph_tokens(self) -> None:
        text = MOTION_JS.read_text(encoding="utf-8")

        self.assertIn("var ccMorphDurationMs = 280;", text)
        self.assertIn("var ccMorphSiblingOffsetPx = 8;", text)
        self.assertIn("var ccMorphListMaxHeight = 220;", text)

    def test_dynamic_island_morph_spring_tokens_and_wiring(self) -> None:
        motion = (COMPONENTS_ROOT / "DynamicIslandMotion.js").read_text(encoding="utf-8")
        overlay = (COMPONENTS_ROOT / "DynamicIslandOverlay.qml").read_text(encoding="utf-8")
        shell = (SHELL_ROOT / "shell.qml").read_text(encoding="utf-8")
        topbar = (COMPONENTS_ROOT / "TopBar.qml").read_text(encoding="utf-8")
        clock = (COMPONENTS_ROOT / "DynamicIslandRestingClockView.qml").read_text(encoding="utf-8")

        # T19: V2 geometry/content tokens; no whole-scene scale spring.
        self.assertNotIn("overlayContentSpring", motion)
        self.assertNotIn("overlayContentEnterScale", motion)
        self.assertIn("var v2CompactToExpandedMs = 280", motion)
        self.assertIn("var v2ContentEnterMs = 170", motion)
        self.assertIn("function contentEnterMs", motion)
        self.assertIn("OutCubic", motion)
        # Chip motion tokens remain defined for historical timing; T12 deleted the chip UI.
        self.assertNotIn("chipColorDuration", motion)
        self.assertNotIn("chipScaleDuration", motion)
        self.assertNotIn("chipContentDuration", motion)
        self.assertFalse((COMPONENTS_ROOT / "DynamicIslandChip.qml").is_file())

        # T11: V2 radius caps expanded (never height/2 ellipse); glass geometry
        # Behaviors remain NumberAnimation only.
        self.assertIn("v2RadiusExpandedMax", overlay)
        self.assertIn("v2RadiusCompactClock", overlay)
        self.assertNotIn("return h / 2", overlay)
        self.assertIn("property bool useSpring", overlay)
        # V2: whole-scene contentScale 0.9→1 removed (sinking text on collapse).
        self.assertNotIn("contentScaleSpring", overlay)
        self.assertIn("scale: 1.0", overlay)
        # No SpringAnimation instances on island geometry/content (comment may mention ban).
        self.assertEqual(overlay.count("SpringAnimation {"), 0)
        # Swipe IPC path still wired (debug + settle).
        self.assertIn("beginSwipe", overlay)
        self.assertIn("advanceSwipe", overlay)
        self.assertIn("resolveSwipe", overlay)
        self.assertIn("cancelSwipe", overlay)

        # Glass geometry: no SpringAnimation on islandSurface width/height/x/radius.
        # Explicit comment guard for glass region.
        self.assertIn("Geometry → TahoeGlassRegion", overlay)
        self.assertIn("eased NumberAnimation only", overlay)
        # V2 surface fill/stroke from SettingsTheme; single pill region.
        self.assertIn("Theme.islandSurfaceFill", overlay)
        self.assertIn("strokeWidth: 1", overlay)
        self.assertIn("v2CompactTopInset", overlay)
        self.assertIn("v2ScreenMargin", overlay)

        # shell forwards useSpring + settingsService.
        self.assertIn("DynamicIslandOverlay", shell)
        self.assertIn("useSpring: shell.useSpring", shell)
        self.assertIn("settingsService: desktopSettings", shell)

        # T12: resting clock + stable TopBar reserve; chip path removed.
        self.assertIn("weekdayText", clock)
        self.assertIn("v2ClockHeight", clock)
        self.assertIn("centerReserveWidth: IslandMotion.v2CompactMediaWidthMax", topbar)
        self.assertIn("hoverExpandDelayMs", topbar)
        self.assertIn("restingClockTargetWidth", overlay)
        self.assertIn("clockWeekdayText", overlay)
        content = (COMPONENTS_ROOT / "DynamicIslandContent.qml").read_text(encoding="utf-8")
        self.assertIn("DynamicIslandRestingClockView", content)

    def test_control_center_module_morph_expand(self) -> None:
        cc = (COMPONENTS_ROOT / "ControlCenter.qml").read_text(encoding="utf-8")

        # State machine + open/close helpers.
        self.assertIn('property string expandedModule: ""', cc)
        self.assertIn("function openModule(name)", cc)
        self.assertIn("function closeModule()", cc)
        self.assertIn('root.openModule("wifi")', cc)
        self.assertIn('root.openModule("bluetooth")', cc)

        # Morph panel reuses Controls list channels only.
        self.assertIn("controlsService.wifiNetworks", cc)
        self.assertIn("controlsService.bluetoothDeviceEntries", cc)
        self.assertIn("component ModuleMorphPanel", cc)
        self.assertIn("onBackRequested", cc)
        self.assertIn("rescanWifi", cc)
        self.assertIn("connectWifi", cc)
        self.assertIn("connectBluetoothDevice", cc)
        self.assertIn("pairBluetoothDevice", cc)

        # Morph height is eased on morphHost only; panel.height has no Behavior
        # (avoids content stretch bounce). Never Spring on glass geometry.
        self.assertIn("Motion.ccMorphDurationMs", cc)
        self.assertIn("Motion.ccMorphSiblingOffsetPx", cc)
        self.assertIn("Motion.ccMorphListMaxHeight", cc)
        self.assertIn("emphasizedDecel", cc)
        self.assertNotIn("SpringAnimation", cc)
        self.assertIn("Behavior on Layout.preferredHeight", cc)
        self.assertNotIn("Behavior on height", cc)
        # content ColumnLayout is top-anchored (not fill) to avoid stretch bounce.
        self.assertIn("id: content", cc)
        self.assertIn("anchors.top: parent.top", cc)
        self.assertIn("anchors.left: parent.left", cc)
        self.assertIn("anchors.right: parent.right", cc)
        content_block = re.search(
            r"ColumnLayout \{\s*id: content.*?// ---- Morph host",
            cc,
            re.S,
        )
        self.assertIsNotNone(content_block)
        assert content_block
        self.assertNotIn("anchors.fill", content_block.group(0))

        # Empty / unavailable placeholders.
        self.assertIn("Wi-Fi 服务不可用", cc)
        self.assertIn("Wi-Fi 已关闭", cc)
        self.assertIn("未发现网络", cc)
        self.assertIn("蓝牙不可用", cc)
        self.assertIn("蓝牙已关闭", cc)
        self.assertIn("附近暂无设备", cc)

        # Closing panel clears morph state (no layout residue).
        self.assertIn("onOpenChanged", cc)
        self.assertIn('root.expandedModule = ""', cc)
        # Sibling stack collapses only while morph-expanded (-1 = auto otherwise).
        self.assertIn("Layout.preferredHeight: root.moduleExpanded ? 0 : -1", cc)
        self.assertIn("Layout.maximumHeight: root.moduleExpanded ? 0 : -1", cc)

    def test_dock_uses_analytical_cosine_wave_and_unified_label(self) -> None:
        dock = (COMPONENTS_ROOT / "Dock.qml").read_text(encoding="utf-8")
        window_button = (COMPONENTS_ROOT / "WindowButton.qml").read_text(encoding="utf-8")

        # Cosine-bell via Motion token; no legacy linear triangle.
        self.assertIn("Motion.dockCosineScale", dock)
        self.assertIn("function pinnedScaleAt(index)", dock)
        self.assertIn("function pinnedRestX(index)", dock)
        self.assertIn("function pinnedPushXAt(index)", dock)
        self.assertIn("function windowScaleAt(index)", dock)
        self.assertNotIn("1 - distance / 135", dock)
        self.assertNotIn("influence * 0.34", dock)

        # T08-fix8/9: rest slots + visual pushX; fix9 = SmoothedAnimation follow.
        self.assertIn("root.pinnedScaleAt(pinnedButton.index)", dock)
        self.assertIn("root.pinnedPushXAt(pinnedButton.index)", dock)
        self.assertIn("var _w = root.pinnedWave;", dock)
        self.assertIn("SmoothedAnimation", dock)
        self.assertIn("SmoothedAnimation", window_button)
        self.assertIn("velocity: -1", dock)
        self.assertIn("velocity: -1", window_button)
        self.assertIn("function computeSectionWave(", dock)
        # Must NOT zero scales to fit host (that killed the wave).
        self.assertNotIn("scales[i] = 1.0;", dock)
        self.assertIn("Cosine scales stay FULL strength", dock)
        self.assertIn("x: root.pinnedRestX(pinnedButton.index)", dock)
        self.assertIn("width: root.dockPinnedButtonWidth", dock)
        self.assertIn("id: pinnedRow", dock)
        self.assertIn("Item {\n                        id: pinnedRow", dock)

        # Icon base 48 (T08-fix from T07's 56) + exclusiveZone/surface recompute.
        self.assertIn("readonly property int dockIconSize: 48", dock)
        self.assertIn("exclusiveZone: 100", dock)
        self.assertIn("glassClip: true", dock)
        self.assertNotIn("glassClip: false", dock)
        self.assertIn("dockMagHeadroom", dock)
        self.assertIn("Motion.dockMagFollowMs", dock)
        self.assertIn("height: root.dockSurfaceHeight", dock)
        self.assertIn("dockSlideDistance", dock)
        self.assertIn("function pinnedWaveLeftExtra()", dock)
        self.assertIn("function dockWaveSurfaceBias()", dock)
        # Glass is rest-centered; wave extras are always 0 (no bar growth).
        self.assertIn("readonly property real dockWaveLeftExtraPx: 0", dock)
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

        # Click bounce still uses dual-branch spring/ease; wave mag/push do NOT
        # (T08-fix8: direct bind — spring restart every move caused jitter).
        self.assertIn("root.useSpring", dock)
        self.assertIn("id: bounceSpring", dock)
        self.assertNotIn("id: magSpring", dock)
        self.assertNotIn("id: pushSpring", dock)
        self.assertIn("magnificationTarget", window_button)
        self.assertIn("slotWidthTarget", window_button)
        self.assertIn("slotXTarget", window_button)
        self.assertIn("width: slotWidthTarget", window_button)
        self.assertIn("x: slotXTarget", window_button)
        # T08-fix8: fixed glass + fit-in-section visual wave (rest slots + pushX).
        self.assertIn("function computeSectionWave(", dock)
        self.assertIn("function pinnedPushXAt(index)", dock)
        self.assertIn("function windowPushXAt(index)", dock)
        self.assertIn("function pinnedClampRight()", dock)
        self.assertIn("readonly property var pinnedWave:", dock)
        self.assertIn("readonly property var windowWave:", dock)
        self.assertIn("id: pinnedSectionHost", dock)
        self.assertIn("id: windowSectionHost", dock)
        self.assertIn("pushXTarget", dock)
        self.assertIn("pushXTarget", window_button)
        self.assertIn("property real pushX: pushXTarget", window_button)
        self.assertIn("Motion.dockMagFollowMs", window_button)
        # Glass never grows with wave extras.
        self.assertIn("readonly property real dockWaveLeftExtraPx: 0", dock)
        self.assertIn("readonly property real dockWaveRightExtraPx: 0", dock)
        self.assertIn("anchors.horizontalCenter: parent.horizontalCenter", dock)
        self.assertNotIn("dockRestSurfaceX - root.dockWaveLeftExtraPx", dock)
        # Flickable contentWidth is rest-only; sections hard-clip.
        self.assertIn("contentWidth: root.pinnedContentWidth", dock)
        self.assertIn("contentWidth: root.activeWindowContentWidth", dock)
        self.assertIn("readonly property int windowViewportWidth: hasNonMinimizedWindows", dock)
        # T08-fix3: scale from icon feet so mag does not float icons mid-air.
        self.assertIn("transformOrigin: Item.Bottom", dock)
        self.assertIn("transformOrigin: Item.Bottom", window_button)
        self.assertNotIn("transformOrigin: Item.Center", dock)
        self.assertNotIn("transformOrigin: Item.Center", window_button)
        # T08-fix4: edge reveal debounce must not restart on every move.
        self.assertIn("if (!dockRevealDebounceTimer.running)", dock)
        self.assertNotIn("dockRevealDebounceTimer.restart()", dock)
        # No dual Behavior on the same property (T00 interceptor 待办 closed).
        # Wave mag/push: one SmoothedAnimation Behavior each (T08-fix9).
        # Dual Behavior on the same property is still forbidden.
        self.assertEqual(dock.count("Behavior on magnification"), 1)
        self.assertEqual(dock.count("Behavior on pushX"), 1)
        self.assertEqual(dock.count("Behavior on bounceOffset"), 0)
        self.assertEqual(window_button.count("Behavior on magnification"), 1)
        self.assertEqual(window_button.count("Behavior on pushX"), 1)
        self.assertEqual(window_button.count("Behavior on bounceOffset"), 0)
        # Mag/push must use SmoothedAnimation, not NumberAnimation+emphasizedDecel.
        self.assertGreaterEqual(dock.count("SmoothedAnimation"), 2)
        self.assertGreaterEqual(window_button.count("SmoothedAnimation"), 2)
        # Do not assign targets in on*Changed while Behavior is active — Qt
        # logs "another interceptor unsupported" and drops the second path.
        self.assertNotIn("onMagnificationTargetChanged:", dock)
        self.assertNotIn("onPushXTargetChanged:", dock)
        self.assertNotIn("onMagnificationTargetChanged:", window_button)
        self.assertNotIn("onPushXTargetChanged:", window_button)
        self.assertIn("property real magnification: magnificationTarget", dock)
        self.assertIn("property real pushX: pushXTarget", dock)
        self.assertIn("property real magnification: magnificationTarget", window_button)
        self.assertIn("property real pushX: pushXTarget", window_button)
        # Autohide spring must settle; tiny epsilon kept residual glass churn.
        self.assertIn("epsilon: 0.05", dock)

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

        # Running indicator: clean small dots, no glow halo (T08-fix5).
        self.assertIn("id: runningDot", dock)
        self.assertNotIn("parent.width + 4", dock)
        self.assertNotIn("parent.width + 4", window_button)
        # Surface HoverHandler owns hide (child exits must not schedule hide).
        # Wave cursor is REST-section local (T08-fix8).
        self.assertIn("id: dockSurfaceHover", dock)
        self.assertIn("HoverHandler", dock)
        self.assertIn("dockSurfaceHover.hovered", dock)
        self.assertIn("id: dockSurfaceMouse", dock)
        self.assertIn("updatePinnedHoverFromIcon", dock)
        self.assertIn("updateWindowHoverFromButton", dock)
        self.assertIn("mapToItem(dockRow", dock)
        self.assertNotIn("mapToItem(root,", dock)
        self.assertIn("// Only clear the label. Do NOT schedule hide", dock)
        # Window half reports rest-slot local x (no mapToItem into PanelWindow).
        self.assertIn("dockPointerMoved(mouse.x, mouse.buttons)", window_button)
        self.assertNotIn("mapToItem(root.dockWindow", window_button)

    def test_phase_b_press_feedback_uses_motion_single_outlet(self) -> None:
        # T06 moved menu press feedback into the shared MenuRow.qml outlet.
        required_counts = {
            "TopBar.qml": 12,
            "Tray.qml": 1,
            "Dock.qml": 2,
            "WindowButton.qml": 1,
            "DockMinimizedWindow.qml": 1,
            # T10 dechrome + T11 morph back/footer pressScale outlets.
            "ControlCenter.qml": 8,
            # T17: shortcut chips removed; one press outlet remains on result rows.
            "Spotlight.qml": 1,
            # T18: category chips removed; one press outlet on app cells.
            "Launchpad.qml": 1,
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
        # T14: accent/separator come from SettingsTheme (selectable accent).
        self.assertIn("Theme.accent(darkMode, accentId)", row)
        self.assertIn("Theme.separator(darkMode)", row)
        self.assertIn("Motion.menuFlashInterval", row)
        self.assertIn("Motion.menuFlashCount", row)
        self.assertIn("function requestActivate()", row)
        self.assertIn("Motion.reducedMotion(settingsService)", row)
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
