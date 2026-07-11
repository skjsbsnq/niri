pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "Motion.js" as Motion
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property var appsService
    property var niriService
    property var thumbnailProvider
    property var settingsService
    property bool launchpadOpen: false
    // See shell.qml useSpring. Spring on Image geometry corrupts textures on
    // VMware/software GPUs; NumberAnimation is safe. Default false.
    property bool useSpring: false
    property bool darkMode: false
    property bool menuOpen: false
    property real dockMouseX: -10000
    property bool dockHovered: false
    property bool pointerDragActive: false
    property int dragTargetVisualIndex: -1
    property var hoveredWindowButton: null
    // Unified hover label (T07): one capsule for pinned / window / tool.
    property string dockHoverLabelText: ""
    property real dockHoverLabelCenterX: 0
    property real dockHoverLabelY: -28
    property bool dockHoverLabelVisible: false
    readonly property bool dockMinimizedShelfEnabled: !!(settingsService && settingsService.dockMinimizedShelfEnabled)
    readonly property var dockWindowList: root.niriService
        ? (root.dockMinimizedShelfEnabled && root.niriService.nonMinimizedWindowList
            ? root.niriService.nonMinimizedWindowList
            : root.niriService.windowList || [])
        : []
    readonly property var dockMinimizedWindowList: root.dockMinimizedShelfEnabled && root.niriService && root.niriService.minimizedWindowList ? root.niriService.minimizedWindowList : []
    readonly property bool hasWindows: niriService && niriService.windowList && niriService.windowList.length > 0
    readonly property bool hasNonMinimizedWindows: dockWindowList.length > 0
    readonly property bool hasMinimizedWindows: dockMinimizedWindowList.length > 0
    readonly property bool hasDockWindowSection: hasNonMinimizedWindows || hasMinimizedWindows
    readonly property bool dockAutoHide: settingsService && settingsService.dockAutoHide
    readonly property int dockHideDelay: settingsService ? settingsService.dockAutoHideDelayMs : 260
    readonly property int dockRevealZoneHeight: settingsService ? settingsService.dockRevealZoneHeight : 8
    readonly property bool dockHidden: dockAutoHide && !dockHovered && !pointerDragActive && !launchpadOpen && !menuOpen
    property bool dockVisualHidden: dockHidden
    property bool dockGlassActive: !dockHidden
    // Writable; animated toward dockSlideTarget via springSmooth / ease dual branch (T08).
    property real dockSlideOffset: 0
    // T08-fix: slide at least the full surface height so the panel never leaves a
    // residual strip at the bottom (surface grew to 96 while token stayed 88).
    readonly property real dockSlideDistance: Math.max(Motion.dockAutohideSlidePx, dockSurfaceHeight)
    readonly property real dockSlideTarget: dockVisualHidden ? dockSlideDistance : 0
    readonly property real dockVisibleAmount: 1 - Math.min(1, Math.max(0, dockSlideOffset / Math.max(1, dockSlideDistance)))
    readonly property real dockGlassInteraction: dockHovered ? dockVisibleAmount : 0.0
    readonly property real dockVisibleHeight: Math.max(0, Math.min(dockSurface.height, dockSurface.height - dockSlideOffset))
    // T08-fix: icon base 56→48 after hand-test (T07 56 felt oversized with peak mag).
    readonly property int dockIconSize: 48
    readonly property int dockOuterMargin: 28
    readonly property int dockSurfacePadding: 32
    readonly property int dockItemSpacing: 8
    readonly property int dockPinnedButtonWidth: 64
    readonly property int dockWindowTitleWidth: 132
    readonly property int dockWindowIconWidth: 60
    readonly property int dockMinimizedThumbnailWidth: 112
    readonly property int dockMinimizedMinimumWidth: 76
    readonly property int dockToolButtonWidth: 56
    readonly property int dockSeparatorWidth: 1
    readonly property int dockIconSourceSize: 128
    readonly property int dockToolIconSourceSize: 96
    readonly property int dockSurfaceHeight: 84
    readonly property int dockPinnedRowHeight: 70
    readonly property int dockWindowRowHeight: 60
    // T08-fix3: scale from icon bottom (macOS). Mag-based lift is no longer
    // needed — center-origin + lift was what left icons floating mid-air.
    readonly property real dockLiftFactor: 0
    readonly property int dockSurfaceMaxWidth: Math.max(1, root.width - dockOuterMargin)
    readonly property int dockContentMaxWidth: Math.max(1, dockSurfaceMaxWidth - dockSurfacePadding)
    readonly property int pinnedAppCount: root.appsService && root.appsService.pinnedApps ? root.appsService.pinnedApps.length : 0
    readonly property int windowButtonCount: dockWindowList.length
    readonly property int minimizedWindowButtonCount: dockMinimizedWindowList.length
    readonly property int pinnedContentWidth: seriesWidth(pinnedAppCount, dockPinnedButtonWidth)
    readonly property int titledWindowContentWidth: seriesWidth(windowButtonCount, dockWindowTitleWidth)
    readonly property int iconWindowContentWidth: seriesWidth(windowButtonCount, dockWindowIconWidth)
    readonly property int minimizedWindowContentWidth: seriesWidth(minimizedWindowButtonCount, dockMinimizedThumbnailWidth)
    readonly property int dockRowChildCount: 4 + (hasDockWindowSection ? 1 : 0) + (hasNonMinimizedWindows ? 1 : 0) + (hasMinimizedWindows ? 1 : 0)
    readonly property int dockRowSpacingWidth: Math.max(0, dockRowChildCount - 1) * dockItemSpacing
    readonly property int dockRightToolsWidth: dockSeparatorWidth + dockToolButtonWidth * 2
    readonly property int dockWindowDividerWidth: hasDockWindowSection ? dockSeparatorWidth : 0
    readonly property int dockFlexibleSectionsBudget: Math.max(0, dockContentMaxWidth - dockRightToolsWidth - dockWindowDividerWidth - dockRowSpacingWidth)
    readonly property int minimumWindowViewportWidth: hasNonMinimizedWindows ? Math.min(iconWindowContentWidth, dockWindowIconWidth) : 0
    readonly property int minimumMinimizedViewportWidth: hasMinimizedWindows ? Math.min(minimizedWindowContentWidth, dockMinimizedMinimumWidth) : 0
    readonly property int pinnedViewportWidth: hasNonMinimizedWindows || hasMinimizedWindows
        ? Math.min(pinnedContentWidth, Math.max(0, dockFlexibleSectionsBudget - minimumWindowViewportWidth - minimumMinimizedViewportWidth))
        : Math.min(pinnedContentWidth, dockFlexibleSectionsBudget)
    // T08-fix4: outer section widths stay at REST size so the glass bar does not
    // grow/shrink under the cursor (that feedback loop made the whole dock jitter).
    // Wave push only moves icons inside the Flickable (contentWidth may exceed).
    readonly property real pinnedDisplayedWidth: pinnedViewportWidth > 0
        ? pinnedViewportWidth
        : Math.min(dockFlexibleSectionsBudget, pinnedContentWidth)
    readonly property int dockRemainingFlexibleWidth: Math.max(0, dockFlexibleSectionsBudget - Math.ceil(pinnedDisplayedWidth))
    readonly property int availableWindowViewportWidth: hasNonMinimizedWindows ? Math.max(0, dockRemainingFlexibleWidth - minimumMinimizedViewportWidth) : 0
    readonly property bool dockWindowButtonsShowTitle: hasNonMinimizedWindows
        && !(settingsService && settingsService.dockForceIconOnly)
        && titledWindowContentWidth <= availableWindowViewportWidth
    readonly property int activeWindowContentWidth: dockWindowButtonsShowTitle ? titledWindowContentWidth : iconWindowContentWidth
    // Rest-sized viewport only — wave no longer expands the glass section width.
    readonly property int windowViewportWidth: hasNonMinimizedWindows
        ? Math.min(activeWindowContentWidth, availableWindowViewportWidth)
        : 0
    readonly property int availableMinimizedViewportWidth: hasMinimizedWindows ? Math.max(0, dockRemainingFlexibleWidth - windowViewportWidth) : 0
    readonly property int minimizedViewportWidth: hasMinimizedWindows ? Math.min(minimizedWindowContentWidth, availableMinimizedViewportWidth) : 0
    readonly property color glassFill: darkMode ? "#d01d1f24" : GlassStyle.FillDock
    readonly property color glassStroke: darkMode ? "#38ffffff" : GlassStyle.StrokeDock
    readonly property color dockText: darkMode ? "#f5f7fb" : "#202124"

    signal toggleLaunchpad()
    signal openPinnedAppMenu(var app, string appId, var anchorRect)
    signal openWindowMenu(var window, var anchorRect)

    visible: true

    onDockHiddenChanged: {
        dockRevealPrepareTimer.stop();

        if (dockHidden) {
            // T08-fix: keep glassActive true while the slide-out runs so blur
            // does not drop to pure transparent mid-animation. glassEnabled
            // still gates on dockVisibleHeight > 0 (see dockSurface).
            dockVisualHidden = true;
        } else {
            dockGlassActive = true;
            dockRevealPrepareTimer.restart();
        }
    }

    onDockSlideTargetChanged: root.animateDockSlideTo(dockSlideTarget)
    Component.onCompleted: root.dockSlideOffset = root.dockSlideTarget

    // Drop glass only after the panel has fully left the screen (or is about
    // to). Re-enable as soon as any visible height remains during reveal.
    onDockVisibleHeightChanged: {
        if (root.dockVisibleHeight > 0.5)
            root.dockGlassActive = true;
        else if (root.dockHidden && root.dockVisibleHeight <= 0.5)
            root.dockGlassActive = false;
    }

    // T08: autohide slide uses springSmooth (critically damped — no overshoot).
    // Glass region geometry stays clamped via dockVisibleHeight; only the
    // content transform (Translate y) is spring-driven. Dual branch for useSpring.
    function animateDockSlideTo(value) {
        dockSlideSpring.stop();
        dockSlideEase.stop();
        if (root.useSpring && !Motion.reducedMotion(root.settingsService)) {
            dockSlideSpring.to = value;
            dockSlideSpring.restart();
        } else {
            dockSlideEase.to = value;
            dockSlideEase.restart();
        }
    }

    SpringAnimation {
        id: dockSlideSpring
        target: root
        property: "dockSlideOffset"
        spring: Motion.springSmooth.spring
        damping: Motion.springSmooth.damping
        epsilon: 0.0005
    }
    NumberAnimation {
        id: dockSlideEase
        target: root
        property: "dockSlideOffset"
        duration: 190
        easing.type: Motion.emphasizedDecel
    }

    // T07 · Cosine-bell dock wave + analytical push.
    //
    // Scale and slot geometry are pure functions of (index, cursorX) against
    // rest centers — NEVER read delegate geometry here. That is what used to
    // create the width→magnification→width binding loop. Each delegate binds
    // magnification/x/width to these helpers; SpringAnimation Behaviors ease
    // toward the targets (useSpring dual branch preserved).
    //
    // scale(d) = 1 + (peak−1)·cos²(πd/2R), peak=Motion.dockMagPeak, R=2.5·icon.
    function dockWaveActive() {
        return dockHovered && !pointerDragActive;
    }

    function pinnedRestCenter(index) {
        return index * (dockPinnedButtonWidth + dockItemSpacing) + dockPinnedButtonWidth / 2;
    }

    function pinnedCursorX() {
        if (!pinnedViewport)
            return -10000;
        // dockMouseX is root-local (T08-fix4). Viewport origin in root space is
        // stable (does not depend on icon springs or surface bias).
        var origin = pinnedViewport.mapToItem(root, 0, 0);
        return dockMouseX - origin.x + pinnedViewport.contentX;
    }

    function pinnedScaleAt(index) {
        if (!dockWaveActive())
            return 1.0;
        return Motion.dockCosineScale(pinnedCursorX() - pinnedRestCenter(index), dockIconSize);
    }

    function pinnedItemWidthAt(index) {
        return dockPinnedButtonWidth * pinnedScaleAt(index);
    }

    function pinnedItemXAt(index) {
        var x = 0;
        for (var j = 0; j < index; j++)
            x += pinnedItemWidthAt(j) + dockItemSpacing;
        return x;
    }

    function pinnedWaveContentWidth() {
        var n = pinnedAppCount;
        if (n <= 0)
            return 0;
        var total = 0;
        for (var i = 0; i < n; i++)
            total += pinnedItemWidthAt(i);
        total += Math.max(0, n - 1) * dockItemSpacing;
        return total;
    }

    // Left-of-cursor wave extra (kept for diagnostics / future bias; unused for surface x).
    function pinnedWaveLeftExtra() {
        if (!dockWaveActive() || pinnedAppCount <= 0)
            return 0;
        var cursor = pinnedCursorX();
        var extra = 0;
        var step = dockPinnedButtonWidth + dockItemSpacing;
        for (var i = 0; i < pinnedAppCount; i++) {
            var restLeft = i * step;
            var restRight = restLeft + dockPinnedButtonWidth;
            var dw = pinnedItemWidthAt(i) - dockPinnedButtonWidth;
            if (dw < 0)
                dw = 0;
            if (cursor >= restRight) {
                extra += dw;
            } else if (cursor > restLeft) {
                extra += dw * ((cursor - restLeft) / Math.max(1, dockPinnedButtonWidth));
                break;
            } else {
                break;
            }
        }
        return extra;
    }

    function windowRestCenter(index) {
        var w = dockWindowButtonsShowTitle ? dockWindowTitleWidth : dockWindowIconWidth;
        return index * (w + dockItemSpacing) + w / 2;
    }

    function windowCursorX() {
        if (!windowViewport)
            return -10000;
        var origin = windowViewport.mapToItem(root, 0, 0);
        return dockMouseX - origin.x + windowViewport.contentX;
    }

    function windowScaleAt(index) {
        if (!dockWaveActive() || dockWindowButtonsShowTitle)
            return 1.0;
        return Motion.dockCosineScale(windowCursorX() - windowRestCenter(index), dockIconSize);
    }

    // T08-fix2: analytical push for icon-only window half (mirrors pinned).
    // Title mode keeps fixed slots — scale is disabled there already.
    function windowItemWidthAt(index) {
        if (dockWindowButtonsShowTitle)
            return dockWindowTitleWidth;
        return dockWindowIconWidth * windowScaleAt(index);
    }

    function windowItemXAt(index) {
        var x = 0;
        for (var j = 0; j < index; j++)
            x += windowItemWidthAt(j) + dockItemSpacing;
        return x;
    }

    function windowWaveContentWidth() {
        var n = windowButtonCount;
        if (n <= 0)
            return 0;
        if (dockWindowButtonsShowTitle)
            return titledWindowContentWidth;
        var total = 0;
        for (var i = 0; i < n; i++)
            total += windowItemWidthAt(i);
        total += Math.max(0, n - 1) * dockItemSpacing;
        return total;
    }

    function windowWaveLeftExtra() {
        if (!dockWaveActive() || dockWindowButtonsShowTitle || windowButtonCount <= 0)
            return 0;
        var cursor = windowCursorX();
        var extra = 0;
        var step = dockWindowIconWidth + dockItemSpacing;
        for (var i = 0; i < windowButtonCount; i++) {
            var restLeft = i * step;
            var restRight = restLeft + dockWindowIconWidth;
            var dw = windowItemWidthAt(i) - dockWindowIconWidth;
            if (dw < 0)
                dw = 0;
            if (cursor >= restRight) {
                extra += dw;
            } else if (cursor > restLeft) {
                extra += dw * ((cursor - restLeft) / Math.max(1, dockWindowIconWidth));
                break;
            } else {
                break;
            }
        }
        return extra;
    }

    // T08-fix4: do NOT shift the glass bar under the cursor. Moving surface.x
    // while dockMouseX is surface-local creates a scale/position feedback loop
    // (whole dock jitter). Icons still push inside the Flickable.
    function dockWaveSurfaceBias() {
        return 0;
    }

    // Optional overflow scroll — intentionally NOT called from every mouse move
    // (contentX → cursorX → wave → contentWidth feedback). Leave contentX at 0
    // unless the user flicks; reset on hover exit.
    function syncPinnedViewportToCursor() {
    }

    function syncWindowViewportToCursor() {
    }

    // Back-compat name used nowhere after T07, kept as alias for any external call.
    function proximityScale(item) {
        return 1.0;
    }

    function markDockHovered() {
        hoverExitTimer.stop();
        // Already revealed or auto-hide off: set immediately. Only the
        // first edge-enter while fully hidden is debounced (T08).
        // T08-fix4: do NOT restart an already-running debounce on every
        // positionChanged — that made reveal wait forever while the pointer moved.
        if (root.dockHovered || !root.dockAutoHide || !root.dockVisualHidden) {
            dockRevealDebounceTimer.stop();
            root.dockHovered = true;
            return;
        }
        if (!dockRevealDebounceTimer.running)
            dockRevealDebounceTimer.start();
    }

    function updateDockHover(x) {
        hoverExitTimer.stop();
        // x is root-local (PanelWindow coordinates). Never store surface-local or
        // animated-delegate-local coords — those thrash the wave (T08-fix4).
        root.dockMouseX = x;
        // Pointer is already on the surface — force reveal without debounce.
        dockRevealDebounceTimer.stop();
        root.dockHovered = true;
        root.pointerDragActive = false;
    }

    function updateDockHoverFromItem(item, localX, localY, buttons) {
        if (buttons !== Qt.NoButton) {
            root.pointerDragActive = true;
            root.resetDockHover();
            return;
        }
        if (!item)
            return;
        // Scene-stable pointer position in root space (includes current transforms
        // of parents but reports where the cursor actually is — not where the
        // spring thinks the slot is).
        var p = item.mapToItem(root, localX, localY !== undefined ? localY : 0);
        root.updateDockHover(p.x);
    }

    function updateDockHoverFromButtons(x, buttons) {
        if (buttons !== Qt.NoButton) {
            root.pointerDragActive = true;
            root.resetDockHover();
            return;
        }

        root.updateDockHover(x);
    }

    function updateDockHoverFromMouse(x, mouse) {
        var buttons = mouse && mouse.buttons !== undefined ? mouse.buttons : Qt.NoButton;
        root.updateDockHoverFromButtons(x, buttons);
    }

    function scheduleDockHoverReset() {
        dockRevealDebounceTimer.stop();
        hoverExitTimer.restart();
    }

    function resetDockHover() {
        hoverExitTimer.stop();
        dockRevealDebounceTimer.stop();
        root.dockHovered = false;
        root.dockMouseX = -10000;
        root.clearDockHoverLabel();
        if (pinnedViewport)
            pinnedViewport.contentX = 0;
        if (windowViewport)
            windowViewport.contentX = 0;
    }

    function showDockHoverLabel(text, item, yOffset) {
        if (!item || !dockSurface)
            return;
        var label = String(text || "");
        if (label.length === 0) {
            root.clearDockHoverLabel();
            return;
        }
        var center = item.mapToItem(dockSurface, item.width / 2, 0);
        root.dockHoverLabelText = label;
        root.dockHoverLabelCenterX = center.x;
        root.dockHoverLabelY = Math.round(center.y + (yOffset !== undefined ? yOffset : -30));
        root.dockHoverLabelVisible = true;
    }

    function updateDockHoverLabelGeometry(item, yOffset) {
        if (!item || !dockSurface || !root.dockHoverLabelVisible)
            return;
        var center = item.mapToItem(dockSurface, item.width / 2, 0);
        root.dockHoverLabelCenterX = center.x;
        root.dockHoverLabelY = Math.round(center.y + (yOffset !== undefined ? yOffset : -30));
    }

    function clearDockHoverLabel() {
        root.dockHoverLabelVisible = false;
        root.dockHoverLabelText = "";
        root.hoveredWindowButton = null;
    }

    function updateWindowHoverLabelGeometry(button) {
        if (!button || root.hoveredWindowButton !== button)
            return;
        root.updateDockHoverLabelGeometry(button, -30);
    }

    function showWindowHoverLabel(button) {
        var label = button ? String(button.label || "") : "";
        if (!button || button.showTitle || label.length === 0)
            return;
        root.hoveredWindowButton = button;
        root.showDockHoverLabel(label, button, -30);
    }

    function clearWindowHoverLabel(button) {
        if (!button || root.hoveredWindowButton === button)
            root.clearDockHoverLabel();
    }

    function seriesWidth(count, itemWidth) {
        count = Math.max(0, Number(count) || 0);
        if (count <= 0)
            return 0;

        return count * itemWidth + (count - 1) * dockItemSpacing;
    }

    function anchorRectFor(item) {
        if (!item)
            return null;

        var rect = root.itemRect(item);
        var panelHeight = root.height > 0 ? root.height : root.implicitHeight;
        var screenHeight = root.screen && root.screen.height ? root.screen.height : panelHeight;
        var dockTop = Math.max(0, screenHeight - panelHeight);
        return {
            "x": Math.round(rect.x),
            "y": Math.round(rect.y + dockTop),
            "width": Math.round(rect.width),
            "height": Math.round(rect.height)
        };
    }

    function pinnedVisualIndexForRowX(rowX) {
        var count = root.appsService && root.appsService.pinnedApps ? root.appsService.pinnedApps.length : 0;
        if (count <= 1)
            return -1;

        var itemWidth = root.dockPinnedButtonWidth;
        var step = itemWidth + root.dockItemSpacing;
        for (var i = 1; i < count; i++) {
            var center = i * step + itemWidth / 2;
            if (rowX < center)
                return i;
        }

        return count - 1;
    }

    function updatePinnedDragTarget(item, mouseX, mouseY) {
        var point = item.mapToItem(pinnedRow, mouseX, mouseY);
        root.dragTargetVisualIndex = pinnedVisualIndexForRowX(point.x);
    }

    function finishPinnedReorder(item) {
        if (root.appsService && root.dragTargetVisualIndex >= 1)
            root.appsService.movePinnedApp(item.pinnedIndex, root.dragTargetVisualIndex);

        root.dragTargetVisualIndex = -1;
        root.pointerDragActive = false;
        root.resetDockHover();
    }

    function openDownloads() {
        Quickshell.execDetached({
            command: [
                "sh",
                "-lc",
                "dir=\"$HOME/Downloads\"; " +
                "if command -v xdg-user-dir >/dev/null 2>&1; then " +
                "found=\"$(xdg-user-dir DOWNLOAD 2>/dev/null || true)\"; " +
                "[ -n \"$found\" ] && dir=\"$found\"; fi; " +
                "xdg-open \"$dir\""
            ]
        });
    }

    function openTrash() {
        Quickshell.execDetached({ command: ["gio", "open", "trash:///"] });
    }

    function trashUrls(urls) {
        if (!urls || urls.length === 0)
            return;

        var command = ["gio", "trash"];
        for (var i = 0; i < urls.length; i++) {
            var path = root.appsService ? root.appsService.localPathFromDropUrl(urls[i]) : String(urls[i] || "");
            if (path.length > 0)
                command.push(path);
        }

        if (command.length > 2)
            Quickshell.execDetached({ command: command });
    }

    onLaunchpadOpenChanged: if (launchpadOpen) resetDockHover()

    Timer {
        id: hoverExitTimer
        interval: root.dockAutoHide ? root.dockHideDelay : 90
        repeat: false
        onTriggered: root.resetDockHover()
    }

    // T08: debounce first edge-enter while dock is hidden so rapid
    // skims of the reveal zone do not jitter the panel open/closed.
    Timer {
        id: dockRevealDebounceTimer
        interval: Motion.dockRevealDebounceMs
        repeat: false
        onTriggered: root.dockHovered = true
    }

    Timer {
        id: dockRevealPrepareTimer
        interval: 34
        repeat: false
        onTriggered: if (!root.dockHidden) root.dockVisualHidden = false
    }

    anchors {
        left: true
        right: true
        bottom: true
    }

    exclusiveZone: 100
    exclusionMode: dockAutoHide ? ExclusionMode.Ignore : ExclusionMode.Normal
    implicitHeight: 140
    color: "transparent"
    WlrLayershell.namespace: "tahoe-dock"

    mask: Region {
        Region {
            x: Math.round(dockSurface.x)
            y: Math.round(root.height - dockSurface.height + root.dockSlideOffset)
            width: dockSurface.width
            height: (!root.dockHidden || root.dockVisibleAmount > 0.001) ? Math.round(root.dockVisibleHeight) : 0
            radius: dockSurface.radius
        }

        Region {
            x: 0
            y: Math.max(0, root.height - root.dockRevealZoneHeight)
            width: root.width
            height: root.dockAutoHide ? Math.max(2, root.dockRevealZoneHeight) : 0
        }
    }

    TahoeGlass.regions: [dockSurface.region]

    // T08: dockSlideOffset is driven by explicit springSmooth / NumberAnimation
    // dual branch (see animateDockSlideTo). No Behavior interceptor here.

    MouseArea {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: Math.max(2, root.dockRevealZoneHeight)
        enabled: root.dockAutoHide
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: root.markDockHovered()
        onPositionChanged: root.markDockHovered()
        onExited: root.scheduleDockHoverReset()
    }

    GlassPanel {
        id: dockSurface

        // T08-fix4: keep surface horizontally centered. Do not bias x with the
        // wave — surface-local mouse coords + moving surface = jitter loop.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        width: Math.min(root.dockSurfaceMaxWidth, dockRow.implicitWidth + root.dockSurfacePadding)
        height: root.dockSurfaceHeight
        material: GlassStyle.MaterialDock
        radius: GlassStyle.RadiusDock
        fillColor: root.glassFill
        strokeColor: root.glassStroke
        useItemRegion: false
        regionX: Math.round(dockSurface.x)
        // niri rejects glass regions that extend outside the layer surface.
        // While the Dock slides in from below, expose only the visible
        // portion so the compositor keeps blur active throughout reveal.
        regionY: Math.round(root.height - root.dockVisibleHeight)
        regionWidth: Math.round(dockSurface.width)
        regionHeight: Math.round(root.dockVisibleHeight)
        interaction: root.dockGlassInteraction
        materialAlpha: 1.0
        // Keep blur alive for the whole slide; only drop when fully off-screen.
        glassEnabled: root.dockGlassActive && root.dockVisibleHeight > 0.5

        transform: Translate {
            y: root.dockSlideOffset
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onPositionChanged: function(mouse) {
                root.updateDockHoverFromItem(this, mouse.x, mouse.y, mouse.buttons !== undefined ? mouse.buttons : Qt.NoButton);
            }
            onEntered: root.markDockHovered()
            onExited: root.scheduleDockHoverReset()
        }

        Row {
            id: dockRow
            anchors.centerIn: parent
            spacing: root.dockItemSpacing

            Item {
                width: root.pinnedDisplayedWidth
                height: root.dockPinnedRowHeight

                Flickable {
                    id: pinnedViewport

                    x: 0
                    y: -40
                    width: parent.width
                    height: parent.height + 40
                    // contentWidth tracks the analytical wave; rest width is the idle floor.
                    // Explicit dockMouseX dep so the binding reevaluates every move.
                    contentWidth: {
                        var _dep = root.dockMouseX + root.pinnedAppCount + (root.dockHovered ? 1 : 0);
                        return Math.max(root.pinnedContentWidth, root.pinnedWaveContentWidth());
                    }
                    contentHeight: height
                    // Only clip when the wave overflows the viewport; otherwise
                    // let edge icons paint into the surface padding (T08-fix).
                    clip: contentWidth > width + 1
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick

                    // Explicit-x container (not Row): each icon's x/width come from
                    // analytical helpers so the wave can push neighbors without
                    // reading live delegate geometry (binding-loop free).
                    Item {
                        id: pinnedRow

                        y: 40
                        width: {
                            var _dep = root.dockMouseX + root.pinnedAppCount + (root.dockHovered ? 1 : 0);
                            return Math.max(root.pinnedContentWidth, root.pinnedWaveContentWidth());
                        }
                        height: root.dockPinnedRowHeight
                        implicitWidth: width

                        Repeater {
                            model: ScriptModel {
                                values: root.appsService ? root.appsService.pinnedApps : []
                            }

                            delegate: Item {
                                id: pinnedButton

                                required property var modelData
                                required property int index
                                // pressScale still uses Behavior (single) via Motion press token.
                                property real pressScale: Motion.pressScaleFor(root.settingsService, iconMouse.pressed && !pinnedButton.reorderActive)
                                readonly property int pinnedIndex: pinnedButton.index
                                readonly property string appId: root.appsService ? root.appsService.pinnedIdForVisualIndex(pinnedButton.pinnedIndex, modelData) : ""
                                readonly property var appModel: root.appsService ? root.appsService.resolveApplication(pinnedButton.appId, modelData) : modelData
                                property bool suppressNextClick: false
                                readonly property bool hovered: !root.pointerDragActive && iconMouse.containsMouse
                                readonly property bool running: (!appModel || appModel.shellAction !== "launchpad")
                                    && root.appsService
                                    && root.niriService
                                    && root.appsService.appHasRunningWindow(appModel, root.niriService.windowList)
                                // T08 launching state machine: true while waiting for first window
                                // after a cold launch. Stops on running or 10s timeout.
                                property bool launching: false
                                readonly property real lift: (magnification - 1.0) * root.dockLiftFactor
                                // Combined bounce: click settle + launch loop share one offset.
                                property real bounceOffset: 0
                                height: root.dockPinnedRowHeight

                                property bool reorderPressed: false
                                property bool reorderActive: false
                                property real reorderPressX: 0
                                property real reorderPressY: 0

                                onRunningChanged: {
                                    if (pinnedButton.running)
                                        pinnedButton.stopLaunchBounce();
                                }
                                onLaunchingChanged: {
                                    if (pinnedButton.launching)
                                        launchBounceTimeout.restart();
                                    else
                                        launchBounceTimeout.stop();
                                }

                                Timer {
                                    id: suppressClickReset
                                    interval: 180
                                    repeat: false
                                    onTriggered: pinnedButton.suppressNextClick = false
                                }

                                // 10s safety stop if the app never maps a window (T08).
                                Timer {
                                    id: launchBounceTimeout
                                    interval: Motion.dockLaunchBounceTimeoutMs
                                    repeat: false
                                    onTriggered: pinnedButton.stopLaunchBounce()
                                }

                                DropArea {
                                    anchors.fill: parent
                                    onDropped: function(drop) {
                                        if (!root.appsService)
                                            return;

                                        try {
                                            if (drop.urls && drop.urls.length > 0) {
                                                root.appsService.openFilesWithApp(pinnedButton.appModel, drop.urls);
                                                drop.acceptProposedAction();
                                            }
                                        } catch (e) {}
                                    }
                                }

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 8
                                    width: root.dockIconSize + 8
                                    height: root.dockIconSize + 8
                                    radius: 18
                                    color: root.launchpadOpen && pinnedButton.appId === "launchpad" ? "#70ffffff" : "transparent"
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: 16
                                    color: "transparent"
                                    border.color: root.dragTargetVisualIndex === pinnedButton.pinnedIndex && root.pointerDragActive ? "#8dffffff" : "transparent"
                                    border.width: 2
                                }

                                Image {
                                    id: appIcon
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    // Bottom-origin scale: feet stay on the dock baseline.
                                    // Only bounceOffset lifts the whole icon (click / launch).
                                    y: 10 - pinnedButton.lift - pinnedButton.bounceOffset
                                    width: root.dockIconSize
                                    height: root.dockIconSize
                                    scale: pinnedButton.magnification * pinnedButton.pressScale
                                    opacity: (pinnedButton.reorderActive ? 0.58 : 1) * (iconMouse.pressed ? 0.75 : 1)
                                    source: root.appsService ? root.appsService.iconForApp(pinnedButton.appModel || pinnedButton.appId) : ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: false
                                    sourceSize.width: root.dockIconSourceSize
                                    sourceSize.height: root.dockIconSourceSize
                                    asynchronous: true
                                    // macOS dock grows upward from the icon feet (T08-fix3).
                                    transformOrigin: Item.Bottom

                                    Behavior on opacity {
                                        NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing }
                                    }
                                }

                                Behavior on pressScale {
                                    NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing }
                                }

                                Rectangle {
                                    id: runningDot
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    width: (pinnedButton.running || pinnedButton.launching) ? 5 : 0
                                    height: 5
                                    radius: 3
                                    color: pinnedButton.launching && !pinnedButton.running
                                        ? (root.darkMode ? "#a0ffffff" : "#99000000")
                                        : (root.darkMode ? "#ccffffff" : "#99000000")

                                    // T08: 2px soft glow (sibling halo; no GraphicalEffects).
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width + 4
                                        height: parent.height + 4
                                        radius: width / 2
                                        z: -1
                                        visible: parent.width > 0
                                        color: root.darkMode ? "#40ffffff" : "#40000000"
                                    }
                                }

                                MouseArea {
                                    id: iconMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onPositionChanged: function(mouse) {
                                        if (pinnedButton.reorderPressed && pinnedButton.appId !== "launchpad" && (mouse.buttons & Qt.LeftButton)) {
                                            var dx = mouse.x - pinnedButton.reorderPressX;
                                            var dy = mouse.y - pinnedButton.reorderPressY;
                                            if (!pinnedButton.reorderActive && Math.sqrt(dx * dx + dy * dy) > 8) {
                                                pinnedButton.reorderActive = true;
                                                pinnedButton.suppressNextClick = true;
                                                root.pointerDragActive = true;
                                                root.resetDockHover();
                                            }

                                            if (pinnedButton.reorderActive)
                                                root.updatePinnedDragTarget(pinnedButton, mouse.x, mouse.y);

                                            return;
                                        }

                                        root.updateDockHoverFromItem(
                                            pinnedButton,
                                            mouse.x,
                                            mouse.y,
                                            mouse.buttons !== undefined ? mouse.buttons : Qt.NoButton
                                        );
                                        if (pinnedButton.hovered) {
                                            var label = root.appsService ? root.appsService.appLabel(pinnedButton.appModel || pinnedButton.appId) : "";
                                            root.showDockHoverLabel(label, pinnedButton, -34);
                                        }
                                    }
                                    onEntered: {
                                        root.markDockHovered();
                                        var label = root.appsService ? root.appsService.appLabel(pinnedButton.appModel || pinnedButton.appId) : "";
                                        root.showDockHoverLabel(label, pinnedButton, -34);
                                    }
                                    onExited: {
                                        root.clearDockHoverLabel();
                                        root.scheduleDockHoverReset();
                                    }
                                    onPressed: function(mouse) {
                                        if (mouse.button === Qt.LeftButton && pinnedButton.appId !== "launchpad") {
                                            pinnedButton.reorderPressed = true;
                                            pinnedButton.reorderPressX = mouse.x;
                                            pinnedButton.reorderPressY = mouse.y;
                                        }
                                    }
                                    onReleased: function(mouse) {
                                        if (pinnedButton.reorderActive) {
                                            root.finishPinnedReorder(pinnedButton);
                                            suppressClickReset.restart();
                                        }

                                        pinnedButton.reorderPressed = false;
                                        pinnedButton.reorderActive = false;
                                    }
                                    onCanceled: {
                                        pinnedButton.reorderPressed = false;
                                        pinnedButton.reorderActive = false;
                                        root.dragTargetVisualIndex = -1;
                                        root.pointerDragActive = false;
                                        root.resetDockHover();
                                        suppressClickReset.restart();
                                    }
                                    onClicked: function(mouse) {
                                        if (pinnedButton.suppressNextClick)
                                            return;

                                        if (mouse.button === Qt.RightButton) {
                                            pinnedButton.bounce();
                                            if (pinnedButton.appId !== "launchpad")
                                                root.openPinnedAppMenu(pinnedButton.appModel, pinnedButton.appId, root.anchorRectFor(pinnedButton));
                                            root.markDockHovered();
                                            return;
                                        } else if (pinnedButton.appId === "launchpad") {
                                            pinnedButton.bounce();
                                            root.toggleLaunchpad();
                                        } else if (root.appsService) {
                                            // T08: cold-start → launch bounce loop; re-click
                                            // while already launching does not stack anims.
                                            // Already-running apps just get a single bounce.
                                            if (!pinnedButton.running && !pinnedButton.launching)
                                                pinnedButton.startLaunchBounce();
                                            else if (!pinnedButton.launching)
                                                pinnedButton.bounce();
                                            root.appsService.launchPinnedApp(pinnedButton.appModel, pinnedButton.appId);
                                        }
                                    }
                                }

                                // T07: explicit dual-branch animations (useSpring gate).
                                // A single property may only have ONE Behavior interceptor;
                                // dual Behavior{} was ignored for the second and spammed
                                // "another interceptor" warnings (T00 待办). Drive settle
                                // with explicit SpringAnimation / NumberAnimation instead.
                                readonly property real magnificationTarget: root.pinnedScaleAt(pinnedButton.index)
                                readonly property real xTarget: root.pinnedItemXAt(pinnedButton.index)
                                readonly property real widthTarget: root.pinnedItemWidthAt(pinnedButton.index)

                                // Writable animated values (not bound) so animations own them.
                                property real magnification: 1.0
                                // bounceOffset declared above (shared by click + launch loop).
                                // x/width still need initial layout; animate toward targets.
                                x: 0
                                width: root.dockPinnedButtonWidth

                                onMagnificationTargetChanged: pinnedButton.animateMagnification()
                                onXTargetChanged: pinnedButton.animateX()
                                onWidthTargetChanged: pinnedButton.animateWidth()
                                Component.onCompleted: {
                                    pinnedButton.magnification = pinnedButton.magnificationTarget;
                                    pinnedButton.x = pinnedButton.xTarget;
                                    pinnedButton.width = pinnedButton.widthTarget;
                                }
                                Component.onDestruction: pinnedButton.stopLaunchBounce()

                                function animateMagnification() {
                                    if (root.useSpring) {
                                        magSpring.to = magnificationTarget;
                                        magSpring.restart();
                                    } else {
                                        magEase.to = magnificationTarget;
                                        magEase.restart();
                                    }
                                }
                                function animateX() {
                                    if (root.useSpring) {
                                        xSpring.to = xTarget;
                                        xSpring.restart();
                                    } else {
                                        xEase.to = xTarget;
                                        xEase.restart();
                                    }
                                }
                                function animateWidth() {
                                    if (root.useSpring) {
                                        widthSpring.to = widthTarget;
                                        widthSpring.restart();
                                    } else {
                                        widthEase.to = widthTarget;
                                        widthEase.restart();
                                    }
                                }

                                SpringAnimation {
                                    id: magSpring
                                    target: pinnedButton
                                    property: "magnification"
                                    spring: Motion.dockMagSpring.spring
                                    damping: Motion.dockMagSpring.damping
                                    epsilon: Motion.dockMagSpring.epsilon
                                }
                                NumberAnimation {
                                    id: magEase
                                    target: pinnedButton
                                    property: "magnification"
                                    duration: Motion.elementMove(root.settingsService)
                                    easing.type: Motion.emphasizedDecel
                                }
                                SpringAnimation {
                                    id: xSpring
                                    target: pinnedButton
                                    property: "x"
                                    spring: Motion.dockMagSpring.spring
                                    damping: Motion.dockMagSpring.damping
                                    epsilon: Motion.dockMagSpring.epsilon
                                }
                                NumberAnimation {
                                    id: xEase
                                    target: pinnedButton
                                    property: "x"
                                    duration: Motion.elementMove(root.settingsService)
                                    easing.type: Motion.emphasizedDecel
                                }
                                SpringAnimation {
                                    id: widthSpring
                                    target: pinnedButton
                                    property: "width"
                                    spring: Motion.dockMagSpring.spring
                                    damping: Motion.dockMagSpring.damping
                                    epsilon: Motion.dockMagSpring.epsilon
                                }
                                NumberAnimation {
                                    id: widthEase
                                    target: pinnedButton
                                    property: "width"
                                    duration: Motion.elementMove(root.settingsService)
                                    easing.type: Motion.emphasizedDecel
                                }

                                // ── Click bounce (single hop) ──────────────────────
                                Timer {
                                    id: bounceTimer
                                    interval: 16
                                    repeat: false
                                    onTriggered: pinnedButton.animateBounceTo(0)
                                }

                                function bounce() {
                                    if (pinnedButton.launching)
                                        return;
                                    bounceSpring.stop();
                                    bounceEase.stop();
                                    launchBounceLoop.stop();
                                    pinnedButton.bounceOffset = 14;
                                    bounceTimer.restart();
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

                                SpringAnimation {
                                    id: bounceSpring
                                    target: pinnedButton
                                    property: "bounceOffset"
                                    spring: Motion.springBouncy.spring
                                    damping: Motion.springBouncy.damping
                                    epsilon: 0.01
                                }
                                NumberAnimation {
                                    id: bounceEase
                                    target: pinnedButton
                                    property: "bounceOffset"
                                    duration: 220
                                    easing.type: Motion.emphasizedDecel
                                }

                                // ── T08 launch bounce loop ─────────────────────────
                                // Parabola cycle: up InQuad, down OutQuad; height =
                                // 0.7×icon, period 550ms. Re-entrant start is a no-op
                                // (连点不叠加). reduced profile: single hop then idle.
                                function startLaunchBounce() {
                                    if (pinnedButton.launching)
                                        return;
                                    if (Motion.reducedMotion(root.settingsService)) {
                                        // One instant hop, no loop under reduced.
                                        pinnedButton.bounce();
                                        return;
                                    }
                                    bounceSpring.stop();
                                    bounceEase.stop();
                                    bounceTimer.stop();
                                    pinnedButton.bounceOffset = 0;
                                    pinnedButton.launching = true;
                                    launchBounceLoop.restart();
                                }
                                function stopLaunchBounce() {
                                    if (!pinnedButton.launching && !launchBounceLoop.running)
                                        return;
                                    launchBounceLoop.stop();
                                    launchBounceTimeout.stop();
                                    pinnedButton.launching = false;
                                    // Settle residual offset to 0 without stacking.
                                    bounceSpring.stop();
                                    bounceEase.stop();
                                    bounceTimer.stop();
                                    if (Math.abs(pinnedButton.bounceOffset) > 0.5)
                                        pinnedButton.animateBounceTo(0);
                                    else
                                        pinnedButton.bounceOffset = 0;
                                }

                                SequentialAnimation {
                                    id: launchBounceLoop
                                    loops: Animation.Infinite
                                    NumberAnimation {
                                        target: pinnedButton
                                        property: "bounceOffset"
                                        from: 0
                                        to: Motion.dockLaunchBounceHeight(root.dockIconSize)
                                        duration: Math.round(Motion.dockLaunchBouncePeriodMs / 2)
                                        easing.type: Easing.InQuad
                                    }
                                    NumberAnimation {
                                        target: pinnedButton
                                        property: "bounceOffset"
                                        from: Motion.dockLaunchBounceHeight(root.dockIconSize)
                                        to: 0
                                        duration: Math.round(Motion.dockLaunchBouncePeriodMs / 2)
                                        easing.type: Easing.OutQuad
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: 1
                height: root.dockIconSize
                radius: 1
                color: root.darkMode ? "#40ffffff" : "#3d000000"
                visible: root.hasDockWindowSection
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                width: root.windowViewportWidth
                height: root.dockWindowRowHeight
                visible: root.hasNonMinimizedWindows && width > 0

                Flickable {
                    id: windowViewport

                    x: 0
                    y: -36
                    width: parent.width
                    height: parent.height + 36
                    // T08-fix2: content tracks analytical wave in icon-only mode.
                    contentWidth: {
                        var _dep = root.dockMouseX + root.windowButtonCount + (root.dockHovered ? 1 : 0)
                            + (root.dockWindowButtonsShowTitle ? 1 : 0);
                        if (root.dockWindowButtonsShowTitle)
                            return root.activeWindowContentWidth;
                        return Math.max(root.activeWindowContentWidth, root.windowWaveContentWidth());
                    }
                    contentHeight: height
                    clip: contentWidth > width + 1
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick

                    // Explicit-x container (not Row) in icon-only mode so wave can
                    // push neighbors without reading live delegate geometry.
                    // Title mode still uses a Row (fixed slots, no scale/push).
                    Item {
                        id: windowRow

                        y: 36
                        width: {
                            var _dep = root.dockMouseX + root.windowButtonCount + (root.dockHovered ? 1 : 0)
                                + (root.dockWindowButtonsShowTitle ? 1 : 0);
                            if (root.dockWindowButtonsShowTitle)
                                return root.activeWindowContentWidth;
                            return Math.max(root.activeWindowContentWidth, root.windowWaveContentWidth());
                        }
                        height: root.dockWindowRowHeight
                        implicitWidth: width

                        Repeater {
                            model: ScriptModel {
                                objectProp: "modelKey"
                                values: root.dockWindowList
                            }

                            delegate: WindowButton {
                                id: windowButton

                                required property var modelData
                                required property int index

                                windowModel: modelData
                                toplevel: modelData ? modelData.toplevel : null
                                windowsService: root.niriService
                                appsService: root.appsService
                                settingsService: root.settingsService
                                useSpring: root.useSpring
                                iconSize: root.dockWindowButtonsShowTitle ? 40 : root.dockIconSize
                                showTitle: root.dockWindowButtonsShowTitle
                                // Analytical slot geometry (icon-only). Title mode
                                // uses fixed rest width via WindowButton defaults.
                                slotWidthTarget: root.dockWindowButtonsShowTitle
                                    ? root.dockWindowTitleWidth
                                    : root.windowItemWidthAt(windowButton.index)
                                slotXTarget: root.dockWindowButtonsShowTitle
                                    ? windowButton.index * (root.dockWindowTitleWidth + root.dockItemSpacing)
                                    : root.windowItemXAt(windowButton.index)
                                magnificationTarget: root.windowScaleAt(windowButton.index)
                                hoverLabelEnabled: false
                                labelClipItem: windowViewport
                                labelClipContentX: windowViewport.contentX
                                dockWindow: root
                                dockSurfaceItem: dockSurface
                                dockSlideOffset: root.dockSlideOffset
                                onDockPointerMoved: function(x, buttons) {
                                    root.updateWindowHoverLabelGeometry(windowButton);
                                    // x is root-local from WindowButton (T08-fix4).
                                    root.updateDockHoverFromButtons(x, buttons === undefined ? Qt.NoButton : buttons);
                                }
                                onDockPointerEntered: {
                                    root.showWindowHoverLabel(windowButton);
                                    root.markDockHovered();
                                }
                                onDockPointerExited: {
                                    root.clearWindowHoverLabel(windowButton);
                                    root.scheduleDockHoverReset();
                                }
                                onContextMenuRequested: function(window) {
                                    root.openWindowMenu(window, root.anchorRectFor(windowButton));
                                    root.markDockHovered();
                                }
                                Component.onDestruction: root.clearWindowHoverLabel(windowButton)
                            }
                        }
                    }
                }
            }

            DockMinimizedShelf {
                width: root.minimizedViewportWidth
                height: root.dockWindowRowHeight
                visible: root.hasMinimizedWindows && width > 0
                windowsService: root.niriService
                thumbnailProvider: root.thumbnailProvider
                appsService: root.appsService
                settingsService: root.settingsService
                dockWindow: root
                dockSurfaceItem: dockSurface
                dockSlideOffset: root.dockSlideOffset
                thumbnailWidth: root.dockMinimizedThumbnailWidth
                onDockPointerMoved: function(x, buttons) {
                    root.updateDockHoverFromButtons(x, buttons === undefined ? Qt.NoButton : buttons);
                }
                onDockPointerEntered: root.markDockHovered()
                onDockPointerExited: root.scheduleDockHoverReset()
                onContextMenuRequested: function(window, anchorItem) {
                    root.openWindowMenu(window, root.anchorRectFor(anchorItem));
                    root.markDockHovered();
                }
            }

            Rectangle {
                width: 1
                height: root.dockIconSize
                radius: 1
                color: root.darkMode ? "#40ffffff" : "#3d000000"
                anchors.verticalCenter: parent.verticalCenter
            }

            DockToolButton {
                iconSource: root.appsService ? root.appsService.iconPath("dock", "downloads.png") : ""
                label: "下载"
                onActivated: root.openDownloads()
            }

            DockToolButton {
                iconSource: root.appsService ? root.appsService.iconPath("dock", "bin.png") : ""
                label: "废纸篓"
                acceptsTrashDrop: true
                onActivated: root.openTrash()
                onUrlsDropped: function(urls) {
                    root.trashUrls(urls);
                }
            }
        }

        // T07 unified hover label — one capsule for pinned / window / tool.
        // Instant appear (no y-slide); 13px; fade only on opacity.
        Rectangle {
            id: dockHoverLabel

            readonly property real labelMaxWidth: Math.max(48, Math.min(280, dockSurface.width - 12))

            z: 20
            x: Math.max(6, Math.min(dockSurface.width - width - 6, root.dockHoverLabelCenterX - width / 2))
            y: root.dockHoverLabelY
            width: Math.min(Math.max(dockHoverLabelTextItem.implicitWidth + 18, 48), labelMaxWidth)
            height: 26
            radius: 7
            color: "#d9f7f8fb"
            border.color: "#70ffffff"
            opacity: root.dockHoverLabelVisible ? 1 : 0
            visible: opacity > 0.01

            Text {
                id: dockHoverLabelTextItem

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                text: root.dockHoverLabelText
                color: root.dockText
                font.pixelSize: 13
                elide: Text.ElideRight
                maximumLineCount: 1
                horizontalAlignment: Text.AlignHCenter
            }

            Behavior on opacity {
                NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.emphasizedDecel }
            }
        }
    }

    component DockToolButton: Item {
        id: tool

        property string iconSource: ""
        property string label: ""
        property bool acceptsTrashDrop: false

        signal activated()
        signal urlsDropped(var urls)

        width: root.dockToolButtonWidth
        height: root.dockPinnedRowHeight - 8
        scale: Motion.pressScaleFor(root.settingsService, toolMouse.pressed)
        opacity: toolMouse.pressed ? 0.75 : 1

        Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
        Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 16
            color: toolMouse.containsMouse ? "#30ffffff" : "transparent"
            border.color: "transparent"
        }

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            width: 40
            height: 40
            source: tool.iconSource
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: false
            sourceSize.width: root.dockToolIconSourceSize
            sourceSize.height: root.dockToolIconSourceSize
            asynchronous: true
        }

        DropArea {
            anchors.fill: parent
            enabled: tool.acceptsTrashDrop
            onDropped: function(drop) {
                try {
                    if (drop.urls && drop.urls.length > 0) {
                        tool.urlsDropped(drop.urls);
                        drop.acceptProposedAction();
                    }
                } catch (e) {}
            }
        }

        MouseArea {
            id: toolMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: {
                root.markDockHovered();
                root.showDockHoverLabel(tool.label, tool, -34);
            }
            onPositionChanged: function(mouse) {
                root.updateDockHoverFromItem(tool, mouse.x, mouse.y, mouse.buttons !== undefined ? mouse.buttons : Qt.NoButton);
                if (toolMouse.containsMouse)
                    root.showDockHoverLabel(tool.label, tool, -34);
            }
            onExited: {
                root.clearDockHoverLabel();
                root.scheduleDockHoverReset();
            }
            onClicked: tool.activated()
        }
    }
}
