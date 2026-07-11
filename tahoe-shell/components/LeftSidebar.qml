pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion
import "settings/SettingsTheme.js" as Theme

// LS05/LS11: left-edge shell container. It owns the glass shell and tab
// switching; System/Weather pages own their own content and data presentation.
PanelWindow {
    id: root

    property bool open: false
    property string currentTab: "system"
    property var systemStatsService
    property var weatherService
    property var settingsService
    property var batteryService
    property bool darkMode: false
    property string monoFontFamily: "Noto Sans Mono CJK SC"

    readonly property int screenWidth: Math.max(1, Number(root.screen && root.screen.width) || root.width)
    readonly property int screenHeight: Math.max(1, Number(root.screen && root.screen.height) || root.height)
    readonly property int panelWidth: Math.max(320, Math.min(540, screenWidth - 24))
    readonly property color glassFill: darkMode ? "#d01d1f24" : GlassStyle.FillPanel
    readonly property color glassStroke: darkMode ? "#38ffffff" : GlassStyle.StrokePanel
    readonly property string accentId: settingsService ? settingsService.accentColor : "blue"
    readonly property color cardFill: Theme.cardFill(darkMode)
    readonly property color cardStroke: Theme.cardStroke(darkMode)
    readonly property color textPrimary: Theme.label(darkMode)
    readonly property color textSecondary: Theme.secondaryLabel(darkMode)
    readonly property color textTertiary: Theme.tertiaryLabel(darkMode)
    readonly property color accentBlue: Theme.accent(darkMode, accentId)
    readonly property bool compositorLayerAnimations: !!(settingsService && settingsService.compositorLayerAnimations)
    readonly property real closedSlideX: -(panelWidth + 24)
    readonly property bool qmlSlideActive: !compositorLayerAnimations && slideTransform.x > closedSlideX + 0.5

    signal closeRequested()
    signal openWeatherSettingsRequested()
    // LS07：透传系统页右键请求给 shell（shell 实例化 ProcessMenu + PopupDismissLayer）。
    // processMenuOpen 由 shell 驱动，回灌到系统页暂停进程刷新。
    signal openProcessMenuRequested(var proc, var anchorRect)
    property bool processMenuOpen: false

    visible: compositorLayerAnimations ? open : (open || qmlSlideActive)
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    focusable: open
    implicitWidth: panelWidth
    implicitHeight: screenHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "tahoe-left-sidebar"

    anchors {
        left: true
        top: true
        bottom: true
    }

    mask: Region {
        Region {
            x: Math.round(panel.x + slideTransform.x)
            y: Math.round(panel.y)
            width: panel.width
            height: panel.height
            radius: panel.radius
        }
    }

    TahoeGlass.regions: [panel.region]

    onOpenChanged: {
        if (open) {
            Qt.callLater(function() {
                if (root.open)
                    focusCatcher.forceActiveFocus();
            });
        }
    }

    GlassPanel {
        id: panel

        x: 0
        y: 0
        width: root.panelWidth
        height: root.height
        material: GlassStyle.MaterialPanel
        radius: GlassStyle.RadiusPanel
        fillColor: root.glassFill
        strokeColor: root.glassStroke
        useItemRegion: false
        // Explicit geometry includes the QML Translate fallback. Binding
        // through `item: panel` does not include item transforms, which makes
        // the blur stay at the final position while the painted panel slides.
        regionX: Math.round(panel.x + slideTransform.x)
        regionY: Math.round(panel.y)
        regionWidth: panel.width
        regionHeight: panel.height
        interaction: 0.0
        regionEnabled: root.compositorLayerAnimations || root.open || root.qmlSlideActive
        opacity: 1

        transform: Translate {
            id: slideTransform

            x: root.compositorLayerAnimations ? 0 : (root.open ? 0 : root.closedSlideX)

            Behavior on x {
                enabled: !root.compositorLayerAnimations
                NumberAnimation {
                    duration: root.open ? Motion.panelEnter(root.settingsService) : Motion.panelExit(root.settingsService)
                    easing.type: root.open ? Motion.emphasizedDecel : Motion.standardDecel
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                spacing: 10

                Text {
                    text: "左侧边栏"
                    color: root.textPrimary
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 15
                    color: closeMouse.containsMouse ? root.cardFill : "transparent"
                    border.color: closeMouse.containsMouse ? root.cardStroke : "transparent"
                    border.width: 1

                    TahoeSymbol {
                        anchors.centerIn: parent
                        name: "\ue5cd" // close
                        color: root.textSecondary
                        size: 18
                    }

                    MouseArea {
                        id: closeMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }

            Item {
                id: tabBar

                property string hoveredTab: tabMouse.containsMouse
                    ? (tabMouse.mouseX < tabBar.width / 2 ? "system" : "weather")
                    : ""

                Layout.fillWidth: true
                Layout.preferredHeight: 38
                z: 2

                Row {
                    anchors.fill: parent
                    spacing: 8

                    TabButton {
                        width: Math.max(0, (tabBar.width - 8) / 2)
                        height: tabBar.height
                        label: "系统"
                        iconCode: "\ue8b8" // settings
                        active: root.currentTab === "system"
                        hovered: tabBar.hoveredTab === "system"
                    }

                    TabButton {
                        width: Math.max(0, (tabBar.width - 8) / 2)
                        height: tabBar.height
                        label: "天气"
                        iconCode: "\ue2bd" // wb_cloudy
                        active: root.currentTab === "weather"
                        hovered: tabBar.hoveredTab === "weather"
                    }
                }

                MouseArea {
                    id: tabMouse

                    anchors.fill: parent
                    z: 10
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        root.currentTab = mouse.x < width / 2 ? "system" : "weather";
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                LeftSidebarSystem {
                    id: systemView
                    anchors.fill: parent
                    visible: root.currentTab === "system"
                    systemStats: root.systemStatsService
                    batteryService: root.batteryService
                    settingsService: root.settingsService
                    sidebarPanel: root
                    darkMode: root.darkMode
                    monoFontFamily: root.monoFontFamily
                    processMenuOpen: root.processMenuOpen
                    onOpenProcessMenu: function(proc, anchorRect) {
                        root.openProcessMenuRequested(proc, anchorRect);
                    }
                }

                LeftSidebarWeather {
                    anchors.fill: parent
                    visible: root.currentTab === "weather"
                    weatherService: root.weatherService
                    settingsService: root.settingsService
                    sidebarOpen: root.open
                    active: root.currentTab === "weather"
                    darkMode: root.darkMode
                    monoFontFamily: root.monoFontFamily
                    onOpenWeatherSettingsRequested: root.openWeatherSettingsRequested()
                }
            }
        }

        Item {
            id: focusCatcher

            anchors.fill: parent
            z: -1
            focus: root.open
            Keys.onEscapePressed: root.closeRequested()
        }
    }

    component TabButton: Rectangle {
        id: tab

        property string label: ""
        property string iconCode: ""
        property bool active: false
        property bool hovered: false

        implicitWidth: 120
        implicitHeight: 38
        radius: 14
        color: active ? (root.darkMode ? "#344b62cc" : "#d8ecff") : (hovered ? root.cardFill : "transparent")
        border.color: active ? root.accentBlue : (hovered ? root.cardStroke : "transparent")
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: 6

            TahoeSymbol {
                anchors.verticalCenter: parent.verticalCenter
                name: tab.iconCode
                color: tab.active ? root.accentBlue : root.textSecondary
                size: 17
            }

            Text {
                text: tab.label
                color: tab.active ? root.textPrimary : root.textSecondary
                font.pixelSize: 13
                font.weight: tab.active ? Font.DemiBold : Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }

    }

}
