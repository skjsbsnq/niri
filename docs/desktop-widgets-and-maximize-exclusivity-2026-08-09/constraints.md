# 约束文件（CONSTRAINTS）

适用范围：`docs/desktop-widgets-and-maximize-exclusivity-2026-08-09/roadmap.md`
中全部任务（C1、B1–B3、A1–A7）。

**本文件是硬边界。执行者在任何任务中违反其中任意一条，该任务即判定失败，
必须回滚重做，不得以"功能已实现"为由通过验收。**

若确有充分理由需要违反某条约束：**先修改本文件并写明理由**，
再进行代码改动。禁止「先改代码、事后补文档」。

---

## 第 0 章：元约束（关于如何工作）

### G-1 串行执行，禁止并行

**必须**完成一个任务的全部流程（实现 → 自检 → 独立子代理审查 → 修复审查问题 →
commit → push）之后，才能开始下一个任务。

禁止：同时开工多个任务；把多个任务合并为一个 commit；
「先把代码都写完最后一起审查」。

### G-2 每个任务必须经独立子代理对抗性审查后才能 commit

审查要求见 `execution-plan.md` 第 3 章。要点：

- 审查者必须是**独立子代理**，不得由实现者自审。
- 审查者**必须实际读取改动后的代码**，不得只读 diff 摘要或凭描述判断。
- 审查须为**对抗性**：默认实现有缺陷，主动寻找反例，而非确认其正确。
- 审查发现的问题必须修复或在文档中明确记录为「已知遗留 + 理由」，
  才能 commit。
- **审查通过前禁止 commit；commit 后才能 push。**

### G-3 禁止无限执行

每个任务有明确的**完成判据**（见 `execution-plan.md` 各任务的「验收」段）。
判据满足即停止该任务，不得继续「优化」「顺手改进」。

单个任务若连续 **3 轮**修复后仍无法通过验收：
**停止该任务，将当前状态、失败原因、已尝试方案写入
`acceptance/<任务号>-blocked.md`，然后停下来向用户报告，不得继续尝试。**

### G-4 任务粒度：不得再行拆分

`roadmap.md` 中的任务已按「一个完整可验收的功能单元」划分。
执行者**不得**把单个任务拆成更小的多次 commit，
也**不得**把多个任务合并。一任务 = 一次完整流程 = 一个 commit。

### G-5 禁止最小实现 / 禁止占位

禁止：`TODO`、`FIXME`、空函数体、`return false; // 待实现`、
硬编码假数据充当真实数据源、只在 happy path 生效的实现。

每个任务交付的必须是**完整可用**的功能。

### G-6 禁止平行接口

**这是本项目历史事故的重点，最高优先级。**

禁止：
- 新增一个函数/属性/组件，与既有的同类功能并存而不替换它
  （例：既有 `setMinimized()`，又新增 `setMinimizedV2()`）。
- 为测试新建一套与生产不同的状态机或数据路径
  （`niri/src/layout/maximize_visual_fsm.rs:53-55` 已确立此原则：
  "Test/diag observation of the production FSM — **no parallel test state machine**"）。
- 同一份状态用两个变量分别维护。
- 在 `tahoe-shell/components/` 下放置临时副本或实验性重复组件。

**允许重构**：可以修改、重命名、合并、删除既有实现，
只要最终**只有一条**代码路径承担该职责。

### G-7 禁止破坏现有功能

改动**不得**改变任何未在 `roadmap.md` 中声明要改变的行为。

每个任务的验收**必须**包含回归验证（见 `execution-plan.md` 第 4 章的回归清单）。

### G-8 禁止添加用户未要求的功能

用户需求的完整定义见 `research-report.md` 第 A-0 节（五条）与 B 项三个现象。

**禁止**自行添加：小部件商店 / 云同步 / 插件机制 / 主题切换 /
多页或多桌面小部件 / 小部件间通信 / 动画特效开关 / 使用统计 /
配置导入导出 / 快捷键自定义界面，以及任何其他未经用户明确要求的功能。

不确定某功能是否在范围内时：**不做**，并在任务报告中提出询问。

---

## 第 1 章：项目既有守护规则（改动前必读）

以下规则来自既有文档与代码 guardrail，**先于本次任务存在**，全部继续有效。

### P-1 玻璃 region 几何严禁弹簧动画

`GlassPanel` 的 `x` / `y` / `width` / `height` / `region*` 属性
**严禁**使用 `SpringAnimation`。

原因：弹簧过冲会让 region 超出 surface，niri 拒绝该 region 并导致纹理损坏。
guardrail 提交：`0704ea4`。

**本次推论**：小部件的拖动落位、resize 换档、编辑模式抖动，
凡影响 region 几何者一律用 `Motion.js` 的时长 + Qt 缓动。

### P-2 `useSpring` 门控

`shell.qml` 的 `useSpring`（默认 true）门控所有 QML 弹簧。
新增动画若使用弹簧，必须尊重此门控（软渲染 / VMware 环境需为 false）。

### P-3 Motion.js 是唯一动效令牌来源

时长与缓动必须取自 `components/Motion.js`。
禁止在组件里硬编码 `duration: 250` 这类字面量。
禁止命令式 `.duration = N` 覆写（既有教训：该形式曾成为审查盲区）。

### P-4 QML 组件不得直写 KDL

`Motion.js` 的 profile 名必须与 `niri_settings_tool.py` 同步。

### P-5 glass region 上限 32

`niri/src/protocols/tahoe_glass.rs:26` `MAX_REGIONS_PER_SURFACE = 32`。
超出**静默丢弃**（`:1091` 的 `.skip()`）。
小部件宿主必须实现计数保护并在超限时给出**可见反馈**，不得静默失效。

### P-6 C7：on-demand 焦点切换时机（niri）

来源：`docs/click-first-hit-swallow-and-wallpaper-boot-postmortem-2026-08-02.md` §5。

wl 键盘焦点 = Qt 应用激活态；失焦会取消该应用**按住中的全部 pointer grab**。
实现见 `niri/src/niri.rs:7145` `handle_on_demand_focus_press()`。

**本次硬性推论**：桌面小部件层必须用 `KeyboardInteractivity.None`，
**不得**给该层设 `focusable`。键盘交互走 IPC 或全局快捷键。

**若任务需要改动 C7 相关代码**：postmortem 标注
"必须重跑嵌套 WAYLAND_DEBUG 复现脚本验证"，且合成器无 headless 输入测试设施
（列为人工审查约束）。本次任务**不应**触及该块。

### P-7 C3：异步化双门不变量

把同步读改异步时：①所有依赖该状态的决策点必须加「未解析早退门」，
②完成回调必须重新驱动被门挡掉的决策。**只做其一必炸。**

### P-8 C6：`waitForJob` 仅限 boot-once

`Component.onCompleted` 之外禁止 `waitForJob`（周期路径必须异步）。

### P-9 C2：QML 结构测试必须锁定义作用域

凡断言 `<id>.<fn>(...)` 调用形态的测试，
必须**同时**断言 `<fn>` 定义在 `<id>` 指向的作用域。

历史教训：只断言调用形态，曾把 bug 钉成规范。

### P-10 C9：部署纪律

1. **提交后必须重建再部署**（禁 `-modified` 二进制上线；
   部署前用 `niri --version` 核验）。
2. 替换运行中二进制必须 `cp 到临时名 && mv -f`（避免 ETXTBSY）。
3. shell QML 改动 `cp` 后需重启 quickshell / 会话。

### P-11 C10：禁止宽匹配杀进程

进程操作必须限定**精确 PID**。
**禁止** `pkill -f` 宽匹配（历史事故：误杀 live quickshell，桌面缺席 80 分钟）。

### P-12 C11：qmllint 工具链

必须用 `/usr/lib/qt6/bin/qmllint --bare`。
PATH 里的是 Qt5.15，对 `pragma ComponentBehavior` 静默失败。

---

## 第 2 章：B 项专属约束

### B-C1 不得新增并行状态机

修复必须在既有 `MaximizeVisualFsm`（`niri/src/layout/maximize_visual_fsm.rs`）
与 `restore_visibility_lease`（`niri/src/layout/tile.rs:891-903`）
的框架内进行。禁止新增第二套最大化/可见性状态表示。

### B-C2 渲染与命中测试判据必须共用

当前 `tiles_in_display_order()`（`scrolling.rs:6126`）同时服务：
- 渲染：`scrolling.rs:3652`
- 命中测试：`scrolling.rs:3727`（`window_under`）

重构后**仍须共用同一判据**，禁止分叉为两套逻辑。
（若确需分离，必须在本文件说明理由。）

### B-C3 三个不变量

- **BI-1**：最小化/恢复动画期间，未参与该次生命周期变更的 tile 的可见性
  **不得**因最大化独占而改变。
- **BI-2**：独占解除必须**按窗口**判定，不得是整列的全局布尔翻转。
- **BI-3**：渲染路径与命中测试路径可见性判据一致（同 B-C2）。

### B-C4 不得放宽超时保护

`MaximizeVisualPhase::TimedOutVisibleFallback` 的存在目的
（`maximize_visual_fsm.rs:18`）是
"Do not let an unresponsive client hide the rest of the workspace indefinitely."

修复**不得**削弱这一保护。

---

## 第 3 章：A 项专属约束

### A-C1 小部件层输入策略

- 层级：`WlrLayer.Bottom`（壁纸之上、窗口之下）
- `exclusionMode: ExclusionMode.Ignore`
- `KeyboardInteractivity.None`（见 P-6）
- namespace：`tahoe-widgets`
- `mask`：顶栏弹层打开 → 置空；否则 → 各小部件 Item 并集

### A-C2 拖动必须复用 Dock 四状态模式

必须复用 `Dock.qml:1396-1470` 的模式，
**禁止**引入 `DragHandler` / `Drag` / `DropArea` 做内部重排。

必须实现的四个回调（缺 `onCanceled` 直接判定失败）：
`onPressed` / `onPositionChanged`（含位移阈值 + `suppressNextClick`）/
`onReleased` / `onCanceled`（完整回滚）。

坐标换算必须用 `mapToItem` 转到宿主坐标系（参照 `Dock.qml:948`）。

### A-C3 小部件禁止自建轮询

小部件**只读**现成 `services/` singleton。
**禁止**自行 spawn 进程、**禁止**新建常驻 Timer。
任何刷新必须门控于宿主可见性（参照 `LeftSidebarWeather.qml:69`）。

编辑模式抖动动画必须门控于编辑模式，不得常驻。

### A-C4 小部件禁止 `layer.enabled`

每个离屏 FBO 均耗内存与显存，小部件数量多则线性放大。
全仓库现仅 2 处使用（`LeftSidebarWeather.qml:190`、`:232`）。

### A-C5 持久化写盘时机

拖动 / resize 期间**禁止**写盘。
只在 `onReleased`（操作完成）时写一次。
使用 `FileView`（fork 内 T07 已改为非阻塞写状态机，提交 `827c8b6`）。

### A-C6 图片卫生

小部件若使用图片：必须设 `sourceSize`（防止大图全尺寸解码；
参照 `Wallpaper.qml:1301` 对 4096×2560 截图的处理）；
一次性图片必须设 `cache: false`。

### A-C7 不得改变现有侧栏两个 tab 的行为

改三分 tab 时，「系统」与「天气」两个 tab 的现有行为、
布局、动画必须保持不变。

---

## 第 4 章：验证工具与命令

### 测试设施

- QML 结构测试：`tahoe-shell/tests/*.py`（现有 110 个）
- niri Rust 测试：`niri/src/tests/`、`niri/src/layout/tests/`
- 既有相关测试文件：
  - `niri/src/tests/lifecycle_observe.rs`（含 `is_suppressed_by_restore_lease` 断言，
    `:1190`、`:1277`）
  - `niri/src/layout/tests/lifecycle_controller.rs`（`:66`、`:114`、`:171`）
  - `niri/src/tests/lifecycle_command.rs`

### 命令

```sh
# QML 静态检查（必须用绝对路径，见 P-12）
/usr/lib/qt6/bin/qmllint --bare <file.qml>

# QML 结构测试
cd /home/wwt/niri/tahoe-shell && python -m pytest tests/ -x -q

# niri 测试
cd /home/wwt/niri/niri && cargo test

# niri 构建
cd /home/wwt/niri/niri && cargo build --release

# 部署前版本核验（见 P-10）
niri --version
```

### 禁止事项（工具层面）

- 禁止 `pkill -f` 宽匹配（P-11）
- 禁止用 PATH 中的 `qmllint`（P-12）
- 禁止部署未重建的二进制（P-10）

---

## 第 5 章：违规判定速查表

| 症状 | 违反 | 处置 |
|---|---|---|
| 新增 `xxxV2()` 与旧函数并存 | G-6 | 回滚重做 |
| 代码里出现 `TODO` / 空实现 | G-5 | 回滚重做 |
| 未经审查即 commit | G-2 | 撤回 commit，补审查 |
| 一个任务拆成多个 commit | G-4 | 合并为一个 |
| 添加了需求外的功能 | G-8 | 移除该功能 |
| 玻璃几何用 SpringAnimation | P-1 | 改为时长 + 缓动 |
| 硬编码 duration 字面量 | P-3 | 改为 Motion.js 令牌 |
| 小部件层设了 `focusable` | P-6 / A-C1 | 改为 `None` |
| 用了 DragHandler / DropArea 做重排 | A-C2 | 改为 Dock 四状态模式 |
| 缺 `onCanceled` 回滚 | A-C2 | 补齐 |
| 小部件自建 Timer / spawn 进程 | A-C3 | 改为读 service singleton |
| 拖动过程中写盘 | A-C5 | 改为 onReleased 写一次 |
| 现有 tab 行为被改变 | A-C7 / G-7 | 回滚该部分 |
| 连续 3 轮验收失败仍继续尝试 | G-3 | 停止并报告 |
