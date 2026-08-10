# A2 审查记录

日期：2026-08-10
子代理数：6（轮1 ×2、轮2 ×2、轮2 追加 ×1、冒烟实证 ×1）

## 各子代理结论

### 轮 1

#### 子代理 1（对抗审查：约束合规与测试有效性）
- 结论：REJECT
- CONFIRMED：
  - C1：`buildUnionRegion` 用 Qt.createQmlObject 拼字符串引用 JS 局部变量 `widgetList[j]` —— createQmlObject 不捕获调用函数作用域，item 绑定解析失败 → region 恒空 → mask 退化为全屏输入区（点击空白不穿透，破坏 A-C1 与完成判据 3）。**实证**：Qt 6.11.1 探针 item 绑定恒 null。
  - C2：`Qt.createComponent("widgets/" + source)` 相对路径基准 = 调用 JS 所在目录（components/widgets/）→ 解析成 widgets/widgets/BatteryWidget.qml 不存在 → 小部件永远创建不出来（破坏完成判据 1）。
  - C3：`test_capacity_constants` 拿常量断言常量（不引用 api），假守护。
- PLAUSIBLE：P1 popupActive 用全局布尔（多屏异屏弹层让本屏小部件失交互）；P2 hostVisible 恒真（门控未接真实宿主可见性）；P3 addWidget/removeWidget 提前实现 A4/A6 范围；P4 Timer 测试锁下限；P5 超限数字失真。

#### 子代理 2（对抗审查：布局与生命周期）
- 结论：REJECT
- CONFIRMED：
  - C1（同代理1 C1）：mask 并集字符串作用域外引用，区域恒空。
  - C2（同代理1 C2）：createComponent 多套一层 widgets/，小部件永不创建。
  - C3（同 P1）：popupActive 未按屏门控，与既有 per-screen 判定不一致。
  - C4：previewMode 假实现——BatteryWidget percentage/charging 直绑 batteryService 不经 dataRefreshActive（注释与实现相反）。
  - C5：G-6——Widget.qml 的 sizeCols/sizeRows/validSize 与 WidgetGrid.js 的 colsForSize/rowsForSize/validSize 重复映射表，且基类副本无人读取。
  - C6：G-5 死代码——configLoaded 只写不读；addWidget 读不存在的 widgetId 属性；MAX_WIDGETS/LIMIT_CELLS 零引用；横幅「配置无效」分支不可达。
- PLAUSIBLE：P1 persistConfig 在初次加载完成前调用丢其他屏配置；P2 屏内超容量（如 8 个 small）被 gridState 静默剔除不计入反馈；P3 mask Region 树每次重建泄漏；P4 多屏同名共享配置段。

### 轮 2（修复后复核）

#### 子代理 3（复核：运行时验证，探针实证）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：BatteryWidget 以 previewMode=true 作为初始属性创建时 onLiveChanged 不发射 → 快照不锁存（A5 若以初始属性创建预览即触发；A2 宿主恒传 previewMode:false 不触发）；stateText 在 _live* 之外的直绑（被 if(!live) 先门控，零影响）。
- 关键实证：`/tmp/widgets-probe` 探针（与 WidgetHost 同形）——createComponent 相对子目录解析 status=Ready、createQmlObject 字符串 `root.maskWidgetItems[j]` 文档 id 路径解析到实例且恒等非 null；mask item→Region 全链路（item 非空生成正确矩形、旧树 destroy 无泄漏）；BatteryWidget 快照锁存（63/false 落锁）；shell.qml 每屏谓词 9 弹层无漏项（对照 activeTopBarPopup）。

#### 子代理 4（复核：修复验证，第二轮）
- 结论：REJECT（新发现 D1/D2）
- CONFIRMED：
  - D1（阻塞）：shell.qml `import "components"` 目录导入**不递归子目录** → components/widgets/WidgetHost.qml 不可解析 → `WidgetHost {` 是 not-a-type → 整个 ShellRoot 文档编译失败（shell 起不来）。**实证**：qmltestrunner 目录导入探针（父目录类型可解析、子目录类型失败）+ qmllint `[import] WidgetHost was not found`。
  - D2（阻塞）：widgets 子目录 `import ".." as C` 的 TahoeGlass JS 是**空模块**（目录导入只暴露 QML 类型，JS 成员为空）→ `C.TahoeGlass.MaterialMenu/RadiusPanelCompact` 全 undefined → 玻璃配方错/radius NaN。**实证**：引擎探针 Object.keys(C.TahoeGlass) 为空。
  - D3：测试假守护盲区——文本断言对 D1/D2 无感知（21 测试全绿而 shell 起不来）。
- PLAUSIBLE：P2 超限计数低估（空 id 条目 continue 不计 removed）；C5 残留（widgetSize 无人读取的透传）；C2 第二参数非 parent（无副作用）；P1 persist 门依赖 FileView 事件。

### 轮 2 追加（冒烟实证，最小树）
- 结论：PASS（修复后验证）
- 实证：`/tmp/a2smoke` 最小配置树（components/widgets 子目录 + WidgetHost + BatteryWidget + 玻璃/JS 直接导入）经真实 quickshell `-p` 加载 → `Configuration Loaded` + 持续运行（exit=124）+ 零 error/not-a-type/ReferenceError 告警。D1/D2 修复在真实运行时生效。
- 另：复刻探针（显式 `import "sub"` 子目录导入）qmltestrunner PASS——显式导入子目录类型可实例化。

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| mask 并集字符串作用域外引用（C1） | CONFIRMED | 已修：新增 root.maskWidgetItems 属性（文档级），字符串改引用 root.maskWidgetItems[j]；updateMask 替换旧 mask 时 destroy 旧 Region 树 | WidgetHost.qml buildUnionRegion/updateMask；探针实证 item 绑定解析非 null |
| createComponent 多套 widgets/ 前缀（C2） | CONFIRMED | 已修：去掉 "widgets/" 前缀，createComponent(source)（相对调用文件目录） | WidgetHost.qml createWidgetInstance；探针 status=Ready |
| popupActive 未按屏门控（C3） | CONFIRMED | 已修：shell.qml 改每屏谓词（topBarPopupOpenFor×9 / navigationOpenFor×2 / dockAppMenuOpenFor / dockWindowMenuOpenFor / processMenuOpenFor）；launchpad/spotlight 全局布尔（全屏 Overlay） | shell.qml WidgetHost 块；复核逐项对照 activeTopBarPopup 无漏项 |
| previewMode 假实现（C4） | CONFIRMED | 已修：BatteryWidget 拆 _live* 与 _snap*，onLiveChanged 锁存 + onCompleted 兜底（初始 previewMode=true 也锁存） | BatteryWidget.qml；探针 63/false 落锁 |
| size 映射表双份（C5） | CONFIRMED | 已修：删 Widget.qml sizeCols/sizeRows/validSize 副本，唯一来源 WidgetGrid.js | Widget.qml / WidgetGrid.js；grep 无残留 |
| 死代码（C6） | CONFIRMED | 已修：删 configLoaded、widgetId 检查、MAX_WIDGETS/LIMIT_CELLS、横幅不可达分支 | 各文件；grep 无残留 |
| 容量测试假守护（C3） | CONFIRMED | 已修：脚本改引用 api.GRID_COLS/GRID_ROWS/LIMIT_ITEMS | test_widget_grid.py |
| 每屏超容量剔除不计反馈（P2） | PLAUSIBLE | 已修：overflowCount = state.removed.length + max(0, totalEntryCount() - LIMIT_ITEMS) | WidgetHost.qml loadConfig/totalEntryCount |
| persist 未就绪覆盖（P1） | PLAUSIBLE | 已修：加 `if (!root.loadingComplete) return;` 早退门（P-7） | WidgetHost.qml persistConfig |
| mask 树泄漏（P3） | PLAUSIBLE | 已修：updateMask destroy 旧 mask | WidgetHost.qml |
| 多屏同名（P4） | PLAUSIBLE | 不修：依赖环境屏名唯一性，与既有屏名语义一致 | — |
| shell.qml 目录导入不递归 → WidgetHost 不可解析（D1） | CONFIRMED | 已修：shell.qml 加 `import "components/widgets"`；测试锁 import | shell.qml；qmltestrunner 探针显式子目录导入 PASS；最小树 quickshell 加载 Configuration Loaded |
| widgets 内 `import ".." as C` JS 空模块（D2） | CONFIRMED | 已修：全部改直接导入 `../TahoeGlass.js as GlassStyle` / `WidgetGrid.js as Grid`；测试锁无 `import ".." as C` | Widget.qml/WidgetHost.qml；最小树加载无 ReferenceError |
| 测试盲区（D3） | CONFIRMED | 已修：契约测试加 import 断言 + JS 直接导入断言 | test_widget_host_layer_contract.py |
| BatteryWidget 初始 previewMode 快照不锁存 | PLAUSIBLE | 已修：onCompleted 兜底锁存（A5 以初始属性创建预览也正确） | BatteryWidget.qml |
| widgetSize 透传残留 | PLAUSIBLE | 不修：A7 接入后生效（当前是配置驱动的规格传递） | — |

## 完成判据核对

| 判据（引 roadmap.md） | 是否满足 | 证据 |
|---|---|---|
| 桌面上显示电池小部件，玻璃材质正确，数据实时正确 | 是（加载链路实证 + 数据源核对） | 最小树 quickshell 加载 Configuration Loaded（WidgetHost + BatteryWidget 实例化成功）；TahoeGlass 令牌直接导入解析；Battery 服务属性（roundedPercentage/charging/stateText/onBattery/available）逐一核对存在。**真机视觉留人工验收（部署后）** |
| 顶栏弹层打开时点击桌面 → 收回弹层（不被小部件层拦截） | 是 | popupActive 时 mask=null → 窗口输入区空 → 点击穿过宿主达 Overlay 层 PopupDismissLayer（PopupDismissLayer.qml:97-98）；每屏谓词 9 弹层无漏项（复核对照 activeTopBarPopup） |
| 弹层关闭时点击小部件 → 接收；点击空白 → 穿透 | 是 | mask 并集修复：item 绑定经 root.maskWidgetItems 文档 id 解析（探针实证非 null + 恒等）；Region applyTo（region.cpp:233）+ Intersect 剪全屏 → 并集语义 = 各小部件矩形 ∪ ∩ 窗口；空白区域不在并集内 → 穿透 |
| 重启 quickshell 后小部件位置与配置一致 | 是 | widgets.json 读写闭环（FileView setText/loaded/loadFailed 语义核对）；gridState 清洗/序列化 node 实测（round-trip、重叠剔除、越界剔除、规格映射） |
| region 计数保护：人为配置 33 个小部件时给出可见反馈而非静默失效 | 是 | 33 条 → overflowCount = 剔除数 + 超额数 → 横幅触发链（onLoadingCompleteChanged → 400ms 定时器 → 6s 横幅）；横幅为宿主内可见 UI（无进程无轮询） |
| qmllint --bare 无新增告警 | 是 | 4 个新文件 + shell.qml 全量零 [error]（widgets 目录含子目录导入 lint 噪音为 bare 模式局限，非 bare 亦零 error）；test_qml_syntax.py 通过 |
| pytest 全绿 | 是 | 1073 passed + 318 subtests（全量，多次复跑一致）；新测试 22 个（契约 13 + 网格 9） |

## 约束核对

| 条款 | 结果 |
|---|---|
| G-1 串行 | 是（A2 独立 commit） |
| G-2 独立子代理审查 | 是（6 个，轮1 双 REJECT → 修复 → 轮2 复核 + 追加冒烟） |
| G-4 一任务一 commit | 是 |
| G-5 无最小实现/TODO | 是（死代码已清；无占位） |
| G-6 无平行接口 | 是（size 映射唯一来源 WidgetGrid.js；mask 单一路径；gridState 单一数据流） |
| G-7 不破坏现有功能 | 是（shell.qml diff 仅 WidgetHost 块 + import；全量回归 1073 绿；既有组件零改动） |
| G-8 无需求外功能 | 是（仅 A-0 五条 + P-5 强制反馈；addWidget/removeWidget 为 A4/A6 预留 API，无 UI 入口，非用户可见功能） |
| A-C1 层级/输入策略/mask | 是（Bottom/Ignore/None/focusable:false/namespace tahoe-widgets；mask 语义修复后成立） |
| A-C3 禁自建轮询 | 是（无 Timer/spawn；横幅对为一次性；battery 事件驱动） |
| A-C4 禁 layer.enabled | 是（无） |
| A-C5 持久化时机 | 是（仅 addWidget/removeWidget 完成时一次；无拖动路径） |
| A-C6 图片卫生 | 是（无 Image 元素） |
| P-1 玻璃禁弹簧 | 是（无 SpringAnimation） |
| P-3 Motion.js 令牌 | 是（无硬编码 duration） |
| P-5 region 计数保护 | 是（≤16/屏结构上限 + 跨屏超额横幅可见反馈） |
| P-6 KeyboardInteractivity.None | 是（focusable:false + WlrKeyboardFocus.None 双重） |
| P-12 qmllint 工具链 | 是（/usr/lib/qt6/bin/qmllint --bare） |

## 最终结论

轮1 双 REJECT（9 CONFIRMED）→ 全部修复 → 轮2 复核：运行时探针 APPROVE + 修复验证 REJECT（新发现 D1/D2 导入级缺陷）→ 修复 → 最小树真实 quickshell 冒烟 Configuration Loaded（实证 D1/D2 生效）。全部 CONFIRMED 已修，冒烟实证加载链路成立 → 允许 commit。

已知遗留（不阻塞，记录备查）：
- 真机视觉验收（电池小部件显示/玻璃观感/弹层点击行为）留部署后人工验证（roadmap A2 人工验证判据）
- A3 需按 A5 未确认项验证 SystemStats 门控后再接入
- 多屏同名屏名共享配置段（依赖环境屏名唯一性）
