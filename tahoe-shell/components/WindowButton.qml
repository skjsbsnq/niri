pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    property var windowModel: null
    property var toplevel: windowModel ? windowModel.toplevel : null
    property var windowsService
    property var appsService
    property bool showTitle: true
    property int iconSize: 38
    // See Dock.qml useSpring. Spring on icon geometry corrupts the Image
    // texture on VMware/software GPUs. Dock forwards its own useSpring here.
    property bool useSpring: false
    // Magnification is fed in by the Dock (proximityScale of the pointer).
    // The SpringAnimation Behavior below eases it toward the target so the
    // running-window half of the dock waves together with the pinned half.
    property real magnification: 1.0
    property real bounceOffset: 0
    property var dockWindow
    property var dockSurfaceItem
    readonly property bool hovered: windowMouse.containsMouse
    readonly property bool active: windowModel ? !!windowModel.isFocused : !!(toplevel && toplevel.activated)
    readonly property bool minimized: windowModel ? !!windowModel.isMinimized : !!(toplevel && toplevel.minimized)
    readonly property string label: appsService ? appsService.toplevelLabel(windowModel || toplevel) : String((windowModel || toplevel) ? (windowModel || toplevel).title || (windowModel || toplevel).appId || "窗口" : "窗口")
    readonly property bool showHoverLabel: !showTitle && hovered && label.length > 0
    readonly property real lift: (magnification - 1.0) * 20

    signal activateRequested(var toplevel)
    signal contextMenuRequested(var window)
    signal dockPointerMoved(real x, int buttons)
    signal dockPointerEntered()
    signal dockPointerExited()

    // Fixed width. Must NOT depend on magnification — WindowButton is fed
    // into Dock's proximityScale() which reads its geometry, so a
    // magnification-driven width is a binding loop that crashes Quickshell
    // (same trap as the pinned-icon delegate; see Dock.qml). The wave feel
    // comes from the icon scale + lift spring, not from reflowing the Row.
    width: showTitle ? 132 : 56
    height: 58

    function updateDockRectangle(mouseX, mouseY) {
        if (!root.dockWindow)
            return;

        var point = root.mapToItem(null, 0, 0);
        if (root.windowsService && root.windowModel) {
            root.windowsService.setRectangle(
                root.windowModel,
                root.dockWindow,
                Math.round(point.x),
                Math.round(point.y),
                Math.round(root.width),
                Math.round(root.height)
            );
        } else if (root.toplevel && root.toplevel.setRectangle) {
            root.toplevel.setRectangle(root.dockWindow, Qt.rect(Math.round(point.x), Math.round(point.y), Math.round(root.width), Math.round(root.height)));
        }
    }

    function scheduleDockRectangleUpdate() {
        dockRectangleRefresh.restart();
    }

    function restoreOrActivate() {
        if (!root.windowModel && !root.toplevel)
            return;

        updateDockRectangle(0, 0);

        if (root.windowsService && root.windowModel) {
            if (root.windowModel.isMinimized) {
                root.windowsService.restore(root.windowModel);
            } else if (root.windowModel.isFocused) {
                root.windowsService.minimize(root.windowModel);
            } else {
                root.windowsService.activate(root.windowModel);
            }
        } else if (root.toplevel.minimized) {
            root.toplevel.minimized = false;
            if (root.toplevel.activate)
                root.toplevel.activate();
        } else if (root.toplevel.activated) {
            root.toplevel.minimized = true;
        } else if (root.toplevel.activate) {
            root.toplevel.activate();
        }

        root.activateRequested(root.windowModel || root.toplevel);
    }

    function minimize() {
        if (!root.windowModel && !root.toplevel)
            return;

        updateDockRectangle(0, 0);
        if (root.windowsService && root.windowModel)
            root.windowsService.minimize(root.windowModel);
        else
            root.toplevel.minimized = true;
        root.activateRequested(root.windowModel || root.toplevel);
    }

    onXChanged: scheduleDockRectangleUpdate()
    onYChanged: scheduleDockRectangleUpdate()
    onWidthChanged: scheduleDockRectangleUpdate()
    onHeightChanged: scheduleDockRectangleUpdate()
    onDockWindowChanged: scheduleDockRectangleUpdate()
    onWindowModelChanged: scheduleDockRectangleUpdate()
    onToplevelChanged: scheduleDockRectangleUpdate()
    Component.onCompleted: scheduleDockRectangleUpdate()

    Timer {
        id: dockRectangleRefresh
        interval: 0
        repeat: false
        onTriggered: root.updateDockRectangle(0, 0)
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
        source: root.appsService ? root.appsService.iconForToplevel(root.windowModel || root.toplevel) : ""
        fillMode: Image.PreserveAspectFit
        smooth: true
        opacity: root.minimized ? 0.58 : 1.0
        transformOrigin: Item.Center
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
        opacity: (root.windowModel || root.toplevel) ? 1 : 0
    }

    Rectangle {
        id: hoverLabel

        anchors.horizontalCenter: icon.horizontalCenter
        z: 10
        y: root.showHoverLabel ? -30 : -20
        width: Math.max(hoverLabelText.implicitWidth + 18, 48)
        height: 24
        radius: 7
        color: "#d9f7f8fb"
        border.color: "#70ffffff"
        opacity: root.showHoverLabel ? 1 : 0
        visible: opacity > 0.01

        Text {
            id: hoverLabelText

            anchors.centerIn: parent
            text: root.label
            color: "#202124"
            font.pixelSize: 11
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: windowMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) {
            if (root.dockSurfaceItem) {
                var point = root.mapToItem(root.dockSurfaceItem, mouse.x, mouse.y);
                root.dockPointerMoved(point.x, mouse.buttons);
            }
        }
        onEntered: root.dockPointerEntered()
        onExited: root.dockPointerExited()
        onClicked: function(mouse) {
            root.bounce();
            if (mouse.button === Qt.RightButton) {
                root.contextMenuRequested(root.windowModel || root.toplevel);
            } else if (mouse.button === Qt.MiddleButton) {
                root.minimize();
            } else {
                root.restoreOrActivate();
            }
        }
    }

    // Spring bounce on click — kick bounceOffset to an overshoot then let
    // the underdamped spring below settle it (1.5 oscillations), matching
    // the Dock and real macOS. A single-shot Timer does the kick→release
    // so the Behavior spring sees a real property change (setting to 14
    // then 0 in the same JS frame would coalesce and never animate).
    Timer {
        id: bounceTimer
        interval: 16
        repeat: false
        onTriggered: root.bounceOffset = 0
    }

    function bounce() {
        // Disable the Behavior momentarily is unnecessary: jumping to 14
        // then back to 0 in two steps gives the spring a target to chase.
        root.bounceOffset = 14;
        bounceTimer.restart();
    }

    // Bounce on click. Spring (underdamped) on real GPUs, gated by useSpring
    // because springing the icon Image's geometry corrupts its texture on
    // VMware/software GPUs. NumberAnimation is the safe default.
    Behavior on bounceOffset {
        enabled: !root.useSpring
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
    Behavior on bounceOffset {
        enabled: root.useSpring
        SpringAnimation {
            spring: 380
            damping: 0.32
            mass: 0.9
            epsilon: 0.01
        }
    }

    // Magnification easing so the running-window half of the dock waves with
    // the pinned half. Same useSpring gate as bounce.
    Behavior on magnification {
        enabled: !root.useSpring
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }
    Behavior on magnification {
        enabled: root.useSpring
        SpringAnimation {
            spring: 260
            damping: 1.0
            epsilon: 0.01
        }
    }
}
