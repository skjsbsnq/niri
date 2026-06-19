pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: row

    property var theme
    property var item

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color rowFill: theme ? theme.rowFill : "#28ffffff"
    readonly property color rowStroke: theme ? theme.rowStroke : "#32ffffff"

    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(54, aboutContent.implicitHeight + 16)

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: row.rowFill
        border.color: row.rowStroke
        border.width: 1
    }

    RowLayout {
        id: aboutContent
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12

        Text {
            Layout.preferredWidth: 150
            Layout.alignment: Qt.AlignVCenter
            text: row.item ? row.item.label : ""
            color: row.textSecondary
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: row.item ? row.item.value : ""
                color: row.textPrimary
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WrapAnywhere
            }

            Text {
                Layout.fillWidth: true
                text: row.item ? row.item.detail : ""
                color: row.textSecondary
                font.pixelSize: 10
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: text.length > 0
            }
        }
    }
}
