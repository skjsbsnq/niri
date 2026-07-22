# 02 · 窗口生命周期、动画、身份与玻璃系统重构改进路线图

日期：2026-07-22
性质：基于当前源码的实施路线图；本文件本身不实施产品代码修改。
前置报告：`01-research-report.md`
外层仓库基线：`main` / `babb63f`
`niri` 子模块基线：`tahoe-layer-animations` / `a7b88a0c`
`quickshell` 子模块基线：`quickshell-tahoe-desktop` / `bbc267ca`

---

## 0. 路线图结论

后续不应从动画参数或单个 `if` 开始修补。正确顺序是：

1. 先建立能观察真实 render list、configure serial、动画时钟、跨输出 anchor 和 GPU/显存成本的回归基础；
2. 先修复已经确定的正确性问题：最大化转换吞 lifecycle overlay、Genie 坐标空间混用、入口语义分叉、多输出 anchor 覆盖；
3. 再收敛 floating/scrolling 生命周期、closing、最大化及 expanded mode 的 ownership；
4. 再用现有 ext identifier 消除 Shell 的模糊窗口身份；
5. 再收敛 glass schema、kernel、client canonicalization 和 redraw ownership；
6. 最后才处理逐帧分配、重绘粒度、snapshot 显存和 Tahoe render batching。

整条路线严格串行。任一任务未完成独立审查、commit、push 和远端核对时，下一任务不得开始，也不得提前在工作树中准备下一任务的代码。

---

## 1. 不可变执行门禁

### 1.1 每个任务的唯一状态机

每个任务只能按以下状态前进：

```text
Pending
  → In progress
  → Author verification complete
  → Task paths staged + review manifest frozen
  → Independent review in progress
  → FINAL PASS
  → Commit
  → Push
  → Remote hash verified
  → Complete
```

硬规则：

- 独立审查必须在 commit 之前读取只包含本任务的 staged diff、冻结 manifest 和相关源码；作者自查不能替代。
- stage 是冻结审查对象，不是完成或提交。审查前只 stage 本任务路径；在同一个审查阶段内，任何 stage/unstage、文件内容或子模块 staged tree 变化都会使该阶段审查失效，任务回到 `In progress`。跨子模块任务只有第 1.2 节规定的、把已审且已推送的子模块 commit 提升为外层 gitlink 的步骤例外；该步骤不得复用内容审查的 `FINAL PASS`，必须冻结最终外层 tree 并再做一次独立集成审查。
- 审查者必须是无作者历史的独立只读会话，默认只做探索和核验，不修改文件。
- 审查若给出任何 finding，任务回到 `In progress`；修改后必须启动全新的独立审查，旧 `PASS` 自动失效。
- 没有明确的 `FINAL PASS` 不得 commit。
- push 失败、远端 hash 不一致或工作树残留目标任务改动时，任务仍未完成。
- 不得把两个任务合进一个审查或一个未推送工作树，也不得以“顺手清理”扩大任务边界。

### 1.2 子模块仓库的提交规则

外层仓库中的 `niri/` 和 `quickshell/` 是独立 Git 子模块。一个逻辑任务若修改子模块，无法用单个 Git object 同时记录子模块内容和外层指针，因此必须使用两个连续审查阶段；两个阶段仍属于同一个任务：

1. 分别只 stage 本任务在每个被改子模块中的路径，并 stage 本任务的外层非 gitlink 文件；冻结每个子模块 staged tree，以及外层非 gitlink blob 清单和基线 gitlink；
2. 启动全新的独立只读**内容审查**，覆盖该任务的全部逻辑 diff。审查者必须复述各冻结 tree/blob；只有明确的内容阶段 `FINAL PASS` 后，才能提交子模块；
3. 内容 `FINAL PASS` 后不得再改变任何已审文件。每个被改子模块只创建一个任务提交，其 commit tree 必须等于该子模块 reviewed staged tree；逐个 push、fetch 并核对远端 hash；
4. 仅在上述核对成功后，外层索引才允许把对应 gitlink 从基线推进到这些已核对 commit。除该预期 gitlink 变化外，外层非 gitlink blob 必须与内容审查 manifest 完全一致；随后冻结最终外层 staged tree；
5. 启动另一个全新的独立只读**集成审查**。它必须验证：最终外层 diff 仍只含本任务；每个新 gitlink 指向已推送 commit；每个子模块 commit tree 等于内容审查记录的 tree；外层非 gitlink blob 未变。只有明确的集成阶段 `FINAL PASS` 后，才能创建外层集成提交；
6. 外层 commit tree 必须等于集成审查的 reviewed outer tree；push 外层提交，fetch 并核对 `origin/main`；
7. 任一阶段出现 finding，必须按变化范围重新冻结并启动全新审查。若子模块内容或外层非 gitlink 内容变化，从内容审查重来；若只有尚未通过的外层 gitlink 集成状态修正，则重新做集成审查；
8. 这仍是一个任务。在所有子模块与外层远端核对完成前，不得开始下一任务，也不得在两个仓库提交之间准备下一任务的代码。

若一个任务不需要跨仓库，禁止为了“预留接口”提前修改另一个仓库。

### 1.3 “不得创建平行接口”的可执行定义

以下情况均视为违反约束：

- 新 lifecycle command 已接入，但旧的 minimize/restore 正常路径仍可被生产调用；
- 新坐标 newtype 已引入，但原始 `Rectangle<Logical>` 旁路仍能进入 Genie；
- 新 controller 已存在，但 floating/scrolling 仍各自维护旧动画容器；
- ext identifier 已成为正常身份源，但 appId/title 模糊匹配仍是另一个正常分支；
- 新 glass schema、kernel 或 render plan 已落地，但旧默认表或 runtime fallback 仍可独立决定同一字段；
- 新 batched render path 与 legacy path 长期并存，由配置或运行时开关任意切换。

允许的不是“新旧长期共存”，而是同一任务内部的临时编辑状态；任务结束时必须迁移所有调用者并删除旧 owner。向后兼容解析只有在最终都归一到同一内部模型时才允许保留。

### 1.4 不得破坏的行为契约

所有任务默认必须保留：

- scrolling、floating、tabbed 及无输出状态；
- maximize 目标排他显示，以及透明 resize 期间不穿出其他 live tile；
- fullscreen 与 maximized 可叠加的“退出 fullscreen 后仍 maximized”语义；
- minimize、restore、途中反转、close、opening、interactive move 与 transaction blocker；
- xray、blocked-out、screencast、overview zoom 和 reduced motion；
- foreign-toplevel、IPC、xdg-toplevel 的现有对外能力；
- 单屏、多屏、分数缩放、旋转输出、输出热插拔；
- Dock 每个屏幕实例仍显示当前产品要求的窗口集合；除非单独产品决策明确改变，不得借 anchor 修复悄悄过滤窗口；
- Tahoe glass 协议不存在时的 Shell fallback；
- 现有 KDL 配置可继续解析，并在同一 resolver 中得到与迁移前等价的默认结果。

### 1.5 每项任务的完成定义

一个实施型任务只有同时满足以下条件才算完成：

- 目标 ownership 已唯一落位；
- 旧 owner 和旧调用路径已删除，并有静态检索结果；
- 新增测试先证明目标风险，再证明修复后的逐帧或逐事件不变量；
- 相关既有回归全部通过；
- 失败、取消、资源销毁和无 renderer fallback 均有结果；
- Go 后实施的性能任务提供修改前后同场景数据，不以主观流畅度代替；
- 独立审查明确 `FINAL PASS`；
- commit、push、远端 hash 核对完成；
- 工作树仅允许存在用户原有且与任务无关的改动。

条件任务若得到 No-go，完成定义改为：门槛在看结果前锁定；原始基线足以支持 No-go；产品代码、ownership、接口和 schema 均未改变；版本化执行记录明确列出未实施项及原因；随后仍须经过独立 `FINAL PASS`、commit、push、远端核对和工作树检查。No-go 不要求伪造“修复后测试”、旧路径删除或修改后性能数据。

---

## 2. 目标 ownership

### 2.1 窗口生命周期目标结构

```text
foreign-toplevel / IPC / xdg-toplevel adapters
                       │
                       ▼
          one compositor lifecycle command
      { window, direction, resolved anchor policy }
                       │
                       ▼
           Layout lifecycle orchestration
      ┌────────────────┼─────────────────┐
      ▼                ▼                 ▼
typed coordinates  space adapter  lifecycle animation controller
                                  {snapshot, reverse, cleanup,
                                   visibility lease, overlay}
                       │
                       ▼
             explicit render policy
      {live-tile exclusivity, lifecycle overlays,
       floating visibility, hit testing}
```

唯一 owner 约束：

| 语义 | 最终 owner | 不再允许的 owner |
| --- | --- | --- |
| 协议请求解析 | 各协议 adapter | adapter 内决定 snapshot/fallback/缓存选择 |
| minimize/restore 策略 | compositor lifecycle command | foreign 与 IPC 各自一套策略 |
| 坐标空间 | 类型化 geometry 模块 | 变量名和旁边的 `Output` 字段暗示语义 |
| 动画反转与清理 | shared lifecycle controller 实现 | floating/scrolling 复制状态机 |
| overlay 是否绘制 | explicit render policy | 动画容器推进与 render loop 各自猜测 |
| 当前输出 Dock anchor | Shell 单一 publisher + Mapped 当前 anchor | 每屏 delegate 都可直接写、compositor 猜最后写入者 |
| 最大化视觉转换 | typed maximize transition FSM | `committed/timed_out` bool 组合 |
| expanded mode 编排 | Workspace expanded-mode owner | fullscreen/maximize/restore-to-floating 分散分支 |

shared controller 可以在 floating 和 scrolling 中各有一个运行时实例；“唯一”指状态机实现及转换规则只有一份，不表示所有工作区共享一个全局容器。

### 2.2 窗口身份目标结构

```text
niri MappedId
   ├─ IPC window.id
   └─ ext_foreign_toplevel_handle_v1.identifier
                         │
                         ▼
      coordinated Quickshell ext-list + wlr manager owner
                         │
                         ▼
          existing QML Toplevel gains exact identifier
                         │
                         ▼
       Tahoe Shell id-indexed WindowModel merge
```

不得增加新的 compositor window-id 协议、带 id 的第二套 wlr 协议、foreign-toplevel-v2 或带 rectangle 的 IPC 旁路。当前协议没有直接把 ext handle 与 wlr management handle关联起来，因此该任务设有明确的可行性门：必须先用当前 niri 的双 manager 创建顺序和跨进程测试证明 coordinated pairing；若不能证明，任务应停止并请求新的架构授权，不能退回模糊匹配冒充完成。

### 2.3 Glass 目标结构

```text
one editable Rust schema/default source
                  │
                  ▼
      resolved material + named blur kernel
                  │
                  ▼
          immutable ResolvedEffectPlan
 {visible geometry, sample geometry, clip, fallback,
  background effect, shadow, shader parameters}
                  │
                  ▼
          existing renderer/shader path
```

Shell 设置工具不再手写 compositor 默认值。缺省配置显示为“继承”，或使用由 Rust 真源生成并由 CI 校验的只读 artifact；该 artifact 不是第二个可编辑 schema。

---

## 3. 严格串行总序列

| 顺序 | 任务 | 主要结果 | 类型 |
| --- | --- | --- | --- |
| R00 | 回归与观测地基 | render-list、真实 serial、anchor、显存/GPU 基线 | 基础设施 |
| R01 | F01 lifecycle overlay render ownership | 最大化转换不再让 overlay 隐形计时 | P0 修复 |
| R02 | F03 类型化坐标与统一转换 | Genie 只消费一种规范空间 | P0 修复/局部重构 |
| R03 | F04 单一内部 lifecycle command | 协议入口语义一致 | P1 修复/局部重构 |
| R04 | F05/F06 当前输出 anchor ownership | 消除跨输出 last-writer-wins 与陈旧发布 | P1 修复 |
| R05 | minimize/restore controller 收敛 | 删除 floating/scrolling 重复状态机 | 可维护性重构 |
| R06 | closing animation lane 收敛 | 删除两套 closing 容器与清理 | 可维护性重构 |
| R07 | `RemovedTile` 状态运输修复 | 跨 workspace/output 不遗忘 expanded intent | P1 修复 |
| R08 | 最大化视觉 FSM 与 F02 serial 判定 | bool 组合变 typed FSM；仅证实后加入 identity | 可维护性/条件修复 |
| R09 | Workspace expanded-mode 编排 | fullscreen/maximize/返回 floating 单一 owner | 可维护性重构 |
| R10 | F08 无尺寸差 unmaximize 观测门 | 有证据才新增视觉状态转换修复 | 条件修复 |
| R11 | F07 消费既有 ext identifier | Shell O(n) 精确身份合并 | P1 修复/跨仓库 |
| R12 | immutable effect plan | 消除 update 顺序和 runtime fallback ownership 重叠 | 可维护性重构 |
| R13 | 单一 glass schema 与 named kernels | material 可选择 kernel，默认值不再多处手写 | 可维护性/功能保持 |
| R14 | glass client canonicalization 与 redraw owner | 去除重复量化和重复 redraw 分支 | 可维护性优化 |
| R15 | 性能基线复测与门槛决策 | 决定后续优化是否有数据支持 | 观测门 |
| R16 | Genie 每帧分配与 identity | 稳定 element、原地更新动态数据 | 确定性优化 |
| R17 | lifecycle/foreign/glass 定向 redraw | 先处理已明确 ownership 的重绘簇 | 条件优化 |
| R18 | snapshot variant cache 与显存预算 | 仅峰值达到门槛时实施 | 条件优化 |
| R19 | Tahoe render batching | 仅 GPU 数据证明 capture/blur 为瓶颈时实施 | 条件优化 |

R00 到 R14 是架构和正确性主线，不得跳过依赖。R15 到 R19 是性能尾部；条件任务即使决定“不实施”，也必须提交测量记录、独立审查、commit、push 后才算完成，不能口头跳过。

---

## 4. R00：回归与观测地基

### 目标

在不改变产品行为的前提下，让后续任务可以断言“每一帧发生了什么”，而不只检查最终窗口状态。

### 实施范围

- 为 layout/render 测试提供稳定的动画时钟推进和 render-element 分类观测；能区分 live tile、closing、minimize、restore 和 maximize target。
- 扩展 headless fixture，使用真实 `Mapped` configure → ack → commit serial；禁止用 `LayoutElement::on_commit()` 空实现回答 F02。
- 增加双输出异分辨率、分数缩放、旋转、source layer map/unmap/remap 的 fixture helper。
- 为测试或 opt-in trace 增加以下可观测字段：lifecycle direction/state、overlay visibility decision、anchor output/space、maximize FSM 状态、snapshot variant 字节、redraw target、关键 GPU span。
- 记录当前基线：frame p50/p95/p99、Genie 每帧分配次数、snapshot 峰值字节、`queue_redraw_all` fallback 次数、Tahoe region request/commit/capture 次数。

生产默认日志不得变成逐帧刷屏；高频信息使用 test-only sink、trace span 或显式诊断开关。

### 不做

- 不修复 F01/F02/F03；
- 不移动 production ownership；
- 不新增第二套 lifecycle API；
- 不提交失败或 ignored 的“未来测试”作为完成证据。

### 验收

- 新 helper 自己有测试，且现有行为全部绿；
- 能构造“最大化转换 ongoing + 非目标窗口 lifecycle 动画 active”的状态，并读出 overlay decision，但 R00 不改变该 decision；
- 能在真实 serial fixture 中区分旧 configure、最新 ack 和 commit；
- 基线记录包含硬件、输出、scale、renderer、构建 profile 与采样时长。

### 独立审查必须回答

1. 新观测是否读取真实 production 状态，而不是复制一份测试状态机？
2. 是否有任何 test-only API 被 production 调用？
3. serial fixture 是否真的经过 `Mapped` 的 `uncommitted_maximized`？
4. instrumentation 默认关闭时是否无高频分配和日志成本？

---

## 5. R01：F01 lifecycle overlay render ownership

### 目标

修复用户报告最直接的确定机制：maximize transition 仍可排他过滤普通 live tile，但不得让已经 active 的 closing/minimize/restore overlay 在不可见状态继续计时直至过期。

### 源码起点

- overlay 推进：`niri/src/layout/scrolling.rs:448-466`
- overlay 被统一挡住：`niri/src/layout/scrolling.rs:3498-3517`
- maximize target render/hit priority：`niri/src/layout/scrolling.rs:3523-3619`
- floating layer visibility：`niri/src/layout/workspace.rs:1854-1863`

### 目标设计

在 scrolling 内建立一个明确 render policy，分别回答：

- 哪些 live tiles 可见；
- lifecycle overlay 是绘制、暂停还是取消；
- floating layer 是否可见；
- hit testing 的目标是谁。

本任务应选择“继续绘制不冲突的 lifecycle overlay”作为默认修复；若特定 overlay 与 maximize target 冲突，必须有显式按 window id 的取消或遮挡规则。禁止保留“容器继续推进、render loop 静默不 push”的第四种状态。

### 必须保留

- maximizing target 的 live tile 独占；
- inactive tab/其他列不会透过透明 resize shader；
- 关闭 maximize target 时原有 transition 取消语义；
- non-target close/minimize/restore 的 stacking 和 hit testing 不回归。

### 回归测试

- maximize pending/committed/late-commit 各阶段，对 target 与 non-target 分别执行 minimize、restore、close；
- 同列 tab、其他列、floating window；
- 生命周期动画中途 reverse；
- 同列激活不移动 viewport、跨列激活移动 viewport；
- 逐帧断言 overlay decision、progress、render list 和最终清理；
- 动画绝不满足“不可见且 progress 增长”。

### 旧路径删除证明

完成后，`scrolling.rs` 不得再以一个 `if !maximize_transition` 同时包住三类 lifecycle render loop。静态审计必须展示 lifecycle overlay 只经过新的唯一 policy，且旧 block 已删除。

### 独立审查必须回答

1. 修复是否覆盖 minimize、restore、close，而不是只覆盖用户复现中的 minimize？
2. maximize 透明区域是否重新露出普通 live tile？
3. overlay 被隐藏时是否明确暂停或取消，而非继续推进？
4. render、hit test 与 floating visibility 是否使用同一 policy 结论？

---

## 6. R02：F03 类型化坐标与统一转换

### 目标

让 surface-local、output-local、workspace-content、workspace-view 和 global 坐标不能再以相同裸类型被误传；Genie 内部只接受一种规范坐标。

### 源码起点

- `MinimizeRect` 仍是 `Output + Rectangle<i32, Logical>`：`niri/src/layout/mod.rs:142-150`
- source surface → output-local：`niri/src/handlers/mod.rs:672-708`
- scrolling 把 tile 起点加回 `view_pos`：`niri/src/layout/scrolling.rs:1700-1734,1776-1807`
- Genie 直接 union 起点与 target，再统一减 `view_rect.loc`：`niri/src/layout/minimize_window_animation.rs:362-407`

### 目标设计

建立不可隐式互换的内部类型，名称可在实现时调整，但至少表达：

- `SurfaceLocalRect`；
- `OutputLocalRect`；
- `WorkspaceContentRect`；
- `WorkspaceViewRect`；
- `GlobalRect`。

转换函数必须要求所需 context，例如 source layer geometry、output global origin 或当前 workspace view offset。`MinimizeWindowAnimation` 只保存 output-local 起点和 anchor；render 时仅进行 output-local → render-target 的一次转换。

类型化坐标是替换，不是给旧 helper 再包一层。任务结束时，lifecycle/anchor 生产路径不得接受语义不明的 `Rectangle<_, Logical>`。

### 回归测试

- `view_pos` 为 0、正大值、负值，并在动画中继续移动；
- scrolling、floating、overview zoom；
- 1.0、1.25、2.0 scale 与 90/270 度输出；
- 两输出原点不为零、分辨率不同；
- target/source 在当前输出、其他输出、缺失和空尺寸；
- minimize 与 restore 的起终点逐帧一致，reverse 不跳变；
- 文档中的 `view_pos=1000/window=100/anchor=900` 数值案例成为可执行测试。

### 旧路径删除证明

至少执行并审计：

```text
rg -n 'pub struct MinimizeRect|target_rect: Option<Rectangle|source_rect: Option<Rectangle' niri/src/layout
rg -n 'tile_pos\.x \+= view_pos' niri/src/layout
```

期望是旧 `MinimizeRect`/裸 target API 和手动补 `view_pos` 路径为零；若新类型沿用旧名字，审查必须证明字段本身已编码空间且无裸旁路。

### 独立审查必须回答

1. 每次转换是否有唯一方向和所需 context？
2. 是否仍存在通过 `.rect` 或 `.to_f64()` 绕开类型检查的生产路径？
3. fractional scale 的 round 是在正确边界发生且只发生一次吗？
4. xray、blocked-out、overview 的坐标是否仍正确？

---

## 7. R03：F04 单一内部 lifecycle command

### 目标

foreign-toplevel、IPC 和 xdg-toplevel 只负责解析请求；缓存 anchor 选择、renderer 可用性、snapshot、fallback、焦点和模型状态由一个 compositor 内部 command 决定。

### 目标设计

单一 command 至少表达：

```text
window id
direction: Minimize | Restore
anchor input: Explicit | CachedForCurrentOutput | None
invocation metadata: 仅用于 trace/权限，不改变动画策略
```

renderer 不可用是正常 fallback，不是另一个 API。command 内一次性完成：

1. 找到 window/current output；
2. 解析显式或缓存 anchor；
3. 验证坐标/output/source generation；
4. 尝试 snapshot 动画；
5. 失败或无 renderer 时走同一模型状态 fallback；
6. 返回统一 result，供 adapter 决定协议响应和 redraw。

Wayland trait 必须保留的 `set_minimized`/`unset_minimized` 是协议 adapter，不算平行接口；它们不得再拥有策略。

### 必须替换的旧入口

- `Layout::set_minimized[_with_rect]` 的生产策略入口；
- `minimize_window_with_snapshot` / `restore_window_with_snapshot`；
- `minimize_window_with_target` / `restore_window_with_source`；
- `Niri::minimize_window_with_animation` / `restore_window_with_animation` 的平行分支；
- foreign handler 直接读 cache、IPC 固定传 `None` 的差异。

私有的分层 adapter 可以存在，但只能由 command 调用，不能被协议入口绕过。

### 回归测试

- 同一窗口、同一 anchor 分别从 foreign、IPC、xdg 发起，得到相同 command trace、snapshot/fallback 和最终状态；
- restore 无 source rect、renderer closure 返回 `None`、snapshot 创建失败；
- duplicate minimize/restore 返回 no-op；
- minimize 结束 interactive move；restore 对正在 move 的 tile 保持现有拒绝语义；
- wrong-output/stale anchor 的降级一致；
- reduced motion、Genie shader 不可用时仍可见。

### 旧路径删除证明

```text
rg -n 'set_minimized_with_rect|minimize_window_with_snapshot|restore_window_with_snapshot|minimize_window_with_target|restore_window_with_source|minimize_window_with_animation|restore_window_with_animation' niri/src
```

旧生产符号应为零；测试 helper 若保留同名也必须迁移，避免测试继续验证已删除架构。

### 独立审查必须回答

1. 三种入口是否真正到达同一策略 owner？
2. cache 选择是否只发生一次且基于 current output？
3. renderer 失败是否会留下“状态已变但 live tile/overlay 均不可见”的半完成态？
4. 是否通过新增带 rectangle 的 IPC 或第四条协议绕开了收敛目标？

---

## 8. R04：F05/F06 当前输出 anchor ownership 与发布生命周期

### 目标

消除正常 Shell 路径中的多 Dock 竞争、remap 后未可靠重发及视觉几何陈旧问题，同时严格遵守 wlr `set_rectangle` “只考虑最后一个 rectangle”的单值语义。竞争的主修复点在 Shell publisher ownership；compositor 不得通过恢复更早值伪造另一套“有效 rectangle”历史。

本节同时构成对 `01-research-report.md` 第 7 节“compositor 按 output 保存 anchor”候选方向的协议勘误：wlr XML 明确只有最后一个 rectangle 被考虑，因此 per-output 表会形成第二事实模型，不进入实施路线。D01 的竞态事实仍成立；其该项候选方案由本节的 Shell current-screen publisher + compositor 单一 typed last-hint slot 取代。

### 目标设计

源码核验起点：

- 协议的 last-rectangle、surface-local 与 `width=height=0` 删除语义：`quickshell/src/wayland/toplevel/wlr-foreign-toplevel-management-unstable-v1.xml:190-214`；
- 当前 wlr request dispatch 直接转交尺寸：`niri/src/protocols/foreign_toplevel.rs:580-626`；
- 当前 handler 将任一维度 `<= 0` 都清空，并在 source 无法解析时清空：`niri/src/handlers/mod.rs:646-708`；
- 当前 `Mapped` 只有一个 last-rectangle slot：`niri/src/window/mapped.rs:50-55,111-112,402-419`；
- 现有 wlr `Toplevel` 已暴露该 handle 自己的 screens，底层由 output enter/leave 更新：`quickshell/src/wayland/toplevel/qml.hpp:34-38`、`quickshell/src/wayland/toplevel/wlr_toplevel.cpp:250-257`；
- 当前 niri 对每个 wlr handle 发布 `ToplevelData.output` 的 leave/enter：`niri/src/protocols/foreign_toplevel.rs:256-303,392-400`。

- Tahoe Shell 保持当前每屏 Dock 窗口集合语义。publisher 的实体 key 必须是现有 wlr `Toplevel`/handle 对象身份，其 current output 使用该 handle 自己的 `screens`/`output_enter`/`output_leave` 状态；候选提交 API 直接接收该 `Toplevel` 对象及几何，不得先按 IPC id 再查一次模型。R11 精确 identifier 尚未可用时，不得用模糊配对出的 IPC `window.output`、`window.id` 或 `modelKey` 证明 publisher ownership。
- 一个 wlr handle 只允许其 current screen 对应 Dock publisher 调用该 handle 的 `setRectangle`；其他屏上的同 handle delegate 只显示，不发布。handle 暂无 screen、多 screen 或 output 事件切换中的决策必须 fail closed 且可观测，不得由 delegate 顺序或上次 IPC 值猜测。
- 所有 WindowButton/minimized-shelf delegate 将几何候选交给一个 Shell-side publisher owner；owner 负责 current-output 判定、frame coalescing、source remap 和 output 变化后的重发。
- 当前 `WindowModel.mergeWindowModels` 仍可能把 IPC 数据与错误的 wlr `Toplevel` 配对；R04 不改 matcher，也不声称修复该身份问题。它只保证：无论一个实际 handle 被挂在哪个现有 delegate 上，该 handle 的候选都以 handle 自身为 key、只由其 current-screen Dock 发布，绝不根据配对到它的 IPC output 把请求发送到另一屏。相同 appId/title 下的按钮标签、minimized-shelf 归类及用户意图与 handle 的精确对应，必须作为已知剩余风险写入 R04 执行记录，并由 R11 关闭。
- 用一个 typed last-hint slot 直接替换 `Mapped.foreign_toplevel_rect: Option<_>`：`Cleared | Unresolved { source/root, surface_local_rect, generation/reason } | Resolved { source/root, output, output_local_rect, generation }`（具体命名可调整）。它仍只有一个当前值，不增加旧值、per-output 值或“最后可用值”。新的合法非删除请求必须替换旧值；即使 source 暂不可解析或 resolved output 与窗口 current output 不匹配，也不得回退到先前 anchor。`Cleared` 不得与 `Unresolved` 混成同一个 `None`。
- lifecycle command 消费 anchor 时统一核对其 resolved output 与窗口 current output。last request 来自错误输出时，该请求仍是唯一协议事实，但本次动画降级为无 anchor fallback；不得让更早 rectangle 继续生效。
- source layer destroy/unmap 只在 source/root 与当前 anchor 匹配时清理；旧 source 的迟到 cleanup 不能清除新 source。
- 尺寸语义必须与协议及任务起始时固定的上游 wlroots server 契约一致。当前核验基线 wlroots `0855cdacb2eeeff35849e2e9c4db0aa996d78d10` 的 `foreign_toplevel_handle_set_rectangle` 只对任一负尺寸 post `invalid_rectangle`，其余组合均分发给 compositor owner；执行任务时应记录所核对的固定 revision。`width == 0 && height == 0` 按 XML 删除当前 rectangle；其他非负组合，包括 `0×N` 和 `N×0`，仍是 last request，不得偷换成删除或协议错误。零面积 hint 可在 lifecycle command 消费时降级为无 anchor fallback，但不得复活更早 rectangle。坐标加法/转换必须 checked，对内部无法表示的合法请求 fail closed 为 unresolved last hint，不能 panic、wrap 或保留旧值。
- source 暂未映射或无法解析的合法非删除请求也已经取代旧请求；compositor 将唯一 slot 写成 `Unresolved`，使动画消费降级，而不是保留旧 rectangle。source map/remap 后由 publisher 重发当前几何；若实现也支持从当前 unresolved slot 重新解析，它只能更新同一个 slot，不能另建待解析队列或历史表。
- 当前 slot 的 resolved/unresolved variant 都记录 source/root/generation identity；resolved variant 额外记录 output。remap 后由 publisher 重新写入，旧 surface 事件不能复活或删除新绑定。
- 高频 magnification/push/bounce 更新必须经过一个明确的 frame-coalesced owner；不得在多个 QML 属性 handler 中各自发协议请求。

不增加 acknowledgement 协议、每输出历史 anchor 表或第二套 anchor IPC；可靠性通过现有单值 `set_rectangle`、current-output ownership、source 生命周期和发布端重发实现。

### 回归矩阵

- 双屏上同一实际 wlr handle 的两个 Dock delegate 都存在，但正常 Shell 路径只有该 handle 的 current-screen owner 发 wire request；强制注入错误输出的合法晚请求时，它取代旧值且 lifecycle 消费降级，不得悄然使用更早 anchor；
- unique app/title 的正常 merge、toplevel-only model 与人工构造的错误 IPC↔handle merge 都要证明 publisher 始终按实际 handle/screens 去重；同 app/title 下的精确按钮/handle 关联在本任务明确标为 R11 剩余风险，不得伪报通过；
- 窗口跨输出、workspace 跨输出、output 热拔插；
- source layer 未映射、map、unmap、remap、destroy、旧 source 迟到 cleanup、异常 Shell disconnect；
- `0×0` 删除；`0×N`/`N×0` 成为新 last request 并在动画消费时降级；负尺寸走 `invalid_rectangle`；坐标溢出风险不 panic/wrap 且不复活旧值；
- Dock fullscreen 隐藏/恢复、auto-hide、reveal slide；
- magnification、push、bounce 的逐帧 coalescing 和最终 rectangle；
- minimized shelf 初次出现、移动、外部 restore、Dock click restore；
- cross-process 测试必须观察 compositor 实际缓存，而不只断言 QML 调用了函数。

### 旧路径删除证明

```text
rg -n 'set_foreign_toplevel_rect\(None\)' niri/src/handlers
rg -n 'function updateDockRectangle|setRectangle\(' tahoe-shell/components
```

第一组不要求所有合法清理为零，而要求“source 未映射就无条件清空”和“旧 source 清掉新绑定”的分支为零，剩余命中逐条解释。第二组不要求 `setRectangle` 为零，而要求所有生产发布都经过一个 Shell-side publisher owner；delegate 内不得继续各自实现 ownership 或时序策略。

### 独立审查必须回答

1. publisher 是否直接按实际 wlr handle/screens 去重，且在 IPC merge 故意错配时也不会采用错误的 IPC output；非 current-screen delegate 是否不会发请求？
2. source 删除是否精确清理，是否可能由旧 source 误删新绑定？
3. remap 后是否由实际事件触发重发，而非依赖下一次 hover？
4. 高频动画是否只合并为每 frame 至多一次发布？
5. 负尺寸、`0×0`、单维为零和坐标溢出风险是否分别按协议与 checked-conversion 契约处理？
6. 当前全屏隐藏、每屏 Dock 和 minimized shelf 功能是否保留；R11 身份风险是否被如实保留而未被 R04 冒充解决？

---

## 9. R05：minimize/restore lifecycle controller 收敛

### 目标

删除 floating/scrolling 两套同构状态机，使 snapshot ownership、反转、完成清理和 live-tile visibility suppression 只有一个实现。

### 目标设计

在 `layout` 内建立 shared lifecycle controller 类型；floating 和 scrolling 各持一个实例。controller 唯一负责：

- window id → active minimize/restore animation；
- 同 id duplicate/no-op；
- minimize ↔ restore 原对象反转和连续 progress；
- animation creation failure；
- advance、完成事件和资源释放；
- restore 期间 live tile visibility lease；
- remove/cancel/output teardown 时解除 lease；
- overlay 列表及稳定 stacking metadata。

space adapter 只提供：

- tile 查找和当前位置；
- snapshot 捕获所需 render context；
- layout-specific focus/activation；
- overlay 放置层。

controller 不能反向知道 Column、FloatingSpace 的完整布局细节。

### 必须删除

- floating/scrolling 中各自的 `minimize_animations`、`restore_animations`；
- 两套 `take_*`、`has_*`、`clear_*`；
- 两套完成清理循环；
- 两套 `start_minimize_animation_for_tile` / `start_restore_animation_for_tile`；
- 裸 `restore_animation_hidden` 及手工 hide/show 三件套，除非它已被替换成 controller 管理的 typed lease。

opening 保持 Tile-local；本任务不为形式统一而移动已经单一的 opening owner。

### 回归测试

- floating/scrolling/tabbed 同一测试表驱动；
- 0%、中段、接近完成时 reverse，无位置、alpha、morph 跳变；
- remove、move、output teardown、snapshot failure；
- restore 完成或失败后 live tile 必须显示；
- wrong/missing anchor fallback；
- xray/blocked-out/screencast variants；
- `are_animations_ongoing` 最终归零且纹理释放。

### 旧路径删除证明

```text
rg -n 'minimize_animations|restore_animations|take_minimize_animation|take_restore_animation|start_(minimize|restore)_animation_for_tile|restore_animation_hidden' niri/src/layout/{floating.rs,scrolling.rs,tile.rs}
```

旧 space/tile owner 应为零；新 controller 内只允许一份实现。

### 独立审查必须回答

1. reverse 是否复用同一 snapshot/texture，而非创建两个并行动画？
2. visibility lease 是否覆盖成功、失败、取消、remove 和 teardown？
3. floating/scrolling 是否只剩窄 adapter，没有复制 controller policy？
4. stacking、focus 和 interactive move 语义是否保持？

---

## 10. R06：closing animation lane 收敛

### 目标

在 minimize/restore controller 稳定后，删除 floating/scrolling 两套 closing 容器、advance、render 和创建逻辑；保留 transaction 的精确顺序。

### 目标设计

shared closing lane 唯一持有 `ClosingWindow` 集合、advance、完成清理和 overlay 枚举。space adapter 仍计算原布局位置：

- scrolling 的列删除位置补偿；
- floating stacking/position；
- interactive-move close 的落点。

`ClosingWindow::AnimationState::{Waiting, Animating}` 继续是 transaction leaf owner，本任务不重写 transaction 协议。

### 必须保留的顺序

```text
store unmap snapshot
  → create transaction/blocker
  → start closing animation
  → window.on_commit / remove window
  → blocker release
  → animation starts and eventually releases texture
```

compositor 自主 unmap 中 snapshot 必须继续早于 `window.on_commit()`。

### 回归测试

- destroy path 与 null-buffer unmap path；
- blocker pending/completed、transactions disabled；
- floating、scrolling、interactive move、tabbed inactive tile；
- non-target close 与 maximize transition 重叠；
- opening 未完成即 close；
- animation creation failure；
- stacking 和完成后一帧纹理释放。

### 旧路径删除证明

```text
rg -n 'closing_windows|start_close_animation_for_tile|start_close_animation_for_window' niri/src/layout/{floating.rs,scrolling.rs,workspace.rs}
```

旧 space 容器和重复 start helper 应为零；允许协议/Workspace adapter 调用唯一 lane。

### 独立审查必须回答

1. snapshot/on_commit/remove 的顺序是否保持？
2. blocker 未释放时 animation 是否不会错误完成或泄漏？
3. scrolling 位置补偿和 floating stacking 是否仍由正确 adapter 提供？
4. R01 的 lifecycle render invariant 是否继续覆盖 closing？

---

## 11. R07：`RemovedTile` 状态运输修复

### 目标

修复源码已明确标记的状态丢失：单窗从 column 移到其他 workspace/output 时，列级 pending maximized/fullscreen 组合不能因 `RemovedTile` 只携带宽度和 floating 状态而遗忘。

### 源码起点

- `RemovedTile` 当前只有 `tile/width/is_full_width/is_floating`：`niri/src/layout/mod.rs:549-558`
- 单窗移动遗忘 maximize 的 FIXME 与测试：`niri/src/layout/tests.rs:4152-4200`
- Column 同时持有 `is_pending_maximized` 与 `is_pending_fullscreen`：`niri/src/layout/scrolling.rs:191-206`

### 目标设计

用一个 typed transport record 替换零散字段，显式携带：

- column width/full-width；
- source placement；
- pending maximized；
- pending fullscreen；
- 返回 floating 的意图或其当前等价信息；
- 重新插入所需且只有 source column 才知道的其他状态。

该 record 随 remove/add 边界传输；禁止建立按 window id 的旁路 side table。`SizingMode` 单值不足以表达 fullscreen 与 maximized 同时为真，不得把二者压成互斥 enum 后丢失语义。

### 回归测试

- 单窗与整列跨 workspace、跨 output；
- fullscreen + maximized，退出 fullscreen 后仍 maximized；
- tabbed column 的 active/inactive tab；
- floating maximize、interactive move、top snap；
- remove output 后重新归属；
- 往返移动两次不累积或遗忘状态。

### 旧路径删除证明

所有 `RemovedTile` 构造/解构必须在同一任务迁移。不得出现旧字段解构后再从 window/column 猜测缺失状态。原 FIXME 必须由通过的回归测试替换，而不是只删除注释。

### 独立审查必须回答

1. fullscreen 与 maximized 组合是否可无损往返？
2. 所有 remove/add 边界是否迁移，无遗漏 constructor？
3. 是否新增了第二个状态表或从 committed window state 错推 pending intent？
4. floating 返回意图和 tabbed 状态是否保持？

---

## 12. R08：最大化视觉 FSM 与 F02 serial 判定

### 目标

把 `MaximizeTransition { committed, timed_out }` 的隐式 bool 组合替换为显式状态转换；用真实 configure/ack/commit 测试决定是否需要 request identity。

### 目标设计

FSM 至少区分：

```text
PendingConfigure
CommittedSettling
TimedOutVisibleFallback
Cancelled
Finished
```

事件至少包括：request、target commit、timeout、view settled、tile transition settled、new request、fullscreen、target removed。render policy、hit testing、floating visibility 都查询 FSM 的 typed output，不读取内部字段组合。

### F02 决策门

先用 R00 的真实 serial fixture 覆盖：

- maximize A → timeout → 有效 late commit；
- maximize → unmaximize → maximize 快速交错；
- 同列其他 tab commit；
- Activated configure/ack/commit；
- 旧 serial 晚于新 request 到达。

只有测试证明旧请求 commit 能被误认成当前 transition 时，才为 FSM 增加 identity；identity 必须复用现有 configure/commit serial 或由它派生，不能另建平行 serial 状态机。若未证实，任务仍完成 typed FSM 重构，并在执行记录中写明“不加入 identity”的证据。

### 回归测试

- 现有 target column/tile priority、cancel、timeout、late commit；
- 1000/1001 ms 边界使用 unadjusted clock；
- fullscreen 覆盖、target remove、column move；
- R01 overlay invariant；
- 同列 tab 只能由目标 window commit 推进。

### 旧路径删除证明

```text
rg -n 'MaximizeTransition|maximize_transition|maximizing_window_location|maximizing_column_idx|committed: bool|timed_out: bool' niri/src/layout/scrolling.rs
```

允许命中新的 controller 字段名，但旧裸 struct、直接字段写入和散落 helper 必须为零。审查报告应列出所有剩余命中及其归属。

### 独立审查必须回答

1. FSM 是否排除了旧 bool 可表达的模糊组合？
2. 是否错误地把普通 Activated commit 定性为 bug？
3. 新 request 如何明确取消/替换旧 transition？
4. serial identity 若加入，是否完全复用 production serial 语义？

---

## 13. R09：Workspace expanded-mode 编排

### 目标

把 fullscreen、maximize、floating ↔ scrolling 迁移以及退出后返回 placement 的同构编排收敛到 Workspace 的一个 expanded-mode owner。

### 目标设计

owner 负责：

- `Normal / Maximized / Fullscreen` 请求及 fullscreen+maximized 叠加意图；
- floating 窗口进入 expanded mode 前记录返回 placement；
- unmaximize/unfullscreen 的正确返回顺序；
- 与 R07 transport record、R08 visual FSM 的事件衔接；
- interactive move 和 top-snap 的统一入口。

Column 继续负责布局尺寸计算，Mapped window 继续负责协议 pending/committed state；Workspace owner 不复制它们，而是编排事件。

裸 `restore_to_floating` bool 应被 typed return placement 替换，所有读写一次迁移。

### 回归测试

- floating maximize → unmaximize 回原 placement/size；
- fullscreen 覆盖 maximized → unfullscreen 回 maximized；
- fullscreen 时 unmaximize 不得立即 float；
- interactive move unfullscreen/unmaximize 到 scrolling 与 floating；
- top-snap maximize；
- tabbed/non-tabbed 多窗列；
- 不发送额外 configure，恢复尺寸恰好相同时仍清除协议状态；
- R07 所有跨 workspace/output 运输场景。

### 旧路径删除证明

```text
rg -n 'restore_to_floating|set_fullscreen\(|set_maximized\(|toggle_window_floating' niri/src/layout
```

审查必须逐项归类剩余调用；裸 bool 为零，编排决策只在新 owner 中，space/Column 只能是执行 adapter。

### 独立审查必须回答

1. 是否混淆 desired mode、committed mode 与 visual transition？
2. fullscreen+maximized 的非互斥语义是否保持？
3. placement/size/configure 次数是否与基线一致？
4. interactive move、top snap 和普通 action 是否走同一 owner？

---

## 14. R10：F08 无尺寸差 unmaximize 观测与条件修复

### 目标

确认“从最大化恢复普通窗口时动画消失”中，除了 F01/F03 外，是否还存在状态变化但尺寸差低于阈值导致的独立可见缺口。

### 观测场景

- 最大化前窗口尺寸等于、接近、小于 working area；
- server-side decoration on/off、border/radius 不同；
- floating/scrolling；
- 即时 ack、迟到 commit、连续 maximize/unmaximize；
- reduced motion on/off；
- snapshot 是否创建、`animate_serials` 是否命中、resize threshold 判定、最终逐帧视觉。

### 决策规则

- 若状态变化但视觉无差异，不增加无意义动画；提交“无需修复”的证据记录。
- 若边框、圆角、placement 或 expanded progress 有明确跳变，即使 size delta 小，也在现有 resize/expanded animation owner 中修复。
- 禁止复制 minimize/Genie 创建一条“unmaximize 专用动画”旁路。
- 不得通过无条件降低 `RESIZE_ANIMATION_THRESHOLD` 引入连续 resize 抖动。

### 验收

无论是否改产品代码，都必须保存 trace、逐帧断言和结论；若实施修复，要覆盖创建失败、相同尺寸、快速反转和 reduced motion。

### 独立审查必须回答

1. 结论是否把 F01/F03 与独立 F08 分开？
2. 测试是否走真实 configure serial 和 snapshot 链？
3. 若新增动画，它是否属于现有 owner 而非平行实现？
4. 若不实施，证据是否足以关闭风险而不是“本机没看到”？

---

## 15. R11：F07 消费既有 ext identifier

### 目标

用 niri 已发布的十进制 `MappedId` identifier 取代 Tahoe Shell 的 appId/title 模糊合并，使模型合并 O(n) 且同应用同标题窗口不会错绑操作与 rectangle。

### 源码起点

- IPC id 与 ext identifier 同源：`niri/src/window/mapped.rs:234-249`
- ext handle 发布 identifier：`niri/src/protocols/foreign_toplevel.rs:340-366`
- niri 同一 `ToplevelData` 持有 ext 与 wlr instances：`niri/src/protocols/foreign_toplevel.rs:61-70`
- Quickshell 现有 QML Toplevel 只消费 wlr manager：`quickshell/src/wayland/toplevel/`
- Shell 当前 O(n²) 模糊匹配：`tahoe-shell/services/windows/WindowModel.js:25-92`

### 同任务跨仓库实施

1. Quickshell 的现有 toplevel management 模块协调绑定 ext-list 与 wlr manager；
2. native owner 对两条 handle stream 做精确 pairing，并将 identifier 暴露到现有 `Toplevel` 对象；
3. Tahoe Shell 以 identifier 解析 IPC id，建立 id map；
4. activate/minimize/restore/rectangle 继续使用已 pairing 的现有 wlr handle；
5. 删除正常路径的 appId/title 匹配。

不得新建第二个 QML 窗口模型。identifier 是现有 `Toplevel` 的身份属性，不是另一套 toplevel API。

### 可行性硬门

当前标准协议不直接发送 ext handle ↔ wlr handle 的关联。任务开始时必须先用当前 niri 双 manager 的创建/刷新顺序和跨进程 fixture 证明 coordinated pairing 在以下场景稳定：

- Shell 先启动，之后创建窗口；
- Shell 重启时已有多个窗口；
- 同 appId、同 title 的多个窗口；
- bind 两 manager 之间有窗口 map/close；
- close/remap、manager stop/rebind；
- event queue 分批 dispatch。

pairing 一旦 desync 必须 fail closed 并产生诊断，不能静默回退到模糊匹配。若 current protocols 无法证明 exact pairing，本任务标记 blocked 并请求架构授权；不得新增 compositor id 协议或把模糊匹配包装成“identifier 支持”。

### 回归测试

- 0/1/多窗口及 100 窗口合并；
- 同 app/title、动态 title、空 appId；
- id 超过 JavaScript safe integer 的策略必须明确；不得无条件 `Number(u64)` 后丢精度；
- IPC reconnect、ext/wlr reconnect、window close/remap；
- rectangle、activate、minimize、restore 精确落在目标窗口；
- toplevel-only fallback 若产品仍需支持，必须与 niri-managed normal path 明确隔离并有删除/兼容说明，不能参与 IPC 窗口模糊合并。

### 旧路径删除证明

```text
rg -n 'findMatchingToplevel|normalizeIdentity\(toplevel\.appId|normalizeTitle\(toplevel\.title' tahoe-shell/services/windows
```

niri-managed IPC 窗口的模糊 matcher 应为零。合并复杂度测试应证明按 identifier map 线性处理。

### 独立审查必须回答

1. ext ↔ wlr pairing 是否由跨进程事件测试证明，而非假设列表顺序？
2. 同标题窗口的 command 和 rectangle 是否精确？
3. 是否新增了 compositor id 协议、第二套 QML model 或永久 fuzzy fallback？
4. u64 id 在 QML/JS 中是否无精度损失？

---

## 16. R12：immutable `ResolvedEffectPlan`

### 目标

先在不改变配置语法和视觉结果的情况下，消除 `BackgroundEffect` 配置、corner radius、clip、sample padding 和 runtime fallback 的更新顺序依赖。

### 目标设计

在进入 renderer 前一次构造不可变 plan，至少包含：

- resolved material/effect 参数；
- blur kernel；
- visible geometry；
- sample geometry 与 padding；
- clip/draw clip；
- corner radii；
- shadow；
- xray/non-xray 与 fallback policy。

renderer 只消费 plan，不再依赖“先 `update_config`、再改 radius、render 时又补 fallback”的隐式时序。同一 plan 应供普通 window/layer 与 Tahoe region 复用现有 renderer primitives；不创建 glass-v2 renderer。

### 回归测试

- 所有现有 material 的 CPU plan golden；
- clip true/false、edge region、sample padding、halo；
- blur off/on、xray、shadow、large-surface lightweight path；
- layer close frozen glass、window/layer 普通 background effect；
- config reload 前后等价；
- shader uniform 值与迁移前容差内一致。

### 旧路径删除证明

审计所有 `update_config`、corner radius setter 和 render-time fallback 写入。相同字段只能在 resolver/plan builder 决定一次；renderer 内不得再次选择 material default。

### 独立审查必须回答

1. plan 是真正 immutable 输入，还是旧 mutable object 的另一层包装？
2. window、layer、Tahoe region 是否消费同一语义？
3. visible/sample/draw clip 是否仍严格区分？
4. 视觉参数和 shader uniform 是否无意变化？

---

## 17. R13：单一 glass schema、默认值与 named blur kernels

### 目标

解决“改一处模糊玻璃，其他地方一起变化”的数据模型根因，并消除 Rust、Python、QML 多份手写默认值。

### 目标设计

- Rust `niri-config` 是唯一可编辑 schema/default owner；
- 现有全局 `blur` 被解析为保留名称的 default kernel；
- Tahoe material 可引用 named kernel；未显式引用时继续使用 default kernel，保证旧配置行为；
- resolver 输出完整 `ResolvedGlassMaterial { kernel, effect, shadow, fallback }`；继承仅在解析阶段发生；
- Shell 设置工具对缺省字段显示 inherited，不伪造 resolved 默认；若界面需要枚举/范围，使用 Rust 真源生成、CI 校验且不可手改的 artifact；
- 现有 KDL 语法向后兼容，但最终都进入同一 resolver，不保留另一套 legacy runtime path。

### 迁移要求

- 为当前 panel、pill、launcher、dock、menu、toast、backdrop 生成迁移前等价 golden；
- 默认配置不应因为引入 named kernel 发生视觉变化；
- 单独调整 dock kernel 后，panel/toast 等 plan 必须字节级或字段级不变；
- 配置错误必须由现有 validator 报告，不在 Shell 另写一套宽松规则。

### 回归测试

- 旧全局 blur-only 配置；
- 多 named kernels、未知引用、循环/重复定义（若语法允许继承）；
- reload、空配置、部分 material override；
- Shell read/edit/write 保留注释和未编辑 token；
- 每个 material 的 kernel isolation；
- Rust schema artifact regen check。

### 旧路径删除证明

- `GLASS_MATERIAL_DEFAULTS` 等 Shell/Python 手写默认表为零；
- `NiriSettings.qml` 不再包含七套可编辑默认对象；
- renderer 不再直接读取全局 blur 后临时与 material fallback 合并；
- 不存在 `legacy_blur`/`glass_v2` 运行时分支。

### 独立审查必须回答

1. 旧配置是否通过同一 resolver 得到等价结果？
2. material kernel 是否真正隔离，还是最后又被全局值覆盖？
3. 生成 artifact 是否只有 Rust 真源可编辑并由 CI 防漂移？
4. 是否引入了两套配置语义或永久 migration flag？

---

## 18. R14：glass client canonicalization 与 redraw owner

### 目标

清除已经确认的重复 ownership，同时保留现有 polish batching 和 ID diff，不为已有机制再加一套 batch API。

### 实施范围

- 量化只保留在 Quickshell C++ 协议边界；删除 `GlassPanel.qml` 及各组件的二次 1/50 量化。
- 保留 `schedulePolish → one setRegions → changed-only commit` 作为唯一 client transaction owner。
- 保留 `TahoeGlassSurface::diffRegions` 作为唯一 ID canonicalization/diff owner；不增加 `beginBatch/endBatch` QML API。
- niri 的 post-commit、destroy、recreate 全部通过现有 `TahoeGlassHandler::queue_redraw_for_tahoe_glass_surface`；删除 post-commit 内联同构分支。
- surface 可定位时只 redraw 对应 output；无法定位才 fallback all，并计数。

### 回归测试

- 相同值、纯 reorder、duplicate id 不产生 wire request/commit；
- 1、7、32 regions 的增删改；
- interaction/materialAlpha 高频变化每 polish 最多一次 commit；
- controller recreate、destroy、异常 disconnect；
- root output 可定位与不可定位的 redraw 数；
- fallback glass 与 protocol glass 生命周期。

### 旧路径删除证明

```text
rg -n 'quantizeGlass01|\* 50\) / 50' tahoe-shell/components
rg -n 'output_for_root\(surface\)' niri/src/protocols/tahoe_glass.rs
```

QML 二次量化应为零；协议文件中不得再有独立 redraw 决策分支。C++ setter 的单一量化和现有 diff 应保留。

### 独立审查必须回答

1. 是否误删了 C++ 边界量化或 changed-only commit？
2. 是否新增了与 polish 并行的 batch API？
3. 所有 server lifecycle redraw 是否到同一 handler？
4. fallback redraw-all 是否只在无法定位时发生并有计数？

---

## 19. R15：性能基线复测与实施门槛

### 目标

在正确性和 ownership 收敛后重新测量，防止使用重构前数据优化已经消失的热点。

### 固定采集

- CPU frame p50/p95/p99 与主线程 span；
- GPU `TahoeGlass::render_region`、framebuffer capture、blur、postprocess；
- Genie 每帧 allocation bytes/count 与 render element identity；
- `queue_redraw`/`queue_redraw_all` 按原因和输出计数；
- snapshot 每 variant 分配字节、峰值、持有时长、释放后一帧；
- Tahoe wire request、surface commit、region count、capture area；
- direct scanout 命中率。

### 固定场景

| 维度 | 取值 |
| --- | --- |
| 输出 | 1 屏；2 屏异分辨率；热插拔 |
| scale/transform | 1.0；1.25；2.0；旋转 |
| 窗口 | 1080p；1440p；4K；10 个并发生命周期动画 |
| layout | scrolling；floating；tabbed；overview |
| lifecycle | minimize；restore；reverse；close；maximize overlap |
| snapshot | Output；Screencast；blocked-out；交替 |
| glass regions | 1；7；32；静止；60/120 Hz 动态 |
| blur | off；passes 1/3/10/31；不同 kernel |

### 决策门槛

阈值应在任务开始时按目标硬件固定并写入执行记录，不能看到结果后移动门槛。至少要求：

- R17：目标 cluster 的 fallback redraw-all 在典型双屏场景中有可测占比；
- R18：snapshot variants 对峰值显存或 allocation stall 有显著贡献；
- R19：capture/blur 是 glass GPU 主要瓶颈，且合批候选有足够重叠。

R16 的逐帧分配已由源码确定存在，可以继续实施，但仍需此处的前测作为对照。

### 独立审查必须回答

1. 前后场景、构建 profile、硬件和采样长度是否一致？
2. 门槛是否在结果之前固定？
3. 是否把 GPU、CPU、显存和协议流量混成一个“流畅度”结论？
4. R17-R19 的 go/no-go 是否有可复核原始数据？

---

## 20. R16：Genie 每帧分配与 render-element identity

### 目标

消除 `render_genie()` 每帧创建 uniform `Rc`、texture `HashMap`、字符串 key 和新 `ShaderRenderElement::Id` 的确定成本，同时保持现有通用 shader draw path。

### 源码起点

- 每帧 `Rc<[Uniform; 7]>`：`niri/src/layout/minimize_window_animation.rs:383-391`
- 每帧 `HashMap<String, GlesTexture>`：`niri/src/layout/minimize_window_animation.rs:397-405`
- `ShaderRenderElement::new` 每次 `Id::new()`：`niri/src/render_helpers/shader_element.rs:180-195`

### 目标设计

`MinimizeWindowAnimation` 按实际 render-target variant 持有稳定 element/binding/storage；静态 texture binding、program、uniform names 和 ID 只初始化一次，逐帧只原地更新 progress、matrix、area 和 location。继续使用现有 `ShaderRenderElement`/renderer，不增加 Genie 专属第二套 draw API。

若通用 element 需要 mutation API，应让其语义适用于现有 shader element，并在同一任务迁移 Genie；不得保留 `new()` per-frame 作为正常 fallback。

### 回归与基准

- 逐帧 element ID 稳定，动态 commit/damage counter 正确前进；
- minimize、restore、reverse、三种 snapshot variant；
- target rect 改变、view movement、scale/output change；
- shader unavailable fallback；
- allocation count/bytes 与 R15 前测对比；
- 逐帧像素或 uniform golden 不变。

### 旧路径删除证明

在 `render_genie` 中以下构造必须为零：`Rc::new`、`HashMap::from`、`String::from`、逐帧 `ShaderRenderElement::new`。不得用 object pool 掩盖仍在创建新 identity。

### 独立审查必须回答

1. element ID 稳定时，damage 是否仍覆盖动态 uniform 变化？
2. texture/renderer context 变化是否安全重建，而非使用失效资源？
3. 所有 render-target variants 是否复用正确 binding？
4. 是否保留了隐藏的 per-frame legacy path？

---

## 21. R17：lifecycle/foreign/glass 定向 redraw

### 目标

不尝试一次清理全部 182 个 `queue_redraw_all()`；只在 ownership 已经明确的 lifecycle、foreign-toplevel 和 Tahoe glass cluster 中，将可证明的事件映射到受影响 output/damage。

这不是最小补丁：本任务应建立一个统一 redraw attribution 结果类型，由已收敛的 command/controller 返回受影响 outputs/reasons；adapter 不再自行猜测。

### Go 条件

R15 必须同时证明：目标 cluster 内仍有可定位事件走 `queue_redraw_all()`，且这些 fallback 对多输出 frame submission、CPU/GPU 成本或 direct-scanout 命中率有达到任务开始前锁定门槛的影响，才实施 attribution 类型。仅有静态 `rg` 命中数不构成 Go 证据。

### 实施规则

- lifecycle command 返回 current/source/target output 影响集；
- anchor 更新仅影响目标窗口及相关 output，纯缓存 no-op 不 redraw；
- maximize/expanded owner 返回 workspace/output 影响集；
- glass 使用 R14 的单一 handler；
- 无法定位、output teardown 或全局配置变化才允许 redraw all；每个 fallback 有 reason counter。

不得为了让定向测试通过而删除真实的跨输出依赖；若事件影响两个输出，显式返回两个，而不是选一个。

### 回归与基准

- 单屏/双屏/跨输出移动；
- minimize/restore/close/maximize、wrong-output anchor；
- output hotplug、无输出状态；
- glass root 可定位/不可定位；
- unaffected output 不提交 frame，affected output 不漏帧；
- R15 同场景 frame/redraw 数据前后对比。

### 旧路径删除证明

目标 cluster 中协议 adapter 直接 `queue_redraw_all()` 应为零；剩余全局重绘必须带被审查的 reason，并在执行记录列出。不得把 `queue_redraw_all` 改名后继续无条件全绘。

### No-go 结果

若 R15 显示 fallback 已极少、事件本质上为全局，或定向重绘对目标指标无可测改善，本任务提交 no-go 原始数据并结束，不引入 redraw attribution 类型、reason registry 或 adapter 中间层。

### 独立审查必须回答

1. attribution 来自唯一 owner，还是 adapter 各自维护 output 列表？
2. 跨输出事件是否完整包含所有受影响输出？
3. fallback 是否可观测且仅用于无法定位/真正全局事件？
4. 是否出现漏帧、动画停止调度或 direct scanout 回归？

---

## 22. R18：snapshot variant cache 与显存预算（条件任务）

### Go 条件

R15 证明 Output/Screencast/blocked-out 多 variant 同时初始化，对峰值显存、allocation stall 或 OOM fallback 有显著贡献。若不满足，提交 no-go 记录并结束本任务，不引入抽象。

### 目标设计

建立一个 snapshot variant cache owner，供 resize/minimize/closing/layer closing 消费：

- 按 renderer context、scale、transform、variant key 懒生成；
- 明确字节预算、LRU/释放策略和 animation lifetime；
- 重用现有 `RenderSnapshot` 输入，不在每个动画类保留独立 `render_to_texture` closure；
- 资源失败统一降级，不留下半初始化 variant；
- 动画完成后一帧内释放不再需要的强引用。

是否降采样必须有视觉/性能单独证据；不能把分辨率降低作为 cache 重构的隐含行为变化。

### 回归与基准

- 4K@2、三 variant 交替与并发动画；
- renderer context reset、output scale/transform 变化；
- xray/blocked-out/screencast 正确纹理；
- allocation failure；
- 快速 reverse/close/remap；
- 峰值字节、创建延迟、释放延迟前后对比。

### 旧路径删除证明

minimize/closing/closing-layer 中重复 `render_to_texture` closure 和旧平行 OnceCell/texture slots 必须迁移到唯一 cache；不能保留“cache miss 就走 legacy converter”的永久 fallback。

### 独立审查必须回答

1. cache key 是否包含所有 renderer/scale/transform/variant 语义？
2. 预算和释放是否真实减少强引用，而非只多一层 map？
3. fallback 是否仍保持动画可见和资源一致？
4. 若 no-go，数据是否足以证明不值得增加抽象？

---

## 23. R19：Tahoe render batching（条件任务）

### Go 条件

只有 R15 证明同一 surface 多 region 的 framebuffer capture/blur pass 是主要 GPU 瓶颈，且候选 region 在 sample geometry、kernel、xray target 和 stacking 上可安全合并，才实施。

### 目标设计原则

- batch identity 必须至少包含 renderer context、render target/output、damage namespace、scale、transform、kernel/effect configuration 和 xray source/target identity；任一不同必须分 batch。不得把“kernel/render target 相同”当成完整 key。
- 只有 capture/sample 来自同一坐标平面、兼容的 sample geometry 可形成有界 union，且 union 面积约束已在 Go 门槛前固定，才允许合并；否则是硬拒绝条件。
- 只允许合并连续且可证明等价的 stacking epoch；中间存在其他 element、namespace 不同或无法保持原 region 顺序时必须分 batch。
- 合并 capture 不得扩大到明显更大的无关区域；
- 每个 region 的 visible clip、sample padding、corner、shadow 和叠放仍独立；
- changed damage 仍按 region id 精确；
- 新 batch owner 直接替换逐 region capture 调度，不保留 batched/legacy 两套长期开关；
- 不修改 Wayland wire protocol，client polish/diff 已经是正确的 transaction owner。

### 回归与基准

- 1、7、32 regions；相邻、重叠、完全分离；
- 同/不同 renderer context、render target、namespace、scale/transform、kernel、clip、shadow、xray source/target 和 stacking epoch；
- sample geometry 可安全 union、union 面积过大、非连续 stacking 和中间插入其他 element；
- edge reveal、close frozen regions、fallback；
- capture area、capture 次数、blur pass、GPU p95/p99；
- 像素 golden 检查 halo、裁剪、折射和 stacking。

### No-go 结果

若可合并区域少、union capture 面积反而更大或 shader 才是瓶颈，提交 no-go 数据并关闭任务。不得为了完成路线图而制造 batch abstraction。

### 独立审查必须回答

1. batch identity 是否完整覆盖 renderer/target/namespace/scale/transform/kernel/xray，并将 sample compatibility 与 stacking 约束作为硬门？
2. union capture 是否在真实场景减少总成本？
3. shadow、clip、halo 和 damage 是否像素正确？
4. 是否存在长期 legacy fallback 或新协议接口？

---

## 24. 全局回归矩阵

每个任务只运行与自身相关的矩阵子集，但 R09、R14 和所有性能任务完成时必须重跑整表的自动化可覆盖部分。

| 维度 | 必测值 | 关键断言 |
| --- | --- | --- |
| layout | scrolling / floating / tabbed / no-output | 状态、位置、focus、overlay owner |
| expanded state | normal / pending maximize / committed maximize / fullscreen+maximized / unmaximizing | desired、committed、visual FSM 不混淆 |
| lifecycle | open / minimize / restore / reverse / target close / non-target close | 逐帧可见或显式暂停/取消、最终清理 |
| focus | 当前 / 同列 tab / 其他列 / 其他 workspace / 其他 output | viewport、target priority、floating visibility |
| invocation | foreign / IPC / xdg | 同一内部 command 与结果 |
| anchor | current / wrong output / stale source / missing / empty / two writers | 精确选择、降级和清理 |
| output | 1 屏 / 2 屏异分辨率 / hotplug / move window / move workspace | ownership 与 redraw 完整 |
| scale/transform | 1 / 1.25 / 2 / 90° / 270° | 只 round 一次、终点一致 |
| client timing | immediate ack / timeout / late commit / old serial / unrelated commit | FSM 只由目标事件推进 |
| renderer | available / unavailable / shader failure / context reset | fallback 可见、资源无泄漏 |
| render target | Output / Screencast / blocked-out / xray | snapshot variant 与背景正确 |
| glass | protocol/fallback / 1,7,32 regions / static,dynamic | plan、wire diff、damage、GPU |
| motion | normal / reduced / fast reverse / 10 concurrent | 无跳变、无无限 ongoing |
| resource lifecycle | map/unmap/remap/destroy/disconnect | owner 清理、纹理释放、无 UAF |

测试断言不得只看最终 bool。至少按任务需要检查：

- controller/FSM 当前状态；
- render element 分类和 identity；
- animation progress 与 visibility decision；
- typed 坐标转换后的数值；
- configure/ack/commit serial；
- anchor source/output/generation；
- redraw output/reason；
- texture bytes 和释放时刻；
- protocol request/commit/capture 计数。

---

## 25. 验证命令分层

具体命令应以任务开始时仓库实际 target 和 feature 为准，不能把无法启动的环境问题写成测试通过。最低分层如下。

### 25.1 每个 niri 任务

```text
(cd niri && cargo fmt --all -- --check)
(cd niri && cargo test -p niri <本任务定向测试> -- --nocapture)
(cd niri && cargo test -p niri <受影响模块测试>)
(cd niri && cargo test -p niri-config <配置相关任务>)
(cd niri && cargo test -p niri-ipc <IPC/身份相关任务>)
```

高风险 ownership 任务在可用环境中再运行完整 `cargo test -p niri`。若 headless fixture、GPU 或临时目录不可用，必须记录“未运行及原因”，不能把已有旧二进制结果当成当前 diff 的通过结果。

### 25.2 每个 Quickshell 任务

```text
(cd quickshell && cmake --build build-tahoe)
(cd quickshell && ctest --test-dir build-tahoe --output-on-failure -R '<相关正则>')
```

identifier 与 Tahoe glass 任务必须包含 native 单元测试和与当前 niri 的跨进程测试；只做 QML 静态字符串检查不足以完成。

### 25.3 每个 Tahoe Shell 任务

```text
(cd tahoe-shell && pytest <本任务定向测试>)
(cd tahoe-shell && pytest tests/test_window_model.py tests/test_windows_workspace_events.py)
(cd tahoe-shell && qmltestrunner <相关 Qt Quick 测试，若构建环境提供>)
```

涉及 rectangle/identifier 的任务必须观察 compositor 接收结果；涉及 glass 的任务必须同时验证 protocol available 与 fallback。

### 25.4 文档与 Git

作者验证阶段：

```text
git diff --check
git diff --no-index --check /dev/null <本任务的未跟踪新文件>
git status --short --untracked-files=all
git diff --submodule=log
git add -- <仅本任务路径>
git diff --cached --check -- <本任务路径>
git diff --cached --name-status
git write-tree
```

对未跟踪新文件，`git diff --check` 本身看不到内容，必须追加 `--no-index` 检查。该命令在“文件确实不同但无 whitespace error”时也会返回 1；此步验收的是无 whitespace-error 诊断，不得将“有 diff”误报为格式失败。随后只 stage 本任务路径，以必须返回 0 的 `git diff --cached --check` 作门禁，并把 staged name-status、blob/tree、子模块 staged tree 和基线 gitlink 写入审查 manifest。独立审查只读这个冻结 snapshot；普通任务在 `FINAL PASS` 前不得 commit，之后不得再改 index 或内容。跨子模块任务严格执行第 1.2 节的两阶段门禁：内容 `FINAL PASS` 后唯一允许的新索引状态是已审子模块 commit 对应的外层 gitlink，且它只用于冻结新的 outer tree 并接受全新集成审查，不能直接提交。

每个 `FINAL PASS` 对应提交后的封装验证（普通任务在外层仓库执行；跨子模块任务先分别在子模块执行内容阶段验证，再在外层执行集成阶段验证）：

```text
git diff --cached --quiet
git show -s --format=%T HEAD
<核对 commit tree / 子模块 commit tree / 外层非-gitlink blobs 与 reviewed manifest>
```

push 后的远端验证（外层和每个被修改子模块分别在自己的仓库执行）：

```text
git fetch origin
git rev-parse HEAD
git rev-parse origin/<branch>
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/<branch>)"
```

`git fetch origin` 不带命令行 branch refspec，以便使用配置的 `remote.origin.fetch` 更新 remote-tracking refs；若仓库没有预期 refspec，必须改用显式 `+refs/heads/<branch>:refs/remotes/origin/<branch>`，不能只 fetch 到 `FETCH_HEAD` 后核对陈旧的 `origin/<branch>`。

---

## 26. 独立审查通用清单

每个任务的独立审查除专属问题外，必须逐项给出结论：

1. **范围**：diff 是否只包含本任务，是否夹带下一任务准备或无关清理？
2. **源码事实**：实现是否与当前调用链、状态和资源生命周期一致？
3. **唯一 ownership**：新 owner 是谁；旧 owner 是否全部删除？
4. **平行接口**：是否存在新旧生产路径、永久 fallback、第二模型或第二 schema？
5. **行为保持**：第 1.4 节相关契约是否有测试？
6. **失败路径**：renderer 失败、stale source、disconnect、teardown、timeout、reverse 是否闭合？
7. **测试质量**：测试是否先能抓住旧问题，是否断言逐帧/逐事件而非最终状态？
8. **性能证据**：性能任务是否同场景前后对比，门槛是否预先固定？
9. **静态删除证明**：检索结果是否逐条解释，不能只说“grep 通过”？
10. **Git 边界**：子模块提交、外层指针和目标远端是否正确？

审查输出按严重度列 findings；只有“阻塞/中等/低均无”并明确写出 `FINAL PASS` 才通过。

---

## 27. 每任务执行记录模板

未来实施时，在同目录维护串行执行记录。版本化记录是待审 diff 的一部分，与实现同一提交；它只能包含独立审查开始前已经确定的证据。不得在 `FINAL PASS` 后再修改该文件补录结果，否则已通过审查的 tree 已变，必须重新审查。

版本化记录模板：

```text
任务：Rxx / 名称
待审状态：Author verification complete | No-go proposed | Blocked
开始基线：外层 / niri / quickshell hash
范围：实际修改文件和 owner
行为契约：本任务适用项
旧路径删除：检索命令、完整剩余命中及解释
测试：命令、结果、未运行项及原因
性能：硬件、场景、前测、后测、阈值
```

最终文件 stage 后，作者在独立审查请求中附上审查 manifest，而不是把它写回版本化记录：外层 staged diff/blob 清单、每个被改子模块的 staged diff 与 `git write-tree` 值、未跟踪文件清单及基线 gitlinks。审查者必须在输出中复述核验后的 manifest 和 `FINAL PASS`；任何后续内容变化都使 PASS 失效。跨子模块任务的内容审查 manifest 与集成审查 manifest 必须分别保存：前者冻结子模块 tree 和外层非 gitlink blob，后者冻结已推送子模块 commit/gitlink 映射及最终 outer tree；第一次 `FINAL PASS` 不能授权外层提交。

`FINAL PASS` 后，commit message trailers 只记录提交前已知的审查会话标识、审查结果和 reviewed manifest/tree 标识；当次交付回执再记录子模块/外层 commit hash、push 结果、fetch 后远端 hash、最终工作树状态及“允许开始 Rxx+1”。这些信息不回写到已审文件。对普通任务，commit tree 必须与 reviewed outer staged tree 相同。对跨子模块任务，子模块 commit 分别记录内容审查标识且 tree 等于其 reviewed staged tree；外层 commit 记录内容审查与集成审查标识且 tree 等于集成审查的 reviewed outer tree。外层新 gitlink 必须指向已核对的子模块 commit，外层非 gitlink blobs 必须与内容审查 manifest 相同。commit 无法在自身 tree 中记录自身 hash，push 前也不可能已知远端核对结果；不得为填满这些字段再造一个“记录提交”。任一 tree/blob/gitlink 不匹配都使对应提交无效并回到第 1.2 节规定的审查阶段。

Blocked 只能用于确实需要新协议授权、外部环境或用户决策的情况；不能通过先做下一任务绕过 blocker。

---

## 28. 预期收益与停止条件

完成 R00-R11 后，应达到：

- 用户报告的最大化后 minimize/restore 动画丢失机制被逐帧测试覆盖并修复；
- lifecycle request、动画状态、render policy 和坐标各有单一 owner；
- floating/scrolling 不再需要同步修改两份状态机；
- 跨 workspace/output 不再遗忘 expanded intent；
- Shell 窗口身份不再依赖 appId/title 猜测。

完成 R12-R14 后，应达到：

- blur kernel 可按 material 选择，不再天然“一改全改”；
- compositor 默认值只有一个可编辑真源；
- renderer 消费 immutable plan，client batching/redraw 也各只有一个 owner。

R15-R19 的停止条件不是“所有想法都实现”，而是：

- 已证实热点得到可测改善且无视觉/正确性回归；或
- 数据证明收益不足，提交 no-go 证据，不制造无用 abstraction。

路线图全部完成后，再评估 `scrolling.rs` 余下职责、其余 `queue_redraw_all()` 和更广泛 renderer 优化。不得在本路线图尚未完成时并行启动这些外围重构。
