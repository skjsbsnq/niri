pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "Motion.js" as Motion
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property bool open: false
    property bool useSpring: false
    property var windowsService
    property var thumbnailProvider
    property var appsService
    property var settingsService
    property string selectedWindowKey: ""
    property var selectedCardItem: null
    // idle | entering | open | leaving
    property string flightPhase: "idle"
    property int flightEpoch: 0
    property int pendingFlights: 0
    readonly property var windowChoices: windowsService && windowsService.windowList ? windowsService.windowList : []
    readonly property var workspaceGroups: buildWorkspaceGroups()
    readonly property int screenWidth: Math.max(1, numberOr(root.screen && root.screen.width, root.width))
    readonly property int screenHeight: Math.max(1, numberOr(root.screen && root.screen.height, root.height))
    readonly property int panelWidth: Math.max(300, Math.min(screenWidth - 40, 1080))
    readonly property int panelHeight: Math.min(screenHeight - 72, 720)
    readonly property int panelLeft: Math.round(Math.max(8, (screenWidth - panelWidth) / 2))
    readonly property int panelTop: Math.round(Math.max(44, (screenHeight - panelHeight) / 2))
    readonly property bool surfaceVisible: open || flightPhase === "entering" || flightPhase === "leaving" || flightPhase === "open"

    signal closeRequested()

    visible: surfaceVisible || backdrop.opacity > 0.01
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
            flightEpoch += 1;
            flightPhase = "entering";
            pendingFlights = 0;
            selectFocusedOrFirst();
            Qt.callLater(function() {
                if (!root.open)
                    return;
                focusCatcher.forceActiveFocus();
                // Second tick: Flow/Repeater layout must settle before mapToItem.
                Qt.callLater(function() {
                    if (root.open)
                        beginEnterFlights();
                });
            });
        } else if (flightPhase === "entering" || flightPhase === "open") {
            if (root.thumbnailProvider)
                root.thumbnailProvider.cancelRequests("window-overview");
            flightEpoch += 1;
            flightPhase = "leaving";
            pendingFlights = 0;
            Qt.callLater(function() {
                if (!root.open)
                    beginLeaveFlights();
            });
        } else {
            if (root.thumbnailProvider)
                root.thumbnailProvider.cancelRequests("window-overview");
            flightPhase = "idle";
            pendingFlights = 0;
        }
    }

    onWindowChoicesChanged: if (open) {
        syncSelectionAfterModelChange();
        if (flightPhase === "open")
            requestVisibleThumbnails(false);
    }

    onFlightPhaseChanged: if (open && flightPhase === "open") requestVisibleThumbnails(false)

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
        Qt.callLater(function() {
            if (root.open)
                overviewFlick.ensureVisible();
        });
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

    function requestThumbnailFor(window, force) {
        if (!root.thumbnailProvider || !window)
            return;
        root.thumbnailProvider.requestThumbnail(window, 480, 300, "window-overview", !!force);
    }

    function requestVisibleThumbnails(force) {
        if (!root.thumbnailProvider)
            return;
        var selected = currentWindow();
        var candidates = [];
        if (selected)
            candidates.push(selected);
        for (var i = 0; i < root.windowChoices.length; i++) {
            if (root.windowChoices[i] !== selected)
                candidates.push(root.windowChoices[i]);
        }
        root.thumbnailProvider.requestThumbnails(candidates, 480, 300, "window-overview", !!force);
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

    // Approximate window geometry → Translate offset that places the card over
    // the real window, then spring back to (0,0). Content-layer only (not glass).
    function flightOffsetForCard(cardItem, window) {
        if (!cardItem)
            return { "x": 0, "y": 0, "scale": 1 };

        var rect = window ? window.geometry : null;
        var cardW = Math.max(1, cardItem.width);
        var cardH = Math.max(1, cardItem.height);

        // No geometry / minimized: short rise from below (no free-standing clones).
        if (!rect || (window && window.isMinimized)) {
            return {
                "x": 0,
                "y": Math.round(56 + (cardItem.indexInGroup || 0) * 8),
                "scale": 0.88
            };
        }

        var winX = Number(rect.x) || 0;
        var winY = Number(rect.y) || 0;
        var winW = Math.max(1, Number(rect.width || rect.w) || 1);
        var winH = Math.max(1, Number(rect.height || rect.h) || 1);

        // Card final position in panel-window coordinates (backdrop fills the surface).
        var cardInSurface = cardItem.mapToItem(backdrop, 0, 0);
        var endX = isFinite(cardInSurface.x) ? cardInSurface.x : (root.panelLeft + cardItem.x);
        var endY = isFinite(cardInSurface.y) ? cardInSurface.y : (root.panelTop + 76 + cardItem.y);

        // Window center → card center, geometry treated as output-local (same screen).
        var startX = winX + winW * 0.5 - cardW * 0.5;
        var startY = winY + winH * 0.5 - cardH * 0.5;

        var offsetX = Math.round(startX - endX);
        var offsetY = Math.round(startY - endY);
        offsetX = Math.max(-root.screenWidth, Math.min(root.screenWidth, offsetX));
        offsetY = Math.max(-root.screenHeight, Math.min(root.screenHeight, offsetY));

        var startScale = Math.max(0.55, Math.min(1.4, Math.min(winW / cardW, winH / cardH) * 0.5));
        return { "x": offsetX, "y": offsetY, "scale": startScale };
    }

    function shouldAnimateFlight() {
        return root.useSpring && !Motion.reducedMotion(root.settingsService);
    }

    function beginEnterFlights() {
        var epoch = root.flightEpoch;
        var cards = collectFlightCards();
        if (cards.length === 0 || !shouldAnimateFlight()) {
            snapAllCardsHome();
            if (root.open && root.flightEpoch === epoch)
                root.flightPhase = "open";
            return;
        }

        root.pendingFlights = cards.length;
        for (var i = 0; i < cards.length; i++) {
            var card = cards[i];
            if (!card || !card.prepareEnter)
                continue;
            card.prepareEnter(epoch);
        }

        // Safety: if no card registered a flight, settle.
        if (root.pendingFlights <= 0 && root.open && root.flightEpoch === epoch) {
            root.flightPhase = "open";
            return;
        }
        enterWatchdog.epoch = epoch;
        enterWatchdog.restart();
    }

    function beginLeaveFlights() {
        var epoch = root.flightEpoch;
        var cards = collectFlightCards();
        if (cards.length === 0 || !shouldAnimateFlight()) {
            snapAllCardsAway();
            finishLeave(epoch);
            return;
        }

        root.pendingFlights = cards.length;
        for (var i = 0; i < cards.length; i++) {
            var card = cards[i];
            if (!card || !card.prepareLeave)
                continue;
            card.prepareLeave(epoch);
        }

        if (root.pendingFlights <= 0)
            finishLeave(epoch);
        // Hard cap leave duration so close never sticks (rules §4.5 stagger budget).
        leaveWatchdog.epoch = epoch;
        leaveWatchdog.restart();
    }

    function finishLeave(epoch) {
        if (root.flightEpoch !== epoch)
            return;
        if (root.open)
            return;
        root.flightPhase = "idle";
        root.pendingFlights = 0;
        // Explicitly drop any residual flight transforms (no clone Items to destroy —
        // cards use Translate/scale on themselves; §4.4 satisfied by resetting state).
        snapAllCardsAway();
    }

    function noteFlightFinished(epoch) {
        if (root.flightEpoch !== epoch)
            return;
        root.pendingFlights = Math.max(0, root.pendingFlights - 1);
        if (root.pendingFlights > 0)
            return;
        if (root.flightPhase === "entering" && root.open)
            root.flightPhase = "open";
        else if (root.flightPhase === "leaving" && !root.open)
            finishLeave(epoch);
    }

    function collectFlightCards() {
        var out = [];
        // Walk groupColumn → Flow → windowCard items that expose flight API.
        function walk(item) {
            if (!item)
                return;
            if (item.flightCapable === true)
                out.push(item);
            var count = item.children ? item.children.length : 0;
            for (var i = 0; i < count; i++)
                walk(item.children[i]);
        }
        walk(groupColumn);
        return out;
    }

    function snapAllCardsHome() {
        var cards = collectFlightCards();
        for (var i = 0; i < cards.length; i++) {
            if (cards[i] && cards[i].snapHome)
                cards[i].snapHome();
        }
    }

    function snapAllCardsAway() {
        var cards = collectFlightCards();
        for (var i = 0; i < cards.length; i++) {
            if (cards[i] && cards[i].snapAway)
                cards[i].snapAway();
        }
    }

    Timer {
        id: leaveWatchdog
        property int epoch: 0
        interval: 480
        repeat: false
        onTriggered: root.finishLeave(epoch)
    }

    Timer {
        id: enterWatchdog
        property int epoch: 0
        interval: 480
        repeat: false
        onTriggered: {
            if (root.flightEpoch !== epoch)
                return;
            if (root.flightPhase === "entering" && root.open) {
                root.snapAllCardsHome();
                root.pendingFlights = 0;
                root.flightPhase = "open";
            }
        }
    }

    TahoeGlass.regions: [overviewSurface.region]

    Rectangle {
        id: backdrop

        anchors.fill: parent
        color: "#1a101418"
        opacity: root.open || root.flightPhase === "entering" || root.flightPhase === "open" || root.flightPhase === "leaving" ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.emphasizedDecel }
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
        // No entrance scale (T20). Opacity follows flight phase so leave can finish.
        opacity: (root.open || root.flightPhase === "entering" || root.flightPhase === "open" || root.flightPhase === "leaving") ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.emphasizedDecel }
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
            regionEnabled: root.surfaceVisible
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

                TahoeSymbol {
                    anchors.centerIn: parent
                    name: "\ue5cd"
                    color: "#30343a"
                    size: 18
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
            onMovementStarted: ensureVisibleAnimation.stop()

            function ensureVisible() {
                var item = root.selectedCardItem;
                if (!item)
                    return;

                var top = item.mapToItem(groupColumn, 0, 0).y - 12;
                var bottom = top + item.height + 24;
                var targetY = contentY;
                if (top < contentY)
                    targetY = Math.max(0, top);
                else if (bottom > contentY + height)
                    targetY = Math.min(Math.max(0, contentHeight - height), bottom - height);

                targetY = Math.max(0, Math.min(Math.max(0, contentHeight - height), targetY));
                if (Math.abs(targetY - contentY) < 0.5)
                    return;

                ensureVisibleAnimation.stop();
                if (Motion.reducedMotion(root.settingsService)
                        || Motion.elementMove(root.settingsService) <= 0) {
                    contentY = targetY;
                    return;
                }
                ensureVisibleAnimation.from = contentY;
                ensureVisibleAnimation.to = targetY;
                ensureVisibleAnimation.restart();
            }

            NumberAnimation {
                id: ensureVisibleAnimation
                target: overviewFlick
                property: "contentY"
                duration: Motion.elementMove(root.settingsService)
                easing.type: Motion.emphasizedDecel
            }

            Column {
                id: groupColumn
                width: overviewFlick.width
                spacing: 18

                Repeater {
                    model: ScriptModel {
                        objectProp: "key"
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

                            move: Transition {
                                NumberAnimation {
                                    properties: "x,y"
                                    duration: Motion.elementMove(root.settingsService)
                                    easing.type: Motion.emphasizedDecel
                                }
                            }

                            Repeater {
                                model: ScriptModel {
                                    objectProp: "modelKey"
                                    values: groupDelegate.modelData.windows
                                }

                                delegate: Item {
                                    id: windowCard

                                    required property var modelData
                                    required property int index
                                    // Flight API (discovered by collectFlightCards).
                                    readonly property bool flightCapable: true
                                    property int indexInGroup: index
                                    property int flightEpochLocal: -1
                                    property bool flightActive: false

                                    readonly property bool selected: root.selectedWindowKey === root.windowKey(modelData)
                                    readonly property bool minimized: !!(modelData && modelData.isMinimized)
                                    readonly property string iconSource: root.windowIcon(modelData)
                                    readonly property var miniRect: root.previewRect(modelData, groupDelegate.modelData.bounds, miniMap.width, miniMap.height)
                                    readonly property int thumbnailRevision: root.thumbnailProvider ? root.thumbnailProvider.revision : 0
                                    readonly property var thumbnailState: root.thumbnailProvider ? root.thumbnailProvider.thumbnailStateForWindow(modelData, thumbnailRevision) : null
                                    readonly property bool thumbnailAvailable: !!(thumbnailState && thumbnailState.ready && !thumbnailState.failed)
                                    readonly property string thumbnailSource: thumbnailAvailable && thumbnailState.path
                                        ? "file://" + String(thumbnailState.path) + "?v=" + String(thumbnailState.generation || 0)
                                        : ""

                                    width: Math.max(188, Math.min(236, groupDelegate.width))
                                    height: 164

                                    transform: [
                                        Translate {
                                            id: flyTranslate
                                            x: 0
                                            y: 0
                                        },
                                        Scale {
                                            id: flyScale
                                            origin.x: windowCard.width / 2
                                            origin.y: windowCard.height / 2
                                            xScale: 1
                                            // Keep axes locked; only xScale is animated.
                                            yScale: xScale
                                        }
                                    ]

                                    // Dual-branch content motion: spring when useSpring, else eased.
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: Motion.fadeFast(root.settingsService)
                                            easing.type: Motion.emphasizedDecel
                                        }
                                    }

                                    SpringAnimation {
                                        id: flyXSpring
                                        target: flyTranslate
                                        property: "x"
                                        spring: Motion.springPanel.spring
                                        damping: Motion.springPanel.damping
                                        epsilon: 0.0005
                                        onStopped: windowCard.maybeFinishFlight()
                                    }
                                    SpringAnimation {
                                        id: flyYSpring
                                        target: flyTranslate
                                        property: "y"
                                        spring: Motion.springPanel.spring
                                        damping: Motion.springPanel.damping
                                        epsilon: 0.0005
                                        onStopped: windowCard.maybeFinishFlight()
                                    }
                                    SpringAnimation {
                                        id: flyScaleSpring
                                        target: flyScale
                                        property: "xScale"
                                        spring: Motion.springSmooth.spring
                                        damping: Motion.springSmooth.damping
                                        epsilon: 0.001
                                        onStopped: windowCard.maybeFinishFlight()
                                    }

                                    NumberAnimation {
                                        id: flyXEase
                                        target: flyTranslate
                                        property: "x"
                                        duration: Motion.elementMove(root.settingsService)
                                        easing.type: Motion.emphasizedDecel
                                        onStopped: windowCard.maybeFinishFlight()
                                    }
                                    NumberAnimation {
                                        id: flyYEase
                                        target: flyTranslate
                                        property: "y"
                                        duration: Motion.elementMove(root.settingsService)
                                        easing.type: Motion.emphasizedDecel
                                        onStopped: windowCard.maybeFinishFlight()
                                    }
                                    NumberAnimation {
                                        id: flyScaleEase
                                        target: flyScale
                                        property: "xScale"
                                        duration: Motion.elementMove(root.settingsService)
                                        easing.type: Motion.emphasizedDecel
                                        onStopped: windowCard.maybeFinishFlight()
                                    }

                                    function stopFlightAnims() {
                                        flyXSpring.stop();
                                        flyYSpring.stop();
                                        flyScaleSpring.stop();
                                        flyXEase.stop();
                                        flyYEase.stop();
                                        flyScaleEase.stop();
                                    }

                                    function snapHome() {
                                        stopFlightAnims();
                                        flyTranslate.x = 0;
                                        flyTranslate.y = 0;
                                        flyScale.xScale = 1;
                                        opacity = 1;
                                        flightActive = false;
                                    }

                                    function snapAway() {
                                        stopFlightAnims();
                                        var off = root.flightOffsetForCard(windowCard, modelData);
                                        flyTranslate.x = off.x;
                                        flyTranslate.y = off.y;
                                        flyScale.xScale = off.scale;
                                        opacity = 0;
                                        flightActive = false;
                                    }

                                    function animateTo(tx, ty, sc, epoch) {
                                        flightEpochLocal = epoch;
                                        flightActive = true;
                                        stopFlightAnims();
                                        if (root.shouldAnimateFlight()) {
                                            flyXSpring.from = flyTranslate.x;
                                            flyXSpring.to = tx;
                                            flyYSpring.from = flyTranslate.y;
                                            flyYSpring.to = ty;
                                            flyScaleSpring.from = flyScale.xScale;
                                            flyScaleSpring.to = sc;
                                            flyXSpring.restart();
                                            flyYSpring.restart();
                                            flyScaleSpring.restart();
                                        } else {
                                            flyXEase.from = flyTranslate.x;
                                            flyXEase.to = tx;
                                            flyYEase.from = flyTranslate.y;
                                            flyYEase.to = ty;
                                            flyScaleEase.from = flyScale.xScale;
                                            flyScaleEase.to = sc;
                                            if (Motion.reducedMotion(root.settingsService) || flyXEase.duration <= 0) {
                                                flyTranslate.x = tx;
                                                flyTranslate.y = ty;
                                                flyScale.xScale = sc;
                                                maybeFinishFlight();
                                            } else {
                                                flyXEase.restart();
                                                flyYEase.restart();
                                                flyScaleEase.restart();
                                            }
                                        }
                                    }

                                    function maybeFinishFlight() {
                                        if (!flightActive)
                                            return;
                                        if (root.flightEpoch !== flightEpochLocal)
                                            return;
                                        var springing = flyXSpring.running || flyYSpring.running || flyScaleSpring.running
                                            || flyXEase.running || flyYEase.running || flyScaleEase.running;
                                        if (springing)
                                            return;
                                        flightActive = false;
                                        root.noteFlightFinished(flightEpochLocal);
                                    }

                                    function prepareEnter(epoch) {
                                        var off = root.flightOffsetForCard(windowCard, modelData);
                                        stopFlightAnims();
                                        flyTranslate.x = off.x;
                                        flyTranslate.y = off.y;
                                        flyScale.xScale = off.scale;
                                        opacity = 1;
                                        animateTo(0, 0, 1, epoch);
                                    }

                                    function prepareLeave(epoch) {
                                        var off = root.flightOffsetForCard(windowCard, modelData);
                                        opacity = 1;
                                        animateTo(off.x, off.y, off.scale, epoch);
                                    }

                                    onSelectedChanged: if (selected) root.selectedCardItem = windowCard
                                    onModelDataChanged: if (root.open && root.flightPhase === "open") root.requestThumbnailFor(modelData, false)

                                    Component.onCompleted: {
                                        if (selected)
                                            root.selectedCardItem = windowCard;
                                        // Late-created cards during open settle at home.
                                        if (root.flightPhase === "open" || root.flightPhase === "entering") {
                                            if (root.flightPhase === "open")
                                                snapHome();
                                        }
                                    }

                                    Component.onDestruction: {
                                        // No free-standing clone layers; transform state dies with the card.
                                        stopFlightAnims();
                                        if (root.selectedCardItem === windowCard)
                                            root.selectedCardItem = null;
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 16
                                        color: windowCard.selected ? "#76ffffff" : cardMouse.containsMouse ? "#44ffffff" : "#24ffffff"
                                        border.color: windowCard.selected ? "#a8ffffff" : "#34ffffff"
                                        border.width: windowCard.selected ? 2 : 1

                                        Behavior on color {
                                            ColorAnimation { duration: Motion.fadeFast(root.settingsService) }
                                        }

                                        Behavior on border.color {
                                            ColorAnimation { duration: Motion.fadeFast(root.settingsService) }
                                        }

                                        Behavior on border.width {
                                            NumberAnimation {
                                                duration: Motion.elementResize(root.settingsService)
                                                easing.type: Motion.emphasizedDecel
                                            }
                                        }
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
                                        clip: true

                                        Image {
                                            id: thumbnailImage

                                            anchors.fill: parent
                                            source: windowCard.thumbnailSource
                                            fillMode: Image.PreserveAspectCrop
                                            smooth: true
                                            mipmap: true
                                            asynchronous: true
                                            cache: false
                                            opacity: windowCard.minimized ? 0.62 : 1
                                            visible: windowCard.thumbnailSource.length > 0 && status !== Image.Error
                                            onStatusChanged: {
                                                if (status === Image.Error && windowCard.thumbnailAvailable && root.thumbnailProvider)
                                                    root.thumbnailProvider.markImageFailed(windowCard.modelData, "window overview thumbnail image failed to load");
                                            }
                                        }

                                        WindowPreviewFallback {
                                            anchors.fill: parent
                                            showGeometry: true
                                            geometryRect: windowCard.miniRect
                                            minimized: windowCard.minimized
                                            focused: !!(windowCard.modelData && windowCard.modelData.isFocused)
                                            visible: !thumbnailImage.visible
                                        }

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 6
                                            width: 24
                                            height: 24
                                            radius: 7
                                            color: "#e8ffffff"
                                            border.color: "#70ffffff"
                                            border.width: 1
                                            visible: thumbnailImage.visible && windowCard.iconSource.length > 0

                                            Image {
                                                anchors.centerIn: parent
                                                width: 17
                                                height: 17
                                                source: windowCard.iconSource
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                                mipmap: true
                                                asynchronous: true
                                            }
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

                                    TahoeSymbol {
                                        anchors.centerIn: appIcon
                                        name: "\ue8d0"
                                        color: "#5a626a"
                                        size: 17
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
                                        onEntered: {
                                            root.selectedWindowKey = root.windowKey(windowCard.modelData);
                                            if (root.flightPhase === "open")
                                                root.requestThumbnailFor(windowCard.modelData, false);
                                        }
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
