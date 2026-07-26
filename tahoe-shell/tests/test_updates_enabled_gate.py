"""P02: per-window updatesEnabled freeze gate.

Contract:
- RenderActivity.js is the shared policy helper (extends visible/pollingActive).
- Every PanelWindow under components/ sets updatesEnabled.
- Popup-style surfaces mirror visible.
- DynamicIslandOverlay / Dock / Wallpaper use resident freeze + paint pulse.
- quickshell ProxyWindowBase re-enables with window->update().
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ROOT / "components"
QUICKSHELL_PROXY = (
    ROOT.parent / "quickshell" / "src" / "window" / "proxywindow.cpp"
)


class UpdatesEnabledGateTests(unittest.TestCase):
    def test_render_activity_helper_documents_unified_policy(self) -> None:
        text = (COMPONENTS / "RenderActivity.js").read_text(encoding="utf-8")
        self.assertIn("function forResidentSurface(", text)
        self.assertIn("paintPulseMs", text)
        self.assertIn("transitionPulseMs", text)
        self.assertIn("updatesEnabled", text)
        self.assertIn("pollingActive", text)
        # Popups inline `updatesEnabled: visible`; no dead wrapper helper.
        self.assertNotIn("forMappedSurface", text)

    def test_every_panel_window_sets_updates_enabled(self) -> None:
        offenders: list[str] = []
        for path in sorted(COMPONENTS.glob("*.qml")):
            text = path.read_text(encoding="utf-8")
            if "PanelWindow {" not in text:
                continue
            if not re.search(r"^[ \t]*updatesEnabled:", text, re.M):
                offenders.append(path.name)
        self.assertEqual(
            offenders,
            [],
            "PanelWindow roots must set updatesEnabled (P02 freeze gate)",
        )

    def test_popup_surfaces_mirror_visible(self) -> None:
        for name in (
            "ControlCenter.qml",
            "Spotlight.qml",
            "TaskSwitcher.qml",
            "NotificationCenter.qml",
            "SettingsPanel.qml",
            "Launchpad.qml",
            "WindowOverview.qml",
            "PopupDismissLayer.qml",
            "TopBar.qml",
        ):
            text = (COMPONENTS / name).read_text(encoding="utf-8")
            self.assertRegex(
                text,
                r"(?m)^[ \t]*updatesEnabled:\s*visible\b",
                msg=name,
            )

    def test_dynamic_island_resident_freeze_and_clock_pulse(self) -> None:
        text = (COMPONENTS / "DynamicIslandOverlay.qml").read_text(encoding="utf-8")
        self.assertIn("import \"RenderActivity.js\" as RenderActivity", text)
        self.assertIn("surfaceMotionActive", text)
        self.assertIn(
            "updatesEnabled: RenderActivity.forResidentSurface(visible, surfaceMotionActive, paintPulse)",
            text,
        )
        # Content/theme events kick Behavior transitions (crossfade 170ms,
        # fillColor 260ms) — their pulses must span the transition, not 48ms.
        self.assertIn(
            "onContentClockTimeChanged: root.requestPaintPulse(RenderActivity.transitionPulseMs)",
            text,
        )
        self.assertIn(
            "onDarkModeChanged: root.requestPaintPulse(RenderActivity.transitionPulseMs)",
            text,
        )
        self.assertIn(
            "onEffectiveContentStateChanged: root.requestPaintPulse(RenderActivity.transitionPulseMs)",
            text,
        )
        # Settle frame: motion→rest must repaint the final animation tick, at
        # transition length (pause kicks a 110ms glyph swap the predicate
        # cannot see — reviews R-P02).
        self.assertIn(
            "onSurfaceMotionActiveChanged: if (!surfaceMotionActive) "
            "root.requestPaintPulse(RenderActivity.transitionPulseMs)",
            text,
        )
        # Frozen-rest inputs that repaint without any state flip.
        self.assertIn("onMediaProgressChanged: root.requestPaintPulse()", text)
        self.assertIn("onAccentColorChanged: root.requestPaintPulse()", text)
        self.assertIn(
            "onScreenWidthChanged: root.requestPaintPulse(RenderActivity.transitionPulseMs)",
            text,
        )
        # Async album art holds the predicate hot until Ready.
        self.assertIn("islandContent.asyncArtLoading", text)
        self.assertIn("protocolGeometrySettled", text)
        self.assertIn("mediaPlaying", text)
        self.assertIn("timerRunning", text)
        self.assertIn("requestPaintPulse", text)
        # First-map pulse is merged into the root's single Component.onCompleted
        # (QML forbids a second root-level handler: "Property value set
        # multiple times" breaks the whole component at load).
        self.assertIn(
            "root.geometryDriversReady = true;\n        root.requestPaintPulse();",
            text,
        )
        self.assertEqual(
            len(re.findall(r"(?m)^    Component\.onCompleted", text)),
            1,
            "exactly one root-level Component.onCompleted",
        )

    def test_resident_surfaces_have_single_root_oncompleted(self) -> None:
        # Duplicate root-level handlers are a QML load error — the freeze-gate
        # pulses must merge into existing handlers, never add a second one.
        for name in ("DynamicIslandOverlay.qml", "Dock.qml", "Wallpaper.qml"):
            text = (COMPONENTS / name).read_text(encoding="utf-8")
            self.assertEqual(
                len(re.findall(r"(?m)^    Component\.onCompleted", text)),
                1,
                name,
            )
            self.assertLessEqual(
                len(re.findall(r"(?m)^    onVisibleChanged:", text)),
                1,
                name,
            )
            self.assertIn(
                "root.requestPaintPulse();",
                text,
                f"{name}: first-map pulse must run from Component.onCompleted",
            )

    def test_paint_pulse_is_extend_only(self) -> None:
        # A short settle request must not truncate a pending transition pulse.
        for name in ("DynamicIslandOverlay.qml", "Dock.qml", "Wallpaper.qml"):
            text = (COMPONENTS / name).read_text(encoding="utf-8")
            self.assertIn("function requestPaintPulse(durationMs)", text, name)
            self.assertRegex(
                text,
                r"Math\.max\(\s*\n?\s*Number\(durationMs\) \|\| RenderActivity\.paintPulseMs,",
                name,
            )

    def test_dock_freezes_when_autohide_hidden_at_rest(self) -> None:
        text = (COMPONENTS / "Dock.qml").read_text(encoding="utf-8")
        self.assertIn("import \"RenderActivity.js\" as RenderActivity", text)
        self.assertIn("dockRenderMotion", text)
        self.assertIn("!dockVisualHidden", text)
        self.assertIn(
            "updatesEnabled: RenderActivity.forResidentSurface(visible, dockRenderMotion, paintPulse)",
            text,
        )
        self.assertIn(
            "onDockRenderMotionChanged: if (!dockRenderMotion) "
            "root.requestPaintPulse(RenderActivity.transitionPulseMs)",
            text,
        )
        # Hidden-at-rest launch bounce peeks above the screen edge; every
        # offset tick re-arms a pulse so bounce/retract render while hidden.
        self.assertIn(
            "onBounceOffsetChanged: if (root.dockVisualHidden) root.requestPaintPulse()",
            text,
        )
        self.assertIn("requestPaintPulse", text)

    def test_wallpaper_freezes_when_static_or_fully_yielded(self) -> None:
        text = (COMPONENTS / "Wallpaper.qml").read_text(encoding="utf-8")
        self.assertIn("import \"RenderActivity.js\" as RenderActivity", text)
        self.assertIn("surfaceMotionActive", text)
        self.assertIn(
            "updatesEnabled: RenderActivity.forResidentSurface(true, surfaceMotionActive, paintPulse)",
            text,
        )
        self.assertIn("launchpadOpen", text)
        self.assertIn("coverPlateVisible", text)
        self.assertIn(
            "onSurfaceMotionActiveChanged: if (!surfaceMotionActive) "
            "root.requestPaintPulse(RenderActivity.transitionPulseMs)",
            text,
        )
        # Cache-hit wallpaper swap can skip the Loading phase — the new texture
        # must still get a paint pulse.
        self.assertIn("onSourceChanged: root.requestPaintPulse()", text)
        self.assertIn("onStatusChanged: root.requestPaintPulse()", text)

    def test_island_art_loading_chain(self) -> None:
        # MediaView exposes the async decode; Content aggregates it for the
        # overlay predicate (Loader item may be absent → coerced false).
        media = (COMPONENTS / "DynamicIslandMediaView.qml").read_text(encoding="utf-8")
        self.assertIn(
            "readonly property bool artLoading: artImage.status === Image.Loading",
            media,
        )
        content = (COMPONENTS / "DynamicIslandContent.qml").read_text(encoding="utf-8")
        self.assertIn(
            "readonly property bool asyncArtLoading: "
            "mediaLoader.item ? !!mediaLoader.item.artLoading : false",
            content,
        )

    def test_quickshell_reenable_schedules_frame(self) -> None:
        self.assertTrue(QUICKSHELL_PROXY.is_file(), QUICKSHELL_PROXY)
        text = QUICKSHELL_PROXY.read_text(encoding="utf-8")
        self.assertIn("void ProxyWindowBase::setUpdatesEnabled(bool updatesEnabled)", text)
        # Must schedule a frame on re-enable so frozen dirty state paints.
        self.assertIn("if (updatesEnabled) this->window->update();", text)


if __name__ == "__main__":
    unittest.main()
