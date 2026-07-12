import QtQuick

// Test-only file-selector replacement: media hit testing does not depend on
// Quickshell's statically linked icon plugin.
Item {
    property string name: ""
    property color color: "transparent"
    property real size: 16
    width: size
    height: size
}
