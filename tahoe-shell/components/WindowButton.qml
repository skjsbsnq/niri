pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property var toplevel
    property var appsService
    property bool showTitle: true
    property int iconSize: 38
    readonly property bool active: !!toplevel && toplevel.activated
    readonly property bool minimized: !!toplevel && toplevel.minimized
    readonly property string label: appsService ? appsService.toplevelLabel(toplevel) : String(toplevel ? toplevel.title || toplevel.appId || "Window" : "Window")

    signal activateRequested(var toplevel)

    width: showTitle ? 132 : 56
    height: 58

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 16
        color: root.active ? "#70ffffff" : root.minimized ? "#24ffffff" : "transparent"
        border.color: root.active ? "#66ffffff" : "transparent"
        border.width: 1
    }

    Image {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: root.showTitle ? 9 : Math.round((parent.width - width) / 2)
        anchors.verticalCenter: parent.verticalCenter
        width: root.iconSize
        height: root.iconSize
        source: root.appsService ? root.appsService.iconForToplevel(root.toplevel) : ""
        fillMode: Image.PreserveAspectFit
        smooth: true
        opacity: root.minimized ? 0.58 : 1.0
    }

    Text {
        anchors.left: icon.right
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showTitle
        text: root.label
        color: root.minimized ? "#7b818a" : "#202124"
        font.pixelSize: 11
        elide: Text.ElideRight
        maximumLineCount: 1
        verticalAlignment: Text.AlignVCenter
    }

    Rectangle {
        anchors.horizontalCenter: icon.horizontalCenter
        anchors.bottom: parent.bottom
        width: root.active ? 16 : root.minimized ? 4 : 6
        height: 4
        radius: 2
        color: root.active ? "#202124" : root.minimized ? "#7b818a" : "#99000000"
        opacity: root.toplevel ? 1 : 0
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.toplevel && root.toplevel.minimized) {
                root.toplevel.minimized = false;
            } else if (root.toplevel && root.toplevel.activate) {
                root.toplevel.activate();
            }
            root.activateRequested(root.toplevel);
        }
    }
}
