pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// Quiet PreferencesGroup-style card: solid-ish fill, thin hairline, no glass stack.
Rectangle {
    id: box

    property var theme
    property string title: ""
    property string subtitle: ""
    default property alias contentData: rows.data

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color textMuted: theme ? theme.textMuted : "#5f6870"
    readonly property color sectionFill: theme ? theme.sectionFill : "#ffffffff"
    readonly property color sectionStroke: theme ? theme.sectionStroke : "#14000000"

    Layout.fillWidth: true
    implicitHeight: visible ? rows.implicitHeight + (box.title.length > 0 || box.subtitle.length > 0 ? 22 : 8) : 0
    radius: 10
    color: box.sectionFill
    border.color: box.sectionStroke
    border.width: 1
    clip: true

    ColumnLayout {
        id: rows
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: box.title.length > 0 || box.subtitle.length > 0 ? 10 : 2
        anchors.bottomMargin: 2
        spacing: 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.bottomMargin: 6
            spacing: 2
            visible: box.title.length > 0 || box.subtitle.length > 0

            Text {
                Layout.fillWidth: true
                text: box.title
                color: box.textMuted
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                visible: text.length > 0
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
