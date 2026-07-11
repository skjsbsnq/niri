pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion

PanelWindow {
    id: root

    property bool open: false
    property var appsService
    property var searchService
    property var settingsService
    property string query: ""
    readonly property var results: root.searchService ? root.searchService.resultsForQuery(root.query, 6) : []
    readonly property bool compositorLayerAnimations:
        root.settingsService && root.settingsService.compositorLayerAnimations

    signal closeRequested()

    visible: compositorLayerAnimations ? open : (open || spotlightPanel.opacity > 0.01)
    aboveWindows: true
    exclusiveZone: 0
    focusable: open
    color: "transparent"
    WlrLayershell.namespace: "tahoe-spotlight"

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    onOpenChanged: {
        if (open) {
            query = "";
            Qt.callLater(function() {
                if (root.open)
                    searchInput.forceActiveFocus();
            });
        }
    }

    function activateResult(result) {
        if (!result)
            return;

        if (root.searchService)
            root.searchService.activateResult(result);
        else if (typeof result.activate === "function")
            result.activate();
        root.closeRequested();
    }

    function resultLabel(result) {
        if (root.searchService)
            return root.searchService.resultTitle(result);
        return String(result && result.title || result && result.name || "");
    }

    function resultSubtitle(result) {
        if (root.searchService)
            return root.searchService.resultSubtitle(result);
        return String(result && result.subtitle || result && result.genericName || "");
    }

    function resultIcon(result) {
        if (root.searchService)
            return root.searchService.resultIcon(result);
        return String(result && result.icon || "");
    }

    function launchFirstResult() {
        if (root.results.length > 0)
            activateResult(root.results[0]);
    }

    function launchShortcut(kind) {
        if (root.searchService && root.searchService.activateShortcut(kind, root.query)) {
            root.closeRequested();
            return;
        }
    }

    TahoeGlass.regions: [spotlightSurface.region, resultsSurface.region]

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    Item {
        id: spotlightPanel

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(58, parent.height * 0.18)
        width: Math.min(parent.width - 28, 690)
        height: spotlightSurface.height + (resultsSurface.visible ? resultsSurface.height + 10 : 0)
        opacity: root.compositorLayerAnimations ? 1 : (root.open ? 1 : 0)
        scale: root.compositorLayerAnimations ? 1 : (root.open ? 1 : 1.04)

        Behavior on opacity {
            NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
        }

        Behavior on scale {
            NumberAnimation { duration: Motion.panelEnter(root.settingsService); easing.type: Motion.emphasizedDecel }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) {
                mouse.accepted = true;
            }
        }

        GlassPanel {
            id: spotlightSurface

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 66
            material: GlassStyle.MaterialPill
            radius: GlassStyle.RadiusPill
            fillColor: GlassStyle.FillPill
            strokeColor: GlassStyle.StrokePill
            useItemRegion: false
            // Keep the glass region bounds independent from spotlightPanel's
            // content-layer scale animation.
            regionX: Math.round(spotlightPanel.x + spotlightSurface.x)
            regionY: Math.round(spotlightPanel.y + spotlightSurface.y)
            regionWidth: Math.round(spotlightSurface.width)
            regionHeight: Math.round(spotlightSurface.height)
            interaction: root.compositorLayerAnimations ? 1 : spotlightPanel.opacity
            materialAlpha: root.compositorLayerAnimations ? 1 : spotlightPanel.opacity
            glassEnabled: root.open || spotlightPanel.opacity > 0.01

            TahoeSymbol {
                anchors.left: parent.left
                anchors.leftMargin: 25
                anchors.verticalCenter: parent.verticalCenter
                name: "\ue8b6"
                color: "#4f5963"
                size: 24
            }

            Text {
                anchors.left: searchInput.left
                anchors.right: shortcutRow.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "搜索"
                color: "#69737d"
                font.pixelSize: 22
                elide: Text.ElideRight
                visible: searchInput.text.length === 0
            }

            TextInput {
                id: searchInput
                anchors.left: parent.left
                anchors.leftMargin: 64
                anchors.right: shortcutRow.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                height: 36
                text: root.query
                color: "#202124"
                selectionColor: "#7ab7ff"
                selectedTextColor: "#ffffff"
                font.pixelSize: 22
                clip: true
                focus: root.open
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: root.query = text
                Keys.onEscapePressed: root.closeRequested()
                Keys.onReturnPressed: root.launchFirstResult()
            }

            Row {
                id: shortcutRow
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Repeater {
                    model: [
                        { "kind": "store", "icon": "AppStore-Symbol.png" },
                        { "kind": "files", "icon": "Folder-Symbol.png" },
                        { "kind": "shortcuts", "icon": "Shortcuts-Symbol.png" },
                        { "kind": "copy", "icon": "Copy-Symbol.png" }
                    ]

                    delegate: Item {
                        id: shortcutButton

                        required property var modelData

                        width: 38
                        height: 38
                        scale: Motion.pressScaleFor(root.settingsService, shortcutMouse.pressed)

                        Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                        Rectangle {
                            anchors.fill: parent
                            radius: 19
                            color: shortcutMouse.pressed ? "#52ffffff" : (shortcutMouse.containsMouse ? "#70ffffff" : "#40ffffff")
                            border.color: "#55ffffff"
                            border.width: 1
                        }

                        Image {
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            source: root.appsService ? root.appsService.iconPath("symbols", shortcutButton.modelData.icon) : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        MouseArea {
                            id: shortcutMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launchShortcut(shortcutButton.modelData.kind)
                        }
                    }
                }
            }
        }

        GlassPanel {
            id: resultsSurface

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: spotlightSurface.bottom
            anchors.topMargin: 10
            height: resultsColumn.implicitHeight + 12
            material: GlassStyle.MaterialPanel
            radius: GlassStyle.RadiusPanelCompact
            fillColor: GlassStyle.FillPanelBright
            strokeColor: GlassStyle.StrokePanelBright
            useItemRegion: false
            regionX: Math.round(spotlightPanel.x + resultsSurface.x)
            regionY: Math.round(spotlightPanel.y + resultsSurface.y)
            regionWidth: Math.round(resultsSurface.width)
            regionHeight: Math.round(resultsSurface.height)
            interaction: resultsSurface.opacity
            materialAlpha: resultsSurface.opacity
            glassEnabled: (root.open || spotlightPanel.opacity > 0.01) && resultsSurface.visible
            opacity: root.open && root.query.trim().length > 0 ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
            }

            Column {
                id: resultsColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                spacing: 2

                Repeater {
                    model: ScriptModel {
                        values: root.results
                    }

                    delegate: Item {
                        id: resultButton

                        required property var modelData

                        width: resultsColumn.width
                        height: 54
                        scale: Motion.pressScaleFor(root.settingsService, resultMouse.pressed)

                        Behavior on scale { NumberAnimation { duration: Motion.pressDurationFor(root.settingsService); easing.type: Motion.pressEasing } }

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: resultMouse.pressed ? "#30ffffff" : (resultMouse.containsMouse ? "#44ffffff" : "transparent")
                        }

                        Image {
                            id: resultIcon
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32
                            source: root.resultIcon(resultButton.modelData)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        Text {
                            id: resultTitle
                            anchors.left: resultIcon.right
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.top: parent.top
                            anchors.topMargin: resultButton.subtitleText.length > 0 ? 9 : 0
                            text: root.resultLabel(resultButton.modelData)
                            color: "#202124"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            verticalAlignment: Text.AlignVCenter
                            height: resultButton.subtitleText.length > 0 ? 18 : parent.height
                        }

                        readonly property string subtitleText: root.resultSubtitle(resultButton.modelData)

                        Text {
                            anchors.left: resultTitle.left
                            anchors.right: resultTitle.right
                            anchors.top: resultTitle.bottom
                            anchors.topMargin: 1
                            text: resultButton.subtitleText
                            color: "#5f6870"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            visible: resultButton.subtitleText.length > 0
                        }

                        MouseArea {
                            id: resultMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activateResult(resultButton.modelData)
                        }
                    }
                }

                Text {
                    width: parent.width
                    height: 42
                    text: "无结果"
                    color: "#5a6570"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    visible: root.query.trim().length > 0 && root.results.length === 0
                }
            }
        }
    }
}
