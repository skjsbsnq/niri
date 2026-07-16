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
    property bool pressInteractionEnabled: true
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
    property int regionRadius: Math.round(radius)
    property color fillColor: GlassStyle.fillForMaterial(material)
    property color strokeColor: GlassStyle.strokeForMaterial(material)
    property int strokeWidth: 1
    readonly property alias region: glassRegion

    radius: GlassStyle.radiusForMaterial(material)
    color: fillColor

    // Snap interaction/alpha to 0.02 steps so continuous opacity/spring feeds
    // do not spam TahoeGlass commits (session.log showed ~60Hz clear/set).
    function quantizeGlass01(value) {
        var n = Number(value);
        if (!isFinite(n))
            return 0;
        if (n <= 0)
            return 0;
        if (n >= 1)
            return 1;
        return Math.round(n * 50) / 50;
    }

    TahoeGlassRegion {
        id: glassRegion

        item: root.useItemRegion ? root.regionItem : null
        x: root.regionX
        y: root.regionY
        width: root.regionWidth
        height: root.regionHeight
        material: root.material
        radius: root.regionRadius
        blur: root.blur
        shadow: root.shadow
        clip: root.regionClip
        interaction: root.quantizeGlass01(Math.max(root.interaction, pressHandler.active ? 1 : 0))
        materialAlpha: root.quantizeGlass01(root.materialAlpha)
        enabled: root.regionEnabled
    }

    PointHandler {
        id: pressHandler

        enabled: root.pressInteractionEnabled
        acceptedButtons: Qt.LeftButton
        target: null
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
