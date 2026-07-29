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
    // T08-fix9: mag/push track analytical targets via SmoothedAnimation
    // (not per-move Spring.restart — that jittered the bar).
    property real magnificationTarget: 1.0
    // Bound to target; Behavior retargets. Do not also assign in handlers.
    property real magnification: magnificationTarget
    // Slot x/width are REST geometry only (never wave-driven).
    // Visual neighbor push is pushX (Translate on the icon).
    property real slotWidthTarget: showTitle ? 132 : 60
    property real slotXTarget: 0
    property real pushXTarget: 0
    property real pushX: pushXTarget
    property real pressScale: Motion.pressScaleFor(settingsService, windowMouse.pressed)
    property real bounceOffset: 0
    property var dockWindow
    // QuickshellScreenInfo for this Dock instance; ownership uses handle.screens.
    property var dockScreen: dockWindow && dockWindow.screen !== undefined ? dockWindow.screen : null
    property var dockSurfaceItem
    property real dockSlideOffset: 0
    property real dockFullscreenOffset: 0
    // When Dock is unmapped for fullscreen, suppress foreign-toplevel rectangle
    // republish. Publishing into a closing game's handle (visibleChanged during
    // unmap on the same event stack as zwlr closed) previously crashed Quickshell.
    property bool dockFullscreenActive: false
    // Observable scene offset of the delegate's parent chain. mapToItem()
    // itself does not establish QML binding dependencies on ancestor motion,
    // so Dock forwards these values to refresh the foreign-toplevel hint while
    // its centered row and optional sections are being laid out.
    property real dockSceneOffsetX: 0
    property real dockSceneOffsetY: 0
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
    // localX is rest-slot local (slots never move — T08-fix7).
    signal dockPointerMoved(real localX, int buttons)
    signal dockPointerEntered()
    signal dockPointerExited()

    // Rest slot geometry. R17 eases model/layout changes here; the live wave
    // remains a separate visual-only pushX/scale transform.
    x: slotXTarget
    width: slotWidthTarget
    height: 60

    Behavior on x {
        NumberAnimation {
            duration: Motion.elementMove(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }
    }

    Behavior on width {
        NumberAnimation {
            duration: Motion.elementResize(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }
    }

    // Only suppress while the Dock layer is unmapped for fullscreen. After
    // fullscreenActive clears, republish immediately even if the reveal slide
    // is still running — niri cleared rects on unmap and minimize needs them.
    // C++ set_rectangle guards cover the closed-handle race on game exit.
    function dockRectanglePublishBlocked() {
        return root.dockFullscreenActive;
    }

    function updateDockRectangle(forcePublish, overrideRect) {
        if (!root.dockWindow)
            return;
        if (!forcePublish && root.dockRectanglePublishBlocked())
            return;
        // Interactive minimize/restore may run mid-reveal: never publish into
        // a still-unmapped fullscreen Dock (compositor has no layer surface).
        if (forcePublish && root.dockFullscreenActive)
            return;
        // R04: always key by the actual wlr handle. Do not fall back to a bare
        // setRectangle path that skips current-screen ownership.
        if (!root.toplevel)
            return;
        if (!root.windowsService || !root.windowsService.submitDockRectangle)
            return;

        // T19 (S-H2/S-M8): report REST geometry. The foreign-toplevel hint is
        // the icon's settled slot position, not the live hover wave. Mapping
        // the icon itself would include magnification*pressScale, the pushX
        // Translate and the click-bounce lift, so a minimize triggered at the
        // wave peak flew to a distorted/pressed/bounced target. Map from root
        // (the delegate Item — no scale, only the slot x/width Behavior) using
        // the icon's rest geometry (settled y, no bounceOffset); the wave is a
        // visual-only transform that never enters the hint. overrideRect (the
        // predicted shelf slot from Dock) is already in the same scene space.
        var left, top, right, bottom;
        if (overrideRect) {
            // The predicted shelf slot (from Dock) is derived from layout .x/.y
            // (QML transform: does not affect .y), so it is already in the
            // revealed/rest scene space — do NOT re-subtract the slide/fullscreen
            // offsets that the mapToItem() path undoes below.
            var ox = Number(overrideRect.x);
            var oy = Number(overrideRect.y);
            left = Math.floor(ox);
            top = Math.floor(oy);
            right = Math.ceil(ox + Number(overrideRect.width));
            bottom = Math.ceil(oy + Number(overrideRect.height));
        } else {
            var restIconY = Math.round(root.height - icon.height - 6);
            var topLeft = root.mapToItem(null, icon.x, restIconY);
            var bottomRight = root.mapToItem(null, icon.x + icon.width, restIconY + icon.height);
            left = Math.floor(Math.min(topLeft.x, bottomRight.x));
            top = Math.floor(Math.min(topLeft.y, bottomRight.y) - root.dockSlideOffset - root.dockFullscreenOffset);
            right = Math.ceil(Math.max(topLeft.x, bottomRight.x));
            bottom = Math.ceil(Math.max(topLeft.y, bottomRight.y) - root.dockSlideOffset - root.dockFullscreenOffset);
        }
        var targetWidth = Math.max(1, right - left);
        var targetHeight = Math.max(1, bottom - top);
        root.windowsService.submitDockRectangle(
            root.toplevel,
            root.dockWindow,
            root.dockScreen,
            left,
            top,
            targetWidth,
            targetHeight,
            { "force": !!forcePublish }
        );
    }

    function scheduleDockRectangleUpdate() {
        if (root.dockRectanglePublishBlocked())
            return;
        dockRectangleRefresh.restart();
    }

    // T19: genie target for a minimize initiated from this button — the
    // predicted appended shelf slot when the shelf is already open, else null
    // (updateDockRectangle falls back to this button's rest rect).
    function minimizeTargetRect() {
        return (root.dockWindow && root.dockWindow.hasMinimizedWindows)
            ? root.dockWindow.predictedMinimizeSlotSceneRect()
            : null;
    }

    function restoreOrActivate() {
        if (!root.windowModel && !root.toplevel)
            return;

        // Force publish after fullscreen so minimize/restore is not a silent
        // no-op while the dock reveal animation still holds a non-zero offset.
        // T19: a minimize initiated here flies TO the dock, so when the shelf is
        // already open we report the predicted appended shelf slot instead of
        // this button's rest rect; restore/activate keep the button rest rect
        // (the restore genie source is the dock icon).
        if (root.windowsService && root.windowModel) {
            if (root.windowModel.isMinimized) {
                updateDockRectangle(true);
                root.windowsService.restore(root.windowModel);
            } else if (root.windowModel.isFocused) {
                updateDockRectangle(true, root.minimizeTargetRect());
                root.windowsService.minimize(root.windowModel);
            } else {
                updateDockRectangle(true);
                root.windowsService.activate(root.windowModel);
            }
        } else if (root.toplevel.minimized) {
            updateDockRectangle(true);
            root.toplevel.minimized = false;
            if (root.toplevel.activate)
                root.toplevel.activate();
        } else if (root.toplevel.activated) {
            updateDockRectangle(true, root.minimizeTargetRect());
            root.toplevel.minimized = true;
        } else if (root.toplevel.activate) {
            updateDockRectangle(true);
            root.toplevel.activate();
        }

        root.activateRequested(root.windowModel || root.toplevel);
    }

    function minimize() {
        if (!root.windowModel && !root.toplevel)
            return;

        // T19: point the genie at the predicted appended shelf slot when the
        // shelf is already open (niri retargets to the real thumbnail once it
        // reports its settled rect, T-20); falls back to the button rest rect.
        updateDockRectangle(true, root.minimizeTargetRect());
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
    onDockScreenChanged: scheduleDockRectangleUpdate()
    onWindowModelChanged: scheduleDockRectangleUpdate()
    onToplevelChanged: scheduleDockRectangleUpdate()
    onDockSceneOffsetXChanged: scheduleDockRectangleUpdate()
    onDockSceneOffsetYChanged: scheduleDockRectangleUpdate()
    // T19: the hover wave (magnification/pushX) and click bounce are visual-only
    // transforms excluded from the REST-geometry hint (see updateDockRectangle),
    // so they no longer trigger a re-publish. Slot/layout/scene-offset changes do.
    // Offset still animates after fullscreen ends; keep coordinates fresh for
    // minimize targets. While fullscreenActive, schedule is blocked above.
    onDockFullscreenOffsetChanged: scheduleDockRectangleUpdate()
    // Layer remaps as soon as fullscreen clears — refill rects niri wiped on unmap.
    onDockFullscreenActiveChanged: {
        if (!root.dockFullscreenActive)
            scheduleDockRectangleUpdate();
    }

    // Handle output enter/leave: only the current-screen Dock may publish.
    Connections {
        target: root.toplevel
        function onScreensChanged() {
            root.scheduleDockRectangleUpdate();
        }
    }
    // Mag/push are bound to targets; Behavior alone retargets. Do NOT also
    // assign in on*TargetChanged — Qt logs "another interceptor unsupported"
    // and drops the second Behavior (session log spam + choppy wave).
    Component.onCompleted: root.scheduleDockRectangleUpdate()

    Behavior on magnification {
        enabled: !Motion.reducedMotion(root.settingsService)
        SmoothedAnimation {
            duration: Motion.dockMagFollowMs
            velocity: -1
            easing.type: Easing.InOutQuad
        }
    }
    Behavior on pushX {
        enabled: !Motion.reducedMotion(root.settingsService)
        SmoothedAnimation {
            duration: Motion.dockMagFollowMs
            velocity: -1
            easing.type: Easing.InOutQuad
        }
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
        // T08-fix7: visual neighbor push only; rest slot stays put.
        transform: Translate {
            x: root.pushX
        }

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
        // T08-fix5: clean macOS-style indicator — small round dot, no glow bar.
        // Follow visual icon (pushX) without moving the rest hit target.
        anchors.horizontalCenter: icon.horizontalCenter
        anchors.horizontalCenterOffset: root.pushX
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: root.active ? 5 : root.minimized ? 3 : 4
        height: width
        radius: width / 2
        color: root.active
            ? (root.minimized ? "#7b818a" : "#202124")
            : root.minimized ? "#7b818a" : "#99000000"
        opacity: (root.windowModel || root.toplevel) ? 1 : 0

        Behavior on width {
            NumberAnimation {
                duration: Motion.elementResize(root.settingsService)
                easing.type: Motion.emphasizedDecel
            }
        }

        Behavior on color {
            ColorAnimation { duration: Motion.fadeFast(root.settingsService) }
        }
    }

    Rectangle {
        id: hoverLabel
        readonly property real labelMaxWidth: Math.max(48, (root.labelClipItem ? root.labelClipItem.width : root.width) - 12)

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
            // Rest-slot local x only (T08-fix7). Dock converts to section rest
            // coordinates — never map into a growing glass surface.
            root.dockPointerMoved(mouse.x, mouse.buttons);
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

    // Wave mag/push are direct bindings (T08-fix8). Click bounce (R01 #75):
    // animated InQuad up leg, then dual-branch spring/ease down leg.
    function bounce() {
        bounceSpring.stop();
        bounceEase.stop();
        bounceUp.stop();
        if (Motion.reducedMotion(root.settingsService)) {
            // Single hop: instant up, eased settle.
            root.bounceOffset = Motion.dockClickBounceHeightPx;
            bounceEase.to = 0;
            bounceEase.restart();
            return;
        }
        bounceUp.restart();
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

    NumberAnimation {
        id: bounceUp
        target: root
        property: "bounceOffset"
        to: Motion.dockClickBounceHeightPx
        duration: Motion.dockClickBounceUpMs
        easing.type: Easing.InQuad
        onFinished: root.animateBounceTo(0)
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
        duration: Motion.dockClickBounceDownMs
        easing.type: Motion.emphasizedDecel
    }
}
