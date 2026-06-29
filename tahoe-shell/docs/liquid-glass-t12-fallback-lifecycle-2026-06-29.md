# T12 TahoeGlass fallback 与生命周期收敛完成记录

日期：2026-06-29

## 范围

T12 只处理 Quickshell Wayland attached surface 生命周期、TahoeGlass 到 BackgroundEffect 的 fallback 切换，以及 niri layer-rule fallback profile 同步。不改 TahoeGlass 协议、不改 shader、不让业务 QML 直接接触 BackgroundEffect。

## 完成项

1. `AttachedSurfaceLifecycle` 现在负责处理 backing `QWindow` 替换：
   - 新窗口接入前解绑旧窗口 event filter 和信号。
   - 旧 `QWaylandWindow` 切换时统一触发 surface/window 清理。
   - `surfaceCreated` / `surfaceDestroyed` 回调去重，避免重复 attach 或重复清理。

2. `BackgroundEffect` reload 抢占更明确：
   - 新 attached object 从旧对象偷取 ext-background-effect protocol surface 后，旧对象清空 pending blur 状态。
   - 旧对象已经脱离 `ProxyWindowBase` 时安排 `deleteLater()`，避免 reload 后悬挂对象继续持有状态。

3. `TahoeGlass` protocol/fallback 切换更稳：
   - surface about-to-destroy、surface destroyed、Wayland window destroyed 时清理 fallback blur region。
   - 新 TahoeGlass 对象 reload 抢占旧 protocol surface 后，旧对象停止 pending region 并退出可用状态。
   - TahoeGlass 协议可用时清掉旧 fallback，避免 TahoeGlass 和 BackgroundEffect 同时作用于同一 surface。
   - TahoeGlass 协议不可用时，fallback 仍只在 TahoeGlass client 内部创建 `BackgroundEffect.blurRegion`。

4. `config/niri/tahoe-phase0.kdl` fallback profile 已同步：
   - `panel` fallback block 继续对齐 `tahoe-glass` 的 `panel` material。
   - 菜单 fallback 独立对齐 `menu` material。
   - `NotificationToast` fallback 独立对齐 `toast` material，不再混用菜单参数。

## 验收

已通过：

- `bash scripts/check-tahoe-glass-guardrails.sh`
- `ninja -C quickshell/build-tahoe quickshell-wayland-attached-surface-lifecycle quickshell-wayland-background-effect quickshell-wayland-tahoe-glass`
- `cargo run --manifest-path niri/Cargo.toml -p niri -- validate -c /home/wwt/niri/config/niri/tahoe-phase0.kdl`

说明：

- `/usr/bin/niri validate` 是系统安装的 `niri 26.04 (8ed0da4)`，不认识本仓库新增的 `tahoe-glass`、`snap-assist` 和 layer animation 字段；本次验收使用仓库内当前源码构建的 `niri/target/debug/niri validate`。
- 当前环境未执行 live Quickshell 热加载和 niri log 观察；该项需要在实际图形会话中验证，随 T13 视觉基线一起补采。

## 结论

T12 已完成代码侧和配置侧收敛。业务 QML 仍只声明 `TahoeGlass.regions`；fallback 仍被封装在 Quickshell TahoeGlass client 内部；guardrail 已覆盖业务 QML 直接使用 `BackgroundEffect` / `blurRegion` 的禁用规则。
