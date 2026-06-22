pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property bool open: false
    property var windowsService
    property var appsService
    property var window: null
    property var anchorRect: null
    property var settingsService
    readonly property int edgePadding: 8
    readonly property int popupGap: 8
    readonly property int screenWidth: Math.max(1, numberOr(root.screen && root.screen.width, root.width))
    readonly property int screenHeight: Math.max(1, numberOr(root.screen && root.screen.height, root.height))
    readonly property int panelWidth: 254
    readonly property int maxWorkspaceListHeight: 180
    readonly property int panelHeight: Math.max(1, panel.implicitHeight)
    readonly property var workspaceChoices: windowsService ? windowsService.workspaceList : []
    readonly property bool hasWindow: !!window
    readonly property bool windowMinimized: hasWindow && !!window.isMinimized
    readonly property bool hasWorkspaces: workspaceChoices && workspaceChoices.length > 0
    readonly property bool canActivate: hasWindow && !!windowsService
    readonly property bool canMinimize: canActivate && !windowMinimized
    readonly property bool canClose: hasWindow && !!windowsService && windowsService.hasWindowId(window)
    readonly property bool canMoveToWorkspace: canClose && hasWorkspaces && workspaceChoices.length > 1
    readonly property string windowTitle: appsService && hasWindow ? appsService.toplevelLabel(window) : "窗口"
    readonly property string windowIcon: appsService && hasWindow ? appsService.iconForToplevel(window) : ""
    readonly property string windowAppId: appsService && hasWindow ? appsService.windowAppId(window) : ""
    readonly property bool canPinWindow: hasWindow && !!appsService && windowAppId.length > 0
    readonly property bool windowPinned: canPinWindow && appsService.isWindowPinned(window)
    readonly property int popupLeft: popupLeftFor()
    readonly property int popupTop: popupTopFor()
    readonly property real popupOriginX: Math.max(0, Math.min(panel.width, anchorCenterX() - panel.x))
    readonly property bool compositorLayerAnimations:
        root.settingsService && root.settingsService.compositorLayerAnimations

    signal closeRequested()

    visible: compositorLayerAnimations ? open : (open || panel.opacity > 0.01)
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: screenWidth
    implicitHeight: screenHeight
    color: "transparent"
    WlrLayershell.namespace: "tahoe-dock-window-menu"

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    function numberOr(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
    }

    function anchorCenterX() {
        if (!anchorRect)
            return root.width / 2;

        var width = numberOr(anchorRect.width, numberOr(anchorRect.w, 1));
        return numberOr(anchorRect.x, 0) + width / 2;
    }

    function popupLeftFor() {
        var maxLeft = Math.max(edgePadding, root.width - panelWidth - edgePadding);
        return Math.round(Math.max(edgePadding, Math.min(maxLeft, anchorCenterX() - panelWidth / 2)));
    }

    function popupTopFor() {
        var maxTop = Math.max(edgePadding, root.height - panelHeight - edgePadding);
        if (!anchorRect)
            return maxTop;

        var y = numberOr(anchorRect.y, root.height - 96);
        return Math.round(Math.max(edgePadding, Math.min(maxTop, y - panelHeight - popupGap)));
    }

    function workspaceReference(workspace, index) {
        return windowsService ? windowsService.workspaceActionReference(workspace, index) : "";
    }

    function isCurrentWorkspace(workspace) {
        return windowsService && windowsService.isWindowOnWorkspace(window, workspace);
    }

    function workspaceRowText(workspace, index, current) {
        var label = windowsService ? windowsService.workspaceDisplayLabel(workspace, index) : "工作区";
        var output = String(workspace && workspace.output ? workspace.output : "").trim();
        if (output.length > 0)
            label += " - " + output;
        if (current)
            label += "（当前）";
        return label;
    }

    TahoeGlass.regions: [
        TahoeGlassRegion {
            x: panel.x
            y: panel.y
            width: panel.width
            height: panel.height
            material: panel.tahoeGlassMaterial
            radius: panel.tahoeGlassRadius
            blur: true
            shadow: true
            clip: true
            interaction: root.compositorLayerAnimations ? 1 : panel.opacity
            materialAlpha: root.compositorLayerAnimations ? 1 : panel.opacity
            enabled: root.open || panel.opacity > 0.01
        }
    ]

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closeRequested()
    }

    Rectangle {
        id: panel
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialMenu
        readonly property real tahoeGlassRadius: GlassStyle.RadiusMenu
        property real contentScale: root.compositorLayerAnimations ? 1 : (root.open ? 1 : 0.98)

        z: 1
        x: root.popupLeft
        y: root.popupTop
        width: root.panelWidth
        implicitHeight: content.implicitHeight + 16
        height: implicitHeight
        radius: tahoeGlassRadius
        color: GlassStyle.FillPanelBright
        opacity: root.compositorLayerAnimations ? 1 : (root.open ? 1 : 0)

        transform: Scale {
            origin.x: root.popupOriginX
            origin.y: panel.height
            xScale: panel.contentScale
            yScale: panel.contentScale
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: GlassStyle.StrokePanelBright
            border.width: 1
        }

        Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Behavior on contentScale {
            NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    Layout.alignment: Qt.AlignVCenter
                    radius: 8
                    color: "#48ffffff"
                    border.color: "#40ffffff"

                    Image {
                        id: headerIcon
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: root.windowIcon
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        visible: root.windowIcon.length > 0 && status !== Image.Error
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "\ue8d0"
                        color: "#661d1d1f"
                        font.family: "Material Icons"
                        font.pixelSize: 16
                        visible: !headerIcon.visible
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: root.windowTitle
                    color: "#1d1d1f"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            Separator {}

            MenuRow {
                text: "显示窗口"
                icon: "\ue8d0"
                enabledRow: root.canActivate
                onActivated: {
                    if (root.windowsService && root.window) {
                        if (root.windowMinimized)
                            root.windowsService.restore(root.window);
                        else
                            root.windowsService.activate(root.window);
                    }
                    root.closeRequested();
                }
            }

            MenuRow {
                text: root.windowMinimized ? "已最小化" : "最小化"
                icon: "\ue15b"
                enabledRow: root.canMinimize
                onActivated: {
                    if (root.windowsService && root.window)
                        root.windowsService.minimize(root.window);
                    root.closeRequested();
                }
            }

            MenuRow {
                text: root.windowPinned ? "从 Dock 移除" : "固定到 Dock"
                icon: root.windowPinned ? "\ue872" : "\ue866"
                destructive: root.windowPinned
                enabledRow: root.canPinWindow
                onActivated: {
                    if (root.appsService && root.window)
                        root.appsService.togglePinnedWindow(root.window);
                    root.closeRequested();
                }
            }

            MenuRow {
                text: "关闭窗口"
                icon: "\ue5cd"
                destructive: true
                enabledRow: root.canClose
                onActivated: {
                    if (root.windowsService && root.window)
                        root.windowsService.closeWindow(root.window);
                    root.closeRequested();
                }
            }

            Separator {}

            MenuRow {
                text: "移动到工作区"
                icon: "\ue8d4"
                enabledRow: false
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.hasWorkspaces
                    ? Math.max(30, Math.min(workspaceColumn.implicitHeight, root.maxWorkspaceListHeight))
                    : 30

                Flickable {
                    id: workspaceViewport
                    anchors.fill: parent
                    visible: root.hasWorkspaces
                    contentWidth: width
                    contentHeight: workspaceColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick

                    Column {
                        id: workspaceColumn
                        width: workspaceViewport.width
                        spacing: 3

                        Repeater {
                            model: root.workspaceChoices

                            delegate: MenuRow {
                                required property var modelData
                                required property int index

                                readonly property bool currentWorkspace: root.isCurrentWorkspace(modelData)
                                readonly property string reference: root.workspaceReference(modelData, index)

                                text: root.workspaceRowText(modelData, index, currentWorkspace)
                                icon: currentWorkspace ? "\ue876" : "\ue835"
                                enabledRow: root.canMoveToWorkspace && !currentWorkspace && reference.length > 0
                                onActivated: {
                                    if (root.windowsService && root.window)
                                        root.windowsService.moveWindowToWorkspace(root.window, modelData, false);
                                    root.closeRequested();
                                }
                            }
                        }
                    }
                }

                MenuRow {
                    anchors.fill: parent
                    visible: !root.hasWorkspaces
                    text: "暂无工作区数据"
                    icon: "\ue88f"
                    enabledRow: false
                }
            }
        }
    }

    component Separator: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: "#22000000"
    }

    component MenuRow: Item {
        id: row

        property string text: ""
        property string icon: ""
        property bool enabledRow: true
        property bool destructive: false

        signal activated()

        width: parent ? parent.width : 0
        height: 30
        Layout.fillWidth: true
        Layout.preferredHeight: 30
        opacity: enabledRow ? 1 : 0.52

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: rowMouse.containsMouse && row.enabledRow ? "#70ffffff" : "transparent"
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: row.icon
            color: row.destructive ? "#b3261e" : "#202124"
            font.family: "Material Icons"
            font.pixelSize: 16
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 34
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: row.text
            color: row.destructive ? "#b3261e" : "#202124"
            font.pixelSize: 12
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: row.enabledRow ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (row.enabledRow)
                    row.activated();
            }
        }
    }
}
