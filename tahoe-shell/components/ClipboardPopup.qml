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
    property var clipboardService
    property var anchorRect: null

    readonly property string iconFont: "Material Icons"
    readonly property var entries: clipboardService ? clipboardService.entries : []
    readonly property int edgePadding: 8
    readonly property int fallbackRight: 202
    readonly property int fallbackTop: 28
    readonly property int popupGap: -1
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, fallbackRight)

    signal closeRequested()

    visible: open || panel.opacity > 0.01
    aboveWindows: true
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 360
    implicitHeight: panel.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "tahoe-clipboard-popup"

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
            interaction: panel.opacity
            materialAlpha: panel.opacity
            enabled: root.open || panel.opacity > 0.01
        }
    ]

    onOpenChanged: {
        if (open && root.clipboardService)
            root.clipboardService.refresh();
    }

    Rectangle {
        id: panel
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialPanel
        readonly property real tahoeGlassRadius: GlassStyle.RadiusPopup
        property real contentScale: root.open ? 1 : 0.98

        y: 0
        width: parent.width
        implicitHeight: content.implicitHeight + 24
        height: implicitHeight
        radius: tahoeGlassRadius
        color: GlassStyle.FillPanelBright
        opacity: root.open ? 1 : 0

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
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Behavior on contentScale {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "剪贴板"
                    color: "#1d1d1f"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                Text {
                    text: root.clipboardService ? root.clipboardService.statusText : ""
                    color: "#731d1d1f"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.maximumWidth: 110
                }

                IconButton {
                    iconCode: "\ue5d5"
                    enabled: !!root.clipboardService
                    onActivated: {
                        if (root.clipboardService)
                            root.clipboardService.refresh();
                    }
                }

                IconButton {
                    iconCode: "\ue872"
                    enabled: root.clipboardService && root.clipboardService.cliphistAvailable && root.entries.length > 0
                    danger: true
                    onActivated: {
                        if (root.clipboardService)
                            root.clipboardService.clearHistory();
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.clipboardService ? root.clipboardService.errorText : "剪贴板服务不可用"
                color: "#ccff453a"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                visible: text.length > 0
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                text: root.clipboardService && root.clipboardService.available ? "暂无历史" : "需要 cliphist 和 wl-clipboard"
                color: "#8a1d1d1f"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                visible: root.entries.length === 0
            }

            ListView {
                id: historyList

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(360, Math.max(120, contentHeight))
                visible: root.entries.length > 0
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: root.entries

                delegate: ClipboardRow {
                    required property var modelData

                    width: historyList.width
                    entry: modelData
                    onCopyRequested: function(entry) {
                        if (root.clipboardService)
                            root.clipboardService.copyEntry(entry);
                    }
                    onDeleteRequested: function(entry) {
                        if (root.clipboardService)
                            root.clipboardService.deleteEntry(entry);
                    }
                }
            }
        }
    }

    component ClipboardRow: Item {
        id: row

        property var entry
        signal copyRequested(var entry)
        signal deleteRequested(var entry)

        height: rowFrame.implicitHeight

        Rectangle {
            id: rowFrame

            width: parent.width
            implicitHeight: rowContent.implicitHeight + 14
            height: implicitHeight
            radius: 14
            color: rowMouse.containsMouse ? "#54ffffff" : "#34ffffff"
            border.color: "#44ffffff"
            border.width: 1

            RowLayout {
                id: rowContent

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 7
                spacing: 8
                z: 1

                Text {
                    text: row.entry ? row.entry.icon : "\ue14f"
                    color: "#731d1d1f"
                    font.family: root.iconFont
                    font.pixelSize: 17
                    Layout.preferredWidth: 20
                    Layout.alignment: Qt.AlignTop
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.preview : ""
                    color: "#1d1d1f"
                    font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 2
                }

                IconButton {
                    iconCode: "\ue14d"
                    enabled: root.clipboardService && root.clipboardService.available
                    onActivated: row.copyRequested(row.entry)
                }

                IconButton {
                    iconCode: "\ue872"
                    enabled: root.clipboardService && root.clipboardService.cliphistAvailable
                    danger: true
                    onActivated: row.deleteRequested(row.entry)
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                z: 0
                cursorShape: root.clipboardService && root.clipboardService.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (root.clipboardService && root.clipboardService.available)
                        row.copyRequested(row.entry);
                }
            }
        }
    }

    component IconButton: Item {
        id: btn

        property string iconCode: ""
        property bool enabled: true
        property bool danger: false
        signal activated()

        Layout.preferredWidth: 26
        Layout.preferredHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: btnMouse.containsMouse ? "#70ffffff" : "#34ffffff"
            border.color: "#50ffffff"
            border.width: 1
            opacity: btn.enabled ? 1 : 0.45
        }

        Text {
            anchors.centerIn: parent
            text: btn.iconCode
            color: btn.danger ? "#ccff453a" : "#1d1d1f"
            font.family: root.iconFont
            font.pixelSize: 16
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (btn.enabled)
                    btn.activated();
            }
        }
    }
}
