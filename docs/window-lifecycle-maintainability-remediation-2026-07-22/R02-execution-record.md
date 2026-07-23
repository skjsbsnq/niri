# 任务：R02 / F03 类型化坐标与统一转换

待审状态：Author verification complete
开始基线：外层 `790a851` / niri `360c2369` / quickshell `bbc267ca`

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/layout/coords.rs` | 新建：`SurfaceLocalRect` / `OutputLocalRect` / `OutputLocalRectF` / `OutputLocalPoint` / `WorkspaceContent{Rect,Point}` / `WorkspaceView{Rect,Point}` / `GlobalRect`；显式单向转换；`GenieEndpointResolve` |
| `src/layout/minimize_window_animation.rs` | Genie 仅存 output-local 起点与 anchor；render 仅做 output-local → render-target 一次减 `view_rect.loc` |
| `src/layout/scrolling.rs` | 删除 minimize/restore 的 `tile_pos.x += view_pos`；view 位姿经 `GenieEndpointResolve` 入 Genie；render 对 Genie 使用 `loc=0` 的 output-local viewport（closing 仍用 content `view_pos`） |
| `src/layout/floating.rs` | 同样经 `GenieEndpointResolve` 注入 typed endpoints |
| `src/layout/mod.rs` | `MinimizeRect.rect` 类型改为 `OutputLocalRect`；mod 导出 `coords` |
| `src/window/mapped.rs` | `ForeignToplevelRect.rect` → `OutputLocalRect` |
| `src/handlers/mod.rs` | `set_rectangle`：`SurfaceLocalRect` + layer geo → `OutputLocalRect` |
| `src/layout/tests/coords.rs` | F03 数值案例与 view_pos 正/零/负回归 |
| `src/layout/tests.rs` / `tests/foreign_toplevel.rs` / `tests/lifecycle_observe.rs` | 适配 typed rect API |

### 外层仓库

| 路径 | 作用 |
| --- | --- |
| `docs/.../R02-execution-record.md` | 本执行记录 |

Owner：layout 坐标类型模块 + Genie 仅消费 output-local 端点；转换在进入动画对象前完成。

## 行为契约

适用 1.4 节：

- scrolling / floating minimize-restore Genie 起终点同一空间；
- 多输出 wrong-output anchor 仍在 workspace 层丢弃（既有过滤）；
- closing 仍用 workspace-content + `view_pos`（R06 范围，未改状态机）；
- foreign `set_rectangle` 语义不变：surface-local + layer geo = output-local 存盘；
- 既有 minimize_restore IPC layout 与 foreign rectangle 测试保持。

明确修复 F03：禁止 workspace-content 窗口位姿与 output-local Dock anchor 在 Genie 内直接 union 后再统一减 `view_pos`。

## 目标设计落地

Canonical Genie 空间 = **output-local**：

1. Dock/foreign rect 经 `SurfaceLocalRect::to_output_local(layer_geo)` 写入 `ForeignToplevelRect` / `MinimizeRect`；
2. Scrolling tile render 位姿为 workspace-view（已含 `-view_pos`），经 `GenieEndpointResolve::window_from_view_pos` → `OutputLocalPoint`（满屏 workspace origin 恒等）；
3. `MinimizeWindowAnimation` 字段为 `OutputLocalPoint` + `Option<OutputLocalRectF>`；
4. Render 使用 `Rectangle::from_size(view_size)`（loc=0），仅一次 `location - view_rect.loc`。

## 旧路径删除

```text
rg -n 'pub struct MinimizeRect|target_rect: Option<Rectangle|source_rect: Option<Rectangle' niri/src/layout
rg -n 'tile_pos\.x \+= view_pos' niri/src/layout
```

作者验证结果：

- `MinimizeRect` 仍保留名字，但 `rect: OutputLocalRect` 字段本身编码空间；生产路径不再接受裸 `Rectangle` 作为 Genie target/source。
- `MinimizeWindowAnimation` 内 `target_rect: Option<Rectangle<...>>` / 裸 `pos: Point<f64, Logical>` 已删除。
- minimize/restore 上 `tile_pos.x += view_pos` 为零；仅 closing 路径保留 `tile_pos.x += self.view_pos()`（非 Genie lifecycle anchor，属 R06）。

```text
rg -n 'tile_pos\.x \+= self\.view_pos' niri/src/layout
```

- 仅 `scrolling.rs` close animation 一处。

## 测试

| 命令 | 结果 |
| --- | --- |
| `cargo fmt --all` | 已格式化（nightly wrap 选项告警可忽略） |
| `cargo test -p niri --lib coords` | 11 passed |
| `cargo test -p niri --lib layout::tests` | 133 passed |
| `cargo test -p niri --lib -- observe lifecycle_observe foreign_toplevel minimize` | 27 passed |

未运行：完整 `cargo test -p niri`（时间）；嵌套会话手测多输出旋转（坐标纯函数 + foreign layer 几何单测覆盖协议路径）。

### 关键不变量断言

- `view_pos=1000` / window screen x=`100` / anchor=`900` → output-local 两端点为 100 与 900，非 dock=-100；
- view_pos 0 / 负 / 大正值下 genie_area 覆盖两端点；
- surface-local (10,20)+(layer y=640) → output-local (10,660)；
- `MinimizeRect` 仅接受 `OutputLocalRect`。

## 性能

正确性修复；无帧时间声称。

## 独立审查专属问题（作者自查）

1. 每次转换是否有唯一方向和所需 context？是（surface→output 需 layer_geo；content↔view 需 view_pos；view→output 需 workspace origin；Genie resolve 封装窗口 view→OL 与 anchor OL）。
2. 是否仍存在通过 `.rect` 或 `.to_f64()` 绕开类型检查的生产路径？Genie 入口为 `OutputLocalRect`/`OutputLocalRectF`；`to_f64()` 为同空间 i32→f64。裸 `Rectangle` 不能传入 `new_with_target`/`new_with_source`。
3. fractional scale 的 round 是否在正确边界且只发生一次？Render 仍对 location 做 `to_physical_precise_round`；未新增二次 round。
4. xray、blocked-out、overview 坐标是否仍正确？Snapshot/xray 路径未改；Genie 仍在 workspace 元素列表内绘制，overview 外层变换不变。
