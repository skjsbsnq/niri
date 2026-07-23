# 任务：R07 / `RemovedTile` 状态运输修复

待审状态：Author verification complete
开始基线：外层 `c9bb5c4` / niri `1bd35b74` / quickshell `bbc267ca`（未改）

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/layout/mod.rs` | **新增** `TileTransport`；`RemovedTile` 仅携带 `tile + transport`；`InteractiveMoveData` 改用同一 transport |
| `src/layout/floating.rs` | remove 时 `TileTransport::floating(width)` |
| `src/layout/scrolling.rs` | remove 时捕获 column `width/full_width/pending_max/pending_fs`；`Column::new_with_tile` / `add_tile` 消费 transport |
| `src/layout/workspace.rs` | `add_tile` 与 floating↔scrolling 切换改走 transport |
| `src/layout/monitor.rs` | workspace 间移动 reinsert 整包 transport；新窗 `for_new_window` |
| `src/layout/tests.rs` | 替换 FIXME 断言；跨 workspace/output、往返、tabbed expel、floating 回归 |

### 外层仓库

| 路径 | 作用 |
| --- | --- |
| `docs/.../R07-execution-record.md` | 本执行记录 |

Owner：

- **`TileTransport`**：remove→add 边界上唯一的 placement + expanded intent 运输记录（width、full-width、floating placement、pending maximized、pending fullscreen）。fullscreen 与 maximized 为独立 bool，可同时为真。
- **`RemovedTile`**：`tile` + `transport`；无 window-id side table。
- **`Column::new_with_tile`**：先应用 transport 的 pending flags；二者皆 false 时才回退到 window `pending_sizing_mode`（新窗路径）。
- **Interactive move**：与 `RemovedTile` 共用 transport 字段集；开始 interactive move 仍先 unfullscreen/unmaximize（既有行为），故 pending 通常为 false，但 reinsert 不再用散落字段。

## 行为契约

适用 1.4 节：

- scrolling / floating / tabbed 放置语义保持；
- fullscreen 与 maximized 可叠加：“退出 fullscreen 后仍 maximized”；
- 整列移动（原已保留 column 状态）与单窗 `RemovedTile` 移动现在对 max+fs 语义一致；
- interactive move 开始时仍清除 max/fs（未改产品语义）；
- floating 运输不发明 expanded intent；
- 无按 window id 的旁路状态表。

## 目标设计落地

```text
remove (floating | scrolling column)
        │
        ▼
RemovedTile { tile, transport: TileTransport {
  width, is_full_width, is_floating,
  is_pending_maximized, is_pending_fullscreen
}}
        │
        ▼
add_tile(..., transport)
        │
        ▼
Column::new_with_tile(..., transport)
  · apply transport pending_fs / pending_max (independent)
  · if both false → derive from window pending SizingMode (new windows)
```

## 旧路径删除

```text
rg -n 'struct RemovedTile|RemovedTile \{' niri/src/layout
# 仅 tile + transport；无 width/is_full_width/is_floating 顶层字段

rg -n 'FIXME: it currently doesn.t because windows themselves' niri/src/layout/tests.rs
# 零命中：FIXME 由通过的回归替换
```

作者验证结果：

- `RemovedTile` 仅 `tile` + `transport`。
- 所有构造：`TileTransport::{scrolling,floating}` 或 interactive-move 已有 transport；无“旧字段解构后再从 window 猜 maximized”。
- 原 FIXME 测试改为断言 `SizingMode::Maximized` 且通过。

允许保留：

- `Column` 上的 `is_pending_maximized` / `is_pending_fullscreen`（列级事实源，非平行 transport）；
- `SizingMode`（窗口协议层互斥值；列级组合仍用双 bool）；
- `TileTransport::for_new_window` 的 placement-only 路径（新窗 expanded 仍由 window pending 推导）。

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo fmt --all)` | 已格式化；无关 fmt 改动已还原 |
| `(cd niri && cargo test -p niri --lib layout::)` | **166 passed** |
| `(cd niri && cargo test -p niri --lib -- lifecycle coords closing_window)` | **49 passed** |
| R07 定向：`maximize_and_fullscreen` / `round_trip` / `expel_tab` / `floating_remove_transport` / `move_window_to_output` | 全部通过 |
| 删除证明（上式） | RemovedTile 仅 transport；FIXME 零命中 |

未运行：完整 `cargo test -p niri`（时间）；嵌套会话手测；interactive-move 手测（路径保留，开始时仍 clear max/fs）。

### 关键不变量

- maximize → fullscreen → `MoveWindowToWorkspace` → unfullscreen → **Maximized**（旧 FIXME 路径）；
- 同上跨 output；
- 往返 workspace 两次后 column 仍 `pending_fs && pending_max`，unfullscreen → Maximized；
- tabbed expel 新列继承 source column 的 pending 组合；
- floating remove/reinsert 不把 pending 设为 true；
- 整列 move 回归仍 Maximized。

## 性能

正确性修复。未声称帧时间或显存收益。

## 独立审查专属问题（作者自查）

1. fullscreen 与 maximized 组合是否可无损往返？**是**；transport 双 bool + `Column::new_with_tile` 独立 `set_fullscreen`/`set_maximized`；测试覆盖 workspace/output/round-trip/tabbed expel。
2. 所有 remove/add 边界是否迁移，无遗漏 constructor？**是**；floating、scrolling 单/多 tile、interactive-move remove、workspace/monitor reinsert、floating↔scrolling toggle 均走 transport。
3. 是否新增了第二个状态表或从 committed window state 错推 pending intent？**否**；无 window-id side table；reinsert 优先 transport flags，仅 placement-only 新窗回退 window pending。
4. floating 返回意图和 tabbed 状态是否保持？**是**；`is_floating` 与既有 `tile.restore_to_floating` 赋值路径保留；tabbed display_mode 仍在 column 上，整列移动未改；expel 携带 pending expanded。
