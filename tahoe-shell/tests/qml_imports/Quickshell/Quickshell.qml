pragma Singleton
import QtQml

QtObject {
    // Minimal surface for production services under qmltestrunner.
    property string stateDir: "/tmp/tahoe-shell-test-state"
    property string shellDir: "."
    property var screens: []

    function shellPath(path) { return path; }
    function execDetached(args) { return true; }
    function env(name) {
        if (name === "HOME")
            return "/tmp/tahoe-shell-test-home";
        if (name === "XDG_CONFIG_HOME")
            return "/tmp/tahoe-shell-test-home/.config";
        return "";
    }
    function iconPath(name, allowTheme) {
        return name && String(name).length > 0 ? ("icon://" + name) : "";
    }
}
