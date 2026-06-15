pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "TahoeGlass.js" as TahoeGlass

PanelWindow {
    id: root

    property var appsService
    property var niriService
    property var notificationsService
    property var batteryService
    property bool controlCenterOpen: false
    property bool launchpadOpen: false
    property bool appMenuOpen: false
    property bool spotlightOpen: false
    property bool notificationCenterOpen: false
    property bool batteryPopupOpen: false
    property date now: new Date()
    readonly property string activeApp: appsService && niriService ? appsService.toplevelLabel(niriService.focusedWindow || niriService.activeToplevel) : "Desktop"
    // Number of retained notification history entries. Drives the bell
    // badge and lets DND-suppressed notifications remain visible.
    readonly property int notificationCount: notificationsService ? notificationsService.historyCount : 0
    readonly property bool dndEnabled: notificationsService ? notificationsService.dndEnabled : false
    readonly property bool batteryAvailable: batteryService && batteryService.available
    readonly property color glassFill: TahoeGlass.FillTopBar
    readonly property color glassStroke: TahoeGlass.StrokeTopBar
    readonly property color glassShadowLine: "#10000000"

    signal toggleAppMenu()
    signal toggleControlCenter()
    signal toggleSpotlight()
    signal toggleLaunchpad()
    signal toggleNotifications()
    signal toggleBattery()
    signal openTrayMenu(var item)

    // When the Launchpad opens, the TopBar must disappear so the Launchpad
    // scrim truly covers everything. Otherwise the TopBar is a sibling
    // layer-shell panel that stays stacked above the Launchpad backdrop
    // and keeps blurring its own slice of the screen, so the three panels
    // (Dock / TopBar / Launchpad) each compute their own glass and the
    // Launchpad looks "not fully covering". See glass-consistency-fix-
    // plan.md §1.2 B / §1.3 B.
    //
    // Visible stays true until the fade-out finishes so the panel is
    // unmapped (and its blurRegion stops sampling) only once it's gone;
    // during the fade the Launchpad scrim covers any residual blur.
    visible: !launchpadOpen || barSurface.opacity > 0.01

    anchors {
        left: true
        right: true
        top: true
    }

    exclusiveZone: 34
    implicitHeight: 34
    color: "transparent"
    WlrLayershell.namespace: "tahoe-topbar"

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    // Floating, rounded glass bar — mirrors the Dock / ControlCenter form
    // so the top bar reads as "a piece of glass floating off the screen
    // edge" instead of a full-width strip glued to the top. The
    // PanelWindow itself stays transparent and keeps exclusiveZone 34 so
    // window layout doesn't shift; only the inner barSurface floats with
    // insets. See glass-consistency-fix-plan.md §2.3.
    //
    // The insets are 8px left/right and 5px top/bottom rather than a flat
    // 8 all around: a flat 8 on implicitHeight 34 would leave barSurface
    // only 18px tall, which cannot fit the 24px-tall RowLayout children
    // (they'd be clipped — violating §2.6 acceptance). 5/5 vertically
    // yields a 24px-tall surface that just fits the content while still
    // floating off every edge.
    BackgroundEffect.blurRegion: Region {
        item: barSurface
        // MUST match barSurface.radius or the blur leaks past the rounded
        // corners (project convention — see NotificationToast.qml).
        radius: barSurface.tahoeGlassRadius
    }

    Rectangle {
        id: barSurface
        readonly property string tahoeGlassMaterial: TahoeGlass.MaterialPanel
        readonly property real tahoeGlassRadius: TahoeGlass.RadiusTopBar

        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 5
        anchors.bottomMargin: 5
        radius: tahoeGlassRadius
        color: root.glassFill
        // Fade the bar surface out when the Launchpad opens (see the
        // visible binding above). NumberAnimation, not spring — see
        // shell.qml useSpring.
        opacity: root.launchpadOpen ? 0 : 1

        Behavior on opacity {
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }

        // NOTE: no `border.width` on the surface itself — a centered 1px
        // border is antialiased against the pixels OUTSIDE the rect and
        // produces faint near-square corners where the arc is tangent to
        // the straight edges. Draw the glass edges with inset Rectangles
        // instead, whose borders sit fully inside the surface and never
        // overshoot (same convention as Dock.qml / NotificationToast.qml).
        Rectangle {
            // Top-left light edge (the Tahoe glass highlight).
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: root.glassStroke
            border.width: 1
        }

        Rectangle {
            // Bottom-right shadow edge.
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: root.glassShadowLine
            border.width: 1
            z: -1
        }

        RowLayout {
            anchors.fill: parent
            // Inset the row inside the floating bar surface so the end
            // children (status button / tahoe label) clear the rounded
            // caps. The surface's radius is 18, so anything within ~14px
            // of the ends would clip under the arc.
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 14

            Item {
                Layout.preferredWidth: tahoeLabel.implicitWidth + 18
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.appMenuOpen ? "#32ffffff" : "transparent"
                    border.color: root.appMenuOpen ? "#42ffffff" : "transparent"
                }

                Text {
                    id: tahoeLabel
                    anchors.centerIn: parent
                    text: "Tahoe"
                    color: "#202124"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleAppMenu()
                }
            }

            Text {
                text: root.activeApp
                color: "#2c2d30"
                font.pixelSize: 13
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: 220
            }

            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 5

                Repeater {
                    model: ScriptModel {
                        values: root.niriService ? root.niriService.visibleWindowsets : []
                    }

                    delegate: Item {
                        required property var modelData
                        required property int index

                        width: 28
                        height: 20

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: modelData.active ? "#32ffffff" : "#18ffffff"
                            border.color: modelData.urgent ? "#ccff453a" : "#36ffffff"
                            border.width: 1
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.niriService ? root.niriService.workspaceLabel(modelData, index) : String(index + 1)
                            color: "#202124"
                            font.pixelSize: 11
                            font.weight: modelData.active ? Font.DemiBold : Font.Normal
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: modelData.canActivate ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (root.niriService)
                                    root.niriService.activateWorkspace(modelData);
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Tray {
                panelWindow: root
                Layout.preferredWidth: visible ? implicitWidth : 0
                Layout.preferredHeight: implicitHeight
                Layout.alignment: Qt.AlignVCenter
                onOpenMenuRequested: function(item) {
                    root.openTrayMenu(item);
                }
            }

            Item {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.notificationCenterOpen ? "#38ffffff" : (badgeMouse.containsMouse ? "#30ffffff" : "#22ffffff")
                    border.color: "#40ffffff"
                }

                Text {
                    anchors.centerIn: parent
                    text: root.dndEnabled ? "\ue7f6" : "\ue7f4"
                    color: "#202124"
                    font.family: "Material Icons"
                    font.pixelSize: 16
                    opacity: root.notificationCount > 0 || root.dndEnabled ? 1 : 0.68
                }

                Rectangle {
                    // Count pip, top-right of the bell.
                    x: parent.width - width - 3
                    y: 1
                    width: countLabel.implicitWidth + 8
                    height: 14
                    radius: 7
                    color: "#ccff453a"
                    border.color: "#ffffff"
                    border.width: 1
                    visible: root.notificationCount > 0

                    Text {
                        id: countLabel
                        anchors.centerIn: parent
                        text: root.notificationCount > 9 ? "9+" : root.notificationCount
                        color: "#ffffff"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: badgeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleNotifications()
                }
            }

            Item {
                Layout.preferredWidth: visible ? 58 : 0
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                visible: root.batteryAvailable

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.batteryPopupOpen ? "#38ffffff" : (batteryMouse.containsMouse ? "#30ffffff" : "#22ffffff")
                    border.color: "#40ffffff"
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.batteryService ? root.batteryService.roundedPercentage + "%" : ""
                    color: "#202124"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Item {
                    width: 20
                    height: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 7
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        id: batteryOutline
                        x: 0
                        y: 2
                        width: 17
                        height: 9
                        radius: 3
                        color: "transparent"
                        border.color: "#99202124"
                        border.width: 1

                        Rectangle {
                            x: 2
                            y: 2
                            width: root.batteryService ? Math.max(2, (parent.width - 4) * root.batteryService.roundedPercentage / 100) : 2
                            height: parent.height - 4
                            radius: 2
                            color: root.batteryService && root.batteryService.roundedPercentage <= 15 && root.batteryService.onBattery
                                ? "#ff453a"
                                : "#202124"
                        }
                    }

                    Rectangle {
                        x: 18
                        y: 5
                        width: 2
                        height: 3
                        radius: 1
                        color: "#99202124"
                    }
                }

                MouseArea {
                    id: batteryMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleBattery()
                }
            }

            Item {
                id: spotlightButton
                Layout.preferredWidth: 30
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.spotlightOpen ? "#38ffffff" : (spotlightMouse.containsMouse ? "#30ffffff" : "#22ffffff")
                    border.color: "#40ffffff"
                }

                Text {
                    anchors.centerIn: parent
                    text: "\ue8b6"
                    color: "#202124"
                    font.family: "Material Icons"
                    font.pixelSize: 16
                }

                MouseArea {
                    id: spotlightMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleSpotlight()
                }
            }

            Text {
                text: Qt.formatDateTime(root.now, "ddd HH:mm")
                color: "#2c2d30"
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                id: statusButton
                Layout.preferredWidth: 44
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.controlCenterOpen ? "#38ffffff" : "#22ffffff"
                    border.color: "#40ffffff"
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        text: root.niriService ? root.niriService.activeWorkspaceName : "1"
                        color: "#202124"
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleControlCenter()
                }
            }
        }
    }
}
