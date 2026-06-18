pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property bool open: false
    property var appsService
    // See shell.qml useSpring. Spring on the launcher scale corrupts the
    // app-icon Image textures on VMware/software GPUs. Default false.
    property bool useSpring: false
    property string query: ""
    readonly property var filteredApps: root.appsService ? root.appsService.filteredLaunchpadApps(root.query) : []

    signal closeRequested()

    visible: open || backdrop.opacity > 0.01
    aboveWindows: true
    exclusiveZone: 0
    focusable: open
    color: "transparent"
    WlrLayershell.namespace: "tahoe-launchpad"

    onOpenChanged: {
        if (open) {
            query = "";
            Qt.callLater(function() {
                if (root.open)
                    searchInput.forceActiveFocus();
            });
        }
    }

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    TahoeGlass.regions: [
        TahoeGlassRegion {
            x: backdrop.x
            y: backdrop.y
            width: backdrop.width
            height: backdrop.height
            material: backdrop.tahoeGlassMaterial
            radius: backdrop.tahoeGlassRadius
            blur: true
            shadow: false
            clip: true
            interaction: backdrop.opacity
            materialAlpha: backdrop.opacity
            enabled: root.open || backdrop.opacity > 0.01
        }
    ]

    Rectangle {
        id: backdrop
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialBackdrop
        readonly property real tahoeGlassRadius: GlassStyle.RadiusBackdrop

        anchors.fill: parent
        // The scrim is just blur + tint, structurally identical to the
        // control center: the glass region above blurs whatever is behind,
        // and this Rectangle is the only thing drawn on top. Kept a touch
        // denser than the control center's 13% (#20) because a full-screen
        // overlay needs more contrast to make the icons pop. Previously
        // there was also a second, SHARP wallpaper Image painted over the
        // blur at 22% opacity — that punched through the blur and made the
        // Launchpad read as "a different, lesser blur" than the control
        // center. Removed. See glass-consistency-fix-plan.md §1.
        color: GlassStyle.FillBackdrop
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    Item {
        id: launcher
        anchors.centerIn: parent
        width: Math.min(parent.width - 72, 820)
        height: Math.min(parent.height - 96, 590)
        opacity: root.open ? 1 : 0
        // Open: scale 1.2 -> 1, matching the web Launchpad reference. Keep
        // the layer cache only while the launcher is visibly animating.
        scale: root.open ? 1 : 1.2
        layer.enabled: opacity > 0.01 && (scale !== 1 || opacity !== 1)
        layer.smooth: true

        Behavior on opacity {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }

        // Scale settle. Spring gives the Tahoe ease-out feel on real GPUs,
        // but springing the launcher scale (which wraps all app-icon Images)
        // corrupts their textures on VMware/software GPUs. NumberAnimation is
        // the safe default; useSpring flips back to spring.
        Behavior on scale {
            enabled: !root.useSpring
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: root.useSpring
            SpringAnimation {
                spring: 200
                damping: 1.0
                epsilon: 0.01
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) {
                mouse.accepted = true;
            }
        }

        Item {
            id: searchBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: Math.min(parent.width, 380)
            height: 42

            Rectangle {
                anchors.fill: parent
                radius: 21
                color: "#cdeaf6ff"
                border.color: "#72ffffff"
                border.width: 1
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 20
                color: "transparent"
                border.color: "#24ffffff"
                border.width: 1
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 17
                anchors.verticalCenter: parent.verticalCenter
                text: "\ue8b6"
                color: "#5f6870"
                font.family: "Material Icons"
                font.pixelSize: 18
            }

            Text {
                anchors.left: searchInput.left
                anchors.verticalCenter: parent.verticalCenter
                text: "搜索"
                color: "#6f7780"
                font.pixelSize: 15
                visible: searchInput.text.length === 0
            }

            TextInput {
                id: searchInput
                anchors.left: parent.left
                anchors.leftMargin: 46
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                height: 26
                text: root.query
                color: "#202124"
                selectionColor: "#7ab7ff"
                selectedTextColor: "#ffffff"
                font.pixelSize: 15
                clip: true
                focus: root.open
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: root.query = text
                Keys.onEscapePressed: root.closeRequested()
                Keys.onReturnPressed: {
                    if (root.filteredApps.length > 0 && root.appsService) {
                        root.appsService.launchApp(root.filteredApps[0]);
                        root.closeRequested();
                    }
                }
            }
        }

        Flickable {
            anchors.fill: parent
            anchors.topMargin: 74
            contentWidth: width
            contentHeight: grid.implicitHeight
            clip: true

            Grid {
                id: grid
                width: parent.width
                columns: Math.max(4, Math.floor(width / 104))
                rowSpacing: 22
                columnSpacing: 12

                Repeater {
                    model: ScriptModel {
                        values: root.filteredApps
                    }

                    delegate: Item {
                        id: appButton

                        required property var modelData

                        width: grid.width / grid.columns - grid.columnSpacing
                        height: 96

                        Image {
                            id: appIcon
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            width: 64
                            height: 64
                            source: root.appsService ? root.appsService.iconForApp(appButton.modelData) : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: appIcon.bottom
                            anchors.topMargin: 7
                            text: root.appsService ? root.appsService.appLabel(appButton.modelData) : ""
                            color: "#202124"
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.appsService)
                                    root.appsService.launchApp(appButton.modelData);
                                root.closeRequested();
                            }
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 92
                text: "无结果"
                color: "#4e565e"
                font.pixelSize: 15
                font.weight: Font.DemiBold
                visible: root.query.trim().length > 0 && root.filteredApps.length === 0
            }
        }
    }
}
