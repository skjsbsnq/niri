pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "Motion.js" as Motion
import "TahoeGlass.js" as GlassStyle
import "settings/SettingsTheme.js" as Theme

// T18 + hand-feel fix: full-screen Launchpad — adaptive 7×5 pages, wallpaper
// zoom (via Wallpaper.qml), unified icon enter, horizontal intent paging
// (short swipe commits; no 50% drag requirement), page dots, arrow keys.
// Category chips removed. Stays on the QML outer animation path (§2.11).
PanelWindow {
    id: root

    property bool open: false
    property var appsService
    property var settingsService
    property bool useSpring: false
    property bool darkMode: false
    property string query: ""
    property int selectedIndex: 0
    property int currentPage: 0
    // Unified grid enter 0→1 (all icons together). Avoid per-icon opacity:0
    // cascade that looked like "one icon, then the rest".
    property real gridEnter: 0
    // Whole-layer presentation 0→1 (opacity + soft settle). Driven explicitly
    // so open/close always animate even when open flips instantly.
    property real layerProgress: 0
    // Launch pop on the tapped icon before closing.
    property int launchingIndex: -1
    property real launchPop: 0
    // Paging: decide at finger-up. Displacement commits first; velocity only
    // for short flicks. Never let a leftover velocity reverse a large drag
    // (the "I already went past and it yanked me back" bug).
    property int pageDragStartPage: 0
    property real pageDragStartX: 0
    property bool pageSnapPending: false
    property real pageReleaseVelocity: 0
    property real pagePeakVelocity: 0
    property bool pageGestureActive: false
    property bool closingForLaunch: false

    readonly property var filteredApps: root.appsService
        ? root.appsService.filteredLaunchpadApps(root.query, "all")
        : []
    readonly property int appCount: filteredApps ? filteredApps.length : 0

    readonly property int screenWidth: Math.max(1, root.numberOr(root.screen && root.screen.width, 1))
    readonly property int screenHeight: Math.max(1, root.numberOr(root.screen && root.screen.height, 1))

    // Grid geometry (adaptive 7×5).
    readonly property int gridCols: Motion.launchpadGridCols
    readonly property int gridRows: Motion.launchpadGridRows
    readonly property int cellsPerPage: gridCols * gridRows
    readonly property int pageCount: Math.max(1, Math.ceil(appCount / Math.max(1, cellsPerPage)))

    readonly property int topChrome: 96
    readonly property int bottomChrome: 48
    readonly property int sidePad: Math.max(48, Math.round(screenWidth * 0.06))
    readonly property int gridWidth: Math.max(280, screenWidth - sidePad * 2)
    readonly property int gridHeight: Math.max(240, screenHeight - topChrome - bottomChrome - 24)
    readonly property int cellWidth: Math.floor(gridWidth / gridCols)
    readonly property int cellHeight: Math.floor(gridHeight / gridRows)
    readonly property int iconSize: Math.max(48, Math.min(72, Math.round(Math.min(cellWidth, cellHeight) * 0.48)))

    readonly property string accentId: settingsService ? settingsService.accentColor : "blue"
    readonly property color accent: Theme.accent(darkMode, accentId)
    readonly property color textPrimary: darkMode ? "#f5f7fb" : "#ffffff"
    readonly property color textSecondary: darkMode ? "#c3ccd6" : "#e8ffffff"
    readonly property color textMuted: darkMode ? "#94a0ad" : "#b8ffffff"

    // Launchpad stays on the QML outer animation path.
    readonly property bool compositorLayerAnimations: false

    signal closeRequested()

    function numberOr(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
    }

    function clampPage(page) {
        return Math.max(0, Math.min(pageCount - 1, Math.round(Number(page) || 0)));
    }

    function goToPage(page, animated) {
        currentPage = clampPage(page);
        var pageW = Math.max(1, pageFlick.width);
        var target = currentPage * pageW;
        var fromX = pageFlick.contentX;
        if (animated === false || Motion.reducedMotion(settingsService)) {
            pageSnapAnim.stop();
            pageFlick.contentX = target;
            pageSnapPending = false;
            pageGestureActive = false;
            return;
        }
        // Already on the page: no-op but clear pending so next gesture works.
        if (Math.abs(fromX - target) < 0.5) {
            pageSnapAnim.stop();
            pageFlick.contentX = target;
            pageSnapPending = false;
            pageGestureActive = false;
            return;
        }
        pageSnapAnim.stop();
        pageSnapAnim.from = fromX;
        pageSnapAnim.to = target;
        pageSnapAnim.duration = Motion.launchpadPageSnapDurationForDistance(
            settingsService, target - fromX, pageW
        );
        // Soft settle after release (tokenized; no inline OutCubic).
        pageSnapAnim.easing.type = Motion.expressiveEffects;
        pageSnapPending = true;
        pageSnapAnim.restart();
    }

    function appAt(index) {
        if (index < 0 || index >= appCount)
            return null;
        return filteredApps[index];
    }

    function requestClose() {
        closingForLaunch = false;
        closeRequested();
    }

    function launchAt(index) {
        var app = appAt(index);
        if (!app || !appsService)
            return;
        selectedIndex = index;
        if (Motion.reducedMotion(settingsService)) {
            appsService.launchApp(app);
            closeRequested();
            return;
        }
        // Pop the icon, then fade the layer out while the app starts.
        launchingIndex = index;
        launchPop = 0;
        launchPopAnim.stop();
        launchPopAnim.from = 0;
        launchPopAnim.to = 1;
        launchPopAnim.duration = Motion.launchpadLaunchPopDuration(settingsService);
        closingForLaunch = true;
        appsService.launchApp(app);
        launchPopAnim.restart();
        launchCloseTimer.restart();
    }

    function launchSelected() {
        launchAt(selectedIndex);
    }

    function pageOfIndex(index) {
        if (cellsPerPage <= 0)
            return 0;
        return Math.floor(Math.max(0, index) / cellsPerPage);
    }

    function selectIndex(index) {
        if (appCount <= 0) {
            selectedIndex = 0;
            return;
        }
        var next = Math.max(0, Math.min(appCount - 1, index));
        selectedIndex = next;
        var page = pageOfIndex(next);
        if (page !== currentPage)
            goToPage(page, true);
    }

    function moveSelection(dx, dy) {
        if (appCount <= 0)
            return;
        var col = selectedIndex % gridCols;
        var rowInPage = Math.floor((selectedIndex % cellsPerPage) / gridCols);
        var page = pageOfIndex(selectedIndex);

        var newCol = col + dx;
        var newRow = rowInPage + dy;
        var newPage = page;

        if (newCol < 0) {
            newPage -= 1;
            newCol = gridCols - 1;
        } else if (newCol >= gridCols) {
            newPage += 1;
            newCol = 0;
        }

        if (newRow < 0)
            newRow = 0;
        if (newRow >= gridRows)
            newRow = gridRows - 1;

        if (newPage < 0 || newPage >= pageCount)
            return;

        var idx = newPage * cellsPerPage + newRow * gridCols + newCol;
        if (idx >= appCount)
            idx = appCount - 1;
        selectIndex(idx);
    }

    function playGridEnter() {
        gridEnterAnim.stop();
        if (Motion.reducedMotion(settingsService)) {
            gridEnter = 1;
            return;
        }
        gridEnter = 0;
        gridEnterAnim.from = 0;
        gridEnterAnim.to = 1;
        gridEnterAnim.duration = Motion.launchpadIconEnterDuration(settingsService);
        gridEnterAnim.restart();
    }

    function playLayerEnter() {
        layerProgressAnim.stop();
        if (Motion.reducedMotion(settingsService)) {
            layerProgress = 1;
            return;
        }
        // Continue from current progress so mid-exit reopen does not flash.
        layerProgressAnim.from = layerProgress;
        layerProgressAnim.to = 1;
        layerProgressAnim.duration = Motion.launchpadLayerEnterDuration(settingsService);
        layerProgressAnim.easing.type = Easing.OutQuint;
        layerProgressAnim.restart();
    }

    function playLayerExit() {
        layerProgressAnim.stop();
        if (Motion.reducedMotion(settingsService)) {
            layerProgress = 0;
            return;
        }
        // Keep grid visible during fade-out (don't zero gridEnter instantly).
        layerProgressAnim.from = layerProgress;
        layerProgressAnim.to = 0;
        layerProgressAnim.duration = Motion.launchpadLayerExitDuration(settingsService);
        // Soft ease-out exit (not harsh accel) so close feels continuous.
        layerProgressAnim.easing.type = Easing.InOutCubic;
        layerProgressAnim.restart();
    }

    NumberAnimation {
        id: gridEnterAnim
        target: root
        property: "gridEnter"
        // OutQuint = longer soft settle than OutCubic for enter feel.
        easing.type: Easing.OutQuint
    }

    NumberAnimation {
        id: layerProgressAnim
        target: root
        property: "layerProgress"
        easing.type: Easing.OutQuint
    }

    NumberAnimation {
        id: launchPopAnim
        target: root
        property: "launchPop"
        easing.type: Easing.OutBack
        easing.overshoot: 1.4
    }

    Timer {
        id: launchCloseTimer
        interval: Motion.launchpadLaunchPopDuration(root.settingsService) + 40
        repeat: false
        onTriggered: {
            root.closeRequested();
        }
    }

    visible: compositorLayerAnimations ? open : (open || layerProgress > 0.01)
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    focusable: open
    implicitWidth: screenWidth
    implicitHeight: screenHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "tahoe-launchpad"

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    onOpenChanged: {
        if (open) {
            query = "";
            selectedIndex = 0;
            currentPage = 0;
            launchingIndex = -1;
            launchPop = 0;
            closingForLaunch = false;
            launchCloseTimer.stop();
            launchPopAnim.stop();
            gridEnter = 0;
            // Start layer fade immediately so open never looks like a hard cut.
            playLayerEnter();
            Qt.callLater(function() {
                if (!root.open)
                    return;
                pageSnapAnim.stop();
                pageFlick.contentX = 0;
                pageSnapPending = false;
                pageGestureActive = false;
                searchInput.forceActiveFocus();
                playGridEnter();
            });
        } else {
            gridEnterAnim.stop();
            launchCloseTimer.stop();
            // If we closed after an icon pop, freeze the pop at its peak
            // during the layer fade (do not snap scale back to 1).
            if (!closingForLaunch) {
                launchPopAnim.stop();
                launchingIndex = -1;
                launchPop = 0;
            } else {
                launchPopAnim.stop();
                // Hold final pop scale while the layer fades out.
                launchPop = 1;
            }
            // Exit: fade whole layer; keep icons until opacity is gone.
            playLayerExit();
            // After exit completes, clear gridEnter / launch state for next open.
            exitCleanupTimer.restart();
        }
    }

    Timer {
        id: exitCleanupTimer
        interval: Motion.launchpadLayerExitDuration(root.settingsService) + 40
        repeat: false
        onTriggered: {
            if (root.open)
                return;
            gridEnter = 0;
            launchingIndex = -1;
            launchPop = 0;
            closingForLaunch = false;
            pageSnapAnim.stop();
            pageSnapPending = false;
            pageGestureActive = false;
        }
    }

    onQueryChanged: {
        selectedIndex = 0;
        currentPage = 0;
        if (pageFlick.width > 0) {
            pageSnapAnim.stop();
            pageFlick.contentX = 0;
            pageSnapPending = false;
        }
        // Filtering swaps in place. Replaying the whole-field opacity + scale
        // on every keystroke made rapid typing read as a grid pulse; the
        // unified enter belongs exclusively to the open path above.
    }

    onAppCountChanged: {
        if (selectedIndex >= appCount)
            selectedIndex = Math.max(0, appCount - 1);
        currentPage = clampPage(currentPage);
    }

    // Full-screen glass region for blur backdrop (static geometry = surface).
    TahoeGlass.regions: [backdropSurface.region]

    // Root dismiss: any click that is not swallowed by search / icons / dots.
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        z: 0
        onClicked: root.requestClose()
    }

    Item {
        id: launcher
        anchors.fill: parent
        opacity: root.compositorLayerAnimations ? 1 : root.layerProgress
        // Soft settle on the whole layer (opacity only — no scale, §2.11 icons).
        scale: root.compositorLayerAnimations
            ? 1
            : (Motion.launchpadLayerScaleFrom
                + (1.0 - Motion.launchpadLayerScaleFrom) * root.layerProgress)
        transformOrigin: Item.Center

        // Full-screen backdrop material (blur region = entire surface).
        GlassPanel {
            id: backdropSurface
            anchors.fill: parent
            material: GlassStyle.MaterialBackdrop
            radius: GlassStyle.RadiusBackdrop
            fillColor: GlassStyle.FillBackdrop
            strokeColor: "transparent"
            useItemRegion: false
            regionX: 0
            regionY: 0
            regionWidth: Math.round(root.screenWidth)
            regionHeight: Math.round(root.screenHeight)
            interaction: 0
            materialAlpha: root.compositorLayerAnimations ? 1 : launcher.opacity
            glassEnabled: root.open || root.layerProgress > 0.01
        }

        // Extra dim so icons read over wallpaper even without blur.
        Rectangle {
            anchors.fill: parent
            color: root.darkMode ? "#66000000" : "#4d000000"
            opacity: launcher.opacity
        }

        // Search pill
        Item {
            id: searchBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 28
            width: Math.min(420, parent.width - 80)
            height: 40
            z: 2

            // Swallow clicks so empty-area close does not fire through the pill.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: searchInput.forceActiveFocus()
            }

            Rectangle {
                anchors.fill: parent
                radius: 20
                color: root.darkMode ? "#66ffffff" : "#88ffffff"
                border.color: root.darkMode ? "#40ffffff" : "#55ffffff"
                border.width: 1
            }

            TahoeSymbol {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                name: "\ue8b6"
                color: root.darkMode ? "#1d1d1f" : "#3a3a3c"
                size: 16
            }

            Text {
                anchors.left: searchInput.left
                anchors.verticalCenter: parent.verticalCenter
                text: "搜索"
                color: root.darkMode ? "#5f6870" : "#6f7780"
                font.pixelSize: 14
                visible: searchInput.text.length === 0
            }

            TextInput {
                id: searchInput
                anchors.left: parent.left
                anchors.leftMargin: 40
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                height: 24
                text: root.query
                color: root.darkMode ? "#1d1d1f" : "#1d1d1f"
                selectionColor: root.accent
                selectedTextColor: "#ffffff"
                font.pixelSize: 14
                clip: true
                focus: root.open
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: root.query = text
                Keys.onEscapePressed: root.requestClose()
                Keys.onReturnPressed: root.launchSelected()
                Keys.onEnterPressed: root.launchSelected()
                Keys.onLeftPressed: root.moveSelection(-1, 0)
                Keys.onRightPressed: root.moveSelection(1, 0)
                Keys.onUpPressed: root.moveSelection(0, -1)
                Keys.onDownPressed: root.moveSelection(0, 1)
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_PageDown) {
                        root.goToPage(root.currentPage + 1, true);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageUp) {
                        root.goToPage(root.currentPage - 1, true);
                        event.accepted = true;
                    }
                }
            }
        }

        // Horizontal paging surface
        Flickable {
            id: pageFlick
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: root.topChrome
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.bottomChrome
            z: 1
            contentWidth: Math.max(width, width * Math.max(1, root.pageCount))
            contentHeight: height
            clip: true
            interactive: root.pageCount > 1
            flickableDirection: Flickable.HorizontalFlick
            // Stop at edges hard — rubber-band rebound was fighting our snap
            // and felt like a second "pull back".
            boundsBehavior: Flickable.StopAtBounds
            // We own settle; kill coast so release velocity is not overwritten.
            flickDeceleration: 10000
            maximumFlickVelocity: 3500
            pressDelay: 0

            onMovementStarted: {
                // Only re-anchor at the start of a real user drag, not during
                // our own snap animation (which also moves contentX).
                if (root.pageSnapPending && !dragging)
                    return;
                pageSnapAnim.stop();
                root.pageSnapPending = false;
                root.pageGestureActive = true;
                root.pageReleaseVelocity = 0;
                root.pagePeakVelocity = 0;
                var pageW = Math.max(1, width);
                // Anchor to the page we were settled on, not a mid-drag round().
                root.pageDragStartPage = root.clampPage(Math.round(contentX / pageW));
                root.pageDragStartX = root.pageDragStartPage * pageW;
                root.currentPage = root.pageDragStartPage;
            }

            onHorizontalVelocityChanged: {
                if (!root.pageGestureActive)
                    return;
                var v = horizontalVelocity;
                root.pageReleaseVelocity = v;
                if (Math.abs(v) > Math.abs(root.pagePeakVelocity))
                    root.pagePeakVelocity = v;
            }

            // Finger up: sample velocity, kill coast, commit from displacement.
            onDraggingChanged: {
                if (dragging) {
                    // Fresh drag: stop any in-flight snap and re-anchor.
                    pageSnapAnim.stop();
                    root.pageSnapPending = false;
                    if (!root.pageGestureActive) {
                        root.pageGestureActive = true;
                        root.pageReleaseVelocity = 0;
                        root.pagePeakVelocity = 0;
                        var pageW = Math.max(1, width);
                        root.pageDragStartPage = root.clampPage(Math.round(contentX / pageW));
                        root.pageDragStartX = root.pageDragStartPage * pageW;
                        root.currentPage = root.pageDragStartPage;
                    }
                    return;
                }
                // Released.
                if (!root.pageGestureActive)
                    return;
                root.pageReleaseVelocity = horizontalVelocity;
                if (Math.abs(horizontalVelocity) > Math.abs(root.pagePeakVelocity))
                    root.pagePeakVelocity = horizontalVelocity;
                cancelFlick();
                root.finishPageGesture();
            }

            // Preview dots from finger displacement (not velocity).
            onContentXChanged: {
                if (!root.pageGestureActive || root.pageSnapPending)
                    return;
                if (!(dragging || moving))
                    return;
                var pageW = Math.max(1, width);
                var delta = contentX - root.pageDragStartX;
                var commitPx = Math.max(
                    Motion.launchpadPageCommitMinPx,
                    pageW * Motion.launchpadPageCommitRatio
                );
                var preview = root.pageDragStartPage;
                if (delta > commitPx * 0.35)
                    preview = root.pageDragStartPage + 1;
                else if (delta < -commitPx * 0.35)
                    preview = root.pageDragStartPage - 1;
                root.currentPage = root.clampPage(preview);
            }

            onMovementEnded: {
                if (root.pageGestureActive && !root.pageSnapPending)
                    root.finishPageGesture();
            }

            NumberAnimation {
                id: pageSnapAnim
                target: pageFlick
                property: "contentX"
                duration: Motion.launchpadPageSnapDuration(root.settingsService)
                easing.type: Motion.expressiveEffects
                onStopped: {
                    root.pageSnapPending = false;
                    root.pageGestureActive = false;
                    // Snap exactly onto a page boundary (avoid subpixel drift).
                    if (pageFlick.width > 0) {
                        var pageW = pageFlick.width;
                        var page = root.clampPage(Math.round(pageFlick.contentX / pageW));
                        pageFlick.contentX = page * pageW;
                        root.currentPage = page;
                    }
                }
            }

            // Unified enter for the whole icon field (opacity + soft scale).
            opacity: root.gridEnter
            transform: Scale {
                origin.x: pageFlick.width / 2
                origin.y: pageFlick.height / 2
                xScale: Motion.launchpadIconEnterScaleFrom
                    + (1.0 - Motion.launchpadIconEnterScaleFrom) * root.gridEnter
                yScale: Motion.launchpadIconEnterScaleFrom
                    + (1.0 - Motion.launchpadIconEnterScaleFrom) * root.gridEnter
            }

            Row {
                id: pagesRow
                height: pageFlick.height

                Repeater {
                    model: root.pageCount

                    delegate: Item {
                        id: pageDelegate
                        required property int index

                        width: pageFlick.width
                        height: pageFlick.height

                        // Empty page chrome closes Launchpad (icons sit above).
                        // Must yield horizontal drags so paging still works on gaps.
                        MouseArea {
                            anchors.fill: parent
                            z: 0
                            preventStealing: false
                            property real pressX: 0
                            property real pressY: 0
                            property bool moved: false
                            onPressed: function(mouse) {
                                pressX = mouse.x;
                                pressY = mouse.y;
                                moved = false;
                            }
                            onPositionChanged: function(mouse) {
                                if (!pressed)
                                    return;
                                var dx = mouse.x - pressX;
                                var dy = mouse.y - pressY;
                                if (Math.abs(dx) > 8 || Math.abs(dy) > 8)
                                    moved = true;
                                if (Math.abs(dx) > 10 && Math.abs(dx) > Math.abs(dy) * 1.2)
                                    mouse.accepted = false;
                            }
                            onClicked: {
                                if (!moved)
                                    root.requestClose();
                            }
                        }

                        Grid {
                            id: pageGrid
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.gridWidth
                            height: root.gridHeight
                            columns: root.gridCols
                            rowSpacing: 0
                            columnSpacing: 0
                            z: 1

                            Repeater {
                                model: root.cellsPerPage

                                delegate: Item {
                                    id: cell
                                    required property int index

                                    readonly property int globalIndex: pageDelegate.index * root.cellsPerPage + cell.index
                                    readonly property var app: root.appAt(cell.globalIndex)
                                    readonly property bool hasApp: !!cell.app
                                    readonly property bool selected: root.selectedIndex === cell.globalIndex && cell.hasApp
                                    readonly property bool isLaunching: root.launchingIndex === cell.globalIndex

                                    width: root.cellWidth
                                    height: root.cellHeight
                                    // Always visible when app exists — enter is on pageFlick.
                                    visible: cell.hasApp
                                    opacity: cell.isLaunching
                                        ? 1.0
                                        : (root.launchingIndex >= 0 ? (1.0 - 0.55 * root.launchPop) : 1.0)
                                    z: cell.isLaunching ? 10 : 0

                                    // Press + selection chrome + launch pop
                                    Item {
                                        anchors.fill: parent
                                        // Press scale only (Behavior). Launch pop uses a separate
                                        // transform so it is not fought by press Behavior.
                                        scale: Motion.pressScaleFor(
                                            root.settingsService,
                                            appMouse.pressed && !cell.isLaunching
                                        )
                                        Behavior on scale {
                                            NumberAnimation {
                                                duration: Motion.pressDurationFor(root.settingsService)
                                                easing.type: Motion.pressEasing
                                            }
                                        }
                                        transform: Scale {
                                            origin.x: cell.width / 2
                                            origin.y: cell.height / 2
                                            xScale: cell.isLaunching
                                                ? (1.0 + Motion.launchpadLaunchPopScaleBoost * root.launchPop)
                                                : 1.0
                                            yScale: cell.isLaunching
                                                ? (1.0 + Motion.launchpadLaunchPopScaleBoost * root.launchPop)
                                                : 1.0
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            radius: 18
                                            color: cell.selected
                                                ? (root.darkMode ? "#40ffffff" : "#38ffffff")
                                                : (appMouse.containsMouse ? "#28ffffff" : "transparent")
                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: Motion.fadeFast(root.settingsService)
                                                }
                                            }
                                        }

                                        Item {
                                            id: appIconSlot
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.topMargin: Math.max(8, (root.cellHeight - root.iconSize - 28) / 2)
                                            width: root.iconSize
                                            height: root.iconSize

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: Math.round(width * 0.22)
                                                color: "#24ffffff"
                                                visible: appIcon.status !== Image.Ready
                                            }

                                            TahoeSymbol {
                                                anchors.centerIn: parent
                                                name: "\ue5c3"
                                                color: root.textSecondary
                                                size: Math.round(parent.width * 0.42)
                                                visible: appIcon.status !== Image.Ready
                                            }

                                            Image {
                                                id: appIcon
                                                anchors.fill: parent
                                                source: root.appsService && cell.app
                                                    ? root.appsService.iconForApp(cell.app)
                                                    : ""
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                                mipmap: true
                                                sourceSize.width: 128
                                                sourceSize.height: 128
                                                // Decode off the GUI thread; the slot above
                                                // remains visible until the image is ready.
                                                asynchronous: true
                                                cache: true
                                                visible: status === Image.Ready
                                            }
                                        }

                                        Text {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: appIconSlot.bottom
                                            anchors.topMargin: 6
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 4
                                            text: root.appsService && cell.app
                                                ? root.appsService.appLabel(cell.app)
                                                : ""
                                            color: root.textPrimary
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 2
                                            lineHeight: 0.95
                                            elide: Text.ElideRight
                                            style: Text.Raised
                                            styleColor: "#66000000"
                                            opacity: cell.isLaunching ? (1.0 - root.launchPop) : 1.0
                                        }

                                        MouseArea {
                                            id: appMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            // Allow pageFlick to steal horizontal drags.
                                            preventStealing: false
                                            property real pressX: 0
                                            property real pressY: 0
                                            property bool moved: false

                                            onPressed: function(mouse) {
                                                pressX = mouse.x;
                                                pressY = mouse.y;
                                                moved = false;
                                            }
                                            onPositionChanged: function(mouse) {
                                                if (!pressed)
                                                    return;
                                                var dx = mouse.x - pressX;
                                                var dy = mouse.y - pressY;
                                                if (Math.abs(dx) > 8 || Math.abs(dy) > 8)
                                                    moved = true;
                                                // Yield horizontal drags to the page Flickable.
                                                if (Math.abs(dx) > 10 && Math.abs(dx) > Math.abs(dy) * 1.2)
                                                    mouse.accepted = false;
                                            }
                                            onReleased: function(mouse) {
                                                if (moved && Math.abs(mouse.x - pressX) > Math.abs(mouse.y - pressY))
                                                    mouse.accepted = false;
                                            }
                                            onClicked: {
                                                if (moved)
                                                    return;
                                                root.selectedIndex = cell.globalIndex;
                                                root.launchAt(cell.globalIndex);
                                            }
                                            onContainsMouseChanged: {
                                                if (containsMouse && cell.hasApp)
                                                    root.selectedIndex = cell.globalIndex;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Empty state
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: "无结果"
            color: root.textPrimary
            font.pixelSize: 18
            font.weight: Font.DemiBold
            visible: root.query.trim().length > 0 && root.appCount === 0
            z: 3

            MouseArea {
                anchors.fill: parent
                anchors.margins: -24
                onClicked: root.requestClose()
            }
        }

        // Page dots
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            spacing: 8
            visible: root.pageCount > 1
            z: 3

            Repeater {
                model: root.pageCount
                delegate: Rectangle {
                    required property int index
                    width: root.currentPage === index ? 8 : 6
                    height: width
                    radius: width / 2
                    color: root.currentPage === index ? "#ffffff" : "#66ffffff"
                    Behavior on width {
                        NumberAnimation {
                            duration: 120
                            easing.type: Motion.emphasizedDecel
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.goToPage(index, true)
                    }
                }
            }
        }

        // Top/bottom chrome strips (outside Flickable) also dismiss on click.
        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: root.topChrome
            z: 1
            // Search box is above (z:2) and swallows its own clicks.
            onClicked: root.requestClose()
        }
        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.bottomChrome
            z: 1
            // Page dots are above (z:3).
            onClicked: root.requestClose()
        }
    }

    // Commit next/prev. Displacement is authoritative once past the commit
    // threshold — velocity must never reverse a page the finger already crossed.
    // Qt: positive horizontalVelocity → content moves right → contentX ↓ → previous.
    function finishPageGesture() {
        if (pageFlick.width <= 0 || pageCount <= 1) {
            pageGestureActive = false;
            pageSnapPending = false;
            return;
        }
        // Re-entry guard: draggingChanged + movementEnded can both fire.
        if (pageSnapPending || !pageGestureActive)
            return;

        pageGestureActive = false;
        pageSnapPending = true;

        var pageW = Math.max(1, pageFlick.width);
        // Live content position vs the settled start page (not mid-gesture drift).
        var startX = pageDragStartPage * pageW;
        var delta = pageFlick.contentX - startX;

        // Prefer release velocity; peak only if release is near zero.
        var vel = pageReleaseVelocity;
        if (Math.abs(vel) < 40 && Math.abs(pagePeakVelocity) > Math.abs(vel))
            vel = pagePeakVelocity;

        var commitPx = Math.max(
            Motion.launchpadPageCommitMinPx,
            pageW * Motion.launchpadPageCommitRatio
        );
        var flickV = Motion.launchpadPageFlickVelocity;

        var page = pageDragStartPage;

        // 1) Displacement past commit → ALWAYS follow the finger.
        //    This is the fix for "I already went past and it yanked me back".
        if (delta >= commitPx) {
            page = pageDragStartPage + 1;
        } else if (delta <= -commitPx) {
            page = pageDragStartPage - 1;
        // 2) Short flick with little travel → velocity, only if same direction.
        } else if (Math.abs(vel) >= flickV) {
            if (vel < 0 && delta >= -commitPx * 0.35)
                page = pageDragStartPage + 1;
            else if (vel > 0 && delta <= commitPx * 0.35)
                page = pageDragStartPage - 1;
        }
        // 3) else stay on start page

        page = clampPage(page);
        // Clear pending so goToPage can re-arm the snap animation flag.
        pageSnapPending = false;
        goToPage(page, true);

        var base = page * cellsPerPage;
        if (selectedIndex < base || selectedIndex >= base + cellsPerPage) {
            var idx = Math.min(appCount - 1, base);
            if (idx >= 0)
                selectedIndex = idx;
        }
    }

    // Kept for tests / page-dot callers that still say "snap".
    function snapToNearestPage() {
        finishPageGesture();
    }
}
