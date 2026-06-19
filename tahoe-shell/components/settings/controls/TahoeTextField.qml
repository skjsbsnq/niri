pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: field

    property var theme
    property alias text: input.text

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"

    signal editingFinished()

    Layout.preferredWidth: 270
    Layout.preferredHeight: 30
    radius: 10
    color: "#48ffffff"
    border.color: "#4cffffff"

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        text: ""
        color: field.textPrimary
        selectionColor: "#7ab7ff"
        selectedTextColor: "#ffffff"
        font.pixelSize: 12
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        onEditingFinished: field.editingFinished()
    }
}
