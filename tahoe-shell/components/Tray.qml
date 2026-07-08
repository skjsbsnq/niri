pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Item {
    id: root

    property var panelWindow
    property bool darkMode: false
    readonly property int itemCount: SystemTray.items ? SystemTray.items.values.length : 0
    readonly property var orderedItems: sortedItems(itemCount)
    readonly property color trayText: darkMode ? "#f5f7fb" : "#1d1d1f"
    readonly property color trayHoverFill: darkMode ? "#24ffffff" : "#26ffffff"
    readonly property color trayHoverStroke: darkMode ? "#32ffffff" : "#28ffffff"
    readonly property color trayAttention: "#ff453a"

    signal openMenuRequested(var item, var anchorRect)

    function anchorRectFor(sourceItem) {
        if (!sourceItem || !root.panelWindow)
            return null;

        var rect = root.panelWindow.itemRect(sourceItem);
        return {
            "x": Math.round(rect.x),
            "y": Math.round(rect.y),
            "width": Math.round(rect.width),
            "height": Math.round(rect.height)
        };
    }

    implicitWidth: trayRow.implicitWidth
    implicitHeight: 22
    visible: itemCount > 0

    function displayMenu(item, sourceItem, mouseX, mouseY) {
        if (!item || !item.hasMenu)
            return;

        root.openMenuRequested(item, root.anchorRectFor(sourceItem));
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

    function itemText(item) {
        if (!item)
            return "";

        var parts = [];
        try { parts.push(String(item.id || "")); } catch (e) {}
        try { parts.push(String(item.title || "")); } catch (e) {}
        try { parts.push(String(item.tooltipTitle || "")); } catch (e) {}
        try { parts.push(String(item.icon || "")); } catch (e) {}
        return parts.join(" ").toLowerCase();
    }

    function isKeyboardLike(item) {
        var text = itemText(item);
        return text.indexOf("fcitx") >= 0
            || text.indexOf("ibus") >= 0
            || text.indexOf("input") >= 0
            || text.indexOf("ime") >= 0
            || text.indexOf("keyboard") >= 0
            || text.indexOf("输入法") >= 0
            || text.indexOf("键盘") >= 0;
    }

    function sortedItems(count) {
        var values = SystemTray.items ? SystemTray.items.values : [];
        var decorated = [];
        for (var i = 0; i < values.length; i++) {
            var item = values[i];
            decorated.push({
                "item": item,
                "priority": isKeyboardLike(item) ? 1 : 0,
                "index": i
            });
        }

        decorated.sort(function(a, b) {
            if (a.priority !== b.priority)
                return a.priority - b.priority;
            return a.index - b.index;
        });

        var result = [];
        for (var j = 0; j < decorated.length; j++)
            result.push(decorated[j].item);
        return result;
    }

    Row {
        id: trayRow

        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Repeater {
            model: ScriptModel {
                values: root.orderedItems
            }

            delegate: Item {
                id: trayItem

                required property var modelData

                width: 24
                height: 22

                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    color: trayMouse.containsMouse ? root.trayHoverFill : "transparent"
                    border.color: root.isAttention(trayItem.modelData)
                        ? root.trayAttention
                        : (trayMouse.containsMouse ? root.trayHoverStroke : "transparent")
                    border.width: 1
                }

                IconImage {
                    id: trayIcon

                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    implicitSize: 16
                    source: root.iconSource(trayItem.modelData)
                    mipmap: true
                    visible: root.iconSource(trayItem.modelData).length > 0 && status !== Image.Error
                }

                Text {
                    anchors.centerIn: parent
                    text: root.fallbackLabel(trayItem.modelData)
                    color: root.trayText
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
