pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion
import "settings/SettingsTheme.js" as Theme

// T19: chrome-free left sidebar. Small top segmented control (or single
// scroll column); System/Weather pages own content. ProcessMenu path
// (openProcessMenuRequested) unchanged — shell.qml:869-905 owns the menu.
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
    property bool useSpring: false

    readonly property int screenWidth: Math.max(1, Number(root.screen && root.screen.width) || root.width)
    readonly property int screenHeight: Math.max(1, Number(root.screen && root.screen.height) || root.height)
    readonly property int panelWidth: Math.max(340, Math.min(420, screenWidth - 24))
    readonly property color glassFill: darkMode ? "#e01c1c1e" : "#e8f5f5f7"
    readonly property color glassStroke: darkMode ? "#28ffffff" : "#2a000000"
    readonly property string accentId: settingsService ? settingsService.accentColor : "blue"
    readonly property color cardFill: Theme.cardFill(darkMode)
    readonly property color cardStroke: "transparent"
    readonly property color textPrimary: Theme.label(darkMode)
    readonly property color textSecondary: Theme.secondaryLabel(darkMode)
    readonly property color textTertiary: Theme.tertiaryLabel(darkMode)
    readonly property color accentBlue: Theme.accent(darkMode, accentId)
    readonly property bool compositorLayerAnimations: !!(settingsService && settingsService.compositorLayerAnimations)
    readonly property real closedSlideX: -(panelWidth + 24)
    readonly property bool qmlSlideActive: !compositorLayerAnimations && slideTransform.x > closedSlideX + 0.5

    // Card enter stagger gate: set true after panel is open so children animate in.
    property bool cardsEnter: false

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
            cardsEnter = false;
            Qt.callLater(function() {
                if (root.open) {
                    focusCatcher.forceActiveFocus();
                    // Let the panel settle, then stagger cards.
                    cardsEnterTimer.restart();
                }
            });
        } else {
            cardsEnterTimer.stop();
            cardsEnter = false;
        }
    }

    Timer {
        id: cardsEnterTimer
        interval: 40
        repeat: false
        onTriggered: {
            if (root.open)
                root.cardsEnter = true;
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
            anchors.margins: 14
            spacing: 10

            // Compact top segmented control (replaces title + close + large tabs).
            Item {
                id: segmentBar
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                z: 2

                Rectangle {
                    anchors.fill: parent
                    radius: 17
                    color: root.darkMode ? "#1affffff" : "#14000000"
                }

                Rectangle {
                    id: segmentThumb
                    width: (parent.width - 4) / 2
                    height: parent.height - 4
                    radius: 15
                    // Driven by moveSegmentThumb — avoids dual interceptors.
                    x: 2
                    y: 2
                    color: root.darkMode ? "#3a3a3c" : "#ffffff"
                    // Soft plate under the selected segment.
                    border.color: root.darkMode ? "#22ffffff" : "#12000000"
                    border.width: 1

                    Behavior on x {
                        enabled: !root.useSpring || Motion.reducedMotion(root.settingsService)
                        NumberAnimation {
                            duration: Motion.elementMove(root.settingsService)
                            easing.type: Motion.emphasizedDecel
                        }
                    }
                    SpringAnimation {
                        id: segmentSpring
                        target: segmentThumb
                        property: "x"
                        spring: Motion.springSnappy.spring
                        damping: Motion.springSnappy.damping
                        epsilon: 0.001
                    }

                    function targetXFor(tab) {
                        return 2 + (tab === "weather" ? width : 0);
                    }

                    function moveTo(tab, animate) {
                        var tx = targetXFor(tab);
                        segmentSpring.stop();
                        if (animate && root.useSpring && !Motion.reducedMotion(root.settingsService)) {
                            segmentSpring.to = tx;
                            segmentSpring.restart();
                        } else {
                            x = tx;
                        }
                    }

                    Component.onCompleted: moveTo(root.currentTab, false)
                }

                Connections {
                    target: root
                    function onCurrentTabChanged() {
                        segmentThumb.moveTo(root.currentTab, true);
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 0

                    SegmentLabel {
                        width: parent.width / 2
                        height: parent.height
                        label: "系统"
                        active: root.currentTab === "system"
                    }

                    SegmentLabel {
                        width: parent.width / 2
                        height: parent.height
                        label: "天气"
                        active: root.currentTab === "weather"
                    }
                }

                MouseArea {
                    anchors.fill: parent
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
                    cardsEnter: root.cardsEnter && root.currentTab === "system"
                    useSpring: root.useSpring
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
                    cardsEnter: root.cardsEnter && root.currentTab === "weather"
                    useSpring: root.useSpring
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

    component SegmentLabel: Item {
        id: seg
        property string label: ""
        property bool active: false

        Text {
            anchors.centerIn: parent
            text: seg.label
            color: seg.active ? root.textPrimary : root.textSecondary
            font.pixelSize: 13
            font.weight: seg.active ? Font.DemiBold : Font.Medium
        }
    }
}
