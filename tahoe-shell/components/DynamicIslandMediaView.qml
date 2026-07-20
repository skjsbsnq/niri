pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion
import "Motion.js" as Motion

// Unified media scene: one layout morphs compact (expandProgress=0) → expanded (1).
// expandProgress is driven by capsule height so art, timeline, and transport
// grow/fade with geometry instead of hard scene swaps.
// Transport glyphs: TahoeSymbol only. Seek when canSeek. No second MPRIS owner.
Item {
    id: root

    property string artUrl: ""
    property string trackTitle: ""
    property string trackArtist: ""
    property bool isPlaying: false
    property real position: 0
    property real duration: 0
    property real progress: 0
    property bool positionSupported: false
    property bool durationSupported: false
    property bool canPlayPause: false
    property bool canPrev: false
    property bool canNext: false
    property bool canSeek: false
    property bool seeking: false
    // 0 = compact pill chrome, 1 = full expanded player. Continuous morph.
    // Default 1 so bare MediaView hosts (lifecycle tests) get full transport;
    // production Content/Overlay always drive this from capsule height.
    property real expandProgress: 1
    property var settingsService
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color accentColor: "#0a84ff"
    property color trackColor: "#30ffffff"
    property color progressFillColor: "#f7f8fa"
    property color controlFill: "#20ffffff"
    property color artFallbackFill: "#28ffffff"
    readonly property bool reducedMotion: Motion.reducedMotion(root.settingsService)

    signal previousRequested()
    signal playPauseRequested()
    signal nextRequested()
    signal controlPressed()
    signal controlReleased()
    signal seekBeginRequested()
    signal seekPreviewRequested(real ratio)
    signal seekCommitRequested(real ratio)
    signal seekCancelRequested()

    // Design endpoints (compact T16 / expanded T17).
    // Compact art 24 sits in 36px pill with ~6px vertical air; expanded 64.
    readonly property int artSizeCompact: 24
    readonly property int artSizeExpanded: 64
    readonly property int artRadiusCompact: 7
    readonly property int artRadiusExpanded: 12
    readonly property int titleSizeCompact: 13
    readonly property int titleSizeExpanded: 16
    readonly property int artistSize: 12
    readonly property int playSize: 36
    readonly property int skipSize: 32
    readonly property int controlHit: 44
    // Trailing status glyph is quieter than transport chrome (14 vs old 16).
    readonly property int statusSize: 14
    readonly property int compactPadH: 12
    readonly property int expandedPadH: 16
    readonly property int compactPadV: 0
    readonly property int expandedPadTop: 16
    readonly property int titleGapCompact: 10
    readonly property int titleGapExpanded: 14
    readonly property int statusGapCompact: 10

    readonly property real p: Math.max(0, Math.min(1, Number(root.expandProgress) || 0))
    // Ease curves for staged reveal (still continuous — no hard cuts).
    // Art/title lead the morph; timeline mid; transport late so buttons never
    // pop at full size inside a half-height pill.
    readonly property real pArt: root.smoothstep(root.p, 0.0, 0.85)
    readonly property real pTimeline: root.smoothstep(root.p, 0.28, 0.92)
    readonly property real pControls: root.smoothstep(root.p, 0.42, 1.0)
    readonly property real pArtist: root.smoothstep(root.p, 0.35, 0.9)
    readonly property real pCompactChrome: 1.0 - root.smoothstep(root.p, 0.0, 0.45)

    readonly property real artSize: root.artSizeCompact
        + (root.artSizeExpanded - root.artSizeCompact) * root.pArt
    readonly property real artRadius: root.artRadiusCompact
        + (root.artRadiusExpanded - root.artRadiusCompact) * root.pArt
    readonly property real titlePx: root.titleSizeCompact
        + (root.titleSizeExpanded - root.titleSizeCompact) * root.pArt
    readonly property real padH: root.compactPadH
        + (root.expandedPadH - root.compactPadH) * root.pArt
    readonly property real padTop: root.compactPadV
        + (root.expandedPadTop - root.compactPadV) * root.pArt
    readonly property real titleLeftGap: root.titleGapCompact
        + (root.titleGapExpanded - root.titleGapCompact) * root.pArt
    // Compact: full pill height so art/title/status can vertical-center.
    // Expanded: art-driven top band (64).
    readonly property real topRowHeight: root.artSizeCompact
        + (root.artSizeExpanded - root.artSizeCompact) * root.pArt
        + (IslandMotion.v2CompactMediaHeight - root.artSizeCompact) * (1.0 - root.pArt)
    // Compact centers the row in the capsule; expanded pins to top with pad.
    readonly property real topRowY: {
        if (root.pArt < 0.02)
            return Math.max(0, (parent.height - root.topRowHeight) / 2);
        // Lerp center → top pad as we expand.
        var centered = Math.max(0, (parent.height - root.topRowHeight) / 2);
        return centered * (1.0 - root.pArt) + root.padTop * root.pArt;
    }

    readonly property bool showArt: root.safeArtUrl.length > 0
    readonly property string safeArtUrl: {
        var url = String(root.artUrl || "").trim();
        if (url.length === 0)
            return "";
        if (url.indexOf("http://") === 0
                || url.indexOf("https://") === 0
                || url.indexOf("file://") === 0
                || url.indexOf("image://") === 0
                || url.indexOf("/") === 0)
            return url;
        return "";
    }
    readonly property string resolvedTitle: {
        var t = String(root.trackTitle || "").trim();
        return t.length > 0 ? t : "正在播放";
    }

    property bool localSeeking: false
    property real localSeekRatio: 0
    readonly property real safeProgress: {
        if (root.localSeeking || root.seeking)
            return Math.max(0, Math.min(1, Number(root.localSeeking ? root.localSeekRatio : root.progress) || 0));
        return Math.max(0, Math.min(1, Number(progress) || 0));
    }
    readonly property real displayPosition: {
        if ((root.localSeeking || root.seeking) && root.duration > 0)
            return root.safeProgress * root.duration;
        return root.positionSupported ? root.position : 0;
    }
    readonly property bool showTimeline: positionSupported || durationSupported || duration > 0
    // Scrub only once expanded enough that the timeline is interactive.
    readonly property bool scrubInteractive: root.canSeek
        && root.showTimeline
        && root.duration > 0
        && root.pTimeline > 0.85
        && root.visible
    readonly property int progressDurationMs: root.reducedMotion
        ? IslandMotion.v2ReducedContentMs
        : IslandMotion.overlayProgressDuration

    // Compact width measure (for Overlay resting_media band) — art+title+status.
    // Cap title contribution so long Chinese titles do not blow the 200–224 band
    // and crush status glyph spacing.
    readonly property int compactTitleMax: Math.max(
        48,
        IslandMotion.v2CompactMediaWidthMax
            - (root.compactPadH * 2)
            - root.artSizeCompact
            - root.statusSize
            - root.titleGapCompact
            - root.statusGapCompact)
    readonly property int compactContentWidth: Math.ceil(
        root.compactPadH * 2
        + root.artSizeCompact
        + root.titleGapCompact
        + Math.min(titleLabel.implicitWidth, root.compactTitleMax)
        + root.statusGapCompact
        + root.statusSize)

    function smoothstep(t, edge0, edge1) {
        var x = Number(t);
        var a = Number(edge0);
        var b = Number(edge1);
        if (!isFinite(x))
            return 0;
        if (b <= a)
            return x >= b ? 1 : 0;
        var u = Math.max(0, Math.min(1, (x - a) / (b - a)));
        return u * u * (3 - 2 * u);
    }

    function formatTime(seconds) {
        var total = Math.max(0, Math.floor(Number(seconds) || 0));
        var minutes = Math.floor(total / 60);
        var secs = total % 60;
        return minutes + ":" + (secs < 10 ? "0" : "") + secs;
    }

    anchors.fill: parent

    // ---- Top: art + title (+ artist when expanded) ----
    // Position with y (not topMargin) so compact can vertical-center in the
    // 36px pill — top-anchored 22px chrome left a dead strip and looked off.
    Item {
        id: topRow
        x: root.padH
        y: root.topRowY
        width: Math.max(1, parent.width - root.padH * 2)
        height: root.topRowHeight

        Rectangle {
            id: artBadge
            width: root.artSize
            height: root.artSize
            radius: root.artRadius
            // Slightly stronger fill so art plate reads against dark glass.
            color: root.artFallbackFill
            clip: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            // Soft edge so square art does not look pasted on the pill.
            border.width: root.pArt < 0.5 ? 1 : 0
            border.color: "#18ffffff"

            Image {
                id: artImage
                anchors.fill: parent
                source: (root.visible && root.showArt) ? root.safeArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                visible: root.showArt && status === Image.Ready
                sourceSize: Qt.size(128, 128)
                asynchronous: true
                // Mild desaturation avoidance — keep full color; smooth edges.
                smooth: true
                mipmap: true
            }

            TahoeSymbol {
                anchors.centerIn: parent
                name: "\ue405"
                color: root.textSecondary
                size: 13 + 15 * root.pArt
                visible: !artImage.visible
            }
        }

        // Title + artist column (expands from single-line compact title).
        Item {
            id: textBlock
            anchors {
                left: artBadge.right
                leftMargin: root.titleLeftGap
                right: statusHit.left
                rightMargin: root.statusGapCompact * (1.0 - root.pArt * 0.3)
                verticalCenter: parent.verticalCenter
            }
            // Compact: single-line title height only so vertical center matches art.
            // Expanded: title + artist stack.
            height: {
                if (root.pArtist > 0.05 && artistLabel.visible)
                    return titleLabel.height + 4 + artistLabel.height;
                return Math.max(titleLabel.height, root.artSizeCompact * 0.9);
            }

            Column {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 4

                Text {
                    id: titleLabel
                    width: parent.width
                    text: root.resolvedTitle
                    color: root.textPrimary
                    font.pixelSize: root.titlePx
                    // Medium reads cleaner for dense CJK in a 36px pill than DemiBold.
                    font.weight: root.pArt < 0.35 ? Font.Medium : Font.DemiBold
                    font.letterSpacing: root.pArt < 0.35 ? 0.2 : 0
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                    opacity: 0.96 + 0.04 * root.pArt
                }

                Text {
                    id: artistLabel
                    width: parent.width
                    text: root.trackArtist
                    color: root.textSecondary
                    font.pixelSize: root.artistSize
                    font.letterSpacing: 0
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    opacity: root.pArtist
                    // Keep height 0 when hidden so compact title stays centered.
                    height: (text.length > 0 && opacity > 0.02) ? implicitHeight : 0
                    visible: height > 0
                }
            }
        }

        // Compact trailing play/pause — quiet secondary chrome, not a loud control.
        Item {
            id: statusHit
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(root.statusSize + 4, 20)
            height: Math.max(root.statusSize + 4, 20)
            opacity: root.pCompactChrome
            visible: opacity > 0.02

            // Soft circular plate so the glyph does not float raw on glass.
            Rectangle {
                anchors.centerIn: parent
                width: 20
                height: 20
                radius: 10
                color: "#14ffffff"
                border.width: 1
                border.color: "#12ffffff"
            }

            TahoeSymbol {
                id: statusIcon
                anchors.centerIn: parent
                name: root.isPlaying ? "\ue034" : "\ue037"
                color: root.textPrimary
                size: root.statusSize
                opacity: 0.72
            }
        }
    }

    // ---- Compact bottom progress (2px) — fades out as expanded timeline appears ----
    Rectangle {
        id: compactProgress
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: root.compactPadH
            rightMargin: root.compactPadH
            // Sit just above the pill edge so it does not collide with art.
            bottomMargin: 3
        }
        height: 2
        radius: 1
        color: root.trackColor
        opacity: root.pCompactChrome * ((root.positionSupported && root.duration > 0) ? 0.9 : 0)
        visible: opacity > 0.02

        Rectangle {
            width: parent.width * root.safeProgress
            height: parent.height
            radius: parent.radius
            color: root.progressFillColor
            opacity: 0.9
        }
    }

    // ---- Expanded timeline — fades/slides in with geometry ----
    Item {
        id: timeline
        anchors {
            left: parent.left
            right: parent.right
            // Use topRow bottom in parent coords (topRow is free-positioned).
            top: parent.top
            topMargin: root.topRowY + root.topRowHeight + (4 + 8 * root.pTimeline)
            leftMargin: root.padH
            rightMargin: root.padH
        }
        height: 10 + 12 * root.pTimeline
        opacity: root.pTimeline * (root.showTimeline ? 1 : 0.45)
        visible: opacity > 0.02
        // Soft rise from below as the pill grows.
        transform: Translate {
            y: (1.0 - root.pTimeline) * 8
        }

        Rectangle {
            id: progressTrack
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                topMargin: 2
            }
            height: (root.localSeeking || root.seeking) ? 6 : (2 + 2 * root.pTimeline)
            radius: height / 2
            color: root.trackColor

            Rectangle {
                id: progressFill
                width: parent.width * root.safeProgress
                height: parent.height
                radius: parent.radius
                color: root.progressFillColor

                Behavior on width {
                    enabled: !root.localSeeking && !root.seeking
                    NumberAnimation {
                        duration: root.progressDurationMs
                        easing.type: IslandMotion.overlayProgressEasing
                    }
                }
            }
        }

        Text {
            anchors {
                left: parent.left
                bottom: parent.bottom
            }
            text: root.formatTime(root.displayPosition)
            color: root.textSecondary
            font.pixelSize: 10
            font.letterSpacing: 0
            opacity: root.pTimeline
            horizontalAlignment: Text.AlignLeft
        }

        Text {
            anchors {
                right: parent.right
                bottom: parent.bottom
            }
            text: root.durationSupported || root.duration > 0
                  ? root.formatTime(root.duration)
                  : "--:--"
            color: root.textSecondary
            font.pixelSize: 10
            font.letterSpacing: 0
            opacity: root.pTimeline
            horizontalAlignment: Text.AlignRight
        }

        MouseArea {
            id: seekArea
            anchors.fill: parent
            enabled: root.scrubInteractive
            preventStealing: true
            hoverEnabled: false
            cursorShape: root.scrubInteractive ? Qt.PointingHandCursor : Qt.ArrowCursor

            function ratioAt(mx) {
                var w = Math.max(1, progressTrack.width);
                var x = Math.max(0, Math.min(w, mx - progressTrack.x));
                return Math.max(0, Math.min(1, x / w));
            }

            function beginSeek(mx) {
                if (!root.scrubInteractive)
                    return;
                var r = ratioAt(mx);
                root.localSeeking = true;
                root.localSeekRatio = r;
                root.seekBeginRequested();
                root.controlPressed();
                root.seekPreviewRequested(r);
            }

            function moveSeek(mx) {
                if (!root.localSeeking)
                    return;
                var r = ratioAt(mx);
                root.localSeekRatio = r;
                root.seekPreviewRequested(r);
            }

            function endSeek(commit) {
                if (!root.localSeeking)
                    return;
                var r = root.localSeekRatio;
                root.localSeeking = false;
                if (commit)
                    root.seekCommitRequested(r);
                else
                    root.seekCancelRequested();
                root.controlReleased();
            }

            onPressed: function(mouse) {
                beginSeek(mouse.x);
                mouse.accepted = true;
            }
            onPositionChanged: function(mouse) {
                if (!pressed)
                    return;
                moveSeek(mouse.x);
                mouse.accepted = true;
            }
            onReleased: function(mouse) {
                endSeek(true);
                mouse.accepted = true;
            }
            onCanceled: {
                endSeek(false);
            }
        }

        Connections {
            target: root
            function onVisibleChanged() {
                if (!root.visible && root.localSeeking)
                    seekArea.endSeek(false);
            }
            function onCanSeekChanged() {
                if (!root.canSeek && root.localSeeking)
                    seekArea.endSeek(false);
            }
            function onExpandProgressChanged() {
                if (root.pTimeline < 0.8 && root.localSeeking)
                    seekArea.endSeek(false);
            }
        }

        Component.onDestruction: {
            if (root.localSeeking)
                seekArea.endSeek(false);
        }
    }

    // ---- Transport: scales + fades in late so buttons never hard-pop ----
    Item {
        id: controlRow
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            bottomMargin: 4 + 6 * root.pControls
        }
        height: root.controlHit
        opacity: root.pControls
        visible: opacity > 0.02
        // Keep hits off until mostly revealed (avoids mid-morph mis-taps).
        enabled: root.pControls > 0.55
        transform: Translate {
            y: (1.0 - root.pControls) * 10
        }
        scale: 0.88 + 0.12 * root.pControls
        transformOrigin: Item.Bottom

        Row {
            anchors.centerIn: parent
            spacing: 18

            MediaControlButton {
                size: root.skipSize
                hit: root.controlHit
                controlEnabled: root.canPrev
                role: "prev"
                primaryColor: root.textPrimary
                accentColor: root.accentColor
                filled: false
                onPressed: {
                    root.controlPressed();
                    if (root.canPrev)
                        root.previousRequested();
                }
                onReleased: root.controlReleased()
                onCanceled: root.controlReleased()
            }

            MediaControlButton {
                size: root.playSize
                hit: root.controlHit
                controlEnabled: root.canPlayPause
                role: root.isPlaying ? "pause" : "play"
                primaryColor: "#ffffff"
                accentColor: root.accentColor
                filled: true
                onPressed: {
                    root.controlPressed();
                    if (root.canPlayPause)
                        root.playPauseRequested();
                }
                onReleased: root.controlReleased()
                onCanceled: root.controlReleased()
            }

            MediaControlButton {
                size: root.skipSize
                hit: root.controlHit
                controlEnabled: root.canNext
                role: "next"
                primaryColor: root.textPrimary
                accentColor: root.accentColor
                filled: false
                onPressed: {
                    root.controlPressed();
                    if (root.canNext)
                        root.nextRequested();
                }
                onReleased: root.controlReleased()
                onCanceled: root.controlReleased()
            }
        }
    }

    component MediaControlButton: Item {
        id: btn
        property int size: 32
        property int hit: 44
        property bool controlEnabled: true
        property string role: "play"
        property color primaryColor: "#ffffff"
        property color accentColor: "#0a84ff"
        property bool filled: false
        property real pressScale: 0.92
        property bool interactionActive: false
        signal pressed()
        signal released()
        signal canceled()

        width: hit
        height: hit
        scale: interactionActive ? pressScale : 1

        Behavior on scale {
            NumberAnimation {
                duration: root.reducedMotion ? 0 : IslandMotion.v2ReducedContentMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }

        function beginInteraction() {
            if (!btn.controlEnabled || !btn.visible || !root.visible || btn.interactionActive)
                return false;
            if (!controlRow.enabled)
                return false;
            btn.interactionActive = true;
            btn.pressed();
            return true;
        }

        function endInteraction(canceled) {
            if (!btn.interactionActive)
                return;
            btn.interactionActive = false;
            if (canceled)
                btn.canceled();
            else
                btn.released();
        }

        onControlEnabledChanged: {
            if (!btn.controlEnabled)
                btn.endInteraction(true);
        }

        Connections {
            target: root
            function onVisibleChanged() {
                if (!root.visible)
                    btn.endInteraction(true);
            }
            function onExpandProgressChanged() {
                if (root.pControls < 0.5)
                    btn.endInteraction(true);
            }
        }

        Component.onDestruction: {
            btn.endInteraction(true);
        }

        Rectangle {
            anchors.centerIn: parent
            width: btn.size
            height: btn.size
            radius: btn.size / 2
            color: btn.filled
                   ? (btn.controlEnabled
                      ? btn.accentColor
                      : Qt.rgba(btn.accentColor.r, btn.accentColor.g, btn.accentColor.b, 0.35))
                   : "transparent"
            opacity: btn.controlEnabled ? 1 : 0.45

            TahoeSymbol {
                anchors.centerIn: parent
                name: {
                    if (btn.role === "prev")
                        return "\ue045";
                    if (btn.role === "next")
                        return "\ue044";
                    if (btn.role === "pause")
                        return "\ue034";
                    return "\ue037";
                }
                color: btn.filled
                       ? btn.primaryColor
                       : (btn.controlEnabled ? btn.primaryColor : "#555560")
                size: btn.filled ? 20 : 18
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            enabled: true
            preventStealing: true
            cursorShape: btn.controlEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPressed: function(mouseEvent) {
                btn.beginInteraction();
                mouseEvent.accepted = true;
            }
            onReleased: function(mouseEvent) {
                btn.endInteraction(false);
                mouseEvent.accepted = true;
            }
            onCanceled: {
                btn.endInteraction(true);
            }
        }
    }
}
