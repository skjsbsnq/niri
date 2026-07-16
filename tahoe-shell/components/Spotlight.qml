pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion
import "settings/SettingsTheme.js" as Theme

// T17: single-glass Spotlight — search row + results + optional preview in
// one panel. Glass region height uses eased NumberAnimation only (no spring).
// Selection highlight y may spring (content transform) behind useSpring.
PanelWindow {
    id: root

    property bool open: false
    property var appsService
    property var searchService
    property var settingsService
    property bool useSpring: false
    property bool darkMode: false
    property string query: ""
    property int selectedIndex: 0
    property int previewEpoch: 0

    readonly property int resultLimit: Motion.spotlightMaxResults
    readonly property var results: root.searchService
        ? root.searchService.resultsForQuery(root.query, root.resultLimit)
        : []
    readonly property var resultSections: root.buildSections(root.results)
    readonly property var flatRows: root.flattenRows(root.resultSections)
    readonly property int selectableCount: root.countSelectable(root.flatRows)
    readonly property var selectedResult: root.resultAtSelectableIndex(root.selectedIndex)
    readonly property bool hasQuery: root.query.trim().length > 0
    readonly property bool showResults: root.hasQuery
    readonly property string accentId: settingsService ? settingsService.accentColor : "blue"
    readonly property color accent: Theme.accent(darkMode, accentId)
    readonly property color textPrimary: Theme.label(darkMode)
    readonly property color textSecondary: Theme.secondaryLabel(darkMode)
    readonly property color textTertiary: Theme.tertiaryLabel(darkMode)
    readonly property color separator: Theme.separator(darkMode)
    readonly property color rowHover: darkMode ? "#22ffffff" : "#38ffffff"
    readonly property color groupLabel: textTertiary

    readonly property int searchRowHeight: Motion.spotlightSearchRowHeight
    readonly property int previewWidth: Motion.spotlightPreviewWidth
    readonly property int rowHeight: Motion.spotlightRowHeight
    readonly property int groupHeaderHeight: Motion.spotlightGroupHeaderHeight
    readonly property int listContentHeight: root.computeListHeight(root.flatRows)
    readonly property int bodyHeight: root.showResults
        ? Math.min(Motion.spotlightMaxListHeight, Math.max(root.listContentHeight, root.rowHeight + 12))
        : 0
    readonly property int targetPanelHeight: root.searchRowHeight
        + (root.showResults ? root.bodyHeight + 1 : 0)

    signal closeRequested()

    visible: open
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
            selectedIndex = 0;
            previewEpoch = 0;
            Qt.callLater(function() {
                if (root.open)
                    searchInput.forceActiveFocus();
            });
        }
    }

    onQueryChanged: {
        selectedIndex = 0;
        previewEpoch += 1;
        Qt.callLater(function() { root.syncHighlightY(false); });
    }

    onResultsChanged: {
        if (selectedIndex >= selectableCount)
            selectedIndex = Math.max(0, selectableCount - 1);
        previewEpoch += 1;
        Qt.callLater(function() { root.syncHighlightY(false); });
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

    function activateSelected() {
        if (root.selectedResult)
            activateResult(root.selectedResult);
    }

    function moveSelection(delta) {
        if (selectableCount <= 0)
            return;
        var next = selectedIndex + delta;
        if (next < 0)
            next = selectableCount - 1;
        else if (next >= selectableCount)
            next = 0;
        setSelectedIndex(next);
    }

    function setSelectedIndex(next) {
        selectedIndex = next;
        previewEpoch += 1;
        ensureSelectedVisible();
        syncHighlightY(true);
    }

    function syncHighlightY(animate) {
        var targetY = highlightYForSelectable(selectedIndex);
        highlightSpring.stop();
        if (animate && root.useSpring && !Motion.reducedMotion(root.settingsService) && root.open) {
            highlightSpring.to = targetY;
            highlightSpring.restart();
        } else {
            // With useSpring=false, Behavior on y eases this assignment.
            // With reduced / closed, snap.
            selectionHighlight.y = targetY;
        }
    }

    function ensureSelectedVisible() {
        var y = highlightYForSelectable(selectedIndex);
        if (y < resultsFlick.contentY)
            resultsFlick.contentY = Math.max(0, y - 8);
        else if (y + rowHeight > resultsFlick.contentY + resultsFlick.height)
            resultsFlick.contentY = Math.max(0, y + rowHeight - resultsFlick.height + 8);
    }

    function providerKey(result) {
        var provider = String(result && (result.provider || result.kind) || "action").toLowerCase();
        if (provider === "application")
            return "apps";
        return provider;
    }

    function groupTitleForProvider(provider) {
        switch (String(provider || "").toLowerCase()) {
        case "apps":
            return "应用程序";
        case "windows":
            return "窗口";
        case "settings":
            return "系统设置";
        case "calculator":
            return "计算";
        case "command":
            return "命令";
        case "screenshot":
            return "截图";
        case "system-actions":
            return "系统操作";
        case "clipboard-pins":
            return "剪贴板";
        case "tracker":
        case "folders":
        case "recent-files":
            return "文件";
        default:
            return "结果";
        }
    }

    function buildSections(list) {
        var sections = [];
        var indexByKey = {};
        var items = list || [];
        for (var i = 0; i < items.length; i++) {
            var result = items[i];
            var key = providerKey(result);
            var idx = indexByKey[key];
            if (idx === undefined) {
                idx = sections.length;
                indexByKey[key] = idx;
                sections.push({
                    "key": key,
                    "title": groupTitleForProvider(key),
                    "items": []
                });
            }
            sections[idx].items.push(result);
        }
        return sections;
    }

    function flattenRows(sections) {
        var rows = [];
        var selectable = 0;
        var secs = sections || [];
        for (var s = 0; s < secs.length; s++) {
            var section = secs[s];
            rows.push({
                "type": "header",
                "title": section.title,
                "key": section.key
            });
            var items = section.items || [];
            for (var i = 0; i < items.length; i++) {
                rows.push({
                    "type": "result",
                    "result": items[i],
                    "selectableIndex": selectable
                });
                selectable += 1;
            }
        }
        return rows;
    }

    function countSelectable(rows) {
        var n = 0;
        var list = rows || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].type === "result")
                n += 1;
        }
        return n;
    }

    function resultAtSelectableIndex(index) {
        var list = flatRows || [];
        for (var i = 0; i < list.length; i++) {
            var row = list[i];
            if (row.type === "result" && row.selectableIndex === index)
                return row.result;
        }
        return null;
    }

    function computeListHeight(rows) {
        var h = 12; // column margins
        var list = rows || [];
        for (var i = 0; i < list.length; i++) {
            h += list[i].type === "header" ? groupHeaderHeight : rowHeight;
            h += 2;
        }
        if (list.length === 0 && hasQuery)
            h = rowHeight + 24;
        return h;
    }

    function highlightYForSelectable(index) {
        var y = 0;
        var list = flatRows || [];
        for (var i = 0; i < list.length; i++) {
            var row = list[i];
            if (row.type === "result" && row.selectableIndex === index)
                return y;
            y += (row.type === "header" ? groupHeaderHeight : rowHeight) + 2;
        }
        return 0;
    }

    function previewKindLabel(result) {
        if (!result)
            return "";
        return groupTitleForProvider(providerKey(result));
    }

    // Keep legacy shortcuts available via IPC/search providers; UI chips removed (T17).
    function launchShortcut(kind) {
        if (root.searchService && root.searchService.activateShortcut(kind, root.query)) {
            root.closeRequested();
            return;
        }
    }

    function launchFirstResult() {
        activateSelected();
    }

    TahoeGlass.regions: [panelSurface.region]

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    Item {
        id: spotlightPanel

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(58, parent.height * 0.16)
        width: Math.min(parent.width - 28, 760)
        height: panelSurface.height

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) {
                mouse.accepted = true;
            }
        }

        GlassPanel {
            id: panelSurface

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            // Animated height: eased only — never Spring (glass region geometry).
            height: root.open ? root.targetPanelHeight : Motion.spotlightMinPanelHeight
            material: GlassStyle.MaterialPanel
            radius: GlassStyle.RadiusPanelCompact
            fillColor: GlassStyle.FillPanelBright
            strokeColor: GlassStyle.StrokePanelBright
            useItemRegion: false
            regionX: Math.round(spotlightPanel.x + panelSurface.x)
            regionY: Math.round(spotlightPanel.y + panelSurface.y)
            regionWidth: Math.round(panelSurface.width)
            regionHeight: Math.round(panelSurface.height)
            // Stay enabled while unmapped so niri's closing snapshot keeps the glass material.
            interaction: 1
            materialAlpha: 1
            clip: true

            Behavior on height {
                NumberAnimation {
                    duration: Motion.spotlightHeightDuration(root.settingsService)
                    easing.type: Motion.emphasizedDecel
                }
            }

            // --- Search row ---
            Item {
                id: searchRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: root.searchRowHeight

                TahoeSymbol {
                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    name: "\ue8b6"
                    color: root.textTertiary
                    size: 22
                }

                Text {
                    anchors.left: searchInput.left
                    anchors.right: searchInput.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "搜索"
                    color: root.textTertiary
                    font.pixelSize: 20
                    elide: Text.ElideRight
                    visible: searchInput.text.length === 0
                }

                TextInput {
                    id: searchInput
                    anchors.left: parent.left
                    anchors.leftMargin: 56
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    height: 34
                    text: root.query
                    color: root.textPrimary
                    selectionColor: root.accent
                    selectedTextColor: "#ffffff"
                    font.pixelSize: 20
                    clip: true
                    focus: root.open
                    verticalAlignment: TextInput.AlignVCenter
                    onTextChanged: root.query = text
                    Keys.onEscapePressed: root.closeRequested()
                    Keys.onReturnPressed: root.activateSelected()
                    Keys.onEnterPressed: root.activateSelected()
                    Keys.onDownPressed: root.moveSelection(1)
                    Keys.onUpPressed: root.moveSelection(-1)
                    Keys.onTabPressed: root.moveSelection(1)
                    Keys.onBacktabPressed: root.moveSelection(-1)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: root.separator
                    visible: root.showResults
                }
            }

            // --- Results body ---
            Item {
                id: body
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: searchRow.bottom
                anchors.bottom: parent.bottom
                visible: root.showResults && height > 1
                opacity: root.showResults ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Motion.fadeFast(root.settingsService)
                        easing.type: Motion.standardDecel
                    }
                }

                // Left: result list
                Item {
                    id: listPane
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: previewPane.left
                    anchors.rightMargin: 0
                    clip: true

                    Flickable {
                        id: resultsFlick
                        anchors.fill: parent
                        anchors.margins: 6
                        contentWidth: width
                        contentHeight: resultsColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height

                        // Selection highlight capsule (content layer; spring OK).
                        // y is driven by setSelectedIndex / syncHighlightY — not a
                        // live binding, so SpringAnimation and Behavior never fight.
                        Rectangle {
                            id: selectionHighlight
                            width: resultsColumn.width
                            height: root.rowHeight
                            radius: 10
                            color: root.accent
                            opacity: root.selectableCount > 0 ? 1 : 0
                            y: 0
                            z: 0

                            Behavior on y {
                                enabled: !root.useSpring || Motion.reducedMotion(root.settingsService)
                                NumberAnimation {
                                    duration: Motion.elementMove(root.settingsService)
                                    easing.type: Motion.emphasizedDecel
                                }
                            }
                            SpringAnimation {
                                id: highlightSpring
                                target: selectionHighlight
                                property: "y"
                                spring: Motion.springSnappy.spring
                                damping: Motion.springSnappy.damping
                                epsilon: 0.001
                            }
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Motion.fadeFast(root.settingsService)
                                    easing.type: Motion.standardDecel
                                }
                            }
                        }

                        Column {
                            id: resultsColumn
                            width: resultsFlick.width
                            spacing: 2
                            z: 1

                            Repeater {
                                model: ScriptModel {
                                    values: root.flatRows
                                }

                                delegate: Item {
                                    id: rowDelegate

                                    required property var modelData

                                    width: resultsColumn.width
                                    height: modelData.type === "header"
                                        ? root.groupHeaderHeight
                                        : root.rowHeight

                                    // Group header
                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 24
                                        text: rowDelegate.modelData.title || ""
                                        color: root.groupLabel
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        visible: rowDelegate.modelData.type === "header"
                                    }

                                    // Result row
                                    Item {
                                        anchors.fill: parent
                                        visible: rowDelegate.modelData.type === "result"

                                        readonly property var result: rowDelegate.modelData.result
                                        readonly property int selIndex: Number(rowDelegate.modelData.selectableIndex) || 0
                                        readonly property bool selected: root.selectedIndex === selIndex
                                        readonly property string subtitleText: root.resultSubtitle(result)

                                        scale: Motion.pressScaleFor(root.settingsService, resultMouse.pressed)

                                        Behavior on scale {
                                            NumberAnimation {
                                                duration: Motion.pressDurationFor(root.settingsService)
                                                easing.type: Motion.pressEasing
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 10
                                            color: resultMouse.containsMouse && !parent.selected
                                                ? root.rowHover
                                                : "transparent"
                                        }

                                        Image {
                                            id: resultIcon
                                            anchors.left: parent.left
                                            anchors.leftMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 28
                                            height: 28
                                            source: root.resultIcon(parent.result)
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            asynchronous: true
                                            sourceSize.width: 64
                                            sourceSize.height: 64
                                        }

                                        Text {
                                            id: resultTitle
                                            anchors.left: resultIcon.right
                                            anchors.leftMargin: 10
                                            anchors.right: parent.right
                                            anchors.rightMargin: 12
                                            anchors.top: parent.top
                                            anchors.topMargin: parent.subtitleText.length > 0 ? 6 : 0
                                            text: root.resultLabel(parent.result)
                                            color: parent.selected ? "#ffffff" : root.textPrimary
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            verticalAlignment: Text.AlignVCenter
                                            height: parent.subtitleText.length > 0 ? 16 : parent.height
                                        }

                                        Text {
                                            anchors.left: resultTitle.left
                                            anchors.right: resultTitle.right
                                            anchors.top: resultTitle.bottom
                                            anchors.topMargin: 1
                                            text: parent.subtitleText
                                            color: parent.selected ? "#e8ffffff" : root.textSecondary
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            visible: parent.subtitleText.length > 0
                                        }

                                        MouseArea {
                                            id: resultMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.setSelectedIndex(parent.selIndex);
                                                root.activateResult(parent.result);
                                            }
                                            onContainsMouseChanged: {
                                                if (containsMouse)
                                                    root.setSelectedIndex(parent.selIndex);
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                height: root.rowHeight
                                text: "无结果"
                                color: root.textSecondary
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                visible: root.hasQuery && root.selectableCount === 0
                            }
                        }
                    }
                }

                // Right: preview pane
                Item {
                    id: previewPane
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    width: root.selectableCount > 0 ? root.previewWidth : 0
                    clip: true

                    Behavior on width {
                        NumberAnimation {
                            duration: Motion.spotlightHeightDuration(root.settingsService)
                            easing.type: Motion.emphasizedDecel
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: root.separator
                        visible: parent.width > 1
                    }

                    Item {
                        id: previewContent
                        anchors.fill: parent
                        anchors.leftMargin: 1
                        anchors.margins: 16
                        opacity: 1
                        visible: root.selectableCount > 0 && root.selectedResult

                        property int epoch: root.previewEpoch
                        property var result: root.selectedResult

                        onEpochChanged: {
                            if (Motion.reducedMotion(root.settingsService)) {
                                opacity = 1;
                                return;
                            }
                            previewFade.restart();
                        }

                        SequentialAnimation {
                            id: previewFade
                            NumberAnimation {
                                target: previewContent
                                property: "opacity"
                                to: 0
                                duration: Motion.spotlightPreviewFade(root.settingsService) / 2
                                easing.type: Motion.standardDecel
                            }
                            ScriptAction {
                                script: {
                                    previewContent.result = root.selectedResult;
                                }
                            }
                            NumberAnimation {
                                target: previewContent
                                property: "opacity"
                                to: 1
                                duration: Motion.spotlightPreviewFade(root.settingsService) / 2
                                easing.type: Motion.standardDecel
                            }
                        }

                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 8
                            spacing: 12

                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 72
                                height: 72
                                source: root.resultIcon(previewContent.result)
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                asynchronous: true
                                sourceSize.width: 128
                                sourceSize.height: 128
                            }

                            Text {
                                width: parent.width
                                text: root.resultLabel(previewContent.result)
                                color: root.textPrimary
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: root.resultSubtitle(previewContent.result)
                                color: root.textSecondary
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                visible: text.length > 0
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: kindLabel.implicitWidth + 16
                                height: 22
                                radius: 11
                                color: root.darkMode ? "#22ffffff" : "#28ffffff"

                                Text {
                                    id: kindLabel
                                    anchors.centerIn: parent
                                    text: root.previewKindLabel(previewContent.result)
                                    color: root.textTertiary
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
