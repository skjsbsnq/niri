# 任务：R01 / F01 lifecycle overlay render ownership

待审状态：Author verification complete
开始基线：外层 `1532a8b5` / niri `cdec1fa5` / quickshell `bbc267ca`

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/layout/scrolling.rs` | 唯一 `ScrollingRenderPolicy` + `LifecycleOverlayAction`；render/observation 走 policy；删除 maximize 统一吞 overlay 的门控 |
| `src/layout/floating.rs` | 拆分 `render_lifecycle_overlays` / `render_live_tiles`，避免 live 可见性吞掉 overlay |
| `src/layout/workspace.rs` | floating live 可见性读 policy.suppress_floating_live_tiles；render_floating 按 policy 独立画 overlay |
| `src/layout/tests/observe.rs` | 布局级 policy 决策与 live 排他回归 |
| `src/tests/lifecycle_observe.rs` | headless 真实 Genie：pending/committed maximize 下 minimize/restore reverse/close 逐帧 Draw |

### 外层仓库

| 路径 | 作用 |
| --- | --- |
| `docs/.../R01-execution-record.md` | 本执行记录 |

Owner：scrolling 内唯一 render policy（live tile 排他、lifecycle overlay 动作、floating live/overlay）。

## 行为契约

适用 1.4 节：

- maximizing target live tile 独占（非目标列/tab 不透过透明 resize）；
- floating live 在 maximize transition 期间仍隐藏；
- 关闭 maximize target 仍先清 transition；
- non-target close/minimize/restore 在 maximize 期间可绘制并推进；
- hit testing 与 live visibility 仍受 maximize exclusivity 约束（overlay 为 snapshot，不接管 hit）。

明确修复 F01：禁止“容器推进、render 静默不 push”。

## 目标设计落地

`ScrollingRenderPolicy::for_maximize_state(exclusive)`：

| 字段 | maximize ongoing | idle |
| --- | --- | --- |
| `maximize_exclusive` | true | false |
| `scrolling_lifecycle_overlays` | **Draw** | Draw |
| `suppress_floating_live_tiles` | true | false |
| `floating_lifecycle_overlays` | **Draw** | Draw |

`LifecycleOverlayAction::{Draw, Pause, Cancel}` 表达三态；R01 默认与生产路径仅产出 **Draw**。Pause/Cancel 为显式规则预留，当前无生产分支写入。

## 旧路径删除

完成后不得再以单个 `if !maximize_transition` / `!maximize_transition_is_ongoing` 同时包住三类 lifecycle render loop。

```text
rg -n 'lifecycle_overlays_are_rendered|if !self\.maximize_transition|if self\.lifecycle_overlays' niri/src/layout
```

结果（作者验证时）：

- 旧 `fn lifecycle_overlays_are_rendered` 已删除；
- 渲染门控仅为 `policy.scrolling_lifecycle_overlays_are_rendered()` / `policy.floating_lifecycle_overlays_are_rendered()`；
- `workspace::is_floating_visible` 读 `policy.suppress_floating_live_tiles`，不再直接 `maximize_transition_is_ongoing()` 作为唯一语义来源（仍由 policy 在 maximize 时置 suppress）。

```text
rg -n 'maximize_transition_is_ongoing' niri/src
```

剩余命中：policy 计算与既有 maximize exclusivity helpers；不再用于吞 lifecycle overlay。

## 测试

| 命令 | 结果 |
| --- | --- |
| `cargo fmt --all` | 已格式化 |
| `cargo test -p niri --lib layout::tests` | 127 passed |
| `cargo test -p niri --lib -- observe lifecycle_observe` | 13 passed |
| `cargo test -p niri --lib -- lifecycle_diag foreign_toplevel` | 7 passed |

未运行：完整 `cargo test -p niri`（时间）；嵌套会话手测（policy 已有逐帧/逐事件单测覆盖 F01）。

### 关键不变量断言

- maximize pending/committed + non-target minimize：`rendered == true` 且 progress 增长；
- mid-minimize reverse → restore：morph 下降且始终 rendered；
- non-target close overlay：Closing + rendered under exclusive；
- non-target live tiles 在 exclusive 下仍不可见；
- floating live 隐藏，floating overlay policy 仍为 Draw。

## 性能

本任务为正确性修复，不声称帧时间改善。Draw 额外成本 = 本应可见的 lifecycle overlay 推入 render list（与无 maximize 时相同路径）。

## 独立审查专属问题（作者自查）

1. minimize/restore/close 均覆盖：是（fixture 三态 + reverse）。
2. maximize 透明区未重新露出普通 live tile：是（tile exclusivity + floating live suppress 测试）。
3. 隐藏时非静默推进：是（仅 Draw；无 unrendered+active）。
4. render / floating visibility 同源 policy：是（`render_policy()`）。
