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
    property bool fullscreenActive: false
    property bool launchpadOpen: false
    // See shell.qml useSpring. Spring on Image geometry corrupts textures on
    // VMware/software GPUs; NumberAnimation is safe. Default false.
    property bool useSpring: false
    property bool darkMode: false
    property bool menuOpen: false
    property real fullscreenTransition: fullscreenActive ? 1 : 0
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
    // Icon base 48 (T08-fix). Peak mag paints ABOVE the glass shelf (macOS).
    // Layer is taller than the glass; glassClip stays TRUE so compositor blur
    // is rounded. QML children are not clipped by glassClip (T08-fix11).
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
    // Glass shelf only — icons grow above it (macOS). Keep short.
    readonly property int dockSurfaceHeight: 84
    readonly property int dockPinnedRowHeight: 70
    readonly property int dockWindowRowHeight: 60
    // Layer headroom ABOVE the glass for peak-mag paint / hit-testing.
    // Must NOT be added to section host heights (that lifted tools via Row
    // top-alignment and drew a floating transparent bar — T08-fix10).
    readonly property int dockMagHeadroom: Math.ceil(dockIconSize * (Motion.dockMagPeak - 1.0) + 16)
    // Soft horizontal bleed past section edges into glass padding.
    readonly property real dockMagBleedPx: dockIconSize * (Motion.dockMagPeak - 1.0) * 0.35
    // T08-fix3: scale from icon bottom (macOS). Mag-based lift is no longer
    // needed — center-origin + lift was what left icons floating mid-air.
    readonly property real dockLiftFactor: 0
    readonly property int dockSurfaceMaxWidth: Math.max(1, root.width - dockOuterMargin)
    readonly property int dockContentMaxWidth: Math.max(1, dockSurfaceMaxWidth - dockSurfacePadding)
    readonly property var dockPinnedEntries: buildDockPinnedEntries()
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
    // T08-fix8: glass geometry is REST-only and never depends on the wave.
    // Wave is visual-only (scale + Translate), clamped inside each section so
    // icons cannot paint into the separator / minimized shelf / tools.
    readonly property real pinnedDisplayedWidth: pinnedViewportWidth > 0
        ? pinnedViewportWidth
        : Math.min(dockFlexibleSectionsBudget, pinnedContentWidth)
    readonly property int dockRemainingFlexibleWidth: Math.max(0, dockFlexibleSectionsBudget - Math.ceil(pinnedDisplayedWidth))
    readonly property int availableWindowViewportWidth: hasNonMinimizedWindows ? Math.max(0, dockRemainingFlexibleWidth - minimumMinimizedViewportWidth) : 0
    readonly property bool dockWindowButtonsShowTitle: hasNonMinimizedWindows
        && !(settingsService && settingsService.dockForceIconOnly)
        && titledWindowContentWidth <= availableWindowViewportWidth
    readonly property int activeWindowContentWidth: dockWindowButtonsShowTitle ? titledWindowContentWidth : iconWindowContentWidth
    readonly property int windowViewportWidth: hasNonMinimizedWindows
        ? Math.min(activeWindowContentWidth, availableWindowViewportWidth)
        : 0
    readonly property int availableMinimizedViewportWidth: hasMinimizedWindows ? Math.max(0, dockRemainingFlexibleWidth - windowViewportWidth) : 0
    readonly property int minimizedViewportWidth: hasMinimizedWindows ? Math.min(minimizedWindowContentWidth, availableMinimizedViewportWidth) : 0
    readonly property real dockRowTargetWidth: pinnedDisplayedWidth
        + dockWindowDividerWidth
        + windowViewportWidth
        + minimizedViewportWidth
        + dockRightToolsWidth
        + dockRowSpacingWidth
    readonly property real dockChromeTargetWidth: Math.min(dockSurfaceMaxWidth, dockRowTargetWidth + dockSurfacePadding)
    // WindowButton computes its exact target with mapToItem(), but that call
    // does not observe changes in ancestor geometry. Keep the parent-chain
    // scene offset explicit so first-layout and later Dock motion republish the
    // foreign-toplevel rectangle instead of leaving the creation-frame value.
    readonly property real windowSectionSceneOffsetX: dockChrome.x
        + dockRow.x
        + windowSectionHost.x
        + windowViewport.x
        + windowRow.x
        - windowViewport.contentX
    readonly property real windowSectionSceneOffsetY: dockChrome.y
        + dockRow.y
        + windowSectionHost.y
        + windowViewport.y
        + windowRow.y
        - windowViewport.contentY
    // Wave section: "pinned" | "window" | "" — cursor is rest-local to that section.
    property string dockWaveSection: ""
    readonly property color glassFill: darkMode ? "#d01d1f24" : GlassStyle.FillDock
    readonly property color glassStroke: darkMode ? "#38ffffff" : GlassStyle.StrokeDock
    readonly property color dockText: darkMode ? "#f5f7fb" : "#202124"

    signal toggleLaunchpad()
    signal openPinnedAppMenu(var app, string appId, var anchorRect)
    signal openWindowMenu(var window, var anchorRect)

    // ScriptModel must key pinned delegates by the configured pin identity, not
    // the currently resolved DesktopEntry id. A fallback pin may resolve to a
    // different desktop entry after a scan; retaining modelKey preserves the
    // delegate's hover, magnification, reorder, and launch-bounce state.
    function buildDockPinnedEntries() {
        var apps = root.appsService && root.appsService.pinnedApps
            ? root.appsService.pinnedApps
            : [];
        var entries = [];
        for (var i = 0; i < apps.length; i++) {
            var app = apps[i];
            var persistentId = root.appsService
                ? root.appsService.pinnedIdForVisualIndex(i, app)
                : "";
            entries.push({
                "modelKey": String(persistentId || ("pinned-" + i)),
                "app": app
            });
        }
        return entries;
    }

    visible: !root.fullscreenActive || dockChrome.opacity > 0.01

    Behavior on fullscreenTransition {
        NumberAnimation {
            duration: Motion.elementResize(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }
    }

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
        // Larger epsilon: sub-pixel residual motion was keeping glass region
        // height/y dirty every frame (~60Hz Tahoe glass commits in session.log).
        epsilon: 0.05
    }
    NumberAnimation {
        id: dockSlideEase
        target: root
        property: "dockSlideOffset"
        duration: 190
        easing.type: Motion.emphasizedDecel
    }

    // T08-fix8/9 · Fixed glass + visual wave that actually magnifies.
    //
    // Lessons from the fix cycle:
    //  - Growing glass with the wave → whole bar shakes.
    //  - SpringAnimation.restart() every mousemove → lag/overshoot looks like shake.
    //  - Compressing *scales* to fit host when host==rest width → factor=0, wave dies.
    //
    // Rules:
    //  1. Glass x/width NEVER depend on the wave.
    //  2. Layout slots stay at REST x/width.
    //  3. Cursor is REST-section local.
    //  4. Cosine scales stay FULL strength (never zeroed to fit).
    //  5. Neighbor push repositions icons; if the ideal pack is wider than the
    //     section, positions are *remapped* into the host (gaps shrink), scales stay.
    //  6. mag/push track targets via SmoothedAnimation (no Spring.restart).
    //  7. Section clip is a hard fence against bleeding into minimized/tools.
    //
    // Returns { scales:[], pushX:[], packedW } or null.
    function computeSectionWave(cursor, count, slotW, restTotal, hostLeft, hostRight) {
        if (count <= 0)
            return null;
        var hostW = Math.max(1, hostRight - hostLeft);
        var scales = [];
        var widths = [];
        var i;
        var active = dockWaveActive() && cursor > -9999;
        for (i = 0; i < count; i++) {
            var restC = i * (slotW + dockItemSpacing) + slotW / 2;
            var s = active ? Motion.dockCosineScale(cursor - restC, dockIconSize) : 1.0;
            scales.push(s);
            // Visual footprint uses icon size (what actually paints), not slot width.
            // Slot stays rest-sized for hit testing.
            widths.push(dockIconSize * s);
        }
        if (!active) {
            var zeros = [];
            for (i = 0; i < count; i++)
                zeros.push(0);
            return { scales: scales, pushX: zeros, packedW: restTotal };
        }

        // Ideal pack of visual footprints with rest spacing between slots.
        // Use rest slot spacing geometry for centers, then offset by push.
        // Simpler macOS-like model: rest centers fixed for scale; push from
        // packed slot-widths (slotW * scale) so neighbors make room.
        var packW = [];
        for (i = 0; i < count; i++)
            packW.push(slotW * scales[i]);
        var lefts = [];
        var x = 0;
        for (i = 0; i < count; i++) {
            lefts.push(x);
            x += packW[i] + dockItemSpacing;
        }
        var packedW = count > 0 ? (x - dockItemSpacing) : 0;

        function restToPacked(restX) {
            var step = slotW + dockItemSpacing;
            if (restX <= 0)
                return 0;
            if (restX >= restTotal)
                return packedW;
            for (var j = 0; j < count; j++) {
                var rl = j * step;
                var rr = rl + slotW;
                if (restX < rl) {
                    var gapStart = rl - dockItemSpacing;
                    var t = dockItemSpacing > 0 ? (restX - gapStart) / dockItemSpacing : 0;
                    var prevR = j === 0 ? 0 : lefts[j - 1] + packW[j - 1];
                    return prevR + t * dockItemSpacing;
                }
                if (restX <= rr || j === count - 1) {
                    var u = (restX - rl) / Math.max(1, slotW);
                    return lefts[j] + u * packW[j];
                }
            }
            return packedW;
        }

        // Cursor-centering shift in ideal pack space.
        var shift = cursor - restToPacked(cursor);
        var packStart = shift;
        var packEnd = shift + packedW;

        // Remap ideal centers into host so the pack always fits.
        // Linear map [packStart, packEnd] → [hostLeft, hostRight] when overflowing;
        // otherwise just clamp the shift.
        var pushX = [];
        for (i = 0; i < count; i++) {
            var idealCenter = lefts[i] + packW[i] / 2 + shift;
            var finalCenter;
            if (packedW <= hostW + 0.5) {
                // Fits: keep cursor-centered shift, clamp whole pack into host.
                var s2 = shift;
                if (s2 < hostLeft)
                    s2 = hostLeft;
                if (s2 + packedW > hostRight)
                    s2 = hostRight - packedW;
                finalCenter = lefts[i] + packW[i] / 2 + s2;
            } else {
                // Overflow: stretch/compress pack into host (keeps relative wave).
                var t = packedW > 0 ? (idealCenter - packStart) / packedW : 0;
                finalCenter = hostLeft + t * hostW;
            }
            // Soft fence: allow a little paint into glass padding so edge icons
            // are not squashed flat (macOS lets them hang past the shelf ends).
            // Hard clip is OFF so vertical growth is never cut.
            var half = (dockIconSize * scales[i]) / 2;
            var bleed = dockMagBleedPx;
            var lo = hostLeft + half - bleed;
            var hi = hostRight - half + bleed;
            if (lo > hi)
                finalCenter = (hostLeft + hostRight) / 2;
            else if (finalCenter < lo)
                finalCenter = lo;
            else if (finalCenter > hi)
                finalCenter = hi;
            var restCenter = i * (slotW + dockItemSpacing) + slotW / 2;
            pushX.push(finalCenter - restCenter);
        }
        return { scales: scales, pushX: pushX, packedW: packedW };
    }

    function dockWaveActive() {
        return dockHovered && !pointerDragActive;
    }

    function pinnedRestCenter(index) {
        return index * (dockPinnedButtonWidth + dockItemSpacing) + dockPinnedButtonWidth / 2;
    }

    function pinnedRestX(index) {
        return index * (dockPinnedButtonWidth + dockItemSpacing);
    }

    function pinnedCursorX() {
        if (dockWaveSection !== "pinned")
            return -10000;
        return dockMouseX;
    }

    function pinnedClampLeft() {
        return pinnedViewport ? pinnedViewport.contentX : 0;
    }

    function pinnedClampRight() {
        var host = pinnedDisplayedWidth > 0 ? pinnedDisplayedWidth : pinnedContentWidth;
        return pinnedClampLeft() + host;
    }

    // Explicit deps so QML re-evaluates when cursor / section / counts change.
    readonly property var pinnedWave: {
        var _dep = dockMouseX + pinnedAppCount + (dockHovered ? 1 : 0)
            + (dockWaveSection === "pinned" ? 1 : 0) + (pointerDragActive ? 0 : 1)
            + pinnedDisplayedWidth + (pinnedViewport ? pinnedViewport.contentX : 0);
        if (dockWaveSection !== "pinned" || !dockWaveActive() || pinnedAppCount <= 0)
            return null;
        return computeSectionWave(
            pinnedCursorX(),
            pinnedAppCount,
            dockPinnedButtonWidth,
            pinnedContentWidth,
            pinnedClampLeft(),
            pinnedClampRight()
        );
    }

    function pinnedScaleAt(index) {
        var w = pinnedWave;
        if (!w || index < 0 || index >= w.scales.length)
            return 1.0;
        return w.scales[index];
    }

    function pinnedPushXAt(index) {
        var w = pinnedWave;
        if (!w || index < 0 || index >= w.pushX.length)
            return 0;
        return w.pushX[index];
    }

    function windowRestCenter(index) {
        var w = dockWindowButtonsShowTitle ? dockWindowTitleWidth : dockWindowIconWidth;
        return index * (w + dockItemSpacing) + w / 2;
    }

    function windowRestX(index) {
        var w = dockWindowButtonsShowTitle ? dockWindowTitleWidth : dockWindowIconWidth;
        return index * (w + dockItemSpacing);
    }

    function windowCursorX() {
        if (dockWaveSection !== "window")
            return -10000;
        return dockMouseX;
    }

    function windowClampLeft() {
        return windowViewport ? windowViewport.contentX : 0;
    }

    function windowClampRight() {
        var host = windowViewportWidth > 0 ? windowViewportWidth : activeWindowContentWidth;
        return windowClampLeft() + host;
    }

    readonly property var windowWave: {
        var _dep = dockMouseX + windowButtonCount + (dockHovered ? 1 : 0)
            + (dockWaveSection === "window" ? 1 : 0) + (pointerDragActive ? 0 : 1)
            + windowViewportWidth + (windowViewport ? windowViewport.contentX : 0)
            + (dockWindowButtonsShowTitle ? 4 : 0);
        if (dockWaveSection !== "window" || !dockWaveActive() || dockWindowButtonsShowTitle || windowButtonCount <= 0)
            return null;
        return computeSectionWave(
            windowCursorX(),
            windowButtonCount,
            dockWindowIconWidth,
            iconWindowContentWidth,
            windowClampLeft(),
            windowClampRight()
        );
    }

    function windowScaleAt(index) {
        var w = windowWave;
        if (!w || index < 0 || index >= w.scales.length)
            return 1.0;
        return w.scales[index];
    }

    function windowPushXAt(index) {
        var w = windowWave;
        if (!w || index < 0 || index >= w.pushX.length)
            return 0;
        return w.pushX[index];
    }

    // Glass must never grow with the wave (jitter). These stay at 0.
    function pinnedWaveLeftExtra() { return 0; }
    function windowWaveLeftExtra() { return 0; }
    function dockWaveSurfaceBias() { return 0; }
    function dockWaveLeftExtra() { return 0; }
    function dockWaveRightExtra() { return 0; }
    readonly property real dockWaveLeftExtraPx: 0
    readonly property real dockWaveRightExtraPx: 0
    function syncPinnedViewportToCursor() {}
    function syncWindowViewportToCursor() {}
    function proximityScale(item) { return 1.0; }
    function pinnedItemWidthAt(index) { return dockPinnedButtonWidth; }
    function pinnedItemXAt(index) { return pinnedRestX(index); }
    function windowItemWidthAt(index) {
        return dockWindowButtonsShowTitle ? dockWindowTitleWidth : dockWindowIconWidth;
    }
    function windowItemXAt(index) { return windowRestX(index); }
    function pinnedWaveContentWidth() { return pinnedContentWidth; }
    function windowWaveContentWidth() {
        return dockWindowButtonsShowTitle ? titledWindowContentWidth : iconWindowContentWidth;
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

    // T08-fix8: dockMouseX is REST-section local. Glass never moves with wave.
    function updateDockHover(section, restX) {
        hoverExitTimer.stop();
        root.dockWaveSection = section || "";
        root.dockMouseX = restX;
        dockRevealDebounceTimer.stop();
        root.dockHovered = true;
        root.pointerDragActive = false;
    }

    // Resolve section from dockRow-local coordinates (Row lays out rest slots).
    function resolveWaveFromDockRow(rowX) {
        if (pinnedSectionHost && pinnedSectionHost.width > 0) {
            var px = pinnedSectionHost.x;
            if (rowX >= px - 4 && rowX < px + pinnedSectionHost.width + 4) {
                return { section: "pinned", x: rowX - px + (pinnedViewport ? pinnedViewport.contentX : 0) };
            }
        }
        if (windowSectionHost && windowSectionHost.visible && windowSectionHost.width > 0) {
            var wx = windowSectionHost.x;
            if (rowX >= wx - 4 && rowX < wx + windowSectionHost.width + 4) {
                return { section: "window", x: rowX - wx + (windowViewport ? windowViewport.contentX : 0) };
            }
        }
        return { section: "", x: -10000 };
    }

    function updateDockHoverFromItem(item, localX, localY, buttons) {
        if (buttons !== Qt.NoButton) {
            root.pointerDragActive = true;
            root.resetDockHover();
            return;
        }
        if (!item || !dockRow)
            return;
        // dockSurface is a real QQuickItem and is rest-stable (fix8). Map into
        // dockRow which is also rest-stable (centerIn surface, no wave offset).
        var p = item.mapToItem(dockRow, localX, localY !== undefined ? localY : 0);
        var hit = root.resolveWaveFromDockRow(p.x);
        root.updateDockHover(hit.section, hit.x);
    }

    // Pinned icon: local coords are already in the rest slot (slots never move).
    function updatePinnedHoverFromIcon(button, localX, localY, buttons) {
        if (buttons !== Qt.NoButton) {
            root.pointerDragActive = true;
            root.resetDockHover();
            return;
        }
        if (!button)
            return;
        var restX = button.x + localX + (pinnedViewport ? pinnedViewport.contentX : 0);
        root.updateDockHover("pinned", restX);
    }

    function updateWindowHoverFromButton(button, localX, localY, buttons) {
        if (buttons !== Qt.NoButton) {
            root.pointerDragActive = true;
            root.resetDockHover();
            return;
        }
        if (!button)
            return;
        var restX = button.x + localX + (windowViewport ? windowViewport.contentX : 0);
        root.updateDockHover("window", restX);
    }

    function seedWaveFromSurfaceHover() {
        if (!dockChrome || !dockSurfaceHover.hovered || !dockRow)
            return;
        var sx = dockSurfaceHover.point.position.x;
        var sy = dockSurfaceHover.point.position.y;
        var p = dockChrome.mapToItem(dockRow, sx, sy);
        var hit = root.resolveWaveFromDockRow(p.x);
        root.updateDockHover(hit.section, hit.x);
    }

    function updateDockHoverFromButtons(x, buttons) {
        if (buttons !== Qt.NoButton) {
            root.pointerDragActive = true;
            root.resetDockHover();
            return;
        }
        root.updateDockHover(root.dockWaveSection || "window", x);
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
        // Still over glass (HoverHandler covers children) → keep revealed.
        if (dockSurfaceHover.hovered)
            return;
        root.dockHovered = false;
        root.dockMouseX = -10000;
        root.dockWaveSection = "";
        root.clearDockHoverLabel();
        if (pinnedViewport)
            pinnedViewport.contentX = 0;
        if (windowViewport)
            windowViewport.contentX = 0;
    }

    // Place the name capsule fully above the (possibly magnified) icon.
    // Bottom-origin scale grows upward by iconSize*(mag−1); a fixed -30px
    // offset sits inside that growth and the label looks "stuck in" the icon.
    function hoverLabelYForItem(item, yOffset) {
        if (!item || !dockChrome)
            return -28;
        // Map icon top-center into chrome; bottom-origin mag rises above that.
        var top = item.mapToItem(dockChrome, item.width / 2, 0);
        var mag = 1.0;
        if (item.magnification !== undefined)
            mag = Number(item.magnification) || 1.0;
        else if (item.magnificationTarget !== undefined)
            mag = Number(item.magnificationTarget) || 1.0;
        var magRise = root.dockIconSize * Math.max(0, mag - 1.0);
        var gap = 10;
        var labelH = 26;
        // Icon visual top in chrome coords.
        var iconTop = top.y - magRise;
        var y = Math.round(iconTop - gap - labelH);
        // Keep capsule inside chrome headroom (not under top of panel).
        if (y < 2)
            y = 2;
        return y;
    }

    function showDockHoverLabel(text, item, yOffset) {
        if (!item || !dockChrome)
            return;
        var label = String(text || "");
        if (label.length === 0) {
            root.clearDockHoverLabel();
            return;
        }
        var center = item.mapToItem(dockChrome, item.width / 2, 0);
        root.dockHoverLabelText = label;
        root.dockHoverLabelCenterX = center.x;
        root.dockHoverLabelY = root.hoverLabelYForItem(item, yOffset);
        root.dockHoverLabelVisible = true;
    }

    function updateDockHoverLabelGeometry(item, yOffset) {
        if (!item || !dockChrome || !root.dockHoverLabelVisible)
            return;
        var center = item.mapToItem(dockChrome, item.width / 2, 0);
        root.dockHoverLabelCenterX = center.x;
        root.dockHoverLabelY = root.hoverLabelYForItem(item, yOffset);
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
        // Grace for icon→icon gaps. Autohide uses at least 320ms so a slow
        // cross of spacing does not drop the panel (T08-fix5).
        interval: root.dockAutoHide ? Math.max(320, root.dockHideDelay) : 160
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
    // Tall layer: glass sits at the bottom; headroom above is empty (no fill)
    // so peak-mag icons can paint without a second "floating" bar.
    implicitHeight: dockSurfaceHeight + dockMagHeadroom
    color: "transparent"
    WlrLayershell.namespace: "tahoe-dock"

    mask: Region {
        // Full chrome hit target (glass + headroom for mag/label). Transparent.
        Region {
            x: Math.round(dockChrome.x)
            y: Math.round(root.height - dockChrome.height + root.dockSlideOffset)
            width: dockChrome.width
            height: (!root.dockHidden || root.dockVisibleAmount > 0.001)
                ? Math.round(Math.min(dockChrome.height, root.dockVisibleHeight + root.dockMagHeadroom))
                : 0
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
        id: revealMouse
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

    // T08-fix12: glass and chrome are SIBLINGS.
    // GlassPanel only paints the rounded shelf (fill + compositor glass).
    // Icons/labels live in dockChrome ABOVE the glass so they never composite
    // inside the glass surface (which looked like a rectangular translucent plate).
    Item {
        id: dockChrome

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        width: root.dockChromeTargetWidth
        // Taller than glass: rest shelf + headroom for mag + name capsule.
        height: root.dockSurfaceHeight + root.dockMagHeadroom
        opacity: 1 - root.fullscreenTransition
        // Never clip — icons/labels may occupy the headroom band.
        clip: false

        Behavior on width {
            NumberAnimation {
                duration: Motion.elementResize(root.settingsService)
                easing.type: Motion.emphasizedDecel
            }
        }

        transform: Translate {
            y: root.dockSlideOffset
        }

        GlassPanel {
            id: dockSurface

            // Glass shelf only — REST size, bottom of chrome.
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.dockSurfaceHeight
            // Clip QML fill/stroke to rounded rect (no child icons here anyway).
            clip: true
            material: GlassStyle.MaterialDock
            radius: GlassStyle.RadiusDock
            fillColor: root.glassFill
            strokeColor: root.glassStroke
            // MUST stay true — false draws unclipped rectangular blur sample.
            glassClip: true
            // Dock shelf does not need a separate drop-shadow plate above.
            shadow: false
            useItemRegion: false
            // Region in PanelWindow coords: glass sits at bottom of layer.
            regionX: Math.round(dockChrome.x)
            regionY: Math.round(root.height - root.dockVisibleHeight)
            regionWidth: Math.round(dockChrome.width)
            regionHeight: Math.round(root.dockVisibleHeight)
            // Quantize so spring settle noise does not republish glass every frame.
            interaction: Math.round(root.dockGlassInteraction * 50) / 50
            materialAlpha: 1.0 - root.fullscreenTransition
            glassEnabled: root.dockGlassActive && root.dockVisibleHeight > 0.5 && root.fullscreenTransition < 0.99
        }

        // Hover over glass + headroom band.
        HoverHandler {
            id: dockSurfaceHover
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onHoveredChanged: {
                if (dockSurfaceHover.hovered) {
                    root.markDockHovered();
                    root.seedWaveFromSurfaceHover();
                } else {
                    root.scheduleDockHoverReset();
                }
            }
        }

        MouseArea {
            id: dockSurfaceMouse
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onPositionChanged: function(mouse) {
                root.updateDockHoverFromItem(
                    dockSurfaceMouse,
                    mouse.x,
                    mouse.y,
                    mouse.buttons !== undefined ? mouse.buttons : Qt.NoButton
                );
            }
            onEntered: root.markDockHovered()
        }

        property real _hoverLocalX: dockSurfaceHover.point.position.x
        property real _hoverLocalY: dockSurfaceHover.point.position.y
        on_HoverLocalXChanged: if (dockSurfaceHover.hovered) root.seedWaveFromSurfaceHover()
        on_HoverLocalYChanged: if (dockSurfaceHover.hovered) root.seedWaveFromSurfaceHover()

        Row {
            id: dockRow
            // Sit on the glass midline (bottom of chrome = glass bottom).
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.max(0, Math.round((root.dockSurfaceHeight - root.dockPinnedRowHeight) / 2))
            // Optional sections own animated spacer widths. Row.spacing would
            // otherwise appear/disappear in a single frame when visible flips.
            spacing: 0
            height: root.dockPinnedRowHeight
            transform: Translate {
                y: root.fullscreenTransition * root.dockSurfaceHeight
            }

            Item {
                id: pinnedSectionHost
                width: root.pinnedDisplayedWidth
                height: root.dockPinnedRowHeight
                // Allow mag to paint above this host into the panel headroom.
                clip: false

                Behavior on width {
                    NumberAnimation {
                        duration: Motion.elementResize(root.settingsService)
                        easing.type: Motion.emphasizedDecel
                    }
                }

                // Flickable only for REST overflow. contentWidth is rest-sized
                // forever — never wave-driven. Clip ONLY when scrolling.
                Flickable {
                    id: pinnedViewport
                    anchors.fill: parent
                    // Extra top margin so bottom-origin scale is not clipped by
                    // the Flickable itself when clip is forced by overflow.
                    topMargin: 0
                    contentWidth: root.pinnedContentWidth
                    contentHeight: height
                    clip: contentWidth > width + 1
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    interactive: contentWidth > width + 1

                    Item {
                        id: pinnedRow

                        y: 0
                        width: root.pinnedContentWidth
                        height: root.dockPinnedRowHeight
                        implicitWidth: width

                        Repeater {
                            model: ScriptModel {
                                objectProp: "modelKey"
                                values: root.dockPinnedEntries
                            }

                            delegate: Item {
                                id: pinnedButton

                                required property var modelData
                                required property int index
                                // pressScale still uses Behavior (single) via Motion press token.
                                property real pressScale: Motion.pressScaleFor(root.settingsService, iconMouse.pressed && !pinnedButton.reorderActive)
                                readonly property int pinnedIndex: pinnedButton.index
                                readonly property var pinnedApp: modelData ? modelData.app : null
                                readonly property string appId: modelData ? String(modelData.modelKey || "") : ""
                                readonly property var appModel: root.appsService ? root.appsService.resolveApplication(pinnedButton.appId, pinnedButton.pinnedApp) : pinnedButton.pinnedApp
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

                                // T08-fix7: rest slot layout is immutable.
                                x: root.pinnedRestX(pinnedButton.index)
                                width: root.dockPinnedButtonWidth

                                Behavior on x {
                                    NumberAnimation {
                                        duration: Motion.elementMove(root.settingsService)
                                        easing.type: Motion.emphasizedDecel
                                    }
                                }

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
                                    // T08-fix7: visual push only — layout slot stays put.
                                    transform: Translate {
                                        x: pinnedButton.pushX
                                    }

                                    Behavior on opacity {
                                        NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing }
                                    }
                                }

                                Behavior on pressScale {
                                    NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing }
                                }

                                Rectangle {
                                    id: runningDot
                                    // T08-fix5: small clean macOS-style running indicator
                                    // (no glow halo). Centered under the (possibly pushed) icon.
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.horizontalCenterOffset: pinnedButton.pushX
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 2
                                    width: (pinnedButton.running || pinnedButton.launching) ? 4 : 0
                                    height: 4
                                    radius: 2
                                    color: pinnedButton.launching && !pinnedButton.running
                                        ? (root.darkMode ? "#80ffffff" : "#66000000")
                                        : (root.darkMode ? "#e6ffffff" : "#cc000000")
                                    opacity: width > 0 ? 1 : 0
                                    Behavior on width {
                                        NumberAnimation { duration: Motion.elementResize(root.settingsService); easing.type: Motion.emphasizedDecel }
                                    }
                                    Behavior on color {
                                        ColorAnimation { duration: Motion.fadeFast(root.settingsService) }
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
                                        // Rest-slot local → section rest x (slots never move).
                                        root.updatePinnedHoverFromIcon(
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
                                        root.updatePinnedHoverFromIcon(
                                            pinnedButton,
                                            iconMouse.mouseX,
                                            iconMouse.mouseY,
                                            Qt.NoButton
                                        );
                                    }
                                    onExited: {
                                        // Only clear the label. Do NOT schedule hide —
                                        // icon→icon moves fire onExited and would kill
                                        // the wave / autohide mid-hover (T08-fix5).
                                        root.clearDockHoverLabel();
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

                                // T08-fix9: mag/push follow analytical targets with
                                // SmoothedAnimation (duration-based). Continuous retarget
                                // blends mid-sweep; Spring.restart() / short OutCubic
                                // NumberAnimation both felt fast or choppy.
                                // Slot x/width remain immutable rest geometry.
                                readonly property real magnificationTarget: {
                                    var _w = root.pinnedWave;
                                    return root.pinnedScaleAt(pinnedButton.index);
                                }
                                readonly property real pushXTarget: {
                                    var _w = root.pinnedWave;
                                    return root.pinnedPushXAt(pinnedButton.index);
                                }
                                // Bind to targets; Behavior retargets. Avoid
                                // on*TargetChanged assignment (interceptor WARN).
                                property real magnification: magnificationTarget
                                property real pushX: pushXTarget
                                // Keep name capsule above the growing icon while mag settles.
                                onMagnificationChanged: {
                                    if (pinnedButton.hovered && root.dockHoverLabelVisible) {
                                        var label = root.appsService
                                            ? root.appsService.appLabel(pinnedButton.appModel || pinnedButton.appId)
                                            : "";
                                        if (label.length > 0)
                                            root.showDockHoverLabel(label, pinnedButton, -34);
                                    }
                                }

                                Behavior on magnification {
                                    enabled: !Motion.reducedMotion(root.settingsService)
                                    SmoothedAnimation {
                                        duration: Motion.dockMagFollowMs
                                        velocity: -1
                                        easing.type: Easing.InOutQuad
                                    }
                                }
                                Behavior on pushX {
                                    enabled: !Motion.reducedMotion(root.settingsService)
                                    SmoothedAnimation {
                                        duration: Motion.dockMagFollowMs
                                        velocity: -1
                                        easing.type: Easing.InOutQuad
                                    }
                                }

                                Component.onDestruction: pinnedButton.stopLaunchBounce()

                                // ── Click bounce (single hop, R01 #75) ─────────────
                                // Animated InQuad up leg (aligned with the launch
                                // loop parabola), dual-branch spring/ease down leg.
                                function bounce() {
                                    if (pinnedButton.launching)
                                        return;
                                    bounceSpring.stop();
                                    bounceEase.stop();
                                    bounceUp.stop();
                                    launchBounceLoop.stop();
                                    if (Motion.reducedMotion(root.settingsService)) {
                                        // Single hop: instant up, eased settle.
                                        pinnedButton.bounceOffset = Motion.dockClickBounceHeightPx;
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

                                NumberAnimation {
                                    id: bounceUp
                                    target: pinnedButton
                                    property: "bounceOffset"
                                    to: Motion.dockClickBounceHeightPx
                                    duration: Motion.dockClickBounceUpMs
                                    easing.type: Easing.InQuad
                                    onFinished: pinnedButton.animateBounceTo(0)
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
                                    duration: Motion.dockClickBounceDownMs
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
                                    bounceUp.stop();
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
                                    bounceUp.stop();
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

            Item {
                width: root.dockItemSpacing
                height: root.dockPinnedRowHeight
            }

            Item {
                id: windowDividerHost
                // Separator host: same row height so Row vertical align stays flat.
                width: root.hasDockWindowSection ? root.dockSeparatorWidth : 0
                height: root.dockPinnedRowHeight
                visible: width > 0

                Behavior on width {
                    NumberAnimation {
                        duration: Motion.elementResize(root.settingsService)
                        easing.type: Motion.emphasizedDecel
                    }
                }

                Rectangle {
                    width: 1
                    height: root.dockIconSize
                    radius: 1
                    anchors.centerIn: parent
                    color: root.darkMode ? "#40ffffff" : "#3d000000"
                }
            }

            Item {
                id: windowDividerTrailingSpacer
                width: root.hasDockWindowSection ? root.dockItemSpacing : 0
                height: root.dockPinnedRowHeight

                Behavior on width {
                    NumberAnimation {
                        duration: Motion.elementResize(root.settingsService)
                        easing.type: Motion.emphasizedDecel
                    }
                }
            }

            Item {
                id: windowSectionHost
                width: root.windowViewportWidth
                // REST height only — center the window row inside pinned row height.
                height: root.dockPinnedRowHeight
                visible: width > 0
                clip: false

                Behavior on width {
                    NumberAnimation {
                        duration: Motion.elementResize(root.settingsService)
                        easing.type: Motion.emphasizedDecel
                    }
                }

                // Rest overflow scroll only (see pinnedViewport). Wave is visual.
                Flickable {
                    id: windowViewport
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: root.dockWindowRowHeight
                    contentWidth: root.activeWindowContentWidth
                    contentHeight: height
                    clip: contentWidth > width + 1
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    interactive: contentWidth > width + 1

                    Item {
                        id: windowRow

                        y: 0
                        width: root.activeWindowContentWidth
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
                                // T08-fix7: rest slot geometry is fixed; wave is pushX + scale.
                                slotWidthTarget: root.dockWindowButtonsShowTitle
                                    ? root.dockWindowTitleWidth
                                    : root.dockWindowIconWidth
                                slotXTarget: root.windowRestX(windowButton.index)
                                magnificationTarget: root.windowScaleAt(windowButton.index)
                                pushXTarget: root.windowPushXAt(windowButton.index)
                                hoverLabelEnabled: false
                                labelClipItem: windowViewport
                                labelClipContentX: windowViewport.contentX
                                dockWindow: root
                                dockSurfaceItem: dockSurface
                                dockSlideOffset: root.dockSlideOffset
                                dockFullscreenOffset: root.fullscreenTransition * root.dockSurfaceHeight
                                dockFullscreenActive: root.fullscreenActive
                                dockSceneOffsetX: root.windowSectionSceneOffsetX
                                dockSceneOffsetY: root.windowSectionSceneOffsetY
                                onDockPointerMoved: function(localX, buttons) {
                                    root.updateWindowHoverLabelGeometry(windowButton);
                                    // localX is rest-slot local from WindowButton (T08-fix7).
                                    root.updateWindowHoverFromButton(
                                        windowButton,
                                        localX,
                                        windowButton.height / 2,
                                        buttons === undefined ? Qt.NoButton : buttons
                                    );
                                }
                                onDockPointerEntered: {
                                    root.showWindowHoverLabel(windowButton);
                                    root.markDockHovered();
                                    root.updateWindowHoverFromButton(
                                        windowButton,
                                        windowButton.width / 2,
                                        windowButton.height / 2,
                                        Qt.NoButton
                                    );
                                }
                                onDockPointerExited: {
                                    // Label only — hide is owned by surface HoverHandler.
                                    root.clearWindowHoverLabel(windowButton);
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

            Item {
                id: windowMinimizedSpacer
                width: root.hasNonMinimizedWindows && root.hasMinimizedWindows ? root.dockItemSpacing : 0
                height: root.dockPinnedRowHeight

                Behavior on width {
                    NumberAnimation {
                        duration: Motion.elementResize(root.settingsService)
                        easing.type: Motion.emphasizedDecel
                    }
                }
            }

            Item {
                id: minimizedSectionHost
                width: root.minimizedViewportWidth
                height: root.dockPinnedRowHeight
                visible: width > 0
                clip: false

                Behavior on width {
                    NumberAnimation {
                        duration: Motion.elementResize(root.settingsService)
                        easing.type: Motion.emphasizedDecel
                    }
                }

                DockMinimizedShelf {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: root.dockWindowRowHeight
                    windowsService: root.niriService
                    thumbnailProvider: root.thumbnailProvider
                    appsService: root.appsService
                    settingsService: root.settingsService
                    useSpring: root.useSpring
                    dockWindow: root
                    dockSurfaceItem: dockSurface
                    dockSlideOffset: root.dockSlideOffset
                    thumbnailWidth: root.dockMinimizedThumbnailWidth
                    onDockPointerMoved: function(x, buttons) {
                        // Minimized shelf is outside the mag wave; keep dock revealed only.
                        if (buttons !== undefined && buttons !== Qt.NoButton)
                            return;
                        root.markDockHovered();
                        root.dockWaveSection = "";
                        root.dockMouseX = -10000;
                    }
                    onDockPointerEntered: {
                        root.markDockHovered();
                        root.dockWaveSection = "";
                        root.dockMouseX = -10000;
                    }
                    onDockPointerExited: {
                        // Surface HoverHandler owns hide (T08-fix5).
                    }
                    onContextMenuRequested: function(window, anchorItem) {
                        root.openWindowMenu(window, root.anchorRectFor(anchorItem));
                        root.markDockHovered();
                    }
                }
            }

            Item {
                id: windowSectionTrailingSpacer
                width: root.hasDockWindowSection ? root.dockItemSpacing : 0
                height: root.dockPinnedRowHeight

                Behavior on width {
                    NumberAnimation {
                        duration: Motion.elementResize(root.settingsService)
                        easing.type: Motion.emphasizedDecel
                    }
                }
            }

            Item {
                width: root.dockSeparatorWidth
                height: root.dockPinnedRowHeight
                Rectangle {
                    width: 1
                    height: root.dockIconSize
                    radius: 1
                    anchors.centerIn: parent
                    color: root.darkMode ? "#40ffffff" : "#3d000000"
                }
            }

            Item {
                width: root.dockItemSpacing
                height: root.dockPinnedRowHeight
            }

            DockToolButton {
                iconSource: root.appsService ? root.appsService.iconPath("dock", "downloads.png") : ""
                label: "下载"
                onActivated: root.openDownloads()
            }

            Item {
                width: root.dockItemSpacing
                height: root.dockPinnedRowHeight
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
        } // dockRow

        // Name capsule lives in chrome (not inside GlassPanel) so it never
        // sits under/inside glass sampling. Y is in chrome coords: glass top
        // is at y=dockMagHeadroom, labels sit above the magnified icon.
        Rectangle {
            id: dockHoverLabel

            readonly property real labelMaxWidth: Math.max(48, Math.min(280, dockChrome.width - 12))

            z: 100
            x: Math.max(6, Math.min(dockChrome.width - width - 6, root.dockHoverLabelCenterX - width / 2))
            y: root.dockHoverLabelY
            width: Math.min(Math.max(dockHoverLabelTextItem.implicitWidth + 18, 48), labelMaxWidth)
            height: 26
            radius: 7
            color: "#e6f7f8fb"
            border.color: "#90ffffff"
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

            Behavior on x {
                NumberAnimation { duration: Motion.elementMove(root.settingsService); easing.type: Motion.emphasizedDecel }
            }

            Behavior on y {
                NumberAnimation { duration: Motion.elementMove(root.settingsService); easing.type: Motion.emphasizedDecel }
            }
        }
    } // dockChrome

    component DockToolButton: Item {
        id: tool

        property string iconSource: ""
        property string label: ""
        property bool acceptsTrashDrop: false

        signal activated()
        signal urlsDropped(var urls)

        // Same height as pinned row so Row never lifts tools above the glass.
        width: root.dockToolButtonWidth
        height: root.dockPinnedRowHeight
        scale: Motion.pressScaleFor(root.settingsService, toolMouse.pressed)
        opacity: toolMouse.pressed ? 0.75 : 1

        Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
        Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 6
            height: parent.width - 6
            radius: 16
            color: toolMouse.containsMouse ? "#30ffffff" : "transparent"
            border.color: "transparent"
        }

        Image {
            anchors.centerIn: parent
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
                // Tools are outside the mag wave.
                root.dockWaveSection = "";
                root.dockMouseX = -10000;
            }
            onPositionChanged: function(mouse) {
                root.markDockHovered();
                root.dockWaveSection = "";
                root.dockMouseX = -10000;
                if (toolMouse.containsMouse)
                    root.showDockHoverLabel(tool.label, tool, -34);
            }
            onExited: {
                root.clearDockHoverLabel();
            }
            onClicked: tool.activated()
        }
    }
}
