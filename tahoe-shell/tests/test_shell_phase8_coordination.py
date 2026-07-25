from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SHELL_QML = ROOT / "shell.qml"
POPUP_HELPER = ROOT / "components" / "ShellPopupState.qml"
NAV_HELPER = ROOT / "components" / "ShellNavigation.qml"


class ShellPhase8CoordinationTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_shellroot_and_ipc_target_stay_stable(self) -> None:
        text = SHELL_QML.read_text(encoding="utf-8")

        self.assertIn("ShellRoot {", text)
        self.assertRegex(text, r"IpcHandler\s*\{[\s\S]*?target:\s*\"tahoe\"")

    def test_popup_and_navigation_helpers_are_mounted(self) -> None:
        text = SHELL_QML.read_text(encoding="utf-8")

        self.assertIn("ShellPopupState {", text)
        self.assertIn("id: shellPopupState", text)
        self.assertIn("ShellNavigation {", text)
        self.assertIn("id: shellNavigation", text)
        self.assertIn("windowsService: niri", text)

    def test_shell_keeps_public_popup_navigation_wrappers(self) -> None:
        text = SHELL_QML.read_text(encoding="utf-8")
        wrappers = [
            "screenName",
            "navigationScreenName",
            "navigationOpenFor",
            "prepareTopBarPopup",
            "topBarPopupOpenValue",
            "setTopBarPopupOpen",
            "topBarPopupOpenForName",
            "toggleTopBarPopup",
            "openTopBarTrayMenu",
            "screenByName",
            "topBarPopupOpenFor",
            "topBarDismissOpenFor",
            "closeTopBarPopups",
        ]

        for wrapper in wrappers:
            with self.subTest(wrapper=wrapper):
                self.assertRegex(text, rf"function\s+{wrapper}\s*\(")

    def test_dismiss_layer_tracks_real_popup_geometry(self) -> None:
        """Dismiss cutouts must follow live card geometry, not a size table.

        The pre-fix hardcoded width/height table drifted from the
        content-sized cards and left invisible dead zones where clicks
        neither reached the card nor dismissed it.
        """
        shell_text = SHELL_QML.read_text(encoding="utf-8")
        self.assertIn("readonly property var activeTopBarPopup:", shell_text)
        self.assertIn("popupWidth: activeTopBarPopup ? activeTopBarPopup.implicitWidth : 1", shell_text)
        self.assertIn("popupHeight: activeTopBarPopup ? activeTopBarPopup.implicitHeight : 1", shell_text)

        helper_text = POPUP_HELPER.read_text(encoding="utf-8")
        self.assertNotIn("topBarDismissPopupWidth", helper_text)
        self.assertNotIn("topBarDismissPopupHeight", helper_text)

        dismiss_text = self.read("components/PopupDismissLayer.qml")
        top_bar_text = self.read("components/TopBar.qml")
        cutout = re.search(r"height:\s*root\.useTopBarCutout\s*\?\s*(\d+)\s*:\s*0", dismiss_text)
        bar_height = re.search(r"implicitHeight:\s*(\d+)", top_bar_text)
        self.assertIsNotNone(cutout)
        self.assertIsNotNone(bar_height)
        # A taller cutout than the bar leaves a strip where clicks pass
        # through to windows underneath instead of dismissing the popup.
        self.assertEqual(cutout.group(1), bar_height.group(1))

    def test_topbar_state_is_aliased_to_helper_not_redeclared_locally(self) -> None:
        text = SHELL_QML.read_text(encoding="utf-8")
        popup_properties = [
            "controlCenterOpen",
            "appMenuOpen",
            "applicationMenuOpen",
            "notificationCenterOpen",
            "batteryPopupOpen",
            "wifiPopupOpen",
            "fanPopupOpen",
            "clipboardPopupOpen",
            "trayMenuOpen",
        ]

        for name in popup_properties:
            with self.subTest(property=name):
                self.assertIn(f"property alias {name}: shellPopupState.{name}", text)
                self.assertNotRegex(text, rf"property\s+bool\s+{name}\s*:\s*false")

        self.assertIn("property alias trayMenuItem: shellPopupState.trayMenuItem", text)
        self.assertIn("property alias topBarPopupAnchorRect: shellPopupState.topBarPopupAnchorRect", text)
        self.assertIn("property alias topBarPopupScreenName: shellPopupState.topBarPopupScreenName", text)

    def test_shell_close_wrapper_keeps_cross_surface_coordination(self) -> None:
        text = SHELL_QML.read_text(encoding="utf-8")
        match = re.search(r"function\s+closeTopBarPopups\s*\([^)]*\)\s*\{(?P<body>[\s\S]*?)\n    \}", text)
        self.assertIsNotNone(match)
        body = match.group("body")

        self.assertIn("shellPopupState.closeTopBarPopups(except)", body)
        self.assertIn("closeDockAppMenu()", body)
        self.assertIn("closeDockWindowMenu()", body)
        self.assertIn("closeProcessMenu()", body)
        self.assertIn("closeSettingsPanel()", body)
        self.assertIn("closeLeftSidebar()", body)
        self.assertIn("closeWindowNavigation(except)", body)

    def test_helper_owns_topbar_mutual_exclusion_and_tray_cleanup(self) -> None:
        text = POPUP_HELPER.read_text(encoding="utf-8")

        self.assertIn("function closeTopBarPopups(except)", text)
        self.assertIn('if (except !== "appMenu")', text)
        self.assertIn('if (except !== "trayMenu")', text)
        self.assertIn("trayMenuItem = null", text)
        self.assertIn("function toggleTopBarPopup", text)
        self.assertIn("function openTopBarTrayMenu", text)

    def test_navigation_helper_keeps_focused_output_fallback_rules(self) -> None:
        text = NAV_HELPER.read_text(encoding="utf-8")

        self.assertIn("property var windowsService: null", text)
        self.assertIn("windowsService.focusedWindow", text)
        self.assertIn("focused.output", text)
        self.assertIn("[...Quickshell.screens]", text)
        self.assertIn("target.length === 0 || target === screenName(screen)", text)


if __name__ == "__main__":
    unittest.main()
