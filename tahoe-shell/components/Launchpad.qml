pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property bool open: false
    property var appsService
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

    signal closeRequested()

    visible: open || launcher.opacity > 0.01
    aboveWindows: true
    exclusiveZone: 0
    focusable: open
    color: "transparent"
    WlrLayershell.namespace: "tahoe-launchpad"

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

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    TahoeGlass.regions: [
        TahoeGlassRegion {
            item: panelSurface
            material: panelSurface.tahoeGlassMaterial
            radius: panelSurface.tahoeGlassRadius
            blur: false
            shadow: false
            clip: true
            interaction: launcher.opacity
            materialAlpha: 0.0
            enabled: root.open || launcher.opacity > 0.01
        }
    ]

    Rectangle {
        id: backdrop
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialBackdrop
        readonly property real tahoeGlassRadius: GlassStyle.RadiusBackdrop

        anchors.fill: parent
        color: "transparent"
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    Item {
        id: launcher
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -18
        width: Math.min(parent.width - 36, 760)
        height: Math.min(parent.height - 64, 540)
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) {
                mouse.accepted = true;
            }
        }

        Rectangle {
            id: panelSurface
            readonly property string tahoeGlassMaterial: GlassStyle.MaterialBackdrop
            readonly property real tahoeGlassRadius: 26

            anchors.fill: parent
            radius: tahoeGlassRadius
            color: "#bdeaf6ff"
            border.color: "#70ffffff"
            border.width: 1
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: panelSurface.radius - 1
            color: "transparent"
            border.color: "#30ffffff"
            border.width: 1
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
                color: "#d7f7fbff"
                border.color: "#72ffffff"
                border.width: 1
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 22
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
                font.pixelSize: 19
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
                    required property var modelData

                    width: 34
                    height: 30

                    Rectangle {
                        anchors.fill: parent
                        radius: 9
                        color: root.category === modelData.id ? "#f2ffffff" : categoryMouse.containsMouse ? "#72ffffff" : "#38ffffff"
                        border.color: root.category === modelData.id ? "#8cffffff" : "#32ffffff"
                        border.width: 1
                    }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.icon
                        color: "#34404a"
                        font.family: "Material Icons"
                        font.pixelSize: 17
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
                columns: Math.max(3, Math.floor(width / 92))
                rowSpacing: 18
                columnSpacing: 0

                Repeater {
                    model: ScriptModel {
                        values: root.filteredApps
                    }

                    delegate: Item {
                        id: appButton

                        required property var modelData

                        width: grid.width / grid.columns
                        height: 66

                        Rectangle {
                            anchors.centerIn: appIcon
                            width: 58
                            height: 58
                            radius: 14
                            color: appMouse.containsMouse ? "#56ffffff" : "transparent"
                            border.color: appMouse.containsMouse ? "#42ffffff" : "transparent"
                            border.width: 1
                        }

                        Image {
                            id: appIcon
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            width: 50
                            height: 50
                            source: root.appsService ? root.appsService.iconForApp(appButton.modelData) : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            sourceSize.width: 128
                            sourceSize.height: 128
                            asynchronous: true
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
