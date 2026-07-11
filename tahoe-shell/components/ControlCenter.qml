pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion
import "PopupGeometry.js" as PopupGeometry

PanelWindow {
    id: root

    property bool open: false
    property var niriService
    property var controlsService
    property var appearanceService
    property var settingsService
    property var anchorRect: null
    property bool controlsExpanded: false
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
    readonly property color glassInnerFill: darkMode ? "#1cffffff" : "#14ffffff"
    // Tiles match the web cc-tile rgba(255,255,255,0.5).
    readonly property color tileFill: darkMode ? "#2c343dcc" : "#80ffffff"
    readonly property color tileFillHover: darkMode ? "#36424dcc" : "#8fffffff"
    readonly property color tileFillActive: darkMode ? "#37424dcc" : "#88ffffff"
    readonly property color tileFillPressed: darkMode ? "#242c34cc" : "#70ffffff"
    readonly property color tileStroke: darkMode ? "#34ffffff" : "#5affffff" // inner top-left light
    readonly property color tileShadowLine: "#1a000000" // inner bottom-right shadow
    // macOS accent blue used when a toggle is on.
    readonly property color accentActive: "#2c9cf2"
    readonly property color textPrimary: darkMode ? "#f5f7fb" : "#1d1d1f"
    readonly property color textSecondary: darkMode ? "#c8d0d8" : "#991d1d1f"
    readonly property color textTertiary: darkMode ? "#9da7b1" : "#731d1d1f"
    readonly property color sliderFill: darkMode ? "#d8e4f0" : "#f2ffffff" // ~0.95 white
    // Material Icons font name registered once in shell.qml via FontLoader.
    readonly property string iconFont: "Material Icons"

    signal closeRequested()

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
        // panel is the compositor-owned glass region item. Its region geometry
        // stays fixed during open/close; niri owns the outer layer motion.
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

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            // ---- Top row: left stack (wifi/bluetooth/airdrop) + music ----
            // T10: no title/close chrome (macOS Control Center style).
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Left stack column.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 10

                    // Connectivity tile (Wi-Fi heading + BT/AirDrop circles).
                    ConnectivityTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 92
                        controls: root.controlsService
                    }
                }

                // Now Playing tile.
                MusicTile {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 92
                    controls: root.controlsService
                }
            }

            // ---- Sliders (full width, stacked) ----
            GlassSlider {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                iconCode: root.controlsService && root.controlsService.brightnessAvailable ? "\ue518" : "\ue1ad" // light_mode / brightness_low
                label: "显示"
                value: root.controlsService ? root.controlsService.brightness : 0
                enabled: root.controlsService && root.controlsService.brightnessAvailable
                onUserSet: function(v) {
                    if (root.controlsService)
                        root.controlsService.setBrightness(v);
                }
            }

            GlassSlider {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                iconCode: root.controlsService && root.controlsService.muted ? "\ue04f" : "\ue050" // volume_off / volume_up
                label: "声音"
                value: root.controlsService && !root.controlsService.muted ? root.controlsService.volume : 0
                enabled: root.controlsService && root.controlsService.audioReady
                onUserSet: function(v) {
                    if (root.controlsService)
                        root.controlsService.setVolume(v);
                }
            }

            // ---- Collapsible utility row ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Layout.preferredHeight: root.controlsExpanded ? 50 : 0
                opacity: root.controlsExpanded ? 1 : 0
                visible: Layout.preferredHeight > 0

                Behavior on Layout.preferredHeight {
                    // NumberAnimation, not spring — this height feeds the
                    // panel's implicitHeight, which is the glass-region
                    // geometry; a spring overshoot here is the same crash
                    // class as animating panel.y/scale directly.
                    NumberAnimation { duration: Motion.elementResize(root.settingsService); easing.type: Motion.emphasizedDecel }
                }

                Behavior on opacity {
                    NumberAnimation { duration: Motion.panelExit(root.settingsService); easing.type: Motion.standardDecel }
                }

                    UtilityButton {
                        Layout.fillWidth: true
                        iconCode: "\ue51c" // dark_mode
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
                        iconCode: "\ue3a9" // nightlight
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
                        iconCode: "\uea5f" // calculate
                        label: "计算器"
                        enabled: true
                        onClicked: root.launchFallbackApp("org.gnome.Calculator", "gnome-calculator", "calc")
                    }

                    UtilityButton {
                        Layout.fillWidth: true
                        iconCode: "\ue425" // timer
                        label: "计时器"
                        enabled: true
                        onClicked: root.launchFallbackApp("org.gnome.Clock", "gnome-clocks", "clock")
                    }

                    UtilityButton {
                        Layout.fillWidth: true
                        iconCode: "\ue3b0" // camera_alt
                        label: "相机"
                        enabled: true
                        onClicked: root.launchFallbackApp("cheese", "cheese", "camera")
                    }
            }

            // ---- Edit Controls / expand toggle ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                radius: 14
                color: editMouse.pressed ? "#34ffffff" : (editMouse.containsMouse ? "#40ffffff" : "#59ffffff")
                border.color: "#30ffffff"
                border.width: 1
                scale: Motion.pressScaleFor(root.settingsService, editMouse.pressed)

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

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

    // Launch a desktop entry by candidate id, falling back to a raw command.
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
    // Inline components (declared as the last children of the root, per
    // project convention — MenuPopup.qml does the same with MenuRow).
    // ==================================================================

    // A glass toggle circle (50x50), used in ConnectivityTile and elsewhere.
    // `active` flips the fill between accent blue and translucent white.
    // T10: state change plays 1→0.9→1 bounce + ColorAnimation 200ms.
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

        Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

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
            id: toggleFill
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

        // Inner top-left highlight (web double-inset signature).
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: (parent.width - 2) / 2
            color: "transparent"
            border.color: "#33ffffff"
            border.width: 1
            opacity: tc.enabled ? 1 : 0.3
        }

        Text {
            anchors.centerIn: parent
            text: tc.iconCode
            color: tc.active ? "#ffffff" : root.textPrimary
            font.family: root.iconFont
            font.pixelSize: 20
            opacity: tc.enabled ? 1 : 0.4

            Behavior on color {
                ColorAnimation {
                    duration: Motion.reducedMotion(root.settingsService) ? 0 : Motion.ccToggleColorMs
                    easing.type: Easing.InOutQuad
                }
            }
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

    // Connectivity tile: Wi-Fi heading + sub, plus a row of BT/AirDrop circles.
    // Mirrors the web cc-wifi-tile + cc-row composition.
    // T10: hover brighten / press dark + scale 0.97.
    component ConnectivityTile: Item {
        id: ct
        property var controls
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

            // Inner top-left light.
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 21
                color: "transparent"
                border.color: "#26ffffff"
                border.width: 1
            }

            // Whole-tile click toggles Wi-Fi, but it must sit below the
            // row controls so Bluetooth/AirDrop clicks do not fall through
            // to Wi-Fi.
            MouseArea {
                id: wifiTileMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                z: 0
                onClicked: {
                    if (ct.controls)
                        ct.controls.toggleWifi();
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 7
                z: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Icon badge (web cc-icon-circle.blue).
                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 14
                        color: ct.controls && ct.controls.wifiEnabled ? "#ffffff" : "#10ffffff"
                        border.color: "#20ffffff"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "\ue63e" // wifi
                            color: ct.controls && ct.controls.wifiConnected ? root.accentActive : root.textPrimary
                            font.family: root.iconFont
                            font.pixelSize: 16
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

                    // Bluetooth circle (web cc-button-circle).
                    ToggleCircle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        active: ct.controls && ct.controls.bluetoothEnabled
                        iconCode: "\ue1a7" // bluetooth
                        enabled: ct.controls && ct.controls.bluetoothAvailable
                        onClicked: {
                            if (ct.controls)
                                ct.controls.toggleBluetooth();
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // AirDrop/Stage Manager placeholder circle (no backend).
                    ToggleCircle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        active: ct.controls && ct.controls.airplaneMode
                        iconCode: "\ue195" // airplanemode_active (airdrop-like)
                        enabled: !!ct.controls
                        onClicked: {
                            if (ct.controls)
                                ct.controls.toggleAirplaneMode();
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        id: previousButton
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

    // Now Playing tile (web cc-music-widget). Shows album art + transport.
    // T10: hover brighten / press scale on transport only; tile surface hover.
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

                    // Album art / fallback icon.
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

                        Text {
                            anchors.centerIn: parent
                            text: "\ue405" // music_note
                            color: root.textSecondary
                            font.family: root.iconFont
                            font.pixelSize: 18
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

                // Transport row.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "\ue045" // skip_previous
                        color: (mt.controls && mt.controls.canPrev) ? root.textPrimary : root.textTertiary
                        font.family: root.iconFont
                        font.pixelSize: 20
                        opacity: (mt.controls && mt.controls.canPrev) ? 1 : 0.4
                        scale: Motion.pressScaleFor(root.settingsService, previousMouse.pressed && mt.controls && mt.controls.canPrev)

                        Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

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
                        id: playButton
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: 17
                        color: playMouse.pressed ? "#4affffff" : "#66ffffff"
                        border.color: "#30ffffff"
                        border.width: 1
                        scale: Motion.pressScaleFor(root.settingsService, playMouse.pressed && mt.controls && mt.controls.canPlayPause)

                        Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                        Text {
                            anchors.centerIn: parent
                            text: (mt.controls && mt.controls.isPlaying) ? "\ue034" : "\ue037" // pause / play_arrow
                            color: root.textPrimary
                            font.family: root.iconFont
                            font.pixelSize: 20
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

                    Text {
                        id: nextButton
                        text: "\ue044" // skip_next
                        color: (mt.controls && mt.controls.canNext) ? root.textPrimary : root.textTertiary
                        font.family: root.iconFont
                        font.pixelSize: 20
                        opacity: (mt.controls && mt.controls.canNext) ? 1 : 0.4
                        scale: Motion.pressScaleFor(root.settingsService, nextMouse.pressed && mt.controls && mt.controls.canNext)

                        Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

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

    // White-fill slider with circular knob + drag scale (T10).
    // MouseArea driven — project never uses QtQuick.Controls.
    component GlassSlider: Item {
        id: gs
        property string iconCode: ""
        property string label: ""
        property real value: 0 // 0..1
        property bool enabled: true
        signal userSet(real value)

        readonly property real clampedValue: Math.max(0, Math.min(1, gs.value))
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

                // Pill track (clip fill only; knob sits above).
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
                            id: fill
                            x: 0
                            y: 0
                            height: parent.height
                            width: parent.width * gs.clampedValue
                            radius: parent.radius
                            color: root.sliderFill
                        }

                        // Right-side icon (web cc-slider-icon-right).
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: gs.iconCode
                            color: root.darkMode ? "#b9c0cc" : "#731d1d1f"
                            font.family: root.iconFont
                            font.pixelSize: 15
                            z: 5
                        }
                    }

                    // Soft shadow under the white knob.
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

                    // White circular knob (macOS signature).
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
                            var v = mouseX / w;
                            v = Math.max(0, Math.min(1, v));
                            gs.userSet(v);
                        }

                        onPressed: function(mouse) {
                            dragArea.applyValue(mouse.x);
                        }
                        onPositionChanged: function(mouse) {
                            if (pressed)
                                dragArea.applyValue(mouse.x);
                        }
                    }
                }
            }
        }
    }

    // Small bottom-row utility circle (web cc-button-circle-small).
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

        Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

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

        Text {
            anchors.centerIn: parent
            text: ub.iconCode
            color: ub.active ? "#ffffff" : root.textPrimary
            font.family: root.iconFont
            font.pixelSize: 20
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
