pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "Motion.js" as Motion
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property bool open: false
    property var windowsService
    property var thumbnailProvider
    property var appsService
    property var settingsService
    property int selectedIndex: 0
    property string selectedWindowKey: ""
    property bool keyboardMode: false
    readonly property var windowChoices: windowsService && windowsService.recentWindowList ? windowsService.recentWindowList : []
    readonly property int screenWidth: Math.max(1, numberOr(root.screen && root.screen.width, root.width))
    readonly property int screenHeight: Math.max(1, numberOr(root.screen && root.screen.height, root.height))
    readonly property int panelWidth: Math.max(300, Math.min(screenWidth - 32, Math.max(360, Math.min(820, windowChoices.length * 150 + 46))))
    readonly property int panelHeight: 190
    readonly property int panelLeft: Math.round(Math.max(8, (screenWidth - panelWidth) / 2))
    readonly property int panelTop: Math.round(Math.max(48, Math.min(screenHeight - panelHeight - 48, screenHeight * 0.34)))

    signal closeRequested()

    visible: open || switcher.opacity > 0.01
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    focusable: open
    implicitWidth: screenWidth
    implicitHeight: screenHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "tahoe-task-switcher"

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    onOpenChanged: {
        if (open) {
            if (windowChoices.length === 0) {
                closeRequested();
                return;
            }

            selectedIndex = focusedIndex();
            selectedWindowKey = windowKey(currentWindow());
            requestVisibleThumbnails(false);
            Qt.callLater(function() {
                if (root.open)
                    focusCatcher.forceActiveFocus();
            });
        } else {
            keyboardMode = false;
        }
    }

    onWindowChoicesChanged: if (open) {
        syncSelectionAfterModelChange();
        requestVisibleThumbnails(false);
    }

    onSelectedIndexChanged: {
        selectedWindowKey = windowKey(currentWindow());
        Qt.callLater(function() {
            if (windowListView.count > 0)
                windowListView.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        });
    }

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

    function currentWindow() {
        if (!windowChoices || windowChoices.length === 0)
            return null;
        var index = normalizeIndex(selectedIndex);
        return windowChoices[index] || null;
    }

    function normalizeIndex(index) {
        var count = windowChoices ? windowChoices.length : 0;
        if (count <= 0)
            return 0;
        var next = Number(index) || 0;
        next = next % count;
        if (next < 0)
            next += count;
        return next;
    }

    function selectedIndexForKey(key) {
        var needle = String(key || "");
        if (needle.length === 0)
            return -1;
        for (var i = 0; i < windowChoices.length; i++) {
            if (windowKey(windowChoices[i]) === needle)
                return i;
        }
        return -1;
    }

    function focusedIndex() {
        for (var i = 0; i < windowChoices.length; i++) {
            if (windowChoices[i] && windowChoices[i].isFocused)
                return i;
        }
        return 0;
    }

    function initialIndex(direction) {
        if (windowChoices.length <= 1)
            return 0;
        if (direction < 0)
            return windowChoices.length - 1;
        if (direction > 0)
            return 1;
        return focusedIndex();
    }

    function syncSelectionAfterModelChange() {
        if (!windowChoices || windowChoices.length === 0) {
            closeRequested();
            return;
        }

        var existing = selectedIndexForKey(selectedWindowKey);
        if (existing >= 0) {
            selectedIndex = existing;
            return;
        }

        selectedIndex = normalizeIndex(selectedIndex);
        selectedWindowKey = windowKey(currentWindow());
    }

    function cycle(direction) {
        if (!windowChoices || windowChoices.length === 0)
            return;
        if (direction === 0)
            return;
        selectedIndex = normalizeIndex(selectedIndex + (direction < 0 ? -1 : 1));
    }

    function cycleFromKeyboard(direction) {
        if (!windowChoices || windowChoices.length === 0)
            return;

        keyboardMode = true;
        if (!open)
            selectedIndex = initialIndex(direction);
        else if (direction !== 0)
            cycle(direction);

        selectedWindowKey = windowKey(currentWindow());
        Qt.callLater(function() {
            if (root.open)
                focusCatcher.forceActiveFocus();
        });
    }

    function chooseIndex(index) {
        selectedIndex = normalizeIndex(index);
        confirm();
    }

    function confirm() {
        var window = currentWindow();
        if (window && windowsService) {
            if (window.isMinimized)
                windowsService.restore(window);
            else
                windowsService.activate(window);
        }
        closeRequested();
    }

    function cancel() {
        closeRequested();
    }

    function isSwitcherModifierRelease(event) {
        return event.key === Qt.Key_Alt
            || event.key === Qt.Key_Control
            || event.key === Qt.Key_Meta;
    }

    function hasSwitcherModifier(modifiers) {
        return !!(modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier));
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
        if (windowsService && window.workspace)
            parts.push(windowsService.workspaceDisplayLabel(window.workspace, 0));
        var output = String(window.output || "").trim();
        if (output.length > 0)
            parts.push(output);
        if (window.isMinimized)
            parts.push("已最小化");
        return parts.join(" - ");
    }

    function requestThumbnailFor(window, force) {
        if (!root.thumbnailProvider || !window)
            return;
        root.thumbnailProvider.requestThumbnail(window, 360, 220, "task-switcher", !!force);
    }

    function requestVisibleThumbnails(force) {
        if (!root.thumbnailProvider)
            return;
        root.thumbnailProvider.requestThumbnails(root.windowChoices, 360, 220, "task-switcher", !!force);
    }

    Timer {
        id: releaseConfirmTimer
        interval: 40
        repeat: false
        onTriggered: {
            if (root.open && root.keyboardMode)
                root.confirm();
        }
    }

    TahoeGlass.regions: [switcherSurface.region]

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.cancel()
    }

    FocusScope {
        id: focusCatcher

        anchors.fill: parent
        focus: root.open
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                root.cycle((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                root.cycle(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                root.cycle(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.confirm();
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                root.cancel();
                event.accepted = true;
            }
        }
        Keys.onReleased: function(event) {
            if (root.keyboardMode && root.isSwitcherModifierRelease(event) && !root.hasSwitcherModifier(event.modifiers)) {
                releaseConfirmTimer.restart();
                event.accepted = true;
            }
        }
    }

    Item {
        id: switcher

        x: root.panelLeft
        y: root.panelTop
        width: root.panelWidth
        height: root.panelHeight
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.98

        Behavior on opacity {
            NumberAnimation { duration: Motion.elementMove(root.settingsService); easing.type: Motion.emphasizedDecel }
        }

        Behavior on scale {
            NumberAnimation { duration: Motion.menuEnter(root.settingsService); easing.type: Motion.emphasizedDecel }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) {
                mouse.accepted = true;
            }
        }

        GlassPanel {
            id: switcherSurface

            anchors.fill: parent
            material: GlassStyle.MaterialMenu
            radius: GlassStyle.RadiusMenu
            fillColor: GlassStyle.FillPanelBright
            strokeColor: GlassStyle.StrokePanelBright
            useItemRegion: false
            regionX: Math.round(switcher.x + switcherSurface.x)
            regionY: Math.round(switcher.y + switcherSurface.y)
            regionWidth: Math.round(switcherSurface.width)
            regionHeight: Math.round(switcherSurface.height)
            interaction: switcher.opacity
            materialAlpha: switcher.opacity
            regionEnabled: root.open || switcher.opacity > 0.01
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.top: parent.top
            anchors.topMargin: 13
            text: "窗口切换"
            color: "#202124"
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.top: parent.top
            anchors.topMargin: 13
            text: String(root.windowChoices.length) + " 个窗口"
            color: "#68717a"
            font.pixelSize: 12
        }

        ListView {
            id: windowListView

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 42
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            orientation: ListView.Horizontal
            spacing: 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: root.selectedIndex
            model: ScriptModel {
                values: root.windowChoices
            }

            delegate: Item {
                id: windowItem

                required property var modelData
                required property int index
                readonly property bool selected: index === root.selectedIndex
                readonly property bool minimized: !!(modelData && modelData.isMinimized)
                readonly property string iconSource: root.windowIcon(modelData)
                readonly property int thumbnailRevision: root.thumbnailProvider ? root.thumbnailProvider.revision : 0
                readonly property var thumbnailState: root.thumbnailProvider ? root.thumbnailProvider.thumbnailStateForWindow(modelData, thumbnailRevision) : null
                readonly property bool thumbnailAvailable: !!(thumbnailState && thumbnailState.ready && !thumbnailState.failed)
                readonly property string thumbnailSource: thumbnailAvailable && thumbnailState.path
                    ? "file://" + String(thumbnailState.path) + "?v=" + String(thumbnailState.generation || 0)
                    : ""

                width: 138
                height: windowListView.height

                onModelDataChanged: if (root.open) root.requestThumbnailFor(modelData, false)
                Component.onCompleted: if (root.open) root.requestThumbnailFor(modelData, false)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 16
                    color: windowItem.selected ? "#76ffffff" : cardMouse.containsMouse ? "#44ffffff" : "#24ffffff"
                    border.color: windowItem.selected ? "#a8ffffff" : "#34ffffff"
                    border.width: windowItem.selected ? 2 : 1
                }

                Rectangle {
                    id: previewFrame

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    width: 116
                    height: 66
                    radius: 13
                    color: windowItem.minimized ? "#26ffffff" : "#42ffffff"
                    border.color: "#42ffffff"
                    border.width: 1
                    clip: true

                    Image {
                        id: thumbnailImage

                        anchors.fill: parent
                        source: windowItem.thumbnailSource
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        cache: false
                        opacity: windowItem.minimized ? 0.62 : 1
                        visible: windowItem.thumbnailSource.length > 0 && status !== Image.Error
                        onStatusChanged: {
                            if (status === Image.Error && windowItem.thumbnailAvailable && root.thumbnailProvider)
                                root.thumbnailProvider.markImageFailed(windowItem.modelData, "task switcher thumbnail image failed to load");
                        }
                    }

                    WindowPreviewFallback {
                        anchors.fill: parent
                        iconSource: windowItem.iconSource
                        minimized: windowItem.minimized
                        iconSize: 38
                        visible: !thumbnailImage.visible
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 5
                        width: 24
                        height: 24
                        radius: 7
                        color: "#e8ffffff"
                        border.color: "#70ffffff"
                        border.width: 1
                        visible: thumbnailImage.visible && windowItem.iconSource.length > 0

                        Image {
                            anchors.centerIn: parent
                            width: 17
                            height: 17
                            source: windowItem.iconSource
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            asynchronous: true
                        }
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 84
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    text: root.windowLabel(windowItem.modelData)
                    color: windowItem.minimized ? "#69727a" : "#202124"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 105
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    text: root.detailText(windowItem.modelData)
                    color: "#68717a"
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 11
                    width: windowItem.modelData && windowItem.modelData.isFocused ? 24 : windowItem.minimized ? 5 : 8
                    height: 4
                    radius: 2
                    color: windowItem.modelData && windowItem.modelData.isFocused ? "#202124" : windowItem.minimized ? "#8a929a" : "#6c747c"
                }

                MouseArea {
                    id: cardMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selectedIndex = windowItem.index
                    onClicked: root.chooseIndex(windowItem.index)
                }
            }
        }
    }
}
