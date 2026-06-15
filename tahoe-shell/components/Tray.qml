pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Item {
    id: root

    property var panelWindow
    readonly property int itemCount: SystemTray.items ? SystemTray.items.values.length : 0

    signal openMenuRequested(var item)

    implicitWidth: trayRow.implicitWidth
    implicitHeight: 24
    visible: itemCount > 0

    function displayMenu(item, sourceItem, mouseX, mouseY) {
        if (!item || !item.hasMenu)
            return;

        root.openMenuRequested(item);
    }

    function iconSource(item) {
        if (!item)
            return "";

        try {
            return String(item.icon || "");
        } catch (e) {
            return "";
        }
    }

    function fallbackLabel(item) {
        if (!item)
            return "?";

        try {
            var title = String(item.tooltipTitle || item.title || item.id || "").trim();
            if (title.length > 0)
                return title.charAt(0).toUpperCase();
        } catch (e) {}

        return "?";
    }

    function isAttention(item) {
        try {
            return Number(item.status) === 2;
        } catch (e) {
            return false;
        }
    }

    Row {
        id: trayRow

        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayItem

                required property var modelData

                width: 24
                height: 24

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: trayMouse.containsMouse ? "#38ffffff" : "#18ffffff"
                    border.color: root.isAttention(trayItem.modelData)
                        ? "#ccff453a"
                        : (trayMouse.containsMouse ? "#48ffffff" : "#2affffff")
                    border.width: 1
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    anchors.topMargin: 1
                    height: 1
                    radius: 1
                    color: "#40ffffff"
                }

                IconImage {
                    id: trayIcon

                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    implicitSize: 18
                    source: root.iconSource(trayItem.modelData)
                    mipmap: true
                    visible: root.iconSource(trayItem.modelData).length > 0 && status !== Image.Error
                }

                Text {
                    anchors.centerIn: parent
                    text: root.fallbackLabel(trayItem.modelData)
                    color: "#202124"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    visible: !trayIcon.visible
                }

                MouseArea {
                    id: trayMouse

                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: function(mouse) {
                        if (!trayItem.modelData)
                            return;

                        if (mouse.button === Qt.RightButton) {
                            if (trayItem.modelData.hasMenu)
                                root.displayMenu(trayItem.modelData, trayItem, mouse.x, mouse.y);
                            return;
                        }

                        if (mouse.button === Qt.MiddleButton) {
                            trayItem.modelData.secondaryActivate();
                            return;
                        }

                        if (trayItem.modelData.onlyMenu && trayItem.modelData.hasMenu) {
                            root.displayMenu(trayItem.modelData, trayItem, mouse.x, mouse.y);
                        } else {
                            trayItem.modelData.activate();
                        }
                    }
                }
            }
        }
    }
}
