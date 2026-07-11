pragma ComponentBehavior: Bound

import QtQuick
import "WeatherCodes.js" as WeatherCodes

// Weather icon: WMO weather_code + day/night → TahoeSymbol (pre-rendered PNG).
// Data mapping lives in WeatherCodes.js; this component only renders.
Item {
    id: root

    property int weatherCode: -1
    property bool night: false
    property real pixelSize: 0
    property color color: "#1d1d1f"

    readonly property real resolvedPixelSize: pixelSize > 0
        ? pixelSize
        : Math.floor(Math.min(root.width, root.height) * 0.86)

    readonly property string glyph: WeatherCodes.materialIcon(weatherCode, night)
    readonly property string label: WeatherCodes.text(weatherCode)

    TahoeSymbol {
        anchors.centerIn: parent
        name: root.glyph
        color: root.color
        size: root.resolvedPixelSize
        width: root.width > 0 ? root.width : size
        height: root.height > 0 ? root.height : size
    }
}
