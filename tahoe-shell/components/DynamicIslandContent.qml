pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion

Item {
    id: root
    clip: true

    property string islandState: "resting_time"
    property string displayText: ""
    property string secondaryText: ""
    property string iconCode: ""
    property real progress: -1
    property bool compactResting: true
    property bool compactContentVisible: compactResting
    property bool mediaExpandedContentVisible: mediaExpanded
    property bool summaryExpandedContentVisible: summaryExpanded
   property bool showSecondaryText: false
   property color textPrimary: "#f7f9fc"
   property color textSecondary: "#b9c0cc"
    property string mediaArtUrl: ""
    property string mediaTrackTitle: ""
    property string mediaTrackArtist: ""
    property bool mediaPlaying: false
    property real mediaPosition: 0
    property real mediaLength: 0
    property real mediaProgress: 0
    property bool mediaPositionSupported: false
    property bool mediaLengthSupported: false
    property bool canPlayPause: false
    property bool canPrev: false
   property bool canNext: false
    signal mediaPreviousRequested()
    signal mediaPlayPauseRequested()
    signal mediaNextRequested()
    signal mediaControlPressed()
    property int summaryBatteryPercent: 0
    property bool summaryBatteryCharging: false
    property real summaryVolume: 0
    property bool summaryMuted: false
    property real summaryBrightness: 0
    property bool summaryBrightnessAvailable: false
    property string summaryWorkspaceLabel: ""
   readonly property bool mediaExpanded: islandState === "expanded_media"
    readonly property bool summaryExpanded: islandState === "expanded_summary"

   readonly property bool notificationActive: islandState === "transient_notification"
    readonly property bool standardDetailActive: !compactResting && !notificationActive && !osdActive && !mediaExpanded && !summaryExpanded
   readonly property bool osdActive: islandState === "transient_osd"
    readonly property bool showOsRing: osdActive && safeProgress(progress) >= 0
   readonly property int notificationFadeInDuration: 280
   readonly property int notificationFadeOutDuration: 140

    function safeProgress(value) {
        var number = Number(value);
        if (!isFinite(number) || number < 0)
            return -1;

        return Math.max(0, Math.min(1, number));
    }

    Text {
        id: compactLabel

        anchors.centerIn: parent
        width: parent.width - 32
        text: root.compactResting ? root.displayText : ""
        color: root.textPrimary
        font.pixelSize: root.islandState === "resting_time" ? 13 : 12
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        maximumLineCount: 1
        opacity: root.compactContentVisible ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.overlayContentDuration; easing.type: IslandMotion.overlayColorEasing }
        }
    }

    Row {
        id: detailRow

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: root.islandState.indexOf("expanded_") === 0 ? 24 : 16
            rightMargin: root.islandState.indexOf("expanded_") === 0 ? 24 : 16
        }
        height: Math.min(parent.height - 16, 52)
        spacing: 10
        opacity: root.standardDetailActive ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.overlayContentDuration; easing.type: IslandMotion.overlayColorEasing }
        }

        TahoeSymbol {
            name: root.iconCode
            color: root.textPrimary
            size: 20
        }

        Item {
            width: Math.max(1, parent.width - 34)
            height: parent.height

            Text {
                id: detailPrimary

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: root.showSecondaryText ? 4 : 0
                }
                text: root.displayText
                color: root.textPrimary
                font.pixelSize: root.islandState.indexOf("expanded_") === 0 ? 17 : 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: detailPrimary.bottom
                    topMargin: 2
                }
                text: root.secondaryText
                color: root.textSecondary
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: root.showSecondaryText
            }
        }
    }

    Row {
        id: notificationRow

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 16
            rightMargin: 18
        }
        height: Math.min(parent.height - 14, 42)
        spacing: 10
        opacity: root.notificationActive ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: root.notificationActive ? root.notificationFadeInDuration : root.notificationFadeOutDuration
                easing.type: IslandMotion.overlayColorEasing
            }
        }

        TahoeSymbol {
            name: root.iconCode.length > 0 ? root.iconCode : "\ue7f4"
            color: root.textPrimary
            size: 20
        }

        Item {
            width: Math.max(1, parent.width - 34)
            height: parent.height

            Text {
                id: notificationTitle

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: root.secondaryText.length > 0 ? 3 : Math.round((parent.height - height) / 2)
                }
                text: root.displayText
                color: root.textPrimary
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: notificationTitle.bottom
                    topMargin: 2
                }
                text: root.secondaryText
                color: root.textSecondary
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
               visible: text.length > 0
           }
       }
   }

    Row {
        id: osdRow

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 18
            rightMargin: 18
        }
        height: Math.min(parent.height - 12, 36)
        spacing: 12
        opacity: root.showOsRing ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.overlayContentDuration; easing.type: IslandMotion.overlayColorEasing }
        }

        TahoeSymbol {
            name: root.iconCode.length > 0 ? root.iconCode : "\ue050"
            color: root.textPrimary
            size: 20
        }

        Item {
            width: Math.max(1, parent.width - 22 - 34)
            height: parent.height

            Text {
                anchors.fill: parent
                text: root.secondaryText.length > 0 ? root.secondaryText : ""
                color: root.textPrimary
                font.pixelSize: 20
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Item {
            width: 30
            height: 30
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.centerIn: parent
                width: 22
                height: 22
                radius: 11
                color: "#111418"
                border.color: "#1f1f1f"
                border.width: 1
            }

            Canvas {
                anchors.fill: parent
                antialiasing: true
                property real progressValue: root.safeProgress(root.progress)

                onProgressValueChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d");
                    var size = Math.min(width, height);
                    var lineWidth = 3.5;
                    var center = size / 2;
                    var radius = (size - lineWidth) / 2 - 0.5;
                    var startAngle = -Math.PI / 2;
                    var endAngle = startAngle + (Math.PI * 2 * progressValue);

                    ctx.clearRect(0, 0, width, height);
                    ctx.lineCap = "round";
                    ctx.lineWidth = lineWidth;

                    ctx.strokeStyle = "rgba(255, 255, 255, 0.16)";
                    ctx.beginPath();
                    ctx.arc(center, center, Math.max(1, radius), 0, Math.PI * 2, false);
                    ctx.stroke();

                    if (progressValue > 0) {
                        ctx.strokeStyle = "#ffffff";
                        ctx.beginPath();
                        ctx.arc(center, center, Math.max(1, radius), startAngle, endAngle, false);
                        ctx.stroke();
                    }
               }
           }
       }
   }

    DynamicIslandMediaView {
        id: mediaView

        anchors.fill: parent
        artUrl: root.mediaArtUrl
        trackTitle: root.mediaTrackTitle
        trackArtist: root.mediaTrackArtist
        isPlaying: root.mediaPlaying
        position: root.mediaPosition
        duration: root.mediaLength
        progress: root.mediaProgress
        positionSupported: root.mediaPositionSupported
        durationSupported: root.mediaLengthSupported
        canPlayPause: root.canPlayPause
        canPrev: root.canPrev
        canNext: root.canNext
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        opacity: root.mediaExpandedContentVisible ? 1 : 0
        visible: opacity > 0.01
        onPreviousRequested: root.mediaPreviousRequested()
        onPlayPauseRequested: root.mediaPlayPauseRequested()
        onNextRequested: root.mediaNextRequested()
        onControlPressed: root.mediaControlPressed()

        Behavior on opacity {
            NumberAnimation {
                duration: root.mediaExpandedContentVisible
                    ? IslandMotion.overlayExpandedEnterFadeMs
                    : IslandMotion.overlayExpandedExitFadeMs
                easing.type: IslandMotion.overlayColorEasing
            }
        }
    }

    DynamicIslandSummaryView {
        id: summaryView

        anchors.fill: parent
        batteryPercent: root.summaryBatteryPercent
        batteryCharging: root.summaryBatteryCharging
        volume: root.summaryVolume
        muted: root.summaryMuted
        brightness: root.summaryBrightness
        brightnessAvailable: root.summaryBrightnessAvailable
        workspaceLabel: root.summaryWorkspaceLabel
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        opacity: root.summaryExpandedContentVisible ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: root.summaryExpandedContentVisible
                    ? IslandMotion.overlayExpandedEnterFadeMs
                    : IslandMotion.overlayExpandedExitFadeMs
                easing.type: IslandMotion.overlayColorEasing
            }
        }
    }

    Rectangle {
        id: progressTrack

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 18
            rightMargin: 18
            bottomMargin: 8
        }
        height: 3
        radius: 2
       color: "#28ffffff"
        opacity: (root.safeProgress(root.progress) >= 0 && !root.showOsRing) ? 1 : 0
       visible: opacity > 0.01

        Rectangle {
            width: parent.width * Math.max(0, root.safeProgress(root.progress))
            height: parent.height
            radius: parent.radius
            color: "#f0ffffff"

            Behavior on width {
                NumberAnimation { duration: IslandMotion.overlayProgressDuration; easing.type: IslandMotion.overlayProgressEasing }
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.overlayContentDuration; easing.type: IslandMotion.overlayColorEasing }
        }
    }
}
