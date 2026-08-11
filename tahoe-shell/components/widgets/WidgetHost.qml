pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../Motion.js" as Motion
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
// 网格：按屏铺满（gridCols×gridRows = floor(屏宽/高 ÷ cellSize)，cellSize
// 固定 ≤90px），小部件可摆放到桌面任意位置；配置按屏持久化
// （widgets.json 以屏幕名为根，数组格式 [{id,size,col,row}]）。
//
// region 计数保护（P-5）：每个小部件 1 个 region；每屏条目上限
// widgetLimit = min(32, 网格容量)，加载时超限截断并计入超限横幅
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
    // 顶栏保留区（TopBar.qml implicitHeight/exclusiveZone = 40）：小部件
    // 最高只能贴着顶栏下沿，不得进入顶栏区域（A6 部署反馈）。
    readonly property int topReserved: 40
    // ---- 全屏网格（A6 部署反馈修复）----
    // cellSize 宽度方向 ≤90px（小部件尺寸语义不变）；垂直方向自适应使
    // 网格恰好铺满 [topReserved, screenHeight] —— 最高行的像素上缘恒等于
    // topReserved（贴着顶栏，不会顶进顶栏；旧实现固定 90px 时 1240px
    // 无法整除，最顶行要么进顶栏要么留 70px 空隙）。
    readonly property real cellSize: {
        var desired = Math.min(Math.max(1, root.screenWidth / Grid.GRID_COLS), 90);
        var usable = Math.max(1, root.screenHeight - root.topReserved);
        var rows = Math.max(Grid.GRID_ROWS, Math.ceil(usable / desired));
        return Math.min(desired, usable / rows);
    }
    // 列数 floor 保证不超屏宽；行数按顶栏以下可用高度铺满（ceil 与
    // cellSize 的 usable/rows 定义一致，网格矩形 = [topReserved, 屏底]）。
    readonly property int gridCols: Math.max(Grid.GRID_COLS, Math.floor(root.screenWidth / root.cellSize))
    readonly property int gridRows: Math.max(Grid.GRID_ROWS, Math.ceil((root.screenHeight - root.topReserved) / root.cellSize))
    // 每屏条目上限 = min(32, 网格容量)：P-5 region 上限（每小部件 1 个
    // region），超限在加载/添加时截断并计入超限横幅（可见反馈）。
    readonly property int widgetLimit: Math.min(32, root.gridCols * root.gridRows)
    // 小部件矩形上限（整列整行占满时需 clamp 到屏内）。
    readonly property int widgetMaxWidth: Math.max(1, Math.round(screenWidth))
    readonly property int widgetMaxHeight: Math.max(1, Math.round(screenHeight))

    // ---- 配置 ----
    // configPath 已提升到 shell 级共享 FileView（A4 单一所有者，见下）。
    readonly property string screenKey: String(root.screen && root.screen.name || "default")

    // ---- 状态 ----
    property var widgetConfigs: []      // 本屏配置（已清洗，数组）
    property int overflowCount: 0       // 未显示条数（本屏清洗剔除）
    property bool loadingComplete: false

    // 小部件注册表：id → {source, name, sizes, defaultSize}。
    // 全仓库唯一注册表（A4 库 tab 复用；禁止另建第二份，G-6）。
    // source 相对本文件所在目录（components/widgets/）。
    // sizes：该小部件支持的可选尺寸（A4 库 tab 展示、A7 换档契约）；
    // defaultSize：A4 库 tab / addWidget 的默认规格（天气/日历为 medium，
    // 按 small 创建会挤压布局）。defaultSize 必须在 sizes 内。
    readonly property var widgetCatalog: ({
        "battery": { "source": "BatteryWidget.qml", "name": "电池", "sizes": ["small"], "defaultSize": "small" },
        "weather": { "source": "WeatherWidget.qml", "name": "天气", "sizes": ["medium"], "defaultSize": "medium" },
        "calendar": { "source": "CalendarWidget.qml", "name": "日历", "sizes": ["medium"], "defaultSize": "medium" },
        "system-monitor": { "source": "SystemMonitorWidget.qml", "name": "系统监控", "sizes": ["small"], "defaultSize": "small" }
    })

    // ---- 配置读写（A4 起单一所有者）----
    // widgets.json 由 shell 级共享 FileView + 内存镜像统一读写
    // （多屏共用同一文件：各屏各自持有 FileView 会以陈旧缓存互相覆盖
    // 丢配置，对抗审查 C2）。本宿主只读注入的 FileView 切片自己的屏段；
    // 写经 persistConfigRequested 提交给 shell 合并后落盘（G-6 单一路径）。
    property var configFile: null
    // 共享 FileView 是否已完成首次加载（含失败，如文件不存在）。shell 在
    // onLoaded/onLoadFailed 时置真；宿主可能在加载完成后才被创建（单文件
    // 单一所有者，FileView 先于 Variants 创建），故用标志 + onCompleted
    // 兜底，而不是只依赖 onLoaded 信号（对抗审查 C2 修复的时序面）。
    property bool configLoaded: false
    signal persistConfigRequested(string screenKey, var configs)

    // mask 并集引用的小部件对象（buildUnionRegion 填充）。必须挂在
    // root 属性上：Qt.createQmlObject 的字符串只在该 QML 文档的 context
    // 中解析标识符，JS 局部变量不可见（实证：item 绑定解析失败会让
    // region 恒空、mask 退化为全屏输入区）。经 root.maskWidgetItems[i]
    // 引用是文档内合法解析。
    property var maskWidgetItems: []

    // ---- 网格状态（单一来源：WidgetGrid.js 的 GridState）----
    readonly property var gridState: Grid.gridStateFromConfig(root.widgetConfigs, root.gridCols, root.gridRows)

    // ---- 子项生成 ----
    // 实例表：id → 实例（QObject）。动态创建（配置异步到达，无法静态 Loader）。
    property var widgetInstances: ({})
    // 实例数（显式维护：widgetInstances 的 mutation 不触发 QML 绑定重算，
    // 直接绑 Object.keys 会卡在旧值）。宿主 visible 依赖它。
    property int widgetInstancesCount: 0

    // ---- A6 编辑模式 ----
    // 任一实例长按进入；「完成」按钮 / 点击桌面空白退出。进入/退出不写盘。
    property bool editMode: false
    function enterEditMode() {
        root.editMode = true;
    }
    function exitEditMode() {
        if (root.dragActive) {
            // 拖动中退出（完成按钮/空白点击/宿主隐藏）：完整回滚——恢复
            // 实例网格位 + 清宿主拖动状态 + 实例手势由 editMode 绑定归零，
            // 不写盘（A-C5）。
            dragXAnim.stop();
            dragYAnim.stop();
            var inst = root.widgetInstances[root.dragWidgetId];
            var start = root.dragStart;
            if (inst && start) {
                inst.x = start.x;
                inst.y = start.y;
            }
            root.clearDrag();
        } else {
            // 无拖动：把可能仍在飞的提交/回滚动画直接补送到终点
            // （实例位置恒等于 config，见 settleWidgets）。
            root.settleWidgets();
        }
        root.editMode = false;
    }
    // 宿主隐藏（移除最后一个小部件等）→ 自动退出编辑模式。
    onVisibleChanged: if (!root.visible) root.exitEditMode()
    // 编辑模式切换 → 重算 mask（编辑态为全屏输入区，见 buildUnionRegion）。
    onEditModeChanged: root.updateMask()

    // 拖动状态（Dock 四状态模式的宿主侧，A-C2）：手势在 Widget.qml 的
    // MouseArea，网格落点/持久化/回滚在本文件。拖动期间只改实例 x/y，
    // 不重建、不写盘（A-C5：仅 onReleased 的 commit 写一次）。
    property bool dragActive: false
    property string dragWidgetId: ""
    // {id,size,cols,rows,col,row,x,y,grabX,grabY} —— 拖动起点快照。
    property var dragStart: null

    function createWidgetInstance(entry, into) {
        // into：重建时传入的临时实例表（A5 审查 C1）。实例表必须「填完再
        // 整体赋值」——先赋空再逐个 mutation 不触发 QML notify，会让
        // 「已添加」观察者（库页 presentIds）停在空快照。
        var map = into || root.widgetInstances;
        if (!entry || !root.widgetCatalog[String(entry.id || "")])
            return null;
        if (map[entry.id])
            return map[entry.id];

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
            // A6：实例自述 id / 宿主引用（拖动与删除回调入口）；网格像素
            // 换算唯一来源 WidgetGrid.js（xPxForCell/yPxForCell，G-6）。
            "widgetId": String(entry.id || ""),
            "widgetHost": root,
            "cellSize": root.cellSize,
            "x": Math.max(0, Grid.xPxForCell(entry.gridX, root.cellSize)),
            "y": Math.max(0, Grid.yPxForCell(entry.gridY, entry.rows, root.cellSize, root.screenHeight)),
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
        // editMode 同样以绑定注入：进入/退出编辑模式时全部实例实时跟随
        // （一次性初值会在后续切换时卡在旧值）。
        obj.editMode = Qt.binding(function() { return root.editMode; });
        map[entry.id] = obj;
        return obj;
    }

    // 重建全部实例（配置或几何变化后）。先销毁旧的（避免 id 重复）。
    // 实例表填完后再整体赋值一次（不是先赋空再 mutation）：
    // mutation 不触发 QML 属性变更，先赋空会让库页「已添加」快照
    // 停在空表（A5 对抗审查 C1）。
    function rebuildWidgets() {
        // 防御性：重建销毁实例前清拖动状态 + 停落位动画（拖动中配置被
        // 重建的极边缘时序，避免宿主 dragActive 残留卡死或动画指向已销毁
        // 实例；正常路径无影响）。
        root.clearDrag();
        dragXAnim.stop();
        dragYAnim.stop();
        var old = root.widgetInstances;
        var next = {};
        var keys = Object.keys(old);
        for (var i = 0; i < keys.length; i++)
            old[keys[i]].destroy();
        for (var j = 0; j < root.gridState.grid.length; j++) {
            var entry = root.gridState.grid[j];
            root.createWidgetInstance(entry, next);
        }
        root.widgetInstances = next;
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
        if (root.editMode) {
            // 编辑模式：全屏输入区 —— 空白点击由 editExitCatcher 退出编辑
            // 模式，小部件/删除按钮/完成按钮都在此区域内可点。弹层打开时
            // 仍由 updateMask 的 popupActive 分支置空（弹层优先）。
            root.maskWidgetItems = [];
            var editRegionText = "import Quickshell; ";
            editRegionText += "Region { x: 0; y: 0; width: " + root.screenWidth
                + "; height: " + root.screenHeight + " }";
            return Qt.createQmlObject(editRegionText, root, "widgetsEditMask");
        }
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
    // 共享 FileView 由 shell 注入（单一所有者，见上）。初次加载完成
    // → 切片 + 建实例；写完成只发 saved 不发 loaded，不会触发重载重建。
    onConfigLoadedChanged: {
        if (root.configLoaded)
            root.loadConfig();
    }

    // 启动时异步读；完成后按屏切片 + 清洗 + 建实例。
    function loadConfig() {
        var raw = root.configFile ? String(root.configFile.text() || "") : "";
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
        var state = Grid.gridStateFromConfig(list, root.gridCols, root.gridRows);
        // 每屏条目上限截断（P-5 region 上限 32）：超出部分计入未显示数。
        var kept = state.grid.slice(0, root.widgetLimit);
        root.widgetConfigs = Grid.serializeEntries({ "grid": kept, "removed": [] });
        // 顶栏保留区清洗：进入顶栏区的旧条目（修复前可能已写入）钳到
        // 贴着顶栏的最高行 —— 网格与保留区对齐后该行的像素上缘恰为
        // topReserved。只重定位、不剔除，不计入超限横幅。
        for (var i = 0; i < root.widgetConfigs.length; i++) {
            var entryRows = Grid.rowsForSize(root.widgetConfigs[i].size);
            var maxRow = Math.max(0, root.gridRows - entryRows);
            if (root.widgetConfigs[i].row > maxRow)
                root.widgetConfigs[i].row = maxRow;
        }
        // 未显示数 = 本屏剔除条目 + 超上限截断条数（每屏独立 surface，
        // region 上限按 surface 计，跨屏条目不参与本屏超限）。
        root.overflowCount = state.removed.length + (state.grid.length - kept.length);
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
        // 提交给 shell 单一所有者合并写盘（读共享镜像而非本地陈旧缓存，
        // 多屏顺序添加不互相覆盖，对抗审查 C2）。
        root.persistConfigRequested(String(root.screenKey || "default"), root.widgetConfigs);
    }

    // ---- 对外 API（A4 库 tab / A6 编辑模式接入点）----
    // 添加小部件：找空位 → 建实例 → 写盘。size 为 A5 库预览所选档位；
    // 只有 catalog 声明过的尺寸才是合法档位（与 A7 换档契约一致），
    // 未知/越权尺寸回退 defaultSize，不创建未注册规格的实例。
    function addWidget(id, size) {
        // P-7 早退门（对抗审查 C1）：初次加载完成前不得添加。否则会在空
        // 配置上建实例，随后 loadConfig 用磁盘内容覆盖重建销毁它——
        // 「假成功 + 未持久化 + 无反馈」的启动竞态。返回 false 让库页
        // 显示可见失败反馈。
        if (!root.loadingComplete) {
            console.warn("[widgets] addWidget before config load complete");
            return false;
        }
        var catalog = root.widgetCatalog[String(id || "")];
        if (!catalog)
            return false;
        var sizes = Array.isArray(catalog.sizes) ? catalog.sizes : [];
        var resolved = String(sizes.indexOf(String(size || "")) >= 0
            ? String(size) : String(catalog.defaultSize || "small"));
        var slot = Grid.findSlot(root.gridState, Grid.colsForSize(resolved), Grid.rowsForSize(resolved),
            root.gridCols, root.gridRows, root.widgetLimit);
        if (!slot)
            return false;

        var nextConfig = root.widgetConfigs.concat([{
            "id": String(id),
            "size": resolved,
            "col": slot.col,
            "row": slot.row
        }]);
        var nextState = Grid.gridStateFromConfig(nextConfig, root.gridCols, root.gridRows);
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

    // ---- A6 拖动 API（Dock 四状态模式的宿主侧）----
    // 坐标一律经实例 mapToItem(widgetLayer) 转到宿主坐标系（A-C2，参照
    // Dock.qml:948）。目标必须是 QQuickItem：PanelWindow 不是 QQuickItem
    // （部署实测 TypeError：Could not convert ... to const QQuickItem*），
    // widgetLayer anchors.fill 宿主，坐标等价。网格落点/冲突判定唯一来源
    // WidgetGrid.js。
    function configEntryFor(id) {
        var sid = String(id || "");
        for (var i = 0; i < root.widgetConfigs.length; i++) {
            if (String(root.widgetConfigs[i].id || "") === sid)
                return root.widgetConfigs[i];
        }
        return null;
    }

    // 把全部实例对齐到配置网格位：提交/回滚动画（130ms）中途被新拖动
    // 打断时补送终点，保证「实例位置恒等于 config」（拖动快照与回滚都
    // 以 config 网格位为基准，不被中间帧污染）。
    function settleWidgets() {
        dragXAnim.stop();
        dragYAnim.stop();
        var keys = Object.keys(root.widgetInstances);
        for (var i = 0; i < keys.length; i++) {
            var inst = root.widgetInstances[keys[i]];
            var entry = root.configEntryFor(keys[i]);
            if (!inst || !entry)
                continue;
            // 与 createWidgetInstance 同一钳制（短屏顶部行像素可为负）。
            inst.x = Math.max(0, Grid.xPxForCell(entry.col, root.cellSize));
            inst.y = Math.max(0, Grid.yPxForCell(entry.row, Grid.rowsForSize(entry.size),
                root.cellSize, root.screenHeight));
        }
    }

    // onPressed 侧：记录起点与抓取偏移（不激活、不写盘）。
    function beginWidgetDrag(inst, localX, localY) {
        var id = String(inst && inst.widgetId || "");
        if (!id || root.dragActive || !root.editMode)
            return;
        // 先把上一提交/回滚动画补送到终点，再从 config 网格位快照
        // （实例此刻的 x/y 才是真实起点；避免动画中间帧污染快照）。
        root.settleWidgets();
        var entry = root.configEntryFor(id);
        if (!entry)
            return;
        var p = inst.mapToItem(widgetLayer, localX, localY);
        var startX = Math.max(0, Grid.xPxForCell(entry.col, root.cellSize));
        var startY = Math.max(0, Grid.yPxForCell(entry.row, Grid.rowsForSize(entry.size),
            root.cellSize, root.screenHeight));
        root.dragStart = {
            "id": id,
            "size": String(entry.size || "small"),
            "cols": Grid.colsForSize(entry.size),
            "rows": Grid.rowsForSize(entry.size),
            "col": Math.round(Number(entry.col) || 0),
            "row": Math.round(Number(entry.row) || 0),
            "x": startX,
            "y": startY,
            "grabX": Number(p.x) - startX,
            "grabY": Number(p.y) - startY
        };
        root.dragWidgetId = id;
        root.dragActive = true;
    }

    // onPositionChanged 侧：实例跟随指针（clamp 屏内），不重建、不写盘。
    function updateWidgetDrag(inst, localX, localY) {
        if (!root.dragActive || String(inst && inst.widgetId || "") !== root.dragWidgetId)
            return;
        var p = inst.mapToItem(widgetLayer, localX, localY);
        var maxX = Math.max(0, root.screenWidth - inst.width);
        // 垂直方向钳在顶栏以下（minY = topReserved）：拖动中也不会顶进顶栏。
        var minY = Math.max(0, root.topReserved);
        var maxY = Math.max(minY, root.screenHeight - inst.height);
        inst.x = Math.max(0, Math.min(maxX, p.x - root.dragStart.grabX));
        inst.y = Math.max(minY, Math.min(maxY, p.y - root.dragStart.grabY));
    }

    // onReleased 侧：网格吸附 → 合法则更新配置 + 落位动画 + 写盘一次
    // （A-C5）；落点非法（重叠）或未移动 → 回滚起点，不写盘。
    function commitWidgetDrag(inst) {
        if (!root.dragActive || String(inst && inst.widgetId || "") !== root.dragWidgetId)
            return;
        var start = root.dragStart;
        var target = Grid.snapPosition(start.cols, start.rows, inst.x, inst.y, root.cellSize,
            root.screenHeight, root.gridCols, root.gridRows);
        var movable = Grid.canPlace(root.gridState.grid, start.id, target.col, target.row,
            start.cols, start.rows, root.gridCols, root.gridRows);
        if (movable && (target.col !== start.col || target.row !== start.row)) {
            root.updateConfigPosition(start.id, target.col, target.row);
            root.animateWidgetTo(inst, Grid.xPxForCell(target.col, root.cellSize),
                Grid.yPxForCell(target.row, start.rows, root.cellSize, root.screenHeight));
            root.persistConfig();
        } else {
            root.animateWidgetTo(inst, start.x, start.y);
        }
        root.clearDrag();
    }

    // onCanceled 侧：完整回滚（恢复起点 + 清状态，不写盘）。
    function cancelWidgetDrag(inst) {
        if (!root.dragActive || String(inst && inst.widgetId || "") !== root.dragWidgetId)
            return;
        dragXAnim.stop();
        dragYAnim.stop();
        inst.x = root.dragStart.x;
        inst.y = root.dragStart.y;
        root.clearDrag();
    }

    function clearDrag() {
        root.dragActive = false;
        root.dragWidgetId = "";
        root.dragStart = null;
    }

    // 更新配置中某条目的网格位置（实例位置由 commit 的落位动画负责，
    // 不重建对象树）。
    function updateConfigPosition(id, col, row) {
        var sid = String(id || "");
        var next = [];
        for (var i = 0; i < root.widgetConfigs.length; i++) {
            var e = root.widgetConfigs[i];
            if (String(e.id || "") === sid) {
                next.push({ "id": e.id, "size": e.size, "col": Math.round(col), "row": Math.round(row) });
            } else {
                next.push(e);
            }
        }
        root.widgetConfigs = next;
    }

    // 落位/回滚动画（P-1：禁弹簧；时长/缓动取自 Motion.js，P-3）。
    function animateWidgetTo(inst, tx, ty) {
        if (!inst)
            return;
        // 与 create/settle 同一钳制：目标像素不得为负（短屏顶部行）。
        tx = Math.max(0, Number(tx) || 0);
        ty = Math.max(0, Number(ty) || 0);
        dragXAnim.target = inst;
        dragXAnim.to = tx;
        dragYAnim.target = inst;
        dragYAnim.to = ty;
        dragXAnim.start();
        dragYAnim.start();
    }

    // ---- mask 与弹层联动 ----
    onPopupActiveChanged: root.updateMask()

    Component.onCompleted: {
        // 共享 FileView 可能已在宿主创建前完成加载：已加载则直接切片
        // （onConfigLoadedChanged 只覆盖创建后到达的置真）。
        if (root.configLoaded)
            root.loadConfig();
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

    // 拖动落位动画（A6）：编辑模式提交/回滚时把实例平滑吸附到网格。
    // 声明为独立 NumberAnimation（不挂 Behavior：拖动中的直接 x/y 更新
    // 不能被自动动画化）；时长/缓动来自 Motion.js（P-3），禁弹簧（P-1）。
    NumberAnimation {
        id: dragXAnim
        property: "x"
        duration: Motion.elementMove(null)
        easing.type: Motion.standardDecel
    }
    NumberAnimation {
        id: dragYAnim
        property: "y"
        duration: Motion.elementMove(null)
        easing.type: Motion.standardDecel
    }

    // 编辑模式空白点击退出（A6）：全屏 MouseArea，位于小部件层之下
    // （小部件手势层在上，优先吃自身事件）。弹层打开时 mask 已置空，
    // 本层同时停用（双重保险）。
    MouseArea {
        id: editExitCatcher
        anchors.fill: parent
        enabled: root.editMode && !root.popupActive
        onClicked: root.exitEditMode()
    }

    // 编辑模式「完成」按钮（A6）：退出编辑模式的显式入口。位于小部件
    // 层之上；整层 mask 在编辑态为全屏，本按钮始终可点（无窗口覆盖时）。
    Item {
        id: editDoneButton
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 48
        width: 76
        height: 32
        visible: root.editMode
        z: 100

        Rectangle {
            anchors.fill: parent
            radius: 16
            color: "#e6ffffff"
            border.color: "#33000000"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "完成"
                color: "#000000"
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.exitEditMode()
        }
    }

    // ---- 小部件层（mask 覆盖区域）----
    Item {
        id: widgetLayer
        anchors.fill: parent
    }
}
