# R06 · 菜单时序重排 · 2026-07-18

覆盖问题：#13（闪 4 拍后才动作）、#14（确认卡高度瞬跳）、#15（确认卡无进出动画）、#16（窗口/当前应用行动作为空）、#17（菜单行按压缩放出戏）、#19（AppMenuPopup refresh 整列表重建）。

## 改动摘要

- `Motion.js`：`menuFlashInterval` 70→55ms，`menuFlashCount` 保持 2；注释改为“动作已先发出，闪烁纯视觉”。
- `MenuRow.qml`：
  - 点击时**立即** `activated()`，再播闪烁；`flashFinished()` 在闪完/reduced 跳过/中途 abort 时发出。
  - 删除行级 `scale` + `Behavior on scale`（#17）。
  - `cancelFlash(emitFinished)`：成功路径不重复发信号；`!visible` / `onDestruction` 走 `cancelFlash(true)` 释放父级 hold。
- 六个菜单现场（MenuPopup / AppMenuPopup / TrayMenu / ProcessMenu / DockAppMenu / DockWindowMenu）：动作在 `onActivated`，关闭在 `onFlashFinished`。
- `MenuPopup.qml`：
  - 确认卡 `confirmHost`：`Layout.preferredHeight` 0↔90 + opacity 进出（eased），`clip` + visible 守卫；面板 `Behavior on implicitHeight` 仅 eased NumberAnimation（喂玻璃 region）。
  - 「窗口」→ `shellBridge.toggleWindowOverview()`；当前应用行 → `appMenuService.activateFocusedWindow()`。
  - `flashHold`（`holdSeq` token）：settings/overview 在 `activated` 里关掉 `appMenuOpen` 时 surface 仍映射至闪完；`ColumnLayout.enabled: open && holdSeq===0` 禁止幽灵点击与二次 arm；reopen 清 `holdSeq`，陈旧 `flashFinished` 不再关新菜单。
  - 电源项：`triggerPower` 只 `requestAction`；`finishRowFlash(!hasPending)` 让确认卡保持打开。
- `AppMenu.qml`：`nativeMenuItems` 按 `modelKey` 稳定 QtObject 缓存（merge/clear）；`itemId` 避开保留字 `id`；`label` 兼容旧测试。
- `AppMenuPopup.qml`：`ScriptModel { objectProp: "modelKey" }`。
- `shell.qml`：MenuPopup 接线 `appMenuService` + `shellBridge`。

## 审查

审查方式：2 个独立 reviewer 初审 + 1 个终审（当前工作树）。

| 轮次 | 结论 | 关键发现 |
| --- | --- | --- |
| Reviewer A（初） | FAIL | P1 幽灵菜单可点；P1 reopen 后陈旧 flash 关新菜单 |
| Reviewer B（初） | PASS | settings 闪被裁（后被 flashHold 覆盖）；双 height Behavior 为残余风险 |
| 修复 | — | holdSeq token + enabled 门控 + abort 发 flashFinished |
| 终审（当前树） | **FINAL PASS** | 无开放 P0/P1 |

残余可接受风险（不挡合并）：确认卡与闪烁约 220ms 重叠；`Layout.preferredHeight` Behavior 在部分 Qt 版本可能不插值（面板 implicitHeight 仍缓动）；separator modelKey 极端重复 id 碰撞；静态契约测试为主。

## 自动验收

- 专项：`tests/test_motion_token_convergence.py` + `tests/test_app_menu_demand_probe.py` → **34 passed**（含 R06 flash/hold/无 press scale/消费者 flashFinished/稳定缓存断言）。
- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -x -q -p no:cacheprovider tests/` → **764 passed, 217 subtests passed**。
- 玻璃守护：`bash scripts/check-tahoe-glass-guardrails.sh` → **passed**。
- 嵌套冒烟：`timeout 25s env NIRI_MODE=nested TAHOE_POWER_PROFILE=keep TAHOE_CONFIG_DIR=$PWD/tahoe-shell bash scripts/run-tahoe-session.sh` → 预期 timeout；无 MenuRow/MenuPopup/AppMenu TypeError/ReferenceError/binding loop。
- 部署：`arch-update.sh --deploy-tahoe-shell` + `--verify-tahoe-shell` → parity OK，manifest `12d18b2754f41b5abaa55814ad3d312a5eda90d3325e723d51bf80cf283691ee`。
- 本任务不改 KDL，`niri validate` 不适用。

## 宿主/手测矩阵

- 点「设置/关于」：动作立即发生；菜单闪约 220ms 后随合成器 pop-slide 关闭（flashHold 保映射）。
- 点「窗口」：打开 Window Overview；当前应用行：activateFocusedWindow。
- 点「重启/关机/睡眠/退出登录」：确认卡 height+opacity 展开，面板高度平滑；取消折叠；确认执行后关闭。
- 点「锁定」：闪后关闭并锁屏路径。
- reduced：跳过闪，同帧 flashFinished。
- 六个菜单现场：动作先、关闭后；无按压缩放。
- AppMenu 打开 refresh：ScriptModel 稳定 key，存续行不整表闪（服务层 merge）。
- Esc/点外关闭、深浅色、useSpring=false：无新增弹簧路径。

## 方案决策

1. **activated 立即 / flashFinished 关闭**（对齐 macOS 感知链路），而非缩短等待后再 activated。
2. **MenuPopup 专用 flashHold**：仅此菜单的动作会在 activated 里 `closeTopBarPopups`；其它菜单关闭由 flashFinished 独占，无需 hold。
3. **holdSeq token** 而非引用计数：reopen 直接作废陈旧 finish，避免双 close / 误关。
4. **当前应用行接 activateFocusedWindow**（与 AppMenuPopup「显示窗口」同语义），「窗口」接 overview；不新增平行 shell API。
5. ConfirmButton hover/press 仍归 R13，本任务不合并控件。

## 范围外发现

- ConfirmButton 内联 hover 瞬切（#18）→ R13。
- 菜单 layer-rule 关闭参数 → R15。
- TrayMenu 系统模型无 ScriptModel objectProp（非 nativeMenuItems 路径）→ 非本任务 #19 范围。
- `topBarDismissPopupHeight` 与菜单真实高度可能不完全一致（既有）。

## 后续修复（同日用户反馈：确认卡不丝滑/闪烁）

根因与修补（第二提交）：

1. 电源 keep-open 行误 `armFlashHold()` → `holdSeq≠0` 时整列 `enabled=false`，闪完再启用造成整卡闪。改为这些行不 arm hold。
2. 行选中闪烁与确认卡展开同帧重叠。keep-open 行（睡眠/退出/重启/关机）设 `flashOnActivate: false`。
3. `Behavior on Layout.preferredHeight` 不可靠。改为单一 `confirmReveal` 实属性 + `Behavior on confirmReveal`，`implicitHeight` 与 `slotHeight` 都绑定它。

验收：`test_motion_token_convergence` 更新断言；全量 764 全绿；host redeploy parity OK。
