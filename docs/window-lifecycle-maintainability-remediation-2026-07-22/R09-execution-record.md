# 任务：R09 / Workspace expanded-mode 编排

待审状态：Author verification complete
开始基线：外层 `a52a17c` / niri `5d7bb07e` / quickshell `bbc267ca`（未改）

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/layout/expanded_mode.rs` | **新增** `ReturnPlacement` / `ExpandedModeKind` / `ExpandedModePlan` / `ExpandedModeOrchestrator`；纯决策与单元测试 |
| `src/layout/workspace.rs` | 唯一生产编排入口：`set_fullscreen` / `set_maximized` / `set_maximized_with_return_placement` / `set_return_placement` → `apply_expanded_mode`；`add_tile` 写 typed placement |
| `src/layout/tile.rs` | 删除 `restore_to_floating: bool`；字段改为 `ReturnPlacement`；getter/setter |
| `src/layout/mod.rs` | `pub mod expanded_mode`；interactive move 决策委托 orchestrator；top-snap 走 `set_maximized_with_return_placement` |
| `src/layout/tests.rs` | 返回 placement 持久化 / unmaximize-during-fs / scrolling 捕获 Scrolling 的逐步断言 |
| `src/layout/tests/fullscreen.rs` | interactive move 断言对齐 `ReturnPlacement::Floating` |

### 外层仓库

| 路径 | 作用 |
| --- | --- |
| `docs/.../R09-execution-record.md` | 本执行记录 |

Owner：

- **`ExpandedModeOrchestrator` + Workspace `apply_expanded_mode`**：fullscreen / maximize / 退出返回 floating 的**唯一**编排 owner。
- **`ReturnPlacement`**：替代裸 `restore_to_floating` bool 的 typed 返回 placement。
- **Column / ScrollingSpace**：继续负责 pending fullscreen/maximized 与布局尺寸（adapter）。
- **Mapped / window**：继续拥有协议 pending/committed sizing。
- **R08 `MaximizeVisualFsm`**：继续拥有最大化**视觉** exclusivity；本任务不复制 visual phase。
- **R07 `TileTransport`**：跨 remove/add 仍运输 floating + expanded intent；Workspace `add_tile` 将 `transport.is_floating()` 归一为 `ReturnPlacement`。

## 行为契约

适用 1.4 节：

- floating maximize → unmaximize 回 floating；
- fullscreen 覆盖 maximized → unfullscreen 回 maximized，再 unmaximize 才 float；
- fullscreen 时 unmaximize **不得**立即 float；
- interactive move 对 “maximized + Floating return” 视为 floating drag；
- top-snap maximize 与普通 maximize 同一 owner（`set_maximized_with_return_placement`）；
- 不发送额外 configure 的既有契约由既有 floating 测试覆盖；
- R07 跨 workspace/output transport 回归保持。

## 目标设计落地

```text
foreign / IPC / xdg / Layout
        │
        ▼
Workspace::set_fullscreen / set_maximized
  / set_maximized_with_return_placement  (top-snap)
        │
        ▼
ExpandedModeOrchestrator::plan_*  → ExpandedModePlan
        │
        ├─ NoOp
        ├─ ExitToFloating          → toggle_window_floating (combined unexpand+float)
        └─ ApplyInScrolling
              · optional floating→scrolling
              · scrolling.set_fullscreen / set_maximized  (Column sizing adapter)
              · optional ReturnPlacement write (only when leaving Normal)

Tile.return_placement: ReturnPlacement { Scrolling | Floating }

interactive_move_treat_as_floating:
  floating || (return_placement.is_floating() && pending maximized)
```

Desired mode（请求/column pending）与 committed sizing（window）与 R08 visual FSM 分离；fullscreen+maximized 在 column 层仍非互斥。

## 旧路径删除

```text
rg -n 'restore_to_floating' niri/src
# 仅：模块文档提及旧名；测试函数名保留语义；零 bool 字段/读写

rg -n 'restore_to_floating\s*:' niri/src
# 零命中（字段声明）
```

作者验证结果：

- **零** `restore_to_floating: bool` 字段与赋值。
- 编排决策只在 `expanded_mode` + `Workspace::apply_expanded_mode`；Column/Scrolling 仅为 sizing adapter。
- top-snap 不再直接写 tile 字段，统一走 `set_maximized_with_return_placement`。
- interactive move 决策经 orchestrator，无平行 bool 逻辑。

允许保留：

- 测试函数名 `restore_to_floating_*`（行为语义描述）；
- `toggle_window_floating`（space 迁移 adapter，非 expanded 决策源）；
- `ScrollingSpace::set_fullscreen/set_maximized` 与 `Column::set_*`（布局尺寸 adapter）；
- Layout 层 `set_fullscreen/set_maximized` 转发到 Workspace。

```text
rg -n 'set_fullscreen\(|set_maximized\(|toggle_window_floating' niri/src/layout
# 归类：Workspace = owner 入口；Scrolling/Column = sizing adapter；
# Layout = 转发/interactive-move unexpand；tests = 驱动
```

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo fmt --all)` | 已格式化；无关 layer/mapped fmt 已还原 |
| `(cd niri && cargo test -p niri --lib layout::)` | **185 passed**（含 expanded_mode 12 + 新增 scrolling_enter） |
| `(cd niri && cargo test -p niri --lib -- lifecycle coords closing_window maximize fullscreen restore_to expanded)` | **132+ passed**（定向子集） |
| `(cd niri && cargo test -p niri)` | **408 passed**（R09 要求整表自动化可覆盖部分） |
| 删除证明（上式） | 裸 bool 字段为零 |

未运行：嵌套会话手测；多输出热插拔手测（自动化矩阵已覆盖 dual-output fixture 等既有项）。

### 关键不变量

- floating → max → fs：return `Floating` 贯穿；unfs → maximized；unmax → floating；
- fs 期间 unmaximize 不 float；unfs 后（max 已清）→ floating；
- scrolling 进入 maximize 捕获 `Scrolling`；
- interactive move：maximized+Floating return 视为 floating；
- top-snap：同一 owner 写 maximize + return placement；
- 不混淆 desired / committed / R08 visual phase。

## 性能

可维护性重构。未声称帧时间或显存收益。

## 独立审查专属问题（作者自查）

1. 是否混淆 desired mode、committed mode 与 visual transition？**否**；orchestrator 只做请求编排与 return placement；Column pending / window pending / R08 FSM 分属三层。
2. fullscreen+maximized 非互斥语义是否保持？**是**；unfullscreen 在 `pending_maximized` 时不 ExitToFloating；回归 `restore_to_floating_persists_*` / `unmaximize_during_fullscreen_*`。
3. placement/size/configure 次数是否与基线一致？**是**；ExitToFloating 仍一次 toggle；既有 `unfullscreen_to_floating_doesnt_send_extra_configure` 等通过完整 suite。
4. interactive move、top snap 和普通 action 是否走同一 owner？**是**；普通 → `set_*`；top-snap → `set_maximized_with_return_placement`；interactive move treat-as-floating 经 orchestrator；unexpand 仍调 Workspace `set_fullscreen/set_maximized`。
