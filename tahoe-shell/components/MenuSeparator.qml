pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// Shared menu separator — inset 1px rule, color matches T06 menu signature.
Item {
    id: root

    property bool darkMode: false

    readonly property color lineColor: darkMode ? "#1affffff" : "#1a000000"

    width: parent ? parent.width : 0
    height: 9
    implicitHeight: 9
    Layout.fillWidth: true
    Layout.preferredHeight: 9

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: root.lineColor
    }
}
