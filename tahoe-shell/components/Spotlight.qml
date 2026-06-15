pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property bool open: false
    property var appsService
    property string query: ""
    readonly property var results: root.appsService ? root.appsService.spotlightResults(root.query, 6) : []

    signal closeRequested()

    visible: open || spotlightPanel.opacity > 0.01
    aboveWindows: true
    exclusiveZone: 0
    focusable: open
    color: "transparent"

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    onOpenChanged: {
        if (open) {
            query = "";
            Qt.callLater(function() {
                if (root.open)
                    searchInput.forceActiveFocus();
            });
        }
    }

    function launchApp(app) {
        if (!app || !root.appsService)
            return;

        root.appsService.launchApp(app);
        root.closeRequested();
    }

    function launchFirstResult() {
        if (root.results.length > 0)
            launchApp(root.results[0]);
    }

    function launchShortcut(kind) {
        if (!root.appsService)
            return;

        if (kind === "copy") {
            var text = String(root.query || "");
            if (text.trim().length === 0)
                return;

            Quickshell.execDetached({
                command: ["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", text],
                workingDirectory: ""
            });
            root.closeRequested();
            return;
        }

        var candidates = [];
        if (kind === "store") {
            candidates = [
                "org.gnome.Software",
                "gnome-software",
                "org.kde.discover",
                "plasma-discover",
                "software"
            ];
        } else if (kind === "files") {
            candidates = [
                "org.gnome.Nautilus",
                "nautilus",
                "org.kde.dolphin",
                "dolphin",
                "thunar",
                "files"
            ];
        } else if (kind === "shortcuts") {
            candidates = [
                "shortcuts",
                "org.gnome.Settings",
                "gnome-control-center",
                "systemsettings",
                "settings"
            ];
        }

        var app = root.appsService.findApplication(candidates);
        if (app)
            launchApp(app);
    }

    BackgroundEffect.blurRegion: Region {
        item: spotlightPanel
        radius: 28
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    Item {
        id: spotlightPanel
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(58, parent.height * 0.18)
        width: Math.min(parent.width - 28, 690)
        height: spotlightSurface.height + (resultsSurface.visible ? resultsSurface.height + 10 : 0)
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 1.04

        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) {
                mouse.accepted = true;
            }
        }

        Rectangle {
            id: spotlightSurface
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 66
            radius: 33
            color: "#dceaf7ff"
            border.color: "#88ffffff"
            border.width: 1

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 32
                color: "transparent"
                border.color: "#24ffffff"
                border.width: 1
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 25
                anchors.verticalCenter: parent.verticalCenter
                text: "\ue8b6"
                color: "#4f5963"
                font.family: "Material Icons"
                font.pixelSize: 24
            }

            Text {
                anchors.left: searchInput.left
                anchors.right: shortcutRow.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "Search"
                color: "#69737d"
                font.pixelSize: 22
                elide: Text.ElideRight
                visible: searchInput.text.length === 0
            }

            TextInput {
                id: searchInput
                anchors.left: parent.left
                anchors.leftMargin: 64
                anchors.right: shortcutRow.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                height: 36
                text: root.query
                color: "#202124"
                selectionColor: "#7ab7ff"
                selectedTextColor: "#ffffff"
                font.pixelSize: 22
                clip: true
                focus: root.open
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: root.query = text
                Keys.onEscapePressed: root.closeRequested()
                Keys.onReturnPressed: root.launchFirstResult()
            }

            Row {
                id: shortcutRow
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Repeater {
                    model: [
                        { "kind": "store", "icon": "AppStore-Symbol.png" },
                        { "kind": "files", "icon": "Folder-Symbol.png" },
                        { "kind": "shortcuts", "icon": "Shortcuts-Symbol.png" },
                        { "kind": "copy", "icon": "Copy-Symbol.png" }
                    ]

                    delegate: Item {
                        id: shortcutButton

                        required property var modelData

                        width: 38
                        height: 38

                        Rectangle {
                            anchors.fill: parent
                            radius: 19
                            color: shortcutMouse.containsMouse ? "#70ffffff" : "#40ffffff"
                            border.color: "#55ffffff"
                            border.width: 1
                        }

                        Image {
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            source: root.appsService ? root.appsService.iconPath("symbols", shortcutButton.modelData.icon) : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        MouseArea {
                            id: shortcutMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launchShortcut(shortcutButton.modelData.kind)
                        }
                    }
                }
            }
        }

        Rectangle {
            id: resultsSurface
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: spotlightSurface.bottom
            anchors.topMargin: 10
            height: resultsColumn.implicitHeight + 12
            radius: 18
            color: "#d8f7f8fb"
            border.color: "#65ffffff"
            border.width: 1
            opacity: root.open && root.query.trim().length > 0 ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            Column {
                id: resultsColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                spacing: 2

                Repeater {
                    model: ScriptModel {
                        values: root.results
                    }

                    delegate: Item {
                        id: resultButton

                        required property var modelData

                        width: resultsColumn.width
                        height: 48

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: resultMouse.containsMouse ? "#44ffffff" : "transparent"
                        }

                        Image {
                            id: resultIcon
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32
                            source: root.appsService ? root.appsService.iconForApp(resultButton.modelData) : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        Text {
                            anchors.left: resultIcon.right
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.appsService ? root.appsService.appLabel(resultButton.modelData) : ""
                            color: "#202124"
                            font.pixelSize: 14
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        MouseArea {
                            id: resultMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launchApp(resultButton.modelData)
                        }
                    }
                }

                Text {
                    width: parent.width
                    height: 42
                    text: "No Results"
                    color: "#5a6570"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    visible: root.query.trim().length > 0 && root.results.length === 0
                }
            }
        }
    }
}
