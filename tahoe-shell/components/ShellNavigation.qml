import QtQuick
import Quickshell

QtObject {
    id: navigation

    property var windowsService: null

    function screenName(screen) {
        return screen ? String(screen.name || "") : "";
    }

    function navigationScreenName() {
        var focused = windowsService ? windowsService.focusedWindow : null;
        var output = focused ? String(focused.output || "").trim() : "";
        if (output.length > 0)
            return output;

        var screens = [...Quickshell.screens];
        return screens.length > 0 ? screenName(screens[0]) : "";
    }

    function navigationOpenFor(open, targetScreenName, screen) {
        var target = String(targetScreenName || "");
        return open && (target.length === 0 || target === screenName(screen));
    }

    function screenByName(name) {
        var target = String(name || "");
        var screens = [...Quickshell.screens];
        for (var i = 0; i < screens.length; i++) {
            if (screenName(screens[i]) === target)
                return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }
}
