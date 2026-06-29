pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property bool open: false
    property var windowsService
    property var appsService
    property string selectedWindowKey: ""
    property var selectedCardItem: null
    readonly property var windowChoices: windowsService && windowsService.windowList ? windowsService.windowList : []
    readonly property var workspaceGroups: buildWorkspaceGroups()
    readonly property int screenWidth: Math.max(1, numberOr(root.screen && root.screen.width, root.width))
    readonly property int screenHeight: Math.max(1, numberOr(root.screen && root.screen.height, root.height))
    readonly property int panelWidth: Math.max(300, Math.min(screenWidth - 40, 1080))
    readonly property int panelHeight: Math.min(screenHeight - 72, 720)
    readonly property int panelLeft: Math.round(Math.max(8, (screenWidth - panelWidth) / 2))
    readonly property int panelTop: Math.round(Math.max(44, (screenHeight - panelHeight) / 2))

    signal closeRequested()

    visible: open || overview.opacity > 0.01
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    focusable: open
    implicitWidth: screenWidth
    implicitHeight: screenHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "tahoe-window-overview"

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    onOpenChanged: {
        if (open) {
            selectFocusedOrFirst();
            Qt.callLater(function() {
                if (root.open)
                    focusCatcher.forceActiveFocus();
            });
        }
    }

    onWindowChoicesChanged: if (open) syncSelectionAfterModelChange()

    function numberOr(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
    }

    function windowKey(window) {
        if (!window)
            return "";
        if (window.id !== undefined && window.id !== null)
            return "id:" + String(window.id);
        var appId = String(window.appId || "");
        var title = String(window.title || "");
        return "fallback:" + appId + ":" + title;
    }

    function windowIndexForKey(key) {
        var needle = String(key || "");
        if (needle.length === 0)
            return -1;
        for (var i = 0; i < windowChoices.length; i++) {
            if (windowKey(windowChoices[i]) === needle)
                return i;
        }
        return -1;
    }

    function currentWindow() {
        var index = windowIndexForKey(selectedWindowKey);
        return index >= 0 ? windowChoices[index] : null;
    }

    function selectFocusedOrFirst() {
        for (var i = 0; i < windowChoices.length; i++) {
            if (windowChoices[i] && windowChoices[i].isFocused) {
                selectedWindowKey = windowKey(windowChoices[i]);
                return;
            }
        }
        selectedWindowKey = windowChoices.length > 0 ? windowKey(windowChoices[0]) : "";
    }

    function syncSelectionAfterModelChange() {
        if (windowChoices.length === 0) {
            selectedWindowKey = "";
            return;
        }
        if (windowIndexForKey(selectedWindowKey) < 0)
            selectFocusedOrFirst();
    }

    function cycleSelection(delta) {
        if (windowChoices.length === 0)
            return;
        var index = windowIndexForKey(selectedWindowKey);
        if (index < 0)
            index = 0;
        var next = (index + delta) % windowChoices.length;
        if (next < 0)
            next += windowChoices.length;
        selectedWindowKey = windowKey(windowChoices[next]);
        overviewFlick.ensureVisible();
    }

    function activateWindow(window) {
        if (!window || !windowsService)
            return;

        if (window.isMinimized)
            windowsService.restore(window);
        else
            windowsService.activate(window);
        closeRequested();
    }

    function activateSelected() {
        activateWindow(currentWindow());
    }

    function workspaceLabel(workspace, fallbackIndex) {
        return windowsService ? windowsService.workspaceDisplayLabel(workspace, fallbackIndex) : "工作区";
    }

    function groupSubtitle(workspace) {
        var output = String(workspace && workspace.output ? workspace.output : "").trim();
        return output.length > 0 ? output : "默认输出";
    }

    function windowsForWorkspace(workspace) {
        var out = [];
        for (var i = 0; i < windowChoices.length; i++) {
            var window = windowChoices[i];
            if (windowsService && windowsService.isWindowOnWorkspace(window, workspace))
                out.push(window);
        }
        return out;
    }

    function geometryBounds(windows) {
        var minX = 0;
        var minY = 0;
        var maxX = 1;
        var maxY = 1;
        var initialized = false;

        for (var i = 0; i < windows.length; i++) {
            var rect = windows[i] ? windows[i].geometry : null;
            if (!rect)
                continue;

            var x = Number(rect.x) || 0;
            var y = Number(rect.y) || 0;
            var width = Math.max(1, Number(rect.width || rect.w) || 1);
            var height = Math.max(1, Number(rect.height || rect.h) || 1);
            if (!initialized) {
                minX = x;
                minY = y;
                maxX = x + width;
                maxY = y + height;
                initialized = true;
            } else {
                minX = Math.min(minX, x);
                minY = Math.min(minY, y);
                maxX = Math.max(maxX, x + width);
                maxY = Math.max(maxY, y + height);
            }
        }

        if (!initialized)
            return { "x": 0, "y": 0, "width": 1, "height": 1, "valid": false };

        return {
            "x": minX,
            "y": minY,
            "width": Math.max(1, maxX - minX),
            "height": Math.max(1, maxY - minY),
            "valid": true
        };
    }

    function buildWorkspaceGroups() {
        var groups = [];
        var used = {};
        var workspaces = windowsService && windowsService.workspaceList ? windowsService.workspaceList : [];

        for (var i = 0; i < workspaces.length; i++) {
            var workspace = workspaces[i];
            var windows = windowsForWorkspace(workspace);
            var key = workspace && workspace.id !== undefined && workspace.id !== null ? "workspace:" + String(workspace.id) : "workspace:" + String(i);
            groups.push({
                "key": key,
                "title": workspaceLabel(workspace, i),
                "subtitle": groupSubtitle(workspace),
                "workspace": workspace,
                "windows": windows,
                "bounds": geometryBounds(windows)
            });
            for (var j = 0; j < windows.length; j++)
                used[windowKey(windows[j])] = true;
        }

        var loose = [];
        for (var k = 0; k < windowChoices.length; k++) {
            var window = windowChoices[k];
            if (!used[windowKey(window)])
                loose.push(window);
        }

        if (loose.length > 0 || groups.length === 0) {
            groups.push({
                "key": "unassigned",
                "title": workspaces.length > 0 ? "未分配窗口" : "所有窗口",
                "subtitle": "Tahoe",
                "workspace": null,
                "windows": loose,
                "bounds": geometryBounds(loose)
            });
        }

        return groups;
    }

    function windowLabel(window) {
        return appsService ? appsService.toplevelLabel(window) : String(window && (window.title || window.appId) ? (window.title || window.appId) : "窗口");
    }

    function windowIcon(window) {
        return appsService ? appsService.iconForToplevel(window) : "";
    }

    function detailText(window) {
        if (!window)
            return "";

        var parts = [];
        var appId = String(window.appId || "").trim();
        if (appId.length > 0)
            parts.push(appId);
        if (window.isMinimized)
            parts.push("已最小化");
        return parts.join(" - ");
    }

    function geometryText(window) {
        var rect = window ? window.geometry : null;
        if (!rect)
            return "几何未知";

        var x = Math.round(Number(rect.x) || 0);
        var y = Math.round(Number(rect.y) || 0);
        var width = Math.round(Number(rect.width || rect.w) || 0);
        var height = Math.round(Number(rect.height || rect.h) || 0);
        return String(x) + "," + String(y) + " " + String(width) + "x" + String(height);
    }

    function previewRect(window, bounds, canvasWidth, canvasHeight) {
        var rect = window ? window.geometry : null;
        if (!rect || !bounds || !bounds.valid)
            return {
                "x": Math.round(canvasWidth * 0.22),
                "y": Math.round(canvasHeight * 0.22),
                "width": Math.round(canvasWidth * 0.56),
                "height": Math.round(canvasHeight * 0.56)
            };

        var pad = 8;
        var width = Math.max(1, Number(rect.width || rect.w) || 1);
        var height = Math.max(1, Number(rect.height || rect.h) || 1);
        var scale = Math.min((canvasWidth - pad * 2) / bounds.width, (canvasHeight - pad * 2) / bounds.height);
        var nextWidth = Math.max(16, Math.round(width * scale));
        var nextHeight = Math.max(12, Math.round(height * scale));
        return {
            "x": Math.round(pad + (Number(rect.x) - bounds.x) * scale),
            "y": Math.round(pad + (Number(rect.y) - bounds.y) * scale),
            "width": Math.min(canvasWidth - pad * 2, nextWidth),
            "height": Math.min(canvasHeight - pad * 2, nextHeight)
        };
    }

    TahoeGlass.regions: [overviewSurface.region]

    Rectangle {
        anchors.fill: parent
        color: "#1a101418"
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closeRequested()
    }

    FocusScope {
        id: focusCatcher

        anchors.fill: parent
        focus: root.open
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.closeRequested();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.activateSelected();
                event.accepted = true;
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                root.cycleSelection(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                root.cycleSelection((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                event.accepted = true;
            }
        }
    }

    Item {
        id: overview

        x: root.panelLeft
        y: root.panelTop
        width: root.panelWidth
        height: root.panelHeight
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.985

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) {
                mouse.accepted = true;
            }
        }

        GlassPanel {
            id: overviewSurface

            anchors.fill: parent
            material: GlassStyle.MaterialPanel
            radius: GlassStyle.RadiusPanel
            fillColor: GlassStyle.FillPanelBright
            strokeColor: GlassStyle.StrokePanelBright
            useItemRegion: false
            regionX: Math.round(overview.x + overviewSurface.x)
            regionY: Math.round(overview.y + overviewSurface.y)
            regionWidth: Math.round(overviewSurface.width)
            regionHeight: Math.round(overviewSurface.height)
            interaction: 0.0
            materialAlpha: overview.opacity
            regionEnabled: root.open || overview.opacity > 0.01
        }

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 22
            anchors.rightMargin: 18
            anchors.topMargin: 16
            height: 34
            spacing: 10

            Text {
                width: parent.width - closeButton.width - 10
                anchors.verticalCenter: parent.verticalCenter
                text: "窗口总览"
                color: "#202124"
                font.pixelSize: 18
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Item {
                id: closeButton

                width: 32
                height: 32

                Rectangle {
                    anchors.fill: parent
                    radius: 16
                    color: closeMouse.containsMouse ? "#5affffff" : "#32ffffff"
                    border.color: "#42ffffff"
                    border.width: 1
                }

                Text {
                    anchors.centerIn: parent
                    text: "\ue5cd"
                    color: "#30343a"
                    font.family: "Material Icons"
                    font.pixelSize: 18
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 23
            anchors.top: parent.top
            anchors.topMargin: 47
            text: String(root.windowChoices.length) + " 个窗口"
            color: "#68717a"
            font.pixelSize: 12
        }

        Flickable {
            id: overviewFlick

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.topMargin: 76
            anchors.bottomMargin: 18
            contentWidth: width
            contentHeight: groupColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            function ensureVisible() {
                var item = root.selectedCardItem;
                if (!item)
                    return;

                var top = item.mapToItem(groupColumn, 0, 0).y - 12;
                var bottom = top + item.height + 24;
                if (top < contentY)
                    contentY = Math.max(0, top);
                else if (bottom > contentY + height)
                    contentY = Math.min(Math.max(0, contentHeight - height), bottom - height);
            }

            Column {
                id: groupColumn
                width: overviewFlick.width
                spacing: 18

                Repeater {
                    model: ScriptModel {
                        values: root.workspaceGroups
                    }

                    delegate: Column {
                        id: groupDelegate

                        required property var modelData

                        width: groupColumn.width
                        spacing: 9

                        Row {
                            width: parent.width
                            height: 22
                            spacing: 8

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: groupDelegate.modelData.title
                                color: "#202124"
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: groupDelegate.modelData.subtitle
                                color: "#68717a"
                                font.pixelSize: 11
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 12

                            Repeater {
                                model: ScriptModel {
                                    values: groupDelegate.modelData.windows
                                }

                                delegate: Item {
                                    id: windowCard

                                    required property var modelData
                                    readonly property bool selected: root.selectedWindowKey === root.windowKey(modelData)
                                    readonly property bool minimized: !!(modelData && modelData.isMinimized)
                                    readonly property string iconSource: root.windowIcon(modelData)
                                    readonly property var miniRect: root.previewRect(modelData, groupDelegate.modelData.bounds, miniMap.width, miniMap.height)

                                    width: Math.max(188, Math.min(236, groupDelegate.width))
                                    height: 164

                                    onSelectedChanged: if (selected) root.selectedCardItem = windowCard

                                    Component.onCompleted: if (selected) root.selectedCardItem = windowCard

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 16
                                        color: windowCard.selected ? "#76ffffff" : cardMouse.containsMouse ? "#44ffffff" : "#24ffffff"
                                        border.color: windowCard.selected ? "#a8ffffff" : "#34ffffff"
                                        border.width: windowCard.selected ? 2 : 1
                                    }

                                    Rectangle {
                                        id: miniMap

                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        anchors.topMargin: 12
                                        height: 70
                                        radius: 12
                                        color: "#1f20242a"
                                        border.color: "#22ffffff"
                                        border.width: 1

                                        Rectangle {
                                            x: windowCard.miniRect.x
                                            y: windowCard.miniRect.y
                                            width: windowCard.miniRect.width
                                            height: windowCard.miniRect.height
                                            radius: 7
                                            color: windowCard.minimized ? "#5f8c929a" : "#8af7fbff"
                                            border.color: windowCard.modelData && windowCard.modelData.isFocused ? "#202124" : "#66ffffff"
                                            border.width: windowCard.modelData && windowCard.modelData.isFocused ? 2 : 1
                                        }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        anchors.top: miniMap.bottom
                                        anchors.topMargin: 12
                                        width: 34
                                        height: 34
                                        radius: 10
                                        color: "#40ffffff"
                                        border.color: "#38ffffff"
                                        border.width: 1
                                    }

                                    Image {
                                        id: appIcon
                                        anchors.left: parent.left
                                        anchors.leftMargin: 19
                                        anchors.top: miniMap.bottom
                                        anchors.topMargin: 17
                                        width: 24
                                        height: 24
                                        source: windowCard.iconSource
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        mipmap: true
                                        opacity: windowCard.minimized ? 0.58 : 1
                                        visible: windowCard.iconSource.length > 0 && status !== Image.Error
                                    }

                                    Text {
                                        anchors.centerIn: appIcon
                                        text: "\ue8d0"
                                        color: "#5a626a"
                                        font.family: "Material Icons"
                                        font.pixelSize: 17
                                        visible: !appIcon.visible
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 56
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        anchors.top: miniMap.bottom
                                        anchors.topMargin: 11
                                        text: root.windowLabel(windowCard.modelData)
                                        color: windowCard.minimized ? "#69727a" : "#202124"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 56
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        anchors.top: miniMap.bottom
                                        anchors.topMargin: 31
                                        text: root.detailText(windowCard.modelData)
                                        color: "#68717a"
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        anchors.right: parent.right
                                        anchors.rightMargin: 14
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 10
                                        text: root.geometryText(windowCard.modelData)
                                        color: "#68717a"
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    MouseArea {
                                        id: cardMouse

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.selectedWindowKey = root.windowKey(windowCard.modelData)
                                        onClicked: root.activateWindow(windowCard.modelData)
                                    }
                                }
                            }

                            Item {
                                width: visible ? parent.width : 0
                                height: visible ? 52 : 0
                                visible: groupDelegate.modelData.windows.length === 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "暂无窗口"
                                    color: "#68717a"
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
