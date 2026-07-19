pragma ComponentBehavior: Bound

import QtQuick
import "Motion.js" as Motion
import "WeatherCodes.js" as WeatherCodes

// Weather icon: WMO weather_code + day/night → TahoeSymbol (pre-rendered PNG).
// Data mapping lives in WeatherCodes.js; this component only renders.
Item {
    id: root

    property int weatherCode: -1
    property bool night: false
    property real pixelSize: 0
    property color color: "#1d1d1f"
    property var settingsService
    property string displayedGlyph: ""
    property string outgoingGlyph: ""
    property real transitionProgress: 1
    property real outgoingStartOpacity: 0
    property real incomingStartOpacity: 1
    property bool componentReady: false

    readonly property real resolvedPixelSize: pixelSize > 0
        ? pixelSize
        : Math.floor(Math.min(root.width, root.height) * 0.86)

    readonly property string glyph: WeatherCodes.materialIcon(weatherCode, night)
    readonly property string label: WeatherCodes.text(weatherCode)

    TahoeSymbol {
        anchors.centerIn: parent
        name: root.outgoingGlyph
        color: root.color
        size: root.resolvedPixelSize
        width: root.width > 0 ? root.width : size
        height: root.height > 0 ? root.height : size
        opacity: root.outgoingStartOpacity * (1 - root.transitionProgress)
        visible: root.outgoingGlyph.length > 0 && opacity > 0.01
    }

    TahoeSymbol {
        anchors.centerIn: parent
        name: root.displayedGlyph
        color: root.color
        size: root.resolvedPixelSize
        width: root.width > 0 ? root.width : size
        height: root.height > 0 ? root.height : size
        opacity: root.incomingStartOpacity
            + (1 - root.incomingStartOpacity) * root.transitionProgress
        visible: root.displayedGlyph.length > 0 && opacity > 0.01
    }

    NumberAnimation {
        id: glyphFade
        target: root
        property: "transitionProgress"
        to: 1
        duration: Motion.fadeFast(root.settingsService)
        easing.type: Motion.standardDecel
        onFinished: {
            root.outgoingGlyph = "";
            root.outgoingStartOpacity = 0;
            root.incomingStartOpacity = 1;
        }
    }

    function transitionToGlyph(nextGlyph) {
        var next = String(nextGlyph || "");
        if (!root.componentReady) {
            root.displayedGlyph = next;
            return;
        }
        if (next === root.displayedGlyph && root.transitionProgress >= 0.999)
            return;

        glyphFade.stop();
        if (Motion.reducedMotion(root.settingsService) || Motion.fadeFast(root.settingsService) <= 0) {
            root.outgoingGlyph = "";
            root.displayedGlyph = next;
            root.outgoingStartOpacity = 0;
            root.incomingStartOpacity = 1;
            root.transitionProgress = 1;
            return;
        }

        var outgoingOpacity = root.outgoingStartOpacity * (1 - root.transitionProgress);
        var incomingOpacity = root.incomingStartOpacity
            + (1 - root.incomingStartOpacity) * root.transitionProgress;
        root.outgoingGlyph = incomingOpacity >= outgoingOpacity
            ? root.displayedGlyph
            : root.outgoingGlyph;
        root.outgoingStartOpacity = Math.max(outgoingOpacity, incomingOpacity);
        root.displayedGlyph = next;
        root.incomingStartOpacity = 0;
        root.transitionProgress = 0;
        glyphFade.duration = Motion.fadeFast(root.settingsService);
        glyphFade.restart();
    }

    onGlyphChanged: transitionToGlyph(glyph)

    Component.onCompleted: {
        componentReady = true;
        displayedGlyph = glyph;
        outgoingGlyph = "";
        outgoingStartOpacity = 0;
        incomingStartOpacity = 1;
        transitionProgress = 1;
    }
}
