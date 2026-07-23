# 任务：R04 / F05–F06 当前输出 anchor ownership 与发布生命周期

待审状态：Author verification complete
开始基线：外层 `47a06cf` / niri `be1ce025` / quickshell `bbc267ca`

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/window/mapped.rs` | `ForeignToplevelRectHint::{Cleared,Unresolved,Resolved}` 单一 last-hint slot；generation；精确 source 清理 |
| `src/handlers/mod.rs` | `set_rectangle`：`0×0`→Cleared；`0×N`/`N×0`/正面积→替换 slot；source 未映射→Unresolved（不复活旧值）；checked 转换 |
| `src/protocols/foreign_toplevel.rs` | 负尺寸 `invalid_rectangle` 协议错误（对齐 wlroots last-request 契约） |
| `src/layout/coords.rs` | `SurfaceLocalRect::try_to_output_local` checked 加法 |
| `src/niri.rs` / `src/lifecycle_command.rs` | 消费时 wrong-output / zero-area / Unresolved / Cleared → 无 anchor 降级 |
| `src/tests/foreign_toplevel.rs` | 0×0、零面积、Unresolved 替换、旧 source 不误清新绑定、零面积 lifecycle 降级 |

### 外层仓库（tahoe-shell + docs）

| 路径 | 作用 |
| --- | --- |
| `tahoe-shell/services/windows/DockRectanglePublisher.js` | 新建：handle/screens ownership、候选求值、归一化（纯 JS） |
| `tahoe-shell/services/Windows.qml` | Shell publisher owner：`submitDockRectangle` + frame coalesce flush；`setRectangle` 仅转发 publisher |
| `tahoe-shell/components/WindowButton.qml` | 只经 publisher；监听 mag/push/bounce 与 screensChanged；删直接 wire `setRectangle` |
| `tahoe-shell/components/DockMinimizedWindow.qml` | 初次/几何/screens 变化即发布；restore 强制 flush |
| `tahoe-shell/tests/test_dock_rectangle_publisher.py` | ownership / 错配 IPC / coalesce / 删除证明 |
| `tahoe-shell/tests/tst_window_button_rectangle_tracking.qml` 等 | 适配 submit API；视觉属性回归 |
| `docs/.../R04-execution-record.md` | 本执行记录 |

Owner：

- **Shell**：`Windows.submitDockRectangle` + `DockRectanglePublisher` 是唯一生产发布 owner；key = 实际 wlr `Toplevel` 对象身份；current-screen = handle.screens 恰为 1 且等于该 Dock screen。
- **Compositor**：`Mapped.foreign_toplevel_rect` 唯一 typed last-hint；协议 adapter 只写入，lifecycle command 只按 current-output 消费。

## 行为契约

适用 1.4 节：

- 每屏 Dock 仍显示全局窗口集合；仅 **发布** 按 current-screen 去重，不悄悄过滤按钮；
- fullscreen 隐藏/恢复、auto-hide、reveal slide 发布门控保留；
- minimize/restore / foreign/IPC/xdg 仍走 R03 command；anchor 只在 Resolved+匹配输出+非空时启用 Genie；
- 0×0 删除；负尺寸协议错误；0×N/N×0 为 last request，消费时降级；
- source unmap/destroy 仅匹配当前 slot 的 source/root 时 Cleared。

明确修复 F05/F06：多 Dock 竞争 → current-screen owner；未映射 source 不再“清空并丢弃事实”；视觉 mag/push/bounce 与 minimized shelf 生命周期发布。

## 目标设计落地

```text
WindowButton / DockMinimizedWindow (per-screen Dock)
        │  submitDockRectangle(toplevel, source, dockScreen, geo, {force})
        ▼
Windows.qml publisher (frame-coalesced pending map by handle id)
  · DockRectanglePublisher.currentScreenOwnership(handle.screens, dockScreen)
  · fail closed: no/multi/mismatch screens (observable reject counters)
  · force → immediate flush; else Qt.callLater once
        │  toplevel.setRectangle(source, rect)  // wire, last wins
        ▼
niri ForeignToplevelHandler::set_rectangle
  · 0×0 → Cleared
  · else always replace slot:
      mapped source + checked geo → Resolved
      else → Unresolved { reason, surface_local, generation }
        ▼
LifecycleCommand CachedForCurrentOutput
  · only Resolved ∩ current output ∩ !empty → Genie
  · else degrade; slot fact unchanged
```

### 协议 / wlroots 核验

- XML last-rectangle + `width=height=0` 删除：`quickshell/.../wlr-foreign-toplevel-management-unstable-v1.xml`
- 负尺寸 → `invalid_rectangle`：与路线图所述 wlroots `foreign_toplevel_handle_set_rectangle` 行为一致（负尺寸 post error；其余非负组合交 compositor）。本树未内嵌该 wlroots 对象 revision；实现按 XML + 路线图固定契约。

## 旧路径删除

```text
rg -n 'set_foreign_toplevel_rect\(None\)' niri/src/handlers
rg -n 'function updateDockRectangle|setRectangle\(' tahoe-shell/components
rg -n 'toplevel\.setRectangle|windowsService\.setRectangle' tahoe-shell/components
```

作者验证结果：

1. `set_foreign_toplevel_rect(None)`：**零命中**。合法清理改为 `set_foreign_toplevel_rect_hint(Cleared)` 或 `clear_foreign_toplevel_rect_for_source`（仅 source 匹配）。“source 未映射就无条件清空”已删除。
2. `updateDockRectangle` 仍存在于 WindowButton / DockMinimizedWindow，但二者均只调用 `windowsService.submitDockRectangle`；组件内 **无** 直接 `toplevel.setRectangle` / `windowsService.setRectangle` 生产发布。
3. `Windows.setRectangle` 仅兼容转发到 `submitDockRectangle`（force），无独立 wire 策略。

## R11 剩余风险（本任务如实保留）

`WindowModel.mergeWindowModels` 仍可能用 appId/title 把 IPC 数据绑到错误 wlr handle。R04 **不**修复身份：

- publisher **从不**用 IPC `window.output` / `window.id` 决定谁可 `setRectangle`；
- 只按实际 handle 的 `screens` 去重；
- 错配时按钮标签、minimized-shelf 归类与用户意图↔handle 精确对应仍可能错误——由 **R11** 关闭。

测试 `test_wrong_ipc_merge_still_uses_handle_screens` 固定：即使“配对”语义错误，HDMI Dock 也不能为仅在 eDP 上的 handle 发 wire。

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo fmt --all)` | 已格式化；无关 fmt 改动已还原 |
| `(cd niri && cargo test -p niri --lib foreign_toplevel)` | 7 passed |
| `(cd niri && cargo test -p niri --lib -- lifecycle_command lifecycle_observe coords foreign_toplevel)` | 33+ passed |
| `(cd niri && cargo test -p niri --lib layout::tests)` | 134 passed |
| `(cd tahoe-shell && pytest tests/test_dock_rectangle_publisher.py tests/test_edge_reveal_semantics.py tests/test_r17_dock_layout_motion.py tests/test_window_button_rectangle_tracking_qml.py tests/test_window_model.py)` | 34 passed |

未运行：完整 `cargo test -p niri`（时间）；嵌套会话双屏手测（单测覆盖 dual-dock ownership 决策、wrong-output 消费、stale source cleanup）。

### 关键不变量

- 双 delegate 仅 current-screen owner 的候选被 accept；非 owner reject 且不覆盖 pending；
- Unresolved 替换 Resolved，不保留旧 output-local；
- 旧 source destroy 不清除新 source 绑定；
- 0×N last request + lifecycle 降级且 slot 仍在；
- mag/push/bounce 变更会 schedule 重发；
- minimized shelf `Component.onCompleted` 即 schedule 发布。

## 性能

正确性/ownership 修复。frame coalesce 将高频 mag 更新合并为每 handle 每 frame 至多一次 wire；无帧时间基线声称。

## 独立审查专属问题（作者自查）

1. publisher 是否按实际 handle/screens 去重，错配 IPC 也不用错误 IPC output？**是**；API 直接收 toplevel；ownership 只看 `screens`。
2. source 删除是否精确、旧 source 会否误删新绑定？**是**；`source_matches` + generation 测试覆盖。
3. remap 后是否由事件重发而非依赖 hover？**是**；fullscreen 清除、screensChanged、minimized onCompleted/geometry 均 schedule。
4. 高频动画是否每 frame 至多一次发布？**是**；pending map + `Qt.callLater` flush；force 路径立即 flush。
5. 负尺寸 / 0×0 / 单维零 / 溢出是否分契约处理？**是**；protocol error / Cleared / Resolved empty / Unresolved CoordinateOverflow。
6. 全屏隐藏、每屏 Dock、shelf 是否保留；R11 风险是否如实保留？**是**；见上文剩余风险段。
