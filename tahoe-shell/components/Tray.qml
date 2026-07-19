pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "Motion.js" as Motion

Item {
    id: root

    property var panelWindow
    property var settingsService
    property bool darkMode: false
    readonly property int itemCount: SystemTray.items ? SystemTray.items.values.length : 0
    readonly property var orderedEntries: sortedEntries(itemCount)
    readonly property real targetWidth: orderedEntries.length > 0
        ? orderedEntries.length * 24 + Math.max(0, orderedEntries.length - 1) * 6
        : 0
    property real animatedWidth: targetWidth
    readonly property color trayText: darkMode ? "#f5f7fb" : "#1d1d1f"
    readonly property color trayHoverFill: darkMode ? "#24ffffff" : "#26ffffff"
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

    implicitWidth: animatedWidth
    implicitHeight: 22
    opacity: itemCount > 0 ? 1 : 0
    visible: animatedWidth > 0.01 || opacity > 0.01

    Behavior on animatedWidth {
        NumberAnimation { duration: Motion.elementResize(root.settingsService); easing.type: Motion.emphasizedDecel }
    }

    Behavior on opacity {
        NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
    }

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

    function trayItemKey(item, fallbackIndex) {
        try {
            var id = String(item && item.id || "").trim();
            if (id.length > 0)
                return id;
        } catch (e) {}
        return "tray-fallback-" + fallbackIndex + ":" + itemText(item);
    }

    function sortedEntries(count) {
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
        for (var j = 0; j < decorated.length; j++) {
            var entry = decorated[j];
            result.push({
                "modelKey": trayItemKey(entry.item, entry.index),
                "item": entry.item
            });
        }
        return result;
    }

    ListView {
        id: trayList
        width: root.animatedWidth
        height: root.implicitHeight
        anchors.verticalCenter: parent.verticalCenter
        orientation: ListView.Horizontal
        interactive: false
        clip: false
        spacing: 6

        model: ScriptModel {
            objectProp: "modelKey"
            values: root.orderedEntries
        }

        delegate: Item {
            id: trayItem

            required property var modelData
            readonly property var trayObject: modelData ? modelData.item : null
            property real lifecycleOpacity: 1
            property real lifecycleScale: 1
            property real pressScale: Motion.pressScaleFor(root.settingsService, trayMouse.pressed)
            property real pressOpacity: trayMouse.pressed ? 0.75 : 1

            width: 24
            height: 22
            scale: lifecycleScale * pressScale
            opacity: lifecycleOpacity * pressOpacity

            Behavior on pressScale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
            Behavior on pressOpacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

            Rectangle {
                anchors.fill: parent
                radius: 7
                color: trayMouse.containsMouse ? root.trayHoverFill : "transparent"
                border.color: root.isAttention(trayItem.trayObject)
                    ? root.trayAttention
                    : "transparent"
                border.width: root.isAttention(trayItem.trayObject) ? 1 : 0

                Behavior on color {
                    ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                }
            }

            IconImage {
                id: trayIcon

                anchors.centerIn: parent
                width: 16
                height: 16
                implicitSize: 16
                source: root.iconSource(trayItem.trayObject)
                mipmap: true
                visible: root.iconSource(trayItem.trayObject).length > 0 && status !== Image.Error
            }

            Text {
                anchors.centerIn: parent
                text: root.fallbackLabel(trayItem.trayObject)
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
                    if (!trayItem.trayObject)
                        return;

                    if (mouse.button === Qt.RightButton) {
                        if (trayItem.trayObject.hasMenu)
                            root.displayMenu(trayItem.trayObject, trayItem, mouse.x, mouse.y);
                        return;
                    }

                    if (mouse.button === Qt.MiddleButton) {
                        trayItem.trayObject.secondaryActivate();
                        return;
                    }

                    if (trayItem.trayObject.onlyMenu && trayItem.trayObject.hasMenu) {
                        root.displayMenu(trayItem.trayObject, trayItem, mouse.x, mouse.y);
                    } else {
                        trayItem.trayObject.activate();
                    }
                }
            }
        }

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "lifecycleOpacity"; from: 0; to: 1; duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                NumberAnimation { property: "lifecycleScale"; from: 0.82; to: 1; duration: Motion.elementResize(root.settingsService); easing.type: Motion.emphasizedDecel }
            }
        }

        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "lifecycleOpacity"; to: 0; duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                NumberAnimation { property: "lifecycleScale"; to: 0.82; duration: Motion.elementResize(root.settingsService); easing.type: Motion.emphasizedDecel }
            }
        }

        move: Transition {
            NumberAnimation { properties: "x,y"; duration: Motion.elementMove(root.settingsService); easing.type: Motion.emphasizedDecel }
        }

        displaced: Transition {
            NumberAnimation { properties: "x,y"; duration: Motion.elementMove(root.settingsService); easing.type: Motion.emphasizedDecel }
        }
    }
}
