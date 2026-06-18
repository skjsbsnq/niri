pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property var appsService
    property var niriService
    property bool launchpadOpen: false
    // See shell.qml useSpring. Spring on Image geometry corrupts textures on
    // VMware/software GPUs; NumberAnimation is safe. Default false.
    property bool useSpring: false
    property bool darkMode: false
    property real dockMouseX: -10000
    property bool dockHovered: false
    property bool pointerDragActive: false
    property int dragTargetVisualIndex: -1
    readonly property bool hasWindows: niriService && niriService.windowList && niriService.windowList.length > 0
    readonly property color glassFill: darkMode ? "#d01d1f24" : GlassStyle.FillDock
    readonly property color glassStroke: darkMode ? "#38ffffff" : GlassStyle.StrokeDock
    readonly property color dockText: darkMode ? "#f5f7fb" : "#202124"

    signal toggleLaunchpad()

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
    // Range ~150px (web uses 195), peak scale 1.5 (web uses 1.7). Wider
    // range + bigger peak is what makes the neighbor-coupling wave visible.
    function proximityScale(item) {
        if (pointerDragActive || !dockHovered || !item || !dockSurface)
            return 1.0;

        var point = item.mapToItem(dockSurface, item.width / 2, item.height / 2);
        var distance = Math.abs(dockMouseX - point.x);
        var influence = Math.max(0, 1 - distance / 150);
        return 1.0 + influence * 0.5;
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

    function pinnedVisualIndexForRowX(rowX) {
        var count = root.appsService && root.appsService.pinnedApps ? root.appsService.pinnedApps.length : 0;
        if (count <= 1)
            return -1;

        var itemWidth = 62;
        var step = itemWidth + dockRow.spacing;
        for (var i = 1; i < count; i++) {
            var center = i * step + itemWidth / 2;
            if (rowX < center)
                return i;
        }

        return count - 1;
    }

    function updatePinnedDragTarget(item, mouseX, mouseY) {
        var point = item.mapToItem(dockRow, mouseX, mouseY);
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
        interval: 90
        repeat: false
        onTriggered: root.resetDockHover()
    }

    anchors {
        left: true
        right: true
        bottom: true
    }

    exclusiveZone: 98
    implicitHeight: 132
    color: "transparent"
    WlrLayershell.namespace: "tahoe-dock"

    TahoeGlass.regions: [
        TahoeGlassRegion {
            item: dockSurface
            material: dockSurface.tahoeGlassMaterial
            radius: dockSurface.tahoeGlassRadius
            blur: false
            shadow: false
            clip: true
            // Keep the dock in its quiet QML-painted resting surface. Any
            // compositor-owned dock material becomes the heavy full-width bar
            // after a click/drag-triggered repaint.
            interaction: 0.0
            materialAlpha: 0.0
            enabled: dockSurface.opacity > 0.01
        }
    ]

    Rectangle {
        id: dockSurface
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialDock
        readonly property real tahoeGlassRadius: GlassStyle.RadiusDock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        width: Math.min(parent.width - 28, dockRow.implicitWidth + 34)
        height: 78
        radius: tahoeGlassRadius
        color: root.glassFill
        opacity: 1

        Behavior on opacity {
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
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
            spacing: 8

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
                    property real bounceOffset: 0
                    property bool suppressNextClick: false
                    readonly property bool hovered: !root.pointerDragActive && iconMouse.containsMouse
                    readonly property bool running: modelData.shellAction !== "launchpad"
                        && root.appsService
                        && root.niriService
                        && root.appsService.appHasRunningWindow(modelData, root.niriService.windowList)
                    readonly property real lift: (magnification - 1.0) * 22 + (hovered ? 3 : 0)

                    // Fixed width. NOTE: width must NOT depend on
                    // magnification — proximityScale() reads this delegate's
                    // geometry to compute the icon center, so a
                    // magnification-driven width creates a binding loop
                    // (width -> magnification -> proximityScale -> width)
                    // that runs away and crashes Quickshell. The wave feel
                    // comes from the icon scale + lift + Row spacing spring
                    // instead.
                    width: 62
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
                                    root.appsService.openFilesWithApp(pinnedButton.modelData, drop.urls);
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
                        color: root.launchpadOpen && modelData.id === "launchpad" ? "#70ffffff" : "transparent"
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
                        y: 8 - pinnedButton.lift - pinnedButton.bounceOffset
                        width: 48
                        height: 48
                        scale: pinnedButton.magnification
                        opacity: pinnedButton.reorderActive ? 0.58 : 1
                        source: root.appsService ? root.appsService.iconForApp(modelData) : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        sourceSize.width: 96
                        sourceSize.height: 96
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
                        anchors.horizontalCenter: parent.horizontalCenter
                        z: 10
                        y: pinnedButton.hovered ? -34 : -24
                        width: Math.max(labelText.implicitWidth + 18, 42)
                        height: 24
                        radius: 7
                        color: "#d9f7f8fb"
                        border.color: "#70ffffff"
                        opacity: pinnedButton.hovered ? 1 : 0
                        visible: opacity > 0.01

                        Text {
                            id: labelText
                            anchors.centerIn: parent
                            text: root.appsService ? root.appsService.appLabel(modelData) : ""
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
                            if (pinnedButton.reorderPressed && modelData.shellAction !== "launchpad" && (mouse.buttons & Qt.LeftButton)) {
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
                            if (mouse.button === Qt.LeftButton && modelData.shellAction !== "launchpad") {
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
                            if (mouse.button === Qt.RightButton && modelData.shellAction !== "launchpad") {
                                if (root.appsService)
                                    root.appsService.unpinApp(modelData);
                            } else if (modelData.shellAction === "launchpad") {
                                root.toggleLaunchpad();
                            } else if (root.appsService) {
                                root.appsService.launchApp(modelData);
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

            Rectangle {
                width: 1
                height: 46
                radius: 1
                color: root.darkMode ? "#40ffffff" : "#3d000000"
                visible: root.hasWindows
                anchors.verticalCenter: parent.verticalCenter
            }

            Repeater {
                model: ScriptModel {
                    values: root.niriService ? root.niriService.windowList : []
                }

                delegate: WindowButton {
                    id: windowButton

                    required property var modelData

                    windowModel: modelData
                    toplevel: modelData ? modelData.toplevel : null
                    windowsService: root.niriService
                    appsService: root.appsService
                    useSpring: root.useSpring
                    showTitle: true
                    magnification: root.proximityScale(windowButton)
                    dockWindow: root
                    dockSurfaceItem: dockSurface
                    onDockPointerMoved: function(x, buttons) {
                        root.updateDockHoverFromButtons(x, buttons === undefined ? Qt.NoButton : buttons);
                    }
                    onDockPointerEntered: root.markDockHovered()
                    onDockPointerExited: root.scheduleDockHoverReset()
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
            y: 7
            width: 42
            height: 42
            source: tool.iconSource
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Rectangle {
            id: toolLabel
            anchors.horizontalCenter: parent.horizontalCenter
            y: toolMouse.containsMouse ? -32 : -22
            width: Math.max(toolLabelText.implicitWidth + 18, 42)
            height: 24
            radius: 7
            color: "#d9f7f8fb"
            border.color: "#70ffffff"
            opacity: toolMouse.containsMouse ? 1 : 0
            visible: opacity > 0.01

            Text {
                id: toolLabelText
                anchors.centerIn: parent
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
