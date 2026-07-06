pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../Motion.js" as Motion

Item {
    id: sw

    property var theme
    property var settingsService
    property bool checked: false

    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
    readonly property color switchOff: theme ? theme.switchOff : "#2e000000"

    Layout.preferredWidth: 42
    Layout.preferredHeight: 24

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: sw.checked ? sw.accentBlue : sw.switchOff

        Rectangle {
            width: 20
            height: 20
            radius: 10
            x: sw.checked ? parent.width - width - 2 : 2
            anchors.verticalCenter: parent.verticalCenter
            color: "#ffffff"

            Behavior on x {
                NumberAnimation { duration: Motion.elementMove(sw.settingsService); easing.type: Motion.emphasizedDecel }
            }
        }
    }
}
