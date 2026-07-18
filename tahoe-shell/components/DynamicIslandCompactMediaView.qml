pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion

// V2 compact media (T16): 22×22 art + single-line title + play/pause symbol.
// Optional 2px bottom progress. Artist is expanded-only. No bar spectrum.
// Active player / metadata come from Controls via DynamicIsland — this view
// never selects or walks the MPRIS player list.
Item {
    id: root

    property string artUrl: ""
    property string trackTitle: ""
    property bool isPlaying: false
    property real progress: 0
    property bool progressSupported: false
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color accentColor: "#0a84ff"
    property color trackColor: "#30ffffff"
    property color artFallbackFill: "#28ffffff"
    property var settingsService

    readonly property int artSize: 22
    readonly property int statusSize: 16
    readonly property int rowSpacing: 8
    readonly property int horizontalPad: 10
    // Title max contribution so art+title+status stay within v2CompactMediaWidthMax.
    readonly property int titleMaxWidth: Math.max(
        48,
        IslandMotion.v2CompactMediaWidthMax
            - (root.horizontalPad * 2)
            - root.artSize
            - root.statusSize
            - (root.rowSpacing * 2))
    readonly property bool showArt: root.safeArtUrl.length > 0
    readonly property string safeArtUrl: {
        var url = String(root.artUrl || "").trim();
        if (url.length === 0)
            return "";
        // Only load common local/remote schemes; reject opaque junk.
        if (url.indexOf("http://") === 0
                || url.indexOf("https://") === 0
                || url.indexOf("file://") === 0
                || url.indexOf("image://") === 0
                || url.indexOf("/") === 0)
            return url;
        return "";
    }
    readonly property string resolvedTitle: {
        var title = String(root.trackTitle || "").trim();
        return title.length > 0 ? title : "正在播放";
    }
    readonly property real safeProgress: {
        var number = Number(root.progress);
        if (!isFinite(number))
            return 0;
        return Math.max(0, Math.min(1, number));
    }
    readonly property bool showProgress: root.progressSupported && root.safeProgress >= 0
    // Measured content width (no capsule chrome). Overlay clamps to 200–224.
    readonly property int contentWidth: Math.ceil(
        root.horizontalPad * 2
        + root.artSize
        + root.rowSpacing
        + Math.min(titleLabel.implicitWidth, root.titleMaxWidth)
        + root.rowSpacing
        + root.statusSize)
    readonly property int contentHeight: IslandMotion.v2CompactMediaHeight

    implicitWidth: contentWidth
    implicitHeight: contentHeight

    Item {
        id: mediaRow
        // Full height always — progress overlays the bottom edge and must not
        // reflow art/title when support flips.
        anchors.fill: parent
        anchors.leftMargin: root.horizontalPad
        anchors.rightMargin: root.horizontalPad
        anchors.topMargin: 0
        anchors.bottomMargin: 0

        Rectangle {
            id: artBadge
            width: root.artSize
            height: root.artSize
            radius: 6
            color: root.artFallbackFill
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            clip: true

            // Only bind Image.source while this compact scene is visible so
            // non-owner / hidden outputs never kick off album art loads.
            // Art crossfades in over the fallback glyph once loaded (#28).
            Image {
                id: artImage
                anchors.fill: parent
                source: (root.visible && root.showArt) ? root.safeArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: (root.showArt && status === Image.Ready) ? 1 : 0
                visible: opacity > 0.01
                sourceSize: Qt.size(44, 44)

                Behavior on opacity {
                    NumberAnimation {
                        duration: IslandMotion.contentEnterMs(root.settingsService)
                        easing.type: IslandMotion.v2ContentEasing
                    }
                }
            }

            TahoeSymbol {
                anchors.centerIn: parent
                name: "\ue405" // music_note
                color: root.textSecondary
                size: 14
                opacity: 1 - artImage.opacity
                visible: opacity > 0.01
            }
        }

        Text {
            id: titleLabel
            anchors.left: artBadge.right
            anchors.leftMargin: root.rowSpacing
            anchors.right: statusIcon.left
            anchors.rightMargin: root.rowSpacing
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(root.titleMaxWidth, Math.max(1, parent.width - root.artSize - root.statusSize - root.rowSpacing * 2))
            text: root.resolvedTitle
            color: root.textPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.letterSpacing: 0
            elide: Text.ElideRight
            maximumLineCount: 1
            verticalAlignment: Text.AlignVCenter
        }

        // Playing → pause (e034); paused → play_arrow (e037). Match
        // DynamicIsland.iconCodeForState so font glyphs stay consistent.
        // Glyph switch fades out, swaps, fades back in (#28 short crossfade).
        TahoeSymbol {
            id: statusIcon
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            property bool shownPlaying: root.isPlaying
            name: statusIcon.shownPlaying ? "\ue034" : "\ue037"
            color: root.textSecondary
            size: root.statusSize

            Connections {
                target: root
                function onIsPlayingChanged() {
                    if (statusIcon.shownPlaying !== root.isPlaying)
                        statusGlyphSwap.restart();
                }
            }

            SequentialAnimation {
                id: statusGlyphSwap
                NumberAnimation {
                    target: statusIcon
                    property: "opacity"
                    to: 0
                    duration: Math.round(IslandMotion.contentExitMs(root.settingsService) / 2)
                    easing.type: IslandMotion.v2ContentEasing
                }
                ScriptAction {
                    script: statusIcon.shownPlaying = root.isPlaying
                }
                NumberAnimation {
                    target: statusIcon
                    property: "opacity"
                    to: 1
                    duration: Math.round(IslandMotion.contentExitMs(root.settingsService) / 2)
                    easing.type: IslandMotion.v2ContentEasing
                }
            }
        }
    }

    // Optional 2px bottom progress (position/length when Controls supports it).
    Rectangle {
        id: progressTrack
        visible: root.showProgress
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.horizontalPad
        anchors.rightMargin: root.horizontalPad
        height: 2
        radius: 1
        color: root.trackColor

        Rectangle {
            width: parent.width * root.safeProgress
            height: parent.height
            radius: parent.radius
            color: root.accentColor
        }
    }
}
