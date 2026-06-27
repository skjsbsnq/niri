pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property var appsService
    property var niriService
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
    property real dockSlideOffset: dockHidden ? 88 : 0
    readonly property real dockVisibleAmount: 1 - Math.min(1, Math.max(0, dockSlideOffset / 88))
    readonly property int dockOuterMargin: 28
    readonly property int dockSurfacePadding: 34
    readonly property int dockItemSpacing: 8
    readonly property int dockPinnedButtonWidth: 62
    readonly property int dockWindowTitleWidth: 132
    readonly property int dockWindowIconWidth: 56
    readonly property int dockMinimizedThumbnailWidth: 112
    readonly property int dockMinimizedMinimumWidth: 76
    readonly property int dockToolButtonWidth: 54
    readonly property int dockSeparatorWidth: 1
    readonly property int dockIconSourceSize: 96
    readonly property int dockToolIconSourceSize: 96
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
    readonly property int dockRemainingFlexibleWidth: Math.max(0, dockFlexibleSectionsBudget - pinnedViewportWidth)
    readonly property int availableWindowViewportWidth: hasNonMinimizedWindows ? Math.max(0, dockRemainingFlexibleWidth - minimumMinimizedViewportWidth) : 0
    readonly property bool dockWindowButtonsShowTitle: hasNonMinimizedWindows
        && !(settingsService && settingsService.dockForceIconOnly)
        && titledWindowContentWidth <= availableWindowViewportWidth
    readonly property int activeWindowContentWidth: dockWindowButtonsShowTitle ? titledWindowContentWidth : iconWindowContentWidth
    readonly property int windowViewportWidth: hasNonMinimizedWindows ? Math.min(activeWindowContentWidth, availableWindowViewportWidth) : 0
    readonly property int availableMinimizedViewportWidth: hasMinimizedWindows ? Math.max(0, dockRemainingFlexibleWidth - windowViewportWidth) : 0
    readonly property int minimizedViewportWidth: hasMinimizedWindows ? Math.min(minimizedWindowContentWidth, availableMinimizedViewportWidth) : 0
    readonly property color glassFill: darkMode ? "#d01d1f24" : GlassStyle.FillDock
    readonly property color glassStroke: darkMode ? "#38ffffff" : GlassStyle.StrokeDock
    readonly property color dockText: darkMode ? "#f5f7fb" : "#202124"

    signal toggleLaunchpad()
    signal openPinnedAppMenu(var app, string appId, var anchorRect)
    signal openWindowMenu(var window, var anchorRect)

    visible: true

    // Spring-smoothed dock magnification.
    //
    // This returns the *target* scale for an icon given the pointer
    // position. The actual magnification property on each delegate has a
    // SpringAnimation Behavior (see the delegate), so the icon eases toward
    // this target every frame instead of snapping. The web dock does the
    // same thing with requestAnimationFrame + exponential lerp (script.js
    // 358-404); here the spring plays the role of the lerp.
    //
    // Range ~135px (web uses 195), peak scale 1.34. This keeps the wave
    // visible without pushing icons into the dock viewport clip.
    function proximityScale(item) {
        if (pointerDragActive || !dockHovered || !item || !dockSurface)
            return 1.0;

        var point = item.mapToItem(dockSurface, item.width / 2, item.height / 2);
        var distance = Math.abs(dockMouseX - point.x);
        var influence = Math.max(0, 1 - distance / 135);
        return 1.0 + influence * 0.34;
    }

    function markDockHovered() {
        hoverExitTimer.stop();
        root.dockHovered = true;
    }

    function updateDockHover(x) {
        hoverExitTimer.stop();
        root.dockMouseX = x;
        root.dockHovered = true;
        root.pointerDragActive = false;
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
        hoverExitTimer.restart();
    }

    function resetDockHover() {
        hoverExitTimer.stop();
        root.dockHovered = false;
        root.dockMouseX = -10000;
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

    anchors {
        left: true
        right: true
        bottom: true
    }

    exclusiveZone: 98
    exclusionMode: dockAutoHide ? ExclusionMode.Ignore : ExclusionMode.Normal
    implicitHeight: 132
    color: "transparent"
    WlrLayershell.namespace: "tahoe-dock"

    mask: Region {
        Region {
            x: Math.round(dockSurface.x)
            y: Math.round(root.height - dockSurface.height + root.dockSlideOffset)
            width: dockSurface.width
            height: (!root.dockHidden || root.dockVisibleAmount > 0.001) ? dockSurface.height : 0
            radius: dockSurface.radius
        }

        Region {
            x: 0
            y: Math.max(0, root.height - root.dockRevealZoneHeight)
            width: root.width
            height: root.dockAutoHide ? Math.max(2, root.dockRevealZoneHeight) : 0
        }
    }

    TahoeGlass.regions: [
        TahoeGlassRegion {
            x: Math.round(dockSurface.x)
            y: Math.round(root.height - dockSurface.height + root.dockSlideOffset)
            width: Math.round(dockSurface.width)
            height: Math.round(dockSurface.height)
            material: dockSurface.tahoeGlassMaterial
            radius: dockSurface.tahoeGlassRadius
            blur: true
            shadow: true
            clip: true
            interaction: 0.0
            materialAlpha: 1.0
            enabled: !root.dockHidden || root.dockVisibleAmount > 0.001
        }
    ]

    Behavior on dockSlideOffset {
        NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
    }

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

    Rectangle {
        id: dockSurface
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialDock
        readonly property real tahoeGlassRadius: GlassStyle.RadiusDock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        width: Math.min(root.dockSurfaceMaxWidth, dockRow.implicitWidth + root.dockSurfacePadding)
        height: 84
        radius: tahoeGlassRadius
        color: root.glassFill

        transform: Translate {
            y: root.dockSlideOffset
        }

        // NOTE: no `border.width` on the surface itself — a centered 1px
        // border antialiased against the outside pixels produces faint
        // near-square corners at the arc tangents. Draw the glass edges
        // with inset Rectangles instead, whose borders sit fully inside.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onPositionChanged: function(mouse) {
                root.updateDockHoverFromMouse(mouse.x, mouse);
            }
            onEntered: root.markDockHovered()
            onExited: root.scheduleDockHoverReset()
        }

        Rectangle {
            // Top-left light edge (the Tahoe glass highlight).
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: root.glassStroke
            border.width: 1
        }

        Row {
            id: dockRow
            anchors.centerIn: parent
            spacing: root.dockItemSpacing

            Item {
                width: root.pinnedViewportWidth
                height: 70

                Flickable {
                    id: pinnedViewport

                    x: 0
                    y: -34
                    width: parent.width
                    height: parent.height + 34
                    contentWidth: pinnedRow.implicitWidth
                    contentHeight: height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick

                    Row {
                        id: pinnedRow

                        y: 34
                        spacing: root.dockItemSpacing

                        Repeater {
                            model: ScriptModel {
                                values: root.appsService ? root.appsService.pinnedApps : []
                            }

                            delegate: Item {
                                id: pinnedButton

                                required property var modelData
                                required property int index
                                // Magnification tracks the pointer position via
                                // proximityScale(); the SpringAnimation Behavior below
                                // eases it toward that target every frame, so neighbors
                                // couple into a wave instead of snapping. This mirrors
                                // the web dock's requestAnimationFrame + exponential
                                // lerp (script.js 358-404) — the spring plays the lerp.
                                // Kept writable (not readonly) so the Behavior reliably
                                // intercepts binding updates.
                                property real magnification: root.proximityScale(pinnedButton)
                                readonly property int pinnedIndex: pinnedButton.index
                                readonly property string appId: root.appsService ? root.appsService.pinnedIdForVisualIndex(pinnedButton.pinnedIndex, modelData) : ""
                                readonly property var appModel: root.appsService ? root.appsService.resolveApplication(pinnedButton.appId, modelData) : modelData
                                property real bounceOffset: 0
                                property bool suppressNextClick: false
                                readonly property bool hovered: !root.pointerDragActive && iconMouse.containsMouse
                                readonly property bool running: (!appModel || appModel.shellAction !== "launchpad")
                                    && root.appsService
                                    && root.niriService
                                    && root.appsService.appHasRunningWindow(appModel, root.niriService.windowList)
                                readonly property real lift: (magnification - 1.0) * 16 + (hovered ? 2 : 0)

                                // Fixed width. NOTE: width must NOT depend on
                                // magnification — proximityScale() reads this delegate's
                                // geometry to compute the icon center, so a
                                // magnification-driven width creates a binding loop
                                // (width -> magnification -> proximityScale -> width)
                                // that runs away and crashes Quickshell. The wave feel
                                // comes from the icon scale + lift + Row spacing spring
                                // instead.
                                width: root.dockPinnedButtonWidth
                                height: 70

                                property bool reorderPressed: false
                                property bool reorderActive: false
                                property real reorderPressX: 0
                                property real reorderPressY: 0

                                Timer {
                                    id: suppressClickReset
                                    interval: 180
                                    repeat: false
                                    onTriggered: pinnedButton.suppressNextClick = false
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
                                    x: 4
                                    y: 8
                                    width: 54
                                    height: 54
                                    radius: 16
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
                                    y: 9 - pinnedButton.lift - pinnedButton.bounceOffset
                                    width: 46
                                    height: 46
                                    scale: pinnedButton.magnification
                                    opacity: pinnedButton.reorderActive ? 0.58 : 1
                                    source: root.appsService ? root.appsService.iconForApp(pinnedButton.appModel || pinnedButton.appId) : ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: false
                                    sourceSize.width: root.dockIconSourceSize
                                    sourceSize.height: root.dockIconSourceSize
                                    asynchronous: true
                                    transformOrigin: Item.Center
                                }

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    width: pinnedButton.running ? 5 : 0
                                    height: 5
                                    radius: 3
                                    color: "#99000000"
                                }

                                Rectangle {
                                    id: hoverLabel
                                    readonly property real labelMaxWidth: Math.max(42, Math.min(280, pinnedViewport.width - 12))
                                    z: 10
                                    x: Math.max(
                                        pinnedViewport.contentX - pinnedButton.x + 6,
                                        Math.min(
                                            pinnedViewport.contentX + pinnedViewport.width - width - pinnedButton.x - 6,
                                            (pinnedButton.width - width) / 2
                                        )
                                    )
                                    y: pinnedButton.hovered ? -34 : -24
                                    width: Math.min(Math.max(labelText.implicitWidth + 18, 42), labelMaxWidth)
                                    height: 24
                                    radius: 7
                                    color: "#d9f7f8fb"
                                    border.color: "#70ffffff"
                                    opacity: pinnedButton.hovered ? 1 : 0
                                    visible: opacity > 0.01

                                    Text {
                                        id: labelText
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 9
                                        anchors.rightMargin: 9
                                        text: root.appsService ? root.appsService.appLabel(pinnedButton.appModel || pinnedButton.appId) : ""
                                        color: root.dockText
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    Behavior on opacity {
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }

                                    Behavior on y {
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
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

                                        var point = pinnedButton.mapToItem(dockSurface, mouse.x, mouse.y);
                                        root.updateDockHoverFromMouse(point.x, mouse);
                                    }
                                    onEntered: root.markDockHovered()
                                    onExited: root.scheduleDockHoverReset()
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

                                        pinnedButton.bounce();
                                        if (mouse.button === Qt.RightButton) {
                                            if (pinnedButton.appId !== "launchpad")
                                                root.openPinnedAppMenu(pinnedButton.appModel, pinnedButton.appId, root.anchorRectFor(pinnedButton));
                                            root.markDockHovered();
                                            return;
                                        } else if (pinnedButton.appId === "launchpad") {
                                            root.toggleLaunchpad();
                                        } else if (root.appsService) {
                                            root.appsService.launchPinnedApp(pinnedButton.appModel, pinnedButton.appId);
                                        }
                                    }
                                }

                                // Spring bounce on click — kick bounceOffset to an
                                // overshoot then let the Behavior spring below settle
                                // it (1.5 oscillations). A single-shot Timer does the
                                // kick→release so the spring sees a real change.
                                Timer {
                                    id: bounceTimer
                                    interval: 16
                                    repeat: false
                                    onTriggered: pinnedButton.bounceOffset = 0
                                }

                                function bounce() {
                                    pinnedButton.bounceOffset = 14;
                                    bounceTimer.restart();
                                }

                                // Bounce on click. Spring (underdamped, ~1.5 oscillations)
                                // gives the macOS feel but corrupts the icon's Image texture
                                // on VMware/software GPUs while it runs, so it's gated behind
                                // useSpring. The default NumberAnimation is a single safe
                                // tween — no overshoot, but no texture loss on VMs either.
                                Behavior on bounceOffset {
                                    enabled: !root.useSpring
                                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                }
                                Behavior on bounceOffset {
                                    enabled: root.useSpring
                                    SpringAnimation {
                                        spring: 380
                                        damping: 0.32
                                        mass: 0.9
                                        epsilon: 0.01
                                    }
                                }

                                // Magnification easing (icon scale + lift track the pointer).
                                // Same useSpring gate as bounce: spring on real GPUs,
                                // NumberAnimation everywhere else.
                                Behavior on magnification {
                                    enabled: !root.useSpring
                                    NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                                }
                                Behavior on magnification {
                                    enabled: root.useSpring
                                    SpringAnimation {
                                        spring: 260
                                        damping: 1.0
                                        epsilon: 0.01
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: 1
                height: 46
                radius: 1
                color: root.darkMode ? "#40ffffff" : "#3d000000"
                visible: root.hasDockWindowSection
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                width: root.windowViewportWidth
                height: 58
                visible: root.hasNonMinimizedWindows && width > 0

                Flickable {
                    id: windowViewport

                    x: 0
                    y: -30
                    width: parent.width
                    height: parent.height + 30
                    contentWidth: windowRow.implicitWidth
                    contentHeight: height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick

                    Row {
                        id: windowRow

                        y: 30
                        spacing: root.dockItemSpacing

                        Repeater {
                            model: ScriptModel {
                                objectProp: "modelKey"
                                values: root.dockWindowList
                            }

                            delegate: WindowButton {
                                id: windowButton

                                required property var modelData

                                windowModel: modelData
                                toplevel: modelData ? modelData.toplevel : null
                                windowsService: root.niriService
                                appsService: root.appsService
                                useSpring: root.useSpring
                                iconSize: root.dockWindowButtonsShowTitle ? 36 : 38
                                showTitle: root.dockWindowButtonsShowTitle
                                magnification: root.proximityScale(windowButton)
                                labelClipItem: windowViewport
                                labelClipContentX: windowViewport.contentX
                                dockWindow: root
                                dockSurfaceItem: dockSurface
                                onDockPointerMoved: function(x, buttons) {
                                    root.updateDockHoverFromButtons(x, buttons === undefined ? Qt.NoButton : buttons);
                                }
                                onDockPointerEntered: root.markDockHovered()
                                onDockPointerExited: root.scheduleDockHoverReset()
                                onContextMenuRequested: function(window) {
                                    root.openWindowMenu(window, root.anchorRectFor(windowButton));
                                    root.markDockHovered();
                                }
                            }
                        }
                    }
                }
            }

            DockMinimizedShelf {
                width: root.minimizedViewportWidth
                height: 64
                visible: root.hasMinimizedWindows && width > 0
                windowsService: root.niriService
                appsService: root.appsService
                dockWindow: root
                dockSurfaceItem: dockSurface
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
                height: 46
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
    }

    component DockToolButton: Item {
        id: tool

        property string iconSource: ""
        property string label: ""
        property bool acceptsTrashDrop: false

        signal activated()
        signal urlsDropped(var urls)

        width: 54
        height: 64

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 16
            color: toolMouse.containsMouse ? "#30ffffff" : "transparent"
            border.color: toolMouse.containsMouse ? "#40ffffff" : "transparent"
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
        }

        Rectangle {
            id: toolLabel
            readonly property real labelMaxWidth: Math.max(42, Math.min(280, dockSurface.width - 12))
            x: Math.max(
                -tool.mapToItem(dockSurface, 0, 0).x + 6,
                Math.min(
                    dockSurface.width - tool.mapToItem(dockSurface, 0, 0).x - width - 6,
                    (tool.width - width) / 2
                )
            )
            y: toolMouse.containsMouse ? -32 : -22
            width: Math.min(Math.max(toolLabelText.implicitWidth + 18, 42), labelMaxWidth)
            height: 24
            radius: 7
            color: "#d9f7f8fb"
            border.color: "#70ffffff"
            opacity: toolMouse.containsMouse ? 1 : 0
            visible: opacity > 0.01

            Text {
                id: toolLabelText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                text: tool.label
                color: root.dockText
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Behavior on opacity {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            Behavior on y {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
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
            onClicked: tool.activated()
        }
    }
}
