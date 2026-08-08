pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "Motion.js" as Motion
import "TahoeGlass.js" as GlassStyle
import "DynamicIslandMotion.js" as IslandMotion
import "settings/SettingsTheme.js" as Theme

PanelWindow {
    id: root

    property var appsService
    property var appMenuService
    property var niriService
    property var notificationsService
    property var batteryService
    property var controlsService
    property var fanService
    property var clipboardService
    property var screenshotService
    property var inputMethodService
    property var dynamicIslandService
    property var settingsService
    property bool fullscreenActive: false
    property real fullscreenTransition: fullscreenActive ? 1 : 0
    property bool controlCenterOpen: false
    property bool launchpadOpen: false
    property bool appMenuOpen: false
    property bool applicationMenuOpen: false
    property bool spotlightOpen: false
    property bool notificationCenterOpen: false
    property bool batteryPopupOpen: false
    property bool wifiPopupOpen: false
    property bool fanPopupOpen: false
    property bool clipboardPopupOpen: false
    property bool leftSidebarOpen: false
    property bool darkMode: false
    readonly property string activeApp: appsService && niriService ? appsService.windowAppLabel(niriService.focusedWindow || niriService.activeToplevel) : "桌面"
    // Number of retained notification history entries. Drives the bell
    // badge and lets DND-suppressed notifications remain visible.
    readonly property int notificationCount: notificationsService ? notificationsService.historyCount : 0
    readonly property int clipboardCount: clipboardService ? clipboardService.historyCount : 0
    readonly property bool dndEnabled: notificationsService ? notificationsService.dndEnabled : false
    readonly property bool dynamicIslandEnabled: settingsService ? !!settingsService.dynamicIslandEnabled : true
    readonly property bool dynamicIslandHideTopbarTime: settingsService ? !!settingsService.dynamicIslandHideTopbarTime : true
    readonly property bool dynamicIslandHoverExpand: settingsService ? !!settingsService.dynamicIslandHoverExpand : false
    // T08: TopBar resting clock is not blanked on non-owner outputs.
    // hideTopbarTime=true → Overlay shows base clock on every screen (including
    // non-owner); TopBar hides its time text. hideTopbarTime=false → TopBar
    // always shows ordinary time; Overlay only appears for owner activity.
    readonly property bool dynamicIslandOverlayHandlesResting: dynamicIslandEnabled && dynamicIslandHideTopbarTime
    readonly property bool showTopbarTimeFallback: !dynamicIslandEnabled || !dynamicIslandHideTopbarTime
    readonly property bool chipInteractive: dynamicIslandEnabled && !dynamicIslandOverlayHandlesResting
    readonly property int islandInputCutoutWidth: Math.min(root.width, root.dynamicIslandInputWidth())
    readonly property int islandInputCutoutLeft: Math.max(0, Math.floor((root.width - root.islandInputCutoutWidth) / 2))
    readonly property int islandInputCutoutRight: Math.min(root.width, root.islandInputCutoutLeft + root.islandInputCutoutWidth)
    readonly property bool batteryAvailable: !!batteryService && !!batteryService.available
    // Single InputMethod owner language glyph (中/EN/あ/한/Aa/--).
    readonly property string inputMethodDisplayText: inputMethodService
        ? String(inputMethodService.displayText || "--")
        : "--"
    readonly property color glassFill: darkMode ? "#d01d1f24" : GlassStyle.FillTopBar
    readonly property color glassStroke: darkMode ? "#38ffffff" : GlassStyle.StrokeTopBar
    // macOS-style: top bar blends into the wallpaper — fill is near-transparent
    // white so only the blur + text remain visible.
    readonly property color glassFillTransparent: darkMode ? "#101d1f24" : "#08ffffff"
    readonly property string accentId: settingsService ? settingsService.accentColor : "blue"
    // macOS menu bar text is white (rgba(255,255,255,0.9)) on any wallpaper —
    // readability comes from a faint shadow, not from dark text. The bar is
    // transparent so white text + subtle shadow matches macOS on light/dark.
    readonly property color topText: darkMode ? "#f5f7fb" : "#ffffff"
    // Unified top-bar text color: macOS uses one color for all menu-bar
    // labels — secondary text must not be a lighter gray (looked mismatched
    // on the transparent bar).
    readonly property color topTextSecondary: topText
    readonly property color statusText: topText
    readonly property color statusTextDisabled: darkMode ? "#73f5f7fb" : "#731d1d1f"
    readonly property color statusTextFaint: darkMode ? "#99f5f7fb" : "#991d1d1f"
    readonly property color statusAttention: Theme.statusAttention(darkMode)
    readonly property color accentColor: Theme.accent(darkMode, accentId)
    // Status-row hit target; slightly taller/wider so 18–20px symbols
    // optically match tray IconImage (16px full-bleed color icons).
    readonly property int statusItemHeight: 24
    readonly property int statusIconWidth: 28
    // TahoeSymbol display size (was 16; Material PNG padding made it look small).
    // 20 reads closer to tray IconImage 16px full-bleed; drop to 18 if crowded.
    readonly property int statusSymbolSize: 20
    readonly property int batteryItemMinWidth: 66
    readonly property int statusRadius: 7
    readonly property color buttonFill: "transparent"
    readonly property color buttonHover: Theme.buttonHover(darkMode)
    readonly property color buttonOpen: Theme.buttonOpen(darkMode)

    signal toggleAppMenu(var anchorRect)
    signal toggleApplicationMenu(var anchorRect)
    signal toggleControlCenter(var anchorRect)
    signal toggleSpotlight()
    signal toggleLaunchpad()
    signal toggleLeftSidebar()
    signal toggleNotifications(var anchorRect)
    signal toggleBattery(var anchorRect)
    signal toggleWifi(var anchorRect)
    signal toggleFan(var anchorRect)
    signal toggleClipboard(var anchorRect)
    signal triggerScreenshot()
    signal toggleInputMethod()
    signal openTrayMenu(var item, var anchorRect)

    // ==================================================================
    // F-10: keyboard focus model. The bar is click-focusable (OnDemand
    // layer interactivity, see focusable below); once it holds keyboard
    // focus, Tab/Backtab and arrow keys walk the visible interactive
    // entries in visual order and Return/Enter/Space activate the current
    // one. keyboardCurrent is the model (indicator + activation target);
    // QML focus itself stays on topbarKeyboardFocusCatcher so the chain is
    // stable even as services/tray/workspace entries appear or disappear.
    // ==================================================================
    property var keyboardCurrent: null
    // Last known position of keyboardCurrent in the entry list; survives the
    // current entry disappearing (service-gated button hidden, tray delegate
    // destroyed) so the next Tab continues from the neighbor instead of
    // jumping to the wrap edge (F3).
    property int keyboardIndex: -1
    // macOS-style focus visibility: the traversal ring shows only after
    // actual keyboard navigation. Pointer clicks still engage the model
    // (F-10: Tab continues from the pointer) but never summon the ring —
    // clicks used to latch a visible ring on the last-clicked entry.
    property bool keyboardRingVisible: false

    function keyboardEntryList() {
        var list = [];
        function push(item) {
            if (item && item.visible)
                list.push(item);
        }
        push(niriMenuButton);
        push(leftSidebarButton);
        push(applicationMenuButton);
        for (var i = 0; i < workspaceRepeater.count; ++i)
            push(workspaceRepeater.itemAt(i));
        if (root.chipInteractive)
            push(topbarTimeFallback);
        if (tray.visible) {
            var trayCount = tray.keyboardItemCount();
            for (var j = 0; j < trayCount; ++j)
                push(tray.keyboardItemAt(j));
        }
        push(notificationButton);
        push(clipboardButton);
        push(fanButton);
        push(batteryButton);
        push(wifiButton);
        push(spotlightButton);
        push(statusButton);
        return list;
    }

    function keyboardIndexOf(entry) {
        var list = root.keyboardEntryList();
        for (var i = 0; i < list.length; ++i) {
            if (list[i] === entry)
                return i;
        }
        return -1;
    }

    // Move the keyboard current by delta entries (wrapping). Entries that
    // became invisible since last navigation are skipped by the list.
    function keyboardStep(delta) {
        // Real keyboard traversal: reveal the ring.
        root.keyboardRingVisible = true;
        var list = root.keyboardEntryList();
        if (list.length === 0) {
            root.keyboardCurrent = null;
            root.keyboardIndex = -1;
            return;
        }
        var idx = root.keyboardIndexOf(root.keyboardCurrent);
        var next = -1;
        if (idx >= 0) {
            root.keyboardIndex = idx;
            next = (idx + delta + list.length) % list.length;
        } else if (root.keyboardCurrent !== null) {
            // Current entry disappeared (hidden/destroyed): continue from its
            // last known position rather than jumping to the wrap edge. The
            // remaining entries shifted left by one: the forward neighbor is
            // the item that slid into the current's old slot; the backward
            // neighbor is the one before the old slot (no clamping — when the
            // disappeared entry was the last one, the true neighbor sits at
            // keyboardIndex - 1, not at the clamped tail).
            if (root.keyboardIndex < 0) {
                next = delta > 0 ? 0 : list.length - 1;
            } else if (delta > 0) {
                next = Math.min(root.keyboardIndex, list.length - 1);
            } else {
                next = (root.keyboardIndex - 1 + list.length) % list.length;
            }
        } else {
            next = delta > 0 ? 0 : list.length - 1;
        }
        root.keyboardCurrent = list[next];
        root.keyboardIndex = next;
    }

    // Mouse engagement: a click makes the entry the keyboard current so the
    // next Tab continues from where the pointer was.
    function engageKeyboardEntry(entry) {
        if (!entry)
            return;
        // Pointer engagement repositions the walk without showing the ring.
        root.keyboardRingVisible = false;
        root.keyboardCurrent = entry;
        var idx = root.keyboardIndexOf(entry);
        root.keyboardIndex = idx >= 0 ? idx : -1;
    }

    function activateKeyboardCurrent() {
        var entry = root.keyboardCurrent;
        if (!entry || typeof entry.keyboardActivate !== "function")
            return;
        // Stale currents (destroyed tray icons / workspace churn) fall out of
        // the fresh entry list; never activate them.
        if (root.keyboardIndexOf(entry) < 0) {
            root.keyboardCurrent = null;
            return;
        }
        entry.keyboardActivate();
    }

    function anchorRectFor(item) {
        if (!item)
            return null;

        var rect = root.itemRect(item);
        return {
            "x": Math.round(rect.x),
            "y": Math.round(rect.y),
            "width": Math.round(rect.width),
            "height": Math.round(rect.height)
        };
    }

    function dynamicIslandInputWidth() {
        if (!root.dynamicIslandOverlayHandlesResting)
            return 0;

        var presentation = root.dynamicIslandService
            ? String(root.dynamicIslandService.presentation || "resting_time")
            : "resting_time";
        switch (presentation) {
        case "expanded_media":
            return IslandMotion.v2MediaExpandedWidthMax;
        case "expanded_timer":
            return IslandMotion.v2TimerExpandedWidthMax;
        case "transient_notification":
            return IslandMotion.v2NotificationExpandedWidthMax;
        case "transient_osd":
            return IslandMotion.v2OsdWidthMax;
        case "transient_workspace":
        case "resting_timer":
        case "transient_timer_complete":
            return IslandMotion.v2WorkspaceWidthMax;
        case "resting_media":
        case "resting_time":
        default:
            // The visual clock may be narrower, but the stable center reserve is
            // intentionally non-interactive while the overlay owns the island.
            return IslandMotion.v2CompactMediaWidthMax;
        }
    }

    // Hard unmap with fullscreen chrome hide. Keeping the surface mapped until
    // the opacity animation finished left TopBar alive while Dynamic Island
    // unmapped; on workspace switch away from a fullscreen game the island
    // remapped under the still-mapped topbar and disappeared behind glass.
    visible: !root.fullscreenActive
    // P02: freeze scene-graph frames while this surface is unmapped/faded out.
    // Extends the existing visible gate onto updatesEnabled (not a parallel path).
    updatesEnabled: visible

    Behavior on fullscreenTransition {
        NumberAnimation {
            duration: Motion.elementResize(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }
    }

    anchors {
        left: true
        right: true
        top: true
    }

    // DynamicIslandOverlay is the sole input owner for the center span. A real
    // cutout lets its native click/swipe/wheel lifecycle work regardless of
    // sibling Top-layer stacking order.
    mask: Region {
        Region {
            x: 0
            y: 0
            width: root.dynamicIslandOverlayHandlesResting
                ? root.islandInputCutoutLeft
                : root.width
            height: root.height
        }
        Region {
            x: root.islandInputCutoutRight
            y: 0
            width: root.dynamicIslandOverlayHandlesResting
                ? Math.max(0, root.width - root.islandInputCutoutRight)
                : 0
            height: root.height
        }
    }

    exclusiveZone: 40
    implicitHeight: 40
    color: "transparent"
    WlrLayershell.namespace: "tahoe-topbar"
    // F-10: OnDemand keyboard interactivity — niri hands keyboard focus to
    // the bar when it is clicked (or focused), which is what lets Tab/arrow
    // traversal reach the bar instead of switching windows. When the bar is
    // not focused, Tab keeps compositor semantics.
    focusable: true

    // Sole QML focus owner for keyboard traversal. Entries never take QML
    // focus: the chain lives in keyboardCurrent so it survives entries
    // appearing/disappearing (services, tray, workspaces).
    Item {
        id: topbarKeyboardFocusCatcher

        objectName: "topbarKeyboardFocusCatcher"
        focus: true
        // The bar QWindow's active state tracks its wl_keyboard focus
        // exactly. When the compositor moves keyboard focus off the bar
        // (click elsewhere, popup dismissed, panel took focus) the traversal
        // indicator must clear — clicks used to leave the focus ring latched
        // on the last-clicked entry forever. Pure Tab traversal keeps the
        // bar focused, so the ring survives it (F-10 intact).
        readonly property bool barWindowActive: Window.active
        onBarWindowActiveChanged: {
            if (!barWindowActive) {
                root.keyboardCurrent = null;
                root.keyboardIndex = -1;
                root.keyboardRingVisible = false;
            }
        }
        Keys.onTabPressed: root.keyboardStep(1)
        Keys.onBacktabPressed: root.keyboardStep(-1)
        Keys.onRightPressed: root.keyboardStep(1)
        Keys.onLeftPressed: root.keyboardStep(-1)
        Keys.onReturnPressed: root.activateKeyboardCurrent()
        Keys.onEnterPressed: root.activateKeyboardCurrent()
        Keys.onSpacePressed: root.activateKeyboardCurrent()
    }

    // macOS-style top bar: fully transparent — no glass, no blur, the bar
    // is invisible and only the content (text/icons) floats on the wallpaper.
    // The PanelWindow stays transparent with exclusiveZone 40 so window
    // layout doesn't shift.
    Item {
        id: barSurface

        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        opacity: 1 - root.fullscreenTransition

        Item {
            id: topBarContent

            anchors.fill: parent
            // Inset content inside the floating bar surface so the end
            // children (status/control buttons and niri menu) clear the rounded
            // caps. The surface's radius is 18, so anything within ~14px
            // of the ends would clip under the arc.
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            transform: Translate {
                y: -root.fullscreenTransition * root.height
            }
            // T12: stable reserve covers max compact media so clock↔media does not
            // shove left/right clusters. Not tied to current island state width.
            readonly property int centerReserveWidth: IslandMotion.v2CompactMediaWidthMax

            Item {
                id: islandReserve

                anchors.centerIn: parent
                width: topBarContent.centerReserveWidth
                height: parent.height
            }

            Row {
                id: leftCluster

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, islandReserve.x - 14)
                height: 24
                spacing: 14
                clip: true

                Item {
                    id: niriMenuButton

                    objectName: "topbarEntryNiriMenu"
                    // F-10: keyboard activation mirrors the MouseArea click path.
                    function keyboardActivate() {
                        root.toggleAppMenu(root.anchorRectFor(niriMenuButton));
                    }

                    width: 30
                    height: 24
                    scale: Motion.pressScaleFor(root.settingsService, niriMenuMouse.pressed)
                    opacity: niriMenuMouse.pressed ? 0.75 : 1

                    Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                    Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: root.appMenuOpen
                            ? "#32ffffff"
                            : (niriMenuMouse.containsMouse ? root.buttonHover : "transparent")
                        border.width: 0

                        Behavior on color {
                            ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                        }
                    }

                    // F-10: keyboard focus indicator.
                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: "transparent"
                        border.color: root.accentColor
                        border.width: 1
                        visible: root.keyboardRingVisible && root.keyboardCurrent === niriMenuButton
                        z: 4
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: Quickshell.shellPath("assets/icons/niri-icon-smol.png")
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }

                    MouseArea {
                        id: niriMenuMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.engageKeyboardEntry(niriMenuButton);
                            root.toggleAppMenu(root.anchorRectFor(niriMenuButton));
                        }
                    }
                }

                Item {
                    id: leftSidebarButton

                    objectName: "topbarEntryLeftSidebar"
                    // F-10: keyboard activation mirrors the MouseArea click path.
                    function keyboardActivate() {
                        root.toggleLeftSidebar();
                    }

                    width: 30
                    height: 24
                    scale: Motion.pressScaleFor(root.settingsService, leftSidebarMouse.pressed)
                    opacity: leftSidebarMouse.pressed ? 0.75 : 1

                    Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                    Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: root.leftSidebarOpen ? root.buttonOpen : (leftSidebarMouse.containsMouse ? root.buttonHover : "transparent")
                        border.width: 0

                        Behavior on color {
                            ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                        }
                    }

                    // F-10: keyboard focus indicator.
                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: "transparent"
                        border.color: root.accentColor
                        border.width: 1
                        visible: root.keyboardRingVisible && root.keyboardCurrent === leftSidebarButton
                        z: 4
                    }

                    TahoeSymbol {
                        anchors.centerIn: parent
                        name: "\ue2bd" // wb_cloudy
                        color: root.leftSidebarOpen ? root.accentColor : root.topTextSecondary
                        size: root.statusSymbolSize
                    }

                    MouseArea {
                        id: leftSidebarMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.engageKeyboardEntry(leftSidebarButton);
                            root.toggleLeftSidebar();
                        }
                    }
                }

                Text {
                    text: root.activeApp
                    color: root.topTextSecondary
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    width: Math.min(implicitWidth, root.width < 1500 ? 168 : 220)
                    height: 24
                }

                Item {
                    id: applicationMenuButton

                    objectName: "topbarEntryAppMenu"
                    // F-10: keyboard activation mirrors the MouseArea click path.
                    function keyboardActivate() {
                        root.toggleApplicationMenu(root.anchorRectFor(applicationMenuButton));
                    }

                    width: visible ? Math.min(applicationMenuLabel.implicitWidth + 18, root.width < 1500 ? 112 : 152) : 0
                    height: 24
                    visible: !!root.appMenuService
                    scale: Motion.pressScaleFor(root.settingsService, applicationMenuMouse.pressed)
                    opacity: applicationMenuMouse.pressed ? 0.75 : 1

                    Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                    Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: root.applicationMenuOpen ? "#32ffffff" : (applicationMenuMouse.containsMouse ? "#24ffffff" : "transparent")
                        border.width: 0

                        Behavior on color {
                            ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                        }
                    }

                    // F-10: keyboard focus indicator.
                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: "transparent"
                        border.color: root.accentColor
                        border.width: 1
                        visible: root.keyboardRingVisible && root.keyboardCurrent === applicationMenuButton
                        z: 4
                    }

                    Text {
                        id: applicationMenuLabel
                        anchors.centerIn: parent
                        width: Math.max(0, parent.width - 18)
                        text: root.appMenuService ? root.appMenuService.menuTitle : "应用菜单"
                        color: root.topText
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        // macOS: white menu-bar text stays readable on any
                        // wallpaper via a faint dark shadow.
                        style: Text.Sunken
                        styleColor: "#66000000"
                    }

                    MouseArea {
                        id: applicationMenuMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.engageKeyboardEntry(applicationMenuButton);
                            root.toggleApplicationMenu(root.anchorRectFor(applicationMenuButton));
                        }
                    }
                }

                Row {
                    y: 2
                    spacing: 5

                    Repeater {
                        id: workspaceRepeater

                        model: ScriptModel {
                            values: root.niriService ? root.niriService.visibleWindowsets : []
                        }

                        delegate: Item {
                            id: workspaceEntry

                            required property var modelData
                            required property int index
                            objectName: "topbarEntryWorkspace"
                            // F-10: keyboard activation mirrors the MouseArea click path.
                            function keyboardActivate() {
                                if (modelData.canActivate && root.niriService)
                                    root.niriService.activateWorkspace(modelData);
                            }

                            width: 28
                            height: 20
                            scale: Motion.pressScaleFor(root.settingsService, workspaceMouse.pressed && modelData.canActivate)
                            opacity: workspaceMouse.pressed && modelData.canActivate ? 0.75 : 1

                            Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                            Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: modelData.active
                                    ? "#32ffffff"
                                    : (workspaceMouse.containsMouse ? root.buttonHover : "#18ffffff")
                                border.color: modelData.urgent ? "#ccff453a" : "#36ffffff"
                                border.width: 1

                                Behavior on color {
                                    ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                                }
                            }

                            // F-10: keyboard focus indicator.
                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: "transparent"
                                border.color: root.accentColor
                                border.width: 1
                                visible: root.keyboardRingVisible && root.keyboardCurrent === workspaceEntry
                                z: 4
                            }

                            Text {
                                anchors.centerIn: parent
                                text: root.niriService ? root.niriService.workspaceLabel(modelData, index) : String(index + 1)
                                color: root.topText
                                font.pixelSize: 11
                                font.weight: modelData.active ? Font.DemiBold : Font.Normal
                            }

                            MouseArea {
                                id: workspaceMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: modelData.canActivate ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    root.engageKeyboardEntry(workspaceEntry);
                                    if (root.niriService)
                                        root.niriService.activateWorkspace(modelData);
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                id: rightCluster

                anchors.left: islandReserve.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                spacing: 9
                clip: true

                Item {
                    Layout.fillWidth: true
                }

            Tray {
                id: tray

                panelWindow: root
                settingsService: root.settingsService
                darkMode: root.darkMode
                Layout.preferredWidth: visible ? implicitWidth : 0
                Layout.preferredHeight: implicitHeight
                Layout.alignment: Qt.AlignVCenter
                onOpenMenuRequested: function(item, anchorRect) {
                    root.openTrayMenu(item, anchorRect);
                }
            }

            Item {
                id: notificationButton

                objectName: "topbarEntryNotifications"
                // F-10: keyboard activation mirrors the MouseArea click path.
                function keyboardActivate() {
                    root.toggleNotifications(root.anchorRectFor(notificationButton));
                }

                Layout.preferredWidth: root.statusIconWidth
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                scale: Motion.pressScaleFor(root.settingsService, badgeMouse.pressed)
                opacity: badgeMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.notificationCenterOpen ? root.buttonOpen : (badgeMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0

                    Behavior on color {
                        ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                    }
                }

                // F-10: keyboard focus indicator.
                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: "transparent"
                    border.color: root.accentColor
                    border.width: 1
                    visible: root.keyboardRingVisible && root.keyboardCurrent === notificationButton
                    z: 4
                }

                TahoeSymbol {
                    anchors.centerIn: parent
                    name: root.dndEnabled ? "\ue7f6" : "\ue7f4"
                    color: root.statusText
                        styleColor: "#66000000"
                    size: root.statusSymbolSize
                    opacity: root.notificationCount > 0 || root.dndEnabled ? 1 : 0.68
                }

                Rectangle {
                    id: notificationBadge
                    readonly property bool hasBadge: root.notificationCount > 0
                    // Count pip, top-right of the bell.
                    x: parent.width - width - 3
                    y: 1
                    width: countLabel.implicitWidth + 8
                    height: 14
                    radius: 7
                    color: root.statusAttention
                    border.color: "#ffffff"
                    border.width: 1
                    opacity: hasBadge ? 1 : 0
                    scale: hasBadge ? 1 : 0.76
                    visible: hasBadge || opacity > 0.01

                    Behavior on opacity {
                        NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                    }

                    Behavior on scale {
                        NumberAnimation { duration: Motion.elementResize(root.settingsService); easing.type: Motion.emphasizedDecel }
                    }

                    Text {
                        id: countLabel
                        anchors.centerIn: parent
                        text: root.notificationCount > 9 ? "9+" : root.notificationCount
                        color: "#ffffff"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: badgeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.engageKeyboardEntry(notificationButton);
                        root.toggleNotifications(root.anchorRectFor(notificationButton));
                    }
                }
            }

            Item {
                id: clipboardButton

                objectName: "topbarEntryClipboard"
                // F-10: keyboard activation mirrors the MouseArea click path.
                function keyboardActivate() {
                    root.toggleClipboard(root.anchorRectFor(clipboardButton));
                }

                Layout.preferredWidth: visible ? root.statusIconWidth : 0
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                visible: !!root.clipboardService
                scale: Motion.pressScaleFor(root.settingsService, clipboardMouse.pressed)
                opacity: clipboardMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.clipboardPopupOpen ? root.buttonOpen : (clipboardMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0

                    Behavior on color {
                        ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                    }
                }

                // F-10: keyboard focus indicator.
                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: "transparent"
                    border.color: root.accentColor
                    border.width: 1
                    visible: root.keyboardRingVisible && root.keyboardCurrent === clipboardButton
                    z: 4
                }

                TahoeSymbol {
                    anchors.centerIn: parent
                    name: "\ue14f"
                    color: root.clipboardService && root.clipboardService.available ? root.statusText : root.statusTextDisabled
                    size: root.statusSymbolSize
                    opacity: root.clipboardService && root.clipboardService.available ? 1 : 0.5
                }

                Rectangle {
                    id: clipboardBadge
                    readonly property bool hasBadge: root.clipboardCount > 0
                    width: countText.implicitWidth + 7
                    height: 13
                    radius: 6.5
                    x: parent.width - width - 2
                    y: 1
                    color: root.statusAttention
                    border.color: "#ffffff"
                    border.width: 1
                    opacity: hasBadge ? 1 : 0
                    scale: hasBadge ? 1 : 0.76
                    visible: hasBadge || opacity > 0.01

                    Behavior on opacity {
                        NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                    }

                    Behavior on scale {
                        NumberAnimation { duration: Motion.elementResize(root.settingsService); easing.type: Motion.emphasizedDecel }
                    }

                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: root.clipboardCount > 9 ? "9+" : root.clipboardCount
                        color: "#ffffff"
                        font.pixelSize: 8
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: clipboardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.engageKeyboardEntry(clipboardButton);
                        root.toggleClipboard(root.anchorRectFor(clipboardButton));
                    }
                }
            }

            Item {
                id: fanButton

                objectName: "topbarEntryFan"
                // F-10: keyboard activation mirrors the MouseArea click path.
                function keyboardActivate() {
                    root.toggleFan(root.anchorRectFor(fanButton));
                }

                Layout.preferredWidth: visible ? root.statusIconWidth : 0
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                visible: !!root.fanService
                scale: Motion.pressScaleFor(root.settingsService, fanMouse.pressed)
                opacity: fanMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.fanPopupOpen ? root.buttonOpen : (fanMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0

                    Behavior on color {
                        ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                    }
                }

                // F-10: keyboard focus indicator.
                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: "transparent"
                    border.color: root.accentColor
                    border.width: 1
                    visible: root.keyboardRingVisible && root.keyboardCurrent === fanButton
                    z: 4
                }

                TahoeSymbol {
                    anchors.centerIn: parent
                    // Semantic "fan" → assets/icons/symbols/fan.png (bitmap-only;
                    // classic Material Icons has no mode_fan; e332 is toys/car).
                    name: "fan"
                    color: root.fanService && root.fanService.available
                        ? root.statusText
                        : root.statusTextDisabled
                    size: root.statusSymbolSize
                    opacity: root.fanService && root.fanService.available
                        ? (root.fanService.autoMode ? 0.76 : 1)
                        : 0.5
                }

                MouseArea {
                    id: fanMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.engageKeyboardEntry(fanButton);
                        root.toggleFan(root.anchorRectFor(fanButton));
                    }
                }
            }

            Item {
                id: batteryButton

                objectName: "topbarEntryBattery"
                // F-10: keyboard activation mirrors the MouseArea click path.
                function keyboardActivate() {
                    root.toggleBattery(root.anchorRectFor(batteryButton));
                }

                Layout.preferredWidth: visible ? Math.max(root.batteryItemMinWidth, batteryContent.implicitWidth + 12) : 0
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                visible: root.batteryAvailable
                scale: Motion.pressScaleFor(root.settingsService, batteryMouse.pressed)
                opacity: batteryMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.batteryPopupOpen ? root.buttonOpen : (batteryMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0

                    Behavior on color {
                        ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                    }
                }

                // F-10: keyboard focus indicator.
                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: "transparent"
                    border.color: root.accentColor
                    border.width: 1
                    visible: root.keyboardRingVisible && root.keyboardCurrent === batteryButton
                    z: 4
                }

                RowLayout {
                    id: batteryContent

                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: root.batteryService ? root.batteryService.roundedPercentage + "%" : ""
                        color: root.statusText
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 14
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            id: batteryOutline
                            x: 0
                            y: 1.5
                            width: 20
                            height: 11
                            radius: 3
                            color: "transparent"
                            border.color: root.statusTextFaint
                            border.width: 1

                            Rectangle {
                                id: batteryFill
                                x: 2
                                y: 2
                                width: root.batteryService ? Math.max(2, (parent.width - 4) * root.batteryService.roundedPercentage / 100) : 2
                                height: parent.height - 4
                                radius: 2
                                color: root.batteryService && root.batteryService.roundedPercentage <= 15 && root.batteryService.onBattery
                                    ? root.statusAttention
                                    : root.statusText

                                Behavior on width {
                                    NumberAnimation { duration: Motion.elementResize(root.settingsService); easing.type: Motion.emphasizedDecel }
                                }

                                Behavior on color {
                                    ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                                }
                            }
                        }

                        Rectangle {
                            x: 21
                            y: 5
                            width: 2
                            height: 4
                            radius: 1
                            color: root.statusTextFaint
                        }
                    }
                }

                MouseArea {
                    id: batteryMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.engageKeyboardEntry(batteryButton);
                        root.toggleBattery(root.anchorRectFor(batteryButton));
                    }
                }
            }

            Item {
                id: inputMethodButton

                Layout.preferredWidth: visible ? root.statusItemHeight : 0
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                // Show the input-method label (中/EN/あ) instead of the tray's
                // gray fcitx icon — macOS uses a text indicator for IME.
                visible: !!root.inputMethodService && root.inputMethodService.available
                scale: Motion.pressScaleFor(root.settingsService, inputMethodMouse.pressed)
                opacity: inputMethodMouse.pressed ? 0.75 : (root.inputMethodService && root.inputMethodService.available ? 1 : 0.55)

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: inputMethodMouse.containsMouse ? root.buttonHover : root.buttonFill
                    border.width: 0

                    Behavior on color {
                        ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                    }
                }

                Text {
                    id: inputMethodLabel
                    anchors.centerIn: parent
                    // Unique InputMethod.displayText consumer — 中 / EN / あ / 한 / Aa / --
                    text: root.inputMethodDisplayText
                    color: root.statusText
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    style: Text.Sunken
                    styleColor: "#66000000"
                }

                MouseArea {
                    id: inputMethodMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleInputMethod()
                }
            }

            Item {
                id: wifiButton

                objectName: "topbarEntryWifi"
                // F-10: keyboard activation mirrors the MouseArea click path.
                function keyboardActivate() {
                    root.toggleWifi(root.anchorRectFor(wifiButton));
                }

                Layout.preferredWidth: visible ? root.statusIconWidth : 0
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                visible: !!root.controlsService
                scale: Motion.pressScaleFor(root.settingsService, wifiMouse.pressed)
                opacity: wifiMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.wifiPopupOpen ? root.buttonOpen : (wifiMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0

                    Behavior on color {
                        ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                    }
                }

                // F-10: keyboard focus indicator.
                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: "transparent"
                    border.color: root.accentColor
                    border.width: 1
                    visible: root.keyboardRingVisible && root.keyboardCurrent === wifiButton
                    z: 4
                }

                TahoeSymbol {
                    anchors.centerIn: parent
                    name: "\ue63e"
                    color: root.statusText
                        styleColor: "#66000000"
                    size: root.statusSymbolSize
                    opacity: root.controlsService && root.controlsService.wifiEnabled ? 1 : 0.45
                }

                MouseArea {
                    id: wifiMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.engageKeyboardEntry(wifiButton);
                        root.toggleWifi(root.anchorRectFor(wifiButton));
                    }
                }
            }

            Item {
                id: spotlightButton

                objectName: "topbarEntrySpotlight"
                // F-10: keyboard activation mirrors the MouseArea click path.
                function keyboardActivate() {
                    root.toggleSpotlight();
                }

                Layout.preferredWidth: root.statusIconWidth
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                scale: Motion.pressScaleFor(root.settingsService, spotlightMouse.pressed)
                opacity: spotlightMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.spotlightOpen ? root.buttonOpen : (spotlightMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0

                    Behavior on color {
                        ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                    }
                }

                // F-10: keyboard focus indicator.
                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: "transparent"
                    border.color: root.accentColor
                    border.width: 1
                    visible: root.keyboardRingVisible && root.keyboardCurrent === spotlightButton
                    z: 4
                }

                TahoeSymbol {
                    anchors.centerIn: parent
                    name: "\ue8b6"
                    color: root.statusText
                        styleColor: "#66000000"
                    size: root.statusSymbolSize
                }

                MouseArea {
                    id: spotlightMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.engageKeyboardEntry(spotlightButton);
                        root.toggleSpotlight();
                    }
                }
            }

            Item {
                id: statusButton

                objectName: "topbarEntryStatus"
                // F-10: keyboard activation mirrors the MouseArea click path.
                function keyboardActivate() {
                    root.toggleControlCenter(root.anchorRectFor(statusButton));
                }

                Layout.preferredWidth: root.statusIconWidth
                Layout.preferredHeight: root.statusItemHeight
                Layout.alignment: Qt.AlignVCenter
                scale: Motion.pressScaleFor(root.settingsService, statusMouse.pressed)
                opacity: statusMouse.pressed ? 0.75 : 1

                Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }
                Behavior on opacity { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: root.controlCenterOpen ? root.buttonOpen : (statusMouse.containsMouse ? root.buttonHover : root.buttonFill)
                    border.width: 0

                    Behavior on color {
                        ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                    }
                }

                // F-10: keyboard focus indicator.
                Rectangle {
                    anchors.fill: parent
                    radius: root.statusRadius
                    color: "transparent"
                    border.color: root.accentColor
                    border.width: 1
                    visible: root.keyboardRingVisible && root.keyboardCurrent === statusButton
                    z: 4
                }

                Item {
                    anchors.centerIn: parent
                    width: 18
                    height: 14

                    Rectangle {
                        x: 0
                        y: 3
                        width: 18
                        height: 2
                        radius: 1
                        color: root.statusText
                        opacity: 0.86
                    }

                    Rectangle {
                        x: 3
                        y: 0
                        width: 6
                        height: 8
                        radius: 3
                        color: root.statusText
                    }

                    Rectangle {
                        x: 0
                        y: 10
                        width: 18
                        height: 2
                        radius: 1
                        color: root.statusText
                        opacity: 0.86
                    }

                    Rectangle {
                        x: 10
                        y: 7
                        width: 6
                        height: 8
                        radius: 3
                        color: root.statusText
                    }
                }

                MouseArea {
                    id: statusMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.engageKeyboardEntry(statusButton);
                        root.toggleControlCenter(root.anchorRectFor(statusButton));
                    }
                }
            }
            }

            // F-10: keyboard focus indicator for the island chip entry
            // (sibling of the chip Text, behind it at z:1 vs z:2).
            Rectangle {
                id: islandChipFocusRing

                anchors.centerIn: topbarTimeFallback
                width: topbarTimeFallback.width + 12
                height: topbarTimeFallback.height + 8
                radius: 9
                color: "transparent"
                border.color: root.accentColor
                border.width: 1
                visible: root.keyboardRingVisible && root.keyboardCurrent === topbarTimeFallback
                z: 1
            }

            // T12: ordinary readable time when island is disabled or Overlay does
            // not own resting (hideTopbarTime=false). No faux island chip.
            Text {
                id: topbarTimeFallback

                anchors.centerIn: islandReserve
                z: 2
                objectName: "topbarEntryIslandChip"
                // F-10: keyboard activation mirrors the chip MouseArea's
                // left-click path.
                function keyboardActivate() {
                    if (root.dynamicIslandService)
                        root.dynamicIslandService.handleChipClick(
                            Qt.LeftButton,
                            root.screen ? String(root.screen.name || "") : "");
                }
                visible: root.showTopbarTimeFallback
                text: root.dynamicIslandService
                      ? String(root.dynamicIslandService.fallbackTimeText || "")
                      : ""
                color: root.topText
                font.pixelSize: 13
                font.weight: Font.DemiBold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                style: Text.Sunken
                styleColor: "#66000000"
                elide: Text.ElideRight
                maximumLineCount: 1
                width: Math.min(islandReserve.width, Math.max(implicitWidth, 1))

                MouseArea {
                    anchors.fill: parent
                    enabled: root.chipInteractive && topbarTimeFallback.visible
                    hoverEnabled: root.chipInteractive
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: root.chipInteractive ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: function(mouse) {
                        root.engageKeyboardEntry(topbarTimeFallback);
                        if (root.dynamicIslandService)
                            root.dynamicIslandService.handleChipClick(
                                mouse.button,
                                root.screen ? String(root.screen.name || "") : "");
                    }
                    onEntered: {
                        if (!root.dynamicIslandHoverExpand || !root.dynamicIslandService)
                            return;
                        topbarIslandHoverCollapse.stop();
                        topbarIslandHoverExpand.restart();
                    }
                    onExited: {
                        topbarIslandHoverExpand.stop();
                        if (root.dynamicIslandHoverExpand && root.dynamicIslandService)
                            topbarIslandHoverCollapse.restart();
                    }
                }

                Timer {
                    id: topbarIslandHoverExpand
                    interval: IslandMotion.hoverExpandDelayMs
                    repeat: false
                    onTriggered: {
                        if (root.dynamicIslandService)
                            root.dynamicIslandService.requestHoverExpand(
                                root.screen ? String(root.screen.name || "") : "");
                    }
                }

                Timer {
                    id: topbarIslandHoverCollapse
                    interval: IslandMotion.hoverCollapseDelayMs
                    repeat: false
                    onTriggered: {
                        if (root.dynamicIslandService)
                            root.dynamicIslandService.requestHoverCollapse();
                    }
                }
            }
        }
    }

}
