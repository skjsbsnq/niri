pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion
import "Motion.js" as Motion

// Expanded media controls rendered inside the island capsule. Mirrors the
// Tide expanded-player layout (art + title/artist + prev/play/next) using
// Tahoe's own MPRIS service. No scrubber in the first version.
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
    // Optional: when motion profile is reduced, freeze visualizer (no phase ticks).
    property var settingsService
    property color textPrimary: "#f7f9fc"
    property color textSecondary: "#b9c0cc"
    property color accent: "#b56cff"
    readonly property bool reducedMotion: Motion.reducedMotion(root.settingsService)
    signal previousRequested()
    signal playPauseRequested()
    signal nextRequested()
    signal controlPressed()
    signal controlReleased()

    readonly property int badgeSize: 56
    readonly property int controlSize: 26
    readonly property int controlHit: 44
    readonly property int fadeDuration: IslandMotion.overlayContentDuration + 90
    readonly property bool showArt: artUrl.length > 0
    readonly property real safeProgress: Math.max(0, Math.min(1, Number(progress) || 0))
    readonly property bool showTimeline: positionSupported || durationSupported || duration > 0

    // Visibility/opacity are owned by DynamicIslandContent (mediaExpandedContentVisible).
    // Do not force visible:true here — multi-screen Overlay instances must be able to
    // hide non-target MediaViews so visualizerTimer stops (Task 08).
    anchors.fill: parent

    Item {
        id: topRow

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 18
            rightMargin: 18
            topMargin: 18
        }
        height: root.badgeSize

        Rectangle {
            id: artBadge

            width: root.badgeSize
            height: root.badgeSize
            radius: 13
            color: "#2c2c2e"
            clip: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Image {
                anchors.fill: parent
                source: root.artUrl
                fillMode: Image.PreserveAspectCrop
                visible: root.showArt
                sourceSize: Qt.size(112, 112)
                asynchronous: true
            }

            TahoeSymbol {
                anchors.centerIn: parent
                name: "\ue405" // music_note
                color: root.textSecondary
                size: 26
                visible: !root.showArt
            }
        }

        Column {
            anchors {
                left: artBadge.right
                leftMargin: 14
                right: visualizerBox.left
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            spacing: 4

            Text {
                width: parent.width
                text: root.trackTitle.length > 0 ? root.trackTitle : "正在播放"
                color: root.textPrimary
                font.pixelSize: 15
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: root.trackArtist
                color: root.textSecondary
                font.pixelSize: 12
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: text.length > 0
            }
        }

        Item {
            id: visualizerBox
            width: 36
            height: 22
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }

            Row {
                anchors.centerIn: parent
                height: parent.height
                spacing: 3

                Repeater {
                    model: 5

                    delegate: Rectangle {
                        required property int index
                        width: 3
                        // Reduced motion: static paused silhouette even while playing.
                        height: (root.isPlaying && !root.reducedMotion)
                            ? 4 + (parent.height - 4) * root.visualizerLevel(index)
                            : 4 + (parent.height - 4) * root.pausedLevel(index)
                        radius: 1.5
                        color: (root.isPlaying && !root.reducedMotion) ? root.accent : "#5f4b72"
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on height {
                            NumberAnimation {
                                // Match visualizerTimer so playing bars settle before retarget.
                                // Reduced motion: zero duration (instant, no continuous work).
                                duration: root.reducedMotion
                                    ? 0
                                    : (root.isPlaying
                                        ? IslandMotion.visualizerPlayingDuration
                                        : IslandMotion.visualizerPausedDuration)
                                easing.type: IslandMotion.overlayColorEasing
                            }
                        }
                    }
                }
            }
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
            spacing: 40

            MediaControlButton {
                size: root.controlSize
                hit: root.controlHit
                controlEnabled: root.canPrev
                glyph: "prev"
                primaryColor: root.textPrimary
                onPressed: {
                    root.controlPressed();
                    if (root.canPrev)
                        root.previousRequested();
                }
                onReleased: root.controlReleased()
                onCanceled: root.controlReleased()
            }

            MediaControlButton {
                size: root.controlSize
                hit: root.controlHit
                controlEnabled: root.canPlayPause
                glyph: root.isPlaying ? "pause" : "play"
                primaryColor: root.textPrimary
                onPressed: {
                    root.controlPressed();
                    if (root.canPlayPause)
                        root.playPauseRequested();
                }
                onReleased: root.controlReleased()
                onCanceled: root.controlReleased()
            }

            MediaControlButton {
                size: root.controlSize
                hit: root.controlHit
                controlEnabled: root.canNext
                glyph: "next"
                primaryColor: root.textPrimary
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

    Item {
        id: timeline

        anchors {
            left: parent.left
            right: parent.right
            top: topRow.bottom
            topMargin: 8
            leftMargin: 22
            rightMargin: 22
        }
        height: 26
        opacity: root.showTimeline ? 1 : 0.45

        Row {
            id: timeRow
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: 12

            Text {
                width: parent.width / 2
                text: root.formatTime(root.positionSupported ? root.position : 0)
                color: root.textSecondary
                font.pixelSize: 10
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                width: parent.width / 2
                text: root.durationSupported || root.duration > 0 ? root.formatTime(root.duration) : "--:--"
                color: root.textSecondary
                font.pixelSize: 10
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
            }
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                bottomMargin: 2
            }
            height: 3
            radius: 2
            color: "#2fffffff"

            Rectangle {
                width: parent.width * root.safeProgress
                height: parent.height
                radius: parent.radius
                color: root.textPrimary

                Behavior on width {
                    NumberAnimation { duration: IslandMotion.overlayProgressDuration; easing.type: IslandMotion.overlayProgressEasing }
                }
            }
        }
    }

    // Single phase owner. Update interval equals playing bar animation duration
    // so each height Behavior can settle before the next target (Task 21).
    // Stops when paused, hidden, reduced motion, or not the active screen's
    // expanded media instance (Task 08 multi-screen gate via parent visible).
    Timer {
        id: visualizerTimer
        interval: IslandMotion.visualizerUpdateMs
        repeat: true
        running: root.isPlaying && root.visible && !root.reducedMotion
        onTriggered: root.visualizerPhase += IslandMotion.visualizerPhaseStep
    }

    property real visualizerPhase: 0

    function visualizerLevel(index) {
        var phase = root.visualizerPhase + index * 0.78;
        var primary = (Math.sin(phase) + 1) * 0.5;
        var secondary = (Math.sin(phase * 2 + index * 0.95) + 1) * 0.5;
        return 0.22 + primary * 0.42 + secondary * 0.24;
    }

    function pausedLevel(index) {
        var levels = [0.34, 0.58, 0.82, 0.58, 0.34];
        return levels[index] || 0.4;
    }

    function formatTime(seconds) {
        var total = Math.max(0, Math.floor(Number(seconds) || 0));
        var minutes = Math.floor(total / 60);
        var secs = total % 60;
        return minutes + ":" + (secs < 10 ? "0" : "") + secs;
    }

    component MediaControlButton: Item {
        id: btn
        property int size: 26
        property int hit: 44
        property bool controlEnabled: true
        property string glyph: "play"
        property color primaryColor: "#ffffff"
        property real pressScale: 0.8
        // Tracks an in-flight pointer grab so release/cancel/destroy stay paired.
        property bool interactionActive: false
        signal pressed()
        signal released()
        signal canceled()

        width: hit
        height: hit
        scale: interactionActive ? pressScale : 1

        // Local exception: press feedback must be shorter than overlay content
        // fades; the component still reuses the Dynamic Island easing token.
        Behavior on scale {
            NumberAnimation { duration: 100; easing.type: IslandMotion.overlayColorEasing }
        }

        function beginInteraction() {
            // root.visible is the Content opacity gate; btn.visible is local.
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

        // Product collapse gates DynamicIslandMediaView via
        // `visible: opacity > 0.01` in Content — ancestor hide does not flip
        // the button's own `visible` property, so watch the media view root.
        Connections {
            target: root
            function onVisibleChanged() {
                if (!root.visible)
                    btn.endInteraction(true);
            }
        }

        Component.onDestruction: {
            // Destroy while grabbed must clear interacting via canceled.
            btn.endInteraction(true);
        }

        Canvas {
            anchors.centerIn: parent
            width: btn.size
            height: btn.size
            property string currentGlyph: btn.glyph
            property bool currentEnabled: btn.controlEnabled
            property color fillColor: btn.interactionActive ? "#8e8e93" : (btn.controlEnabled ? btn.primaryColor : "#555560")
            onCurrentGlyphChanged: requestPaint()
            onCurrentEnabledChanged: requestPaint()
            onFillColorChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = ctx.strokeStyle = fillColor;
                ctx.lineJoin = "round";
                ctx.lineWidth = 2;

                if (btn.glyph === "prev") {
                    ctx.beginPath();
                    ctx.rect(2, 4, 3, 18);
                    ctx.moveTo(13, 4);
                    ctx.lineTo(5, 13);
                    ctx.lineTo(13, 22);
                    ctx.closePath();
                    ctx.fill();
                    ctx.stroke();
                } else if (btn.glyph === "next") {
                    ctx.beginPath();
                    ctx.moveTo(4, 4);
                    ctx.lineTo(12, 13);
                    ctx.lineTo(4, 22);
                    ctx.closePath();
                    ctx.moveTo(13, 4);
                    ctx.lineTo(21, 13);
                    ctx.lineTo(13, 22);
                    ctx.closePath();
                    ctx.rect(21, 4, 3, 18);
                    ctx.fill();
                    ctx.stroke();
                } else if (btn.glyph === "pause") {
                    ctx.beginPath();
                    ctx.rect(6, 4, 5, 18);
                    ctx.rect(15, 4, 5, 18);
                    ctx.fill();
                } else {
                    ctx.beginPath();
                    ctx.moveTo(7, 4);
                    ctx.lineTo(22, 13);
                    ctx.lineTo(7, 22);
                    ctx.closePath();
                    ctx.fill();
                    ctx.stroke();
                }
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            // Always enabled so the hit rect absorbs presses when the control
            // is disabled (prevents fall-through to capsule click/swipe).
            // Actions and interacting still require controlEnabled via begin.
            enabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onPressed: function(mouseEvent) {
                // beginInteraction is a no-op when disabled; always accept so
                // the event does not fall through to the capsule MouseArea.
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
