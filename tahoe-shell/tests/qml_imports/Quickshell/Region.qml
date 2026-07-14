import QtQuick

// Minimal Region stand-in so PanelWindow.mask loads under qmltestrunner.
// Production Region comes from Quickshell C++; tests only need nesting/props.
Item {
    property real x: 0
    property real y: 0
    property real width: 0
    property real height: 0
    property real radius: 0
    default property alias data: host.data
    Item { id: host }
}
