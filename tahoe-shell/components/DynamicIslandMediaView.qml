pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion
import "Motion.js" as Motion

// V2 expanded media (T17): 64×64 art, 16px title / 12px artist, timeline,
// 36px accent play/pause + 32px prev/next (44px hit). TahoeSymbol only.
// No hand-drawn path glyphs, no fake sine spectrum, no album-art blur.
// Active player / capabilities come from Controls via DynamicIsland.
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
    // Interactive scrub only when Controls reports canSeek (MPRIS CanSeek +
    // position + length). Timeline remains painted when only position is known.
    property bool canSeek: false
    property bool seeking: false
    property var settingsService
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color accentColor: "#0a84ff"
    property color trackColor: "#30ffffff"
    // Progress rail fill is monochrome (islandProgressFill); accent is transport only.
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

    readonly property int badgeSize: 64
    readonly property int playSize: 36
    readonly property int skipSize: 32
    readonly property int controlHit: 44
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
    // Local scrub preview so the bar tracks the finger even before Controls
    // rebinds mediaProgress (and while width Behavior is disabled).
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
    readonly property bool scrubInteractive: root.canSeek && root.showTimeline && root.duration > 0
    readonly property int progressDurationMs: root.reducedMotion
        ? IslandMotion.v2ReducedContentMs
        : IslandMotion.overlayProgressDuration

    // Visibility/opacity owned by DynamicIslandContent (mediaExpandedContentVisible).
    anchors.fill: parent

    Item {
        id: topRow
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 16
            rightMargin: 16
            topMargin: 16
        }
        height: root.badgeSize

        Rectangle {
            id: artBadge
            width: root.badgeSize
            height: root.badgeSize
            radius: 12
            color: root.artFallbackFill
            clip: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            // Only load while this expanded scene is visible (hidden outputs stay cold).
            Image {
                id: artImage
                anchors.fill: parent
                source: (root.visible && root.showArt) ? root.safeArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                visible: root.showArt && status === Image.Ready
                sourceSize: Qt.size(128, 128)
                asynchronous: true
            }

            TahoeSymbol {
                anchors.centerIn: parent
                name: "\ue405" // music_note
                color: root.textSecondary
                size: 28
                visible: !artImage.visible
            }
        }

        Column {
            anchors {
                left: artBadge.right
                leftMargin: 14
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            spacing: 4

            Text {
                width: parent.width
                text: root.trackTitle.length > 0 ? root.trackTitle : "正在播放"
                color: root.textPrimary
                font.pixelSize: 16
                font.weight: Font.DemiBold
                font.letterSpacing: 0
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: root.trackArtist
                color: root.textSecondary
                font.pixelSize: 12
                font.letterSpacing: 0
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: text.length > 0
            }
        }
    }

    Item {
        id: timeline
        anchors {
            left: parent.left
            right: parent.right
            top: topRow.bottom
            topMargin: 12
            leftMargin: 16
            rightMargin: 16
        }
        // Full 22px hit band for scrub (paint is 4px). Prevents capsule
        // swipe/click from stealing mid-seek.
        height: 22
        opacity: root.showTimeline ? 1 : 0.45

        Rectangle {
            id: progressTrack
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            height: root.localSeeking || root.seeking ? 6 : 4
            radius: height / 2
            color: root.trackColor

            Behavior on height {
                NumberAnimation {
                    duration: root.reducedMotion ? 0 : IslandMotion.v2ReducedContentMs
                    easing.type: IslandMotion.v2ContentEasing
                }
            }

            Rectangle {
                id: progressFill
                width: parent.width * root.safeProgress
                height: parent.height
                radius: parent.radius
                color: root.progressFillColor

                Behavior on width {
                    // Disable follow animation while scrubbing so the bar is 1:1.
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
            horizontalAlignment: Text.AlignRight
        }

        MouseArea {
            id: seekArea
            anchors.fill: parent
            enabled: root.scrubInteractive && root.visible
            preventStealing: true
            hoverEnabled: false
            cursorShape: root.scrubInteractive ? Qt.PointingHandCursor : Qt.ArrowCursor

            function ratioAt(mx) {
                var w = Math.max(1, progressTrack.width);
                // Map into track coordinates (MouseArea fills timeline).
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
        }

        Component.onDestruction: {
            if (root.localSeeking)
                seekArea.endSeek(false);
        }
    }

    Item {
        id: controlRow
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            bottomMargin: 10
        }
        height: root.controlHit

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

    function formatTime(seconds) {
        var total = Math.max(0, Math.floor(Number(seconds) || 0));
        var minutes = Math.floor(total / 60);
        var secs = total % 60;
        return minutes + ":" + (secs < 10 ? "0" : "") + secs;
    }

    component MediaControlButton: Item {
        id: btn
        property int size: 32
        property int hit: 44
        property bool controlEnabled: true
        // "prev" | "play" | "pause" | "next"
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
                // Press feedback: shorter than content enter; still tokenized.
                duration: root.reducedMotion ? 0 : IslandMotion.v2ReducedContentMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }

        function beginInteraction() {
            if (!btn.controlEnabled || !btn.visible || !root.visible || btn.interactionActive)
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

            // Match ControlCenter + compact island media transport glyphs.
            TahoeSymbol {
                anchors.centerIn: parent
                name: {
                    if (btn.role === "prev")
                        return "\ue045";
                    if (btn.role === "next")
                        return "\ue044";
                    if (btn.role === "pause")
                        return "\ue034";
                    return "\ue037"; // play
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
            // Always enabled so the hit rect absorbs presses when disabled
            // (prevents fall-through to capsule click/swipe).
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
