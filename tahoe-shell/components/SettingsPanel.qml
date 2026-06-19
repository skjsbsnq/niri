pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property bool open: false
    property string page: "settings"
    property string selectedPage: page.length > 0 ? page : "settings"
    property var settingsService
    property var systemStatusService
    property var appearanceService
    property var notificationsService
    property var inputMethodService
    property var screenshotService
    property var controlsService
    property var clipboardService
    property var batteryService
    property var powerProfileService
    property var fanService
    property var windowsService

    readonly property int screenWidth: Math.max(1, numberOr(root.screen && root.screen.width, root.width))
    readonly property int screenHeight: Math.max(1, numberOr(root.screen && root.screen.height, root.height))
    readonly property int panelWidth: Math.max(320, Math.min(screenWidth - 32, 1080))
    readonly property int panelHeight: Math.max(420, Math.min(screenHeight - 64, 720))
    readonly property int panelLeft: Math.round(Math.max(8, (screenWidth - panelWidth) / 2))
    readonly property int panelTop: Math.round(Math.max(42, (screenHeight - panelHeight) / 2))
    readonly property string iconFont: "Material Icons"
    readonly property color textPrimary: "#1d1d1f"
    readonly property color textSecondary: "#721d1d1f"
    readonly property color textMuted: "#5f6870"
    readonly property color accentBlue: "#2c9cf2"
    readonly property color sectionFill: "#24ffffff"
    readonly property color sectionStroke: "#38ffffff"
    readonly property color rowFill: "#28ffffff"
    readonly property color rowFillHover: "#48ffffff"
    readonly property color rowStroke: "#32ffffff"

    signal closeRequested()

    visible: open || panel.opacity > 0.01
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    focusable: open
    implicitWidth: screenWidth
    implicitHeight: screenHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "tahoe-settings"

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    onPageChanged: {
        if (page.length > 0)
            selectedPage = page;
    }

    onOpenChanged: {
        if (open) {
            if (systemStatusService)
                systemStatusService.refresh();
            Qt.callLater(function() {
                if (root.open)
                    focusCatcher.forceActiveFocus();
            });
        }
    }

    function numberOr(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
    }

    function pageTitle() {
        if (selectedPage === "appearance")
            return "外观";
        if (selectedPage === "notifications")
            return "通知与输入";
        if (selectedPage === "screenshot")
            return "截图";
        if (selectedPage === "dock")
            return "Dock";
        if (selectedPage === "startup")
            return "启动项";
        if (selectedPage === "health")
            return "系统健康";
        if (selectedPage === "about")
            return "关于 niri";
        return "概览";
    }

    function pageSubtitle() {
        if (selectedPage === "appearance")
            return "深浅色、夜览和色温";
        if (selectedPage === "notifications")
            return "勿扰、通知历史和输入法状态";
        if (selectedPage === "screenshot")
            return "保存目录、复制和通知动作";
        if (selectedPage === "dock")
            return "窗口按钮显示偏好";
        if (selectedPage === "startup")
            return "XDG autostart 和会话备注";
        if (selectedPage === "health")
            return systemStatusService ? "最后检测 " + systemStatusService.lastUpdatedText : "系统状态检测";
        if (selectedPage === "about")
            return "Tahoe Shell、niri、Quickshell 和当前会话";
        return "常用状态、偏好入口和系统摘要";
    }

    function settingsPageVisible() {
        return selectedPage === "settings"
            || selectedPage === "appearance"
            || selectedPage === "notifications"
            || selectedPage === "screenshot"
            || selectedPage === "dock"
            || selectedPage === "startup";
    }

    function showCategory(name) {
        return selectedPage === name;
    }

    function stateLabel(state) {
        if (state === "ok")
            return "正常";
        if (state === "warn")
            return "注意";
        if (state === "missing")
            return "缺失";
        return "信息";
    }

    function stateColor(state) {
        if (state === "ok")
            return "#34c759";
        if (state === "warn")
            return "#ff9f0a";
        if (state === "missing")
            return "#ff453a";
        return "#2c9cf2";
    }

    function inputStatusText() {
        if (!inputMethodService)
            return "输入法服务不可用";
        if (!inputMethodService.available)
            return "不可用";
        return inputMethodService.tooltipText;
    }

    function screenshotPathText() {
        return settingsService ? settingsService.effectiveScreenshotDirectory : "";
    }

    function dockTitleMode() {
        return settingsService ? settingsService.dockWindowTitleMode : "auto";
    }

    function setDockTitleMode(mode) {
        if (settingsService)
            settingsService.setDockWindowTitleMode(mode);
    }

    TahoeGlass.regions: [
        TahoeGlassRegion {
            x: panel.x + panelSurface.x
            y: panel.y + panelSurface.y
            width: panelSurface.width
            height: panelSurface.height
            material: panelSurface.tahoeGlassMaterial
            radius: panelSurface.tahoeGlassRadius
            blur: true
            shadow: true
            clip: true
            interaction: panel.opacity
            materialAlpha: panel.opacity
            enabled: root.open || panel.opacity > 0.01
        }
    ]

    Rectangle {
        anchors.fill: parent
        color: "#1a101418"
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closeRequested()
    }

    FocusScope {
        id: focusCatcher

        anchors.fill: parent
        focus: root.open
        Keys.onEscapePressed: root.closeRequested()
    }

    Item {
        id: panel

        x: root.panelLeft
        y: root.panelTop
        width: root.panelWidth
        height: root.panelHeight
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.985

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) { mouse.accepted = true; }
        }

        Rectangle {
            id: panelSurface
            readonly property string tahoeGlassMaterial: GlassStyle.MaterialPanel
            readonly property real tahoeGlassRadius: GlassStyle.RadiusPanel

            anchors.fill: parent
            radius: tahoeGlassRadius
            color: GlassStyle.FillPanelBright
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: panelSurface.radius - 1
            color: "transparent"
            border.color: GlassStyle.StrokePanelBright
            border.width: 1
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 188
                Layout.fillHeight: true
                radius: 18
                color: "#20ffffff"
                border.color: "#34ffffff"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        spacing: 9

                        Rectangle {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            radius: 10
                            color: "#4cffffff"
                            border.color: "#42ffffff"

                            Text {
                                anchors.centerIn: parent
                                text: "\ue8b8"
                                color: root.textPrimary
                                font.family: root.iconFont
                                font.pixelSize: 19
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: "Tahoe"
                                color: root.textPrimary
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Desktop"
                                color: root.textSecondary
                                font.pixelSize: 11
                            }
                        }
                    }

                    SidebarButton {
                        label: "概览"
                        iconCode: "\ue8b8"
                        active: root.selectedPage === "settings"
                        onActivated: root.selectedPage = "settings"
                    }

                    SidebarButton {
                        label: "外观"
                        iconCode: "\ue51c"
                        active: root.selectedPage === "appearance"
                        onActivated: root.selectedPage = "appearance"
                    }

                    SidebarButton {
                        label: "通知与输入"
                        iconCode: "\ue7f4"
                        active: root.selectedPage === "notifications"
                        badgeText: root.notificationsService && root.notificationsService.historyCount > 0
                            ? String(Math.min(99, root.notificationsService.historyCount))
                            : ""
                        onActivated: root.selectedPage = "notifications"
                    }

                    SidebarButton {
                        label: "截图"
                        iconCode: "\ue3b0"
                        active: root.selectedPage === "screenshot"
                        onActivated: root.selectedPage = "screenshot"
                    }

                    SidebarButton {
                        label: "Dock"
                        iconCode: "\ue8d0"
                        active: root.selectedPage === "dock"
                        onActivated: root.selectedPage = "dock"
                    }

                    SidebarButton {
                        label: "启动项"
                        iconCode: "\ue89e"
                        active: root.selectedPage === "startup"
                        onActivated: root.selectedPage = "startup"
                    }

                    SidebarButton {
                        label: "系统健康"
                        iconCode: "\ue868"
                        active: root.selectedPage === "health"
                        badgeText: root.systemStatusService && root.systemStatusService.missingCount > 0
                            ? String(root.systemStatusService.missingCount)
                            : ""
                        onActivated: {
                            root.selectedPage = "health";
                            if (root.systemStatusService)
                                root.systemStatusService.refresh();
                        }
                    }

                    SidebarButton {
                        label: "关于"
                        iconCode: "\ue88e"
                        active: root.selectedPage === "about"
                        onActivated: root.selectedPage = "about"
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        Layout.fillWidth: true
                        text: root.settingsService ? root.settingsService.settingsPath : ""
                        color: root.textSecondary
                        font.pixelSize: 10
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 3
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: root.pageTitle()
                            color: root.textPrimary
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.pageSubtitle()
                            color: root.textSecondary
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    ActionButton {
                        visible: root.selectedPage === "health" || root.selectedPage === "about"
                        iconCode: "\ue5d5"
                        label: "刷新"
                        enabled: !!root.systemStatusService && !root.systemStatusService.refreshing
                        onActivated: {
                            if (root.systemStatusService)
                                root.systemStatusService.refresh();
                        }
                    }

                    IconButton {
                        iconCode: "\ue5cd"
                        onActivated: root.closeRequested()
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: settingsColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        visible: root.settingsPageVisible()

                        ColumnLayout {
                            id: settingsColumn
                            width: parent.width
                            spacing: 12

                            GridLayout {
                                Layout.fillWidth: true
                                columns: settingsColumn.width >= 620 ? 2 : 1
                                columnSpacing: 10
                                rowSpacing: 10
                                visible: root.selectedPage === "settings"

                                SummaryTile {
                                    Layout.fillWidth: true
                                    iconCode: root.appearanceService && root.appearanceService.darkMode ? "\ue51c" : "\ue518"
                                    title: root.appearanceService && root.appearanceService.darkMode ? "深色模式" : "浅色模式"
                                    detail: root.appearanceService && root.appearanceService.nightMode
                                        ? "夜览 " + root.appearanceService.colorTemperature + "K"
                                        : "夜览关闭"
                                    accentColor: "#5b8def"
                                    onActivated: root.selectedPage = "appearance"
                                }

                                SummaryTile {
                                    Layout.fillWidth: true
                                    iconCode: root.notificationsService && root.notificationsService.dndEnabled ? "\ue7f6" : "\ue7f4"
                                    title: root.notificationsService && root.notificationsService.dndEnabled ? "勿扰已开启" : "通知正常"
                                    detail: root.notificationsService
                                        ? root.notificationsService.historyCount + " 条历史通知"
                                        : "通知服务不可用"
                                    accentColor: root.notificationsService && root.notificationsService.dndEnabled ? "#ff9f0a" : "#34c759"
                                    onActivated: root.selectedPage = "notifications"
                                }

                                SummaryTile {
                                    Layout.fillWidth: true
                                    iconCode: "\ue3b0"
                                    title: "截图"
                                    detail: root.screenshotPathText()
                                    accentColor: "#ff7a59"
                                    onActivated: root.selectedPage = "screenshot"
                                }

                                SummaryTile {
                                    Layout.fillWidth: true
                                    iconCode: "\ue8d0"
                                    title: "Dock"
                                    detail: root.settingsService ? "窗口标题：" + root.settingsService.modeLabel(root.dockTitleMode()) : "设置服务不可用"
                                    accentColor: "#af52de"
                                    onActivated: root.selectedPage = "dock"
                                }

                                SummaryTile {
                                    Layout.fillWidth: true
                                    iconCode: root.systemStatusService && root.systemStatusService.missingCount > 0 ? "\ue002" : "\ue86c"
                                    title: root.systemStatusService && root.systemStatusService.missingCount > 0 ? "有缺失项" : "系统健康"
                                    detail: root.systemStatusService
                                        ? root.systemStatusService.okCount + " 正常 · " + root.systemStatusService.warnCount + " 注意 · " + root.systemStatusService.missingCount + " 缺失"
                                        : "等待检测"
                                    accentColor: root.systemStatusService && root.systemStatusService.missingCount > 0 ? "#ff453a" : "#2c9cf2"
                                    onActivated: {
                                        root.selectedPage = "health";
                                        if (root.systemStatusService)
                                            root.systemStatusService.refresh();
                                    }
                                }

                                SummaryTile {
                                    Layout.fillWidth: true
                                    iconCode: "\ue89e"
                                    title: "启动项"
                                    detail: root.settingsService && root.settingsService.startupNote.length > 0
                                        ? root.settingsService.startupNote
                                        : "管理 autostart 目录"
                                    accentColor: "#30b0c7"
                                    onActivated: root.selectedPage = "startup"
                                }
                            }

                            SectionBox {
                                title: "外观"
                                subtitle: "深浅色、夜览和色温"
                                visible: root.showCategory("appearance")

                                ToggleRow {
                                    label: "深色模式"
                                    detail: root.appearanceService && root.appearanceService.darkMode ? "当前偏好深色" : "当前偏好浅色"
                                    iconCode: "\ue51c"
                                    checked: root.appearanceService && root.appearanceService.darkMode
                                    enabled: !!root.appearanceService
                                    onToggled: function(checked) {
                                        if (root.appearanceService)
                                            root.appearanceService.setDarkMode(checked);
                                    }
                                }

                                ToggleRow {
                                    label: "夜览"
                                    detail: root.appearanceService && root.appearanceService.nightMode
                                        ? "色温 " + root.appearanceService.colorTemperature + "K"
                                        : "关闭"
                                    iconCode: "\ue3a9"
                                    checked: root.appearanceService && root.appearanceService.nightMode
                                    enabled: !!root.appearanceService
                                    onToggled: function(checked) {
                                        if (root.appearanceService)
                                            root.appearanceService.setNightMode(checked);
                                    }
                                }

                                SettingRow {
                                    label: "夜览色温"
                                    detail: root.appearanceService ? root.appearanceService.colorTemperature + "K" : "不可用"
                                    iconCode: "\ueb37"

                                    RowLayout {
                                        spacing: 7

                                        ActionButton {
                                            label: "-250"
                                            enabled: !!root.appearanceService
                                            onActivated: root.appearanceService.setColorTemperature(root.appearanceService.colorTemperature - 250)
                                        }

                                        ActionButton {
                                            label: "+250"
                                            enabled: !!root.appearanceService
                                            onActivated: root.appearanceService.setColorTemperature(root.appearanceService.colorTemperature + 250)
                                        }
                                    }
                                }
                            }

                            SectionBox {
                                title: "通知与输入"
                                subtitle: "通知历史、勿扰和输入法"
                                visible: root.showCategory("notifications")

                                ToggleRow {
                                    label: "勿扰模式"
                                    detail: root.notificationsService && root.notificationsService.dndEnabled
                                        ? "横幅和提示音已静音"
                                        : "通知正常显示"
                                    iconCode: root.notificationsService && root.notificationsService.dndEnabled ? "\ue7f6" : "\ue7f4"
                                    checked: root.notificationsService && root.notificationsService.dndEnabled
                                    enabled: !!root.notificationsService
                                    onToggled: function(checked) {
                                        if (root.notificationsService && root.notificationsService.dndEnabled !== checked)
                                            root.notificationsService.toggleDnd();
                                    }
                                }

                                SettingRow {
                                    label: "通知历史"
                                    detail: root.notificationsService ? root.notificationsService.historyCount + " 项" : "不可用"
                                    iconCode: "\ue7f4"

                                    ActionButton {
                                        label: "清空"
                                        enabled: !!root.notificationsService && root.notificationsService.historyCount > 0
                                        onActivated: root.notificationsService.clearEverything()
                                    }
                                }

                                SettingRow {
                                    label: "输入法"
                                    detail: root.inputStatusText()
                                    iconCode: "\ue312"

                                    RowLayout {
                                        spacing: 7

                                        ActionButton {
                                            label: "切换"
                                            enabled: root.inputMethodService && root.inputMethodService.available
                                            onActivated: root.inputMethodService.toggle()
                                        }

                                        ActionButton {
                                            label: "刷新"
                                            enabled: !!root.inputMethodService
                                            onActivated: root.inputMethodService.refresh()
                                        }
                                    }
                                }
                            }

                            SectionBox {
                                title: "截图"
                                subtitle: "保存目录、复制和通知动作"
                                visible: root.showCategory("screenshot")

                                SettingRow {
                                    label: "保存目录"
                                    detail: root.screenshotPathText()
                                    iconCode: "\ue2c7"

                                    RowLayout {
                                        spacing: 7
                                        Layout.maximumWidth: 420

                                        Rectangle {
                                            Layout.preferredWidth: 270
                                            Layout.preferredHeight: 30
                                            radius: 10
                                            color: "#48ffffff"
                                            border.color: "#4cffffff"

                                            TextInput {
                                                id: screenshotDirectoryInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                text: root.settingsService ? root.settingsService.screenshotDirectory : ""
                                                color: root.textPrimary
                                                selectionColor: "#7ab7ff"
                                                selectedTextColor: "#ffffff"
                                                font.pixelSize: 12
                                                verticalAlignment: TextInput.AlignVCenter
                                                clip: true
                                                onEditingFinished: {
                                                    if (root.settingsService)
                                                        root.settingsService.setScreenshotDirectory(text);
                                                }
                                            }
                                        }

                                        ActionButton {
                                            label: "保存"
                                            enabled: !!root.settingsService
                                            onActivated: root.settingsService.setScreenshotDirectory(screenshotDirectoryInput.text)
                                        }

                                        ActionButton {
                                            label: "默认"
                                            enabled: !!root.settingsService
                                            onActivated: root.settingsService.resetScreenshotDirectory()
                                        }
                                    }
                                }

                                ToggleRow {
                                    label: "截图后复制"
                                    detail: "保存 PNG 后写入 Wayland 剪贴板"
                                    iconCode: "\ue14f"
                                    checked: root.settingsService && root.settingsService.screenshotCopyToClipboard
                                    enabled: !!root.settingsService
                                    onToggled: function(checked) {
                                        if (root.settingsService)
                                            root.settingsService.setScreenshotCopyToClipboard(checked);
                                    }
                                }

                                ToggleRow {
                                    label: "保存通知动作"
                                    detail: "通知里显示标注、打开、复制动作"
                                    iconCode: "\ue3b0"
                                    checked: root.settingsService && root.settingsService.screenshotOfferActions
                                    enabled: !!root.settingsService
                                    onToggled: function(checked) {
                                        if (root.settingsService)
                                            root.settingsService.setScreenshotOfferActions(checked);
                                    }
                                }
                            }

                            SectionBox {
                                title: "Dock"
                                subtitle: "窗口按钮显示偏好"
                                visible: root.showCategory("dock")

                                SettingRow {
                                    label: "窗口标题"
                                    detail: "空间不足时始终保留阶段 2 的不出屏约束"
                                    iconCode: "\ue8d0"

                                    RowLayout {
                                        spacing: 7

                                        ModeButton {
                                            label: "自动"
                                            active: root.dockTitleMode() === "auto"
                                            onActivated: root.setDockTitleMode("auto")
                                        }

                                        ModeButton {
                                            label: "仅图标"
                                            active: root.dockTitleMode() === "icons"
                                            onActivated: root.setDockTitleMode("icons")
                                        }

                                        ModeButton {
                                            label: "标题优先"
                                            active: root.dockTitleMode() === "titles"
                                            onActivated: root.setDockTitleMode("titles")
                                        }
                                    }
                                }
                            }

                            SectionBox {
                                title: "启动项"
                                subtitle: "XDG autostart 管理入口"
                                visible: root.showCategory("startup")

                                SettingRow {
                                    label: "自动启动文件夹"
                                    detail: root.settingsService && root.settingsService.homeDir.length > 0
                                        ? root.settingsService.homeDir + "/.config/autostart"
                                        : "不可用"
                                    iconCode: "\ue89e"

                                    ActionButton {
                                        label: "打开"
                                        enabled: !!root.settingsService
                                        onActivated: root.settingsService.openAutostartFolder()
                                    }
                                }

                                SettingRow {
                                    label: "启动项备注"
                                    detail: root.settingsService && root.settingsService.startupNote.length > 0
                                        ? root.settingsService.startupNote
                                        : "未设置"
                                    iconCode: "\ue873"

                                    RowLayout {
                                        spacing: 7
                                        Layout.maximumWidth: 420

                                        Rectangle {
                                            Layout.preferredWidth: 270
                                            Layout.preferredHeight: 30
                                            radius: 10
                                            color: "#48ffffff"
                                            border.color: "#4cffffff"

                                            TextInput {
                                                id: startupNoteInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                text: root.settingsService ? root.settingsService.startupNote : ""
                                                color: root.textPrimary
                                                selectionColor: "#7ab7ff"
                                                selectedTextColor: "#ffffff"
                                                font.pixelSize: 12
                                                verticalAlignment: TextInput.AlignVCenter
                                                clip: true
                                                onEditingFinished: {
                                                    if (root.settingsService)
                                                        root.settingsService.setStartupNote(text);
                                                }
                                            }
                                        }

                                        ActionButton {
                                            label: "保存"
                                            enabled: !!root.settingsService
                                            onActivated: root.settingsService.setStartupNote(startupNoteInput.text)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: healthColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        visible: root.selectedPage === "health"

                        ColumnLayout {
                            id: healthColumn
                            width: parent.width
                            spacing: 10

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 74
                                radius: 18
                                color: "#2affffff"
                                border.color: "#42ffffff"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    HealthCounter {
                                        label: "正常"
                                        value: root.systemStatusService ? root.systemStatusService.okCount : 0
                                        colorValue: "#34c759"
                                    }

                                    HealthCounter {
                                        label: "注意"
                                        value: root.systemStatusService ? root.systemStatusService.warnCount : 0
                                        colorValue: "#ff9f0a"
                                    }

                                    HealthCounter {
                                        label: "缺失"
                                        value: root.systemStatusService ? root.systemStatusService.missingCount : 0
                                        colorValue: "#ff453a"
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: root.systemStatusService && root.systemStatusService.refreshing ? "检测中" : "已刷新"
                                        color: root.textSecondary
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.systemStatusService ? root.systemStatusService.lastError : ""
                                color: "#ccff453a"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                visible: text.length > 0
                                wrapMode: Text.WordWrap
                            }

                            Repeater {
                                model: root.systemStatusService ? root.systemStatusService.statusItems : []

                                delegate: StatusRow {
                                    required property var modelData
                                    item: modelData
                                }
                            }
                        }
                    }

                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: aboutColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        visible: root.selectedPage === "about"

                        ColumnLayout {
                            id: aboutColumn
                            width: parent.width
                            spacing: 10

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 92
                                radius: 18
                                color: "#2affffff"
                                border.color: "#42ffffff"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 14

                                    Image {
                                        Layout.preferredWidth: 54
                                        Layout.preferredHeight: 54
                                        source: Quickshell.shellPath("assets/icons/niri-icon-smol.png")
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        mipmap: true
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            Layout.fillWidth: true
                                            text: "niri Tahoe Desktop"
                                            color: root.textPrimary
                                            font.pixelSize: 18
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "当前 shell、子模块、运行时、GPU 和会话信息"
                                            color: root.textSecondary
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            Repeater {
                                model: root.systemStatusService ? root.systemStatusService.aboutItems : []

                                delegate: AboutRow {
                                    required property var modelData
                                    item: modelData
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component SidebarButton: Item {
        id: btn

        property string label: ""
        property string iconCode: ""
        property bool active: false
        property string badgeText: ""

        signal activated()

        Layout.fillWidth: true
        Layout.preferredHeight: 34

        Rectangle {
            anchors.fill: parent
            radius: 11
            color: btn.active ? "#64ffffff" : (buttonMouse.containsMouse ? "#42ffffff" : "transparent")
            border.color: btn.active ? "#5cffffff" : "transparent"
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: btn.iconCode
            color: root.textPrimary
            font.family: root.iconFont
            font.pixelSize: 17
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 38
            anchors.right: badge.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: btn.label
            color: root.textPrimary
            font.pixelSize: 12
            font.weight: btn.active ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }

        Rectangle {
            id: badge
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: badgeText.implicitWidth + 8
            height: 16
            radius: 8
            color: "#ccff453a"
            visible: btn.badgeText.length > 0

            Text {
                id: badgeText
                anchors.centerIn: parent
                text: btn.badgeText
                color: "#ffffff"
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
        }
    }

    component SummaryTile: Item {
        id: tile

        property string iconCode: ""
        property string title: ""
        property string detail: ""
        property color accentColor: root.accentBlue

        signal activated()

        Layout.preferredHeight: 86

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: tileMouse.containsMouse ? "#4cffffff" : "#30ffffff"
            border.color: tileMouse.containsMouse ? "#66ffffff" : "#42ffffff"
            border.width: 1
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                Layout.alignment: Qt.AlignVCenter
                radius: 14
                color: tile.accentColor
                border.color: "#66ffffff"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: tile.iconCode
                    color: "#ffffff"
                    font.family: root.iconFont
                    font.pixelSize: 22
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: tile.title
                    color: root.textPrimary
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    Layout.fillWidth: true
                    text: tile.detail
                    color: root.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "\ue5cc"
                color: root.textSecondary
                font.family: root.iconFont
                font.pixelSize: 18
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.activated()
        }
    }

    component SectionBox: Rectangle {
        id: box

        property string title: ""
        property string subtitle: ""
        default property alias contentData: rows.data

        Layout.fillWidth: true
        implicitHeight: visible ? rows.implicitHeight + 26 : 0
        radius: 18
        color: root.sectionFill
        border.color: root.sectionStroke
        border.width: 1

        ColumnLayout {
            id: rows
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        text: box.title
                        color: root.textPrimary
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: box.subtitle
                        color: root.textSecondary
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        visible: text.length > 0
                    }
                }
            }
        }
    }

    component SettingRow: Item {
        id: row

        property string label: ""
        property string detail: ""
        property string iconCode: ""
        default property alias controlData: controlSlot.data

        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(46, rowContent.implicitHeight + 14)

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: root.rowFill
            border.color: root.rowStroke
            border.width: 1
        }

        RowLayout {
            id: rowContent
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            Text {
                Layout.preferredWidth: 22
                Layout.alignment: Qt.AlignVCenter
                text: row.iconCode
                color: root.textPrimary
                font.family: root.iconFont
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: row.label
                    color: root.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: row.detail
                    color: root.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    visible: text.length > 0
                }
            }

            RowLayout {
                id: controlSlot
                Layout.alignment: Qt.AlignVCenter
                spacing: 7
            }
        }
    }

    component ToggleRow: Item {
        id: toggleRow

        property string label: ""
        property string detail: ""
        property string iconCode: ""
        property bool checked: false

        signal toggled(bool checked)

        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(46, rowContent.implicitHeight + 14)
        opacity: enabled ? 1 : 0.48

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: root.rowFill
            border.color: root.rowStroke
            border.width: 1
        }

        RowLayout {
            id: rowContent
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            Text {
                Layout.preferredWidth: 22
                Layout.alignment: Qt.AlignVCenter
                text: toggleRow.iconCode
                color: root.textPrimary
                font.family: root.iconFont
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: toggleRow.label
                    color: root.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: toggleRow.detail
                    color: root.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    visible: text.length > 0
                }
            }

            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                radius: 12
                color: toggleRow.checked ? "#2c9cf2" : "#36000000"

                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    x: toggleRow.checked ? parent.width - width - 2 : 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#ffffff"

                    Behavior on x {
                        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: toggleRow.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (toggleRow.enabled)
                    toggleRow.toggled(!toggleRow.checked);
            }
        }
    }

    component ActionButton: Item {
        id: btn

        property string label: ""
        property string iconCode: ""
        property bool primary: false

        signal activated()

        Layout.preferredWidth: Math.max(54, labelText.implicitWidth + (btn.iconCode.length > 0 ? 34 : 20))
        Layout.preferredHeight: 30
        opacity: enabled ? 1 : 0.45

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: btn.primary ? "#d82c9cf2" : (buttonMouse.containsMouse && btn.enabled ? root.rowFillHover : "#48ffffff")
            border.color: btn.primary ? "#70ffffff" : "#50ffffff"
            border.width: 1
        }

        Row {
            anchors.centerIn: parent
            spacing: 5

            Text {
                text: btn.iconCode
                color: btn.primary ? "#ffffff" : root.textPrimary
                font.family: root.iconFont
                font.pixelSize: 15
                visible: btn.iconCode.length > 0
            }

            Text {
                id: labelText
                text: btn.label
                color: btn.primary ? "#ffffff" : root.textPrimary
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (btn.enabled)
                    btn.activated();
            }
        }
    }

    component IconButton: Item {
        id: btn

        property string iconCode: ""

        signal activated()

        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
        opacity: enabled ? 1 : 0.45

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: mouse.containsMouse && btn.enabled ? root.rowFillHover : "#48ffffff"
            border.color: "#50ffffff"
            border.width: 1
        }

        Text {
            anchors.centerIn: parent
            text: btn.iconCode
            color: root.textPrimary
            font.family: root.iconFont
            font.pixelSize: 18
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (btn.enabled)
                    btn.activated();
            }
        }
    }

    component ModeButton: ActionButton {
        id: modeButton

        property bool active: false

        primary: active
        Layout.preferredWidth: Math.max(72, modeButton.label.length * 8 + 20)
    }

    component HealthCounter: Item {
        id: counter

        property string label: ""
        property int value: 0
        property color colorValue: "#2c9cf2"

        Layout.preferredWidth: 92
        Layout.fillHeight: true

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2

            Text {
                text: String(counter.value)
                color: counter.colorValue
                font.pixelSize: 22
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: counter.label
                color: root.textSecondary
                font.pixelSize: 11
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    component StatusRow: Item {
        id: row

        property var item
        readonly property string statusState: item ? String(item.state || "info") : "info"

        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(74, statusContent.implicitHeight + 18)

        Rectangle {
            anchors.fill: parent
            radius: 16
            color: root.rowFill
            border.color: root.rowStroke
            border.width: 1
        }

        RowLayout {
            id: statusContent
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 11

            Rectangle {
                Layout.preferredWidth: 12
                Layout.preferredHeight: 12
                Layout.alignment: Qt.AlignVCenter
                radius: 6
                color: root.stateColor(row.statusState)
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: row.item ? row.item.title : ""
                        color: root.textPrimary
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        text: root.stateLabel(row.statusState)
                        color: root.stateColor(row.statusState)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: row.item ? row.item.detail : ""
                    color: root.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    Layout.fillWidth: true
                    text: row.item ? row.item.impact : ""
                    color: root.textMuted
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    visible: text.length > 0
                }

                Text {
                    Layout.fillWidth: true
                    text: row.item ? row.item.action : ""
                    color: "#ccff453a"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    visible: text.length > 0
                }
            }
        }
    }

    component AboutRow: Item {
        id: row

        property var item

        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(54, aboutContent.implicitHeight + 16)

        Rectangle {
            anchors.fill: parent
            radius: 16
            color: root.rowFill
            border.color: root.rowStroke
            border.width: 1
        }

        RowLayout {
            id: aboutContent
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 12

            Text {
                Layout.preferredWidth: 150
                Layout.alignment: Qt.AlignVCenter
                text: row.item ? row.item.label : ""
                color: root.textSecondary
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: row.item ? row.item.value : ""
                    color: root.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WrapAnywhere
                }

                Text {
                    Layout.fillWidth: true
                    text: row.item ? row.item.detail : ""
                    color: root.textSecondary
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    visible: text.length > 0
                }
            }
        }
    }
}
