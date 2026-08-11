pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "Motion.js" as Motion
import "settings/SettingsTheme.js" as Theme
import "widgets/WidgetGrid.js" as Grid

// A5：侧栏第三个 tab「小部件」—— 带真实预览的画廊（A4 文字列表升级）。
//
// 数据单一来源：WidgetHost.qml 的 widgetCatalog（由 shell 注入本组件，
// 不在此处维护第二份注册表，G-6）。每个条目渲染小部件的**真实预览实例**
// （WidgetPreview：previewMode=true，禁用交互与数据刷新，A-C3）；同一
// 小部件的多种可选尺寸以尺寸 chips 分别预览与选择。点击卡片发
// addRequested(id, selectedSize)，由 shell 负责：成功 → 关闭侧栏 +
// 桌面空位添加；失败（桌面已满）→ 回灌 addFailed → 本组件显示可见反馈。
//
// 约束：
// - A-C3：无自建轮询；反馈横幅用单发 Timer（与 WidgetHost 超限横幅同
//   模式）；预览实例经 previewMode 停摆数据刷新，无常驻刷新路径。
// - P-1/P-3：动画只用 Motion.js 令牌（禁弹簧、无硬编码 duration 字面量）。
// - G-6：尺寸 → 网格换算唯一来源 WidgetGrid.js（colsForSize/rowsForSize）。
Item {
    id: root

    property var widgetCatalog: ({})
    // 宿主当前实例表（shell 注入；对象被宿主在重建时整体替换，
    // onPresentWidgetsChanged 驱动刷新「已添加」标记）。
    property var presentWidgets: ({})
    property var settingsService: null
    // A5：预览实例的数据源（同一批 singleton；预览只读锁存快照）。
    property var batteryService: null
    property var weatherService: null
    property var systemStatsService: null
    property bool darkMode: false
    property bool cardsEnter: false
    property bool useSpring: false
    // shell 回灌：最近一次添加失败（桌面无空位）。true 时显示横幅。
    property bool addFailed: false

    signal addRequested(string id, string size)

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
    readonly property color chipSelected: root.darkMode ? "#3a3a3c" : "#e5e5ea"
    readonly property color chipStroke: root.darkMode ? "#33ffffff" : "#1a000000"

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
                "source": String(entry.source || ""),
                "sizes": Array.isArray(entry.sizes) ? entry.sizes : [],
                "defaultSize": String(entry.defaultSize || "small")
            });
        }
        return out;
    }

    // 尺寸列表归一（QML 模型会包装 JS 数组：Repeater 的 modelData.sizes
    // 经 Array.isArray 为 false，必须按对象+length 兜底复制，否则多尺寸
    // 条目被误判为单尺寸 —— 真机探针实测 sizesJson 有值但 Array.isArray
    // 为假）。
    function sizeList(sizes) {
        if (Array.isArray(sizes))
            return sizes;
        var out = [];
        if (sizes && typeof sizes === "object" && typeof sizes.length === "number") {
            for (var i = 0; i < sizes.length; i++)
                out.push(String(sizes[i]));
        }
        return out;
    }

    // 条目初始选中尺寸：catalog.defaultSize 优先，否则首个合法尺寸。
    function initialSize(entry) {
        var list = root.sizeList(entry && entry.sizes);
        var def = String(entry && entry.defaultSize ? entry.defaultSize : "small");
        for (var i = 0; i < list.length; i++) {
            if (String(list[i]) === def)
                return def;
        }
        return list.length > 0 ? String(list[0]) : "small";
    }

    // 尺寸 id → 显示名（small/medium/large 三档，与 WidgetGrid.js 一致）。
    function sizeLabel(size) {
        if (size === "medium")
            return "中";
        if (size === "large")
            return "大";
        return "小";
    }

    // 预览单元尺寸：小部件按网格 span 缩放渲染（4 列占满时约等于
    // 内容宽，2 行高度）；clamp 防过小/过大。
    readonly property real previewCell: Math.max(24, Math.min(72, Math.floor((root.width - 48) / 4)))

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

    // 尺寸选择 chip（multiSize 条目才显示）。点击只切档，不触发添加
    // （chip 的 MouseArea 优先于卡片 MouseArea）。
    component SizeChip: Rectangle {
        id: chip
        required property string size
        required property bool selected
        // 注意：不能命名 enabled（遮蔽 QQuickItem.enabled，qmllint
        // property-override 告警）；点击可用性由宿主 present 状态决定。
        required property bool clickable

        width: 44
        height: 26
        radius: 8
        color: chip.selected ? root.chipSelected : "transparent"
        border.color: chip.selected ? "transparent" : root.chipStroke
        border.width: 1
        Behavior on color {
            ColorAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.standardDecel }
        }

        Text {
            anchors.centerIn: parent
            text: root.sizeLabel(chip.size)
            color: chip.selected ? root.textPrimary : root.textSecondary
            font.pixelSize: 11
            font.weight: chip.selected ? Font.DemiBold : Font.Normal
        }

        MouseArea {
            anchors.fill: parent
            enabled: chip.clickable
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
        signal clicked()
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
                            readonly property bool multiSize: root.sizeList(modelData.sizes).length > 1
                            // 初始选中尺寸：catalog.defaultSize 优先，否则首个合法尺寸。
                            // 必须是绑定（函数调用）而非一次性初始化块：Repeater
                            // 的 required modelData 在属性初始化之后才注入，初始化
                            // 块会拿到 undefined 而恒回退 small（真机探针实测）。
                            property string selectedSize: root.initialSize(modelData)
                            function hasSize(s) {
                                var sizes = root.sizeList(modelData.sizes);
                                for (var i = 0; i < sizes.length; i++) {
                                    if (String(sizes[i]) === s)
                                        return true;
                                }
                                return false;
                            }

                            readonly property real previewW: Math.max(1, Math.round(Grid.colsForSize(selectedSize) * root.previewCell))
                            readonly property real previewH: Math.max(1, Math.round(Grid.rowsForSize(selectedSize) * root.previewCell))
                            // 卡片高 = 上下边距 + 头部 + 预览区 + （多尺寸时）chips 行。
                            readonly property real cardHeight: 12 + 22 + 10 + previewH + (multiSize ? 8 + 26 : 0) + 12

                            width: mainColumn.width
                            height: cardHeight

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

                                // 卡片点击（添加）垫底：chips 的 MouseArea 在
                                // 上层优先消费点击，不误触添加。
                                MouseArea {
                                    anchors.fill: parent
                                    // 已在桌面：标记「已添加」且不可重复点击（宿主配置
                                    // 唯一 id，重复添加会被拒绝；禁用可避免误报「桌面已满」）。
                                    enabled: !present
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onEntered: entryCard.color = root.cardHover
                                    onExited: entryCard.color = root.cardFill
                                    onClicked: root.addRequested(String(modelData.id || ""), selectedSize)
                                }

                                // 头部：名称 + 已添加/单尺寸标注。
                                Item {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.topMargin: 12
                                    height: 22

                                    Text {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.name
                                        color: root.textPrimary
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: present ? "已添加"
                                            : (multiSize ? "" : "尺寸：" + root.sizeLabel(selectedSize))
                                        color: present ? root.textTertiary : root.textSecondary
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }

                                // 预览区：真实小部件实例（previewMode），
                                // 按选中尺寸的网格 span 缩放居中。
                                Item {
                                    id: previewArea
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    anchors.topMargin: 44
                                    width: previewW
                                    height: previewH
                                    clip: true

                                    WidgetPreview {
                                        anchors.fill: parent
                                        widgetId: String(modelData.id || "")
                                        source: String(modelData.source || "")
                                        widgetSize: selectedSize
                                        cellSize: root.previewCell
                                        batteryService: root.batteryService
                                        weatherService: root.weatherService
                                        systemStatsService: root.systemStatsService
                                    }
                                }

                                // 尺寸 chips：multiSize 条目可分别预览与选择；
                                // 已添加时禁用（不可重复添加）。
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: previewArea.bottom
                                    anchors.topMargin: 8
                                    visible: multiSize
                                    spacing: 6

                                    SizeChip {
                                        size: "small"
                                        selected: selectedSize === "small"
                                        clickable: !present
                                        visible: hasSize("small")
                                        onClicked: selectedSize = "small"
                                    }
                                    SizeChip {
                                        size: "medium"
                                        selected: selectedSize === "medium"
                                        clickable: !present
                                        visible: hasSize("medium")
                                        onClicked: selectedSize = "medium"
                                    }
                                    SizeChip {
                                        size: "large"
                                        selected: selectedSize === "large"
                                        clickable: !present
                                        visible: hasSize("large")
                                        onClicked: selectedSize = "large"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
