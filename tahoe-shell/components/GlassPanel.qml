pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle

Rectangle {
    id: root

    property string material: GlassStyle.MaterialPanel
    property bool blur: true
    property bool shadow: true
    property real interaction: 0
    property real materialAlpha: 1
    property bool glassClip: true
    property bool glassEnabled: true
    property bool regionClip: glassClip
    property bool regionEnabled: glassEnabled
    property Item regionItem: root
    property bool useItemRegion: true
    property int regionX: Math.round(x)
    property int regionY: Math.round(y)
    property int regionWidth: Math.round(width)
    property int regionHeight: Math.round(height)
    property color fillColor: GlassStyle.fillForMaterial(material)
    property color strokeColor: GlassStyle.strokeForMaterial(material)
    property int strokeWidth: 1
    readonly property alias region: glassRegion

    radius: GlassStyle.radiusForMaterial(material)
    color: fillColor

    TahoeGlassRegion {
        id: glassRegion

        item: root.useItemRegion ? root.regionItem : null
        x: root.regionX
        y: root.regionY
        width: root.regionWidth
        height: root.regionHeight
        material: root.material
        radius: root.radius
        blur: root.blur
        shadow: root.shadow
        clip: root.regionClip
        interaction: root.interaction
        materialAlpha: root.materialAlpha
        enabled: root.regionEnabled
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.strokeWidth > 0 ? root.strokeWidth : 0
        radius: Math.max(0, root.radius - root.strokeWidth)
        color: "transparent"
        border.color: root.strokeColor
        border.width: root.strokeWidth
        visible: root.strokeWidth > 0
    }
}
