pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    property var toplevel
    readonly property bool hasWindow: !!toplevel

    implicitWidth: controlsRow.implicitWidth
    implicitHeight: 22
    opacity: hasWindow ? 1 : 0.35

    function closeWindow() {
        if (toplevel && toplevel.close)
            toplevel.close();
    }

    function minimizeWindow() {
        if (toplevel)
            toplevel.minimized = true;
    }

    function toggleMaximizeWindow() {
        if (toplevel)
            toplevel.maximized = !toplevel.maximized;
    }

    Row {
        id: controlsRow

        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        ControlButton {
            fill: "#ff5f57"
            stroke: "#d94b43"
            enabled: root.hasWindow
            onActivated: root.closeWindow()
        }

        ControlButton {
            fill: "#ffbd2e"
            stroke: "#d99a1e"
            enabled: root.hasWindow
            onActivated: root.minimizeWindow()
        }

        ControlButton {
            fill: "#28c840"
            stroke: "#21a833"
            enabled: root.hasWindow
            onActivated: root.toggleMaximizeWindow()
        }
    }

    component ControlButton: Item {
        id: button

        property color fill
        property color stroke
        signal activated()

        width: 13
        height: 13

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: button.enabled ? button.fill : "#6fffffff"
            border.color: button.enabled ? button.stroke : "#40ffffff"
            border.width: 1
            opacity: mouse.containsMouse ? 0.86 : 1
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            enabled: button.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.activated()
        }
    }
}
