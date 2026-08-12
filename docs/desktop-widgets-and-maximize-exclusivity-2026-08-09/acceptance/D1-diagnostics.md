# D1 诊断记录：关闭窗口后 niri 显存线性增长

日期：2026-08-12
环境：RTX 4070 Laptop / 驱动 610.57.04 / niri 26.04（64635051）+ Tahoe fork，
2560×1600@240Hz scale 1.25，单输出。

## 复现基线（`nvidia-smi` 进程表，niri PID）

| 实验 | 结果 |
|---|---|
| 空闲 70 秒 | 稳定（867 MiB 不动） |
| 开/关 alacritty 800×635（逻辑）小窗 ×20 | 每轮恰好 **+8 MiB**，1326→1486，完美线性 |
| 开/关 300×80 大窗 ×1 | 一轮净增 **+125 MiB** |
| `window-close off` ×3 轮 | 仍每轮 +8 MiB（与关闭动画无关） |
| 关窗后 `do-screen-transition`（强制全量重绘） | 不释放 |
| Firefox 最大化开→关（用户实测） | 一次涨几十 MiB |

## 完整诊断（`NIRI_LIFECYCLE_DIAG=1` 重启后）

诊断构建：niri 侧 live 计数 + 关窗事件计数；smithay **仅本地**观察补丁
（cleanup 时输出 `buffers` / `dmabuf_cache` / `glDeleteTextures`，已移除不入库）。

受控循环：10 轮小窗 + 1 轮大窗（alacritty），同步采集 nvidia-smi 与
`~/.local/state/tahoe-niri/session.log`。

### 1. niri 侧全部保留结构在 churn 后归零（session.log `vram-diag live`）

| 指标 | 基线 | churn 后 |
|---|---|---|
| windows | 4 | 4 |
| unmapped_windows | 0 | 0 |
| root_surface | 11 | 11 |
| closing_layers | 0 | 0 |
| closing_entries（floating+scrolling） | 0 | 0 |
| unmap_snapshot_tiles | 0 | 0 |
| layer_surfaces | 5 | 5 |
| retained_blur_mib | 16.6 | 16.6（churn 中最高 23.0，随后回落） |

### 2. smithay 侧 buffer 表恒定 + glDeleteTextures 正常调用

- `buffers` 受控循环期间恒为 2（启动瞬间出现过 1）。
- `dmabuf_cache` churn 峰值 34，churn 后回到 30（基线）。
- **`glDeleteTextures` 有 161 条 cleanup 事件（合计 546 次调用），全部
  发生在 10 轮小窗阶段；含大窗轮共 268 条/683 次**——纹理已在 GL API
  层被 niri/smithay 释放。

### 3. 关窗事件计数（`lifecycle-diag 5s delta`，churn 期间抽样）

`window_closed +1..2/5s`、`dmabuf_hook +7/-6`、`surface_destroyed +7`、
`unmapped +1/-0`（映射路径 remove 未计为 -，live 计数恒 0，无残留）。

## 结论

**不是 niri / smithay 代码泄漏。** API 层资源全部释放（结构归零 +
glDeleteTextures 调用），但 nvidia-smi 每轮仍 +8 MiB 且不回落 →
**NVIDIA 驱动保留了已释放的纹理显存**（`[实测]`；具体机制是否即
`GLVidHeapReuseRatio` reuse heap 为上游推断 `[未确认]`，见
research-report D-4）。nvidia-smi 读的是「分配/保留」而非「实际在用」。

对照上游：niri-wm/niri#1869（plateau ~650MB–1GB，#3404 修复的是另一条
dead-surface-hook 路径，本 fork 已含）、#1962（wiki：profile 方案
2.5GiB→168MiB）、#4372（26.04+NVIDIA 同类现象，未结案）、
NVIDIA/egl-wayland#126（驱动启发式在组合器 GL 用法下保留不当，非真泄漏）。

## 修复（见 D5）

`~/.nv/nvidia-application-profiles-rc`：`GLVidHeapReuseRatio=0`，
procname 匹配 `niri`。装后重启会话，受控循环如实记录显存增长/回收行为
（短时未见立竿见影，判为驱动回收时序，见「补充实测」）。


## 补充实测（profile 已装后，2026-08-12 13:00 会话）

- 基线 148 MiB（与此前会话的 210–224 MiB 为无对照跨会话比较，不归因）。
- 10 轮小窗仍约每轮 +8 MiB（148→230，合计 +82），大窗一轮 +38 MiB；20 秒后不回落。
- 压力实验：同时开 3 个大窗（niri 323→469，总显存 978→1393），关闭后
  niri 仅回落到 439（-30），随后 120 秒持平；总显存回落到 ~1100。
- 结论：驱动回收为**部分 + 延迟 + 时序相关**（用户正常使用中偶见回落，
  开机场景回落快；受控高频 churn 场景不回落）。`GLVidHeapReuseRatio=0`
  已安装但短时实验未见立即生效，保留并建议长周期观察。


## 勘误与最终代码说明（2026-08-12，对抗性审查后修订）

- `glDeleteTextures` 口径：smithay 本地补丁按「每次 cleanup 批次的删除数」
  打印——10 轮小窗阶段共 **161 条 cleanup 事件（合计 546 次调用）**；
  含大窗轮共 **268 条 / 683 次**。文档正文的「161 次」指 10 轮阶段事件数。
- `dmabuf_cache` churn 峰值 **34**（正文「最高 33」不精确）；`buffers`
  在启动瞬间出现过 1，受控循环期间恒为 2。
- 早期诊断日志中的 `unmapped +1/-0` 来自中间构建（映射路径移除未计数）；
  最终交付代码四路径全部配对（`note_unmapped_removed` 在映射与销毁两处，
  `note_dmabuf_hook_removed` 在 destroyed 与 remove_default 两处）。
- 「profile 后基线略降（148 vs 210–224）」为跨会话无对照比较，不归因于
  profile；profile 效果以「短时未见立竿见影、待长周期观察」为准。
- 回归证据：`cd /home/wwt/niri/niri && cargo test` → **667 passed / 0 failed**
  （含 `lifecycle_diag` 三个测试与 lifecycle/thumbnail/blur 既有回归）。
