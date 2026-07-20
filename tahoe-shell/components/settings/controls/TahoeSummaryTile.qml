pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."

// Navigation tile for hubs. Uses neutral symbolic icon color (system list feel)
// rather than per-category brand rainbows. accentColor is kept for API stability.
Item {
    id: tile

    property var theme
    property string iconCode: ""
    property string title: ""
    property string detail: ""
    property color accentColor: theme ? theme.textSecondary : "#636366"

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color tileFill: theme ? theme.tileFill : "#30ffffff"
    readonly property color tileFillHover: theme ? theme.tileFillHover : "#4cffffff"
    readonly property color tileStroke: theme ? theme.tileStroke : "#42ffffff"
    readonly property color tileStrokeHover: theme ? theme.tileStrokeHover : "#66ffffff"
    readonly property color iconTint: theme ? theme.textSecondary : "#636366"

    signal activated()

    Layout.preferredHeight: 72

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: tileMouse.containsMouse ? tile.tileFillHover : tile.tileFill
        border.color: tileMouse.containsMouse ? tile.tileStrokeHover : tile.tileStroke
        border.width: 1
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        TahoeSymbol {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            name: tile.iconCode
            color: tile.iconTint
            size: 22
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: tile.title
                color: tile.textPrimary
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                Layout.fillWidth: true
                text: tile.detail
                color: tile.textSecondary
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
            }
        }

        TahoeSymbol {
            Layout.alignment: Qt.AlignVCenter
            name: "\ue5cc"
            color: tile.textSecondary
            size: 16
        }
    }

    MouseArea {
        id: tileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.activated()
    }
}
