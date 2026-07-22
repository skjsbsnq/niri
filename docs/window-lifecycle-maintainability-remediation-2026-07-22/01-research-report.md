# 01 · 源码研究报告：窗口生命周期、动画回归、玻璃耦合与可维护性

日期：2026-07-22
性质：只读源码审计结论；本文件不代表已经实施修复。
外层仓库基线：`main` / `44fe0e6`
`niri` 子模块基线：`tahoe-layer-animations` / `a7b88a0c`
审计范围：`niri/`、`tahoe-shell/`，以及两者之间的 Wayland foreign-toplevel、IPC、Dock rectangle 和 Tahoe glass 链路。

---

## 0. 研究约束与结论等级

本轮优先相信当前源码，不以历史设计文档作为事实依据。研究期间未修改产品代码，也未进行真实 Tahoe 桌面交互复现；因此本文严格区分三类结论：

- **确定缺陷**：从状态创建、数据传递、渲染门控到清理均已在源码中形成闭环，不依赖运行时猜测。
- **高风险设计**：源码已证明存在竞态、覆盖或语义分叉，但具体出现频率仍依赖事件顺序、客户端行为或多显示器环境。
- **优化机会**：当前行为可以正确工作，但结构或成本会放大后续回归概率。

行号以基线提交为准。后续实施若改变代码，应在每个任务的验收记录中更新引用，不应静默沿用过期行号。

---

## 1. 一句话结论

项目仍有显著的正确性、可维护性和性能优化空间。最需要优先处理的不是局部动画参数，而是下列四个系统边界：

1. 最大化转换与窗口生命周期动画共享渲染层，却没有共享状态不变量；
2. 输出本地坐标、工作区坐标和全局坐标都使用裸 `Rectangle<Logical>`；
3. foreign-toplevel、IPC、xdg-shell 分别拥有最小化/恢复入口，行为并不等价；
4. 全局 blur kernel、Tahoe material 和 Shell 侧材质默认值存在多份真相源。

用户报告的“最大化后切到其他应用，再最小化时动画消失”已有一个确定的危险机制：只要最小化发生时 `maximize_transition` 仍为 ongoing，动画可以成功进入活跃容器，但排他渲染不会把它加入 render list；动画时钟仍在后台推进。源码由此能确定重叠时段会丢失可见动画进度，但不能单凭静态路径断言 transition 一定持续到整段动画过期。切换到不同列会启动视口运动，而视口静止是最大化转换的结算条件之一，因此可能延长屏蔽窗口；同列激活则不会启动该运动。现场是否恰好遮住整段动画，以及普通 Activated configure/commit 的精确作用，仍需 render-list 测试和运行时 trace。

---

## 2. 当前窗口生命周期链路

### 2.1 Dock / foreign-toplevel 路径

```text
WindowButton / DockMinimizedWindow
  → toplevel.setRectangle(source layer surface, output-local rect)
  → ForeignToplevelHandler::set_rectangle
  → Mapped.foreign_toplevel_rect = Some { source, output, rect }
  → foreign-toplevel set_minimized / unset_minimized
  → minimize_window_with_animation / restore_window_with_animation
  → workspace output 校验
  → floating 或 scrolling snapshot
  → MinimizeWindowAnimation
  → Genie shader 或 alpha/scale fallback
```

主要源码：

- `tahoe-shell/components/WindowButton.qml:94-200`
- `tahoe-shell/components/DockMinimizedWindow.qml:75-136`
- `niri/src/handlers/mod.rs:618-708`
- `niri/src/niri.rs:2165-2265`
- `niri/src/layout/workspace.rs:803-875`
- `niri/src/layout/minimize_window_animation.rs:300-408`

### 2.2 IPC 路径

```text
niri msg action minimize-window / restore-window
  → Action::MinimizeWindow(ById) / RestoreWindowById
  → minimize_window_with_animation(window, None)
    或 restore_window_with_animation(window, None)
  → 不读取 Mapped.foreign_toplevel_rect
```

主要源码：

- `tahoe-shell/services/Windows.qml:261-289`
- `niri/src/input/mod.rs:838-865`
- `niri/src/niri.rs:2237-2244`

### 2.3 最大化转换

```text
set_maximized(true)
  → 创建 MaximizeTransition
  → maximizing_window_location() 返回目标窗口
  → 只渲染目标列/目标 tile
  → 同时禁止 closing/minimize/restore overlays
  → finish_maximize_transition_if_settled()
```

主要源码：

- `niri/src/layout/scrolling.rs:3343-3390`
- `niri/src/layout/scrolling.rs:3423-3487`
- `niri/src/layout/scrolling.rs:3498-3545`

---

## 3. 确定缺陷 F01：最大化转换屏蔽生命周期动画但不暂停其时钟

严重度：**P0**
置信度：**确定存在重叠期间的可见进度丢失；“整段动画完全不可见并过期”仍需运行时证明**
影响：scrolling workspace 中的最小化、恢复，以及最大化目标之外窗口的关闭动画；并会临时隐藏 floating 层。关闭最大化目标自身通常会先取消该 transition，不应与非目标窗口混为一谈。

### 3.1 证据闭环

最大化请求会建立 `maximize_transition`：

- 字段：`niri/src/layout/scrolling.rs:80`
- 创建：`niri/src/layout/scrolling.rs:3343-3390`

渲染阶段只要转换仍被认为 ongoing，就完全不 push 三类生命周期元素：

- closing windows
- minimize animations
- restore animations

证据：`niri/src/layout/scrolling.rs:3498-3517`。

但是动画推进和清理不受这个门控影响：

- `closing.advance_animations()`
- `minimize.advance_animations()`
- `restore.advance_animations()`
- 动画结束后由 `retain_mut` 删除

证据：`niri/src/layout/scrolling.rs:448-466`。

因此源码确定的生命周期是：

```text
动画已创建
  → 被最大化排他渲染挡住
  → 后台继续计时
  → transition 若先结算，只能从已经推进的位置开始显示
  → transition 若遮挡超过剩余时长，动画到期删除而始终不可见
```

第一条结果已由静态控制流确定；第二条结果取决于 transition 结算与动画时长的相对顺序，是对用户现场最直接的解释候选，而不是尚未测量时序下的必然结论。

最小化不会终止最大化转换。`set_minimized()` 会维护 minimize/restore 容器、焦点和 tile 可见性，但没有处理 `maximize_transition`：`niri/src/layout/scrolling.rs:1586-1675`。

工作区上层也没有补画这些动画。相反，最大化转换 ongoing 时 floating 层会被整体判定为不可见：`niri/src/layout/workspace.rs:1854-1863`。

关闭动画需要区分目标与非目标。移除最大化目标 tile 或包含它的整列时，会先清除对应 `maximize_transition`：`niri/src/layout/scrolling.rs:1162-1173,1283-1289`。因此确定受门控影响的是最大化转换期间其他窗口的 closing overlay；目标自身关闭通常不走同一吞帧链路。

### 3.2 回归引入点

当前 `niri` HEAD `a7b88a0c`（`fix(layout): make maximize transition target-exclusive`）引入了：

- `MaximizeTransition`；
- 目标列/目标 tile 排他显示；
- 对 lifecycle overlay 的统一 `if !maximize_transition` 门控；
- 超时及迟到 commit 重新进入转换的测试。

提交意图是防止最大化 resize shader 的透明像素漏出其他窗口，但当前实现扩大了排他范围，把本应位于普通 live tile 之上的生命周期 overlay 一并屏蔽。

### 3.3 修复必须维护的不变量

后续修复不能只为 minimize 增加特例。正确的不变量应是：

> 任何已经进入活跃容器的 lifecycle animation，必须满足“正在渲染、明确暂停、或明确取消”之一；不允许不可见地推进并过期。

最大化转换可以过滤普通 live tiles，但不应无条件过滤 closing/minimize/restore overlays。若某个 overlay 与最大化目标确实冲突，应通过显式 ownership 和取消语义解决，而不是靠 render list 静默丢弃。

---

## 4. 待证风险 F02：transition 自身没有 request identity，跨请求时序缺少生产级测试

严重度：**P1 候选**
置信度：**确定存在 transition 级身份缺口，但尚未证明普通焦点 commit 会造成错误 epoch；必须先补生产 serial 测试**。

### 4.1 超时并未销毁状态

`finish_maximize_transition_if_settled()` 在客户端一秒内没有 commit 时，只执行：

```rust
transition.timed_out = true;
```

没有删除 transition。证据：`niri/src/layout/scrolling.rs:3449-3487`。

`timed_out=true` 只让 `maximizing_window_location()` 暂时返回 `None`，因此排他渲染暂时解除；旧 transition record 仍然留在对象中。

### 4.2 重要反证：窗口 committed maximized 状态已经按 serial 跟踪

不能把 `MaximizeTransition` 自身没有 serial，直接推导成“任何普通 commit 都可以无条件复活旧转换”。生产链路还有一层报告必须保留的 serial 语义：

- compositor 从 `ToplevelCachedState.current().last_acked.serial` 取得 commit serial，再调用 layout update：`niri/src/handlers/compositor.rs:333-356`；
- scrolling 在判断 `committed_maximize` 前，先调用 `tile.window_mut().on_commit(serial)`：`niri/src/layout/scrolling.rs:1390-1402`；
- `Mapped` 发送 configure 时，将 maximized 状态与 serial 存入 `uncommitted_maximized`：`niri/src/window/mapped.rs:1203-1213`；
- commit 只会应用 serial 不晚于 `commit_serial` 的 maximized 状态：`niri/src/window/mapped.rs:1452-1486`。

因此后续 `column.tiles[tile_idx].sizing_mode().is_maximized()` 不是一个完全脱离 configure serial 的裸 bool。焦点变化产生的较新 Activated configure 使用累积 xdg-toplevel state；客户端 ack 并 commit 它时，也承诺此前仍有效的 Maximized 状态。该行为本身不能被称为 epoch 混淆。

### 4.3 已知行为与仍需验证的风险

如果窗口层在 serial 语义下已经进入 committed maximized，layout 会把保留的 transition 重新标记为 committed/非超时：

```rust
transition.committed = true;
transition.timed_out = false;
```

证据：`niri/src/layout/scrolling.rs:1535-1540`。

这可以被解释为：一秒超时只临时解除排他显示，迟到但有效的最大化 commit 到达后继续完成视觉转换。当前源码不足以将这个设计本身定为 P0 bug。

真正仍需验证的是跨请求穿越，例如：

- `maximize A → unmaximize B → maximize C` 快速连续请求；
- 第一次 maximize 的迟到 commit 在第三次 transition 存在时到达；
- window 层 serial 状态合法地暂时变为 maximized，但 layout transition 实际属于更新的请求 C。

`MaximizeTransition` 只保存 window、started_at、committed、timed_out，没有自己的 request identity，因此上述交错是否会误认仍值得测试；但必须用真实 `Mapped`、configure、ack、commit serial 证明，不能依靠 layout mock 推断。

现有 `maximize_transition_times_out_and_restarts_on_late_commit` 测试位于 `niri/src/layout/tests.rs:3947-3971`，但测试 `LayoutElement::on_commit()` 是空实现，`Op::Communicate` 也带有 `FIXME: serial` 并传 `None`：`niri/src/layout/tests.rs:288,1459-1471`。它能验证 layout 的排他行为，不能证明生产 serial 存在 epoch bug。

### 4.4 处理边界

先补集成测试和 trace，再决定是否需要修改。若跨请求误认得到证实，应让 transition identity 复用现有 configure/commit serial 语义，而不是在 layout 旁边再建一套平行 serial 状态机。可能需要的状态仍包括：

- 能与目标请求关联的现有 serial 或派生 generation；
- 明确的 `Pending → Committed → Settling → Finished/Cancelled/TimedOut` 状态；
- 新请求替换旧 transition 的显式规则；
- 超时是“仅解除排他显示”还是“终止整个 transition”的明确契约。

普通焦点 commit 不应被当作默认 bug 修复对象；F01 的 lifecycle overlay 不变量必须独立修复，不能依赖改变迟到 commit 语义来碰巧缩短遮挡时间。

---

## 5. 确定缺陷 F03：Genie 动画混用 output-local 与 workspace 坐标

严重度：**P0**
置信度：**确定**
影响：scrolling layout；视口横移越大越明显。

### 5.1 rectangle 的来源坐标

foreign-toplevel `set_rectangle` 接收相对于 Dock layer surface 的坐标。compositor 查找 layer 所属输出，并加上 layer geometry，最终保存为该输出的本地逻辑坐标：`niri/src/handlers/mod.rs:672-708`。

存储类型仍是普通 `Rectangle<i32, Logical>`，只通过旁边的 `output` 字段表达语义：`niri/src/window/mapped.rs:111-112`。

### 5.2 scrolling 快照位置被转换成 workspace 坐标

`tiles_with_render_positions_mut(false)` 返回的 tile position 已包含 `-view_pos`：`niri/src/layout/scrolling.rs:2870-2889`。

最小化和恢复在捕获 snapshot 后又执行：

```rust
tile_pos.x += view_pos;
```

证据：

- minimize：`niri/src/layout/scrolling.rs:1700-1724`
- restore：`niri/src/layout/scrolling.rs:1776-1807`

这把窗口起点转换回 scrolling workspace 内容坐标。

### 5.3 shader 把两者当成同一坐标系

`MinimizeWindowAnimation::render_genie()` 直接用：

- `self.pos + offset` 构造 `window_rect`；
- 原样传入 `target_rect`；
- 用两者的 union 构造 `genie_area`；
- 最后只对整个 area 减一次当前 `view_rect.loc`。

证据：`niri/src/layout/minimize_window_animation.rs:362-407`。

数值例：

```text
当前 view_pos = 1000
窗口屏幕位置 x = 100
Dock 图标输出本地 x = 900

窗口进入动画前被存成 workspace x = 1100
Dock target 仍为 output-local x = 900

渲染时整个 area 减 view_pos：
窗口回到 x = 100（正确）
Dock 变成 x = -100（错误，可能完全离屏）
```

这解释了为何普通位置偶尔正常，而最大化、激活其他列或大幅横向滚动后更容易表现为“动画消失”。

### 5.4 所需设计

禁止继续依靠变量名区分坐标。建议使用 newtype 或带空间参数的类型：

- `OutputLocalRect`
- `WorkspaceRect`
- `GlobalRect`
- 必要时 `SurfaceLocalRect`

转换必须要求显式的 output/workspace context。Genie 内部只接受一种规范坐标，例如 output-local；snapshot 起点和 Dock anchor 在进入动画对象前统一转换。

---

## 6. 正确性缺陷 F04：IPC 与 foreign-toplevel 生命周期入口语义不等价

严重度：**P1**
置信度：**确定**。

Tahoe Shell 的 `Windows.qml` 优先使用 `window.toplevel`：

- minimize：`tahoe-shell/services/Windows.qml:261-273`
- restore：`tahoe-shell/services/Windows.qml:275-289`

只有模型没有成功关联 foreign-toplevel 时才退化到 IPC action。

foreign-toplevel handler 会读取 `Mapped.foreign_toplevel_rect` 并传给动画：`niri/src/handlers/mod.rs:618-639`。

IPC handler 则固定传 `None`，即使同一个 `Mapped` 已缓存 rectangle：`niri/src/input/mod.rs:838-865`。

恢复路径收到 `source_rect=None` 时，在 renderer snapshot 之前直接执行普通 `layout.restore_window()`：`niri/src/niri.rs:2237-2244`。这意味着没有 Dock→窗口的 Genie restore，只能由 layout 的 alpha/scale fallback 承担。

结果是同一用户意图因入口不同产生不同动画：

| 入口 | 读取缓存 anchor | Genie minimize | Genie restore |
| --- | --- | --- | --- |
| foreign-toplevel | 是 | 可用 | 可用 |
| IPC | 否 | 无 target 或退化 | 直接绕过 snapshot |
| xdg-toplevel app request | 取决于 foreign rect | 可用 | 不适用/依入口 |

后续不应新增第四条“带 rectangle 的 IPC”平行接口。应收敛为一个 compositor 内部 lifecycle command，所有协议入口只负责解析窗口和可选显式 anchor，缓存选择、snapshot、状态变更和动画策略由同一实现完成。

---

## 7. 高风险设计 F05：多输出 Dock 最后写入覆盖

严重度：**P1**
置信度：**强证据；需双屏运行验证事件顺序**。

`shell.qml` 在 `Variants { model: Quickshell.screens }` 内为每块屏幕实例化一个 Dock：`tahoe-shell/shell.qml:793-1004`。

每个 Dock 都直接使用全局列表：

- `niriService.windowList`
- `nonMinimizedWindowList`
- `minimizedWindowList`

证据：

- `tahoe-shell/components/Dock.qml:35-43`
- `tahoe-shell/components/Dock.qml:1523-1537`
- `tahoe-shell/components/DockMinimizedShelf.qml:20-23,58-61`

没有按 `window.output` 过滤，因此同一个窗口在每个输出上都有按钮/缩略图 delegate，每个 delegate 都可能发布自己的 Dock rectangle。

niri 每窗口只保存一个 `foreign_toplevel_rect: Option<...>`：`niri/src/window/mapped.rs:111-112,402-407`。后写入者覆盖先写入者，没有按 output 建表。

动画入口会校验 rectangle output 是否等于窗口 workspace 当前输出；不相等就丢弃 anchor：

- minimize：`niri/src/layout/workspace.rs:812-815`
- restore：`niri/src/layout/workspace.rs:861-864`

因此双屏下最后一次 QML 几何更新若来自另一块屏幕，动画会退化或失去目标。

正确方向不是在 niri 内“猜最后一个正确写入”。应同时明确：

1. Shell 的 Dock ownership：按钮是否只存在于窗口所属输出；
2. compositor 的 anchor ownership：若产品需要每屏都显示窗口，应按 output 保存 anchor，并在执行时选择当前输出对应项。

---

## 8. 高风险设计 F06：Dock rectangle 生命周期与视觉几何不同步

严重度：**P1–P2**。

### 8.1 WindowButton 缺少实际视觉属性监听

`WindowButton.updateDockRectangle()` 用 `icon.mapToItem()` 计算目标，理论上包含 scale/push/bounce 后的视觉边界：`tahoe-shell/components/WindowButton.qml:94-130`。

但更新触发只监听 x/y/width/height、iconSize、窗口模型、祖先 scene offset 和 fullscreen offset：`WindowButton.qml:179-200`。没有监听实际动画中的：

- `magnification`
- `pushX`
- `bounceOffset`

因此应用自己从窗口按钮发起 `xdg_toplevel.set_minimized` 时，compositor 可能只持有波形动画之前的旧 rectangle。

### 8.2 最小化缩略图只在点击恢复时发布

`DockMinimizedWindow.updateDockRectangle()` 存在，但只由 `restoreWindow()` 调用：`tahoe-shell/components/DockMinimizedWindow.qml:75-105`。

`Component.onCompleted` 和模型变化只刷新 thumbnail，没有发布 rectangle：`DockMinimizedWindow.qml:134-142`。因此：

- 外部 restore；
- 搜索/概览 restore；
- Dock 布局移动后 restore；

都可能使用旧位置。

### 8.3 一次发布失败会清空旧值

`ForeignToplevelHandler::set_rectangle()` 找不到已映射 source layer 时，会直接清空现有 rectangle：`niri/src/handlers/mod.rs:689-699`。没有确认、generation 或重试机制。

Dock layer unmap/destroy 同样清除所有由该 source 发布的 rectangle：`niri/src/handlers/layer_shell.rs:55-58,223-227`。这是合理的资源清理，但 Shell 必须在 remap 后可靠重发；当前链路缺少 compositor acknowledgement。现有 Rust 集成测试已经验证已映射 layer 的 output/坐标转换、minimize/restore 后持久性、无效 source、空尺寸以及 layer destroy 清理：`niri/src/tests/foreign_toplevel.rs:25-99`。现有 Qt Quick 测试还验证祖先移动后的最终坐标、发布先于模拟外部 minimize，以及 fullscreen 发布门控：`tahoe-shell/tests/tst_window_button_rectangle_tracking.qml:75-118`。缺口应准确限定为 magnification/push/bounce 的逐帧几何、source 尚未映射时发布、layer remap 后 Shell 是否可靠重发，以及 compositor 实际接收结果的跨进程时序。

---

## 9. 高风险设计 F07：Shell 未消费 niri 已发布的稳定 identifier

严重度：**P1**
影响：rectangle、激活、最小化、缩略图和 output ownership 都可能绑定错误窗口。

`WindowModel.mergeWindowModels()` 逐个 IPC window 在线性 foreign-toplevel 列表中查找，整体最坏 O(n²)：`tahoe-shell/services/windows/WindowModel.js:25-50`。

匹配规则依次是：

1. 规范化后的 `appId + title`；
2. 仅 `appId`；
3. 无匹配时生成 IPC-only 或 toplevel-only model。

证据：`WindowModel.js:53-92`。

动态标题、同应用多个窗口、标题相同、客户端 appId 不稳定时都可能错配。测试 fixture 覆盖了部分输入形态，但 Shell 当前合并路径没有使用已存在的稳定身份。

niri 已经完成 compositor 侧身份发布：`MappedId::to_protocol_identifier()` 使用与 IPC window id 相同的十进制表示，源码注释明确说明它用于关联 foreign-toplevel 与 IPC：`niri/src/window/mapped.rs:234-249`；该值通过 `ext_foreign_toplevel_handle_v1.identifier` 发布：`niri/src/protocols/foreign_toplevel.rs:340-355`。

正确方向是让 Shell/Quickshell 消费现有 ext-foreign-toplevel identifier，并将它关联到当前用于 activate/minimize/rectangle 的 wlr-management handle。实施前先确认当前 Quickshell API 是否已经暴露 identifier；若未暴露，应在现有 ext-list/wlr-management 模型中补消费或桥接能力。不得新增 compositor window-id 协议、foreign-toplevel-v2 或另一套稳定 ID。

迁移完成后 Shell 按 id map 做 O(n) 合并。不得长期保留“id 精确匹配 + appId/title 模糊匹配”两套正常路径；模糊匹配只能是有监控、有删除期限的兼容阶段，并需单独任务完成退出。

---

## 10. “从最大化还原到普通窗口”的独立动画缺口

严重度：**P1 候选**
置信度：**源码存在缺口，但尚未证明是用户现场唯一根因**。

窗口 maximize/unmaximize resize 动画依赖如下链路：

```text
request_size(..., animate=true)
  → 若 pending size 改变，animate_next_configure=true
  → send_pending_configure() 把 serial 放入 animate_serials
  → 对应 commit 前保存 snapshot
  → Tile::update_window() 建立 ResizeAnimation
```

关键问题是 `request_size()` 仅在 `state.size` 改变时设置 `animate_next_configure`：`niri/src/window/mapped.rs:832-858`。Maximized state 本身即使变化，若请求尺寸恰好相同，也只触发 configure，不会标记动画。

此外 `Tile::update_window()` 计算 snapshot 与新尺寸差值，低于 `RESIZE_ANIMATION_THRESHOLD` 时会直接清除 resize animation：`niri/src/layout/tile.rs:390-425`。

因此以下场景可能没有可见还原动画：

- 最大化前窗口已接近 working area 大小；
- unmaximize 只改变状态、圆角、边框或 expanded progress，尺寸没有显著变化；
- 客户端 commit 时序让可动画 snapshot 没有建立。

这一项需要在实施前增加 serial/configure/commit trace 与真实复现，不能直接照搬最小化动画的修法。

---

## 11. 玻璃与模糊：为何改一处会影响其他表面

严重度：**结构性 P1**
置信度：**确定**。

### 11.1 当前配置模型

全局 `Blur` 只维护一份 kernel 和通用后处理参数：

- `off`
- `passes`
- `offset`
- `noise`
- `saturation`

证据：`niri/niri-config/src/appearance.rs:1009-1055`。

Tahoe material 拥有 background effect 和 shadow，可以单独设置 tint、contrast、refraction、noise、saturation 等，但没有自己的 blur passes/offset kernel：`niri/niri-config/src/tahoe_glass.rs:8-61`。

所有 mapped window 和 layer surface 都复制相同全局 blur：

- window：`niri/src/window/mapped.rs:123-124,311,669-670`
- layer：`niri/src/layer/mapped.rs:58-62,147-164`

Tahoe region 渲染同样调用 `background_effect.update_config(blur_config)`：`niri/src/render_helpers/tahoe_glass.rs:315-351`。真正的 passes/offset、fallback noise/saturation 最终从全局 `blur_config` 解析：`niri/src/render_helpers/background_effect.rs:249-260`。

所以修改全局 passes/offset 会同时改变普通窗口、panel、Dock、toast 等所有使用 blur 的表面。这是数据模型的直接结果，不是偶发缓存污染。

### 11.2 多份默认值

玻璃默认值还分散在：

- Rust material 默认：`niri/niri-config/src/tahoe_glass.rs:79-117`
- 生产 KDL：`config/niri/tahoe-phase0.kdl`
- Shell JS：`tahoe-shell/components/TahoeGlass.js`
- 设置服务：`tahoe-shell/services/niri_settings_tool.py`
- 设置 QML：`tahoe-shell/services/NiriSettings.qml`

部分测试通过读取源码和正则保证同步。这能发现漂移，却没有消除多份真相源；增加新 material 或参数时仍容易遗漏一个消费者。

### 11.3 所需设计

建议引入单一 schema 和解析结果：

```text
GlassMaterialId
  → ResolvedGlassMaterial {
      blur_kernel: BlurKernelId / ResolvedBlurKernel,
      background_effect,
      shadow,
      fallback_policy
    }
```

约束：

- named blur kernels，而不是所有 material 隐式继承同一个 kernel；
- 每个 material 解析后是完整不可变值；
- 继承只发生在配置解析阶段，渲染阶段不再临时 fallback；
- Shell 与设置界面的默认值从同一 schema 生成；
- 不创建一套“glass-v2”平行接口，原配置解析器应在同一模型中完成迁移。

---

## 12. Tahoe glass 协议与渲染成本

### 12.1 已有资源边界

协议不是完全无上限：

- 每个 surface 最多 32 regions：`MAX_REGIONS_PER_SURFACE`，见 `niri/src/protocols/tahoe_glass.rs:25,627-642`；
- region 必须完整位于 surface geometry 内；
- 所有 committed region 面积之和不能超过 surface 面积；
- 使用 checked add 防止坐标溢出。

验证位于 `niri/src/protocols/tahoe_glass.rs:382-431`。Tahoe global 还只向 `client_is_unrestricted` 客户端开放：`niri/src/niri.rs:2570-2571`。

因此当前结论不是“普通任意客户端可无限制造 GPU DoS”。

### 12.2 仍有优化空间

每个 region 都拥有独立的：

- `BackgroundEffect`
- `Shadow`
- renderer map entry

见 `niri/src/render_helpers/tahoe_glass.rs:23-32,237-258`。

非 xray region 会分别准备 sample geometry 并渲染 background effect：`tahoe_glass.rs:315-357`。相同 material/kernel 且采样区域相邻时，可合并 framebuffer capture 或建立共享 blur atlas，再分别裁剪/合成。

当前 region 差异计算和 renderer retain 都是嵌套线性查找：

- `changed_region_damage()`：`tahoe_glass.rs:93-115`
- `regions.retain(... regions.iter().any(...))`：`tahoe_glass.rs:233-235`

上限 32 使其不会无限增长，但每帧/每 commit 的结构仍可改为 id-indexed map，减少常数和复杂度。

---

## 13. 维护性热点

### 13.1 floating 与 scrolling 生命周期状态机重复

两套实现分别拥有：

- `take_minimize_animation`
- `take_restore_animation`
- `set_minimized`
- `minimize_with_snapshot`
- `start_minimize_animation_for_tile`
- `start_restore_animation_for_tile`

对应位置：

- `niri/src/layout/floating.rs:262-270,751-1075`
- `niri/src/layout/scrolling.rs:375-383,1586-1985`

两者又各自处理 active window、raise/column activation、interactive resize、反向播放、hidden-for-restore、失败恢复。历史上任何 lifecycle bug 都容易要求同时修改多处；漏掉其中一支就形成“改一处，另一处坏了”。

应该抽取共享 lifecycle controller，layout-specific 部分通过窄适配点提供：

- 查找/激活 tile；
- 捕获 snapshot 的位置和视口；
- 状态变更后的焦点策略；
- 动画 overlay 的最终放置。

不应保留原状态机并在旁边新增第二套 controller；迁移任务必须删除旧分支并用编译/grep 证据证明唯一 ownership。

### 13.2 `scrolling.rs` 职责过载

当前文件约 6274 行，同时承担：

- 列/窗口布局；
- focus 和 view movement；
- fullscreen/maximize；
- resize/move 动画；
- minimize/restore/close；
- render order；
- input gesture；
- transition settlement。

最大化排他渲染回归本质上来自“状态策略、动画时钟和 render ordering”散布在同一大对象的不同区域，缺少可检查的不变量。

局部重构是合理且必要的，但应按 ownership 拆分，而不是机械按文件长度拆：

- `MaximizeTransitionController`
- `LifecycleAnimationController`
- `ScrollingRenderPolicy`
- 类型化 coordinate conversion

### 13.3 状态以多个 bool 隐式组合

`MaximizeTransition` 当前使用 `committed`、`timed_out` 两个 bool 表达状态，允许语义模糊组合。窗口自身又同时存在 pending maximized、committed sizing mode、pending fullscreen、view movement、tile resize 等状态。

建议用 enum 和显式事件转换，禁止不可达组合。每个事件处理后运行 debug invariant；测试应直接断言 controller state，而不只断言最后可见 tile。

### 13.4 effect 配置与 runtime fallback 重叠

`BackgroundEffect` 同时保存 options、全局 blur 和 corner radius；render 时又修改 clip radius 并计算 fallback。`background_effect.rs:24-28` 的 corner radius 与调用侧参数形成双份状态，注释也承认 render 会重写。

应构造一次 `ResolvedEffectPlan`，把 kernel、可见几何、采样几何、clip、fallback 和材质参数作为不可变输入交给 renderer，减少 update 顺序依赖。

---

## 14. 性能优化空间

### 14.1 全局重绘过多

当前 `niri/src` 静态计数约有：

- `queue_redraw_all()`：182 处；
- `FIXME: granular`：109 处。

最小化、恢复、maximize foreign-toplevel 和 IPC handler 都会全输出重绘。多显示器和高刷新率下，应将事件映射到：

- 单个 output；
- 受影响 workspace；
- 必要时精确 damage region。

这项必须在正确性和 ownership 收敛后实施，否则过早缩小 redraw 可能掩盖未声明的跨输出依赖。

### 14.2 Genie 每帧分配

`render_genie()` 每帧重新创建：

- uniform 数组；
- `Rc`；
- 字符串 key；
- texture `HashMap`；
- 新 `ShaderRenderElement` identity。

证据：`niri/src/layout/minimize_window_animation.rs:383-407`。

可以缓存静态 binding、使用稳定 element id，只更新 progress 和几何 uniform。稳定 identity 也有利于 damage tracking。

### 14.3 大窗口 snapshot 显存与带宽

最大化 4K 窗口的 minimize/restore animation 可能同时保留普通 snapshot、blocked-out/xray 变体和 offscreen texture：`niri/src/layout/minimize_window_animation.rs:181-233`。

可评估：

- animation-only 降采样；
- texture pool；
- 只在实际使用 xray/blocked-out 时生成变体；
- 根据动画缩小进度动态选择 mip；
- 显存预算和失败时的一致 fallback。

### 14.4 窗口合并 O(n²)

消费现有 ext identifier 不仅修正确性，也可将 `WindowModel.js` 的 O(n²) 模糊匹配改成两个 id map 的 O(n) 合并。

---

## 15. 现有测试为何没有拦住问题

### 15.1 已有覆盖

本轮已运行并通过：

```text
cargo test -p niri maximizing_inactive_window_prioritizes_target_column -- --nocapture
cargo test -p niri foreign_toplevel_set_rectangle_tracks_layer_surface_rect -- --nocapture
pytest tests/test_window_button_rectangle_tracking_qml.py tests/test_window_model.py
```

结果：两项定向 Rust 测试通过；Python/QML 为 `6 passed, 6 subtests passed`。

### 15.2 覆盖断层

现有测试分别验证：

- 最大化时目标 tile 优先；
- rectangle 可以保存、清理且携带 output；
- QML 会在特定属性变化后调用 setRectangle；
- IPC/foreign 模型可在 fixture 中合并。

但没有一条测试串联：

```text
最大化 configure/transition
  → 超时或焦点切换
  → Dock rectangle ownership
  → minimize/restore snapshot
  → 实际 render element list
  → 动画时钟推进和清理
```

测试只检查 tile visibility，未检查 lifecycle overlay 是否进入 render list。`maximize_transition_times_out_and_restarts_on_late_commit` 还使用不跟踪 serial 的 mock，因此不能回答生产环境中跨 maximize 请求是否发生 epoch 误认。

### 15.3 必需的回归矩阵

后续测试至少覆盖：

| 维度 | 取值 |
| --- | --- |
| layout | scrolling / floating / tabbed |
| window state | normal / maximizing pending / maximized committed / unmaximizing |
| focus | 当前窗口 / 同工作区其他列 / 其他输出 |
| lifecycle | minimize / restore / target close / non-target close / reverse mid-flight |
| anchor | current output / wrong output / stale / missing |
| outputs | 单屏 / 双屏异分辨率 / 窗口跨输出移动 |
| client timing | 即时 ack / 超时 / 迟到 commit / unrelated commit |
| invocation | foreign-toplevel / IPC / xdg request |

关键断言不只包括最终状态，还包括：

- transition generation 和终态；
- overlay 在每一帧是否可渲染；
- hidden tile 最终是否恢复；
- animation clock 是否在不可见时暂停或取消；
- anchor 转换后的 output-local 数值；
- 双屏下选择的 anchor source/output；
- snapshot 分配失败时 fallback 是否仍可见。

---

## 16. 风险与优先级总表

| 编号 | 问题 | 等级 | 结论 | 首要处理 |
| --- | --- | --- | --- | --- |
| F01 | 最大化排他渲染屏蔽 lifecycle overlay、时钟却继续推进 | P0 | 重叠进度丢失确定；整段过期待运行确认 | 是 |
| F02 | transition 缺少 request identity 的跨请求风险 | P1 候选 | 待生产 serial 测试 | 先补观测 |
| F03 | output-local / workspace 坐标混用 | P0 | 确定缺陷 | 是 |
| F04 | IPC 与 foreign 生命周期行为不等价 | P1 | 确定缺陷 | 是 |
| F05 | 多输出 Dock 最后写入覆盖 | P1 | 强证据风险 | 是 |
| F06 | rectangle 发布时序和视觉几何陈旧 | P1–P2 | 强证据风险 | 是 |
| F07 | Shell 未消费现有 ext identifier，仍做模糊身份匹配 | P1 | 确定架构风险 | 是 |
| F08 | 状态变化但尺寸相同时 unmaximize 不动画 | P1 候选 | 待运行确认 | 先补观测 |
| M01 | floating/scrolling lifecycle 重复 | P1 | 维护性缺陷 | 是 |
| M02 | 全局 blur kernel 耦合所有 material | P1 | 维护性缺陷 | 是 |
| M03 | 多份 glass 默认值 | P2 | 维护性缺陷 | 是 |
| P01 | Tahoe region 独立采样 | P2 | 性能优化 | 后置 |
| P02 | 全局 redraw | P2 | 性能优化 | ownership 后实施 |
| P03 | Genie 每帧分配和大 snapshot | P2 | 性能优化 | 正确性后实施 |

---

## 17. 后续重构必须遵守的边界

1. **不做最小补丁堆叠**：允许围绕 ownership 做局部重构，修复必须覆盖同一不变量下的 minimize、restore、close 和 reverse，而不是只让单一复现路径通过。
2. **不得创建平行接口**：不新增第二套 lifecycle API、glass-v2、坐标 helper 旁路或长期双身份匹配。新 ownership 落地时必须迁移调用方并删除旧实现。
3. **保持原功能与表现能力**：最大化目标排他、透明 resize 防穿帮、floating/scrolling、tabbed、xray、blocked-out、reduced motion、多输出和所有现有协议入口都必须保留。
4. **严格串行**：一个任务完成验收、独立审查、commit、push 后，才能开始下一任务；不允许多个未验收重构同时堆在工作树。
5. **每任务可单独回滚**：一个任务对应一个清晰 ownership 变化和一个提交，不把无关清理混入。
6. **独立审查是硬门禁**：审查者必须读取 diff 和相关源码，检查平行接口、状态不变量、坐标转换、回归测试与范围；作者自查不能替代。
7. **运行证据与源码证据分开**：F08 等待确认项必须先增加观测和复现，不能按推测直接重写状态机。

详细任务拆分、依赖、验收命令、独立审查问题和提交门禁将在同目录的 `02-refactor-roadmap.md` 中定义。
