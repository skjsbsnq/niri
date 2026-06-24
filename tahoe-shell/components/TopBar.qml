pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property var appsService
    property var appMenuService
    property var niriService
    property var notificationsService
    property var batteryService
    property var controlsService
    property var fanService
    property var clipboardService
    property var screenshotService
    property var inputMethodService
    property var dynamicIslandService
    property bool controlCenterOpen: false
    property bool launchpadOpen: false
    property bool appMenuOpen: false
    property bool applicationMenuOpen: false
    property bool spotlightOpen: false
    property bool notificationCenterOpen: false
    property bool batteryPopupOpen: false
    property bool wifiPopupOpen: false
    property bool fanPopupOpen: false
    property bool clipboardPopupOpen: false
    property bool darkMode: false
    readonly property string activeApp: appsService && niriService ? appsService.toplevelLabel(niriService.focusedWindow || niriService.activeToplevel) : "桌面"
    // Number of retained notification history entries. Drives the bell
    // badge and lets DND-suppressed notifications remain visible.
    readonly property int notificationCount: notificationsService ? notificationsService.historyCount : 0
    readonly property int clipboardCount: clipboardService ? clipboardService.historyCount : 0
    readonly property bool dndEnabled: notificationsService ? notificationsService.dndEnabled : false
    readonly property bool batteryAvailable: batteryService && batteryService.available
    readonly property color glassFill: darkMode ? "#d01d1f24" : GlassStyle.FillTopBar
    readonly property color glassStroke: darkMode ? "#38ffffff" : GlassStyle.StrokeTopBar
    readonly property color topText: darkMode ? "#f5f7fb" : "#202124"
    readonly property color topTextSecondary: darkMode ? "#d6dde5" : "#2c2d30"
    readonly property color buttonFill: darkMode ? "#24ffffff" : "#22ffffff"
    readonly property color buttonHover: darkMode ? "#36ffffff" : "#30ffffff"
    readonly property color buttonOpen: darkMode ? "#42ffffff" : "#38ffffff"
    readonly property color buttonBorder: darkMode ? "#52ffffff" : "#40ffffff"

    signal toggleAppMenu(var anchorRect)
    signal toggleApplicationMenu(var anchorRect)
    signal toggleControlCenter(var anchorRect)
    signal toggleSpotlight()
    signal toggleLaunchpad()
    signal toggleNotifications(var anchorRect)
    signal toggleBattery(var anchorRect)
    signal toggleWifi(var anchorRect)
    signal toggleFan(var anchorRect)
    signal toggleClipboard(var anchorRect)
    signal triggerScreenshot()
    signal toggleInputMethod()
    signal openTrayMenu(var item, var anchorRect)

    function anchorRectFor(item) {
        if (!item)
            return null;

        var rect = root.itemRect(item);
        return {
            "x": Math.round(rect.x),
            "y": Math.round(rect.y),
            "width": Math.round(rect.width),
            "height": Math.round(rect.height)
        };
    }

    visible: true

    anchors {
        left: true
        right: true
        top: true
    }

    exclusiveZone: 34
    implicitHeight: 34
    color: "transparent"
    WlrLayershell.namespace: "tahoe-topbar"

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
    TahoeGlass.regions: [
        TahoeGlassRegion {
            item: barSurface
            material: barSurface.tahoeGlassMaterial
            radius: barSurface.tahoeGlassRadius
            blur: true
            shadow: true
            clip: true
            materialAlpha: barSurface.opacity
            enabled: barSurface.opacity > 0.01
        }
    ]

    Rectangle {
        id: barSurface
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialPanel
        readonly property real tahoeGlassRadius: GlassStyle.RadiusTopBar

        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 5
        anchors.bottomMargin: 5
        radius: tahoeGlassRadius
        color: root.glassFill
        opacity: 1

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

        Item {
            id: topBarContent

            anchors.fill: parent
            // Inset content inside the floating bar surface so the end
            // children (status/control buttons and niri menu) clear the rounded
            // caps. The surface's radius is 18, so anything within ~14px
            // of the ends would clip under the arc.
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            readonly property int centerReserveWidth: root.width < 1500 ? 168 : 184

            Item {
                id: islandReserve

                anchors.centerIn: parent
                width: topBarContent.centerReserveWidth
                height: parent.height
            }

            Row {
                id: leftCluster

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, islandReserve.x - 14)
                height: 24
                spacing: 14
                clip: true

                Item {
                    id: niriMenuButton

                    width: 30
                    height: 24

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: root.appMenuOpen ? "#32ffffff" : "transparent"
                        border.color: root.appMenuOpen ? "#42ffffff" : "transparent"
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: Quickshell.shellPath("assets/icons/niri-icon-smol.png")
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleAppMenu(root.anchorRectFor(niriMenuButton))
                    }
                }

                Text {
                    text: root.activeApp
                    color: root.topTextSecondary
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    width: Math.min(implicitWidth, root.width < 1500 ? 168 : 220)
                    height: 24
                }

                Item {
                    id: applicationMenuButton
                    width: visible ? Math.min(applicationMenuLabel.implicitWidth + 18, root.width < 1500 ? 112 : 152) : 0
                    height: 24
                    visible: !!root.appMenuService

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: root.applicationMenuOpen ? "#32ffffff" : (applicationMenuMouse.containsMouse ? "#24ffffff" : "transparent")
                        border.color: root.applicationMenuOpen ? "#42ffffff" : "transparent"
                    }

                    Text {
                        id: applicationMenuLabel
                        anchors.centerIn: parent
                        width: Math.max(0, parent.width - 18)
                        text: root.appMenuService ? root.appMenuService.menuTitle : "应用菜单"
                        color: root.topText
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    MouseArea {
                        id: applicationMenuMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleApplicationMenu(root.anchorRectFor(applicationMenuButton))
                    }
                }

                Row {
                    y: 2
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
                                color: root.topText
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
            }

            RowLayout {
                id: rightCluster

                anchors.left: islandReserve.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                spacing: 14
                clip: true

                Item {
                    Layout.fillWidth: true
                }

            Tray {
                panelWindow: root
                Layout.preferredWidth: visible ? implicitWidth : 0
                Layout.preferredHeight: implicitHeight
                Layout.alignment: Qt.AlignVCenter
                onOpenMenuRequested: function(item, anchorRect) {
                    root.openTrayMenu(item, anchorRect);
                }
            }

            Item {
                id: notificationButton

                Layout.preferredWidth: 30
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.notificationCenterOpen ? root.buttonOpen : (badgeMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.color: root.buttonBorder
                }

                Text {
                    anchors.centerIn: parent
                    text: root.dndEnabled ? "\ue7f6" : "\ue7f4"
                    color: root.topText
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
                    onClicked: root.toggleNotifications(root.anchorRectFor(notificationButton))
                }
            }

            Item {
                id: clipboardButton

                Layout.preferredWidth: 30
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                visible: !!root.clipboardService

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.clipboardPopupOpen ? root.buttonOpen : (clipboardMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.color: root.buttonBorder
                }

                Text {
                    anchors.centerIn: parent
                    text: "\ue14f"
                    color: root.clipboardService && root.clipboardService.available ? root.topText : "#731d1d1f"
                    font.family: "Material Icons"
                    font.pixelSize: 16
                    opacity: root.clipboardService && root.clipboardService.available ? 1 : 0.5
                }

                Rectangle {
                    width: countText.implicitWidth + 7
                    height: 13
                    radius: 6.5
                    x: parent.width - width - 2
                    y: 1
                    color: "#cc2c9cf2"
                    border.color: "#ffffff"
                    border.width: 1
                    visible: root.clipboardCount > 0

                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: root.clipboardCount > 9 ? "9+" : root.clipboardCount
                        color: "#ffffff"
                        font.pixelSize: 8
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: clipboardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleClipboard(root.anchorRectFor(clipboardButton))
                }
            }

            Item {
                id: fanButton

                Layout.preferredWidth: 30
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                visible: !!root.fanService

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.fanPopupOpen ? root.buttonOpen : (fanMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.color: root.buttonBorder
                }

                Text {
                    anchors.centerIn: parent
                    text: "\ue332"
                    color: root.fanService && root.fanService.available && !root.fanService.autoMode ? "#0b6bd3" : root.topText
                    font.family: "Material Icons"
                    font.pixelSize: 16
                    opacity: root.fanService && root.fanService.available ? 1 : 0.5
                }

                Rectangle {
                    width: 5
                    height: 5
                    radius: 2.5
                    x: parent.width - width - 5
                    y: parent.height - height - 4
                    color: "#2c9cf2"
                    visible: root.fanService && root.fanService.available && !root.fanService.autoMode
                }

                MouseArea {
                    id: fanMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleFan(root.anchorRectFor(fanButton))
                }
            }

            Item {
                id: batteryButton

                Layout.preferredWidth: visible ? 58 : 0
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                visible: root.batteryAvailable

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.batteryPopupOpen ? root.buttonOpen : (batteryMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.color: root.buttonBorder
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.batteryService ? root.batteryService.roundedPercentage + "%" : ""
                    color: root.topText
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
                                : root.topText
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
                    onClicked: root.toggleBattery(root.anchorRectFor(batteryButton))
                }
            }

            Item {
                id: wifiButton

                Layout.preferredWidth: 30
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                visible: !!root.controlsService

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.wifiPopupOpen ? root.buttonOpen : (wifiMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.color: root.buttonBorder
                }

                Text {
                    anchors.centerIn: parent
                    text: "\ue63e"
                    color: root.controlsService && root.controlsService.wifiConnected ? "#0b6bd3" : root.topText
                    font.family: "Material Icons"
                    font.pixelSize: 16
                    opacity: root.controlsService && root.controlsService.wifiEnabled ? 1 : 0.45
                }

                Rectangle {
                    width: 5
                    height: 5
                    radius: 2.5
                    x: parent.width - width - 5
                    y: parent.height - height - 4
                    color: "#2c9cf2"
                    visible: root.controlsService && root.controlsService.wifiConnected
                }

                MouseArea {
                    id: wifiMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWifi(root.anchorRectFor(wifiButton))
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
                    color: root.spotlightOpen ? root.buttonOpen : (spotlightMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.color: root.buttonBorder
                }

                Text {
                    anchors.centerIn: parent
                    text: "\ue8b6"
                    color: root.topText
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

            Item {
                id: inputMethodButton
                Layout.preferredWidth: visible ? 36 : 0
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                visible: !!root.inputMethodService

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: inputMethodMouse.containsMouse ? root.buttonHover : root.buttonFill
                    border.color: root.buttonBorder
                }

                Text {
                    anchors.centerIn: parent
                    text: root.inputMethodService ? root.inputMethodService.displayText : "--"
                    color: root.inputMethodService && root.inputMethodService.active ? "#0b6bd3" : root.topText
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    opacity: root.inputMethodService && root.inputMethodService.available ? 1 : 0.45
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                MouseArea {
                    id: inputMethodMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.inputMethodService && root.inputMethodService.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.toggleInputMethod()
                }
            }

            Item {
                id: screenshotButton
                Layout.preferredWidth: visible ? 30 : 0
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                visible: !!root.screenshotService

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: screenshotMouse.containsMouse ? root.buttonHover : root.buttonFill
                    border.color: root.buttonBorder
                }

                Text {
                    anchors.centerIn: parent
                    text: "\ue3b0"
                    color: root.topText
                    font.family: "Material Icons"
                    font.pixelSize: 16
                }

                MouseArea {
                    id: screenshotMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.triggerScreenshot()
                }
            }

            Item {
                id: statusButton
                Layout.preferredWidth: 30
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.controlCenterOpen ? root.buttonOpen : root.buttonFill
                    border.color: root.buttonBorder
                }

                Item {
                    anchors.centerIn: parent
                    width: 18
                    height: 14

                    Rectangle {
                        x: 0
                        y: 3
                        width: 18
                        height: 2
                        radius: 1
                        color: root.topText
                        opacity: 0.86
                    }

                    Rectangle {
                        x: 3
                        y: 0
                        width: 6
                        height: 8
                        radius: 3
                        color: root.topText
                    }

                    Rectangle {
                        x: 0
                        y: 10
                        width: 18
                        height: 2
                        radius: 1
                        color: root.topText
                        opacity: 0.86
                    }

                    Rectangle {
                        x: 10
                        y: 7
                        width: 6
                        height: 8
                        radius: 3
                        color: root.topText
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleControlCenter(root.anchorRectFor(statusButton))
                }
            }
            }

            DynamicIslandChip {
                id: islandChip

                anchors.centerIn: islandReserve
                width: implicitWidth
                height: implicitHeight
                displayText: root.dynamicIslandService ? root.dynamicIslandService.displayText : ""
                darkMode: root.darkMode
                z: 2
                onClicked: function(button) {
                    if (root.dynamicIslandService)
                        root.dynamicIslandService.handleChipClick(button);
                }
            }
        }
    }
}
