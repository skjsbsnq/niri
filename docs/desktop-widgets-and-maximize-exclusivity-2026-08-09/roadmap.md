# 改进路线图（ROADMAP）

日期：2026-08-09
配套文件：`research-report.md`（事实依据）、`constraints.md`（硬约束）、
`execution-plan.md`（执行与验收）

**任务顺序即执行顺序：C1 → B1 → B2 → B3 → A1 → A2 → A3 → A4 → A5 → A6 → A7。
严格串行，不得跳序、不得并行。**

任务粒度已按「一个完整可验收的功能单元」划分。
**不得再拆分，不得合并**（见 `constraints.md` G-4）。

---

## 全局阶段划分

| 阶段 | 任务 | 目标 |
|---|---|---|
| **C：清理既有文档遗留缺陷** | C1 | 修掉 postmortem §6 中已核实成立的两个缺陷 + 更新过时记录 |
| **B：修复最大化独占渲染缺陷** | B1 – B3 | 消除三个窗口遮挡现象，为小部件铺平地基 |
| **A：桌面小部件系统** | A1 – A7 | 实现用户定义的五条需求 |

**为何 C 先于 B/A**：C 中两项均为小范围零依赖的确定性缺陷。
其中 C2（异步双门守护恒假）尤其需要先修 —— 它是 `constraints.md` P-7
的残留缺口，而 A 项涉及小部件配置文件的异步读写，
同类模式若沿用错误先例会扩散。（详见 `research-report.md` C-1 ~ C-3）

**为何 B 先于 A**：桌面小部件位于 `WlrLayer.Bottom`。当最大化独占生效、
该列窗口被 `.take(1)` 过滤时，小部件会整片暴露；独占解除时又被瞬间盖住。
B 不修则小部件上线即出现桌面闪烁，且难以区分是小部件自身缺陷还是既有缺陷。
（详见 `research-report.md` B-4）

---

# 阶段 C：清理既有文档遗留缺陷

## C1 — 修复壁纸预启动路径的死代码与失效守护

**问题引用**：`research-report.md` C-1、C-2、C-3

**目标**：修掉 postmortem §6 中已核实成立的两个缺陷，并更新该文档的过时记录。

**为何合为一个任务**：三项同属 `Wallpaper.qml` 预启动路径 / 同一份 postmortem，
改动范围小且互相关联，符合「一个完整可验收单元」的粒度
（不得再拆成三个 commit，见 G-4）。

**范围**：

1. **C-1 死代码**：`tahoe-shell/components/Wallpaper.qml:1417-1427`
   的 `prestartedWallpaperReadyTimer` 全文件仅有 `:845` 一处 `stop()`，
   从无 `start()`/`restart()`，`onTriggered` 永不执行。
   **须判定**：该 Timer 是「本应被启动但漏了」还是「已被其他机制取代」。
   - 若为漏启动 → 补上正确的启动点，使其语义生效
   - 若已被取代 → 连同 `:845` 的 `stop()` 一并删除

   **不得**只删 Timer 而留下悬空的 `stop()` 调用（会成为运行时错误）。

2. **C-2 守护恒假**：`Wallpaper.qml:711`
   `prestartReloadGeneration = ++prestartRecordGeneration;`
   把两个代次赋为同值，致 `:728` 的守护恒假，
   其注释声称的「防止被取代的异步 reload 污染状态」从未生效。
   须使该守护**真正生效**：让「发起 reload」与「记录当前代次」分离，
   使被取代的完成回调能被正确识别并早退。

3. **C-3 更新过时记录**：
   `docs/click-first-hit-swallow-and-wallpaper-boot-postmortem-2026-08-02.md` §6
   中「预存失败：`test_r17_dock_layout_motion.py:259`」一项已不成立
   （实测 11 passed），须在该文档中标注为已修复并注明核实日期。
   同时把本任务修掉的 C-1、C-2 也从「遗留观察项」中划掉。

**约束重点**：
- `constraints.md` P-7（C3 异步化双门不变量）—— C-2 修的正是双门中失效的那一门
- `constraints.md` G-5（禁止死代码/占位）
- `constraints.md` G-6（禁止平行接口）—— C-2 不得新增第三个代次变量，
  须在既有两个变量的框架内修正语义
- `constraints.md` G-7（不得破坏现有功能）—— 壁纸启动路径是历史事故高发区
  （postmortem §S3 即壁纸启动闪烁 + 双引擎泄漏），改动须格外谨慎

**不做**：不碰 `research-report.md` C-4 列出的其余四项遗留观察项。

**完成判据**：
- `prestartedWallpaperReadyTimer` 或语义生效、或被完整删除（含 `:845` 的调用）
- `:728` 守护条件在「reload 被取代」场景下能真正为真并早退
  （须有测试或可复现的验证方式证明，不得仅凭代码阅读声称）
- postmortem §6 三项记录已更新
- **人工验证（部署后）**：冷启动 / 热重启 quickshell，壁纸均正常显示，
  无闪烁、无盖板残留、无重复 `linux-wallpaperengine` 进程
  （用精确 PID 核验，见 P-11）
- `pytest` 全绿

---

# 阶段 B：最大化独占渲染缺陷

## B1 — 建立缺陷的可复现测试基线

**问题引用**：`research-report.md` B-0 / B-1 / B-2 / B-3

**目标**：在**不改动生产代码**的前提下，建立能稳定复现三个现象的自动化测试，
且这些测试当前**必须失败**（红）。

**为何独立成任务**：三个现象都是时序缺陷，若无先行的红灯测试，
后续修复无法证明真正解决了问题（历史教训：静态测试抓不到跨层时序 bug）。

**范围**：
- 新增 niri 测试，覆盖三个场景：
  1. 最大化 + 后方存在其他 tile → 触发最小化 → 断言后方 tile
     在动画**开始时**即进入可见集合（当前会失败）
  2. 独占解除时断言**仅**目标窗口可见性改变，其余不受影响（当前会失败）
  3. 恢复最小化窗口 → 断言其它正常窗口可见性不变（当前会失败）
- 测试须同时覆盖渲染路径与命中测试路径（`constraints.md` B-C2）

**不做**：任何生产代码改动。

**完成判据**：三个测试存在、可运行、且**全部为红**（证明确实复现了缺陷）。
若某个测试意外为绿，说明该现象的理解有误 →
停止并在 `acceptance/B1-note.md` 记录，向用户报告。

---

## B2 — 修复独占解除时机与粒度

**问题引用**：`research-report.md` B-1、B-2；根因 B-0

**目标**：让 B1 中的场景 1、场景 2 测试转绿，且满足 BI-1 / BI-2 / BI-3。

**范围**：
- 修改 `MaximizeVisualFsm`（`niri/src/layout/maximize_visual_fsm.rs`）
  与/或 `maximizing_window_location()`（`scrolling.rs:3443`）
  与/或 `tiles_in_display_order()`（`scrolling.rs:6126`）的独占判据
- 使最小化/恢复动画期间，未参与该次生命周期变更的 tile 不受独占影响（BI-1）
- 使独占解除按窗口判定，而非整列布尔翻转（BI-2）

**约束重点**：
- `constraints.md` B-C1（禁止新增并行状态机）
- `constraints.md` B-C2（渲染与命中测试判据共用）
- `constraints.md` B-C4（不得削弱 `TimedOutVisibleFallback` 超时保护）

**不做**：不碰 `restore_visibility_lease` 相关逻辑（留给 B3）。

**完成判据**：B1 场景 1、2 转绿；场景 3 仍可为红；
niri 既有测试全绿（回归）。

---

## B3 — 修复恢复路径的可见性抑制

**问题引用**：`research-report.md` B-3

**目标**：让 B1 场景 3 转绿。

**范围**：修正恢复路径中三处状态变更的叠加效应：
1. `restore_visibility_lease`（`tile.rs:891-903`；
   渲染侧 `scrolling.rs:3656`、`:4892`）
2. `activate_workspace_for_window`（`layout/mod.rs:4009-4011`）
3. `floating_is_active = FloatingActive::No`（`workspace.rs:810`）

使恢复某个最小化窗口时，其它正常窗口的可见性不被改变。

**约束重点**：`constraints.md` B-C1、B-C3（BI-1）。

**完成判据**：B1 全部三个场景转绿；niri 既有测试全绿；
**人工验证三个原始现象均消失**（验证步骤见 `execution-plan.md`）。

---

# 阶段 A：桌面小部件系统

## A1 — 面板按需加载（内存地基）

**问题引用**：`research-report.md` A-3

**目标**：把零外部引用的重面板改为按需加载，关闭时释放对象树。

**为何在小部件之前**：实测面板首开内存永不回收
（WindowOverview +15 MB 开、13 MB 不回收）。
不先做此项，每个小部件都是一份永久 RSS。

**范围**：
- 将 `WindowOverview` / `ControlCenter` / `Spotlight` / `SettingsPanel` /
  `NotificationCenter` 改为 `LazyLoader`（外部 id 引用均为 0，阻力最小）
- 将 `LeftSidebar` 改为 `LazyLoader`，
  并把 `panelWidth` 提升为 shell 级 readonly 属性
  （唯一外部引用在 `shell.qml:949`）
- 各面板由既有 `open:` 布尔属性驱动 `LazyLoader.active`
- 先实测确认 `WindowOverview` 13 MB 残留的归属
  （`research-report.md` A-3 标注为 `[未确认]`）

**不做**：不动 `dock`（34 处引用）与 `dynamicIsland`（43 处引用）。

**完成判据**：
- 六个面板均可正常打开/关闭，功能与动画无变化（回归）
- 实测 RSS：关闭后回收量显著改善，且给出改造前后的对比数据
- `python -m pytest tests/` 全绿

---

## A2 — 小部件基类与宿主层

**问题引用**：`research-report.md` A-1（三点）、A-2（AC-1~AC-5）、A-6

**目标**：建立桌面小部件的**承载基础设施**，含一个最简小部件用于验证。

**范围**：
- `Widget.qml` 基类：三档尺寸规格（small 2×2 / medium 4×2 / large 4×4）、
  圆角 `RadiusPanelCompact`(18)、玻璃材质（每小部件 1 个 region）、
  `hostVisible` 门控契约、`previewMode` 属性（为 A7 预留，本任务即需实现其行为）
- 桌面宿主 `PanelWindow`：`WlrLayer.Bottom`、`ExclusionMode.Ignore`、
  `KeyboardInteractivity.None`、namespace `tahoe-widgets`
- `mask` 输入策略：顶栏弹层打开 → 置空；否则 → 各小部件 Item 并集
- region 计数保护（上限 32，超限须**可见反馈**，见 `constraints.md` P-5）
- 网格占用表 + 「找第一个可容纳空位」算法
- 配置持久化：`Quickshell.stateDir + "/widgets.json"`，
  格式 `[{id, size, col, row}]`，用 `FileView` 读写
- **电池小部件**（small）作为基类验证载体，数据源 `services/Battery.qml`

**约束重点**：`constraints.md` A-C1、A-C3、A-C4、A-C5、A-C6、P-1、P-3、P-5、P-6。

**不做**：拖动、resize、编辑模式、侧栏 tab（各为后续任务）。
本任务小部件位置由配置文件决定，不可交互移动。

**完成判据**：
- 桌面上显示电池小部件，玻璃材质正确，数据实时正确
- 顶栏弹层打开时点击桌面 → 收回弹层（不被小部件层拦截）
- 弹层关闭时点击小部件 → 小部件接收；点击空白 → 穿透到桌面
- 重启 quickshell 后小部件位置与配置一致
- region 计数保护：人为配置 33 个小部件时给出可见反馈而非静默失效
- `qmllint --bare` 无新增告警；`pytest` 全绿

---

## A3 — 首批小部件（天气 / 日历 / 系统监控）

**问题引用**：`research-report.md` A-5、A-7

**目标**：补齐首批四个小部件中剩余三个，覆盖全部四种数据模式。

**为何与 A2 分离**：A2 验证基类，本任务验证基类对不同数据模式的适配性。
三个小部件共享同一基类与验收方式，故合为一个任务（不得再拆）。

**范围**：
- **天气**（medium）：数据源 `services/Weather.qml`
- **日历**（medium）：纯本地计算，零 I/O；
  分钟对齐刷新可借鉴 `DynamicIsland.qml:2435` 的 `msecsToNextMinute()`
- **系统监控**（small）：数据源 `services/SystemStats.qml`。
  **前置**：必须先验证 `SystemStats` 是否已受 `servicePollingActive` 门控
  （`research-report.md` A-5 标注 `[未确认]`）。
  若未门控，必须先使其门控于宿主可见性，否则违反 `constraints.md` A-C3。

**约束重点**：`constraints.md` A-C3（禁止自建轮询）、A-C4、A-C6。

**不做**：任何需缩略图或大图的小部件（照片、窗口预览、媒体封面）。

**完成判据**：
- 四个小部件（含 A2 的电池）同时显示，数据均正确
- **实测**：小部件常驻时，60 秒子进程采样的稳定 PID 数与新建 Timer 数
  相比 A2 完成时**无新增**（证明未引入唤醒源）
- 宿主隐藏时所有小部件刷新停止
- `pytest` 全绿

---

## A4 — 长按进入编辑模式 + 拖动移位

**问题引用**：`research-report.md` A-0 第 3 条、A-2（AC-4）

**目标**：长按小部件进入编辑模式，可拖动改变位置并持久化。

**为何在 A3 之后**：只有存在 ≥3 个小部件时，拖动重排才可被有意义地测试。

**范围**：
- 长按识别：`onPressed` 启动计时；位移超阈值则取消（判为拖动而非长按）；
  计时到达 → 进入编辑模式
- 编辑模式视觉：抖动动画（**必须**门控于编辑模式，见 `constraints.md` A-C3）、
  删除按钮
- 拖动：复用 `Dock.qml:1396-1470` 四状态模式
  （`onPressed` / `onPositionChanged` + 位移阈值 + `suppressNextClick` /
  `onReleased` / `onCanceled` 完整回滚）
- 落点：二维网格吸附；坐标须 `mapToItem` 转宿主坐标系
- 拖动期：抑制 hover、阻止宿主尺寸变化（避免 region 更新风暴）
- 删除小部件：对象树须真正销毁（`Loader` 卸载）
- 提交时机：仅 `onReleased` 写盘一次

**约束重点**：`constraints.md` A-C2、A-C5、P-1（禁弹簧）、P-3（Motion.js 令牌）。

**不做**：resize（A5）。

**完成判据**：
- 长按进入编辑模式；短按不触发；拖动不误触发点击
- 拖动改变位置并持久化；重启后位置正确
- **`onCanceled` 路径验证**：拖动中途使宿主失去输入（如打开顶栏弹层）→
  拖动状态完整回滚，不卡死
- 拖动期间无写盘（可通过 strace 或日志验证）
- 退出编辑模式后抖动动画停止（无常驻动画）
- `pytest` 全绿

---

## A5 — 编辑模式边缘 resize（三档切换）

**问题引用**：`research-report.md` A-0 第 4 条、A-6

**目标**：编辑模式下按住小部件边缘拖动，在 small/medium/large 三档间切换。

**范围**：
- 边缘命中区（建议 6–8px），仅在编辑模式生效
- 拖过阈值即换档（**非**自由缩放）
- 换档后重新计算网格占用；若目标尺寸与其他小部件冲突则拒绝换档并给出反馈
- 尺寸变化动画：**禁用弹簧**（`constraints.md` P-1）
- 提交时机：仅操作结束时写盘一次

**约束重点**：`constraints.md` P-1、P-3、A-C5。

**完成判据**：
- 三档均可互相切换，视觉与布局正确
- 冲突场景（空间不足）被正确拒绝且有反馈，不产生重叠
- 换档动画无弹簧（可通过 grep 断言 + 结构测试）
- 持久化正确；重启后尺寸一致
- `pytest` 全绿

---

## A6 — 侧栏第三个 tab（小部件库）

**问题引用**：`research-report.md` A-0 第 1、2 条、A-4

**目标**：侧栏分段控件改三分，第三个 tab 列出可用小部件；
点击某项 → 关闭侧栏 → 桌面空位自动添加。

**范围**：
- 分段控件二分改三分，须同时改四处
  （`LeftSidebar.qml:148` 宽度、`:176` `targetXFor()`、
  `:205-217` SegmentLabel、`:224` 点击分区）
- 新增第三个 tab 内容：可用小部件列表（从上到下排列，含名称与可选尺寸）
- 点击项 → 发信号 → shell 关闭侧栏 + 在桌面找空位添加
- 小部件注册表：集中定义 `{id, name, sizes, source}`

**约束重点**：`constraints.md` A-C7（现有两 tab 行为不得改变）、G-8（不得加需求外功能）。

**不做**：带实时预览的画廊（A7）。本任务列表为文字/图标条目即可。

**完成判据**：
- 三个 tab 均可切换，thumb 动画正确对齐三分位置
- **回归**：「系统」「天气」两 tab 的行为、布局、动画与改造前一致
- 点击列表项 → 侧栏关闭 → 小部件出现在桌面空位
- 桌面无空位时给出可见反馈，不静默失败
- `pytest` 全绿

---

## A7 — 小部件库实时预览

**问题引用**：`research-report.md` A-0 第 1 条（"按照列表从上到下排列"的完整形态）

**目标**：把 A6 的文字列表升级为带真实预览的画廊。

**为何最后做**：只有 ≥4 个小部件时画廊才有意义；
过早实现会把基类的 `previewMode` 语义过早固化。

**范围**：
- 列表项渲染小部件的**真实预览实例**（使用 A2 已实现的 `previewMode`：
  禁用交互与数据刷新）
- 同一小部件的多种可选尺寸可分别预览与选择

**约束重点**：`constraints.md` A-C3（预览实例不得触发数据刷新）、G-8。

**完成判据**：
- 每个可用小部件在库中显示真实预览
- **实测**：打开库 tab 时无新增进程 spawn、无新增 Timer
  （预览不得触发数据刷新）
- 从预览选择尺寸后正确添加到桌面
- `pytest` 全绿

---

## 路线图完成判据（全局）

全部 11 个任务完成后，须满足：

1. postmortem §6 中已核实成立的遗留缺陷（C-1、C-2）已修，过时记录（C-3）已更新
2. 用户报告的三个窗口遮挡现象**均消失**（人工验证）
3. 用户定义的五条小部件需求**均实现**
4. `niri` 全部测试绿；`tahoe-shell` 全部 pytest 绿
5. 无 `constraints.md` 第 5 章速查表中的任何违规
6. 实测：小部件系统上线后未引入新的常驻唤醒源
7. 实测：面板按需加载后 RSS 有可量化改善
8. 每个任务均有独立子代理审查记录存于 `acceptance/`
