pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property bool open: false
    property var niriService
    property var controlsService
    property bool controlsExpanded: false

    // Glass palette (kept in sync with the rest of the shell). Each Tahoe
    // component re-declares its own block rather than sharing a file.
    readonly property color glassFill: "#24ffffff"
    readonly property color glassStroke: "#52ffffff"
    readonly property color glassInnerFill: "#18ffffff"
    // Tiles match the web cc-tile rgba(255,255,255,0.5).
    readonly property color tileFill: "#80ffffff"
    readonly property color tileFillActive: "#88ffffff"
    readonly property color tileStroke: "#5affffff" // inner top-left light
    readonly property color tileShadowLine: "#1a000000" // inner bottom-right shadow
    // macOS accent blue used when a toggle is on.
    readonly property color accentActive: "#2c9cf2"
    readonly property color textPrimary: "#1d1d1f"
    readonly property color textSecondary: "#991d1d1f"
    readonly property color textTertiary: "#731d1d1f"
    readonly property color sliderFill: "#f2ffffff" // ~0.95 white

    // Material Icons font name registered once in shell.qml via FontLoader.
    readonly property string iconFont: "Material Icons"

    signal closeRequested()

    visible: open || panel.opacity > 0.01
    aboveWindows: true
    exclusiveZone: 0
    implicitWidth: 360
    implicitHeight: panel.implicitHeight
    color: "transparent"

    anchors {
        top: true
        right: true
    }

    margins {
        top: 40
        right: 12
    }

    BackgroundEffect.blurRegion: Region {
        item: panel
        radius: 28
    }

    Rectangle {
        id: panel
        x: 0
        y: root.open ? 0 : -14
        width: parent.width
        implicitHeight: content.implicitHeight + 28
        radius: 28
        color: root.glassFill
        border.color: root.glassStroke
        border.width: 1
        opacity: root.open ? 1 : 0

        // Top hairline highlight (project convention: anchored 1px accents).
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.topMargin: 1
            height: 1
            radius: 1
            color: "#5affffff"
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            height: 1
            radius: 1
            color: "#1a000000"
        }

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            // ---- Header row: title + close ----
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                spacing: 8

                Text {
                    text: "Control Center"
                    color: root.textPrimary
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 12
                    color: root.glassInnerFill
                    border.color: "#36ffffff"

                    Text {
                        anchors.centerIn: parent
                        text: "x"
                        color: root.textPrimary
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }

            // ---- Top row: left stack (wifi/bluetooth/airdrop) + music ----
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
                label: "Display"
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
                label: "Sound"
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
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

                Behavior on opacity {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                    UtilityButton {
                        Layout.fillWidth: true
                        iconCode: "\ue51c" // dark_mode
                        label: "Dark"
                        enabled: false
                    }

                    UtilityButton {
                        Layout.fillWidth: true
                        iconCode: "\uea5f" // calculate
                        label: "Calc"
                        enabled: true
                        onClicked: root.launchFallbackApp("org.gnome.Calculator", "gnome-calculator", "calc")
                    }

                    UtilityButton {
                        Layout.fillWidth: true
                        iconCode: "\ue425" // timer
                        label: "Timer"
                        enabled: true
                        onClicked: root.launchFallbackApp("org.gnome.Clock", "gnome-clocks", "clock")
                    }

                    UtilityButton {
                        Layout.fillWidth: true
                        iconCode: "\ue3b0" // camera_alt
                        label: "Camera"
                        enabled: true
                        onClicked: root.launchFallbackApp("cheese", "cheese", "camera")
                    }
            }

            // ---- Edit Controls / expand toggle ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                radius: 14
                color: editMouse.containsMouse ? "#40ffffff" : "#59ffffff"
                border.color: "#30ffffff"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: root.controlsExpanded ? "Show Less" : "Edit Controls"
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
    component ToggleCircle: Item {
        id: tc
        property bool active: false
        property string iconCode: ""
        property color activeColor: root.accentActive
        property bool enabled: true
        signal clicked()

        implicitWidth: 48
        implicitHeight: 48

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: tc.active ? tc.activeColor : "#59ffffff"
            border.color: "#30ffffff"
            border.width: 1
            opacity: tc.enabled ? 1 : 0.4
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
        }

        MouseArea {
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
    component ConnectivityTile: Item {
        id: ct
        property var controls

        Rectangle {
            anchors.fill: parent
            radius: 22
            color: root.tileFill
            border.color: root.tileStroke
            border.width: 1

            // Inner top-left light.
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
                spacing: 7

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
                            text: ct.controls ? ct.controls.wifiName : "Off"
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
                        active: false
                        iconCode: "\ue195" // airplanemode_active (airdrop-like)
                        enabled: false
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: ct.controls && ct.controls.bluetoothEnabled
                              ? (ct.controls.bluetoothConnectedCount + " device(s)")
                              : "Bluetooth"
                        color: root.textTertiary
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
            }

            // Whole-tile click toggles Wi-Fi (macOS tile behavior).
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (ct.controls)
                        ct.controls.toggleWifi();
                }
            }
        }
    }

    // Now Playing tile (web cc-music-widget). Shows album art + transport.
    component MusicTile: Item {
        id: mt
        property var controls

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
                            text: mt.controls && mt.controls.hasMedia ? mt.controls.trackTitle : "Not Playing"
                            color: root.textPrimary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Text {
                            Layout.fillWidth: true
                            text: mt.controls && mt.controls.hasMedia ? mt.controls.trackArtist : "Media"
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

                        MouseArea {
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
                        color: "#66ffffff"
                        border.color: "#30ffffff"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: (mt.controls && mt.controls.isPlaying) ? "\ue034" : "\ue037" // pause / play_arrow
                            color: root.textPrimary
                            font.family: root.iconFont
                            font.pixelSize: 20
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: (mt.controls && mt.controls.canPlayPause) ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (mt.controls && mt.controls.canPlayPause)
                                    mt.controls.togglePlayPause();
                            }
                        }
                    }

                    Text {
                        text: "\ue044" // skip_next
                        color: (mt.controls && mt.controls.canNext) ? root.textPrimary : root.textTertiary
                        font.family: root.iconFont
                        font.pixelSize: 20
                        opacity: (mt.controls && mt.controls.canNext) ? 1 : 0.4

                        MouseArea {
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

    // White-fill slider (web cc-slider-pill + box-shadow trick). MouseArea
    // driven — the project never uses QtQuick.Controls, so we stay consistent.
    component GlassSlider: Item {
        id: gs
        property string iconCode: ""
        property string label: ""
        property real value: 0 // 0..1
        property bool enabled: true
        signal userSet(real value)

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
                    color: "#b3000000" // rgba(0,0,0,0.7)
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                // Pill track.
                Rectangle {
                    id: pillTrack
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    radius: 13
                    color: "#47ffffff" // rgba(255,255,255,0.28)
                    clip: true

                    // White fill from left to current value (no visible thumb).
                    Rectangle {
                        id: fill
                        x: 0
                        y: 0
                        height: parent.height
                        width: parent.width * Math.max(0, Math.min(1, gs.value))
                        radius: parent.radius
                        color: root.sliderFill
                    }

                    // Right-side icon (web cc-slider-icon-right).
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: gs.iconCode
                        color: "#731d1d1f"
                        font.family: root.iconFont
                        font.pixelSize: 15
                        z: 5
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
        signal clicked()

        implicitWidth: 48
        implicitHeight: 48

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: ubMouse.containsMouse ? "#66ffffff" : "#59ffffff"
            border.color: "#30ffffff"
            border.width: 1
            opacity: ub.enabled ? 1 : 0.4
        }

        Text {
            anchors.centerIn: parent
            text: ub.iconCode
            color: root.textPrimary
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
