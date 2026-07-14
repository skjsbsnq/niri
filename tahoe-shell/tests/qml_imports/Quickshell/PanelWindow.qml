import QtQuick
import QtQuick.Window

// Minimal PanelWindow for Overlay under qmltestrunner (no shared plugins).
// Attached-style names are exposed as dynamic JS properties after construction
// so declarative WlrLayershell.*/TahoeGlass.* bindings from production can bind
// via the type's dynamic meta-object when set before load — production uses
// real attached types; this stand-in is Window + nested QtObjects.
Window {
    id: root
    color: "transparent"
    flags: Qt.FramelessWindowHint
    property bool focusable: false
    property var mask: null
    property real implicitWidth: width
    property real implicitHeight: height

    // Nested objects with stable ids; production uses attached properties.
    // QML cannot declare uppercase property names, so Overlay's
    // `WlrLayershell.layer:` requires the real C++ attached type OR a
    // rewritten root. Tests load Overlay via a thin Window host when needed.
    property var layerShell: QtObject {
        property int layer: 2
        property string namespace: ""
    }
    property var glass: QtObject {
        property var regions: []
    }
    property var edgeAnchors: QtObject {
        property bool left: false
        property bool right: false
        property bool top: false
        property bool bottom: false
    }
}
