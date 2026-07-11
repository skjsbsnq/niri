pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import "TahoeSymbols.js" as Symbols

// Unified monochrome symbol icon (T13).
// Source is a pre-rendered white PNG under assets/icons/symbols/; tint via
// MultiEffect colorization (QtQuick.Effects; avoids GraphicalEffects plugin).
// `name` accepts a semantic name ("wifi") or a legacy Material codepoint
// string ("\ue63e") — both resolve through TahoeSymbols.js.
// Path resolution prefers appsService.iconPath("symbols", file) when an
// Apps service is provided (rules §3.1 iconPath entry); otherwise falls
// back to Quickshell.shellPath under assets/icons/symbols/.
//
// Memory discipline (rules §4.3): sourceSize is clamped to ≤128 and defaults
// to 2× display size (retina). Always asynchronous.
Item {
    id: root

    // Semantic name or legacy Material private-use codepoint string.
    property string name: ""
    // Optional absolute / file URL override. When set, bypasses name resolution.
    property string source: ""
    // Optional Apps service — when set, path goes through iconPath("symbols", …).
    property var appsService
    property color color: "#1d1d1f"
    // Display size (width & height). ≤0 → fill parent when both sides known.
    property real size: 16
    // Optional independent source pixel budget (defaults to min(128, size*2)).
    property int sourceSize: 0
    property bool asynchronous: true
    property bool mipmap: true
    property int fillMode: Image.PreserveAspectFit

    readonly property string resolvedName: Symbols.resolveName(root.name)
    readonly property string resolvedFile: {
        if (root.source.length > 0)
            return "";
        return Symbols.fileName(root.name);
    }
    readonly property string resolvedSource: {
        if (root.source.length > 0)
            return root.source;
        if (resolvedFile.length === 0)
            return "";
        if (root.appsService && root.appsService.iconPath)
            return root.appsService.iconPath("symbols", resolvedFile);
        return Quickshell.shellPath("assets/icons/symbols/" + resolvedFile);
    }
    readonly property int pixelBudget: {
        if (root.sourceSize > 0)
            return Math.min(128, root.sourceSize);
        var display = root.size > 0 ? root.size : Math.max(root.width, root.height);
        if (display <= 0)
            display = 16;
        return Math.min(128, Math.max(16, Math.ceil(display * 2)));
    }
    readonly property real displaySize: root.size > 0 ? root.size : Math.min(root.width, root.height)

    implicitWidth: root.size > 0 ? root.size : 16
    implicitHeight: root.size > 0 ? root.size : 16
    width: implicitWidth
    height: implicitHeight

    Image {
        id: baseImage

        anchors.centerIn: parent
        width: root.displaySize > 0 ? root.displaySize : parent.width
        height: root.displaySize > 0 ? root.displaySize : parent.height
        source: root.resolvedSource
        sourceSize.width: root.pixelBudget
        sourceSize.height: root.pixelBudget
        fillMode: root.fillMode
        asynchronous: root.asynchronous
        mipmap: root.mipmap
        smooth: true
        visible: false
        cache: true
    }

    // Tint white glyph PNGs. colorization=1 fully replaces luminance with
    // colorizationColor while preserving the source alpha mask.
    MultiEffect {
        anchors.fill: baseImage
        source: baseImage
        colorization: 1.0
        colorizationColor: root.color
        visible: baseImage.status === Image.Ready && root.resolvedSource.length > 0
    }
}
