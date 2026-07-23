# 任务：R03 / F04 单一内部 lifecycle command

待审状态：Author verification complete
开始基线：外层 `7018894` / niri `b0b75c87` / quickshell `bbc267ca`

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/lifecycle_command.rs` | 新建：`LifecycleCommand` / `LifecycleDirection` / `LifecycleAnchorInput` / `LifecycleInvocationSource` / `LifecycleCommandResult` |
| `src/niri.rs` | 删除平行 `minimize/restore_window_with_animation`；唯一策略 owner `execute_lifecycle_command` |
| `src/layout/mod.rs` | 合并 snapshot/model 入口为 `apply_lifecycle` + `apply_lifecycle_with_snapshot`；统一 minimize 结束 interactive move / restore 拒绝 Moving |
| `src/handlers/mod.rs` | foreign set/unset_minimized → command + `CachedForCurrentOutput`（adapter 不再读 cache） |
| `src/handlers/xdg_shell.rs` | xdg minimize_request → 同一 command |
| `src/input/mod.rs` | IPC/bind Minimize/Restore → 同一 command + `CachedForCurrentOutput`（修复 F04） |
| `src/lib.rs` | 注册 `lifecycle_command` 模块 |
| `src/tests/lifecycle_command.rs` | F04 跨入口等价、duplicate no-op、无 renderer fallback、wrong-output 降级、IPC 消费 cache |
| `src/tests/lifecycle_observe.rs` | 迁移到 command API |
| `src/tests/mod.rs` | 注册测试模块 |
| `src/layout/tests.rs` / `tests/coords.rs` | 使用 `apply_lifecycle`；restore 拒绝 interactive move |

### 外层仓库

| 路径 | 作用 |
| --- | --- |
| `docs/.../R03-execution-record.md` | 本执行记录 |

Owner：`State::execute_lifecycle_command` 是 minimize/restore 策略唯一 owner；协议 adapter 只解析窗口与 anchor 输入模式。

## 行为契约

适用 1.4 节：

- foreign / IPC / xdg 同一窗口与同一 cache 得到同一最终 minimized 状态与同一 command 路径；
- renderer 不可用时走同一 `apply_lifecycle` fallback，不另开 API；
- restore 无 anchor 不再在 State 层短路绕过 command（旧 `if source_rect.is_none() { restore_window }` 已删）；
- minimize 结束 interactive move；restore 对 Moving 同 id 返回 NoOp；
- wrong-output cached anchor 降级为无 anchor，不清除协议 cache；
- scrolling/floating/tabbed Genie 与 alpha/scale fallback 仍由 layout space adapter 执行。

明确修复 F04：IPC 不得固定传 `None` 忽略已缓存 Dock rect。

## 目标设计落地

```text
foreign / IPC / xdg adapters
        │  only parse → LifecycleCommand
        ▼
State::execute_lifecycle_command
  1. find window + current output
  2. resolve Explicit | CachedForCurrentOutput | None
     (cache only when rect.output == window current output)
  3. try apply_lifecycle_with_snapshot (renderer + xray)
  4. else apply_lifecycle (same model path)
  5. LifecycleCommandResult { Applied | NoOp }
```

`LifecycleInvocationSource` 仅 trace/metadata，不改变动画策略。

## 旧路径删除

```text
rg -n 'set_minimized_with_rect|minimize_window_with_snapshot|restore_window_with_snapshot|minimize_window_with_target|restore_window_with_source|minimize_window_with_animation|restore_window_with_animation' niri/src
```

作者验证结果：**零命中**。

保留（非平行策略入口）：

- `Layout::minimize_window` / `restore_window`：layout 单测 model-only helper，内部仅 `apply_lifecycle(..., None)`；
- floating/scrolling `set_minimized` / `minimize_with_snapshot` / `restore_with_snapshot`：space adapter，仅由 layout lifecycle 方法调用；
- Wayland trait `set_minimized`/`unset_minimized`：协议 adapter，无策略。

## 测试

| 命令 | 结果 |
| --- | --- |
| `cargo fmt --all` | 已格式化（nightly wrap 选项告警可忽略）；无关 fmt 改动已还原 |
| `cargo test -p niri --lib lifecycle_command` | 5 passed |
| `cargo test -p niri --lib layout::tests` | 133+ passed（含 restore_rejects） |
| `cargo test -p niri --lib -- lifecycle_command lifecycle_observe foreign_toplevel xdg_toplevel_set_minimized coords minimize` | 38 passed |

未运行：完整 `cargo test -p niri`（时间）；嵌套会话手测 multi-output Dock（wrong-output 与 foreign rectangle 单测覆盖策略）。

### 关键不变量断言

- foreign / IPC / xdg 最小化后 `is_minimized` 一致；IPC 在 cache 命中时产生 Genie minimize overlay；
- duplicate minimize/restore → `NoOp`；
- 无 renderer + `None` anchor：状态仍切换，无 overlay；
- wrong-output cache：状态切换，cache 保留，不按错误输出做 Genie。

## 性能

正确性/ownership 修复；无帧时间声称。

## 独立审查专属问题（作者自查）

1. 三种入口是否真正到达同一策略 owner？是：均 `execute_lifecycle_command`。
2. cache 选择是否只发生一次且基于 current output？是：仅 command 内 `CachedForCurrentOutput` 分支，`rect.output == window_output`。
3. renderer 失败是否会留下半完成态？否：`with_primary_renderer` 为 `None` 时走同一 `apply_lifecycle`；snapshot 路径失败则 `set_minimized` 未成功时不启动动画。
4. 是否通过新增带 rectangle 的 IPC 或第四条协议绕开收敛？否：未新增 IPC 字段；IPC 复用 cache 模式。
