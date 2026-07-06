# GOAL-9 验收：内存与高频分配治理

日期：2026-07-06

范围：只处理 GOAL-9 中已确认的内存和高频分配热点：Xray filtered damage、snapshot/texture 生命周期检查、thumbnail provider cache/queue burst 行为。不进入 GOAL-10 默认策略。

## 完成了什么

- `niri/src/render_helpers/xray.rs`
  - 新增内部 `XrayElementCache`，通过 smithay `UserDataMap` render element cache 复用 `filtered_damage`。
  - `XrayElement::draw()` 没有 subregion 时不再创建 filtered damage `Vec`。
  - 有 subregion 且 render cache 存在时，使用缓存 `Vec::clear()` 后重新填充；只有没有 cache 的兜底路径才按当前 damage 数量创建临时 `Vec`。
  - 抽出 `draw_texture()`，保持原有 texture render path、uniform、opacity、transform 和 program 语义不变。
- `tahoe-shell/services/ThumbnailProvider.qml`
  - 保留唯一 provider、唯一 runtime cache 目录和现有 `niri msg --json window-thumbnail` IPC。
  - cache state 改为 provider 内部直接 keyed mutation，不再每次 state create/delete 复制整个 JS object。
  - queued key set 改为直接 mutation，不再 enqueue/dequeue/remove 时复制 `queuedKeys` object。
  - queue 改为 cursor-backed storage：enqueue 用 `push`，dequeue 用 `queueHead` 前移，只有达到 compaction 阈值才切片压缩 storage。
  - 保留 queue overflow、refreshPending、active job cancel、image failure fallback 和 stale thumbnail cleanup 语义。
- 新增 `tahoe-shell/tests/test_memory_allocation_governance.py`
  - 覆盖 Xray filtered damage 不回退到每 draw `Vec::new()`。
  - 覆盖 thumbnail provider 继续使用单一 cursor-backed queue，不恢复 concat/slice(1)/copyObject hot path。
  - 覆盖 GOAL-7 snapshot 生命周期回归测试仍然存在。

## 优化前后对比

GOAL-0 live RSS baseline at `2026-07-06T19:10:40+08:00`:

| Process | Before RSS KiB |
| --- | ---: |
| `quickshell` | 502832 |
| `niri` compositor | 178112 |
| `niri msg --json event-stream` | 15824 |

GOAL-9 drift snapshot after source changes:

| Process | Current RSS KiB | Notes |
| --- | ---: | --- |
| `quickshell` | 560680 | Running `/home/wwt/.config/quickshell/tahoe`, not this edited source tree |
| `niri` compositor | 176496 | Running installed `/home/wwt/.local/bin/niri`, not rebuilt from this source change |
| `niri msg --json event-stream` | 15824 | unchanged service child |

This is not claimed as a live after-RSS win because GOAL-9 did not deploy/restart Quickshell or rebuild/restart the compositor. The trustworthy after comparison for this gate is source-level allocation behavior:

| Hot path | Before | After |
| --- | --- | --- |
| Xray draw without subregion | Allocated a fresh `Vec` before checking subregion | No filtered damage storage is created |
| Xray draw with subregion and render cache | Fresh `Vec::new()` every draw | Reused `UserDataMap` cache `Vec`, cleared per draw |
| Xray draw with no render cache | Fresh `Vec::new()` every draw | Temporary `Vec::with_capacity(damage.len())` fallback only |
| Thumbnail enqueue | `copyObject(queuedKeys)` plus `queue.concat([key])` | direct `queuedKeys[key] = true` plus `queue.push(key)` |
| Thumbnail dequeue | `queue.slice(1)` plus `copyObject(queuedKeys)` every job | `queueHead += 1`, direct delete, occasional compaction |
| Thumbnail state create/delete | copied whole `cache` object | direct provider-owned keyed mutation |

Thumbnail burst model for 64 unique requests:

- Before: 64 queue array copies on enqueue, 64 queue array copies on dequeue, and queued-key object copies on both enqueue and dequeue.
- After: 64 enqueue pushes, 64 cursor advances, direct keyed mutation, and one storage compaction at the 32-item threshold.
- Runtime cache files remained in the same directory and same shape: `window-2.png`, `window-3.png`, `window-5.png`, `window-7.png`; total `92897` bytes.
- No active `window-thumbnail` child process remained in the GOAL-9 drift snapshot.

## Snapshot 和 texture 生命周期检查

- Snapshot lifecycle is covered by the GOAL-7 Rust tests that still pass:
  - `layer_animation_fast_toggle_settles_without_residual_snapshots`
  - `layer_close_snapshot_releases_one_frame_after_duration`
- Texture lifecycle was inspected in the existing render helpers:
  - `EffectBuffer::prepare_offscreen()` recreates offscreen texture on size change, non-unique reference, or renderer context change.
  - `FramebufferEffect` already keeps reusable framebuffer/blur/intermediate textures and reusable `subregion_damage`.
  - GOAL-9 did not change texture ownership or lifetime rules.

## 没有做什么

- 没有新增第二套 thumbnail provider。
- 没有新增第二套 thumbnail cache directory。
- 没有让组件直接 spawn `niri msg window-thumbnail`。
- 没有改变 thumbnail failure fallback、queue overflow fallback 或 stale cleanup。
- 没有改变 material、blur、animation profile 或 KDL 默认值。
- 没有部署到 `/home/wwt/.config/quickshell/tahoe`，没有 rebuild/install/restart `/home/wwt/.local/bin/niri`。
- 没有开始 GOAL-10。

## 复用了哪些现有接口

- smithay `UserDataMap` render element cache。
- Existing `XrayElement` / `EffectBuffer` render path。
- Existing `ThumbnailProvider.qml` provider contract。
- Existing niri IPC command `niri msg --json window-thumbnail`。
- Existing runtime cache directory `$XDG_RUNTIME_DIR/tahoe/window-thumbnails`。
- Existing GOAL-7 layer-shell snapshot tests。

## 是否新增接口

没有新增 runtime、IPC、config 或用户可见接口。

新增的是内部实现细节和测试：

- `XrayElementCache` private Rust helper。
- `queueHead` / `pendingQueueLength` private QML provider state。
- `test_memory_allocation_governance.py` source-level governance tests。

## 运行命令

```text
cargo check -p niri
python3 tahoe-shell/tests/test_memory_allocation_governance.py
python3 tahoe-shell/tests/test_thumbnail_provider_contract.py
python3 -m unittest discover tahoe-shell/tests
cargo test -p niri layer_shell
cargo test -p niri xray
cargo fmt
cargo fmt --check
cargo test -p niri tahoe_glass
/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
git diff --check
```

结果：

- `cargo check -p niri`：passed。
- `test_memory_allocation_governance.py`：3 tests passed。
- `test_thumbnail_provider_contract.py`：3 tests passed。
- Full `python3 -m unittest discover tahoe-shell/tests`：56 tests passed。
- `cargo test -p niri layer_shell`：18 tests passed。
- `cargo test -p niri xray`：compiled, 0 matching tests, passed。
- `cargo test -p niri tahoe_glass`：3 tests passed。
- `cargo fmt --check`：passed, with existing stable-toolchain warnings for unstable rustfmt options。
- `/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl`：config is valid。
- Parent and nested `git diff --check`：passed。

## 剩余风险

- Live after-RSS requires deploying the edited Quickshell source and rebuilding/restarting the compositor. GOAL-9 intentionally avoided restart/deploy churn, so this doc does not claim a live RSS reduction.
- The Xray no-cache fallback can still allocate a temporary `Vec`, but the normal render path has a `UserDataMap` cache and now reuses storage.
- QML array compaction still allocates occasionally by design; it is no longer on every dequeue.
- A long-running post-deploy session should re-run the GOAL-0 RSS and thumbnail cache commands to confirm real-world retention behavior.

## 回滚方式

- Revert `niri/src/render_helpers/xray.rs` to restore the old local filtered damage allocation.
- Revert `tahoe-shell/services/ThumbnailProvider.qml` to restore the old copy-on-mutation queue/cache behavior.
- Delete `tahoe-shell/tests/test_memory_allocation_governance.py`。
- Delete this acceptance document and revert the GOAL-9 status row.
