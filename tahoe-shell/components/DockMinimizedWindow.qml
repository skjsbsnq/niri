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
    property var dockScreen: dockWindow && dockWindow.screen !== undefined ? dockWindow.screen : null
    property var dockSurfaceItem
    property real dockSlideOffset: 0
    // Undo the fullscreen transition transform on dockRow (mirror WindowButton)
    // so the hint reports the revealed, not slid-down, position; and suppress
    // republish while the Dock layer is unmapped for fullscreen.
    property real dockFullscreenOffset: 0
    property bool dockFullscreenActive: false
    // S-L8: set after restore() so the dying delegate stops publishing its
    // geometry — the reverse (un-minimize) genie already has the REST rect
    // and a stale / bounce-contaminated report from the destroying delegate
    // would misdirect it. Cleared when a new window is assigned (recycle).
    property bool restoredPending: false
    // T19/S-M3: ancestor scene offset trigger — mapToItem() establishes no
    // binding dependency, so Dock forwards the minimized-section scene offset
    // to refresh the foreign-toplevel hint while the shelf reflows/scrolls.
    property real dockSceneOffsetX: 0
    property real dockSceneOffsetY: 0
    // See Dock.qml useSpring — forwarded so the bounce down leg can use the
    // spring branch off software GPUs.
    property bool useSpring: false
    property int thumbnailMaxWidth: 320
    property int thumbnailMaxHeight: 220
    // Logical→physical scale for Image sourceSize / capture budgets.
    readonly property real screenScale: {
        var dpr = Number(root.dockWindow && root.dockWindow.devicePixelRatio);
        if (!isFinite(dpr) || dpr <= 0)
            dpr = Number(root.dockScreen && root.dockScreen.devicePixelRatio);
        if (!isFinite(dpr) || dpr <= 0)
            dpr = 1;
        return dpr;
    }
    readonly property int thumbnailCaptureWidth: Math.max(root.thumbnailMaxWidth, Math.ceil(root.width * root.screenScale))
    readonly property int thumbnailCaptureHeight: Math.max(root.thumbnailMaxHeight, Math.ceil(root.height * root.screenScale))
    property real bounceOffset: 0
    property real lifecycleOpacity: 1
    property real lifecycleScale: 1
    property real pressScale: Motion.pressScaleFor(root.settingsService, thumbnailMouse.pressed)
    property real pressOpacity: thumbnailMouse.pressed ? 0.75 : 1
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
    scale: lifecycleScale * pressScale
    opacity: lifecycleOpacity * pressOpacity

    Behavior on pressScale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
    Behavior on pressOpacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

    function scheduleThumbnailRefresh() {
        refreshTimer.restart();
    }

    // Fall back to the steady preview geometry (root 112×62, frame margins 2)
    // so a 0×0 pre-layout bind does not decode a 1×1 placeholder.
    function thumbnailSourceSize(itemWidth, itemHeight) {
        var iw = Number(itemWidth);
        var ih = Number(itemHeight);
        if (!isFinite(iw) || iw < 2)
            iw = Math.max(1, root.width - 4);
        if (!isFinite(ih) || ih < 2)
            ih = Math.max(1, root.height - 4);
        if (iw < 2)
            iw = 108;
        if (ih < 2)
            ih = 58;
        var w = Math.max(1, Math.ceil(iw * root.screenScale));
        var h = Math.max(1, Math.ceil(ih * root.screenScale));
        return Qt.size(w, h);
    }

    function iconSourceSize(itemWidth, itemHeight) {
        var scale = Math.max(2, root.screenScale * 2);
        var w = Math.max(64, Math.min(128, Math.ceil(Number(itemWidth) * scale)));
        var h = Math.max(64, Math.min(128, Math.ceil(Number(itemHeight) * scale)));
        return Qt.size(w, h);
    }

    function refreshThumbnail() {
        if (!root.hasWindowId || !root.thumbnailProvider)
            return;

        root.thumbnailProvider.requestThumbnail(
            root.windowModel,
            root.thumbnailCaptureWidth,
            root.thumbnailCaptureHeight,
            "dock-minimized",
            false
        );
    }

    // Mirror WindowButton: suppress foreign-toplevel rectangle republish while
    // the Dock layer is unmapped for fullscreen (publishing into a closing game
    // handle raced Quickshell on unmap), and republish once fullscreen clears.
    function dockRectanglePublishBlocked() {
        return root.dockFullscreenActive;
    }

    function updateDockRectangle(forcePublish) {
        // S-L8: after restore the delegate is being destroyed; its geometry
        // changes are stale / bounce-contaminated and must not reach niri
        // while the reverse genie is in flight. restoreWindow publishes the
        // REST rect before this flag goes true.
        if (root.restoredPending)
            return;
        if (!root.dockWindow || !root.windowsService || !root.windowsService.submitDockRectangle)
            return;
        var toplevel = root.windowModel ? root.windowModel.toplevel : null;
        if (!toplevel)
            return;
        if (!forcePublish && root.dockRectanglePublishBlocked())
            return;
        // Interactive restore may run mid-reveal: never publish into a still-
        // unmapped fullscreen Dock (compositor has no layer surface).
        if (forcePublish && root.dockFullscreenActive)
            return;

        // T19 (S-M8): report REST geometry. Mapping previewFrame directly would
        // inherit root.scale (lifecycleScale*pressScale) and the bounce
        // Translate, so a quick minimize→restore cached a source rect shrunk
        // by the add-transition/press scale. Map from root.parent (the ListView
        // contentItem — no scale) using the delegate's rest frame (previewFrame
        // margins) at scale 1, with no bounce; keep the autohide slide undo so
        // the hint refers to the revealed, not off-screen, position.
        var p = root.parent;
        if (!p)
            return;
        var restX = root.x + 2;
        var restY = root.y + 2;
        var restW = root.width - 4;
        var restH = root.height - 4;
        var topLeft = p.mapToItem(null, restX, restY);
        var bottomRight = p.mapToItem(null, restX + restW, restY + restH);
        var left = Math.floor(Math.min(topLeft.x, bottomRight.x));
        var top = Math.floor(Math.min(topLeft.y, bottomRight.y) - root.dockSlideOffset - root.dockFullscreenOffset);
        var right = Math.ceil(Math.max(topLeft.x, bottomRight.x));
        var bottom = Math.ceil(Math.max(topLeft.y, bottomRight.y) - root.dockSlideOffset - root.dockFullscreenOffset);
        root.windowsService.submitDockRectangle(
            toplevel,
            root.dockWindow,
            root.dockScreen,
            left,
            top,
            Math.max(1, right - left),
            Math.max(1, bottom - top),
            { "force": !!forcePublish }
        );
    }

    function scheduleDockRectangleUpdate() {
        if (root.dockRectanglePublishBlocked())
            return;
        dockRectangleRefresh.restart();
        // T21: debounce a force-publish after the shelf/ancestor Behavior (move/
        // resize transitions) settles (interval = Motion.elementResize, the
        // longest layout-Behavior duration) so the settled geometry reaches
        // niri for a T-20 retarget.
        dockRectangleSettle.restart();
    }

    function restoreWindow() {
        if (!root.windowModel || !root.windowsService)
            return;

        root.updateDockRectangle(true);
        root.windowsService.restore(root.windowModel);
        root.activated(root.windowModel);
        // S-L8: the REST rect is published above; from here the delegate is
        // being destroyed, so suppress further reports (the dying-delegate
        // geometry churn would otherwise pollute the reverse genie hint) and
        // skip the click bounce, which would be truncated mid-flight.
        root.restoredPending = true;
    }

    // Click bounce (R01 #74): animated InQuad up leg, dual-branch spring/ease
    // down leg — same physics as Dock icons / WindowButton, shorter height
    // because the thumbnail shelf has less vertical travel.
    function bounce() {
        bounceSpring.stop();
        bounceEase.stop();
        bounceUp.stop();
        if (Motion.reducedMotion(root.settingsService)) {
            // Single hop: instant up, eased settle.
            root.bounceOffset = Motion.dockClickBounceShelfHeightPx;
            bounceEase.to = 0;
            bounceEase.restart();
            return;
        }
        bounceUp.restart();
    }
    function animateBounceTo(value) {
        if (root.useSpring) {
            bounceSpring.to = value;
            bounceSpring.restart();
        } else {
            bounceEase.to = value;
            bounceEase.restart();
        }
    }

    onWindowModelChanged: {
        // S-L8: a new window assigned to a recycled delegate means it is alive
        // again — clear the post-restore publish suppressor before the
        // scheduled report below.
        root.restoredPending = false;
        scheduleThumbnailRefresh();
        scheduleDockRectangleUpdate();
    }
    onThumbnailProviderChanged: scheduleThumbnailRefresh()
    onDockWindowChanged: scheduleDockRectangleUpdate()
    onDockScreenChanged: scheduleDockRectangleUpdate()
    onXChanged: scheduleDockRectangleUpdate()
    onYChanged: scheduleDockRectangleUpdate()
    onWidthChanged: scheduleDockRectangleUpdate()
    onHeightChanged: scheduleDockRectangleUpdate()
    onDockSlideOffsetChanged: scheduleDockRectangleUpdate()
    // T19: bounce is a visual-only transform excluded from the REST-geometry
    // hint (see updateDockRectangle); it no longer triggers a re-publish.
    onDockSceneOffsetXChanged: scheduleDockRectangleUpdate()
    onDockSceneOffsetYChanged: scheduleDockRectangleUpdate()
    // Undo the fullscreen slide mid-transition so the hint tracks the revealed
    // position; after fullscreen clears, republish immediately even if the
    // reveal slide still runs (niri cleared rects on unmap and restore needs
    // them). While fullscreenActive, schedule is blocked above.
    onDockFullscreenOffsetChanged: scheduleDockRectangleUpdate()
    onDockFullscreenActiveChanged: {
        // niri wipes foreign-toplevel rects when the Dock layer unmaps for
        // fullscreen; drop the wire-dedup cache so the post-remap republish of
        // identical coordinates is not suppressed as "unchanged".
        if (root.windowsService && root.windowsService.invalidateDockRectanglePublish)
            root.windowsService.invalidateDockRectanglePublish(
                root.windowModel ? root.windowModel.toplevel : null);
        if (!root.dockFullscreenActive) {
            scheduleDockRectangleUpdate();
            // One force publish a beat after the layer remaps, NOT debounced by
            // layout churn: niri may store the first post-remap report as
            // Unresolved (source layer not mapped yet) and the wire-dedup gate
            // would suppress identical retries. Floor 32ms (~2 frames at 60Hz)
            // covers the layer remap commit in reduced-motion profiles where
            // Motion.elementResize is 0.
            dockRectangleRemapForce.restart();
        }
    }
    Component.onCompleted: {
        scheduleThumbnailRefresh();
        scheduleDockRectangleUpdate();
    }

    Connections {
        target: root.windowModel && root.windowModel.toplevel ? root.windowModel.toplevel : null
        function onScreensChanged() {
            root.scheduleDockRectangleUpdate();
        }
    }

    Timer {
        id: refreshTimer
        interval: 40
        repeat: false
        onTriggered: root.refreshThumbnail()
    }

    Timer {
        id: dockRectangleRefresh
        interval: 0
        repeat: false
        onTriggered: root.updateDockRectangle(false)
    }

    // T21: force-publish once more after the shelf/ancestor Behavior (move/resize
    // transitions) settles. interval = Motion.elementResize, the longest
    // layout-Behavior duration (>= elementMove), so it fires once all of them
    // settle. The interval-0 dockRectangleRefresh reports per-frame; this
    // guarantees the settled value reaches niri (T-20 retarget) even if the last
    // per-frame report landed mid-Behavior. Debounced via restart on each schedule.
    Timer {
        id: dockRectangleSettle
        interval: Motion.elementResize(root.settingsService)
        repeat: false
        onTriggered: root.updateDockRectangle(true)
    }

    // R04-dedup hardening (see onDockFullscreenActiveChanged). Single-shot;
    // never restarted by scheduleDockRectangleUpdate, so layout churn cannot
    // starve it. Post-restore suppression (restoredPending) makes it a no-op
    // if the delegate is dying when it fires.
    Timer {
        id: dockRectangleRemapForce
        interval: Math.max(Motion.elementResize(root.settingsService), 32)
        repeat: false
        onTriggered: root.updateDockRectangle(true)
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

        Behavior on color {
            ColorAnimation { duration: Motion.fadeFast(root.settingsService) }
        }

        Behavior on border.color {
            ColorAnimation { duration: Motion.fadeFast(root.settingsService) }
        }

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
            // Bust via ?v=generation on thumbnailSource; keep cache across dock
            // hover revisits so the same PNG is not re-decoded every time.
            cache: true
            sourceSize: root.thumbnailSourceSize(width, height)
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
                sourceSize: root.iconSourceSize(width, height)
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
            NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.emphasizedDecel }
        }

        Behavior on y {
            NumberAnimation { duration: Motion.elementMove(root.settingsService); easing.type: Motion.emphasizedDecel }
        }
    }

    MouseArea {
        id: thumbnailMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) {
            // dockSurface-local (PanelWindow is not a QQuickItem — T08-fix6).
            var target = root.dockSurfaceItem;
            if (target) {
                var point = root.mapToItem(target, mouse.x, mouse.y);
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
                // S-L8: no bounce on restore — the delegate is being destroyed
                // so the bounce would be truncated mid-flight (a dying-delegate
                // visual glitch); restoredPending separately suppresses the
                // geometry churn that would pollute the reverse genie hint.
                root.restoreWindow();
            }
        }
    }

    NumberAnimation {
        id: bounceUp
        target: root
        property: "bounceOffset"
        to: Motion.dockClickBounceShelfHeightPx
        duration: Motion.dockClickBounceUpMs
        easing.type: Easing.InQuad
        onFinished: root.animateBounceTo(0)
    }
    SpringAnimation {
        id: bounceSpring
        target: root
        property: "bounceOffset"
        spring: Motion.springBouncy.spring
        damping: Motion.springBouncy.damping
        epsilon: 0.01
    }
    NumberAnimation {
        id: bounceEase
        target: root
        property: "bounceOffset"
        duration: Motion.dockClickBounceDownMs
        easing.type: Motion.emphasizedDecel
    }
}
