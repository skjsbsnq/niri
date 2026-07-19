# R14 · 锁屏动效包 · 2026-07-19

覆盖问题：#38 #39 #40（余）。

## 实施摘要

- session-lock surface 内部增加进入 fade + 10px 轻位移；认证成功后整体 fade/上移，最长 180ms 后才释放 ext-session-lock。surface 底色始终不透明，进入期不会暴露桌面。
- 失败路径统一到 `triggerAuthenticationFailure()`：启动失败、密码错误/次数过多、PAM error 都先清凭据，再将失败序号递增。每块输出 surface 的 shake 都执行 stop → 归零 → restart，约 300ms 三摆，连续失败不叠加。
- 密码框边框与 status 颜色/opacity 接入 Motion profile；status 保留旧文案到 fade-out 完成，不再被 `visible:false` 截断。
- 提交按钮换为 R13 `Controls.IconButton`，统一 hover、press、disabled opacity；按钮与输入在 PAM active / unlocking 时禁用。
- LockScreen 注入 `desktopSettings`。reduced profile 下 enter/exit/shake/颜色与 status duration 均为 0；R14 没有 SpringAnimation，`useSpring=false` 天然走同一 eased 路径。

## 安全与多屏边界

- `WlSessionLock.surface` 是每输出实例化的 Component。SystemClock、PamContext、退出序列和唯一 `credentialText` 改为锁根显式 typed properties，避免 clock/PAM 被误捕获进 surface、每屏重复实例化。
- 两块 surface 的 TextInput 通过根 `credentialText` 同步；根函数不再反向引用 surface 内 id。PAM 只启动一次，response 使用根唯一凭据。
- Success 进入退出动画前立即清除根凭据与所有 surface 输入；退出等待期间 `locked=true && secure=true`。动画完成后才 `locked=false`，mock 断言两块 surface 一起销毁。
- 退出时长为 `min(180ms, Motion.panelExit())`；reduced 为 0。选择短守卫延迟而不是“先 locked=false 再动画”，因为 Quickshell 在协议 unlock 时会立即销毁所有 surface，后者没有可见动画载体。
- 同任务修复既有 `lockClock is not defined` / `pam is not defined` 作用域风险；真实 nested lock 日志不再出现这两类错误。

## 审查

独立审查共三轮：

1. 初审发现成功淡出窗口仍保留凭据、测试未建模 `secure`、单屏 mock 无法验证 surface Component 边界。
2. 修复后复审要求成功链同时断言两块 surface 清密并释放。
3. 补齐双输入与 `surfaceInstances.length === 0` 后终审 **FINAL CLEAN**。

最终审查确认：失败 shake 重入、status fade、共享按钮、reduced、单 PAM owner、双屏凭据同步、secure 保持与 release 均无未解决 finding。

## 自动验收

- 锁屏专项与关联回归：`test_lock_screen_minute_clock.py` + `test_r13_correctness.py` → **15 passed**；扩展 QML probe 实际创建两块 surface。
- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -x -q -p no:cacheprovider tahoe-shell/tests/` → **793 passed, 230 subtests passed in 39.36s**。
- `qmllint -I quickshell/build-tahoe/qml_modules tahoe-shell/components/LockScreen.qml tahoe-shell/shell.qml` → 退出 0、无输出。
- `bash scripts/check-tahoe-glass-guardrails.sh`、`git diff --check` → 退出 0。
- 部署：`scripts/arch-update.sh --deploy-tahoe-shell` + `--verify-tahoe-shell` → parity OK，manifest `ce29c20d37908e147da703cfec3fbf614d5c10087720ea389d3578fff789800c`。

## 验收矩阵

- 真实 nested session：启动源码配置后通过 Tahoe IPC 调用 lock；`lockStatus` 依次为 `locked=false; secure=false`、请求后 `locked=true; secure=false`、1s 后 `locked=true; secure=true`。当前 LockScreen 日志无 ReferenceError、TypeError、Binding loop 或赋值错误；60s timeout 后隔离 compositor/SIGTERM 正常退出（预期 124）。
- 成功解锁：真实 QML probe 覆盖 Success 后两块输入立即清空、退出期 locked+secure 保持、≤180ms 后两块 surface 释放且 unlock 只发生一次。
- 失败：probe 覆盖 `pam.start()==false`、普通失败连续两次；失败序号逐次增加、输入清空、键入后错误态清除。shake restart 与红边/status 动画由 runtime object 实例化。
- 连续失败：动画每次 stop/归零/restart，不叠加；两屏共用同一凭据与 PAM，`startCount` 只增加一次。
- reduced：enter/exit/feedback duration 全为 0，成功同一事件循环释放；共享按钮 press scale 归 1。
- `useSpring=false`：无 SpringAnimation，空间路径全为 NumberAnimation。
- 多屏：Wayland mock 按生产默认 Component 机制创建两块 surface，验证同步输入、单 owner、secure 与销毁；真实 nested 环境验证协议握手。
- 深浅色：锁屏使用固定高对比暗色视觉，不依赖桌面 light/dark 切换；本任务未改变可读性配色。

## 范围外

- 自动化不向真实宿主会话提交用户密码；成功/失败 PAM 回调由真实 QML Pam mock 覆盖，真实 ext-session-lock 握手在隔离 nested compositor 中覆盖。
