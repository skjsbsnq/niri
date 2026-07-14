pragma Singleton
import QtQml

QtObject {
    // Minimal surface for production services under qmltestrunner.
    property string stateDir: "/tmp/tahoe-shell-test-state"
    property string shellDir: "."
    property var screens: []

    function shellPath(path) { return path; }
    function execDetached(args) { return true; }
}
