# A4 审查记录

日期：2026-08-11
子代理数：2（Zeno APPROVE；Huygens REJECT 2×CONFIRMED → 全部修复 → 复跑全量 + 真机复验）

## 各子代理结论

### 子代理 1（Zeno：约束合规 / 回归 / 边界）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：
  - P1：「已添加」标记在宿主重建（`widgetInstances` 先整体重赋再 mutation）期间可能快照为空，
    靠「成功即关侧栏」+ 重开自愈掩盖；低危时序。
  - P2：`addWidget` 在 `createWidgetInstance` 失败时仍返回 true 并关侧栏（A2 既有行为；
    当前四个 catalog source 均有效，现网不可达）。
  - P3：库页 `entries` 对 `widgetCatalog` 注入为 null 无防御。
  - P4：`sizeLabel` 对未知尺寸兜底为「小」（当前 catalog 无未知尺寸）。
  - P5：`useSpring` 属性声明未消费（无弹簧动画，无害）。

### 子代理 2（Huygens：操作序列 / 时序竞态 / QML 作用域 / 多屏）
- 结论：REJECT
- CONFIRMED：
  - C1：`addWidget` 无 `loadingComplete` 门 —— 启动竞态下「添加成功但未持久化」：
    persistConfig 的 P-7 早退只挡写盘不挡重建；FileView 异步加载完成前点击库条目 →
    空配置上加实例 → 返回 true 关侧栏 → loadConfig 到达后覆盖重建销毁刚加的小部件，
    无任何反馈。
  - C2：多屏顺序添加丢配置 —— 每屏一个 WidgetHost 各自持有 FileView 缓存同一
    widgets.json 的启动时旧文本；A 屏 persist 写盘后，B 屏 persist 以陈旧缓存为基底
    整文件覆盖 → A 屏新增段从文件丢失（重启后消失）。A4 是 persistConfig 的第一个调用方。
- PLAUSIBLE：
  - P1：同 Zeno P1（present 快照为空）。
  - P2：失败横幅文案单一，「桌面已满」覆盖三种失败原因。
  - P3：第三 tab thumb 相对 label 有 ~2.7px 左偏（继承旧二分同款公式，非 A4 回归）。
  - P4：G-8 边界（「已添加」标记是否越界，交由主代理裁量）。

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| C1 启动竞态假成功 | CONFIRMED | 已修：`addWidget` 顶部加 `if (!root.loadingComplete) { warn; return false; }`；横幅文案改中性「无法添加小部件」（覆盖未就绪/无空位/未知条目，不误导） | WidgetHost.qml addWidget；LeftSidebarWidgetLibrary.qml 横幅；结构测试 `test_config_persistence_single_owner_and_add_gate` |
| C2 多屏顺序添加丢配置 | CONFIRMED | 已修：widgets.json 读写收敛为 shell 级**单一所有者** —— 共享 FileView（`widgetConfigFile`）+ 内存镜像 `widgetConfigText`（同步反映磁盘内容 + 已排队未落盘写）；宿主只读注入 FileView 切片自己的屏段，写经 `persistConfigRequested` 信号提交 shell 合并后 `setText` 一次；宿主删除本地 FileView（G-6 单一路径） | shell.qml FileView/镜像/onPersistConfigRequested；WidgetHost.qml configFile/persistConfigRequested；`onConfigLoadedChanged` + onCompleted 兜底共享 FileView 先于宿主加载完成（含文件不存在） |
| P1 present 快照过期 | PLAUSIBLE | 记录为已知遗留：当前唯一 rebuild 路径（添加成功）随即关侧栏销毁库页，无可见陈旧帧；重开侧栏由 `Component.onCompleted` 重新快照自愈。A6 接入 removeWidget 若需「侧栏开着时刷新」，应在该任务补刷新机制 | LeftSidebarWidgetLibrary.qml refreshPresent/onCompleted |
| P2 实例化失败误报成功 | PLAUSIBLE | 记录为已知遗留：A2 既有行为（createWidgetInstance 失败仅 console.warn）；当前 catalog 四个 source 均存在可实例化，现网不可达；真机复验四件均正常创建 | WidgetHost.qml createWidgetInstance/addWidget |
| P3 entries null 防御 | PLAUSIBLE | 已修：`Object.keys(root.widgetCatalog || {})` | LeftSidebarWidgetLibrary.qml entries；结构测试断言 |
| P4 未知尺寸兜底「小」 | PLAUSIBLE | 记录为已知遗留：当前 catalog sizes 全为合法档位（small/medium），A7 引入新档位时由该任务扩展 sizeLabel | LeftSidebarWidgetLibrary.qml sizeLabel |
| Huygens P3 thumb 左偏 ~2.7px | PLAUSIBLE | 记录为已知遗留：继承 164f8ae 二分版同款公式（`(parent.width-4)/N`），非 A4 回归；纯视觉可忽略 | LeftSidebar.qml segmentThumb/targetXFor |
| Huygens P4 「已添加」是否越界 | PLAUSIBLE | 裁量为范围内：宿主网格唯一 id（gridStateFromConfig 拒绝重复），不加标记则点击已存在条目会误报「桌面已满」——该标记是完成判据「不静默失败/诚实反馈」的必要组成，非商店类需求外功能 | WidgetGrid.js 重复剔除；LeftSidebarWidgetLibrary.qml 已添加/enabled:!present |

## 完成判据核对

| 判据（引 roadmap.md A4） | 是否满足 | 证据 |
|---|---|---|
| 三个 tab 均可切换，thumb 动画正确对齐三分位置 | 是 | 真机（部署后）实测：libSetTab 驱动 + 探针读 `thumbX`：system=2、weather=131.33、widgets=260.67（=2+width、2+2×width，width=(parent.width-4)/3）；截图像素核验白色 thumb 分别位于左/中/右三分（x 21-179 / 183-341 / 345-503 物理 px） |
| 回归：「系统」「天气」两 tab 行为、布局、动画与改造前一致 | 是 | git diff 仅触碰 segmentBar 三处几何/文案 + 新增库页；LeftSidebarSystem/Weather 两文件未改，绑定逐字未动；真机截图 system/weather 内容正常；全量 1105 pytest 绿 |
| 点击列表项 → 侧栏关闭 → 小部件出现在桌面空位 | 是 | 真机：清空配置 → 库 tab → 驱动 `addWidgetRequested`（MouseArea 点击 → addRequested → addWidgetRequested 的精确信号链）→ `widgetHost.addWidget` 成功 → 侧栏关闭（open=false）→ 小部件渲染（截图白字像素核验）→ widgets.json 落盘（共享所有者，~2s 异步写）→ 重启后配置一致 |
| 桌面无空位时给出可见反馈，不静默失败 | 是 | 真机：4 件占满网格后添加失败 → 侧栏保持打开 + 粉色横幅 + 红字「无法添加小部件」渲染（截图像素核验）；「已添加」条目在库页标记并禁用（截图：weather 卡右侧「已添加」窄文本；结构测试锁 `enabled: !present`） |
| pytest 全绿 | 是 | 1105 passed + 318 subtests（多次复跑一致）；新增 `tests/test_left_sidebar_library_tab.py`（7 项，含 C1/C2 修复守卫） |

## 约束核对

- G-6：widgetCatalog 唯一（WidgetHost.qml）；widgets.json 读写单一所有者（shell 共享 FileView + 镜像，宿主不再持有 FileView）；无第二套注册表/状态机 —— 通过（结构测试锁定）。
- G-5：无 TODO/空实现/假数据；库列表尺寸来自 catalog；失败横幅真实可达 —— 通过。
- G-7/A-C7：系统/天气两 tab 绑定逐字未动；打开/关闭、cardsEnter、LazyLoader、currentTabChangeRequested 原样 —— 通过。
- G-8：「已添加」标记与中性失败横幅裁量为诚实反馈（防误报「桌面已满」），非需求外功能；未添加商店/同步/插件等 —— 通过。
- A-C3：库页唯一 Timer 为单发 4000ms 反馈横幅（repeat:false，仅失败时 restart），无轮询/无 spawn —— 通过（结构测试锁定）。
- P-3：新文件无硬编码 duration 字面量，动画全部 Motion.js 令牌 —— 通过（结构测试锁定）。
- A-C1/P-5/P-6：小部件层输入策略、region 计数保护未触碰 —— 通过。

## 真机验证记录（部署后）

- 部署：`cp -r tahoe-shell/* ~/.config/quickshell/tahoe/` + 精确 PID 重启（P-10/P-11/P-12 遵守；无 pkill 宽匹配）。
- 干净部署加载：`Configuration Loaded`，无 [error]/TypeError/ReferenceError。
- 三 tab thumb 三分对齐、库页 4 条目、添加成功链路、失败横幅、「已添加」标记、4 件满桌面、重启后配置一致 —— 全部实测通过（截图存 /tmp/a4shots/：10-system、11-weather、12-widgets、20-present、21-calendar、22-full、24-banner-neutral、25-final）。
- 点击交互经临时 IPC 探针驱动**生产信号链**（leftSidebar.addWidgetRequested → shell 处理器 → widgetHost.addWidget），MouseArea 点击 → addRequested 为 QML 信号直连，由结构测试锁定；探针仅存在于部署副本，最终部署已还原为仓库版本并复验加载。

## 最终结论

Huygens 2×CONFIRMED（C1 启动竞态、C2 多屏丢配置）已全部修复并复验；Zeno 无 CONFIRMED。全部 CONFIRMED 已修 → 允许 commit。
