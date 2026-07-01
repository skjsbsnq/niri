pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: box

    property var theme
    property string title: ""
    property string subtitle: ""
    default property alias contentData: rows.data

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color sectionFill: theme ? theme.sectionFill : "#24ffffff"
    readonly property color sectionStroke: theme ? theme.sectionStroke : "#38ffffff"

    Layout.fillWidth: true
    implicitHeight: visible ? rows.implicitHeight + 26 : 0
    radius: 8
    color: box.sectionFill
    border.color: box.sectionStroke
    border.width: 1

    ColumnLayout {
        id: rows
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: box.title
                    color: box.textPrimary
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: box.subtitle
                    color: box.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    visible: text.length > 0
                }
            }
        }
    }
}
