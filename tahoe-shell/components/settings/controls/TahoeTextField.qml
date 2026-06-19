pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: field

    property var theme
    property alias text: input.text

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color fieldFill: theme ? theme.fieldFill : "#3fffffff"
    readonly property color fieldStroke: theme ? theme.fieldStroke : "#4cffffff"
    readonly property color fieldStrokeFocus: theme ? theme.fieldStrokeFocus : "#007ff7"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"

    signal editingFinished()

    Layout.preferredWidth: 270
    Layout.preferredHeight: 30
    radius: 8
    color: field.fieldFill
    border.color: input.activeFocus ? field.fieldStrokeFocus : field.fieldStroke
    border.width: input.activeFocus ? 2 : 1

    Behavior on border.width {
        NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        text: ""
        color: field.textPrimary
        selectionColor: field.accentBlue
        selectedTextColor: "#ffffff"
        font.pixelSize: 12
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        onEditingFinished: field.editingFinished()
    }
}
