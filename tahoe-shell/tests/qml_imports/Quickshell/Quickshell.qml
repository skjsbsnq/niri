pragma Singleton
import QtQml

QtObject {
    // Minimal surface for production services under qmltestrunner.
    property string stateDir: "/tmp/tahoe-shell-test-state"
    property string shellDir: "."

    function shellPath(path) { return path; }
}
