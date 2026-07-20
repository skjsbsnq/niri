pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import "TahoeSymbols.js" as Symbols

// Unified monochrome symbol icon. Material private-use codepoints are rendered
// directly from the bundled font so every call site shares the font's metrics,
// baseline and optical size. Explicit bitmap sources and the few PNG-only
// shortcut symbols retain the image fallback.
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
    // Optional independent source pixel budget (defaults to full 128px asset).
    // Top-bar symbols are ~20px; decoding at only 2× (40px) made detailed PNGs
    // (e.g. fan) look soft after MultiEffect colorization. Prefer the native
    // 128 asset and let the GPU downsample from a sharp source.
    property int sourceSize: 0
    property bool asynchronous: true
    // Mipmaps soften thin monochrome glyphs at ≤24px; default off for bitmap
    // path. Font glyphs ignore this. Call sites can re-enable for large icons.
    property bool mipmap: false
    property int fillMode: Image.PreserveAspectFit
    // Material's font line box sits slightly above the optical center at small
    // sizes. Keep one shared correction so popup and top-bar glyphs agree.
    property real opticalOffsetX: 0
    property real opticalOffsetY: 1

    readonly property string glyph: Symbols.glyph(root.name)
    readonly property bool usesFontGlyph: root.source.length === 0 && root.glyph.length > 0
    readonly property string resolvedName: Symbols.resolveName(root.name)
    readonly property string resolvedFile: {
        if (root.source.length === 0)
            return Symbols.fileName(root.name);
        return "";
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
            return Math.min(128, Math.max(16, root.sourceSize));
        var display = root.size > 0 ? root.size : Math.max(root.width, root.height);
        if (display <= 0)
            display = 16;
        // At least 4× display (capped at asset size) so 20px icons sample from
        // ≥80px — still sharp after colorization. Full 128 when display ≥32.
        return Math.min(128, Math.max(64, Math.ceil(display * 4)));
    }
    readonly property real displaySize: root.size > 0 ? root.size : Math.min(root.width, root.height)

    implicitWidth: root.size > 0 ? root.size : 16
    implicitHeight: root.size > 0 ? root.size : 16
    width: implicitWidth
    height: implicitHeight

    FontLoader {
        id: materialIconsFont
        source: Quickshell.shellPath("assets/fonts/MaterialIconsRound.ttf")
    }

    Text {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.opticalOffsetX
        anchors.verticalCenterOffset: root.opticalOffsetY
        width: root.displaySize
        height: root.displaySize
        text: root.glyph
        color: root.color
        font.family: materialIconsFont.name
        font.pixelSize: Math.max(1, Math.round(root.displaySize))
        font.weight: Font.Normal
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.QtRendering
        visible: root.usesFontGlyph && materialIconsFont.status === FontLoader.Ready
    }

    Image {
        id: baseImage

        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.opticalOffsetX
        anchors.verticalCenterOffset: root.opticalOffsetY
        // Integer pixel box avoids half-pixel sampling blur at top-bar sizes.
        width: root.displaySize > 0 ? Math.round(root.displaySize) : parent.width
        height: root.displaySize > 0 ? Math.round(root.displaySize) : parent.height
        source: root.usesFontGlyph ? "" : root.resolvedSource
        sourceSize.width: root.pixelBudget
        sourceSize.height: root.pixelBudget
        fillMode: root.fillMode
        asynchronous: root.asynchronous
        mipmap: root.mipmap
        // Smooth downsample from high-res source; combined with full pixelBudget
        // this stays sharper than 2× decode + mipmaps.
        smooth: true
        visible: false
        cache: true
    }

    MultiEffect {
        anchors.fill: baseImage
        source: baseImage
        colorization: 1.0
        colorizationColor: root.color
        // Avoid extra blur passes that mush thin symbol edges.
        blurEnabled: false
        visible: !root.usesFontGlyph
            && baseImage.status === Image.Ready
            && root.resolvedSource.length > 0
    }
}
