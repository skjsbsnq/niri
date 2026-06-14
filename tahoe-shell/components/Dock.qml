pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property var appsService
    property var niriService
    property bool launchpadOpen: false
    property real dockMouseX: -10000
    property bool dockHovered: false
    readonly property bool hasWindows: niriService && niriService.toplevelList && niriService.toplevelList.length > 0
    readonly property color glassFill: "#22ffffff"
    readonly property color glassStroke: "#50ffffff"
    readonly property color glassInnerStroke: "#18ffffff"
    readonly property color glassShadowLine: "#16000000"

    signal toggleLaunchpad()

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
        if (!dockHovered || !item || !dockSurface)
            return 1.0;

        var point = item.mapToItem(dockSurface, item.width / 2, item.height / 2);
        var distance = Math.abs(dockMouseX - point.x);
        var influence = Math.max(0, 1 - distance / 150);
        return 1.0 + influence * 0.5;
    }

    anchors {
        left: true
        right: true
        bottom: true
    }

    exclusiveZone: 98
    implicitHeight: 132
    color: "transparent"

    BackgroundEffect.blurRegion: Region {
        item: dockSurface
        radius: 24
    }

    Rectangle {
        id: dockSurface
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        width: Math.min(parent.width - 28, dockRow.implicitWidth + 34)
        height: 78
        radius: 24
        color: root.glassFill

        // NOTE: no `border.width` on the surface itself — a centered 1px
        // border antialiased against the outside pixels produces faint
        // near-square corners at the arc tangents. Draw the glass edges
        // with inset Rectangles instead, whose borders sit fully inside.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onPositionChanged: function(mouse) {
                root.dockMouseX = mouse.x;
            }
            onEntered: root.dockHovered = true
            onExited: {
                root.dockHovered = false;
                root.dockMouseX = -10000;
            }
        }

        Rectangle {
            // Top-left light edge (the Tahoe glass highlight).
            anchors.fill: parent
            anchors.margins: 1
            radius: 23
            color: "transparent"
            border.color: root.glassStroke
            border.width: 1
        }

        Rectangle {
            // Bottom-right shadow edge.
            anchors.fill: parent
            anchors.margins: 1
            radius: 23
            color: "transparent"
            border.color: "#14000000"
            border.width: 1
            z: -1
        }

        Rectangle {
            // Inner faint stroke (kept from the original double-inset).
            anchors.fill: parent
            anchors.margins: 2
            radius: 22
            color: "transparent"
            border.color: root.glassInnerStroke
            border.width: 1
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.topMargin: 1
            height: 1
            radius: 1
            color: "#4cffffff"
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            height: 1
            radius: 1
            color: root.glassShadowLine
        }

        Row {
            id: dockRow
            anchors.centerIn: parent
            spacing: 8

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
                    readonly property bool hovered: iconMouse.containsMouse
                    readonly property bool running: modelData.shellAction !== "launchpad"
                        && root.appsService
                        && root.niriService
                        && root.appsService.appHasRunningWindow(modelData, root.niriService.toplevelList)
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
                            root.dockMouseX = point.x;
                            root.dockHovered = true;
                        }
                        onEntered: root.dockHovered = true
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

                    // Underdamped spring on bounce — ~1.5 oscillations before
                    // settling. SpringAnimation drives a real second-order
                    // ODE, unlike the old two-step SequentialAnimation that
                    // went up once and came back once (no overshoot).
                    Behavior on bounceOffset {
                        SpringAnimation {
                            spring: 380
                            damping: 0.32
                            mass: 0.9
                            epsilon: 0.01
                        }
                    }

                    // Critically damped spring on magnification. Because
                    // magnification is bound to proximityScale(), this
                    // Behavior fires each time the pointer moves to a new
                    // icon, easing the icon scale + lift toward the new
                    // target. Without this the whole row snaps per-frame.
                    Behavior on magnification {
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
                    showTitle: true
                    magnification: root.proximityScale(windowButton)
                    dockWindow: root
                    dockSurfaceItem: dockSurface
                    onDockPointerMoved: function(x) {
                        root.dockMouseX = x;
                        root.dockHovered = true;
                    }
                    onDockPointerEntered: root.dockHovered = true
                }
            }
        }
    }
}
