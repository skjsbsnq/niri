// Non-production Dynamic Island V2 visual preview.
// - Does not register IPC.
// - Does not open Notifications, MPRIS, or niri sockets.
// - Must never be imported by shell.qml.
//
// Launch:
//   qml tahoe-shell/preview/dynamic-island-v2/DynamicIslandV2Preview.qml
//   qmlscene tahoe-shell/preview/dynamic-island-v2/DynamicIslandV2Preview.qml

import QtQuick 2.15
import QtQuick.Window 2.15
import "mock/MockStates.js" as Mock
import "../../components/settings/SettingsTheme.js" as Theme

Window {
    id: root

    width: 1100
    height: 920
    visible: true
    title: "Tahoe Dynamic Island V2 Preview (non-production)"
    color: wallpaperBright ? "#d8e2ec" : "#1a1c20"

    property bool darkMode: true
    property bool wallpaperBright: false
    property string localeTag: "zh-CN"
    property string accentId: "blue"
    property int viewportWidth: 2048
    property real viewportScale: 1.25

    readonly property color accentColor: Theme.accent(darkMode, accentId)
    readonly property var states: Mock.allStates(localeTag)

    // Guard: never look like production shell wiring.
    readonly property bool isProductionShell: false
    readonly property bool registersIpc: false

    Column {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        Text {
            text: "Dynamic Island V2 — static preview"
            color: root.wallpaperBright ? "#1d1d1f" : "#f5f7fb"
            font.pixelSize: 18
            font.weight: Font.DemiBold
            font.family: "Noto Sans CJK SC"
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "dark focus glass · SettingsTheme island tokens · no IPC/services · viewport "
                  + root.viewportWidth + " @ scale " + root.viewportScale
                  + " · locale " + root.localeTag
            color: root.wallpaperBright ? "#5f6870" : "#aeb6c2"
            font.pixelSize: 12
            font.family: "Noto Sans CJK SC"
        }

        Row {
            spacing: 10

            Repeater {
                model: [
                    { label: "Light shell", action: "light" },
                    { label: "Dark shell", action: "dark" },
                    { label: "Bright WP", action: "wp_bright" },
                    { label: "Dark WP", action: "wp_dark" },
                    { label: "中文", action: "zh" },
                    { label: "EN", action: "en" },
                    { label: "1366", action: "w1366" },
                    { label: "1920", action: "w1920" },
                    { label: "2048", action: "w2048" },
                    { label: "scale 1.0", action: "s1" },
                    { label: "scale 1.25", action: "s125" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: chipLabel.implicitWidth + 16
                    height: 28
                    radius: 8
                    color: root.wallpaperBright ? "#80ffffff" : "#28ffffff"
                    border.width: 1
                    border.color: root.wallpaperBright ? "#40ffffff" : "#30ffffff"

                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        color: root.wallpaperBright ? "#1d1d1f" : "#f5f7fb"
                        font.pixelSize: 11
                        font.family: "Noto Sans CJK SC"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var a = String(modelData.action);
                            if (a === "light")
                                root.darkMode = false;
                            else if (a === "dark")
                                root.darkMode = true;
                            else if (a === "wp_bright")
                                root.wallpaperBright = true;
                            else if (a === "wp_dark")
                                root.wallpaperBright = false;
                            else if (a === "zh")
                                root.localeTag = "zh-CN";
                            else if (a === "en")
                                root.localeTag = "en-US";
                            else if (a === "w1366")
                                root.viewportWidth = 1366;
                            else if (a === "w1920")
                                root.viewportWidth = 1920;
                            else if (a === "w2048")
                                root.viewportWidth = 2048;
                            else if (a === "s1")
                                root.viewportScale = 1.0;
                            else if (a === "s125")
                                root.viewportScale = 1.25;
                        }
                    }
                }
            }
        }

        // Simulated top bar strip for visual relationship checks.
        Rectangle {
            width: Math.min(parent.width, Math.round(root.viewportWidth / root.viewportScale * 0.55))
            height: 32
            radius: 10
            color: root.wallpaperBright ? "#a8f5f6f8" : "#661d1f24"
            border.width: 1
            border.color: root.wallpaperBright ? "#90ffffff" : "#30ffffff"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "TopBar cluster"
                color: root.wallpaperBright ? "#3a3a3c" : "#c3ccd6"
                font.pixelSize: 11
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "reserve ≥ compact media"
                color: root.wallpaperBright ? "#3a3a3c" : "#c3ccd6"
                font.pixelSize: 11
            }
        }

        Flickable {
            width: parent.width
            height: parent.height - 160
            contentWidth: width
            contentHeight: grid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Flow {
                id: grid
                width: parent.width
                spacing: 18

                Repeater {
                    model: root.states
                    delegate: Column {
                        required property var modelData
                        spacing: 6
                        width: Math.max(modelData.width, 160)

                        Text {
                            text: String(modelData.kind)
                            color: root.wallpaperBright ? "#5f6870" : "#7f8996"
                            font.pixelSize: 10
                            font.family: "Noto Sans CJK SC"
                        }

                        Item {
                            width: modelData.width
                            height: modelData.height

                            DynamicIslandV2Surface {
                                id: surface
                                model: modelData
                                darkMode: root.darkMode
                                accentColor: root.accentColor
                            }

                            Loader {
                                anchors.fill: surface
                                source: root.sceneSource(modelData.kind)
                                onLoaded: root.bindScene(item, modelData)
                            }
                        }

                        Text {
                            text: modelData.width + "×" + modelData.height
                                  + " r" + modelData.radius
                                  + " · " + modelData.fillRole
                            color: root.wallpaperBright ? "#7f8996" : "#5f6870"
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }

    function sceneSource(kind) {
        switch (String(kind)) {
        case "clock":
            return Qt.resolvedUrl("scenes/ClockScene.qml");
        case "compact_media":
            return Qt.resolvedUrl("scenes/CompactMediaScene.qml");
        case "osd":
            return Qt.resolvedUrl("scenes/OsdScene.qml");
        case "notification_compact":
            return Qt.resolvedUrl("scenes/NotificationCompactScene.qml");
        case "notification_expanded":
            return Qt.resolvedUrl("scenes/NotificationExpandedScene.qml");
        case "expanded_media":
            return Qt.resolvedUrl("scenes/ExpandedMediaScene.qml");
        case "workspace":
            return Qt.resolvedUrl("scenes/WorkspaceScene.qml");
        case "timer_compact":
        case "timer_expanded":
            return Qt.resolvedUrl("scenes/TimerScene.qml");
        default:
            return "";
        }
    }

    function bindScene(item, modelData) {
        if (!item)
            return;
        item.model = modelData;
        if (item.textPrimary !== undefined)
            item.textPrimary = Theme.islandTextPrimary(root.darkMode);
        if (item.textSecondary !== undefined)
            item.textSecondary = Theme.islandTextSecondary(root.darkMode);
        if (item.textMuted !== undefined)
            item.textMuted = Theme.islandTextMuted(root.darkMode);
        if (item.accentColor !== undefined)
            item.accentColor = root.accentColor;
        if (item.trackColor !== undefined)
            item.trackColor = Theme.islandProgressTrack(root.darkMode);
        if (item.controlFill !== undefined)
            item.controlFill = Theme.islandControlFill(root.darkMode);
        if (item.criticalColor !== undefined)
            item.criticalColor = Theme.islandCriticalEdge(root.darkMode);
    }
}
