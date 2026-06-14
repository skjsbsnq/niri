pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property var toplevel
    property var appsService
    property bool showTitle: true
    property int iconSize: 38
    property real magnification: 1.0
    property real bounceOffset: 0
    property var dockWindow
    property var dockSurfaceItem
    readonly property bool active: !!toplevel && toplevel.activated
    readonly property bool minimized: !!toplevel && toplevel.minimized
    readonly property string label: appsService ? appsService.toplevelLabel(toplevel) : String(toplevel ? toplevel.title || toplevel.appId || "Window" : "Window")
    readonly property real lift: (magnification - 1.0) * 16

    signal activateRequested(var toplevel)
    signal dockPointerMoved(real x)
    signal dockPointerEntered()

    width: showTitle ? 132 : 56
    height: 58

    function updateDockRectangle(mouseX, mouseY) {
        if (!root.toplevel || !root.toplevel.setRectangle || !root.dockWindow)
            return;

        var point = root.mapToItem(null, 0, 0);
        root.toplevel.setRectangle(root.dockWindow, Qt.rect(Math.round(point.x), Math.round(point.y), Math.round(root.width), Math.round(root.height)));
    }

    function restoreOrActivate() {
        if (!root.toplevel)
            return;

        updateDockRectangle(0, 0);

        if (root.toplevel.minimized) {
            root.toplevel.minimized = false;
            if (root.toplevel.activate)
                root.toplevel.activate();
        } else if (root.toplevel.activated) {
            root.toplevel.minimized = true;
        } else if (root.toplevel.activate) {
            root.toplevel.activate();
        }

        root.activateRequested(root.toplevel);
    }

    function minimize() {
        if (!root.toplevel)
            return;

        updateDockRectangle(0, 0);
        root.toplevel.minimized = true;
        root.activateRequested(root.toplevel);
    }

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
        x: root.showTitle ? 9 : Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2 - root.lift - root.bounceOffset)
        width: root.iconSize
        height: root.iconSize
        scale: root.magnification
        source: root.appsService ? root.appsService.iconForToplevel(root.toplevel) : ""
        fillMode: Image.PreserveAspectFit
        smooth: true
        opacity: root.minimized ? 0.58 : 1.0
        transformOrigin: Item.Center

        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
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
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) {
            if (root.dockSurfaceItem) {
                var point = root.mapToItem(root.dockSurfaceItem, mouse.x, mouse.y);
                root.dockPointerMoved(point.x);
            }
        }
        onEntered: root.dockPointerEntered()
        onClicked: function(mouse) {
            bounceAnimation.restart();
            if (mouse.button === Qt.MiddleButton)
                root.minimize();
            else
                root.restoreOrActivate();
        }
    }

    SequentialAnimation {
        id: bounceAnimation

        NumberAnimation {
            target: root
            property: "bounceOffset"
            to: 5
            duration: 70
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: root
            property: "bounceOffset"
            to: 0
            duration: 110
            easing.type: Easing.OutCubic
        }
    }
}
