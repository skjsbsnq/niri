pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "Motion.js" as Motion
import "TahoeGlass.js" as GlassStyle
import "settings/SettingsTheme.js" as Theme

// T18: full-screen Launchpad — adaptive 7×5 pages, wallpaper zoom (via
// Wallpaper.qml), distance-based icon stagger (budget ≤450ms), horizontal
// snap paging + page dots, arrow-key navigation. Category chips removed.
// Stays on the QML outer animation path (rules §2.11): compositor scale
// softens themed app icons on large surfaces.
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
    // Custom inverted paging (finger right → content left → next page).
    // Flickable is NOT interactive; pageDragArea owns the gesture so we can
    // invert drag 1:1 and snap with a smooth ease (no Flickable coast fight).
    property int pageDragStartPage: 0
    property real pageDragStartContentX: 0
    property real pageDragStartFingerX: 0
    property real pageDragLastFingerX: 0
    property real pageDragLastMs: 0
    property real pageFingerVelocity: 0
    property real pagePeakFingerVelocity: 0
    property bool pageSnapPending: false
    property bool pageGestureActive: false

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

    // Standard LTR strip: page 0 at contentX=0, page 1 at +width, …
    // Finger right → contentX increases → next page slides in from the right
    // (content moves left on screen). Implemented by inverted drag in pageDragArea.
    function contentXForPage(page) {
        var pageW = Math.max(1, pageFlick.width);
        return clampPage(page) * pageW;
    }

    function pageFromContentX(x) {
        var pageW = Math.max(1, pageFlick.width);
        if (pageW <= 0 || pageCount <= 0)
            return 0;
        return clampPage(Math.round(Number(x) / pageW));
    }

    function minContentX() {
        return 0;
    }

    function maxContentX() {
        return Math.max(0, (pageCount - 1) * Math.max(1, pageFlick.width));
    }

    // Rubber-band past ends (diminishing resistance).
    function clampContentXWithRubber(x) {
        var lo = minContentX();
        var hi = maxContentX();
        if (x < lo)
            return lo + (x - lo) * 0.35;
        if (x > hi)
            return hi + (x - hi) * 0.35;
        return x;
    }

    function goToPage(page, animated) {
        currentPage = clampPage(page);
        var target = contentXForPage(currentPage);
        if (animated === false || Motion.reducedMotion(settingsService)) {
            pageSnapAnim.stop();
            pageFlick.contentX = target;
            pageSnapPending = false;
            return;
        }
        if (Math.abs(pageFlick.contentX - target) < 0.5) {
            pageSnapAnim.stop();
            pageFlick.contentX = target;
            pageSnapPending = false;
            return;
        }
        pageSnapAnim.stop();
        pageSnapAnim.from = pageFlick.contentX;
        pageSnapAnim.to = target;
        // Distance-scaled duration feels smoother on short bounces vs full pages.
        var dist = Math.abs(pageSnapAnim.to - pageSnapAnim.from);
        var pageW = Math.max(1, pageFlick.width);
        var base = Motion.launchpadPageSnapDuration(settingsService);
        pageSnapAnim.duration = Math.max(180, Math.min(base, base * (0.45 + 0.55 * Math.min(1, dist / pageW))));
        pageSnapPending = true;
        pageSnapAnim.restart();
    }

    function appAt(index) {
        if (index < 0 || index >= appCount)
            return null;
        return filteredApps[index];
    }

    function launchAt(index) {
        var app = appAt(index);
        if (!app || !appsService)
            return;
        appsService.launchApp(app);
        closeRequested();
    }

    function launchSelected() {
        launchAt(selectedIndex);
    }

    // Map a point in pageFlick to a global app index and launch (tap path).
    function launchAtPoint(x, y) {
        var pageW = Math.max(1, pageFlick.width);
        var pageH = Math.max(1, pageFlick.height);
        if (x < 0 || y < 0 || x > pageW || y > pageH)
            return;
        var page = pageFromContentX(pageFlick.contentX);
        // Grid is centered in the page.
        var gridLeft = (pageW - gridWidth) / 2;
        var gridTop = (pageH - gridHeight) / 2;
        var lx = x - gridLeft;
        var ly = y - gridTop;
        if (lx < 0 || ly < 0 || lx >= gridWidth || ly >= gridHeight)
            return;
        var col = Math.floor(lx / cellWidth);
        var row = Math.floor(ly / cellHeight);
        if (col < 0 || row < 0 || col >= gridCols || row >= gridRows)
            return;
        var idx = page * cellsPerPage + row * gridCols + col;
        if (idx >= 0 && idx < appCount)
            launchAt(idx);
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

    NumberAnimation {
        id: gridEnterAnim
        target: root
        property: "gridEnter"
        easing.type: Motion.emphasizedDecel
    }

    visible: compositorLayerAnimations ? open : (open || launcher.opacity > 0.01)
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
            gridEnter = 0;
            Qt.callLater(function() {
                if (!root.open)
                    return;
                pageSnapAnim.stop();
                pageFlick.contentX = root.contentXForPage(0);
                searchInput.forceActiveFocus();
                playGridEnter();
            });
        } else {
            gridEnterAnim.stop();
            gridEnter = 0;
        }
    }

    onQueryChanged: {
        selectedIndex = 0;
        currentPage = 0;
        if (pageFlick.width > 0) {
            pageSnapAnim.stop();
            pageFlick.contentX = root.contentXForPage(0);
        }
        if (root.open)
            playGridEnter();
    }

    onAppCountChanged: {
        if (selectedIndex >= appCount)
            selectedIndex = Math.max(0, appCount - 1);
        currentPage = clampPage(currentPage);
        if (open && pageFlick.width > 0 && !pageSnapPending)
            pageFlick.contentX = contentXForPage(currentPage);
    }

    onPageCountChanged: {
        currentPage = clampPage(currentPage);
        if (open && pageFlick.width > 0 && !pageSnapPending && !pageGestureActive)
            pageFlick.contentX = contentXForPage(currentPage);
    }

    // Full-screen glass region for blur backdrop (static geometry = surface).
    TahoeGlass.regions: [backdropSurface.region]

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closeRequested()
    }

    Item {
        id: launcher
        anchors.fill: parent
        opacity: root.compositorLayerAnimations ? 1 : (root.open ? 1 : 0)
        // Soft whole-layer settle (opacity only — no scale, keeps icons sharp §2.11).

        Behavior on opacity {
            NumberAnimation {
                duration: root.open
                    ? Motion.panelEnter(root.settingsService)
                    : Motion.panelExit(root.settingsService)
                easing.type: Motion.emphasizedDecel
            }
        }

        // Click empty chrome (not icons) closes — Flickable/search sit above this.
        MouseArea {
            anchors.fill: parent
            z: 0
            onClicked: root.closeRequested()
        }

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
            glassEnabled: root.open || launcher.opacity > 0.01
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
                Keys.onEscapePressed: root.closeRequested()
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

        // Horizontal paging surface (standard LTR: page0 | page1 | page2).
        // Drag is inverted via pageDragArea: finger right → contentX up → next.
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
            // We own drag/snap ourselves for inverted feel + smooth settle.
            interactive: false
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            NumberAnimation {
                id: pageSnapAnim
                target: pageFlick
                property: "contentX"
                duration: Motion.launchpadPageSnapDuration(root.settingsService)
                // Smooth settle via Motion.emphasizedDecel (shared token).
                easing.type: Motion.emphasizedDecel
                onStopped: {
                    root.pageSnapPending = false;
                    root.pageGestureActive = false;
                    if (pageFlick.width > 0)
                        root.currentPage = root.pageFromContentX(pageFlick.contentX);
                }
            }

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
                        // Standard LTR: visual index === logical page.
                        readonly property int logicalPage: pageDelegate.index

                        width: pageFlick.width
                        height: pageFlick.height

                        Grid {
                            id: pageGrid
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.gridWidth
                            height: root.gridHeight
                            columns: root.gridCols
                            rowSpacing: 0
                            columnSpacing: 0

                            Repeater {
                                model: root.cellsPerPage

                                delegate: Item {
                                    id: cell
                                    required property int index

                                    readonly property int globalIndex: pageDelegate.logicalPage * root.cellsPerPage + cell.index
                                    readonly property var app: root.appAt(cell.globalIndex)
                                    readonly property bool hasApp: !!cell.app
                                    readonly property bool selected: root.selectedIndex === cell.globalIndex && cell.hasApp

                                    width: root.cellWidth
                                    height: root.cellHeight
                                    visible: cell.hasApp
                                    opacity: 1

                                    Item {
                                        anchors.fill: parent
                                        scale: Motion.pressScaleFor(root.settingsService, appMouse.pressed)
                                        Behavior on scale {
                                            NumberAnimation {
                                                duration: Motion.pressDurationFor(root.settingsService)
                                                easing.type: Motion.pressEasing
                                            }
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

                                        Image {
                                            id: appIcon
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.topMargin: Math.max(8, (root.cellHeight - root.iconSize - 28) / 2)
                                            width: root.iconSize
                                            height: root.iconSize
                                            source: root.appsService && cell.app
                                                ? root.appsService.iconForApp(cell.app)
                                                : ""
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            mipmap: true
                                            sourceSize.width: 128
                                            sourceSize.height: 128
                                            asynchronous: false
                                            cache: true
                                        }

                                        Text {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: appIcon.bottom
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
                                        }

                                        MouseArea {
                                            id: appMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            // pageDragArea is above us for horizontal pans;
                                            // keep click-to-launch for taps.
                                            z: 0
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
                                                if (Math.abs(mouse.x - pressX) > 8 || Math.abs(mouse.y - pressY) > 8)
                                                    moved = true;
                                            }
                                            onClicked: {
                                                if (moved || root.pageGestureActive)
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

            // Full-surface drag: invert finger → content so finger right moves
            // content left (next page slides in from the right).
            MouseArea {
                id: pageDragArea
                anchors.fill: parent
                z: 10
                acceptedButtons: Qt.LeftButton
                // Only steal when horizontal pan is clear; otherwise clicks
                // fall through to icon MouseAreas (propagateComposedEvents).
                propagateComposedEvents: true
                preventStealing: false
                property bool panning: false
                property real pressX: 0
                property real pressY: 0

                onPressed: function(mouse) {
                    if (root.pageCount <= 1) {
                        mouse.accepted = false;
                        return;
                    }
                    pageSnapAnim.stop();
                    root.pageSnapPending = false;
                    panning = false;
                    pressX = mouse.x;
                    pressY = mouse.y;
                    root.pageDragStartFingerX = mouse.x;
                    root.pageDragLastFingerX = mouse.x;
                    root.pageDragLastMs = Date.now();
                    root.pageFingerVelocity = 0;
                    root.pagePeakFingerVelocity = 0;
                    root.pageDragStartContentX = pageFlick.contentX;
                    root.pageDragStartPage = root.pageFromContentX(pageFlick.contentX);
                    root.currentPage = root.pageDragStartPage;
                    root.pageGestureActive = false;
                    // Don't accept yet — wait for horizontal threshold so taps launch.
                    mouse.accepted = true;
                }

                onPositionChanged: function(mouse) {
                    if (!pressed || root.pageCount <= 1)
                        return;
                    var dx = mouse.x - pressX;
                    var dy = mouse.y - pressY;
                    if (!panning) {
                        if (Math.abs(dx) < 8 && Math.abs(dy) < 8)
                            return;
                        if (Math.abs(dy) > Math.abs(dx) * 1.15) {
                            // Vertical-ish: let go (no pan).
                            mouse.accepted = false;
                            return;
                        }
                        panning = true;
                        root.pageGestureActive = true;
                    }

                    var now = Date.now();
                    var dt = Math.max(1, now - root.pageDragLastMs);
                    var fingerDx = mouse.x - root.pageDragLastFingerX;
                    var v = fingerDx / dt * 1000.0;
                    root.pageFingerVelocity = v;
                    if (Math.abs(v) > Math.abs(root.pagePeakFingerVelocity))
                        root.pagePeakFingerVelocity = v;
                    root.pageDragLastFingerX = mouse.x;
                    root.pageDragLastMs = now;

                    // Invert: finger right (positive) → contentX increases → next page.
                    var fingerTravel = mouse.x - root.pageDragStartFingerX;
                    var rawX = root.pageDragStartContentX + fingerTravel;
                    pageFlick.contentX = root.clampContentXWithRubber(rawX);

                    // Live page-dot preview from finger travel.
                    var pageW = Math.max(1, pageFlick.width);
                    var commitPx = Math.max(
                        Motion.launchpadPageCommitMinPx,
                        pageW * Motion.launchpadPageCommitRatio
                    );
                    var preview = root.pageDragStartPage;
                    if (fingerTravel > commitPx * 0.45)
                        preview = root.pageDragStartPage + 1;
                    else if (fingerTravel < -commitPx * 0.45)
                        preview = root.pageDragStartPage - 1;
                    root.currentPage = root.clampPage(preview);
                }

                onReleased: function(mouse) {
                    if (root.pageCount <= 1) {
                        root.launchAtPoint(mouse.x, mouse.y);
                        return;
                    }
                    if (!panning) {
                        // Tap: launch the icon under the press point.
                        root.pageGestureActive = false;
                        root.launchAtPoint(pressX, pressY);
                        return;
                    }
                    // Final velocity sample.
                    var now = Date.now();
                    var dt = Math.max(1, now - root.pageDragLastMs);
                    var fingerDx = mouse.x - root.pageDragLastFingerX;
                    var v = fingerDx / dt * 1000.0;
                    if (Math.abs(v) > Math.abs(root.pagePeakFingerVelocity))
                        root.pagePeakFingerVelocity = v;
                    root.pageFingerVelocity = root.pagePeakFingerVelocity;
                    root.finishPageGesture(mouse.x - root.pageDragStartFingerX);
                    panning = false;
                }

                onCanceled: {
                    if (panning || root.pageGestureActive)
                        root.finishPageGesture(root.pageDragLastFingerX - root.pageDragStartFingerX);
                    panning = false;
                    root.pageGestureActive = false;
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
    }

    // fingerDelta = finger end X − start X (right positive).
    // content animates so finger-right → next page slides in from the right.
    function finishPageGesture(fingerDelta) {
        if (pageFlick.width <= 0 || pageCount <= 1) {
            pageGestureActive = false;
            return;
        }
        if (pageSnapPending)
            return;

        pageSnapPending = true;
        pageGestureActive = false;

        var pageW = Math.max(1, pageFlick.width);
        var d = Number(fingerDelta);
        if (!isFinite(d))
            d = pageDragLastFingerX - pageDragStartFingerX;
        var vel = pagePeakFingerVelocity;
        if (Math.abs(pageFingerVelocity) > Math.abs(vel))
            vel = pageFingerVelocity;

        var page = Motion.launchpadResolvePage(
            pageDragStartPage,
            pageCount,
            d,
            vel,
            pageW
        );
        goToPage(page, true);

        var base = page * cellsPerPage;
        if (selectedIndex < base || selectedIndex >= base + cellsPerPage) {
            var idx = Math.min(appCount - 1, base);
            if (idx >= 0)
                selectedIndex = idx;
        }
    }

    function snapToNearestPage() {
        finishPageGesture(pageDragLastFingerX - pageDragStartFingerX);
    }
}
