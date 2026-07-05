# Tahoe 任务桌面反腐化路线图阶段 2 验收记录

日期：2026-06-30

状态：完成

范围：`task-desktop-research-roadmap-2026-06-30.md` 阶段 2：锁屏入口统一。本阶段只统一快捷键、电源菜单、idle 和健康页锁屏路径，不做缩略图 provider、命令 provider、搜索扩展、设置写入边界或 XWayland 兼容性改造。

## 修改范围

- 修改 `tahoe-shell/shell.qml`。
  - 新增 Tahoe lock IPC：`lock()`、`lockFrom(source)`、`lockStatus()`。
  - 新增 `requestLock(source)`，所有 IPC/idle 锁屏请求都通过 `Power.requestAction("lock")` 进入既有 `LockScreen.qml`。
  - 接入 Quickshell Wayland `IdleMonitor`，默认 `TAHOE_IDLE_LOCK_SECONDS=600`；设置为 `0` 可关闭 idle 锁屏，便于 smoke test 或调试。
- 修改 `config/niri/tahoe-phase0.kdl`。
  - `Super+Alt+L` 从直接 `spawn "swaylock"` 改为调用 Tahoe lock helper/IPC。
- 新增 `tahoe-shell/scripts/tahoe-lock.sh`。
  - fallback 顺序为 Tahoe IPC -> `loginctl lock-session` -> `swaylock` emergency fallback。
- 修改 `tahoe-shell/services/SystemStatus.qml`。
  - 健康页新增 `Tahoe 锁屏路径` 状态，检查 `LockScreen.qml`、IPC、idle monitor、快捷键 helper 和 emergency fallback。
- 修改 `scripts/README.md`。
  - 明确 `swaylock` 是 emergency lock fallback。
- 更新 `task-desktop-research-roadmap-2026-06-30.md`。
  - 标记阶段 2 完成，并补充完成确认。

## 保留的行为边界

- 未删除 Tahoe `LockScreen.qml`。
- 未替换 PAM 认证路径。
- 电源菜单仍调用既有 `Power.requestAction("lock")` -> `LockScreen.lock()`。
- `swaylock` 未删除，但只在 Tahoe IPC 和 `loginctl lock-session` 不可用时作为 emergency fallback。
- 未改动阶段 3 以后的缩略图、搜索、命令 provider、设置写入或兼容性路径。

## 验证命令

```bash
git diff --check -- tahoe-shell/shell.qml tahoe-shell/services/SystemStatus.qml tahoe-shell/scripts/tahoe-lock.sh config/niri/tahoe-phase0.kdl scripts/README.md tahoe-shell/docs/task-desktop-research-roadmap-2026-06-30.md
bash -n tahoe-shell/scripts/tahoe-lock.sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/shell.qml tahoe-shell/services/SystemStatus.qml
niri/target/release/niri validate -c config/niri/tahoe-phase0.kdl
TAHOE_IDLE_LOCK_SECONDS=0 timeout 18s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell
/home/wwt/.local/bin/quickshell ipc --id 11al5ecfht show
/home/wwt/.local/bin/quickshell ipc --id 11al5ecfht call tahoe lockStatus
```

## 验证结果

- `git diff --check` 退出 0。
- `bash -n tahoe-shell/scripts/tahoe-lock.sh` 退出 0。
- `qmllint` 退出 0。
  - 仍有既有 `modelData` unqualified warnings；本阶段不做全文件 lint 整理。
- `niri validate -c config/niri/tahoe-phase0.kdl` 退出 0，输出 `config is valid`。
- repo-path Quickshell smoke 到达 `Configuration Loaded`；`timeout` 退出 124 为预期。
  - 运行时仍有既有 Dock 动画 interceptor warning、`Qt.application.font` 只读 warning、notification server 已占用 warning、portal app id warning。
  - 未出现 QML load failure、`ReferenceError`、`SyntaxError` 或新增 `IdleMonitor` 加载错误。
- 用临时实例 id `11al5ecfht` 查询 IPC，确认新增方法已暴露：
  - `function lock(): string`
  - `function lockFrom(source: string): string`
  - `function lockStatus(): string`
- `lockStatus` 返回：

```text
locked=false; secure=false; source=; idleEnabled=false; idleTimeoutSeconds=0
```

这里 `idleEnabled=false` 是 smoke test 显式设置 `TAHOE_IDLE_LOCK_SECONDS=0` 的结果；默认运行时为 600 秒。

## 验收清单

- 快捷键入口不再直接调用 `swaylock`，而是先调用 Tahoe lock helper/IPC。
- 电源菜单入口继续走 Tahoe `LockScreen.qml`。
- idle 锁屏接入 `IdleMonitor`，触发时调用同一个 `requestLock("idle")` -> `Power.requestAction("lock")` 路径。
- 解锁失败仍由 `LockScreen.qml` 显示 `密码不正确`、`认证次数过多` 或 PAM 错误。
- 解锁成功仍通过 PAM success 调用 `unlock()`，关闭 Tahoe lock surface。
- `swaylock` 已明确为 emergency fallback，只有 Tahoe IPC 和 `loginctl lock-session` 不可用时才尝试。
- 健康页新增 `Tahoe 锁屏路径` 状态。

## 未自动触发项

- 本轮没有调用 `lock` 或真实触发 `Super+Alt+L`/idle 锁屏，以避免自动锁住当前工作会话。自动验收覆盖 QML 加载、IPC 暴露、niri 配置有效性和源码路径；真实锁屏 UI、密码失败/成功交互应在当前桌面中人工触发确认。

结论：阶段 2 已完成。下一阶段只能进入阶段 3：缩略图 provider；不得夹带命令 provider、搜索扩展或设置写入边界改造。
