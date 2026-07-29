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
    readonly property int screenHeight: Math.max(1, PopupGeometry.numberOr(root.screen && root.screen.height, root.height))
    readonly property int popupLeftMargin: PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, fallbackRight)
    // Fixed surface height. SNI menu children arrive over DBus asynchronously
    // after open (QsMenuOpener.children), so a content-driven implicitHeight
    // grows mid-open and leaves the bottom rows outside the committed layer
    // surface / TahoeGlass input region until a later configure — those rows
    // were unhoverable/un-clickable on the first open. Pin the surface height
    // to a fixed menu-sized cap (same treatment R06 gave MenuPopup.qml) so the
    // layer shell / glass region / dismiss cutout stay static throughout; the
    // content scrolls in a Flickable when it overflows. Same pattern as
    // AppMenuPopup.qml, but pinned (not Math.min'd to content) so the surface
    // is at its final height on the very first frame.
    // 360px fits header(34) + separator(9) + ~12 rows(26) + padding(16); taller
    // menus scroll. Capped to available screen height below the anchor so a
    // tiny display never grows the panel past the screen edge.
    readonly property int maxPanelHeight: Math.min(360, Math.max(180, screenHeight - popupTopMargin - edgePadding))
    signal closeRequested()

    visible: open
    // P02: freeze scene-graph frames while this surface is unmapped/faded out.
    // Extends the existing visible gate onto updatesEnabled (not a parallel path).
    updatesEnabled: visible
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 238
    // Fixed (capped) surface height — see maxPanelHeight rationale. Keeps the
    // layer shell / glass region from resizing mid-open while SNI menu children
    // stream in over DBus.
    implicitHeight: panel.height
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

        // No whole-card press boost: the compositor glass gain reads as an
        // opacity flash when clicking anywhere inside the card.
        pressInteractionEnabled: false

        // Keep the compositor glass region anchored. In compositor animation
        // mode niri owns the outer motion.
        y: 0
        width: parent.width
        // Pinned to the fixed surface cap (maxPanelHeight), not content. The
        // glass region (panel.region) tracks this size, so a static height
        // keeps the compositor input region static while SNI menu children
        // arrive asynchronously. Overflowing children scroll in the Flickable.
        implicitHeight: root.maxPanelHeight
        height: implicitHeight
        material: GlassStyle.MaterialMenu
        radius: GlassStyle.RadiusMenu
        fillColor: GlassStyle.FillPanelBright
        strokeColor: GlassStyle.StrokePanelBright
        opacity: 1
        clip: true

        Flickable {
            anchors.fill: parent
            anchors.margins: 8
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // Only grab pointer events when content actually overflows the
            // viewport — i.e. when there is something to scroll. When the menu
            // is short, leaving interactive false lets a click on the empty
            // glass area below the rows fall through to the surface MouseArea
            // (z: -1) and dismiss the menu, instead of being swallowed by an
            // idle Flickable.
            interactive: contentHeight > height

            ColumnLayout {
                id: content

                width: parent.width
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
                            size: 18
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
                        }
                        onFlashFinished: root.closeRequested()
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
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: root.open
        onClicked: root.closeRequested()
    }
}
