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
    // A8 深浅外观（shell.darkMode 注入）：传给每个小部件实例与「完成」
    // 按钮，玻璃/文字/图标颜色随外观自适应（macOS 行为）。
    property bool darkMode: false

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
    // 小部件视觉缝隙（px，单一来源 WidgetGrid.GAP_PX）：网格占用仍按整格，
    // 实例像素矩形四周内缩 gap/2 —— 相邻小部件之间留完整 gap，屏幕边缘
    // 留半 gap（部署反馈：之前整格铺放，相邻小部件贴死无缝隙）。
    readonly property real widgetGap: Grid.GAP_PX
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
        "battery": { "source": "BatteryWidget.qml", "name": "电池", "sizes": ["small", "medium", "large"], "defaultSize": "small" },
        "weather": { "source": "WeatherWidget.qml", "name": "天气", "sizes": ["small", "medium", "large"], "defaultSize": "medium" },
        "calendar": { "source": "CalendarWidget.qml", "name": "日历", "sizes": ["small", "medium", "large"], "defaultSize": "medium" },
        "system-monitor": { "source": "SystemMonitorWidget.qml", "name": "系统监控", "sizes": ["small", "medium", "large"], "defaultSize": "small" }
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
        if (root.resizeActive) {
            // resize 中退出（完成按钮/空白点击/宿主隐藏）：完整回滚——
            // 恢复起点几何与档位 + 清宿主 resize 状态，不写盘（A-C5）。
            var rinst = root.widgetInstances[root.resizeWidgetId];
            if (rinst)
                root.cancelWidgetResize(rinst);
            else
                root.clearResize();
        }
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
        // 退出编辑模式：清掉可能仍在显示的 resize 冲突横幅（避免编辑态
        // 外残留临时反馈，对抗审查 P2）。
        root.resizeRejectedVisible = false;
        resizeRejectHide.stop();
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
            "x": Math.max(0, Grid.xPxForCell(entry.gridX, root.cellSize, root.widgetGap)),
            "y": Math.max(0, Grid.yPxForCell(entry.gridY, entry.rows, root.cellSize, root.screenHeight, root.widgetGap)),
            "width": Math.min(root.widgetMaxWidth, Math.max(1, Math.round(entry.cols * root.cellSize - root.widgetGap))),
            "height": Math.min(root.widgetMaxHeight, Math.max(1, Math.round(entry.rows * root.cellSize - root.widgetGap))),
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
        // darkMode 同样以绑定注入：深浅外观切换时全部实例实时跟随
        // （A8 自适应玻璃，一次性初值会在切换时卡在旧值）。
        obj.darkMode = Qt.binding(function() { return root.darkMode; });
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
        root.clearResize();
        dragXAnim.stop();
        dragYAnim.stop();
        resizeXAnim.stop();
        resizeYAnim.stop();
        resizeWAnim.stop();
        resizeHAnim.stop();
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
            // 与 createWidgetInstance 同一钳制（短屏顶部行像素可为负）与
            // 同一缝隙内缩（gap 参数一致，避免回滚后位置偏移）。
            inst.x = Math.max(0, Grid.xPxForCell(entry.col, root.cellSize, root.widgetGap));
            inst.y = Math.max(0, Grid.yPxForCell(entry.row, Grid.rowsForSize(entry.size),
                root.cellSize, root.screenHeight, root.widgetGap));
        }
    }

    // onPressed 侧：记录起点与抓取偏移（不激活、不写盘）。
    function beginWidgetDrag(inst, localX, localY) {
        var id = String(inst && inst.widgetId || "");
        if (!id || root.dragActive || root.resizeActive || !root.editMode)
            return;
        // 先把上一提交/回滚动画补送到终点，再从 config 网格位快照
        // （实例此刻的 x/y 才是真实起点；避免动画中间帧污染快照）。
        root.settleWidgets();
        var entry = root.configEntryFor(id);
        if (!entry)
            return;
        var p = inst.mapToItem(widgetLayer, localX, localY);
        var startX = Math.max(0, Grid.xPxForCell(entry.col, root.cellSize, root.widgetGap));
        var startY = Math.max(0, Grid.yPxForCell(entry.row, Grid.rowsForSize(entry.size),
            root.cellSize, root.screenHeight, root.widgetGap));
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
        // 拖动钳制与静止位同一缝隙内缩（gap/2）：静止位四周距屏边
        // gap/2（见 createWidgetInstance），若按原始屏边钳制，拖到边缘
        // 松手会回弹 gap/2（审查观察）。右缘还要锚到网格右边界
        // gridCols*cellSize（屏宽不整除 cellSize 时留白区无合法落点，
        // 按屏边钳制会回弹最多一个 cell 宽，审查 C-1）。垂直下沿仍钳在
        // 顶栏保留区以下。
        var halfGap = root.widgetGap / 2;
        var minX = Math.max(0, halfGap);
        var maxX = Math.max(minX, root.gridCols * root.cellSize - inst.width - halfGap);
        var minY = Math.max(0, root.topReserved + halfGap);
        var maxY = Math.max(minY, root.screenHeight - inst.height - halfGap);
        inst.x = Math.max(minX, Math.min(maxX, p.x - root.dragStart.grabX));
        inst.y = Math.max(minY, Math.min(maxY, p.y - root.dragStart.grabY));
    }

    // onReleased 侧：网格吸附 → 合法则更新配置 + 落位动画 + 写盘一次
    // （A-C5）；落点非法（重叠）或未移动 → 回滚起点，不写盘。
    function commitWidgetDrag(inst) {
        if (!root.dragActive || String(inst && inst.widgetId || "") !== root.dragWidgetId)
            return;
        var start = root.dragStart;
        var target = Grid.snapPosition(start.cols, start.rows, inst.x, inst.y, root.cellSize,
            root.screenHeight, root.gridCols, root.gridRows, root.widgetGap);
        var movable = Grid.canPlace(root.gridState.grid, start.id, target.col, target.row,
            start.cols, start.rows, root.gridCols, root.gridRows);
        if (movable && (target.col !== start.col || target.row !== start.row)) {
            root.updateConfigEntry(start.id, target.col, target.row);
            root.animateWidgetTo(inst, Grid.xPxForCell(target.col, root.cellSize, root.widgetGap),
                Grid.yPxForCell(target.row, start.rows, root.cellSize, root.screenHeight, root.widgetGap));
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

    // ---- A7 边缘 resize（三档切换）----
    // 手柄在 Widget.qml（8 个 8px 命中区，编辑模式才启用）；本文件是
    // 档位/落点/持久化的唯一属主（G-6：WidgetGrid.js 的纯函数是档位与
    // 落点唯一来源）。拖动中不重建、不写盘（A-C5）；换档即时生效
    // （几何动画用 Motion.elementResize 令牌，禁弹簧 P-1），冲突
    // （canPlace 失败）拒绝换档并显示可见反馈（不静默失败）。
    property bool resizeActive: false
    property string resizeWidgetId: ""
    // {id, handleId, anchor, tier, size, col, row, cols, rows, x, y, width,
    //  height, pressX, pressY, currentTier, rejectedTier, switched} ——
    // 起点快照 + 当前显示档位。currentTier 只在「成功换档」时更新；
    // rejectedTier 记录最近一次被拒的目标档位（抑制同方向重复反馈，
    // 换档成功后清除）；switched 只在成功换档时置真。commit 仅在
    // switched 且净档位变化时写盘：被拒绝的操作与「放大又缩回起点」
    // 都不产生写盘（A-C5）。
    property var resizeStart: null

    function beginWidgetResize(inst, handleId, anchor, localX, localY) {
        var id = String(inst && inst.widgetId || "");
        if (!id || root.resizeActive || root.dragActive || !root.editMode)
            return;
        // 先在几何跳变前把指针映射到宿主坐标系（mapToItem 之后才
        // settle/停动画：若上一轮换档动画仍在飞，settle 落位会改变
        // 实例 x/y，先映射可保证 pressX/Y 不被落位跳变污染，对抗审查
        // P2）。
        var p = inst.mapToItem(widgetLayer, localX, localY);
        // 停掉上一轮可能仍在飞的换档动画，再补送落位动画到终点
        // （begin 快照必须取自稳定几何；与 rebuild 同款清理）。
        resizeXAnim.stop();
        resizeYAnim.stop();
        resizeWAnim.stop();
        resizeHAnim.stop();
        root.settleWidgets();
        var entry = root.configEntryFor(id);
        if (!entry)
            return;
        var cols = Grid.colsForSize(entry.size);
        var rows = Grid.rowsForSize(entry.size);
        root.resizeStart = {
            "id": id,
            "handleId": String(handleId || "right"),
            "anchor": String(anchor || "top-left"),
            "tier": Grid.tierIndex(entry.size),
            "size": String(entry.size || "small"),
            "col": Math.round(Number(entry.col) || 0),
            "row": Math.round(Number(entry.row) || 0),
            "cols": cols,
            "rows": rows,
            "x": Math.max(0, Grid.xPxForCell(entry.col, root.cellSize, root.widgetGap)),
            "y": Math.max(0, Grid.yPxForCell(entry.row, rows, root.cellSize, root.screenHeight, root.widgetGap)),
            "width": Math.max(1, Math.round(cols * root.cellSize - root.widgetGap)),
            "height": Math.max(1, Math.round(rows * root.cellSize - root.widgetGap)),
            "pressX": Number(p.x),
            "pressY": Number(p.y),
            "currentTier": Grid.tierIndex(entry.size),
            "rejectedTier": -1,
            "switched": false
        };
        root.resizeWidgetId = id;
        root.resizeActive = true;
    }

    // onPositionChanged 侧：按手柄轴向归一化外扩距离 → 目标档位 →
    // 锚点落点 → canPlace 校验。合法则换档（实例几何即时更新 +
    // elementResize 动画）；冲突则拒绝并给可见反馈。不重建、不写盘。
    function updateWidgetResize(inst, handleId, localX, localY) {
        if (!root.resizeActive || String(inst && inst.widgetId || "") !== root.resizeWidgetId)
            return;
        var start = root.resizeStart;
        var p = inst.mapToItem(widgetLayer, localX, localY);
        var dx = Number(p.x) - start.pressX;
        var dy = Number(p.y) - start.pressY;
        var delta = 0;
        switch (start.handleId) {
        case "left": delta = -dx; break;
        case "top": delta = -dy; break;
        case "bl": delta = dy - dx; break;
        case "tr": delta = dx - dy; break;
        case "tl": delta = -(dx + dy); break;
        case "br": delta = dx + dy; break;
        case "bottom": delta = dy; break;
        default: delta = dx; // right
        }
        var targetTier = Grid.resizeTargetTier(start.tier, delta, Motion.widgetResizeThresholdPx);
        // 当前已显示档位 / 已被拒档位都不再尝试（避免无操作重试与
        // 同方向重复反馈；指针越过阈值进入新档位后自然可再试）。
        if (targetTier === start.currentTier || targetTier === start.rejectedTier)
            return;
        var size = Grid.sizeForTier(targetTier);
        var cols = Grid.colsForSize(size);
        var rows = Grid.rowsForSize(size);
        var placement = Grid.resizePlacement(
            { "col": start.col, "row": start.row, "cols": start.cols, "rows": start.rows },
            size, start.anchor);
        if (!Grid.canPlace(root.gridState.grid, start.id, placement.col, placement.row,
                cols, rows, root.gridCols, root.gridRows)) {
            // 冲突（空间不足/越界）：拒绝换档 + 可见反馈；记下该档位避免
            // 同方向重复提示，指针反向回落后可再试。
            start.rejectedTier = targetTier;
            root.showResizeRejected();
            return;
        }
        // 合法：换档（几何动画禁弹簧，P-1；令牌 Motion.elementResize，P-3）。
        start.currentTier = targetTier;
        start.rejectedTier = -1;
        start.switched = true;
        start.size = size;
        start.col = placement.col;
        start.row = placement.row;
        start.cols = cols;
        start.rows = rows;
        if (inst.widgetSize !== size)
            inst.widgetSize = size;
        root.animateWidgetResizeTo(inst,
            Math.max(0, Grid.xPxForCell(placement.col, root.cellSize, root.widgetGap)),
            Math.max(0, Grid.yPxForCell(placement.row, rows, root.cellSize, root.screenHeight, root.widgetGap)),
            Math.max(1, Math.round(cols * root.cellSize - root.widgetGap)),
            Math.max(1, Math.round(rows * root.cellSize - root.widgetGap)));
    }

    // onReleased 侧：换过档 → 配置（档位+落点）+ 写盘一次（A-C5）；
    // 未换档 → 回滚起点，不写盘。
    function commitWidgetResize(inst) {
        if (!root.resizeActive || String(inst && inst.widgetId || "") !== root.resizeWidgetId)
            return;
        var start = root.resizeStart;
        // 只在实际发生净档位变化时写盘：被拒绝的操作不写；放大后又缩回
        // 起点档位（currentTier === tier）也不写（A-C5 对抗审查 C2）。
        if (start.switched && start.currentTier !== start.tier) {
            root.updateConfigEntry(start.id, start.col, start.row, start.size);
            root.persistConfig();
            // 把最后一次换档动画补送到终点（与拖动提交同一语义）。
            root.animateWidgetResizeTo(inst,
                Math.max(0, Grid.xPxForCell(start.col, root.cellSize, root.widgetGap)),
                Math.max(0, Grid.yPxForCell(start.row, start.rows, root.cellSize, root.screenHeight, root.widgetGap)),
                Math.max(1, Math.round(start.cols * root.cellSize - root.widgetGap)),
                Math.max(1, Math.round(start.rows * root.cellSize - root.widgetGap)));
        } else {
            root.animateWidgetResizeTo(inst, start.x, start.y, start.width, start.height);
        }
        root.clearResize();
    }

    // onCanceled 侧：完整回滚（恢复起点几何与档位 + 清状态，不写盘）。
    function cancelWidgetResize(inst) {
        if (!root.resizeActive || String(inst && inst.widgetId || "") !== root.resizeWidgetId)
            return;
        var start = root.resizeStart;
        resizeXAnim.stop();
        resizeYAnim.stop();
        resizeWAnim.stop();
        resizeHAnim.stop();
        inst.x = start.x;
        inst.y = start.y;
        inst.width = start.width;
        inst.height = start.height;
        inst.widgetSize = start.size;
        root.clearResize();
    }

    function clearResize() {
        root.resizeActive = false;
        root.resizeWidgetId = "";
        root.resizeStart = null;
    }

    // 更新配置中某条目的网格位置/档位（拖动与 resize 共用的单一路径，
    // G-6：不得再有第二份配置改写函数）。size 为空 → 保持既有档位。
    // 实例几何由 commit 的落位/换档动画负责，不重建对象树。
    function updateConfigEntry(id, col, row, size) {
        var sid = String(id || "");
        var next = [];
        for (var i = 0; i < root.widgetConfigs.length; i++) {
            var e = root.widgetConfigs[i];
            if (String(e.id || "") === sid) {
                next.push({
                    "id": e.id,
                    "size": size && String(size).length > 0 ? String(size) : String(e.size || "small"),
                    "col": Math.round(col),
                    "row": Math.round(row)
                });
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

    // 换档/回滚动画（A7：P-1 禁弹簧；时长/缓动取自 Motion.js，P-3）。
    // 与 create/settle 同一钳制：目标像素不得为负（短屏顶部行）。
    function animateWidgetResizeTo(inst, tx, ty, tw, th) {
        if (!inst)
            return;
        tx = Math.max(0, Number(tx) || 0);
        ty = Math.max(0, Number(ty) || 0);
        tw = Math.max(1, Number(tw) || 1);
        th = Math.max(1, Number(th) || 1);
        resizeXAnim.target = inst;
        resizeXAnim.to = tx;
        resizeYAnim.target = inst;
        resizeYAnim.to = ty;
        resizeWAnim.target = inst;
        resizeWAnim.to = tw;
        resizeHAnim.target = inst;
        resizeHAnim.to = th;
        resizeXAnim.start();
        resizeYAnim.start();
        resizeWAnim.start();
        resizeHAnim.start();
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

    // A7 resize 冲突反馈状态（可见横幅；单发 Timer，无常驻轮询 A-C3）。
    property bool resizeRejectedVisible: false
    function showResizeRejected() {
        root.resizeRejectedVisible = true;
        resizeRejectHide.restart();
    }
    Timer {
        id: resizeRejectHide
        interval: 1200
        repeat: false
        onTriggered: root.resizeRejectedVisible = false
    }

    // 横幅渲染层（mask 之上：遮罩不挡横幅，且 mask 无 region 时横幅仍在）。
    // z:50 高于小部件层（widgetLayer 声明在后会盖住横幅，对抗审查 P1）；
    // 低于「完成」按钮 z:100。
    Item {
        id: bannerLayer
        anchors.fill: parent
        z: 50
        visible: root.overflowBannerVisible || root.resizeRejectedVisible

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

        // A7 resize 冲突反馈：目标档位放不下（空间不足/越界）时拒绝换档，
        // 显示可见横幅（不静默失败），单发 Timer 自动消失。topMargin 96
        // 避开顶部居中的「完成」按钮（y≈48-80），不互相遮挡。
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 96
            width: Math.min(360, root.screenWidth - 48)
            height: 44
            radius: GlassStyle.RadiusPanelCompact
            color: "#cc1d1d1f"
            visible: root.resizeRejectedVisible

            Text {
                anchors.centerIn: parent
                text: "无法调整大小：空间不足"
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

    // 换档/回滚动画（A7）：编辑模式 resize 提交/回滚时平滑切换几何。
    // 独立 NumberAnimation（不挂 Behavior：拖动中的直接 x/y/width/height
    // 更新不能被自动动画化）；时长/缓动来自 Motion.js（P-3），禁弹簧（P-1）。
    NumberAnimation {
        id: resizeXAnim
        property: "x"
        duration: Motion.elementResize(null)
        easing.type: Motion.standardDecel
    }
    NumberAnimation {
        id: resizeYAnim
        property: "y"
        duration: Motion.elementResize(null)
        easing.type: Motion.standardDecel
    }
    NumberAnimation {
        id: resizeWAnim
        property: "width"
        duration: Motion.elementResize(null)
        easing.type: Motion.standardDecel
    }
    NumberAnimation {
        id: resizeHAnim
        property: "height"
        duration: Motion.elementResize(null)
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
            radius: height / 2
            color: root.darkMode ? "#e6ffffff" : "#ffffff"
            border.color: root.darkMode ? "#33000000" : "#1a000000"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "完成"
                color: root.darkMode ? "#000000" : "#1d1d1f"
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
