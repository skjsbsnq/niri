pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property var appsService
    property var niriService
    property bool launchpadOpen: false
    // See shell.qml useSpring. Spring on Image geometry corrupts textures on
    // VMware/software GPUs; NumberAnimation is safe. Default false.
    property bool useSpring: false
    property real dockMouseX: -10000
    property bool dockHovered: false
    property bool pointerDragActive: false
    readonly property bool hasWindows: niriService && niriService.windowList && niriService.windowList.length > 0
    readonly property color glassFill: GlassStyle.FillDock
    readonly property color glassStroke: GlassStyle.StrokeDock

    signal toggleLaunchpad()

    // When the Launchpad opens, the Dock must disappear so the Launchpad
    // scrim truly covers everything. Otherwise the Dock is a sibling
    // layer-shell panel that stays stacked above the Launchpad backdrop
    // and keeps blurring its own slice of the screen, so the three panels
    // (Dock / TopBar / Launchpad) each compute their own glass and the
    // Launchpad looks "not fully covering". See glass-consistency-fix-
    // plan.md §1.2 B / §1.3 B.
    //
    // Visible stays true until the fade-out finishes so the panel is
    // unmapped (and its glass region stops sampling) only once it's gone;
    // during the fade the Launchpad scrim covers any residual blur.
    visible: !launchpadOpen || dockSurface.opacity > 0.01

    // Spring-smoothed dock magnification.
    //
    // This returns the *target* scale for an icon given the pointer
    // position. The actual magnification property on each delegate has a
    // SpringAnimation Behavior (see the delegate), so the icon eases toward
    // this target every frame instead of snapping. The web dock does the
    // same thing with requestAnimationFrame + exponential lerp (script.js
    // 358-404); here the spring plays the role of the lerp.
    //
    // Range ~150px (web uses 195), peak scale 1.5 (web uses 1.7). Wider
    // range + bigger peak is what makes the neighbor-coupling wave visible.
    function proximityScale(item) {
        if (pointerDragActive || !dockHovered || !item || !dockSurface)
            return 1.0;

        var point = item.mapToItem(dockSurface, item.width / 2, item.height / 2);
        var distance = Math.abs(dockMouseX - point.x);
        var influence = Math.max(0, 1 - distance / 150);
        return 1.0 + influence * 0.5;
    }

    function updateDockWaveSpacing() {
        if (!dockRow)
            return;

        var target = dockRow.baseSpacing;
        if (!pointerDragActive && dockHovered) {
            var maxScale = 1.0;
            var items = dockRow.children;
            for (var i = 0; i < items.length; i++) {
                var item = items[i];
                if (!item || item.visible === false || item.magnification === undefined)
                    continue;

                var scale = root.proximityScale(item);
                if (scale > maxScale)
                    maxScale = scale;
            }

            target = dockRow.baseSpacing + Math.max(0, maxScale - 1.0) * 18;
        }

        dockRow.waveSpacing = target;
    }

    function markDockHovered() {
        hoverExitTimer.stop();
        root.dockHovered = true;
        root.updateDockWaveSpacing();
    }

    function updateDockHover(x) {
        hoverExitTimer.stop();
        root.dockMouseX = x;
        root.dockHovered = true;
        root.pointerDragActive = false;
        root.updateDockWaveSpacing();
    }

    function updateDockHoverFromButtons(x, buttons) {
        if (buttons !== Qt.NoButton) {
            root.pointerDragActive = true;
            root.resetDockHover();
            return;
        }

        root.updateDockHover(x);
    }

    function updateDockHoverFromMouse(x, mouse) {
        var buttons = mouse && mouse.buttons !== undefined ? mouse.buttons : Qt.NoButton;
        root.updateDockHoverFromButtons(x, buttons);
    }

    function scheduleDockHoverReset() {
        hoverExitTimer.restart();
    }

    function resetDockHover() {
        hoverExitTimer.stop();
        root.dockHovered = false;
        root.dockMouseX = -10000;
        root.updateDockWaveSpacing();
    }

    onLaunchpadOpenChanged: if (launchpadOpen) resetDockHover()

    Timer {
        id: hoverExitTimer
        interval: 90
        repeat: false
        onTriggered: root.resetDockHover()
    }

    anchors {
        left: true
        right: true
        bottom: true
    }

    exclusiveZone: 98
    implicitHeight: 132
    color: "transparent"
    WlrLayershell.namespace: "tahoe-dock"

    TahoeGlass.regions: [
        TahoeGlassRegion {
            item: dockSurface
            material: dockSurface.tahoeGlassMaterial
            radius: dockSurface.tahoeGlassRadius
            blur: false
            shadow: false
            clip: true
            // Keep the dock in its quiet QML-painted resting surface. Any
            // compositor-owned dock material becomes the heavy full-width bar
            // after a click/drag-triggered repaint.
            interaction: 0.0
            materialAlpha: 0.0
            enabled: !root.launchpadOpen && dockSurface.opacity > 0.01
        }
    ]

    Rectangle {
        id: dockSurface
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialDock
        readonly property real tahoeGlassRadius: GlassStyle.RadiusDock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        width: Math.min(parent.width - 28, dockRow.implicitWidth + 34)
        height: 78
        radius: tahoeGlassRadius
        color: root.glassFill
        // Fade the dock surface out when the Launchpad opens (see the
        // visible binding above). NumberAnimation, not spring — see
        // shell.qml useSpring: spring on Image geometry corrupts the
        // icon textures on VMware/software GPUs.
        opacity: root.launchpadOpen ? 0 : 1

        Behavior on opacity {
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }

        // NOTE: no `border.width` on the surface itself — a centered 1px
        // border antialiased against the outside pixels produces faint
        // near-square corners at the arc tangents. Draw the glass edges
        // with inset Rectangles instead, whose borders sit fully inside.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onPositionChanged: function(mouse) {
                root.updateDockHoverFromMouse(mouse.x, mouse);
            }
            onEntered: root.markDockHovered()
            onExited: root.scheduleDockHoverReset()
        }

        Rectangle {
            // Top-left light edge (the Tahoe glass highlight).
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: root.glassStroke
            border.width: 1
        }

        Row {
            id: dockRow
            anchors.centerIn: parent
            property real baseSpacing: 8
            property real waveSpacing: baseSpacing
            spacing: waveSpacing

            Behavior on waveSpacing {
                enabled: !root.useSpring
                NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
            }
            Behavior on waveSpacing {
                enabled: root.useSpring
                SpringAnimation {
                    spring: 220
                    damping: 1.0
                    epsilon: 0.01
                }
            }

            Repeater {
                model: ScriptModel {
                    values: root.appsService ? root.appsService.pinnedApps : []
                }

                delegate: Item {
                    id: pinnedButton

                    required property var modelData
                    // Magnification tracks the pointer position via
                    // proximityScale(); the SpringAnimation Behavior below
                    // eases it toward that target every frame, so neighbors
                    // couple into a wave instead of snapping. This mirrors
                    // the web dock's requestAnimationFrame + exponential
                    // lerp (script.js 358-404) — the spring plays the lerp.
                    // Kept writable (not readonly) so the Behavior reliably
                    // intercepts binding updates.
                    property real magnification: root.proximityScale(pinnedButton)
                    property real bounceOffset: 0
                    readonly property bool hovered: !root.pointerDragActive && iconMouse.containsMouse
                    readonly property bool running: modelData.shellAction !== "launchpad"
                        && root.appsService
                        && root.niriService
                        && root.appsService.appHasRunningWindow(modelData, root.niriService.windowList)
                    readonly property real lift: (magnification - 1.0) * 22 + (hovered ? 3 : 0)

                    // Fixed width. NOTE: width must NOT depend on
                    // magnification — proximityScale() reads this delegate's
                    // geometry to compute the icon center, so a
                    // magnification-driven width creates a binding loop
                    // (width -> magnification -> proximityScale -> width)
                    // that runs away and crashes Quickshell. The wave feel
                    // comes from the icon scale + lift + Row spacing spring
                    // instead.
                    width: 62
                    height: 70

                    Rectangle {
                        x: 4
                        y: 8
                        width: 54
                        height: 54
                        radius: 16
                        color: root.launchpadOpen && modelData.id === "launchpad" ? "#70ffffff" : "transparent"
                    }

                    Image {
                        id: appIcon
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 8 - pinnedButton.lift - pinnedButton.bounceOffset
                        width: 48
                        height: 48
                        scale: pinnedButton.magnification
                        source: root.appsService ? root.appsService.iconForApp(modelData) : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        transformOrigin: Item.Center
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: pinnedButton.running ? 5 : 0
                        height: 5
                        radius: 3
                        color: "#99000000"
                    }

                    Rectangle {
                        id: hoverLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        z: 10
                        y: pinnedButton.hovered ? -34 : -24
                        width: Math.max(labelText.implicitWidth + 18, 42)
                        height: 24
                        radius: 7
                        color: "#d9f7f8fb"
                        border.color: "#70ffffff"
                        opacity: pinnedButton.hovered ? 1 : 0
                        visible: opacity > 0.01

                        Text {
                            id: labelText
                            anchors.centerIn: parent
                            text: root.appsService ? root.appsService.appLabel(modelData) : ""
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
                        id: iconMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: function(mouse) {
                            var point = pinnedButton.mapToItem(dockSurface, mouse.x, mouse.y);
                            root.updateDockHoverFromMouse(point.x, mouse);
                        }
                        onEntered: root.markDockHovered()
                        onExited: root.scheduleDockHoverReset()
                        onClicked: {
                            pinnedButton.bounce();
                            if (modelData.shellAction === "launchpad") {
                                root.toggleLaunchpad();
                            } else if (root.appsService) {
                                root.appsService.launchApp(modelData);
                            }
                        }
                    }

                    // Spring bounce on click — kick bounceOffset to an
                    // overshoot then let the Behavior spring below settle
                    // it (1.5 oscillations). A single-shot Timer does the
                    // kick→release so the spring sees a real change.
                    Timer {
                        id: bounceTimer
                        interval: 16
                        repeat: false
                        onTriggered: pinnedButton.bounceOffset = 0
                    }

                    function bounce() {
                        pinnedButton.bounceOffset = 14;
                        bounceTimer.restart();
                    }

                    // Bounce on click. Spring (underdamped, ~1.5 oscillations)
                    // gives the macOS feel but corrupts the icon's Image texture
                    // on VMware/software GPUs while it runs, so it's gated behind
                    // useSpring. The default NumberAnimation is a single safe
                    // tween — no overshoot, but no texture loss on VMs either.
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

                    // Magnification easing (icon scale + lift track the pointer).
                    // Same useSpring gate as bounce: spring on real GPUs,
                    // NumberAnimation everywhere else.
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
            }

            Rectangle {
                width: 1
                height: 46
                radius: 1
                color: "#3d000000"
                visible: root.hasWindows
                anchors.verticalCenter: parent.verticalCenter
            }

            Repeater {
                model: root.niriService ? root.niriService.toplevels : null

                delegate: WindowButton {
                    id: windowButton

                    required property var modelData

                    toplevel: modelData
                    appsService: root.appsService
                    useSpring: root.useSpring
                    showTitle: true
                    magnification: root.proximityScale(windowButton)
                    dockWindow: root
                    dockSurfaceItem: dockSurface
                    onDockPointerMoved: function(x, buttons) {
                        root.updateDockHoverFromButtons(x, buttons === undefined ? Qt.NoButton : buttons);
                    }
                    onDockPointerEntered: root.markDockHovered()
                    onDockPointerExited: root.scheduleDockHoverReset()
                }
            }
        }
    }
}
