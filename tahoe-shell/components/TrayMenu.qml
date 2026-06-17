pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property bool open: false
    property var trayItem
    readonly property var menuHandle: trayItem && trayItem.hasMenu ? trayItem.menu : null
    readonly property string title: trayItem
        ? String(trayItem.tooltipTitle || trayItem.title || trayItem.id || "Tray")
        : "Tray"
    readonly property string iconSource: trayItem ? String(trayItem.icon || "") : ""
    readonly property string iconFont: "Material Icons"

    signal closeRequested()

    visible: open || panel.opacity > 0.01
    aboveWindows: true
    exclusiveZone: 0
    implicitWidth: 238
    implicitHeight: panel.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "tahoe-tray-menu"

    anchors {
        top: true
        right: true
    }

    margins {
        top: 0
        right: 40
    }

    QsMenuOpener {
        id: opener
        menu: root.open ? root.menuHandle : null
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
            interaction: panel.opacity
            materialAlpha: panel.opacity
            enabled: root.open || panel.opacity > 0.01
        }
    ]

    Rectangle {
        id: panel
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialMenu
        readonly property real tahoeGlassRadius: GlassStyle.RadiusMenu
        property real contentScale: root.open ? 1 : 0.98

        // Keep the compositor glass region anchored; popup motion is content
        // scale/opacity plus material alpha, not region translation.
        y: 0
        width: parent.width
        implicitHeight: content.implicitHeight + 16
        height: implicitHeight
        radius: tahoeGlassRadius
        color: GlassStyle.FillPanelBright
        opacity: root.open ? 1 : 0

        transform: Scale {
            origin.x: panel.width
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

                    Text {
                        anchors.centerIn: parent
                        text: "\ue8b8"
                        color: "#661d1d1f"
                        font.family: root.iconFont
                        font.pixelSize: 16
                        visible: !headerIcon.visible
                    }
                }

                Text {
                    text: root.title
                    color: "#1d1d1f"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#22000000"
            }

            Repeater {
                model: opener.children

                delegate: MenuEntry {
                    required property var modelData

                    Layout.fillWidth: true
                    entry: modelData
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                visible: !opener.children || opener.children.values.length === 0

                Text {
                    anchors.centerIn: parent
                    text: "No Actions"
                    color: "#8a1d1d1f"
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

    component MenuEntry: Item {
        id: row

        property var entry
        readonly property bool separator: !!entry && !!entry.isSeparator
        readonly property bool enabledEntry: !!entry && !!entry.enabled
        readonly property bool checkedEntry: !!entry && entry.checkState === Qt.Checked
        readonly property bool hasButton: !!entry && Number(entry.buttonType) > 0
        readonly property bool hasSubmenu: !!entry && !!entry.hasChildren

        Layout.preferredHeight: separator ? 7 : 28
        opacity: enabledEntry ? 1 : 0.45

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
            color: entryMouse.containsMouse && row.enabledEntry ? "#70ffffff" : "transparent"
            visible: !row.separator
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: row.hasButton && row.checkedEntry ? "\ue5ca" : ""
            color: "#1d1d1f"
            font.family: root.iconFont
            font.pixelSize: 15
            visible: !row.separator
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 30
            anchors.right: submenuGlyph.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: row.entry ? row.entry.text : ""
            color: "#1d1d1f"
            font.pixelSize: 12
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
            font.family: root.iconFont
            font.pixelSize: 15
            visible: !row.separator && row.hasSubmenu
        }

        MouseArea {
            id: entryMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: row.enabledEntry && !row.separator ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: row.enabledEntry && !row.separator
            onClicked: {
                if (!row.entry)
                    return;
                row.entry.triggered();
                root.closeRequested();
            }
        }
    }
}
