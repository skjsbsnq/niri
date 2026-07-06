pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../Motion.js" as Motion
import "SettingsModel.js" as SettingsModel
import "controls" as Controls

Rectangle {
    id: sidebar

    property var panel
    property var theme
    property string searchText: ""
    property var navItems: SettingsModel.sidebarItems(searchText)

    readonly property string iconFont: theme ? theme.iconFont : "Material Icons"
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color textMuted: theme ? theme.textMuted : "#5f6870"
    readonly property color sidebarFill: theme ? theme.sidebarFill : "#20ffffff"
    readonly property color sidebarStroke: theme ? theme.sidebarStroke : "#34ffffff"
    readonly property color fieldFill: theme ? theme.fieldFill : "#3fffffff"
    readonly property color fieldStroke: theme ? theme.fieldStroke : "#4cffffff"
    readonly property color fieldStrokeFocus: theme ? theme.fieldStrokeFocus : "#007ff7"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
    readonly property bool searching: searchText.trim().length > 0

    Layout.preferredWidth: 210
    Layout.fillHeight: true
    radius: 8
    color: sidebar.sidebarFill
    border.color: sidebar.sidebarStroke
    border.width: 1
    clip: true

    function parentPageFor(id) {
        return SettingsModel.parentId(id);
    }

    function activeFor(info) {
        if (!sidebar.panel || !info)
            return false;

        var current = SettingsModel.resolveId(sidebar.panel.selectedPage);
        if (current === info.id)
            return true;
        if (sidebar.searching)
            return false;
        return parentPageFor(current) === info.id;
    }

    function badgeFor(info) {
        if (!sidebar.panel || !info)
            return "";
        if (info.id === "notifications"
                && sidebar.panel.notificationsService
                && sidebar.panel.notificationsService.historyCount > 0)
            return String(Math.min(99, sidebar.panel.notificationsService.historyCount));
        if (info.id === "system"
                && sidebar.panel.systemStatusService
                && sidebar.panel.systemStatusService.missingCount > 0)
            return String(sidebar.panel.systemStatusService.missingCount);
        return "";
    }

    function activeIndex() {
        for (var i = 0; i < navItems.length; i++) {
            var item = navItems[i];
            if (item && !item.separator && activeFor(item))
                return i;
        }
        return -1;
    }

    function ensureActiveVisible() {
        if (!navList || navList.count <= 0)
            return;

        var index = activeIndex();
        if (index >= 0)
            navList.positionViewAtIndex(index, ListView.Contain);
    }

    Component.onCompleted: Qt.callLater(function() { sidebar.ensureActiveVisible(); })
    onHeightChanged: Qt.callLater(function() { sidebar.ensureActiveVisible(); })
    onSearchTextChanged: Qt.callLater(function() { sidebar.ensureActiveVisible(); })
    onNavItemsChanged: Qt.callLater(function() { sidebar.ensureActiveVisible(); })

    Connections {
        target: sidebar.panel

        function onSelectedPageChanged() {
            Qt.callLater(function() { sidebar.ensureActiveVisible(); });
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            text: "设置"
            color: sidebar.textPrimary
            font.pixelSize: 17
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 8
            color: sidebar.fieldFill
            border.color: searchInput.activeFocus ? sidebar.fieldStrokeFocus : sidebar.fieldStroke
            border.width: searchInput.activeFocus ? 2 : 1

            // Local exception: focus border feedback is intentionally shorter
            // than fadeFast so typing focus feels immediate.
            Behavior on border.width {
                NumberAnimation { duration: 80; easing.type: Motion.emphasizedDecel }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 7
                spacing: 7

                Text {
                    Layout.preferredWidth: 18
                    text: "\ue8b6"
                    color: sidebar.textSecondary
                    font.family: sidebar.iconFont
                    font.pixelSize: 17
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Text {
                        anchors.fill: parent
                        text: "搜索"
                        color: sidebar.textMuted
                        font.pixelSize: 12
                        verticalAlignment: Text.AlignVCenter
                        visible: searchInput.text.length === 0
                    }

                    TextInput {
                        id: searchInput

                        anchors.fill: parent
                        text: sidebar.searchText
                        color: sidebar.textPrimary
                        selectionColor: sidebar.accentBlue
                        selectedTextColor: "#ffffff"
                        font.pixelSize: 12
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        onTextChanged: {
                            if (sidebar.searchText !== text)
                                sidebar.searchText = text;
                        }
                    }
                }

                Text {
                    Layout.preferredWidth: 18
                    text: "\ue5cd"
                    color: clearMouse.containsMouse ? sidebar.textPrimary : sidebar.textSecondary
                    font.family: sidebar.iconFont
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    visible: sidebar.searchText.length > 0

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            sidebar.searchText = "";
                            searchInput.forceActiveFocus();
                        }
                    }
                }
            }
        }

        ListView {
            id: navList

            Layout.fillWidth: true
            Layout.fillHeight: true
            model: sidebar.navItems
            spacing: 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            delegate: Item {
                id: navDelegate

                required property var modelData

                width: ListView.view.width
                height: modelData && modelData.separator ? 11 : 34

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1
                    color: sidebar.sidebarStroke
                    visible: !!(navDelegate.modelData && navDelegate.modelData.separator)
                }

                Controls.TahoeSidebarButton {
                    anchors.fill: parent
                    theme: sidebar.theme
                    label: navDelegate.modelData && navDelegate.modelData.title ? navDelegate.modelData.title : ""
                    iconCode: navDelegate.modelData && navDelegate.modelData.icon ? navDelegate.modelData.icon : ""
                    active: sidebar.activeFor(navDelegate.modelData)
                    badgeText: sidebar.badgeFor(navDelegate.modelData)
                    visible: !(navDelegate.modelData && navDelegate.modelData.separator)
                    onActivated: {
                        if (sidebar.panel && navDelegate.modelData)
                            sidebar.panel.openPage(navDelegate.modelData.id);
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "无结果"
            color: sidebar.textSecondary
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            visible: sidebar.searching && sidebar.navItems.length === 0
        }
    }
}
