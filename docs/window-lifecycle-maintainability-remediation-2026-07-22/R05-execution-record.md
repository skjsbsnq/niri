# 任务：R05 / minimize/restore lifecycle controller 收敛

待审状态：Author verification complete
开始基线：外层 `6ad98b3` / niri `d39d5e51` / quickshell `bbc267ca`（未改）

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/layout/lifecycle_controller.rs` | **新建**：`MinimizeRestoreController` 唯一 policy owner；方向、反转、advance、lease 事件、overlay 枚举 |
| `src/layout/floating.rs` | 删除双 Vec 与 `take_*`/`start_*_for_tile`；持有一个 controller 实例；adapter 只做 snapshot/focus/lease 应用 |
| `src/layout/scrolling.rs` | 同上；render_observation / render 经 controller 枚举 |
| `src/layout/tile.rs` | `restore_animation_hidden` → controller 管理的 `restore_visibility_lease` + apply/release API |
| `src/layout/mod.rs` | 注册 `lifecycle_controller` 模块 |
| `src/layout/tests/lifecycle_controller.rs` | floating/scrolling/tabbed 表驱动；remove/lease/empty controller |
| `src/layout/tests.rs` | 挂载测试模块 |
| `src/tests/lifecycle_observe.rs` | 0%/中段/近完成 reverse morph 连续 + restore 完成释放 lease |

### 外层仓库

| 路径 | 作用 |
| --- | --- |
| `docs/.../R05-execution-record.md` | 本执行记录 |

Owner：

- **MinimizeRestoreController**（floating / scrolling 各一实例）：window id → 唯一 active 动画；minimize↔restore 原对象反转；visibility lease 发放/回收；advance 与完成清理；overlay 列表。
- **Space adapter**（floating / scrolling）：tile 查找与位置、snapshot 捕获、layout-specific focus/activation、closing 与 overlay 放置层。不得复制 reverse/lease/duplicate policy。

opening 仍 Tile-local；closing 仍各自容器（R06）。

## 行为契约

适用 1.4 节：

- floating / scrolling / tabbed minimize/restore 语义与 focus 规则保持；
- reverse 复用同一 snapshot/texture（`reverse_to_*` 原地改方向与 progress）；
- restore 期间 live tile 由 lease 抑制；成功完成、失败创建、反转回 minimize、remove 时释放；
- wrong/missing anchor 仍走无 Genie / alpha fallback（adapter 路径不变）；
- R01 lifecycle overlay Draw 策略与 maximize exclusivity 不回归；
- foreign / IPC / xdg 仍经 R03 command；本任务不改协议入口。

## 目标设计落地

```text
set_minimized / minimize_with_snapshot / restore_with_snapshot
        │  layout focus / snapshot (space)
        ▼
MinimizeRestoreController
  · reverse_to_minimize / reverse_to_restore  (same entry + texture)
  · start_minimize / start_restore
  · advance → LeaseEvent::{Suppress,Reveal}
  · clear on remove
        │  LeaseEvent
        ▼
Tile.apply_restore_visibility_lease / release_restore_visibility_lease
        │
        ▼
render: controller.render_overlays + skip lease-suppressed live tiles
```

## 旧路径删除

```text
rg -n 'minimize_animations|restore_animations|take_minimize_animation|take_restore_animation|start_(minimize|restore)_animation_for_tile|restore_animation_hidden' niri/src/layout/{floating.rs,scrolling.rs,tile.rs}
```

作者验证结果：**零命中**。

新 owner 仅一份：`src/layout/lifecycle_controller.rs`。floating/scrolling 仅委托 `minimize_restore: MinimizeRestoreController`。

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo fmt --all)` | 已格式化；无关 fmt 改动已还原 |
| `(cd niri && cargo test -p niri --lib layout::)` | 156 passed |
| `(cd niri && cargo test -p niri --lib lifecycle)` | 28 passed（含 reverse 三进度点 + lease 释放） |
| `(cd niri && cargo test -p niri --lib coords)` | 12 passed |
| 删除证明 `rg`（上式） | 零命中 |

未运行：完整 `cargo test -p niri`（时间）；嵌套会话手测。

### 关键不变量

- reverse 后 minimize/restore overlay 计数恰为 1（无并行动画）；
- morph “how minimized” 在 reverse 点连续（0% / mid / near-complete）；
- restore 完成与 reverse-to-minimize 后 `is_suppressed_by_restore_lease() == false`；
- 无 GPU 的 minimize/restore 不留下 lease 或假 overlay；
- floating 与 scrolling 各自独立 controller 实例。

## 性能

可维护性重构。未声称帧时间或显存收益。

## 独立审查专属问题（作者自查）

1. reverse 是否复用同一 snapshot/texture？**是**；`reverse_to_*` 原地改方向，不 `new_*`。
2. visibility lease 是否覆盖成功、失败、取消、remove、teardown？**是**；advance 完成 Reveal；start_restore 失败不 Suppress；clear on remove 丢弃 entry；reverse-to-minimize Reveal。
3. floating/scrolling 是否只剩窄 adapter？**是**；无双 Vec / take / start_for_tile policy 副本。
4. stacking、focus、interactive move 语义是否保持？**是**；set_minimized 内 raise/activate/resize 取消仍在 space；既有 layout/lifecycle 测试通过。
