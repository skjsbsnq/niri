import QtQuick

// Minimal TahoeGlassRegion stand-in for GlassPanel under qmltestrunner.
// Avoid redeclaring Item's final x/y/width/height; use aliases for region geometry.
Item {
    id: root
    property var item: null
    property string material: ""
    property real radius: 0
    property bool blur: true
    property bool shadow: true
    property bool clip: true
    property real interaction: 0
    property real materialAlpha: 1
    property bool enabled: true
    // GlassPanel sets x/y/width/height on the region; Item already provides them.
}
