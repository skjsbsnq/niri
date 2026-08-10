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
    // A1: currentTab 由 shell 级注入并在变更时回灌（面板关闭即销毁，
    // tab 状态跨开关保留）。保留本地默认以便独立预览/测试。
    property string currentTab: "system"
    property var systemStatsService
    property var weatherService
    property var settingsService
    property var batteryService
    property bool darkMode: false
    property string monoFontFamily: "Noto Sans Mono CJK SC"
    property bool useSpring: false
    property bool backgroundEffectsAllowed: true

    readonly property int screenWidth: Math.max(1, Number(root.screen && root.screen.width) || root.width)
    readonly property int screenHeight: Math.max(1, Number(root.screen && root.screen.height) || root.height)
    // A1: 面板宽度由 shell 级注入（唯一外部引用 shell.qml 的 cutout 已改读
    // shell.panelWidth）。保留本地回退公式以便独立预览/测试使用。
    property real panelWidth: Math.max(340, Math.min(420, screenWidth - 24))
    readonly property color glassFill: darkMode ? "#e01c1c1e" : "#e8f5f5f7"
    readonly property color glassStroke: darkMode ? "#28ffffff" : "#2a000000"
    readonly property string accentId: settingsService ? settingsService.accentColor : "blue"
    readonly property color cardFill: Theme.cardFill(darkMode)
    readonly property color cardStroke: "transparent"
    readonly property color textPrimary: Theme.label(darkMode)
    readonly property color textSecondary: Theme.secondaryLabel(darkMode)
    readonly property color textTertiary: Theme.tertiaryLabel(darkMode)
    readonly property color accentBlue: Theme.accent(darkMode, accentId)
    // Card enter stagger gate: set true after panel is open so children animate in.
    property bool cardsEnter: false

    signal closeRequested()
    signal openWeatherSettingsRequested()
    // A1: 用户切换 tab 时回灌 shell（面板可能因 LazyLoader 销毁，状态须
    // 提升到 shell 级跨开关保留）。
    signal currentTabChangeRequested(string tab)
    // LS07：透传系统页右键请求给 shell（shell 实例化 ProcessMenu + PopupDismissLayer）。
    // processMenuOpen 由 shell 驱动，回灌到系统页暂停进程刷新。
    signal openProcessMenuRequested(var proc, var anchorRect)
    property bool processMenuOpen: false

    visible: open
    // P02: freeze scene-graph frames while this surface is unmapped/faded out.
    // Extends the existing visible gate onto updatesEnabled (not a parallel path).
    updatesEnabled: visible
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
            x: Math.round(panel.x)
            y: Math.round(panel.y)
            width: panel.width
            height: panel.height
            radius: panel.radius
        }
    }

    TahoeGlass.regions: [panel.region]

    // A1: 进入动作（卡片入场调度）。打开面板时执行；LazyLoader 化后重开是
    // 重建对象树、open=true 为初始值（onOpenChanged 不触发），故 onCompleted
    // 也驱动一次。关闭动作（停 timer、清 cardsEnter）仅关闭路径需要，
    // 重建时对象树销毁已隐含清理。
    function enter() {
        cardsEnter = false;
        Qt.callLater(function() {
            if (root.open) {
                focusCatcher.forceActiveFocus();
                // Let the panel settle, then stagger cards.
                cardsEnterTimer.restart();
            }
        });
    }

    onOpenChanged: {
        if (open) {
            enter();
        } else {
            cardsEnterTimer.stop();
            cardsEnter = false;
        }
    }

    Component.onCompleted: {
        if (root.open)
            enter();
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
        // Stay enabled while unmapped so niri's closing snapshot keeps the glass material.
        regionX: Math.round(panel.x)
        regionY: Math.round(panel.y)
        regionWidth: panel.width
        regionHeight: panel.height
        interaction: 0.0
        opacity: 1

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
                        var tab = mouse.x < width / 2 ? "system" : "weather";
                        if (tab !== root.currentTab) {
                            root.currentTab = tab;
                            root.currentTabChangeRequested(tab);
                        }
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
                    opacity: root.currentTab === "system" ? 1 : 0
                    visible: root.currentTab === "system" || opacity > 0.01
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

                    Behavior on opacity {
                        NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                    }
                }

                LeftSidebarWeather {
                    anchors.fill: parent
                    opacity: root.currentTab === "weather" ? 1 : 0
                    visible: root.currentTab === "weather" || opacity > 0.01
                    weatherService: root.weatherService
                    settingsService: root.settingsService
                    sidebarOpen: root.open
                    active: root.currentTab === "weather"
                    darkMode: root.darkMode
                    monoFontFamily: root.monoFontFamily
                    cardsEnter: root.cardsEnter && root.currentTab === "weather"
                    useSpring: root.useSpring
                    backgroundEffectsAllowed: root.backgroundEffectsAllowed
                    onOpenWeatherSettingsRequested: root.openWeatherSettingsRequested()

                    Behavior on opacity {
                        NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                    }
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

            Behavior on color {
                ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
            }
        }
    }
}
