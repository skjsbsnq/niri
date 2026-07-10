pragma ComponentBehavior: Bound

import QtQuick
import "Motion.js" as Motion

Item {
    id: root

    property var windowModel: null
    property var windowsService
    property var thumbnailProvider
    property var appsService
    property var settingsService
    property var dockWindow
    property var dockSurfaceItem
    property real dockSlideOffset: 0
    property int thumbnailMaxWidth: 320
    property int thumbnailMaxHeight: 220
    property real bounceOffset: 0
    readonly property bool hasWindowId: windowModel && windowModel.id !== undefined && windowModel.id !== null
    readonly property int thumbnailProviderRevision: thumbnailProvider ? thumbnailProvider.revision : 0
    readonly property var thumbnailState: thumbnailProvider ? thumbnailProvider.thumbnailStateForWindow(windowModel, thumbnailProviderRevision) : null
    readonly property bool thumbnailReady: !!(thumbnailState && thumbnailState.ready)
    readonly property bool thumbnailFailed: !!(thumbnailState && thumbnailState.failed)
    readonly property int thumbnailGeneration: thumbnailState ? Number(thumbnailState.generation || 0) : 0
    readonly property string thumbnailPath: thumbnailState ? String(thumbnailState.path || "") : ""
    readonly property string thumbnailSource: thumbnailReady && thumbnailPath.length > 0
        ? "file://" + thumbnailPath + "?v=" + String(thumbnailGeneration)
        : ""
    readonly property string windowLabel: appsService
        ? appsService.toplevelLabel(windowModel)
        : String(windowModel ? windowModel.title || windowModel.appId || "窗口" : "窗口")
    readonly property string windowIcon: appsService ? appsService.iconForToplevel(windowModel) : ""
    readonly property bool hovered: thumbnailMouse.containsMouse
    readonly property bool showFallback: !thumbnailReady || thumbnailFailed || thumbnailImage.status !== Image.Ready

    signal activated(var window)
    signal contextMenuRequested(var window, var anchorItem)
    signal dockPointerMoved(real x, int buttons)
    signal dockPointerEntered()
    signal dockPointerExited()

    width: 112
    height: 62
    scale: Motion.pressScaleFor(root.settingsService, thumbnailMouse.pressed)
    opacity: thumbnailMouse.pressed ? 0.75 : 1

    Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
    Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

    function scheduleThumbnailRefresh() {
        refreshTimer.restart();
    }

    function refreshThumbnail() {
        if (!root.hasWindowId || !root.thumbnailProvider)
            return;

        root.thumbnailProvider.requestThumbnail(
            root.windowModel,
            root.thumbnailMaxWidth,
            root.thumbnailMaxHeight,
            "dock-minimized",
            false
        );
    }

    function updateDockRectangle() {
        if (!root.dockWindow || !root.windowsService || !root.windowModel)
            return;

        // Report the visible preview at its stable, fully revealed Dock
        // position. Autohide translates the whole Dock, and the click bounce
        // translates the preview, neither of which belongs in the restore
        // destination cached by foreign-toplevel.
        var topLeft = previewFrame.mapToItem(null, 0, 0);
        var bottomRight = previewFrame.mapToItem(null, previewFrame.width, previewFrame.height);
        var left = Math.floor(Math.min(topLeft.x, bottomRight.x));
        var top = Math.floor(Math.min(topLeft.y, bottomRight.y) - root.dockSlideOffset + root.bounceOffset);
        var right = Math.ceil(Math.max(topLeft.x, bottomRight.x));
        var bottom = Math.ceil(Math.max(topLeft.y, bottomRight.y) - root.dockSlideOffset + root.bounceOffset);
        root.windowsService.setRectangle(
            root.windowModel,
            root.dockWindow,
            left,
            top,
            Math.max(1, right - left),
            Math.max(1, bottom - top)
        );
    }

    function restoreWindow() {
        if (!root.windowModel || !root.windowsService)
            return;

        root.updateDockRectangle();
        root.windowsService.restore(root.windowModel);
        root.activated(root.windowModel);
    }

    function bounce() {
        root.bounceOffset = 8;
        bounceTimer.restart();
    }

    onWindowModelChanged: scheduleThumbnailRefresh()
    onThumbnailProviderChanged: scheduleThumbnailRefresh()
    Component.onCompleted: scheduleThumbnailRefresh()

    Timer {
        id: refreshTimer
        interval: 40
        repeat: false
        onTriggered: root.refreshThumbnail()
    }

    Rectangle {
        id: previewFrame

        anchors.fill: parent
        anchors.margins: 2
        radius: 8
        color: root.hovered ? "#42ffffff" : "#2bffffff"
        border.color: root.hovered ? "#80ffffff" : "#3fffffff"
        border.width: 1
        clip: true
        transform: Translate {
            y: -root.bounceOffset
        }

        Image {
            id: thumbnailImage

            anchors.fill: parent
            source: root.thumbnailSource
            fillMode: Image.PreserveAspectCrop
            smooth: true
            mipmap: true
            asynchronous: true
            cache: false
            visible: !root.showFallback
            onStatusChanged: {
                if (status === Image.Error && root.thumbnailReady && root.thumbnailProvider)
                    root.thumbnailProvider.markImageFailed(root.windowModel, "dock thumbnail image failed to load");
            }
        }

        WindowPreviewFallback {
            anchors.fill: parent
            visible: root.showFallback
            backgroundColor: "#f2f4f7"
            iconSource: root.windowIcon
            title: root.windowLabel
            iconSize: 28
            showTitle: true
            titlePixelSize: 10
            titleBottomMargin: 7
        }

        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 5
            width: 24
            height: 24
            radius: 7
            color: "#e8ffffff"
            border.color: "#80ffffff"
            border.width: 1

            Image {
                anchors.centerIn: parent
                width: 18
                height: 18
                source: root.windowIcon
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                asynchronous: true
            }
        }
    }

    Rectangle {
        id: hoverLabel

        anchors.horizontalCenter: parent.horizontalCenter
        z: 10
        y: root.hovered ? -28 : -18
        width: Math.max(hoverLabelText.implicitWidth + 18, 52)
        height: 24
        radius: 7
        color: "#d9f7f8fb"
        border.color: "#70ffffff"
        opacity: root.hovered ? 1 : 0
        visible: opacity > 0.01

        Text {
            id: hoverLabelText

            anchors.centerIn: parent
            width: parent.width - 12
            text: root.windowLabel
            color: "#202124"
            font.pixelSize: 11
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: Text.AlignHCenter
        }

        Behavior on opacity {
            NumberAnimation { duration: Motion.panelExit(root.settingsService); easing.type: Motion.emphasizedDecel }
        }

        Behavior on y {
            NumberAnimation { duration: Motion.panelExit(root.settingsService); easing.type: Motion.emphasizedDecel }
        }
    }

    MouseArea {
        id: thumbnailMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) {
            if (root.dockSurfaceItem) {
                var point = root.mapToItem(root.dockSurfaceItem, mouse.x, mouse.y);
                root.dockPointerMoved(point.x, mouse.buttons);
            }
        }
        onEntered: root.dockPointerEntered()
        onExited: root.dockPointerExited()
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                root.bounce();
                root.contextMenuRequested(root.windowModel, root);
            } else {
                root.restoreWindow();
                root.bounce();
            }
        }
    }

    Timer {
        id: bounceTimer
        interval: 16
        repeat: false
        onTriggered: root.bounceOffset = 0
    }

    // Local exception: minimized-thumbnail bounce is shorter than the dock icon
    // fallback because the thumbnail shelf has less vertical travel.
    Behavior on bounceOffset {
        NumberAnimation { duration: 170; easing.type: Motion.emphasizedDecel }
    }
}
