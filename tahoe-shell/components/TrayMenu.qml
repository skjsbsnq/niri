pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "TahoeGlass.js" as GlassStyle
import "PopupGeometry.js" as PopupGeometry

PanelWindow {
    id: root

    property bool open: false
    property var trayItem
    property var anchorRect: null
    property var settingsService
    property bool darkMode: false
    readonly property var menuHandle: trayItem && trayItem.hasMenu ? trayItem.menu : null
    readonly property string title: trayItem
        ? String(trayItem.tooltipTitle || trayItem.title || trayItem.id || "托盘")
        : "托盘"
    readonly property string iconSource: trayItem ? String(trayItem.icon || "") : ""
    readonly property int edgePadding: 8
    readonly property int fallbackRight: 40
    readonly property int fallbackTop: 28
    readonly property int popupGap: 8
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, fallbackRight)
    signal closeRequested()

    visible: open
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 238
    implicitHeight: panel.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "tahoe-tray-menu"

    anchors {
        top: true
        left: true
    }

    margins {
        top: root.popupTopMargin
        left: root.popupLeftMargin
    }

    QsMenuOpener {
        id: opener
        menu: root.open ? root.menuHandle : null
    }

    TahoeGlass.regions: [panel.region]

    GlassPanel {
        id: panel

        // Keep the compositor glass region anchored. In compositor animation
        // mode niri owns the outer motion.
        y: 0
        width: parent.width
        implicitHeight: content.implicitHeight + 16
        height: implicitHeight
        material: GlassStyle.MaterialMenu
        radius: GlassStyle.RadiusMenu
        fillColor: GlassStyle.FillPanelBright
        strokeColor: GlassStyle.StrokePanelBright
        opacity: 1

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 2

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

                    IconImage {
                        id: headerIcon
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        implicitSize: 18
                        source: root.iconSource
                        mipmap: true
                        visible: root.iconSource.length > 0 && status !== Image.Error
                    }

                    TahoeSymbol {
                        anchors.centerIn: parent
                        name: "\ue8b8"
                        color: root.darkMode ? "#94a0ad" : "#661d1d1f"
                        size: 16
                        visible: !headerIcon.visible
                    }
                }

                Text {
                    text: root.title
                    color: root.darkMode ? "#f5f7fb" : "#1d1d1f"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            MenuSeparator {
                darkMode: root.darkMode
            }

            Repeater {
                model: opener.children

                delegate: MenuRow {
                    required property var modelData

                    Layout.fillWidth: true
                    text: modelData ? String(modelData.text || "") : ""
                    separator: !!modelData && !!modelData.isSeparator
                    enabledRow: !!modelData && !!modelData.enabled
                    checked: !!modelData && modelData.checkState === Qt.Checked
                    showCheckColumn: true
                    hasSubmenu: !!modelData && !!modelData.hasChildren
                    settingsService: root.settingsService
                    darkMode: root.darkMode
                    onActivated: {
                        if (!modelData)
                            return;
                        modelData.triggered();
                        root.closeRequested();
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                visible: !opener.children || opener.children.values.length === 0

                Text {
                    anchors.centerIn: parent
                    text: "无可用操作"
                    color: root.darkMode ? "#94a0ad" : "#8a1d1d1f"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
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
}
