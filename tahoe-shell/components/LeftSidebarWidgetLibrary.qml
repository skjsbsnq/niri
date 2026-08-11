pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "Motion.js" as Motion
import "settings/SettingsTheme.js" as Theme

// A4：侧栏第三个 tab「小部件」—— 可用小部件列表（从上到下排列，
// 含名称与可选尺寸）。文字条目即可（实时预览画廊属 A5，不在本任务）。
//
// 数据单一来源：WidgetHost.qml 的 widgetCatalog（由 shell 注入本组件，
// 不在此处维护第二份注册表，G-6）。点击条目发 addRequested(id)，
// 由 shell 负责：成功 → 关闭侧栏 + 桌面空位添加；失败（桌面已满）→
// 回灌 addFailed → 本组件显示可见反馈（不静默失败）。
//
// 约束：
// - A-C3：无自建轮询。反馈横幅用单发 Timer（与 WidgetHost 超限横幅同模式），
//   无常驻刷新路径。
// - P-3：动画时长一律取 Motion.js 令牌，无硬编码 duration 字面量。
Item {
    id: root

    property var widgetCatalog: ({})
    // 宿主当前实例表（shell 注入；对象被宿主在重建时整体替换，
    // onPresentWidgetsChanged 驱动刷新「已添加」标记）。
    property var presentWidgets: ({})
    property var settingsService: null
    property bool darkMode: false
    property bool cardsEnter: false
    property bool useSpring: false
    // shell 回灌：最近一次添加失败（桌面无空位）。true 时显示横幅。
    property bool addFailed: false

    signal addRequested(string id)

    // 已在桌面的条目 id 列表（presentWidgets 的键快照；宿主配置唯一 id，
    // 重复添加会被 gridStateFromConfig 拒绝，故这些条目必须标记已添加）。
    property var presentIds: []
    function refreshPresent() {
        var keys = Object.keys(root.presentWidgets || {});
        var out = [];
        for (var i = 0; i < keys.length; i++)
            out.push(String(keys[i] || ""));
        root.presentIds = out;
    }
    onPresentWidgetsChanged: root.refreshPresent()
    Component.onCompleted: root.refreshPresent()
    function isPresent(id) {
        for (var i = 0; i < root.presentIds.length; i++) {
            if (root.presentIds[i] === id)
                return true;
        }
        return false;
    }

    readonly property color textPrimary: Theme.label(root.darkMode)
    readonly property color textSecondary: Theme.secondaryLabel(root.darkMode)
    readonly property color textTertiary: Theme.tertiaryLabel(root.darkMode)
    readonly property color cardFill: root.darkMode ? "#2c2c2e" : "#ffffff"
    readonly property color cardHover: root.darkMode ? "#3a3a3c" : "#f2f2f7"

    // 注册表 → 有序条目数组（保持对象插入序，从上到下排列）。
    readonly property var entries: {
        var ids = Object.keys(root.widgetCatalog || {});
        var out = [];
        for (var i = 0; i < ids.length; i++) {
            var entry = root.widgetCatalog[ids[i]];
            if (!entry || !entry.source)
                continue;
            out.push({
                "id": ids[i],
                "name": String(entry.name || ids[i]),
                "sizes": Array.isArray(entry.sizes) ? entry.sizes : []
            });
        }
        return out;
    }

    // 尺寸 id → 显示名（small/medium/large 三档，与 WidgetGrid.js 一致）。
    function sizeLabel(size) {
        if (size === "medium")
            return "中";
        if (size === "large")
            return "大";
        return "小";
    }

    function sizesText(sizes) {
        var labels = [];
        for (var i = 0; i < sizes.length; i++)
            labels.push(root.sizeLabel(String(sizes[i] || "")));
        return labels.length > 0 ? labels.join(" / ") : "";
    }

    // ---- 添加失败横幅（可见反馈，不静默失败）----
    property bool bannerVisible: false
    onAddFailedChanged: {
        if (root.addFailed) {
            root.bannerVisible = true;
            bannerHide.restart();
        }
    }
    Timer {
        id: bannerHide
        interval: 4000
        repeat: false
        onTriggered: root.bannerVisible = false
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // 失败横幅：贴顶，短暂显示后自动消失。
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.bannerVisible ? 36 : 0
            clip: true
            opacity: root.bannerVisible ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
            }

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 2
                radius: 12
                color: root.darkMode ? "#3a3a3c" : "#fff0f0"
                border.color: root.darkMode ? "#224d4d4f" : "#26d70000"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    // 覆盖「桌面无空位 / 配置未就绪 / 未知条目」等失败原因
                    // （对抗审查 C2/P2：单一文案不得误导为仅桌面已满）。
                    text: "无法添加小部件"
                    color: root.darkMode ? "#ff9f9f" : "#c73a3a"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // 无可用小部件时的空态（注册表为空时避免整页空白）。
            Text {
                anchors.centerIn: parent
                visible: root.entries.length === 0
                text: "暂无可用小部件"
                color: root.textTertiary
                font.pixelSize: 13
            }

            Flickable {
                id: mainFlick
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: mainColumn.implicitHeight
                interactive: contentHeight > height
                visible: root.entries.length > 0

                Column {
                    id: mainColumn
                    width: mainFlick.width
                    spacing: 10

                    Repeater {
                        id: entryRepeater
                        model: root.entries

                        delegate: Item {
                            required property var modelData

                            // 是否已在桌面（presentWidgets 快照；宿主配置唯一
                            // id，重复添加会被 gridStateFromConfig 拒绝）。
                            readonly property bool present: root.isPresent(String(modelData.id || ""))

                            width: mainColumn.width
                            height: 62

                            // 入场：cardsEnter 门控（与系统/天气页同一
                            // 侧栏入场语义；非编辑模式常驻动画）。
                            property real enterY: root.cardsEnter ? 0 : Motion.sidebarCardEnterOffsetPx
                            property real enterOpacity: root.cardsEnter ? 1 : 0
                            transform: Translate { y: enterY }
                            opacity: enterOpacity
                            Behavior on enterY {
                                NumberAnimation { duration: Motion.sidebarCardEnterDuration(root.settingsService); easing.type: Motion.emphasizedDecel }
                            }
                            Behavior on enterOpacity {
                                NumberAnimation { duration: Motion.sidebarCardEnterDuration(root.settingsService); easing.type: Motion.emphasizedDecel }
                            }

                            Rectangle {
                                id: entryCard
                                anchors.fill: parent
                                radius: 18
                                color: root.cardFill
                                Behavior on color {
                                    ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    color: root.textPrimary
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: present ? "已添加"
                                        : (root.sizesText(modelData.sizes).length > 0 ? "尺寸：" + root.sizesText(modelData.sizes) : "")
                                    color: present ? root.textTertiary : root.textSecondary
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                // 已在桌面：标记「已添加」且不可重复点击（宿主配置
                                // 唯一 id，重复添加会被拒绝；禁用可避免误报「桌面已满」）。
                                enabled: !present
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onEntered: entryCard.color = root.cardHover
                                onExited: entryCard.color = root.cardFill
                                onClicked: root.addRequested(String(modelData.id || ""))
                            }
                        }
                    }
                }
            }
        }
    }
}
