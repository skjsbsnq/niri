pragma ComponentBehavior: Bound

import QtQuick
import "Motion.js" as Motion

Item {
    id: root

    property var windowModel: null
    property var toplevel: windowModel ? windowModel.toplevel : null
    property var windowsService
    property var appsService
    property var settingsService
    property bool showTitle: true
    property int iconSize: 38
    // See Dock.qml useSpring. Spring on icon geometry corrupts the Image
    // texture on VMware/software GPUs. Dock forwards its own useSpring here.
    property bool useSpring: false
    // Magnification target is fed by Dock (cosine-bell wave, T07). The actual
    // magnification is animated toward the target via explicit dual-branch
    // Spring/Number animations (useSpring gate) — dual Behavior{} is unsupported.
    property real magnificationTarget: 1.0
    property real magnification: 1.0
    // T08-fix2: analytical slot x/width from Dock (icon-only push). Dock always
    // feeds these; title mode uses fixed rest slots (no scale/push reflow).
    property real slotWidthTarget: showTitle ? 132 : 60
    property real slotXTarget: 0
    property real pressScale: Motion.pressScaleFor(settingsService, windowMouse.pressed)
    property real bounceOffset: 0
    property var dockWindow
    property var dockSurfaceItem
    property real dockSlideOffset: 0
    property var labelClipItem: null
    property real labelClipContentX: 0
    // Per-button hover label is disabled when Dock owns the unified capsule
    // (T07). Keep the property so external callers can still opt in.
    property bool hoverLabelEnabled: false
    readonly property bool hovered: windowMouse.containsMouse
    readonly property bool active: windowModel ? !!windowModel.isFocused : !!(toplevel && toplevel.activated)
    readonly property bool minimized: windowModel ? !!windowModel.isMinimized : !!(toplevel && toplevel.minimized)
    readonly property string label: appsService ? appsService.toplevelLabel(windowModel || toplevel) : String((windowModel || toplevel) ? (windowModel || toplevel).title || (windowModel || toplevel).appId || "窗口" : "窗口")
    readonly property bool showHoverLabel: hoverLabelEnabled && !showTitle && hovered && label.length > 0
    // T08-fix3: bottom-origin scale — no mag-based lift (was floating mid-air).
    readonly property real lift: 0

    signal activateRequested(var toplevel)
    signal contextMenuRequested(var window)
    signal dockPointerMoved(real x, int buttons)
    signal dockPointerEntered()
    signal dockPointerExited()

    // Animated slot geometry. Dock owns targets via slotXTarget/slotWidthTarget
    // (analytical push in icon-only mode). Initial values match rest icon slot.
    x: 0
    width: showTitle ? 132 : 60
    height: 60

    function updateDockRectangle() {
        if (!root.dockWindow)
            return;

        // The foreign-toplevel hint is the icon itself, not this delegate's
        // hit target. Mapping both corners includes hover magnification/lift.
        // Remove Dock's autohide translation so cached hints always refer to
        // the stable, fully revealed Dock position rather than off-screen.
        var topLeft = icon.mapToItem(null, 0, 0);
        var bottomRight = icon.mapToItem(null, icon.width, icon.height);
        var left = Math.floor(Math.min(topLeft.x, bottomRight.x));
        var top = Math.floor(Math.min(topLeft.y, bottomRight.y) - root.dockSlideOffset);
        var right = Math.ceil(Math.max(topLeft.x, bottomRight.x));
        var bottom = Math.ceil(Math.max(topLeft.y, bottomRight.y) - root.dockSlideOffset);
        var targetWidth = Math.max(1, right - left);
        var targetHeight = Math.max(1, bottom - top);
        if (root.windowsService && root.windowModel) {
            root.windowsService.setRectangle(
                root.windowModel,
                root.dockWindow,
                left,
                top,
                targetWidth,
                targetHeight
            );
        } else if (root.toplevel && root.toplevel.setRectangle) {
            root.toplevel.setRectangle(root.dockWindow, Qt.rect(left, top, targetWidth, targetHeight));
        }
    }

    function scheduleDockRectangleUpdate() {
        dockRectangleRefresh.restart();
    }

    function restoreOrActivate() {
        if (!root.windowModel && !root.toplevel)
            return;

        updateDockRectangle();

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

        updateDockRectangle();
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
    onIconSizeChanged: scheduleDockRectangleUpdate()
    onDockWindowChanged: scheduleDockRectangleUpdate()
    onWindowModelChanged: scheduleDockRectangleUpdate()
    onToplevelChanged: scheduleDockRectangleUpdate()
    onMagnificationTargetChanged: root.animateMagnification()
    onSlotWidthTargetChanged: root.animateWidth()
    onSlotXTargetChanged: root.animateX()
    Component.onCompleted: {
        root.magnification = root.magnificationTarget;
        root.x = root.slotXTarget;
        root.width = root.slotWidthTarget;
        root.scheduleDockRectangleUpdate();
    }

    Timer {
        id: dockRectangleRefresh
        interval: 0
        repeat: false
        onTriggered: root.updateDockRectangle()
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 16
        color: "transparent"
        border.color: "transparent"
        border.width: 0
    }

    Image {
        id: icon
        x: root.showTitle ? 9 : Math.round((parent.width - width) / 2)
        // Bottom-align to row baseline; scale grows upward (transformOrigin Bottom).
        // bounceOffset still lifts the whole icon on click.
        y: Math.round(parent.height - height - 6 - root.bounceOffset)
        width: root.iconSize
        height: root.iconSize
        scale: root.magnification * root.pressScale
        source: root.appsService ? root.appsService.iconForToplevel(root.windowModel || root.toplevel) : ""
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: false
        sourceSize.width: 96
        sourceSize.height: 96
        opacity: (root.minimized ? 0.58 : 1.0) * (windowMouse.pressed ? 0.75 : 1.0)
        transformOrigin: Item.Bottom

        Behavior on opacity {
            NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing }
        }
    }

    Behavior on pressScale {
        NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing }
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

        // T08: 2px soft glow under the running indicator.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 4
            height: parent.height + 4
            radius: Math.min(width, height) / 2
            z: -1
            visible: parent.opacity > 0.01 && parent.width > 0
            color: "#40000000"
        }
    }

    Rectangle {
        id: hoverLabel
        readonly property real labelMaxWidth: Math.max(48, Math.min(280, (root.labelClipItem ? root.labelClipItem.width : root.width) - 12))

        z: 10
        x: {
            var centered = icon.x + icon.width / 2 - width / 2;
            if (!root.labelClipItem)
                return centered;

            var left = root.labelClipContentX - root.x + 6;
            var right = root.labelClipContentX + root.labelClipItem.width - width - root.x - 6;
            return Math.max(left, Math.min(right, centered));
        }
        // Instant appear (T07) — no y-slide; Dock's unified label is preferred.
        y: -30
        width: Math.min(Math.max(hoverLabelText.implicitWidth + 18, 48), labelMaxWidth)
        height: 26
        radius: 7
        color: "#d9f7f8fb"
        border.color: "#70ffffff"
        opacity: root.showHoverLabel ? 1 : 0
        visible: opacity > 0.01

        Text {
            id: hoverLabelText

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            text: root.label
            color: "#202124"
            font.pixelSize: 13
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Behavior on opacity {
            NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.emphasizedDecel }
        }
    }

    MouseArea {
        id: windowMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) {
            // Root-local pointer (not surface-local / not animated-slot-local raw).
            // mapToItem(dockWindow) uses live transforms so the result is where the
            // cursor actually is — independent of sibling spring motion.
            if (root.dockWindow) {
                var point = root.mapToItem(root.dockWindow, mouse.x, mouse.y);
                root.dockPointerMoved(point.x, mouse.buttons);
            }
        }
        onEntered: root.dockPointerEntered()
        onExited: root.dockPointerExited()
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                root.bounce();
                root.contextMenuRequested(root.windowModel || root.toplevel);
            } else if (mouse.button === Qt.MiddleButton) {
                root.minimize();
                root.bounce();
            } else {
                root.restoreOrActivate();
                root.bounce();
            }
        }
    }

    // Explicit dual-branch animations (useSpring). Dual Behavior{} on the same
    // property is unsupported in Qt Quick and only the first interceptor sticks.
    function animateMagnification() {
        if (root.useSpring) {
            magSpring.to = magnificationTarget;
            magSpring.restart();
        } else {
            magEase.to = magnificationTarget;
            magEase.restart();
        }
    }
    function animateX() {
        if (root.useSpring) {
            xSpring.to = slotXTarget;
            xSpring.restart();
        } else {
            xEase.to = slotXTarget;
            xEase.restart();
        }
    }
    function animateWidth() {
        if (root.useSpring) {
            widthSpring.to = slotWidthTarget;
            widthSpring.restart();
        } else {
            widthEase.to = slotWidthTarget;
            widthEase.restart();
        }
    }

    SpringAnimation {
        id: magSpring
        target: root
        property: "magnification"
        spring: Motion.dockMagSpring.spring
        damping: Motion.dockMagSpring.damping
        epsilon: Motion.dockMagSpring.epsilon
    }
    NumberAnimation {
        id: magEase
        target: root
        property: "magnification"
        duration: Motion.elementMove(root.settingsService)
        easing.type: Motion.emphasizedDecel
    }
    SpringAnimation {
        id: xSpring
        target: root
        property: "x"
        spring: Motion.dockMagSpring.spring
        damping: Motion.dockMagSpring.damping
        epsilon: Motion.dockMagSpring.epsilon
    }
    NumberAnimation {
        id: xEase
        target: root
        property: "x"
        duration: Motion.elementMove(root.settingsService)
        easing.type: Motion.emphasizedDecel
    }
    SpringAnimation {
        id: widthSpring
        target: root
        property: "width"
        spring: Motion.dockMagSpring.spring
        damping: Motion.dockMagSpring.damping
        epsilon: Motion.dockMagSpring.epsilon
    }
    NumberAnimation {
        id: widthEase
        target: root
        property: "width"
        duration: Motion.elementMove(root.settingsService)
        easing.type: Motion.emphasizedDecel
    }

    Timer {
        id: bounceTimer
        interval: 16
        repeat: false
        onTriggered: root.animateBounceTo(0)
    }

    function bounce() {
        bounceSpring.stop();
        bounceEase.stop();
        root.bounceOffset = 14;
        bounceTimer.restart();
    }
    function animateBounceTo(value) {
        if (root.useSpring) {
            bounceSpring.to = value;
            bounceSpring.restart();
        } else {
            bounceEase.to = value;
            bounceEase.restart();
        }
    }

    SpringAnimation {
        id: bounceSpring
        target: root
        property: "bounceOffset"
        spring: Motion.springBouncy.spring
        damping: Motion.springBouncy.damping
        epsilon: 0.01
    }
    NumberAnimation {
        id: bounceEase
        target: root
        property: "bounceOffset"
        duration: 220
        easing.type: Motion.emphasizedDecel
    }
}
