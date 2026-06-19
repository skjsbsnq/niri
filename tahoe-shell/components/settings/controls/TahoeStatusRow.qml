pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: row

    property var theme
    property var item
    readonly property string statusState: item ? String(item.state || "info") : "info"
    readonly property string iconFont: theme ? theme.iconFont : "Material Icons"
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color textMuted: theme ? theme.textMuted : "#5f6870"
    readonly property color rowFill: theme ? theme.rowFill : "#28ffffff"
    readonly property color rowStroke: theme ? theme.rowStroke : "#32ffffff"

    function stateLabel(state) {
        return theme ? theme.stateLabel(state) : "信息";
    }

    function stateColor(state) {
        return theme ? theme.stateColor(state) : "#2c9cf2";
    }

    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(74, statusContent.implicitHeight + 18)

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: row.rowFill
        border.color: row.rowStroke
        border.width: 1
    }

    RowLayout {
        id: statusContent
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 11

        Rectangle {
            Layout.preferredWidth: 12
            Layout.preferredHeight: 12
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: row.stateColor(row.statusState)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: row.item ? row.item.title : ""
                    color: row.textPrimary
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    text: row.stateLabel(row.statusState)
                    color: row.stateColor(row.statusState)
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            Text {
                Layout.fillWidth: true
                text: row.item ? row.item.detail : ""
                color: row.textSecondary
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                Layout.fillWidth: true
                text: row.item ? row.item.impact : ""
                color: row.textMuted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                visible: text.length > 0
            }

            Text {
                Layout.fillWidth: true
                text: row.item ? row.item.action : ""
                color: "#ccff453a"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                visible: text.length > 0
            }
        }
    }
}
