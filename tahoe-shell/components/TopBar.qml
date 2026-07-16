pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "Motion.js" as Motion
import "TahoeGlass.js" as GlassStyle
import "DynamicIslandMotion.js" as IslandMotion
import "settings/SettingsTheme.js" as Theme

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
    property var settingsService
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
    property bool leftSidebarOpen: false
    property bool darkMode: false
    readonly property string activeApp: appsService && niriService ? appsService.windowAppLabel(niriService.focusedWindow || niriService.activeToplevel) : "桌面"
    // Number of retained notification history entries. Drives the bell
    // badge and lets DND-suppressed notifications remain visible.
    readonly property int notificationCount: notificationsService ? notificationsService.historyCount : 0
    readonly property int clipboardCount: clipboardService ? clipboardService.historyCount : 0
    readonly property bool dndEnabled: notificationsService ? notificationsService.dndEnabled : false
    readonly property bool dynamicIslandEnabled: settingsService ? !!settingsService.dynamicIslandEnabled : true
    readonly property bool dynamicIslandHideTopbarTime: settingsService ? !!settingsService.dynamicIslandHideTopbarTime : true
    readonly property bool dynamicIslandHoverExpand: settingsService ? !!settingsService.dynamicIslandHoverExpand : false
    // T08: TopBar resting clock is not blanked on non-owner outputs.
    // hideTopbarTime=true → Overlay shows base clock on every screen (including
    // non-owner); TopBar hides its time text. hideTopbarTime=false → TopBar
    // always shows ordinary time; Overlay only appears for owner activity.
    readonly property bool dynamicIslandOverlayHandlesResting: dynamicIslandEnabled && dynamicIslandHideTopbarTime
    readonly property bool showTopbarTimeFallback: !dynamicIslandEnabled || !dynamicIslandHideTopbarTime
    readonly property bool chipInteractive: dynamicIslandEnabled && !dynamicIslandOverlayHandlesResting
    readonly property int islandInputCutoutWidth: Math.min(root.width, root.dynamicIslandInputWidth())
    readonly property int islandInputCutoutLeft: Math.max(0, Math.floor((root.width - root.islandInputCutoutWidth) / 2))
    readonly property int islandInputCutoutRight: Math.min(root.width, root.islandInputCutoutLeft + root.islandInputCutoutWidth)
    readonly property bool batteryAvailable: batteryService && batteryService.available
    // Single InputMethod owner language glyph (中/EN/あ/한/Aa/--).
    readonly property string inputMethodDisplayText: inputMethodService
        ? String(inputMethodService.displayText || "--")
        : "--"
    readonly property color glassFill: darkMode ? "#d01d1f24" : GlassStyle.FillTopBar
    readonly property color glassStroke: darkMode ? "#38ffffff" : GlassStyle.StrokeTopBar
    readonly property string accentId: settingsService ? settingsService.accentColor : "blue"
    readonly property color topText: Theme.label(darkMode)
    readonly property color topTextSecondary: Theme.topTextSecondary(darkMode)
    readonly property color statusText: topText
    readonly property color statusTextDisabled: darkMode ? "#73f5f7fb" : "#731d1d1f"
    readonly property color statusTextFaint: darkMode ? "#99f5f7fb" : "#991d1d1f"
    readonly property color statusAttention: Theme.statusAttention(darkMode)
    readonly property color accentColor: Theme.accent(darkMode, accentId)
    // Status-row hit target; slightly taller/wider so 18–20px symbols
    // optically match tray IconImage (16px full-bleed color icons).
    readonly property int statusItemHeight: 24
    readonly property int statusIconWidth: 28
    // TahoeSymbol display size (was 16; Material PNG padding made it look small).
    // 20 reads closer to tray IconImage 16px full-bleed; drop to 18 if crowded.
    readonly property int statusSymbolSize: 20
    readonly property int batteryItemMinWidth: 66
    readonly property int statusRadius: 7
    readonly property color buttonFill: "transparent"
    readonly property color buttonHover: Theme.buttonHover(darkMode)
    readonly property color buttonOpen: Theme.buttonOpen(darkMode)

    signal toggleAppMenu(var anchorRect)
    signal toggleApplicationMenu(var anchorRect)
    signal toggleControlCenter(var anchorRect)
    signal toggleSpotlight()
    signal toggleLaunchpad()
    signal toggleLeftSidebar()
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

    function dynamicIslandInputWidth() {
        if (!root.dynamicIslandOverlayHandlesResting)
            return 0;

        var presentation = root.dynamicIslandService
            ? String(root.dynamicIslandService.presentation || "resting_time")
            : "resting_time";
        switch (presentation) {
        case "expanded_media":
            return IslandMotion.v2MediaExpandedWidthMax;
        case "expanded_timer":
            return IslandMotion.v2TimerExpandedWidthMax;
        case "transient_notification":
            return IslandMotion.v2NotificationExpandedWidthMax;
        case "transient_osd":
            return IslandMotion.v2OsdWidthMax;
        case "transient_workspace":
        case "resting_timer":
        case "transient_timer_complete":
            return IslandMotion.v2WorkspaceWidthMax;
        case "resting_media":
        case "resting_time":
        default:
            // The visual clock may be narrower, but the stable center reserve is
            // intentionally non-interactive while the overlay owns the island.
            return IslandMotion.v2CompactMediaWidthMax;
        }
    }

    visible: true

    anchors {
        left: true
        right: true
        top: true
    }

    // DynamicIslandOverlay is the sole input owner for the center span. A real
    // cutout lets its native click/swipe/wheel lifecycle work regardless of
    // sibling Top-layer stacking order.
    mask: Region {
        Region {
            x: 0
            y: 0
            width: root.dynamicIslandOverlayHandlesResting
                ? root.islandInputCutoutLeft
                : root.width
            height: root.height
        }
        Region {
            x: root.islandInputCutoutRight
            y: 0
            width: root.dynamicIslandOverlayHandlesResting
                ? Math.max(0, root.width - root.islandInputCutoutRight)
                : 0
            height: root.height
        }
    }

    exclusiveZone: 40
    implicitHeight: 40
    color: "transparent"
    WlrLayershell.namespace: "tahoe-topbar"

    // Floating, rounded glass bar — mirrors the Dock / ControlCenter form
    // so the top bar reads as "a piece of glass floating off the screen
    // edge" instead of a full-width strip glued to the top. The
    // PanelWindow itself stays transparent and keeps exclusiveZone 34 so
    // window layout doesn't shift; only the inner barSurface floats with
    // insets. See glass-consistency-fix-plan.md §2.3.
    //
    // Keep the surface thick enough to read as glass after the shared panel
    // material was made more restrained for bright backgrounds.
    TahoeGlass.regions: [barSurface.region]

    GlassPanel {
        id: barSurface

        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        material: GlassStyle.MaterialPanel
        radius: GlassStyle.RadiusTopBar
        fillColor: root.glassFill
        strokeColor: root.glassStroke
        interaction: 0.0
        materialAlpha: opacity
        glassEnabled: opacity > 0.01
        opacity: 1

        // Local exception: topbar glass fade is slightly shorter than panelEnter
        // so clock/status reveal does not lag behind compositor layer motion.
        Behavior on opacity {
            NumberAnimation { duration: 170; easing.type: Motion.emphasizedDecel }
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
            // T12: stable reserve covers max compact media so clock↔media does not
            // shove left/right clusters. Not tied to current island state width.
            readonly property int centerReserveWidth: IslandMotion.v2CompactMediaWidthMax

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
                    scale: Motion.pressScaleFor(root.settingsService, niriMenuMouse.pressed)
                    opacity: niriMenuMouse.pressed ? 0.75 : 1

                    Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                    Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: root.appMenuOpen ? "#32ffffff" : "transparent"
                        border.width: 0
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
                        id: niriMenuMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleAppMenu(root.anchorRectFor(niriMenuButton))
                    }
                }

                Item {
                    id: leftSidebarButton

                    width: 30
                    height: 24
                    scale: Motion.pressScaleFor(root.settingsService, leftSidebarMouse.pressed)
                    opacity: leftSidebarMouse.pressed ? 0.75 : 1

                    Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                    Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: root.leftSidebarOpen ? root.buttonOpen : (leftSidebarMouse.containsMouse ? root.buttonHover : "transparent")
                        border.width: 0
                    }

                    TahoeSymbol {
                        anchors.centerIn: parent
                        name: "\ue2bd" // wb_cloudy
                        color: root.leftSidebarOpen ? root.accentColor : root.topTextSecondary
                        size: root.statusSymbolSize
                    }

                    MouseArea {
                        id: leftSidebarMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleLeftSidebar()
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
                    scale: Motion.pressScaleFor(root.settingsService, applicationMenuMouse.pressed)
                    opacity: applicationMenuMouse.pressed ? 0.75 : 1

                    Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                    Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: root.applicationMenuOpen ? "#32ffffff" : (applicationMenuMouse.containsMouse ? "#24ffffff" : "transparent")
                        border.width: 0
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
                            scale: Motion.pressScaleFor(root.settingsService, workspaceMouse.pressed && modelData.canActivate)
                            opacity: workspaceMouse.pressed && modelData.canActivate ? 0.75 : 1

                            Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                            Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

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
                                id: workspaceMouse
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
                spacing: 9
                clip: true

                Item {
                    Layout.fillWidth: true
                }

            Tray {
                panelWindow: root
                settingsService: root.settingsService
                darkMode: root.darkMode
                Layout.preferredWidth: visible ? implicitWidth : 0
                Layout.preferredHeight: implicitHeight
                Layout.alignment: Qt.AlignVCenter
                onOpenMenuRequested: function(item, anchorRect) {
                    root.openTrayMenu(item, anchorRect);
                }
            }

            Item {
                id: notificationButton

                Layout.preferredWidth: root.statusIconWidth
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                scale: Motion.pressScaleFor(root.settingsService, badgeMouse.pressed)
                opacity: badgeMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.notificationCenterOpen ? root.buttonOpen : (badgeMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0
                }

                TahoeSymbol {
                    anchors.centerIn: parent
                    name: root.dndEnabled ? "\ue7f6" : "\ue7f4"
                    color: root.statusText
                    size: root.statusSymbolSize
                    opacity: root.notificationCount > 0 || root.dndEnabled ? 1 : 0.68
                }

                Rectangle {
                    // Count pip, top-right of the bell.
                    x: parent.width - width - 3
                    y: 1
                    width: countLabel.implicitWidth + 8
                    height: 14
                    radius: 7
                    color: root.statusAttention
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

                Layout.preferredWidth: visible ? root.statusIconWidth : 0
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                visible: !!root.clipboardService
                scale: Motion.pressScaleFor(root.settingsService, clipboardMouse.pressed)
                opacity: clipboardMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.clipboardPopupOpen ? root.buttonOpen : (clipboardMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0
                }

                TahoeSymbol {
                    anchors.centerIn: parent
                    name: "\ue14f"
                    color: root.clipboardService && root.clipboardService.available ? root.statusText : root.statusTextDisabled
                    size: root.statusSymbolSize
                    opacity: root.clipboardService && root.clipboardService.available ? 1 : 0.5
                }

                Rectangle {
                    width: countText.implicitWidth + 7
                    height: 13
                    radius: 6.5
                    x: parent.width - width - 2
                    y: 1
                    color: root.statusAttention
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

                Layout.preferredWidth: visible ? root.statusIconWidth : 0
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                visible: !!root.fanService
                scale: Motion.pressScaleFor(root.settingsService, fanMouse.pressed)
                opacity: fanMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.fanPopupOpen ? root.buttonOpen : (fanMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0
                }

                TahoeSymbol {
                    anchors.centerIn: parent
                    name: "\ue332"
                    color: root.statusText
                    size: root.statusSymbolSize
                    opacity: root.fanService && root.fanService.available ? (root.fanService.autoMode ? 0.76 : 1) : 0.45
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

                Layout.preferredWidth: visible ? Math.max(root.batteryItemMinWidth, batteryContent.implicitWidth + 12) : 0
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                visible: root.batteryAvailable
                scale: Motion.pressScaleFor(root.settingsService, batteryMouse.pressed)
                opacity: batteryMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.batteryPopupOpen ? root.buttonOpen : (batteryMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0
                }

                RowLayout {
                    id: batteryContent

                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: root.batteryService ? root.batteryService.roundedPercentage + "%" : ""
                        color: root.statusText
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 14
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            id: batteryOutline
                            x: 0
                            y: 1.5
                            width: 20
                            height: 11
                            radius: 3
                            color: "transparent"
                            border.color: root.statusTextFaint
                            border.width: 1

                            Rectangle {
                                x: 2
                                y: 2
                                width: root.batteryService ? Math.max(2, (parent.width - 4) * root.batteryService.roundedPercentage / 100) : 2
                                height: parent.height - 4
                                radius: 2
                                color: root.batteryService && root.batteryService.roundedPercentage <= 15 && root.batteryService.onBattery
                                    ? root.statusAttention
                                    : root.statusText
                            }
                        }

                        Rectangle {
                            x: 21
                            y: 5
                            width: 2
                            height: 4
                            radius: 1
                            color: root.statusTextFaint
                        }
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
                id: inputMethodButton

                Layout.preferredWidth: Math.max(root.statusIconWidth, inputMethodLabel.implicitWidth + 10)
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                // Always show the language glyph; unavailable uses "--" from displayText.
                scale: Motion.pressScaleFor(root.settingsService, inputMethodMouse.pressed)
                opacity: inputMethodMouse.pressed ? 0.75 : (root.inputMethodService && root.inputMethodService.available ? 1 : 0.55)

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: inputMethodMouse.containsMouse ? root.buttonHover : root.buttonFill
                    border.width: 0
                }

                Text {
                    id: inputMethodLabel
                    anchors.centerIn: parent
                    // Unique InputMethod.displayText consumer — 中 / EN / あ / 한 / Aa / --
                    text: root.inputMethodDisplayText
                    color: root.statusText
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: inputMethodMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleInputMethod()
                }
            }

            Item {
                id: wifiButton

                Layout.preferredWidth: visible ? root.statusIconWidth : 0
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                visible: !!root.controlsService
                scale: Motion.pressScaleFor(root.settingsService, wifiMouse.pressed)
                opacity: wifiMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.wifiPopupOpen ? root.buttonOpen : (wifiMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0
                }

                TahoeSymbol {
                    anchors.centerIn: parent
                    name: "\ue63e"
                    color: root.statusText
                    size: root.statusSymbolSize
                    opacity: root.controlsService && root.controlsService.wifiEnabled ? 1 : 0.45
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
                Layout.preferredWidth: root.statusIconWidth
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                scale: Motion.pressScaleFor(root.settingsService, spotlightMouse.pressed)
                opacity: spotlightMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.spotlightOpen ? root.buttonOpen : (spotlightMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0
                }

                TahoeSymbol {
                    anchors.centerIn: parent
                    name: "\ue8b6"
                    color: root.statusText
                    size: root.statusSymbolSize
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
                id: statusButton
                Layout.preferredWidth: root.statusIconWidth
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                scale: Motion.pressScaleFor(root.settingsService, statusMouse.pressed)
                opacity: statusMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.controlCenterOpen ? root.buttonOpen : (statusMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0
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
                        color: root.statusText
                        opacity: 0.86
                    }

                    Rectangle {
                        x: 3
                        y: 0
                        width: 6
                        height: 8
                        radius: 3
                        color: root.statusText
                    }

                    Rectangle {
                        x: 0
                        y: 10
                        width: 18
                        height: 2
                        radius: 1
                        color: root.statusText
                        opacity: 0.86
                    }

                    Rectangle {
                        x: 10
                        y: 7
                        width: 6
                        height: 8
                        radius: 3
                        color: root.statusText
                    }
                }

                MouseArea {
                    id: statusMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleControlCenter(root.anchorRectFor(statusButton))
                }
            }
            }

            // T12: ordinary readable time when island is disabled or Overlay does
            // not own resting (hideTopbarTime=false). No faux island chip.
            Text {
                id: topbarTimeFallback

                anchors.centerIn: islandReserve
                z: 2
                visible: root.showTopbarTimeFallback
                text: root.dynamicIslandService
                      ? String(root.dynamicIslandService.fallbackTimeText || "")
                      : ""
                color: root.topText
                font.pixelSize: 13
                font.weight: Font.DemiBold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                width: Math.min(islandReserve.width, Math.max(implicitWidth, 1))

                MouseArea {
                    anchors.fill: parent
                    enabled: root.chipInteractive && topbarTimeFallback.visible
                    hoverEnabled: root.chipInteractive
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: root.chipInteractive ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: function(mouse) {
                        if (root.dynamicIslandService)
                            root.dynamicIslandService.handleChipClick(
                                mouse.button,
                                root.screen ? String(root.screen.name || "") : "");
                    }
                    onEntered: {
                        if (!root.dynamicIslandHoverExpand || !root.dynamicIslandService)
                            return;
                        topbarIslandHoverCollapse.stop();
                        topbarIslandHoverExpand.restart();
                    }
                    onExited: {
                        topbarIslandHoverExpand.stop();
                        if (root.dynamicIslandHoverExpand && root.dynamicIslandService)
                            topbarIslandHoverCollapse.restart();
                    }
                }

                Timer {
                    id: topbarIslandHoverExpand
                    interval: IslandMotion.hoverExpandDelayMs
                    repeat: false
                    onTriggered: {
                        if (root.dynamicIslandService)
                            root.dynamicIslandService.requestHoverExpand(
                                root.screen ? String(root.screen.name || "") : "");
                    }
                }

                Timer {
                    id: topbarIslandHoverCollapse
                    interval: IslandMotion.hoverCollapseDelayMs
                    repeat: false
                    onTriggered: {
                        if (root.dynamicIslandService)
                            root.dynamicIslandService.requestHoverCollapse();
                    }
                }
            }
        }
    }

}
