pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."
import "../TahoeGlass.js" as GlassStyle
import "WidgetGrid.js" as Grid

// 桌面小部件宿主层（A2 承载基础设施）。
//
// 层级契约（A-C1 / P-6）：
// - WlrLayer.Bottom（壁纸之上、窗口之下）；ExclusionMode.Ignore
// - KeyboardInteractivity.None（WlrKeyboardFocus.None）；不设 focusable
//   （C7 首击吞噬约束，见 constraints.md P-6）
// - namespace "tahoe-widgets"（niri layer-rule 动画可独立匹配）
// - mask：顶栏弹层打开 → 置空（点击直达 PopupDismissLayer 收回弹层）；
//   否则 → 各小部件 Item 并集（小部件接收点击，空白穿透到桌面）
//
// 网格：4×6 单元格（屏宽 4 列、屏高方向最多 6 行），每屏一份宿主，
// 配置按屏持久化（widgets.json 以屏幕名为根，数组格式 [{id,size,col,row}]）。
//
// region 计数保护（P-5）：每个小部件 1 个 region；每屏网格容量 ≤24，
// 单屏不可能超 32，但配置文件跨屏总条目可能超限（最多 24×N），故
// 加载时对【每屏条目上限 24】截断，并把被截断的条目数计入超限横幅
// （可见反馈，不静默失效）。
PanelWindow {
    id: root

    required property var screen
    // 顶栏弹层打开（该屏）→ mask 置空。由 shell 注入。
    property bool popupActive: false
    // 服务注入（A2 电池；A3 起注入天气 / 系统监控）。
    property var batteryService
    property var weatherService
    property var systemStatsService

    // 宿主可见性（真实门控源）：注入到每个小部件 hostVisible，
    // 宿主隐藏 → dataRefreshActive=false → 刷新/动画停止（A3 判据）。
    readonly property bool hostVisible: root.visible
    // 系统监控小部件在场且宿主可见 → 激活既有 SystemStats 服务
    // （shell.qml 聚合各屏需求；同一服务、同一进程，非新唤醒源）。
    // 注意不能把此值绑到 widgetInstances[...]：widgetInstances 在
    // rebuildWidgets 中先整体重赋再逐个 mutation，mutation 不触发
    // QML 绑定重算（会卡死在 false）。故用显式刷新（重建/可见性变化
    // 两个已知变更点，见 refreshSystemStatsDemand）。
    property bool systemStatsDemand: false
    function refreshSystemStatsDemand() {
        var next = root.hostVisible && !!root.widgetInstances["system-monitor"];
        if (root.systemStatsDemand !== next)
            root.systemStatsDemand = next;
    }

    // ---- 层级契约 ----
    // 宿主可见性跟随小部件实例数：无小部件 → 宿主隐藏（层不映射），
    // 有 → 可见。这给「宿主隐藏 → 刷新停止」判据一个真实可执行的触发
    // 路径（移除最后一个小部件即隐藏，hostVisible 门控随之生效）。
    visible: root.widgetInstancesCount > 0
    updatesEnabled: visible
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: false
    focusable: false
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "tahoe-widgets"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }
    color: "transparent"

    // ---- 屏与网格 ----
    readonly property int screenWidth: Math.max(1, Math.round(Number(root.screen && root.screen.width) || 1))
    readonly property int screenHeight: Math.max(1, Math.round(Number(root.screen && root.screen.height) || 1))
    readonly property real cellSize: Math.min(Math.max(1, screenWidth / Grid.GRID_COLS), 90)
    // 小部件矩形上限（整列整行占满时需 clamp 到屏内）。
    readonly property int widgetMaxWidth: Math.max(1, Math.round(screenWidth))
    readonly property int widgetMaxHeight: Math.max(1, Math.round(screenHeight))

    // ---- 配置 ----
    readonly property string configPath: Quickshell.stateDir + "/widgets.json"
    readonly property string screenKey: String(root.screen && root.screen.name || "default")

    // ---- 状态 ----
    property var widgetConfigs: []      // 本屏配置（已清洗，数组）
    property int overflowCount: 0       // 未显示条数（本屏清洗剔除）
    property bool loadingComplete: false

    // 小部件注册表：id → {source, name}。A4 库 tab 复用同一注册表。
    // source 相对本文件所在目录（components/widgets/）。
    // defaultSize：A4 库 tab / addWidget 的默认规格（天气/日历为 medium，
    // 按 small 创建会挤压布局）。
    readonly property var widgetCatalog: ({
        "battery": { "source": "BatteryWidget.qml", "name": "电池", "defaultSize": "small" },
        "weather": { "source": "WeatherWidget.qml", "name": "天气", "defaultSize": "medium" },
        "calendar": { "source": "CalendarWidget.qml", "name": "日历", "defaultSize": "medium" },
        "system-monitor": { "source": "SystemMonitorWidget.qml", "name": "系统监控", "defaultSize": "small" }
    })

    // mask 并集引用的小部件对象（buildUnionRegion 填充）。必须挂在
    // root 属性上：Qt.createQmlObject 的字符串只在该 QML 文档的 context
    // 中解析标识符，JS 局部变量不可见（实证：item 绑定解析失败会让
    // region 恒空、mask 退化为全屏输入区）。经 root.maskWidgetItems[i]
    // 引用是文档内合法解析。
    property var maskWidgetItems: []

    // ---- 网格状态（单一来源：WidgetGrid.js 的 GridState）----
    readonly property var gridState: Grid.gridStateFromConfig(root.widgetConfigs)

    // ---- 子项生成 ----
    // 实例表：id → 实例（QObject）。动态创建（配置异步到达，无法静态 Loader）。
    property var widgetInstances: ({})
    // 实例数（显式维护：widgetInstances 的 mutation 不触发 QML 绑定重算，
    // 直接绑 Object.keys 会卡在旧值）。宿主 visible 依赖它。
    property int widgetInstancesCount: 0

    function createWidgetInstance(entry) {
        if (!entry || !root.widgetCatalog[String(entry.id || "")])
            return null;
        if (root.widgetInstances[entry.id])
            return root.widgetInstances[entry.id];

        // source 相对本文件所在目录（components/widgets/），
        // Qt.createComponent 相对 URL 以调用 JS 所在文件目录为基准。
        var source = root.widgetCatalog[entry.id].source;
        var component = Qt.createComponent(source, root);
        if (component.status !== Component.Ready) {
            console.warn("[widgets] createComponent failed: " + source
                + " (" + component.errorString() + ")");
            return null;
        }
        // 按目录条目注入各自服务（避免向无关小部件传不存在的属性）。
        // widgetSize 从跨度经 WidgetGrid.js 唯一来源推导（gridState 条目
        // 只带 cols/rows；配置里的 size 字段经 serializeEntries 已规范化，
        // 但 gridState 条目本身不带 size，直接读 entry.size 会恒为 small）。
        var props = {
            "widgetSize": Grid.sizeForSpan(entry.cols, entry.rows),
            "cellSize": root.cellSize,
            "x": Math.max(0, Math.round(entry.gridX * root.cellSize)),
            "y": Math.max(0, Math.round(root.screenHeight - (entry.gridY + entry.rows) * root.cellSize)),
            "width": Math.min(root.widgetMaxWidth, Math.max(1, Math.round(entry.cols * root.cellSize))),
            "height": Math.min(root.widgetMaxHeight, Math.max(1, Math.round(entry.rows * root.cellSize))),
            "previewMode": false
        };
        var sid = String(entry.id || "");
        if (sid === "battery")
            props.batteryService = root.batteryService;
        else if (sid === "weather")
            props.weatherService = root.weatherService;
        else if (sid === "system-monitor")
            props.systemStatsService = root.systemStatsService;
        var obj = component.createObject(widgetLayer, props);
        if (!obj) {
            console.warn("[widgets] createObject failed: " + source);
            return null;
        }
        // hostVisible 用绑定（非一次性初值）：宿主可见性后续变化时
        // 小部件门控实时跟随（createObject 初值是一次性赋值）。
        obj.hostVisible = Qt.binding(function() { return root.hostVisible; });
        root.widgetInstances[entry.id] = obj;
        return obj;
    }

    // 重建全部实例（配置或几何变化后）。先销毁旧的（避免 id 重复）。
    function rebuildWidgets() {
        var old = root.widgetInstances;
        root.widgetInstances = {};
        var keys = Object.keys(old);
        for (var i = 0; i < keys.length; i++)
            old[keys[i]].destroy();
        for (var j = 0; j < root.gridState.grid.length; j++) {
            var entry = root.gridState.grid[j];
            root.createWidgetInstance(entry);
        }
        root.widgetInstancesCount = Object.keys(root.widgetInstances).length;
        root.updateMask();
        root.refreshSystemStatsDemand();
    }

    onHostVisibleChanged: root.refreshSystemStatsDemand()

    // mask：弹层打开 → 空；否则 → 小部件 Item 并集。
    // 替换旧 mask 时销毁旧 Region 对象树（setMask 只 disconnect 不删
    // 对象；不销毁则每次弹层开关/重建泄漏一棵 Region 树）。
    function updateMask() {
        var oldMask = root.mask;
        if (root.popupActive) {
            root.mask = null;
        } else {
            root.mask = root.buildUnionRegion();
        }
        if (oldMask && oldMask !== root.mask)
            oldMask.destroy();
    }

    // Region 并集：顶层 Region（Intersect 剪到全屏）× 若干子 Region
    // （默认 Combine）→ PendingRegion::applyTo 顺序合并（region.cpp:233）。
    // item 引用必须经 root.maskWidgetItems[i]（文档 id + 属性路径），
    // 不能写 JS 局部变量名（createQmlObject 不捕获调用函数作用域）。
    function buildUnionRegion() {
        var widgetList = [];
        var keys = Object.keys(root.widgetInstances);
        for (var i = 0; i < keys.length; i++) {
            var inst = root.widgetInstances[keys[i]];
            if (inst && inst.interactive)
                widgetList.push(inst);
        }
        if (widgetList.length === 0)
            return null;

        root.maskWidgetItems = widgetList;

        var regionText = "import Quickshell; ";
        regionText += "Region { x: 0; y: 0; width: " + root.screenWidth
            + "; height: " + root.screenHeight + "; intersection: Intersection.Intersect; ";
        for (var j = 0; j < widgetList.length; j++) {
            regionText += "Region { item: root.maskWidgetItems[" + j + "] } ";
        }
        regionText += "}";
        return Qt.createQmlObject(regionText, root, "widgetsMask");
    }

    // ---- 配置读写（FileView；T07 非阻塞写状态机）----
    FileView {
        id: configFile
        path: root.configPath
        blockLoading: false
        blockAllReads: false
        blockWrites: false
        printErrors: false
        onLoaded: root.loadConfig()
        onLoadFailed: root.loadConfig()
    }

    // 启动时异步读；完成后按屏切片 + 清洗 + 建实例。
    function loadConfig() {
        var raw = configFile.text();
        var parsed = null;
        if (raw && raw.trim().length > 0) {
            try {
                parsed = JSON.parse(raw);
            } catch (e) {
                console.warn("[widgets] config parse failed: " + e);
            }
        }

        var list = [];
        if (Array.isArray(parsed))
            list = parsed;
        else if (parsed && typeof parsed === "object")
            list = Array.isArray(parsed[root.screenKey]) ? parsed[root.screenKey] : [];

        // 清洗（越界/重叠/重复剔除）→ 得出实际可显示条目与未显示数。
        var state = Grid.gridStateFromConfig(list);
        root.widgetConfigs = Grid.serializeEntries(state);
        // 未显示数 = 本屏剔除条目（每屏独立 surface，region 上限按 surface
        // 计，跨屏条目不参与本屏超限；多屏混算会产生假阳性）。
        root.overflowCount = state.removed.length;
        root.rebuildWidgets();
        root.loadingComplete = true;
    }

    // 写回配置：读取当前全量文件内容 → 覆盖本屏段 → 整体写回。
    // 只在操作完成时调用一次（A-C5）。
    // P-7 早退门：初次加载完成前调用会以空内容覆盖全量配置（丢其他屏
    // 段）。A4 接入前本函数无调用方，门是防御性的。
    function persistConfig() {
        if (!root.loadingComplete)
            return;
        var raw = configFile.text();
        var parsed = {};
        if (raw && raw.trim().length > 0) {
            try {
                var p = JSON.parse(raw);
                if (p && typeof p === "object")
                    parsed = p;
            } catch (e) {
                console.warn("[widgets] config parse failed (persist): " + e);
            }
        }
        parsed[root.screenKey] = root.widgetConfigs;
        configFile.setText(JSON.stringify(parsed, null, 2));
    }

    // ---- 对外 API（A4 库 tab / A6 编辑模式接入点）----
    // 添加小部件：找空位 → 建实例 → 写盘。
    function addWidget(id) {
        var catalog = root.widgetCatalog[String(id || "")];
        if (!catalog)
            return false;
        var size = String(catalog.defaultSize || "small");
        var slot = Grid.findSlot(root.gridState, Grid.colsForSize(size), Grid.rowsForSize(size));
        if (!slot)
            return false;

        var nextConfig = root.widgetConfigs.concat([{
            "id": String(id),
            "size": size,
            "col": slot.col,
            "row": slot.row
        }]);
        var nextState = Grid.gridStateFromConfig(nextConfig);
        if (nextState.removed.length > 0)
            return false;

        root.widgetConfigs = Grid.serializeEntries(nextState);
        root.rebuildWidgets();
        root.persistConfig();
        return true;
    }

    // 移除小部件（对象树真正销毁 + 写盘）。
    function removeWidget(id) {
        var sid = String(id || "");
        if (!root.widgetInstances[sid])
            return false;
        var nextConfig = [];
        for (var i = 0; i < root.widgetConfigs.length; i++) {
            if (String(root.widgetConfigs[i].id || "") !== sid)
                nextConfig.push(root.widgetConfigs[i]);
        }
        if (nextConfig.length === root.widgetConfigs.length)
            return false;
        root.widgetConfigs = nextConfig;
        root.rebuildWidgets();
        root.persistConfig();
        return true;
    }

    // ---- mask 与弹层联动 ----
    onPopupActiveChanged: root.updateMask()

    Component.onCompleted: {
        root.updateMask();
    }

    // ---- 可见反馈：超限横幅（P-5；不 spawn 进程、无轮询）----
    // 配置加载完成（loadingComplete 为真）后若 hasOverflow，显示横幅。
    readonly property bool hasOverflow: root.overflowCount > 0

    Timer {
        id: overflowBannerTimer
        interval: 400
        repeat: false
        onTriggered: {
            root.overflowBannerVisible = true;
            overflowBannerHide.restart();
        }
    }
    Timer {
        id: overflowBannerHide
        interval: 6000
        repeat: false
        onTriggered: root.overflowBannerVisible = false
    }
    property bool overflowBannerVisible: false
    onLoadingCompleteChanged: {
        if (root.loadingComplete && root.hasOverflow)
            overflowBannerTimer.restart();
    }

    // 横幅渲染层（mask 之上：遮罩不挡横幅，且 mask 无 region 时横幅仍在）。
    Item {
        id: bannerLayer
        anchors.fill: parent
        visible: root.overflowBannerVisible

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            width: Math.min(360, root.screenWidth - 48)
            height: 44
            radius: GlassStyle.RadiusPanelCompact
            color: "#cc1d1d1f"

            Text {
                anchors.centerIn: parent
                text: "小部件配置超限：" + root.overflowCount + " 个未显示"
                color: "#ffffff"
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // ---- 小部件层（mask 覆盖区域）----
    Item {
        id: widgetLayer
        anchors.fill: parent
    }
}
