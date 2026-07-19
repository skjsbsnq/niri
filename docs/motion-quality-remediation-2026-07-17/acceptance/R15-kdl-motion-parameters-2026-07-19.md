# R15 · KDL 参数修正包 · 2026-07-19

覆盖问题：#6 #89 #95 #96 #97 #100。

## 实施摘要

- Spotlight close `scale-to 0.992 → 0.96`，与 open `scale-from 0.96` 对称；保留既有 110/80ms transform/opacity 时长，避免在没有收益证据时扩大参数面。
- Battery/WiFi/Fan/Clipboard/Tray-menu 状态弹窗组 open `opacity-from 0.84 → 0.68`；close 改为 `opacity-to 0`、120ms、`emphasized-accel`，不再零淡出后硬消失。
- 删除 Control Center、Notification Center、状态弹窗组 open/close 共 6 个无效 `distance 24`；仅保留一处注释说明 edge-reveal 固定使用完整 surface extent。
- Window open/close scale `0.97 → 0.94`，保留 bounded native `220/180ms ease-out-cubic`；未引入 spring、shader 或扩大绘制区域。
- 既有 `MOTION_PROFILE_LAYERS.small_popup` 同步 balanced/fast/liquid：open 0.68，close 完全淡出，时长梯度 90/120/140ms；reduced 保持 0 transform + 60–80ms 纯 opacity。这样切换 motion profile 不会覆盖本任务修复。

## 方案决策

- Tray-menu 维持状态弹窗 edge-reveal 组，不迁入 pointer pop-slide。其 layer-shell anchor 是 surface 左上角而非点击按钮；迁入 anchor 会拉伸玻璃，pointer 又依赖 map-time seat。当前注释与精确 namespace 分组测试共同固定该决策。
- #100 采用 0.94 scale，但不改时长：更清晰的 zoom 感来自幅度，不用延长生命周期或引入被性能注释禁止的 spring。
- Spotlight 只改对称 scale，不改 duration；open 使用 spring、close 使用 bounded ease，本就不要求数值镜像。
- `niri_settings_tool.py` 只同步既有 LAYER profile 的值，不新增字段/接口；`MOTION_PROFILE_SPRINGS`、`ANIM_ACTIONS` 和四个 GUI 管理节点零改动。

## 审查

独立逐 diff 审查结论 **CLEAN**：

- KDL 产品 diff 仅落在 `window-open/window-close` 与目标 layer-rule。
- 所有 edge-reveal phase 均无 `distance`；pop-slide/toast 的有效 4/22/28px distance 保留。
- Spotlight、状态弹窗组、profile roundtrip、tray-menu 分组和 reduced 路径均有精确 block/phase 测试。
- 曲线名均为 niri 已注册词汇；MOTION_PROFILE_SPRINGS 与四管理节点零 diff。

## 自动验收

- R15 专项：`test_edge_reveal_semantics.py` + `test_niri_settings_tool.py` → **29 passed, 20 subtests passed**。
- profile roundtrip：fast/balanced/liquid/reduced 均能识别；切回 balanced 与当前 KDL 字节一致。
- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -x -q -p no:cacheprovider tahoe-shell/tests/` → **795 passed, 234 subtests passed in 40.22s**。
- 源码与部署配置：
  - `/home/wwt/.local/bin/niri validate --config config/niri/tahoe-phase0.kdl` → 通过。
  - `/home/wwt/.local/bin/niri validate --config ~/.config/niri/tahoe/config.kdl` → 通过。
  - `cmp` 源码/部署 KDL → 字节一致。
- 完整部署：以 `BUILD_XWAYLAND_SATELLITE=false`、关闭 session-entry 写入的安全环境运行 `scripts/arch-update.sh`，仍走原生 guardrail、Tahoe shell 与 niri config deploy；manifest `a9a3dc97146e83074871775143d9a19ff3d94cfcfb9282a524f65feda39e1d90`，shell parity OK。
- 父仓与两个子模块提交均未被部署流程改变。

## 验收矩阵

- nested compositor 实际加载新 KDL；Spotlight、Battery、WiFi、Fan、Clipboard 分别 open/close ×3 快速循环，Quickshell 日志无 ReferenceError、TypeError、Binding loop、snapshot 或动画 warning。
- 窗口 open/close：nested niri 中启动并关闭 Alacritty ×3，0.94 bounded native scale 路径无异常。
- 状态弹窗服务不可用/空态由现有 QML 保持；R15 只改 compositor map/unmap 参数，不改数据链路。
- reduced：profile 表保持 transform=0，close 仍完整到 opacity 0；fast/balanced/liquid 时长按档位递增。
- Tray-menu：维持现组，精确 namespace 测试与 anchor 注释通过；未引入第二条动画规则。
- `MOTION_PROFILE_SPRINGS` 管理面、workspace/window movement/resize/overview 四节点零改动。
- 宿主配置已部署但未强制重启 niri，避免中断当前工作会话；新配置已在隔离 nested compositor 完整加载和回归。

## 范围外

- Control Center / Notification Center 仍保持原有 opacity 参数；R15 对它们只删除无效 distance，不提前改变 R18 之外的观感。
