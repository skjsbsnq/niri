pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: tile

    property var theme
    property string iconCode: ""
    property string title: ""
    property string detail: ""
    property color accentColor: theme ? theme.accentBlue : "#2c9cf2"

    readonly property string iconFont: theme ? theme.iconFont : "Material Icons"
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color tileFill: theme ? theme.tileFill : "#30ffffff"
    readonly property color tileFillHover: theme ? theme.tileFillHover : "#4cffffff"
    readonly property color tileStroke: theme ? theme.tileStroke : "#42ffffff"
    readonly property color tileStrokeHover: theme ? theme.tileStrokeHover : "#66ffffff"

    signal activated()

    Layout.preferredHeight: 86

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: tileMouse.containsMouse ? tile.tileFillHover : tile.tileFill
        border.color: tileMouse.containsMouse ? tile.tileStrokeHover : tile.tileStroke
        border.width: 1
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        Text {
            Layout.preferredWidth: 42
            Layout.preferredHeight: 42
            Layout.alignment: Qt.AlignVCenter
            text: tile.iconCode
            color: tile.accentColor
            font.family: tile.iconFont
            font.pixelSize: 24
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 3

            Text {
                Layout.fillWidth: true
                text: tile.title
                color: tile.textPrimary
                font.pixelSize: 14
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

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: "\ue5cc"
            color: tile.textSecondary
            font.family: tile.iconFont
            font.pixelSize: 18
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
