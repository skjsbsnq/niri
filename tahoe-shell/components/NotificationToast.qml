pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion
import "DynamicIslandMotion.js" as IslandMotion

// Real notification toast stack (T09).
//
// Driven by Notifications.activeModel via visibleStack(max). Up to
// notificationToastStackMax (default 3) cards render newest-on-top.
// Enter / scale use springPanel on *content* transforms only. Glass region
// geometry uses eased y (stack) and eased x (swipe) — never SpringAnimation
// (guardrail 0704ea4). Horizontal swipe dismiss reuses DynamicIslandMotion
// thresholds. Hover lifts the top card and reveals a top-left close button.
//
// DND and Dynamic Island still suppress the whole toast surface.

PanelWindow {
    id: root

    property var notificationsService
    property var settingsService
    property var dynamicIslandService
    property var current: notificationsService ? notificationsService.current : null
    property bool hasCurrent: !!current
    readonly property bool suppressedByDynamicIsland: root.dynamicIslandService
        ? !!root.dynamicIslandService.islandEnabled
        : (!!root.settingsService && !!root.settingsService.dynamicIslandEnabled)
    readonly property int stackMax: {
        var n = root.settingsService ? Number(root.settingsService.notificationToastStackMax) : Motion.toastStackMaxDefault;
        if (!isFinite(n))
            n = Motion.toastStackMaxDefault;
        return Math.max(1, Math.min(3, Math.round(n)));
    }
    // Depend on activeCount so FIFO mutations re-evaluate the stack slice.
    readonly property int activeCount: notificationsService ? notificationsService.activeCount : 0
    readonly property var stackItems: {
        var _watch = root.activeCount;
        if (!notificationsService || root.suppressedByDynamicIsland || _watch <= 0)
            return [];
        return notificationsService.visibleStack(root.stackMax);
    }
    readonly property int stackCount: stackItems.length
    readonly property bool shouldShowToast: stackCount > 0
    // Kept for shell.qml compatibility. Glass geometry never uses Spring.
    property bool useSpring: false
    readonly property int screenWidth: Math.max(1, root.numberOr(root.screen && root.screen.width, 1))
    readonly property int toastLeftMargin: Math.round(Math.max(8, root.screenWidth - root.implicitWidth - 16))
    readonly property bool compositorLayerAnimations:
        root.settingsService && root.settingsService.compositorLayerAnimations
    property real toastMaterialAlpha: shouldShowToast ? 1 : 0
    readonly property bool toastGlassActive: shouldShowToast || toastMaterialAlpha > 0.01
    readonly property int cardBaseHeight: 86
    property int measuredStackHeight: cardBaseHeight

    function numberOr(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
    }

    function accentFor(notification) {
        if (!notification)
            return GlassStyle.StrokeToast;
        try {
            return Number(notification.urgency) === 2 ? "#ccff453a" : GlassStyle.StrokeToast;
        } catch (e) {
            return GlassStyle.StrokeToast;
        }
    }

    function iconUrlFor(notification) {
        if (!notificationsService || !notification)
            return "";
        return notificationsService.iconUrlFor(notification);
    }

    function dismissNotification(notification) {
        if (!notificationsService || !notification)
            return;
        notificationsService.dismissId(notification.id, "dismiss");
    }

    function invokeAction(notification, identifier) {
        if (!notificationsService || !notification)
            return;
        notificationsService.invokeAction(notification.id, identifier);
    }

    function recomputeStackHeight() {
        var h = root.cardBaseHeight;
        var slots = [stackSlot0, stackSlot1, stackSlot2];
        for (var i = 0; i < slots.length; i++) {
            var item = slots[i];
            if (!item || !item.active)
                continue;
            var bottom = item.y + item.height;
            if (bottom > h)
                h = bottom;
        }
        measuredStackHeight = Math.ceil(h + 4);
    }

    visible: toastGlassActive
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    implicitWidth: 318
    implicitHeight: Math.max(cardBaseHeight, measuredStackHeight)
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "tahoe-notification-toast"

    anchors {
        top: true
        left: true
    }

    margins {
        top: 48
        left: root.toastLeftMargin
    }

    Behavior on toastMaterialAlpha {
        NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Motion.elementResize(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }
    }

    TahoeGlass.regions: [
        stackSlot0.cardRegion,
        stackSlot1.cardRegion,
        stackSlot2.cardRegion
    ]

    ToastCard {
        id: stackSlot0
        stackIndex: 0
    }
    ToastCard {
        id: stackSlot1
        stackIndex: 1
    }
    ToastCard {
        id: stackSlot2
        stackIndex: 2
    }

    onStackCountChanged: Qt.callLater(recomputeStackHeight)
    onStackItemsChanged: Qt.callLater(recomputeStackHeight)

    component ToastCard: Item {
        id: cardRoot

        property int stackIndex: 0
        readonly property var notification: {
            if (stackIndex < 0 || stackIndex >= root.stackItems.length)
                return null;
            return root.stackItems[stackIndex];
        }
        readonly property bool active: !!notification && stackIndex < root.stackMax
        readonly property string iconUrl: root.iconUrlFor(notification)
        readonly property bool hasIcon: iconUrl.length > 0
        readonly property color accentColor: root.accentFor(notification)
        readonly property int notifId: notification ? Number(notification.id) : -1

        // Content-only motion (spring-safe).
        property real enterX: 0
        property real contentScale: 1
        property real contentOpacity: 0

        // Glass-safe geometry: eased only.
        property real stackY: 0
        property real swipeX: 0
        property real hoverLift: 0

        property bool swipeDragging: false
        property bool swipeMoved: false
        property real swipeStartX: 0
        property real swipePointerStartX: 0
        property real swipePointerStartY: 0
        property int boundNotifId: -1

        readonly property alias cardRegion: glass.region

        width: root.implicitWidth
        height: Math.max(root.cardBaseHeight, contentColumn.implicitHeight + 28)
        // Glass-safe: stack offset + hover lift + swipe (all NumberAnimation).
        x: swipeX
        y: stackY - hoverLift
        z: root.stackMax - stackIndex
        visible: active || contentOpacity > 0.01 || Math.abs(swipeX) > 0.5
        opacity: root.toastMaterialAlpha
        // Visual stack scale on the slot (paint transform). GlassPanel region
        // still reports rest width/height — never spring the region geometry.
        transform: Scale {
            origin.x: cardRoot.width / 2
            origin.y: 0
            xScale: cardRoot.contentScale
            yScale: cardRoot.contentScale
        }

        onHeightChanged: root.recomputeStackHeight()
        onYChanged: root.recomputeStackHeight()
        onXChanged: root.recomputeStackHeight()

        // Glass geometry: eased, never spring.
        Behavior on y {
            NumberAnimation {
                duration: Motion.elementMove(root.settingsService)
                easing.type: Motion.emphasizedDecel
            }
        }
        Behavior on x {
            enabled: !cardRoot.swipeDragging
            NumberAnimation {
                duration: Motion.panelExit(root.settingsService)
                easing.type: Motion.emphasizedAccel
            }
        }
        Behavior on hoverLift {
            NumberAnimation {
                duration: Motion.fadeFast(root.settingsService)
                easing.type: Motion.emphasizedDecel
            }
        }

        function syncFromStack() {
            if (!active) {
                contentOpacity = 0;
                hoverLift = 0;
                if (!swipeDragging && Math.abs(swipeX) < 1)
                    swipeX = 0;
                return;
            }

            var targetScale = Motion.toastStackScaleForIndex(stackIndex);
            var targetY = Motion.toastStackYForIndex(stackIndex);
            stackY = targetY;
            animateScaleTo(targetScale);
            contentOpacity = 1;

            // New identity: only the top card springs in. Demoted/promoted
            // cards snap content so the stack does not re-slide every push.
            if (boundNotifId !== notifId) {
                boundNotifId = notifId;
                swipeX = 0;
                swipeDragging = false;
                if (stackIndex === 0) {
                    enterX = Motion.toastEnterOffsetPx;
                    Qt.callLater(function () {
                        if (cardRoot.boundNotifId === cardRoot.notifId && cardRoot.stackIndex === 0)
                            cardRoot.animateEnterTo(0);
                    });
                } else {
                    enterX = 0;
                }
            }
        }

        onActiveChanged: syncFromStack()
        onNotifIdChanged: syncFromStack()
        onStackIndexChanged: {
            if (active) {
                stackY = Motion.toastStackYForIndex(stackIndex);
                animateScaleTo(Motion.toastStackScaleForIndex(stackIndex));
            }
        }

        Component.onCompleted: syncFromStack()

        function animateEnterTo(value) {
            enterSpring.stop();
            enterEase.stop();
            if (root.useSpring && !Motion.reducedMotion(root.settingsService)) {
                enterSpring.to = value;
                enterSpring.restart();
            } else {
                enterEase.to = value;
                enterEase.restart();
            }
        }

        function animateScaleTo(value) {
            // Stack scale is content-only and always eased (no spring): lower
            // cards settle to 0.96/0.92 without overshoot near glass bounds.
            scaleEase.stop();
            scaleEase.to = value;
            scaleEase.restart();
        }

        function animateSwipeTo(value, thenDismiss) {
            swipeDragging = false;
            dismissAfterSwipe.pending = !!thenDismiss;
            // Drive via property; Behavior on x handles easing. For large
            // dismiss targets, also run an explicit animation so onStopped fires.
            swipeAnim.stop();
            swipeX = value;
            if (thenDismiss) {
                swipeAnim.to = value;
                swipeAnim.from = swipeX;
                // Property already set; use timer fallback for dismiss.
                dismissAfterSwipe.restart();
            }
        }

        function beginSwipe(px, py) {
            if (!active || stackIndex !== 0)
                return;
            swipeDragging = true;
            swipeMoved = false;
            swipeStartX = swipeX;
            swipePointerStartX = px;
            swipePointerStartY = py;
            swipeAnim.stop();
            dismissAfterSwipe.stop();
        }

        function advanceSwipe(px, py) {
            if (!swipeDragging)
                return;
            var dx = px - swipePointerStartX;
            var dy = py - swipePointerStartY;
            var vertical = Math.abs(dy);
            var horizontal = dx;
            var tol = IslandMotion.swipeVerticalTolerance;
            if (vertical > tol)
                horizontal = horizontal * Math.max(0, 1 - (vertical - tol) / 36);
            swipeX = swipeStartX + horizontal;
            if (Math.abs(swipeX - swipeStartX) > 4)
                swipeMoved = true;
        }

        function resolveSwipe() {
            if (!swipeDragging)
                return;
            swipeDragging = false;
            var w = Math.max(1, cardRoot.width);
            var progress = swipeX / w;
            var absPx = Math.abs(swipeX);
            var enter = IslandMotion.swipeEnterThreshold;
            if (Math.abs(progress) >= enter || absPx >= Motion.toastSwipeDismissPx) {
                var target = (swipeX >= 0 ? 1 : -1) * (w + 48);
                swipeX = target;
                dismissAfterSwipe.pending = true;
                dismissAfterSwipe.restart();
            } else {
                swipeX = 0;
            }
        }

        SpringAnimation {
            id: enterSpring
            target: cardRoot
            property: "enterX"
            spring: Motion.springPanel.spring
            damping: Motion.springPanel.damping
            epsilon: 0.001
        }
        NumberAnimation {
            id: enterEase
            target: cardRoot
            property: "enterX"
            duration: Motion.panelEnter(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }

        NumberAnimation {
            id: scaleEase
            target: cardRoot
            property: "contentScale"
            duration: Motion.elementMove(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }

        NumberAnimation {
            id: swipeAnim
            target: cardRoot
            property: "swipeX"
            duration: Motion.panelExit(root.settingsService)
            easing.type: Motion.emphasizedAccel
        }

        Timer {
            id: dismissAfterSwipe
            property bool pending: false
            interval: Motion.panelExit(root.settingsService)
            repeat: false
            onTriggered: {
                if (pending && cardRoot.notification)
                    root.dismissNotification(cardRoot.notification);
                pending = false;
            }
        }

        Behavior on contentOpacity {
            NumberAnimation {
                duration: Motion.fadeFast(root.settingsService)
                easing.type: Motion.standardDecel
            }
        }

        GlassPanel {
            id: glass

            // Rest geometry only — no transform on GlassPanel (region tracks
            // item bounds; scale/enter must stay on contentHost). Swipe is
            // cardRoot.x (eased NumberAnimation, never Spring).
            x: 0
            y: 0
            width: parent.width
            height: parent.height
            material: GlassStyle.MaterialToast
            radius: GlassStyle.RadiusToast
            fillColor: GlassStyle.FillPanelBright
            strokeWidth: 0
            interaction: root.toastMaterialAlpha * (cardRoot.stackIndex === 0 && cardHover.hovered ? 1 : 0.85)
            materialAlpha: root.toastMaterialAlpha * cardRoot.contentOpacity
            regionEnabled: cardRoot.active && root.toastGlassActive
            opacity: cardRoot.contentOpacity

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.color: cardRoot.accentColor
                border.width: 1
            }

            Item {
                id: contentHost
                anchors.fill: parent
                opacity: 1
                // Enter slide only (content transform). Stack scale is on cardRoot.
                transform: Translate { x: cardRoot.enterX }

                Column {
                    id: contentColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 8

                    Item {
                        width: parent.width
                        height: 36

                        Rectangle {
                            id: iconBox
                            x: 0
                            y: 0
                            width: 36
                            height: 36
                            radius: 11
                            color: "#70ffffff"
                            border.color: "#60ffffff"

                            Text {
                                anchors.centerIn: parent
                                text: "\ue7f4"
                                color: "#3c4043"
                                font.family: "Material Icons"
                                font.pixelSize: 20
                                visible: !cardRoot.hasIcon
                            }

                            Image {
                                anchors.fill: parent
                                anchors.margins: 4
                                fillMode: Image.PreserveAspectCrop
                                source: cardRoot.iconUrl
                                visible: cardRoot.hasIcon
                                sourceSize.width: 64
                                sourceSize.height: 64
                                asynchronous: true
                            }
                        }

                        Text {
                            anchors.left: iconBox.right
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: cardRoot.stackIndex === 0 ? 28 : 0
                            anchors.verticalCenter: iconBox.verticalCenter
                            text: cardRoot.notification ? String(cardRoot.notification.appName || "Notification") : ""
                            color: "#202124"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        width: parent.width
                        text: cardRoot.notification ? String(cardRoot.notification.summary || "") : ""
                        color: "#202124"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        visible: text.length > 0
                    }

                    Text {
                        width: parent.width
                        text: cardRoot.notification ? String(cardRoot.notification.body || "") : ""
                        color: "#5f6368"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 4
                        visible: text.length > 0
                    }

                    Row {
                        width: parent.width
                        spacing: 8
                        layoutDirection: Qt.RightToLeft
                        visible: cardRoot.notification && cardRoot.notification.actions
                                 && cardRoot.notification.actions.length > 0

                        Repeater {
                            model: cardRoot.notification ? cardRoot.notification.actions : []

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                height: 26
                                width: actionLabel.implicitWidth + 22
                                radius: 13
                                color: actionMouse.containsMouse ? "#a0ffffff" : "#60ffffff"
                                border.color: "#50ffffff"

                                Text {
                                    id: actionLabel
                                    anchors.centerIn: parent
                                    text: {
                                        var t = String(modelData.text || "");
                                        if (t.length > 0)
                                            return t;
                                        return String(modelData.identifier || "");
                                    }
                                    color: "#1a73e8"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: actionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.invokeAction(cardRoot.notification, modelData.identifier)
                                }
                            }
                        }
                    }
                }
            }

            HoverHandler {
                id: cardHover
                enabled: cardRoot.active && cardRoot.stackIndex === 0
                onHoveredChanged: {
                    if (hovered)
                        cardRoot.hoverLift = Motion.toastHoverLiftPx;
                    else if (!closeMouse.containsMouse)
                        cardRoot.hoverLift = 0;
                }
            }

            Item {
                id: closeBtn
                width: 22
                height: 22
                x: 8
                y: 8
                z: 5
                visible: cardRoot.active && cardRoot.stackIndex === 0
                         && (cardHover.hovered || closeMouse.containsMouse)

                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: closeMouse.containsMouse ? "#90ffffff" : "#60ffffff"
                    border.color: "#50ffffff"
                }

                Text {
                    anchors.centerIn: parent
                    text: "\ue5cd"
                    color: "#3c4043"
                    font.family: "Material Icons"
                    font.pixelSize: 14
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismissNotification(cardRoot.notification)
                    onContainsMouseChanged: {
                        if (!containsMouse && !cardHover.hovered)
                            cardRoot.hoverLift = 0;
                    }
                }
            }

            MouseArea {
                id: swipeArea
                anchors.fill: parent
                z: -1
                enabled: cardRoot.active && cardRoot.stackIndex === 0
                cursorShape: Qt.PointingHandCursor
                preventStealing: true

                onPressed: function (mouse) {
                    cardRoot.beginSwipe(mouse.x, mouse.y);
                }
                onPositionChanged: function (mouse) {
                    if (pressed)
                        cardRoot.advanceSwipe(mouse.x, mouse.y);
                }
                onReleased: function (mouse) {
                    if (cardRoot.swipeMoved) {
                        cardRoot.resolveSwipe();
                    } else {
                        cardRoot.swipeDragging = false;
                        cardRoot.swipeX = 0;
                        root.dismissNotification(cardRoot.notification);
                    }
                }
                onCanceled: {
                    cardRoot.swipeDragging = false;
                    cardRoot.swipeX = 0;
                }
            }
        }
    }
}
