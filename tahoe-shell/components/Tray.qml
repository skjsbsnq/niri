pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray

Item {
    id: root

    property var panelWindow
    readonly property int itemCount: SystemTray.items ? SystemTray.items.values.length : 0

    implicitWidth: trayRow.implicitWidth
    implicitHeight: 24
    visible: itemCount > 0

    function displayMenu(item, sourceItem, mouseX, mouseY) {
        if (!item || !item.hasMenu || !root.panelWindow)
            return;

        var point = sourceItem.mapToItem(null, mouseX, mouseY);
        item.display(root.panelWindow, Math.round(point.x), Math.round(point.y));
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

                width: 22
                height: 22

                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: trayMouse.containsMouse ? "#32ffffff" : "transparent"
                    border.color: trayMouse.containsMouse ? "#42ffffff" : "transparent"
                    border.width: 1
                }

                Image {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: trayItem.modelData ? trayItem.modelData.icon : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
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
