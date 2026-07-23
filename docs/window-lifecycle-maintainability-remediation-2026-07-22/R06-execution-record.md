# 任务：R06 / closing animation lane 收敛

待审状态：Author verification complete
开始基线：外层 `60145a8` / niri `7d98cc18` / quickshell `bbc267ca`（未改）

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/layout/lifecycle_controller.rs` | **扩展**：`ClosingAnimationLane` 唯一持有 `ClosingWindow` 集合、`start`、`advance`、完成 drop、overlay 枚举 |
| `src/layout/closing_window.rs` | `AnimationState` 交易 leaf 逻辑收敛到可测方法；Waiting/Animating 单元测试 |
| `src/layout/floating.rs` | 删除 `closing_windows: Vec` 与重复 create helper；持有 `closing: ClosingAnimationLane`；adapter 只做 snapshot/position |
| `src/layout/scrolling.rs` | 同上；保留列删除位置补偿与 tabbed inactive skip；render_observation 经 lane len |
| `src/layout/workspace.rs` | 路由 `start_closing` / `start_closing_at`（interactive-move 落点仍 floating） |
| `src/layout/mod.rs` | 协议入口名保留；调用 workspace 新 adapter 名 |
| `src/layout/tests/lifecycle_controller.rs` | floating/scrolling/tabbed close-without-snapshot；独立 lane 实例 |
| `src/tests/lifecycle_observe.rs` | closing 完成释放；floating close 不进 scrolling observation |

### 外层仓库

| 路径 | 作用 |
| --- | --- |
| `docs/.../R06-execution-record.md` | 本执行记录 |

Owner：

- **ClosingAnimationLane**（floating / scrolling 各一实例）：`ClosingWindow` 集合；创建（含 disable_transactions → completed blocker）；advance 与完成清理（drop 释放纹理）；overlay 枚举/render。
- **Space adapter**：tile 查找、unmap snapshot、layout 位置（scrolling 列删除补偿、tabbed inactive 跳过、floating 位置）；interactive-move 由 Layout 算落点后 `start_closing_at`。
- **Transaction leaf**：仍在 `ClosingWindow::AnimationState::{Waiting, Animating}`；本任务不重写 transaction 协议。
- **协议顺序**（handlers 未改）：store unmap snapshot → create transaction/blocker → start close animation → `window.on_commit` / remove → blocker release → animation。

opening 仍 Tile-local；minimize/restore 仍 `MinimizeRestoreController`（R05）。

## 行为契约

适用 1.4 节：

- destroy path 与 null-buffer unmap 的 snapshot→start→on_commit 顺序保持（handlers 未改）；
- blocker pending 时 Waiting 不错误完成；completed / disable_transactions 立即 Animating；
- floating / scrolling / tabbed inactive skip / interactive-move 落点语义保持；
- non-target close 与 maximize 重叠时 R01 Draw 策略继续覆盖 closing；
- opening 未完成即 close：无 snapshot 则无假 overlay；
- 创建失败只 warn、不 push、无泄漏；
- advance 完成后 drop 释放纹理（逐帧清空 observation）。

## 目标设计落地

```text
Layout::start_close_animation_for_window  (protocol entry name kept)
        │
        ▼
Workspace::start_closing / start_closing_at
        │  space adapter: snapshot + layout pos
        ▼
ClosingAnimationLane::start / advance / render_overlays
        │
        ▼
ClosingWindow { AnimationState::Waiting | Animating }
```

## 旧路径删除

```text
rg -n 'closing_windows|start_close_animation_for_tile|start_close_animation_for_window' niri/src/layout/{floating.rs,scrolling.rs,workspace.rs}
```

作者验证结果：**零命中**。

允许保留：

- `Layout::start_close_animation_for_window`（协议/compositor 入口，非上述三文件）；
- space/workspace 的 `start_closing` / `start_closing_at` 窄 adapter；
- `ClosingWindow` 类型与 `ClosingWindowRenderElement`（lane 与 render 元素，非双容器）。

新 owner 仅一份实现：`ClosingAnimationLane` in `lifecycle_controller.rs`。floating/scrolling 各委托一个实例。

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo fmt --all)` | 已格式化 |
| `(cd niri && cargo test -p niri --lib layout::)` | 162 passed |
| `(cd niri && cargo test -p niri --lib -- lifecycle closing_window)` | 37 passed（含 blocker Waiting、完成释放、floating lane） |
| `(cd niri && cargo test -p niri --lib coords)` | 12 passed |
| 删除证明 `rg`（上式） | 零命中 |

未运行：完整 `cargo test -p niri`（时间）；嵌套会话手测；interactive-move close 手测（路径保留为 adapter，未改落点算法）。

### 关键不变量

- blocker pending：`AnimationState::Waiting`，advance 不提前完成；
- blocker completed / transactions disabled：立即 `Animating`；
- 完成后一帧 `lifecycle_overlays` 无 Closing（lane drop）；
- floating close 不出现在 scrolling `render_observation`；
- 无 snapshot 的 close 不发明 Closing overlay；
- floating 与 scrolling 各自独立 lane 实例。

## 性能

可维护性重构。未声称帧时间或显存收益。

## 独立审查专属问题（作者自查）

1. snapshot/on_commit/remove 顺序是否保持？**是**；handlers 未改；仍 store → start → on_commit/remove。
2. blocker 未释放时 animation 是否不会错误完成或泄漏？**是**；Waiting 保持 ongoing；释放后才 Animating；失败 start 不 push。
3. scrolling 位置补偿和 floating stacking 是否仍由正确 adapter 提供？**是**；补偿/tabbed skip 在 scrolling `start_closing`；floating 位置在 floating adapter；interactive-move 仍 `start_closing_at` → floating lane。
4. R01 的 lifecycle render invariant 是否继续覆盖 closing？**是**；scrolling 仍经 `scrolling_lifecycle_overlays_are_rendered()` 后 `closing.render_overlays`；既有 maximize+close 测试通过。
