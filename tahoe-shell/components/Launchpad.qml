pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "Motion.js" as Motion
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property bool open: false
    property var appsService
    property var settingsService
    // Kept for the shell.qml interface. The launcher no longer scales as a
    // whole, because scaling the layer makes themed app icons look blurry.
    property bool useSpring: false
    property string query: ""
    property string category: "all"
    readonly property var filteredApps: root.appsService ? root.appsService.filteredLaunchpadApps(root.query, root.category) : []
    readonly property var categories: [
        { "id": "all", "icon": "\ue5c3" },
        { "id": "development", "icon": "\ue869" },
        { "id": "internet", "icon": "\ue80b" },
        { "id": "media", "icon": "\ue3f4" },
        { "id": "office", "icon": "\ue8f9" },
        { "id": "games", "icon": "\ue338" },
        { "id": "system", "icon": "\ue8b8" }
    ]
    readonly property int screenWidth: Math.max(1, root.numberOr(root.screen && root.screen.width, 1))
    readonly property int screenHeight: Math.max(1, root.numberOr(root.screen && root.screen.height, 1))
    readonly property int launcherWidth: Math.min(760, Math.max(280, root.screenWidth - 48))
    readonly property int launcherHeight: Math.min(560, Math.max(360, root.screenHeight - 110))
    readonly property int launcherLeft: Math.round(Math.max(8, (root.screenWidth - root.launcherWidth) / 2))
    readonly property int launcherTop: Math.round(Math.max(8, Math.min(Math.max(8, root.screenHeight - root.launcherHeight - 8), (root.screenHeight - root.launcherHeight) / 2 - 12)))
    // Launchpad stays on the QML outer animation path: compositor scaling made
    // app icons and the glass blur look soft on large centered surfaces.
    readonly property bool compositorLayerAnimations: false

    signal closeRequested()

    function numberOr(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
    }

    visible: compositorLayerAnimations ? open : (open || launcher.opacity > 0.01)
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    focusable: open
    implicitWidth: screenWidth
    implicitHeight: screenHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "tahoe-launchpad"

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    onOpenChanged: {
        if (open) {
            query = "";
            category = "all";
            Qt.callLater(function() {
                if (root.open)
                    searchInput.forceActiveFocus();
            });
        }
    }

    TahoeGlass.regions: [panelSurface.region]

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closeRequested()
    }

    Item {
        id: launcher
        property real contentScale: root.compositorLayerAnimations ? 1 : (root.open ? 1 : 0.98)

        x: root.launcherLeft
        y: root.launcherTop
        width: root.launcherWidth
        height: root.launcherHeight
        opacity: root.compositorLayerAnimations ? 1 : (root.open ? 1 : 0)

        transform: Scale {
            origin.x: launcher.width / 2
            origin.y: launcher.height / 2
            xScale: launcher.contentScale
            yScale: launcher.contentScale
        }

        Behavior on opacity {
            NumberAnimation { duration: Motion.panelExit(root.settingsService); easing.type: Motion.emphasizedDecel }
        }

        Behavior on contentScale {
            NumberAnimation { duration: Motion.menuEnter(root.settingsService); easing.type: Motion.emphasizedDecel }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) {
                mouse.accepted = true;
            }
        }

        GlassPanel {
            id: panelSurface

            anchors.fill: parent
            material: GlassStyle.MaterialLauncher
            radius: GlassStyle.RadiusPanel
            fillColor: GlassStyle.FillLauncher
            strokeColor: GlassStyle.StrokeLauncher
            useItemRegion: false
            regionX: Math.round(launcher.x + panelSurface.x)
            regionY: Math.round(launcher.y + panelSurface.y)
            regionWidth: Math.round(panelSurface.width)
            regionHeight: Math.round(panelSurface.height)
            interaction: root.compositorLayerAnimations ? 1 : launcher.opacity
            materialAlpha: root.compositorLayerAnimations ? 1 : launcher.opacity
            glassEnabled: root.open || launcher.opacity > 0.01
        }

        Item {
            id: searchBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 14
            width: parent.width - 28
            height: 46

            Rectangle {
                anchors.fill: parent
                radius: 23
                color: GlassStyle.FillPill
                border.color: GlassStyle.StrokePill
                border.width: 1
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 22
                color: "transparent"
                border.color: "#28ffffff"
                border.width: 1
            }

            TahoeSymbol {
                anchors.left: parent.left
                anchors.leftMargin: 17
                anchors.verticalCenter: parent.verticalCenter
                name: "\ue8b6"
                color: "#5f6870"
                size: 19
            }

            Text {
                anchors.left: searchInput.left
                anchors.verticalCenter: parent.verticalCenter
                text: "搜索应用..."
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

        Row {
            id: categoryStrip
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: searchBox.bottom
            anchors.topMargin: 10
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            height: 32
            spacing: 6

            Repeater {
                model: ScriptModel {
                    values: root.categories
                }

                delegate: Item {
                    id: categoryButton
                    required property var modelData

                    width: 34
                    height: 30
                    scale: Motion.pressScaleFor(root.settingsService, categoryMouse.pressed)

                    Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 9
                        color: categoryMouse.pressed
                            ? "#3cffffff"
                            : root.category === modelData.id ? "#78ffffff" : categoryMouse.containsMouse ? "#50ffffff" : "#28ffffff"
                        border.color: root.category === modelData.id ? GlassStyle.StrokePanelBright : "#30ffffff"
                        border.width: 1
                    }

                    TahoeSymbol {
                        anchors.centerIn: parent
                        name: modelData.icon
                        color: "#34404a"
                        size: 17
                    }

                    MouseArea {
                        id: categoryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.category = modelData.id
                    }
                }
            }
        }

        Flickable {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: categoryStrip.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 16
            anchors.bottomMargin: 18
            contentWidth: width
            contentHeight: grid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Grid {
                id: grid
                width: parent.width
                columns: Math.max(3, Math.floor(width / 104))
                rowSpacing: 12
                columnSpacing: 0

                Repeater {
                    model: ScriptModel {
                        values: root.filteredApps
                    }

                    delegate: Item {
                        id: appButton

                        required property var modelData

                        width: grid.width / grid.columns
                        height: 94
                        scale: Motion.pressScaleFor(root.settingsService, appMouse.pressed)

                        Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 15
                            color: appMouse.pressed ? "#28ffffff" : (appMouse.containsMouse ? "#38ffffff" : "transparent")
                            border.color: appMouse.containsMouse ? "#40ffffff" : "transparent"
                            border.width: 1
                        }

                        Image {
                            id: appIcon
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            width: 48
                            height: 48
                            source: root.appsService ? root.appsService.iconForApp(appButton.modelData) : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            sourceSize.width: 128
                            sourceSize.height: 128
                            asynchronous: true
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: appIcon.bottom
                            anchors.topMargin: 5
                            anchors.leftMargin: 5
                            anchors.rightMargin: 5
                            text: root.appsService ? root.appsService.appLabel(appButton.modelData) : ""
                            color: "#25303a"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            lineHeight: 0.9
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: appMouse
                            anchors.fill: parent
                            hoverEnabled: true
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
