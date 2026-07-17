pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion
import "PopupGeometry.js" as PopupGeometry
import "settings/SettingsTheme.js" as Theme

PanelWindow {
    id: root

    property bool open: false
    property var niriService
    property var controlsService
    property var appearanceService
    property var settingsService
    property var anchorRect: null
    property bool controlsExpanded: false
    // T11: "" | "wifi" | "bluetooth" — module morph expand state.
    property string expandedModule: ""
    readonly property bool moduleExpanded: expandedModule === "wifi" || expandedModule === "bluetooth"
    readonly property bool darkMode: appearanceService && appearanceService.darkMode

    readonly property int edgePadding: 8
    readonly property int fallbackRight: 12
    readonly property int fallbackTop: 28
    readonly property int popupGap: 8
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, fallbackRight)
    readonly property color glassFill: darkMode ? "#d01d1f24" : GlassStyle.FillPanel
    readonly property color glassStroke: darkMode ? "#38ffffff" : GlassStyle.StrokePanel
    readonly property color glassInnerFill: Theme.controlInnerFill(darkMode)
    readonly property string accentId: settingsService ? settingsService.accentColor : "blue"
    readonly property color tileFill: Theme.controlTileFill(darkMode)
    readonly property color tileFillHover: Theme.controlTileFillHover(darkMode)
    readonly property color tileFillActive: Theme.controlTileFillActive(darkMode)
    readonly property color tileFillPressed: Theme.controlTileFillPressed(darkMode)
    readonly property color tileStroke: Theme.controlTileStroke(darkMode)
    readonly property color tileShadowLine: "#1a000000"
    readonly property color accentActive: Theme.accent(darkMode, accentId)
    readonly property color textPrimary: Theme.label(darkMode)
    readonly property color textSecondary: Theme.secondaryLabel(darkMode)
    readonly property color textTertiary: Theme.tertiaryLabel(darkMode)
    readonly property color sliderFill: Theme.sliderFill(darkMode)
    readonly property var wifiNetworks: controlsService ? controlsService.wifiNetworks : []
    readonly property var bluetoothDevices: controlsService ? controlsService.bluetoothDeviceEntries : []
    readonly property int morphDuration: Motion.reducedMotion(settingsService) ? 0 : Motion.ccMorphDurationMs
    readonly property int collapsedTopHeight: 92
    readonly property int expandedTopHeight: 40 + Motion.ccMorphListMaxHeight + 12

    signal closeRequested()

    function openModule(name) {
        var key = String(name || "");
        if (key !== "wifi" && key !== "bluetooth")
            return;
        root.expandedModule = key;
        if (!root.controlsService)
            return;
        if (key === "wifi") {
            try { root.controlsService.rescanWifi(); } catch (e) {}
        } else if (key === "bluetooth") {
            try {
                if (root.controlsService.bluetoothEnabled && !root.controlsService.bluetoothDiscovering)
                    root.controlsService.setBluetoothDiscovering(true);
            } catch (e) {}
        }
    }

    function closeModule() {
        root.expandedModule = "";
    }

    onOpenChanged: {
        if (!open) {
            root.expandedModule = "";
            root.controlsExpanded = false;
        }
    }

    visible: open
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Motion.ccPanelWidth
    implicitHeight: panel.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "tahoe-control-center"

    anchors {
        top: true
        left: true
    }

    margins {
        top: root.popupTopMargin
        left: root.popupLeftMargin
    }

    TahoeGlass.regions: [panel.region]

    GlassPanel {
        id: panel

        x: 0
        // Glass region geometry follows panel height via eased NumberAnimation
        // only (never Spring) — guardrail 0704ea4 / T11.
        y: 0
        width: parent.width
        implicitHeight: content.implicitHeight + 28
        height: implicitHeight
        material: GlassStyle.MaterialPanel
        radius: GlassStyle.RadiusPanel
        fillColor: root.glassFill
        strokeColor: root.glassStroke
        interaction: 0.0
        opacity: 1

        // No Behavior on panel.height: content uses anchors.fill, so a lagged
        // height animation stretches the ColumnLayout (extra space) then snaps
        // back — visible as sliders jumping down on 「编辑控制项」collapse.
        // Morph height is animated only via morphHost / sibling layout props;
        // panel.height tracks content.implicitHeight 1:1 (still no Spring).

        ColumnLayout {
            id: content
            // Top-align to natural height; do not stretch to a lagging panel.
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 12

            // ---- Morph host: collapsed tiles ↔ expanded module list ----
            Item {
                id: morphHost
                Layout.fillWidth: true
                Layout.preferredHeight: root.moduleExpanded ? root.expandedTopHeight : root.collapsedTopHeight
                clip: true

                Behavior on Layout.preferredHeight {
                    // Feeds glass region height — NumberAnimation only, no spring.
                    NumberAnimation {
                        duration: root.morphDuration
                        easing.type: Motion.emphasizedDecel
                    }
                }

                // Collapsed: connectivity + music side by side.
                RowLayout {
                    id: collapsedRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: root.collapsedTopHeight
                    spacing: 10
                    opacity: root.moduleExpanded ? 0 : 1
                    // No Behavior on y / Item.y — Phase 5 glass guardrails ban
                    // those patterns in popup shells. Sibling offset uses
                    // Layout.topMargin on siblingColumn only.
                    enabled: !root.moduleExpanded
                    visible: opacity > 0.01

                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.morphDuration
                            easing.type: Motion.emphasizedDecel
                        }
                    }

                    ConnectivityTile {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: root.collapsedTopHeight
                        controls: root.controlsService
                        onWifiExpandRequested: root.openModule("wifi")
                        onBluetoothExpandRequested: root.openModule("bluetooth")
                    }

                    MusicTile {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: root.collapsedTopHeight
                        controls: root.controlsService
                    }
                }

                // Expanded: full-width module list with back chevron.
                ModuleMorphPanel {
                    id: modulePanel
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: root.expandedTopHeight
                    opacity: root.moduleExpanded ? 1 : 0
                    enabled: root.moduleExpanded
                    visible: opacity > 0.01
                    moduleName: root.expandedModule
                    controls: root.controlsService
                    onBackRequested: root.closeModule()

                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.morphDuration
                            easing.type: Motion.emphasizedDecel
                        }
                    }
                }
            }

            // ---- Sliders + utilities: sibling fade/down when morph open ----
            // Morph only: force height 0 when module expanded (no Behavior on
            // preferredHeight — binding to implicitHeight + Behavior re-ran on
            // every 「编辑控制项」toggle and lagged the utility-row animation).
            ColumnLayout {
                id: siblingColumn
                Layout.fillWidth: true
                spacing: 12
                opacity: root.moduleExpanded ? 0 : 1
                Layout.topMargin: root.moduleExpanded ? Motion.ccMorphSiblingOffsetPx : 0
                // -1 = use implicitHeight (edit-controls grow/shrink freely).
                Layout.preferredHeight: root.moduleExpanded ? 0 : -1
                Layout.maximumHeight: root.moduleExpanded ? 0 : -1
                clip: root.moduleExpanded
                enabled: !root.moduleExpanded
                visible: !root.moduleExpanded || opacity > 0.01

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.morphDuration
                        easing.type: Motion.emphasizedDecel
                    }
                }
                Behavior on Layout.topMargin {
                    NumberAnimation {
                        duration: root.morphDuration
                        easing.type: Motion.emphasizedDecel
                    }
                }

                GlassSlider {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    iconCode: root.controlsService && root.controlsService.brightnessAvailable ? "\ue518" : "\ue1ad"
                    label: "显示"
                    value: root.controlsService ? root.controlsService.brightness : 0
                    enabled: root.controlsService && root.controlsService.brightnessAvailable
                    onUserPreview: function(v) {
                        if (root.controlsService)
                            root.controlsService.previewBrightness(v);
                    }
                    onUserCommit: function(v) {
                        if (root.controlsService)
                            root.controlsService.commitBrightness(v);
                    }
                }

                GlassSlider {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    iconCode: root.controlsService && root.controlsService.muted ? "\ue04f" : "\ue050"
                    label: "声音"
                    value: root.controlsService && !root.controlsService.muted ? root.controlsService.volume : 0
                    enabled: root.controlsService && root.controlsService.audioReady
                    onUserPreview: function(v) {
                        if (root.controlsService)
                            root.controlsService.setVolume(v);
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Layout.preferredHeight: root.controlsExpanded ? 50 : 0
                    opacity: root.controlsExpanded ? 1 : 0
                    visible: Layout.preferredHeight > 0

                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: Motion.elementResize(root.settingsService)
                            easing.type: Motion.emphasizedDecel
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.panelExit(root.settingsService)
                            easing.type: Motion.standardDecel
                        }
                    }

                    UtilityButton {
                        Layout.fillWidth: true
                        iconCode: "\ue51c"
                        label: "深色"
                        enabled: !!root.appearanceService
                        active: root.appearanceService && root.appearanceService.darkMode
                        onClicked: {
                            if (root.appearanceService)
                                root.appearanceService.toggleDarkMode();
                        }
                    }

                    UtilityButton {
                        Layout.fillWidth: true
                        iconCode: "\ue3a9"
                        label: "夜览"
                        enabled: !!root.appearanceService
                        active: root.appearanceService && root.appearanceService.nightMode
                        onClicked: {
                            if (root.appearanceService)
                                root.appearanceService.toggleNightMode();
                        }
                    }

                    UtilityButton {
                        Layout.fillWidth: true
                        iconCode: "\uea5f"
                        label: "计算器"
                        enabled: true
                        onClicked: root.launchFallbackApp("org.gnome.Calculator", "gnome-calculator", "calc")
                    }

                    UtilityButton {
                        Layout.fillWidth: true
                        iconCode: "\ue425"
                        label: "计时器"
                        enabled: true
                        onClicked: root.launchFallbackApp("org.gnome.Clock", "gnome-clocks", "clock")
                    }

                    UtilityButton {
                        Layout.fillWidth: true
                        iconCode: "\ue3b0"
                        label: "相机"
                        enabled: true
                        onClicked: root.launchFallbackApp("cheese", "cheese", "camera")
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: 14
                    color: editMouse.pressed ? "#34ffffff" : (editMouse.containsMouse ? "#40ffffff" : "#59ffffff")
                    border.color: "#30ffffff"
                    border.width: 1
                    scale: Motion.pressScaleFor(root.settingsService, editMouse.pressed)

                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.pressDurationFor(root.settingsService)
                            easing.type: Motion.pressEasing
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.controlsExpanded ? "收起" : "编辑控制项"
                        color: root.textPrimary
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: editMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.controlsExpanded = !root.controlsExpanded
                    }
                }
            }
        }
    }

    function launchFallbackApp(desktopId, command, label) {
        try {
            var entry = DesktopEntries.byId(desktopId);
            if (entry && entry.execute) {
                entry.execute();
                return;
            }
        } catch (e) {}
        try {
            Quickshell.execDetached({ command: [command] });
        } catch (e) {}
    }

    // ==================================================================
    // Inline components
    // ==================================================================

    component ToggleCircle: Item {
        id: tc
        property bool active: false
        property string iconCode: ""
        property color activeColor: root.accentActive
        property bool enabled: true
        property real bounceScale: 1.0
        signal clicked()

        implicitWidth: 48
        implicitHeight: 48
        scale: tc.bounceScale * Motion.pressScaleFor(root.settingsService, toggleMouse.pressed && tc.enabled)

        Behavior on scale {
            NumberAnimation {
                duration: Motion.pressDurationFor(root.settingsService)
                easing.type: Motion.pressEasing
            }
        }

        onActiveChanged: {
            if (Motion.reducedMotion(root.settingsService)) {
                tc.bounceScale = 1.0;
                return;
            }
            toggleBounce.restart();
        }

        SequentialAnimation {
            id: toggleBounce
            NumberAnimation {
                target: tc
                property: "bounceScale"
                to: 0.9
                duration: Math.round(Motion.ccToggleBounceMs * 0.4)
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: tc
                property: "bounceScale"
                to: 1.0
                duration: Math.round(Motion.ccToggleBounceMs * 0.6)
                easing.type: Easing.OutBack
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: toggleMouse.pressed && tc.enabled
                ? Qt.darker(tc.active ? tc.activeColor : "#59ffffff", 1.18)
                : tc.active ? tc.activeColor : "#59ffffff"
            border.color: "#30ffffff"
            border.width: 1
            opacity: tc.enabled ? 1 : 0.4

            Behavior on color {
                ColorAnimation {
                    duration: Motion.reducedMotion(root.settingsService) ? 0 : Motion.ccToggleColorMs
                    easing.type: Easing.InOutQuad
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: (parent.width - 2) / 2
            color: "transparent"
            border.color: "#33ffffff"
            border.width: 1
            opacity: tc.enabled ? 1 : 0.3
        }

        TahoeSymbol {
            anchors.centerIn: parent
            name: tc.iconCode
            color: tc.active ? "#ffffff" : root.textPrimary
            size: 20
            opacity: tc.enabled ? 1 : 0.4
        }

        MouseArea {
            id: toggleMouse
            anchors.fill: parent
            cursorShape: tc.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (tc.enabled)
                    tc.clicked();
            }
        }
    }

    // Connectivity tile: click Wi-Fi body → morph expand; BT circle → BT morph.
    // Airplane stays an instant toggle.
    component ConnectivityTile: Item {
        id: ct
        property var controls
        signal wifiExpandRequested()
        signal bluetoothExpandRequested()
        readonly property bool tilePressed: wifiTileMouse.pressed
        readonly property bool tileHovered: wifiTileMouse.containsMouse
        scale: Motion.reducedMotion(root.settingsService)
            ? 1.0
            : (ct.tilePressed ? Motion.ccTilePressScale : 1.0)

        Behavior on scale {
            NumberAnimation {
                duration: Motion.pressDurationFor(root.settingsService)
                easing.type: Motion.pressEasing
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 22
            color: ct.tilePressed
                ? root.tileFillPressed
                : (ct.tileHovered ? root.tileFillHover : root.tileFill)
            border.color: root.tileStroke
            border.width: 1

            Behavior on color {
                ColorAnimation {
                    duration: Motion.pressDurationFor(root.settingsService)
                    easing.type: Motion.pressEasing
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 21
                color: "transparent"
                border.color: "#26ffffff"
                border.width: 1
            }

            MouseArea {
                id: wifiTileMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                z: 0
                onClicked: ct.wifiExpandRequested()
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 7
                z: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 14
                        color: ct.controls && ct.controls.wifiEnabled ? "#ffffff" : "#10ffffff"
                        border.color: "#20ffffff"
                        border.width: 1

                        TahoeSymbol {
                            anchors.centerIn: parent
                            name: "\ue63e"
                            color: ct.controls && ct.controls.wifiConnected ? root.accentActive : root.textPrimary
                            size: 16
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: "Wi-Fi"
                            color: root.textPrimary
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Text {
                            Layout.fillWidth: true
                            text: {
                                if (!ct.controls || !ct.controls.wifiEnabled)
                                    return "已关闭";
                                if (ct.controls.wifiConnected)
                                    return ct.controls.wifiName;
                                return "已开启";
                            }
                            color: root.textTertiary
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    ToggleCircle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        active: ct.controls && ct.controls.bluetoothEnabled
                        iconCode: "\ue1a7"
                        enabled: ct.controls && ct.controls.bluetoothAvailable
                        onClicked: ct.bluetoothExpandRequested()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ToggleCircle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        active: ct.controls && ct.controls.airplaneMode
                        iconCode: "\ue195"
                        enabled: !!ct.controls
                        onClicked: {
                            if (ct.controls)
                                ct.controls.toggleAirplaneMode();
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: ct.controls && ct.controls.airplaneMode
                              ? "飞行模式"
                              : ct.controls && ct.controls.bluetoothEnabled
                              ? (ct.controls.bluetoothConnectedCount + " 台设备")
                              : ct.controls && ct.controls.bluetoothAvailable
                              ? "蓝牙"
                              : "无蓝牙"
                        color: root.textTertiary
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // Full-width morph panel for wifi / bluetooth lists (Controls data only).
    component ModuleMorphPanel: Item {
        id: mp
        property string moduleName: ""
        property var controls
        signal backRequested()

        readonly property bool isWifi: moduleName === "wifi"
        readonly property bool isBluetooth: moduleName === "bluetooth"
        readonly property var listModel: {
            if (mp.isWifi)
                return root.wifiNetworks;
            if (mp.isBluetooth)
                return root.bluetoothDevices;
            return [];
        }
        property string expandedSsid: ""

        onModuleNameChanged: expandedSsid = ""

        Rectangle {
            anchors.fill: parent
            radius: 22
            color: root.tileFill
            border.color: root.tileStroke
            border.width: 1

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 21
                color: "transparent"
                border.color: "#26ffffff"
                border.width: 1
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                // Header: back + title + power switch.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 14
                        color: backMouse.pressed ? "#40ffffff" : (backMouse.containsMouse ? "#34ffffff" : "#20ffffff")
                        border.color: "#30ffffff"
                        border.width: 1
                        scale: Motion.pressScaleFor(root.settingsService, backMouse.pressed)

                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.pressDurationFor(root.settingsService)
                                easing.type: Motion.pressEasing
                            }
                        }

                        TahoeSymbol {
                            anchors.centerIn: parent
                            name: "\ue5c4" // chevron_left
                            color: root.textPrimary
                            size: 18
                        }

                        MouseArea {
                            id: backMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mp.backRequested()
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: mp.isWifi ? "Wi-Fi" : (mp.isBluetooth ? "蓝牙" : "")
                        color: root.textPrimary
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        verticalAlignment: Text.AlignVCenter
                    }

                    // Power toggle in expanded header (replaces tile-body toggle).
                    Rectangle {
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 24
                        radius: 12
                        color: powerOn ? root.accentActive : "#32000000"
                        border.color: "#38ffffff"
                        border.width: 1
                        visible: mp.isWifi || (mp.isBluetooth && mp.controls && mp.controls.bluetoothAvailable)
                        readonly property bool powerOn: {
                            if (!mp.controls)
                                return false;
                            if (mp.isWifi)
                                return !!mp.controls.wifiEnabled;
                            return !!mp.controls.bluetoothEnabled;
                        }

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            x: parent.powerOn ? parent.width - width - 2 : 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#ffffff"

                            Behavior on x {
                                NumberAnimation {
                                    duration: Motion.elementMove(root.settingsService)
                                    easing.type: Motion.emphasizedDecel
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!mp.controls)
                                    return;
                                if (mp.isWifi)
                                    mp.controls.toggleWifi();
                                else if (mp.isBluetooth)
                                    mp.controls.toggleBluetooth();
                            }
                        }
                    }
                }

                // Empty / unavailable placeholders.
                Text {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    visible: {
                        if (mp.isWifi) {
                            if (!mp.controls)
                                return true;
                            if (!mp.controls.wifiEnabled)
                                return true;
                            return root.wifiNetworks.length === 0;
                        }
                        if (mp.isBluetooth) {
                            if (!mp.controls || !mp.controls.bluetoothAvailable)
                                return true;
                            if (!mp.controls.bluetoothEnabled)
                                return true;
                            return root.bluetoothDevices.length === 0;
                        }
                        return true;
                    }
                    text: {
                        if (mp.isWifi) {
                            if (!mp.controls)
                                return "Wi-Fi 服务不可用";
                            if (!mp.controls.wifiEnabled)
                                return "Wi-Fi 已关闭";
                            return "未发现网络";
                        }
                        if (mp.isBluetooth) {
                            if (!mp.controls || !mp.controls.bluetoothAvailable)
                                return "蓝牙不可用";
                            if (!mp.controls.bluetoothEnabled)
                                return "蓝牙已关闭";
                            return "附近暂无设备";
                        }
                        return "";
                    }
                    color: root.textTertiary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                ListView {
                    id: moduleList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    model: mp.listModel
                    visible: {
                        if (mp.isWifi)
                            return !!mp.controls && mp.controls.wifiEnabled && root.wifiNetworks.length > 0;
                        if (mp.isBluetooth)
                            return !!mp.controls && mp.controls.bluetoothEnabled
                                && mp.controls.bluetoothAvailable && root.bluetoothDevices.length > 0;
                        return false;
                    }

                    delegate: Item {
                        id: row
                        required property var modelData
                        width: moduleList.width
                        height: rowFrame.implicitHeight

                        readonly property bool isWifiRow: mp.isWifi
                        readonly property bool connected: {
                            if (!row.modelData)
                                return false;
                            if (row.isWifiRow)
                                return !!row.modelData.connected;
                            return !!row.modelData.connected;
                        }
                        readonly property string primaryLabel: {
                            if (!row.modelData)
                                return "";
                            if (row.isWifiRow)
                                return String(row.modelData.name || "");
                            return String(row.modelData.name || "未命名设备");
                        }
                        readonly property string secondaryLabel: {
                            if (!row.modelData)
                                return "";
                            if (row.isWifiRow) {
                                var parts = [];
                                if (row.modelData.known)
                                    parts.push("已保存");
                                parts.push(String(row.modelData.signalPercent || 0) + "%");
                                return parts.join(" · ");
                            }
                            var bits = [];
                            if (row.modelData.connected)
                                bits.push("已连接");
                            else if (row.modelData.paired)
                                bits.push("已配对");
                            else
                                bits.push("附近");
                            if (row.modelData.batteryAvailable)
                                bits.push(String(row.modelData.batteryPercent) + "%");
                            return bits.join(" · ");
                        }
                        readonly property bool showPsk: row.isWifiRow
                            && mp.expandedSsid === primaryLabel
                            && row.modelData
                            && row.modelData.secured
                            && !row.modelData.known
                            && !row.modelData.connected

                        Rectangle {
                            id: rowFrame
                            width: parent.width
                            implicitHeight: rowContent.implicitHeight + 12
                            height: implicitHeight
                            radius: 12
                            color: row.connected
                                ? (root.darkMode ? "#403a7ab5" : "#5ad7f0ff")
                                : (rowMouse.containsMouse ? "#40ffffff" : "#28ffffff")
                            border.color: row.connected ? root.accentActive : "#34ffffff"
                            border.width: 1

                            ColumnLayout {
                                id: rowContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 6
                                spacing: 6

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 8

                                        TahoeSymbol {
                                            Layout.preferredWidth: 20
                                            name: {
                                                if (row.isWifiRow)
                                                    return row.connected ? "\ue5ca" : (row.modelData && row.modelData.secured ? "\ue897" : "\ue63e");
                                                return row.connected ? "\ue5ca" : "\ue1a7";
                                            }
                                            color: row.connected ? root.accentActive : root.textTertiary
                                            size: 16
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0

                                            Text {
                                                Layout.fillWidth: true
                                                text: row.primaryLabel
                                                color: root.textPrimary
                                                font.pixelSize: 13
                                                font.weight: row.connected ? Font.DemiBold : Font.Normal
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: row.secondaryLabel
                                                color: root.textTertiary
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                                visible: text.length > 0
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: rowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!row.modelData || !mp.controls)
                                                return;
                                            if (row.isWifiRow) {
                                                if (row.modelData.connected) {
                                                    mp.controls.disconnectWifi();
                                                    return;
                                                }
                                                if (row.modelData.secured && !row.modelData.known) {
                                                    mp.expandedSsid = mp.expandedSsid === row.primaryLabel ? "" : row.primaryLabel;
                                                    return;
                                                }
                                                mp.controls.connectWifi(row.modelData, "");
                                                mp.expandedSsid = "";
                                                return;
                                            }
                                            // Bluetooth
                                            if (row.modelData.connected)
                                                mp.controls.disconnectBluetoothDevice(row.modelData);
                                            else if (row.modelData.paired || row.modelData.bonded)
                                                mp.controls.connectBluetoothDevice(row.modelData);
                                            else
                                                mp.controls.pairBluetoothDevice(row.modelData);
                                        }
                                    }
                                }

                                // Password field for secured unknown Wi-Fi.
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: row.showPsk ? 36 : 0
                                    radius: 10
                                    color: "#24ffffff"
                                    border.color: "#3cffffff"
                                    border.width: 1
                                    visible: row.showPsk
                                    clip: true

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        spacing: 6

                                        TextInput {
                                            id: pskInput
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            color: root.textPrimary
                                            selectionColor: root.accentActive
                                            selectedTextColor: "#ffffff"
                                            font.pixelSize: 13
                                            echoMode: TextInput.Password
                                            clip: true
                                            selectByMouse: true
                                            verticalAlignment: TextInput.AlignVCenter
                                            Keys.onReturnPressed: {
                                                if (mp.controls)
                                                    mp.controls.connectWifi(row.modelData, pskInput.text);
                                                pskInput.text = "";
                                                mp.expandedSsid = "";
                                            }
                                            Keys.onEscapePressed: mp.expandedSsid = ""
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: connectLabel.implicitWidth + 14
                                            Layout.preferredHeight: 26
                                            radius: 12
                                            color: "#50ffffff"
                                            border.color: "#40ffffff"
                                            border.width: 1

                                            Text {
                                                id: connectLabel
                                                anchors.centerIn: parent
                                                text: "连接"
                                                color: root.textPrimary
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (mp.controls)
                                                        mp.controls.connectWifi(row.modelData, pskInput.text);
                                                    pskInput.text = "";
                                                    mp.expandedSsid = "";
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Footer actions for wifi rescan / bt scan.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    spacing: 8
                    visible: (mp.isWifi && mp.controls && mp.controls.wifiEnabled)
                        || (mp.isBluetooth && mp.controls && mp.controls.bluetoothEnabled && mp.controls.bluetoothAvailable)

                    Text {
                        text: {
                            if (mp.isWifi)
                                return "重新扫描";
                            if (mp.controls && mp.controls.bluetoothDiscovering)
                                return "停止扫描";
                            return "扫描设备";
                        }
                        color: root.accentActive
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        scale: Motion.pressScaleFor(root.settingsService, footerMouse.pressed)

                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.pressDurationFor(root.settingsService)
                                easing.type: Motion.pressEasing
                            }
                        }

                        MouseArea {
                            id: footerMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!mp.controls)
                                    return;
                                if (mp.isWifi)
                                    mp.controls.rescanWifi();
                                else
                                    mp.controls.toggleBluetoothDiscovering();
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }

    component MusicTile: Item {
        id: mt
        property var controls
        readonly property bool tileHovered: musicHover.hovered

        HoverHandler {
            id: musicHover
        }

        Rectangle {
            anchors.fill: parent
            radius: 22
            color: mt.tileHovered ? root.tileFillHover : root.tileFill
            border.color: root.tileStroke
            border.width: 1

            Behavior on color {
                ColorAnimation {
                    duration: Motion.pressDurationFor(root.settingsService)
                    easing.type: Motion.pressEasing
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 21
                color: "transparent"
                border.color: "#26ffffff"
                border.width: 1
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 38
                        radius: 9
                        color: "#30ffffff"
                        border.color: "#20ffffff"
                        border.width: 1
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: mt.controls && mt.controls.hasMedia ? mt.controls.trackArtUrl : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: mt.controls && mt.controls.hasMedia && mt.controls.trackArtUrl.length > 0
                            asynchronous: true
                            sourceSize.width: 76
                            sourceSize.height: 76
                        }

                        TahoeSymbol {
                            anchors.centerIn: parent
                            name: "\ue405"
                            color: root.textSecondary
                            size: 18
                            visible: !(mt.controls && mt.controls.hasMedia && mt.controls.trackArtUrl.length > 0)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: mt.controls && mt.controls.hasMedia ? mt.controls.trackTitle : "未播放"
                            color: root.textPrimary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Text {
                            Layout.fillWidth: true
                            text: mt.controls && mt.controls.hasMedia ? mt.controls.trackArtist : "媒体"
                            color: root.textTertiary
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14

                    Item { Layout.fillWidth: true }

                    Item {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        scale: Motion.pressScaleFor(root.settingsService, previousMouse.pressed && mt.controls && mt.controls.canPrev)

                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.pressDurationFor(root.settingsService)
                                easing.type: Motion.pressEasing
                            }
                        }

                        TahoeSymbol {
                            anchors.centerIn: parent
                            name: "\ue045"
                            color: (mt.controls && mt.controls.canPrev) ? root.textPrimary : root.textTertiary
                            size: 20
                            opacity: (mt.controls && mt.controls.canPrev) ? 1 : 0.4
                        }

                        MouseArea {
                            id: previousMouse
                            anchors.fill: parent
                            cursorShape: (mt.controls && mt.controls.canPrev) ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (mt.controls && mt.controls.canPrev)
                                    mt.controls.previous();
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: 17
                        color: playMouse.pressed ? "#4affffff" : "#66ffffff"
                        border.color: "#30ffffff"
                        border.width: 1
                        scale: Motion.pressScaleFor(root.settingsService, playMouse.pressed && mt.controls && mt.controls.canPlayPause)

                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.pressDurationFor(root.settingsService)
                                easing.type: Motion.pressEasing
                            }
                        }

                        TahoeSymbol {
                            anchors.centerIn: parent
                            name: (mt.controls && mt.controls.isPlaying) ? "\ue034" : "\ue037"
                            color: root.textPrimary
                            size: 20
                        }

                        MouseArea {
                            id: playMouse
                            anchors.fill: parent
                            cursorShape: (mt.controls && mt.controls.canPlayPause) ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (mt.controls && mt.controls.canPlayPause)
                                    mt.controls.togglePlayPause();
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        scale: Motion.pressScaleFor(root.settingsService, nextMouse.pressed && mt.controls && mt.controls.canNext)

                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.pressDurationFor(root.settingsService)
                                easing.type: Motion.pressEasing
                            }
                        }

                        TahoeSymbol {
                            anchors.centerIn: parent
                            name: "\ue044"
                            color: (mt.controls && mt.controls.canNext) ? root.textPrimary : root.textTertiary
                            size: 20
                            opacity: (mt.controls && mt.controls.canNext) ? 1 : 0.4
                        }

                        MouseArea {
                            id: nextMouse
                            anchors.fill: parent
                            cursorShape: (mt.controls && mt.controls.canNext) ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (mt.controls && mt.controls.canNext)
                                    mt.controls.next();
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }

    component GlassSlider: Item {
        id: gs
        property string iconCode: ""
        property string label: ""
        property real value: 0
        property bool enabled: true
        property bool userDragging: false
        property real userValue: 0
        signal userPreview(real value)
        signal userCommit(real value)

        readonly property real sourceValue: Math.max(0, Math.min(1, Number(gs.value) || 0))
        readonly property real clampedValue: gs.userDragging ? gs.userValue : gs.sourceValue
        readonly property real knobSize: 22
        readonly property real trackHeight: 26

        Rectangle {
            anchors.fill: parent
            radius: 26
            color: root.tileFill
            border.color: root.tileStroke
            border.width: 1
            opacity: gs.enabled ? 1 : 0.6

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 25
                color: "transparent"
                border.color: "#26ffffff"
                border.width: 1
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 3

                Text {
                    text: gs.label
                    color: root.darkMode ? "#c8d0d8" : "#b3000000"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                Item {
                    id: trackHost
                    Layout.fillWidth: true
                    Layout.preferredHeight: gs.trackHeight

                    Rectangle {
                        id: pillTrack
                        anchors.fill: parent
                        radius: height / 2
                        color: "#47ffffff"
                        clip: true

                        Rectangle {
                            x: 0
                            y: 0
                            height: parent.height
                            width: parent.width * gs.clampedValue
                            radius: parent.radius
                            color: root.sliderFill
                        }

                        TahoeSymbol {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            name: gs.iconCode
                            color: root.darkMode ? "#b9c0cc" : "#731d1d1f"
                            size: 15
                        }
                    }

                    Rectangle {
                        id: knobShadow
                        width: gs.knobSize
                        height: gs.knobSize
                        radius: width / 2
                        color: "#40000000"
                        x: Math.max(0, Math.min(pillTrack.width - width, pillTrack.width * gs.clampedValue - width / 2))
                        anchors.verticalCenter: pillTrack.verticalCenter
                        anchors.verticalCenterOffset: 1
                        scale: knob.scale
                        z: 6
                    }

                    Rectangle {
                        id: knob
                        width: gs.knobSize
                        height: gs.knobSize
                        radius: width / 2
                        color: "#ffffff"
                        border.color: "#22000000"
                        border.width: 1
                        x: knobShadow.x
                        anchors.verticalCenter: pillTrack.verticalCenter
                        scale: dragArea.pressed && gs.enabled
                            ? (Motion.reducedMotion(root.settingsService) ? 1.0 : Motion.ccSliderKnobDragScale)
                            : 1.0
                        z: 7

                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.pressDurationFor(root.settingsService)
                                easing.type: Motion.pressEasing
                            }
                        }
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        enabled: gs.enabled
                        cursorShape: gs.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        preventStealing: true

                        function applyValue(mouseX) {
                            var w = pillTrack.width;
                            if (w <= 0)
                                return;
                            var v = Math.max(0, Math.min(1, mouseX / w));
                            // Paint from pointer position before any backend
                            // round-trip. The service decides the write budget.
                            gs.userValue = v;
                            gs.userPreview(v);
                            return v;
                        }

                        onPressed: function(mouse) {
                            gs.userDragging = true;
                            dragArea.applyValue(mouse.x);
                        }
                        onPositionChanged: function(mouse) {
                            if (pressed)
                                dragArea.applyValue(mouse.x);
                        }
                        onReleased: function(mouse) {
                            var value = dragArea.applyValue(mouse.x);
                            gs.userCommit(value);
                            gs.userDragging = false;
                        }
                        onCanceled: {
                            if (gs.userDragging)
                                gs.userCommit(gs.userValue);
                            gs.userDragging = false;
                        }
                    }
                }
            }
        }
    }

    component UtilityButton: Item {
        id: ub
        property string iconCode: ""
        property string label: ""
        property bool enabled: true
        property bool active: false
        signal clicked()

        implicitWidth: 48
        implicitHeight: 48
        scale: Motion.pressScaleFor(root.settingsService, ubMouse.pressed && ub.enabled)

        Behavior on scale {
            NumberAnimation {
                duration: Motion.pressDurationFor(root.settingsService)
                easing.type: Motion.pressEasing
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: ubMouse.pressed && ub.enabled
                ? Qt.darker(ub.active ? root.accentActive : "#59ffffff", 1.18)
                : ub.active ? root.accentActive : (ubMouse.containsMouse ? "#66ffffff" : "#59ffffff")
            border.color: "#30ffffff"
            border.width: 1
            opacity: ub.enabled ? 1 : 0.4
        }

        TahoeSymbol {
            anchors.centerIn: parent
            name: ub.iconCode
            color: ub.active ? "#ffffff" : root.textPrimary
            size: 20
            opacity: ub.enabled ? 1 : 0.4
        }

        MouseArea {
            id: ubMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: ub.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (ub.enabled)
                    ub.clicked();
            }
        }
    }
}
