pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "PopupGeometry.js" as PopupGeometry

PanelWindow {
    id: root

    property bool open: false
    property var appMenuService
    property var anchorRect: null
    property var settingsService
    readonly property int edgePadding: 8
    readonly property int fallbackTop: 28
    readonly property int popupGap: 8
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int screenHeight: Math.max(1, PopupGeometry.numberOr(root.screen && root.screen.height, root.height))
    readonly property int maxPanelHeight: Math.max(180, screenHeight - popupTopMargin - edgePadding)
    readonly property bool nativeMenuAvailable: root.appMenuService && root.appMenuService.nativeMenuAvailable
    readonly property int popupLeftMargin: anchorRect
        ? PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, 96)
        : 96
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: anchorRect
        ? PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, 96)
        : 0
    readonly property bool compositorLayerAnimations:
        root.settingsService && root.settingsService.compositorLayerAnimations

    signal closeRequested()

    visible: compositorLayerAnimations ? open : (open || panel.opacity > 0.01)
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 286
    implicitHeight: panel.height
    color: "transparent"
    WlrLayershell.namespace: "tahoe-application-menu"

    onOpenChanged: {
        if (open && appMenuService)
            appMenuService.refresh();
    }

    anchors {
        top: true
        left: true
    }

    margins {
        top: root.popupTopMargin
        left: root.popupLeftMargin
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

    Rectangle {
        id: panel
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialMenu
        readonly property real tahoeGlassRadius: GlassStyle.RadiusMenu
        property real contentScale: root.compositorLayerAnimations ? 1 : (root.open ? 1 : 0.98)

        width: parent.width
        implicitHeight: Math.min(root.maxPanelHeight, content.implicitHeight + 16)
        height: implicitHeight
        radius: tahoeGlassRadius
        color: GlassStyle.FillPanelBright
        opacity: root.compositorLayerAnimations ? 1 : (root.open ? 1 : 0)

        transform: Scale {
            origin.x: root.popupOriginX
            origin.y: 0
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

        Flickable {
            anchors.fill: parent
            anchors.margins: 8
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: content
                width: parent.width
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 8
                        color: "#48ffffff"
                        border.color: "#40ffffff"

                        Text {
                            anchors.centerIn: parent
                            text: root.nativeMenuAvailable ? "\ue86c" : "\ue8a0"
                            color: "#202124"
                            font.family: "Material Icons"
                            font.pixelSize: 16
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: root.appMenuService ? root.appMenuService.activeTitle : "桌面"
                            color: "#1d1d1f"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.appMenuService ? root.appMenuService.menuStatusText : ""
                            color: "#721d1d1f"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            visible: text.length > 0
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: "#22000000"
                }

                Repeater {
                    model: root.nativeMenuAvailable && root.appMenuService ? root.appMenuService.nativeMenuItems : []

                    delegate: NativeMenuRow {
                        required property var modelData

                        Layout.fillWidth: true
                        item: modelData
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: "#22000000"
                    visible: root.nativeMenuAvailable
                }

                MenuRow {
                    text: "固定到 Dock"
                    icon: "\ue866"
                    enabledRow: root.appMenuService && root.appMenuService.hasFocusedWindow
                    onActivated: {
                        if (root.appMenuService)
                            root.appMenuService.pinFocusedApp();
                        root.closeRequested();
                    }
                }

                MenuRow {
                    text: "显示窗口"
                    icon: "\ue8d0"
                    enabledRow: root.appMenuService && root.appMenuService.hasFocusedWindow
                    onActivated: {
                        if (root.appMenuService)
                            root.appMenuService.activateFocusedWindow();
                        root.closeRequested();
                    }
                }

                MenuRow {
                    text: "最小化"
                    icon: "\ue15b"
                    enabledRow: root.appMenuService && root.appMenuService.hasFocusedWindow
                    onActivated: {
                        if (root.appMenuService)
                            root.appMenuService.minimizeFocusedWindow();
                        root.closeRequested();
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: root.open
        onClicked: root.closeRequested()
    }

    component MenuRow: Item {
        id: row

        property string text: ""
        property string icon: ""
        property bool enabledRow: true

        signal activated()

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
            color: "#202124"
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
            color: "#202124"
            font.pixelSize: 12
            elide: Text.ElideRight
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

    component NativeMenuRow: Item {
        id: row

        property var item
        readonly property string kind: item ? String(item.kind || "item") : "item"
        readonly property bool separator: kind === "separator"
        readonly property bool header: kind === "header"
        readonly property bool enabledRow: !!item && !!item.enabled && !separator && !header
        readonly property int indent: item ? Math.max(0, Number(item.indent || 0)) : 0
        readonly property bool checked: !!item && !!item.checked
        readonly property bool hasChildren: !!item && !!item.hasChildren

        Layout.preferredHeight: separator ? 7 : 28
        opacity: enabledRow || header ? 1 : 0.48

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: "#22000000"
            visible: row.separator
        }

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: rowMouse.containsMouse && row.enabledRow ? "#70ffffff" : "transparent"
            visible: !row.separator
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 8 + row.indent * 14
            anchors.verticalCenter: parent.verticalCenter
            text: row.checked ? "\ue5ca" : ""
            color: row.header ? "#541d1d1f" : "#1d1d1f"
            font.family: "Material Icons"
            font.pixelSize: 15
            visible: !row.separator
            opacity: row.checked ? 1 : 0
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 30 + row.indent * 14
            anchors.right: submenuGlyph.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: row.item ? row.item.text : ""
            color: row.header ? "#721d1d1f" : "#1d1d1f"
            font.pixelSize: row.header ? 11 : 12
            font.weight: row.header ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
            visible: !row.separator
        }

        Text {
            id: submenuGlyph
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "\ue5cc"
            color: "#661d1d1f"
            font.family: "Material Icons"
            font.pixelSize: 15
            visible: !row.separator && row.hasChildren && !row.header
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: row.enabledRow ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: row.enabledRow
            onClicked: {
                if (!root.appMenuService)
                    return;
                root.appMenuService.activateNativeItem(row.item);
                root.closeRequested();
            }
        }
    }
}
