pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion
import "settings/SettingsTheme.js" as Theme

// V2 OSD scene (T13): icon + horizontal progress + exact value.
// Volume, muted, and brightness share this layout. Continuous progress
// updates animate the bar only — no full content re-enter.
Item {
    id: root

    property string iconCode: "\ue050"
    property string valueText: ""
    property real progress: 0
    property bool muted: false
    property bool darkMode: true
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color accentColor: Theme.accent(darkMode, "blue")
    property color trackColor: "#30ffffff"

    readonly property real clampedProgress: {
        var number = Number(root.progress);
        if (!isFinite(number))
            return 0;
        return Math.max(0, Math.min(1, number));
    }
    readonly property real barProgress: root.muted ? 0 : root.clampedProgress

    Row {
        id: osdRow
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 12

        Item {
            width: 20
            height: parent.height

            TahoeSymbol {
                anchors.centerIn: parent
                name: root.iconCode.length > 0 ? root.iconCode : "\ue050"
                color: root.textPrimary
                size: 20
            }
        }

        Item {
            // Fit mid-band capsule 230: 14+20+12+118+12+40+14 = 230.
            // Design band still 112–128.
            width: 118
            height: parent.height

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: root.trackColor

                Rectangle {
                    id: fill
                    width: parent.width * root.barProgress
                    height: parent.height
                    radius: parent.radius
                    // Neutral accent for volume/brightness; muted stays neutral (not danger red).
                    color: root.muted ? "#70ffffff" : root.accentColor

                    Behavior on width {
                        NumberAnimation {
                            duration: IslandMotion.overlayProgressDuration
                            easing.type: IslandMotion.overlayProgressEasing
                        }
                    }
                }
            }
        }

        Text {
            id: valueLabel
            width: 40
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            text: root.muted
                  ? (root.valueText.length > 0 ? root.valueText : "静音")
                  : (root.valueText.length > 0
                     ? root.valueText
                     : String(Math.round(root.clampedProgress * 100)))
            color: root.textPrimary
            font.pixelSize: 14
            font.weight: Font.DemiBold
            font.letterSpacing: 0
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
