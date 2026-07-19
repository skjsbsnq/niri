pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion
import "PopupGeometry.js" as PopupGeometry
import "controls" as Controls

PanelWindow {
    id: root

    property bool open: false
    property var clipboardService
    property var anchorRect: null
    property var settingsService

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
    implicitHeight: panel.height
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

    TahoeGlass.regions: [panel.region]

    GlassPanel {
        id: panel

        y: 0
        width: parent.width
        implicitHeight: content.implicitHeight + 24
        height: implicitHeight
        clip: true
        material: GlassStyle.MaterialPanel
        radius: GlassStyle.RadiusPopup
        fillColor: GlassStyle.FillPanelBright
        strokeColor: GlassStyle.StrokePanelBright
        opacity: 1

        // Glass region geometry follows this height: eased only, never spring.
        Behavior on height {
            NumberAnimation {
                duration: Motion.elementResize(root.settingsService)
                easing.type: Motion.emphasizedDecel
            }
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

                Controls.IconButton {
                    iconCode: "\ue5d5"
                    enabled: !!root.clipboardService
                    settingsService: root.settingsService
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

                Controls.TextButton {
                    label: "清空历史"
                    iconCode: "\ue872"
                    enabled: root.clipboardService && root.clipboardService.cliphistAvailable && root.entries.length > 0
                    danger: true
                    minimumWidth: 80
                    fontPixelSize: 11
                    settingsService: root.settingsService
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
                    || pinnedList.Layout.preferredHeight > 0.5

                SectionHeader {
                    label: "固定"
                    count: root.pinnedEntries.length
                }

                ListView {
                    id: pinnedList

                    Layout.fillWidth: true
                    Layout.preferredHeight: root.pinnedEntries.length > 0
                        ? Math.min(146, Math.max(44, contentHeight)) : 0
                    clip: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel {
                        objectProp: "modelKey"
                        values: root.pinnedEntries
                    }

                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: Motion.elementResize(root.settingsService)
                            easing.type: Motion.emphasizedDecel
                        }
                    }

                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation {
                                property: "x"
                                from: 16
                                to: 0
                                duration: Motion.elementMove(root.settingsService)
                                easing.type: Motion.emphasizedDecel
                            }
                            NumberAnimation {
                                property: "opacity"
                                from: 0
                                to: 1
                                duration: Motion.fadeFast(root.settingsService)
                                easing.type: Motion.standardDecel
                            }
                        }
                    }

                    remove: Transition {
                        ParallelAnimation {
                            NumberAnimation {
                                property: "x"
                                from: 0
                                to: -16
                                duration: Motion.elementMove(root.settingsService)
                                easing.type: Motion.emphasizedAccel
                            }
                            NumberAnimation {
                                property: "opacity"
                                from: 1
                                to: 0
                                duration: Motion.fadeFast(root.settingsService)
                                easing.type: Motion.emphasizedAccel
                            }
                            NumberAnimation {
                                property: "height"
                                to: 0
                                duration: Motion.elementResize(root.settingsService)
                                easing.type: Motion.emphasizedDecel
                            }
                        }
                    }

                    displaced: Transition {
                        NumberAnimation {
                            properties: "x,y"
                            duration: Motion.elementMove(root.settingsService)
                            easing.type: Motion.emphasizedDecel
                        }
                    }

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
                    || historyList.Layout.preferredHeight > 0.5
            }

            ListView {
                id: historyList

                Layout.fillWidth: true
                Layout.preferredHeight: root.entries.length > 0
                    ? Math.min(root.pinnedEntries.length > 0 ? 250 : 360,
                        Math.max(120, contentHeight)) : 0
                visible: root.entries.length > 0 || Layout.preferredHeight > 0.5
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel {
                    objectProp: "modelKey"
                    values: root.entries
                }

                Behavior on Layout.preferredHeight {
                    NumberAnimation {
                        duration: Motion.elementResize(root.settingsService)
                        easing.type: Motion.emphasizedDecel
                    }
                }

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "x"
                            from: 20
                            to: 0
                            duration: Motion.elementMove(root.settingsService)
                            easing.type: Motion.emphasizedDecel
                        }
                        NumberAnimation {
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: Motion.fadeFast(root.settingsService)
                            easing.type: Motion.standardDecel
                        }
                    }
                }

                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "x"
                            from: 0
                            to: 32
                            duration: Motion.elementMove(root.settingsService)
                            easing.type: Motion.emphasizedAccel
                        }
                        NumberAnimation {
                            property: "opacity"
                            from: 1
                            to: 0
                            duration: Motion.fadeFast(root.settingsService)
                            easing.type: Motion.emphasizedAccel
                        }
                        NumberAnimation {
                            property: "height"
                            to: 0
                            duration: Motion.elementResize(root.settingsService)
                            easing.type: Motion.emphasizedDecel
                        }
                    }
                }

                displaced: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: Motion.elementMove(root.settingsService)
                        easing.type: Motion.emphasizedDecel
                    }
                }

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
            : !!(root.clipboardService && root.clipboardService.available && row.pinnable)
        signal copyRequested(var entry)
        signal pinRequested(var entry)
        signal unpinRequested(var entry)
        signal deleteRequested(var entry)

        height: rowFrame.implicitHeight
        scale: Motion.pressScaleFor(root.settingsService, rowMouse.pressed)
        transformOrigin: Item.Center

        Behavior on scale {
            NumberAnimation {
                duration: Motion.pressDurationFor(root.settingsService)
                easing.type: Motion.pressEasing
            }
        }

        Rectangle {
            id: rowFrame

            width: parent.width
            implicitHeight: rowContent.implicitHeight + 14
            height: implicitHeight
            radius: 14
            color: rowMouse.containsMouse ? "#54ffffff" : "#34ffffff"
            border.color: "#44ffffff"
            border.width: 1

            Behavior on color {
                ColorAnimation {
                    duration: Motion.fadeFast(root.settingsService)
                    easing.type: Motion.standardDecel
                }
            }

            RowLayout {
                id: rowContent

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 7
                spacing: 8
                z: 1

                TahoeSymbol {
                    Layout.preferredWidth: 20
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 2
                    name: row.entry ? row.entry.icon : "\ue14f"
                    color: "#731d1d1f"
                    size: 17
                }

                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.preview : ""
                    color: "#1d1d1f"
                    font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 2
                }

                Controls.IconButton {
                    iconCode: row.pinnedRow ? "\ue5cd" : "\ue866"
                    enabled: row.pinnedRow || (root.clipboardService && root.clipboardService.cliphistAvailable && row.pinnable)
                    active: row.pinned && !row.pinnedRow
                    danger: row.pinnedRow
                    settingsService: root.settingsService
                    onActivated: {
                        if (row.pinnedRow)
                            row.unpinRequested(row.entry);
                        else
                            row.pinRequested(row.entry);
                    }
                }

                Controls.IconButton {
                    iconCode: "\ue14d"
                    enabled: row.copyEnabled
                    settingsService: root.settingsService
                    onActivated: row.copyRequested(row.entry)
                }

                Controls.IconButton {
                    iconCode: "\ue872"
                    enabled: root.clipboardService && root.clipboardService.cliphistAvailable
                    danger: true
                    visible: !row.pinnedRow
                    settingsService: root.settingsService
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

}
