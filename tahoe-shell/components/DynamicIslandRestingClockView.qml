pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion

// V2 resting clock (T12): localized weekday (secondary) + 24h time (primary).
// Content-driven width; Overlay clamps to v2ClockWidthMin/Max.
Item {
    id: root

    property string weekdayText: ""
    property string timeText: ""
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"

    // Measured text row only (caller adds horizontal padding for capsule width).
    readonly property int contentWidth: Math.ceil(clockRow.implicitWidth)
    readonly property int contentHeight: Math.ceil(Math.max(weekdayLabel.implicitHeight, timeLabel.implicitHeight))

    implicitWidth: contentWidth
    implicitHeight: Math.max(IslandMotion.v2ClockHeight, contentHeight)

    Row {
        id: clockRow
        anchors.centerIn: parent
        spacing: 9

        Text {
            id: weekdayLabel
            text: root.weekdayText
            color: root.textSecondary
            font.pixelSize: 13
            font.weight: Font.Normal
            font.letterSpacing: 0
            verticalAlignment: Text.AlignVCenter
            // System locale fonts; no dedicated UI face.
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Text {
            id: timeLabel
            text: root.timeText
            color: root.textPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.letterSpacing: 0
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
