pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion
import "PopupGeometry.js" as PopupGeometry

PanelWindow {
    id: root

    property bool open: false
    property var clipboardService
    property var anchorRect: null
    property var settingsService

    readonly property string iconFont: "Material Icons"
    readonly property var entries: clipboardService ? clipboardService.entries : []
    readonly property var pinnedEntries: clipboardService ? clipboardService.pinnedEntries : []
    readonly property int edgePadding: 8
    readonly property int fallbackRight: 202
    readonly property int fallbackTop: 28
    readonly property int popupGap: 8
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, fallbackRight)
    signal closeRequested()

    visible: open
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

    onOpenChanged: {
        if (open && root.clipboardService)
            root.clipboardService.refresh();
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
            interaction: 1
            materialAlpha: 1
            enabled: true
        }
    ]

    Rectangle {
        id: panel
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialPanel
        readonly property real tahoeGlassRadius: GlassStyle.RadiusPopup

        y: 0
        width: parent.width
        implicitHeight: content.implicitHeight + 24
        height: implicitHeight
        radius: tahoeGlassRadius
        color: GlassStyle.FillPanelBright
        opacity: 1

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: GlassStyle.StrokePanelBright
            border.width: 1
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

                IconButton {
                    iconCode: "\ue5d5"
                    enabled: !!root.clipboardService
                    onActivated: {
                        if (root.clipboardService)
                            root.clipboardService.refresh();
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: root.clipboardService ? root.clipboardService.statusText : ""
                    color: "#731d1d1f"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                TextButton {
                    label: "清空历史"
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

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.pinnedEntries.length > 0

                SectionHeader {
                    label: "固定"
                    count: root.pinnedEntries.length
                }

                ListView {
                    id: pinnedList

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(146, Math.max(44, contentHeight))
                    clip: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.pinnedEntries

                    delegate: ClipboardRow {
                        required property var modelData

                        width: pinnedList.width
                        entry: modelData
                        pinnedRow: true
                        pinned: true
                        pinnable: true
                        onCopyRequested: function(entry) {
                            if (root.clipboardService)
                                root.clipboardService.copyPinnedEntry(entry);
                        }
                        onUnpinRequested: function(entry) {
                            if (root.clipboardService)
                                root.clipboardService.unpinPinnedEntry(entry);
                        }
                    }
                }
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
                visible: root.entries.length === 0 && root.pinnedEntries.length === 0
            }

            SectionHeader {
                label: "历史"
                count: root.entries.length
                visible: root.entries.length > 0
            }

            ListView {
                id: historyList

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(root.pinnedEntries.length > 0 ? 250 : 360, Math.max(120, contentHeight))
                visible: root.entries.length > 0
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: root.entries

                delegate: ClipboardRow {
                    required property var modelData

                    width: historyList.width
                    entry: modelData
                    pinned: root.clipboardService ? root.clipboardService.isEntryPinned(modelData) : false
                    pinnable: modelData && modelData.pinnable !== false
                    onCopyRequested: function(entry) {
                        if (root.clipboardService)
                            root.clipboardService.copyEntry(entry);
                    }
                    onPinRequested: function(entry) {
                        if (root.clipboardService)
                            root.clipboardService.pinEntry(entry);
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
        property bool pinned: false
        property bool pinnedRow: false
        property bool pinnable: true
        readonly property bool copyEnabled: pinnedRow
            ? !!(root.clipboardService && root.clipboardService.wlCopyAvailable)
            : !!(root.clipboardService && root.clipboardService.available)
        signal copyRequested(var entry)
        signal pinRequested(var entry)
        signal unpinRequested(var entry)
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
                    iconCode: row.pinnedRow ? "\ue5cd" : "\ue866"
                    enabled: row.pinnedRow || (root.clipboardService && root.clipboardService.cliphistAvailable && row.pinnable)
                    active: row.pinned && !row.pinnedRow
                    danger: row.pinnedRow
                    onActivated: {
                        if (row.pinnedRow)
                            row.unpinRequested(row.entry);
                        else
                            row.pinRequested(row.entry);
                    }
                }

                IconButton {
                    iconCode: "\ue14d"
                    enabled: row.copyEnabled
                    onActivated: row.copyRequested(row.entry)
                }

                IconButton {
                    iconCode: "\ue872"
                    enabled: root.clipboardService && root.clipboardService.cliphistAvailable
                    danger: true
                    visible: !row.pinnedRow
                    onActivated: row.deleteRequested(row.entry)
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                z: 0
                cursorShape: row.copyEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (row.copyEnabled)
                        row.copyRequested(row.entry);
                }
            }
        }
    }

    component SectionHeader: Item {
        id: header

        property string label: ""
        property int count: 0

        Layout.fillWidth: true
        Layout.preferredHeight: 18

        RowLayout {
            anchors.fill: parent
            spacing: 6

            Text {
                text: header.label
                color: "#731d1d1f"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }

            Text {
                text: String(header.count)
                color: "#661d1d1f"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }
    }

    component IconButton: Item {
        id: btn

        property string iconCode: ""
        property bool enabled: true
        property bool danger: false
        property bool active: false
        signal activated()

        Layout.preferredWidth: 26
        Layout.preferredHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: btn.active ? "#d82c9cf2" : (btnMouse.containsMouse && btn.enabled ? "#70ffffff" : "#34ffffff")
            border.color: btn.active ? "#70ffffff" : "#50ffffff"
            border.width: 1
            opacity: btn.enabled ? 1 : 0.45
        }

        Text {
            anchors.centerIn: parent
            text: btn.iconCode
            color: btn.active ? "#ffffff" : (btn.danger ? "#ccff453a" : "#1d1d1f")
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

    component TextButton: Item {
        id: btn

        property string label: ""
        property string iconCode: ""
        property bool enabled: true
        property bool danger: false
        signal activated()

        Layout.preferredWidth: Math.max(80, labelText.implicitWidth + (btn.iconCode.length > 0 ? 34 : 20))
        Layout.preferredHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: btnMouse.containsMouse && btn.enabled ? "#70ffffff" : "#34ffffff"
            border.color: "#50ffffff"
            border.width: 1
            opacity: btn.enabled ? 1 : 0.45
        }

        Row {
            anchors.centerIn: parent
            spacing: 4

            Text {
                text: btn.iconCode
                color: btn.danger ? "#ccff453a" : "#1d1d1f"
                font.family: root.iconFont
                font.pixelSize: 15
                visible: btn.iconCode.length > 0
            }

            Text {
                id: labelText
                text: btn.label
                color: btn.danger ? "#ccff453a" : "#1d1d1f"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
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
