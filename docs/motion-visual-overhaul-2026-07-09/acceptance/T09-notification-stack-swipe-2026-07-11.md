# T09 · 通知堆叠与滑出 · 验收记录

日期：2026-07-11

## 实现范围

### 1. Motion.js toast stack tokens

| token | 值 |
| --- | --- |
| `toastStackMaxDefault` | 3 |
| `toastStackYStep` | 8 |
| `toastStackScaleStep` | 0.04 → scale 1.0 / 0.96 / 0.92 |
| `toastEnterOffsetPx` | 60 |
| `toastSwipeDismissPx` | 96 |
| `toastClearStaggerMs` | 30 |
| `toastClearStaggerBudgetMs` | 450 |
| `toastClearStaggerMaxItems` | 40 |
| `toastHoverLiftPx` | 4 |
| helpers | `toastStackScaleForIndex` / `toastStackYForIndex` / `toastClearStaggerDelay` |

### 2. DesktopSettings 字段

- `notificationToastStackMax`（JsonAdapter，默认 3，sanitize 钳制 1–3）
- `setNotificationToastStackMax(value)`
- 设置 → 通知页增加「横幅堆叠」1/2/3 分段

### 3. Notifications.qml

- `visibleStack(maxCount)`：newest-first 切片，供 Toast 多卡绑定
- `groupedHistory()`：按 `appName` 分组（历史已是 newest-first）
- 每条非 Critical 独立 `expireMap` + `armSoonestExpire`（栈内可独立超时，不绑 head）
- 保留 `current` / `dismissCurrent` / DND expire 路径

### 4. NotificationToast.qml

- 固定 3 slot（`stackSlot0..2`），无动态 Instantiator 残留
- 新卡：`enterX` 用 **springPanel**（`useSpring` 双分支 + reduced 走 ease）
- 旧卡：`stackY` +8 步进（**eased** 玻璃安全 y）；`contentScale` 0.96/0.92（content transform，eased）
- 顶卡 hover 浮起 + 左上 X；横滑 dismiss（`IslandMotion.swipeEnterThreshold` + `toastSwipeDismissPx`）
- 点击非动作区仍 dismiss；action 按钮保留
- 玻璃 region：`TahoeGlass.regions` 三槽；`regionEnabled` 随 active 关闭；**无 Spring 驱动 glass x/y/w/h**
- DND / 灵动岛抑制：`suppressedByDynamicIsland` 仍清空 stack 显示

### 5. NotificationCenter.qml

- 历史按 app 分组（`AppGroup`）；>2 条默认可收起，点「N 条」展开
- 「清空」→ stagger 飞出（30ms 步进，总预算 ≤450ms，≤40 项）→ `clearEverything()`
- 单条删除 / DND toggle 不回归

### 6. 治理测试

`test_motion_token_convergence.py`：
- `test_motion_exports_toast_stack_tokens`
- `test_notification_toast_stack_and_swipe`

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，92 passed**（+2 相对 T08） |
| quickshell 冒烟（`timeout 12s qs -p tahoe-shell -n`） | **Configuration Loaded**；无 NotificationToast/Center QML 错误；无 Binding loop |
| Spring 护栏 | Toast 内仅 1 处 `SpringAnimation`，且 `property: "enterX"` |

### 机械验证

```
rg -n 'visibleStack|groupedHistory|notificationToastStackMax|springPanel' \
  tahoe-shell/components/NotificationToast.qml \
  tahoe-shell/services/Notifications.qml \
  tahoe-shell/services/DesktopSettings.qml
→ 命中

rg -n 'SpringAnimation' tahoe-shell/components/NotificationToast.qml
→ 仅 enterX 一处

rg -n 'function setNotificationToastStackMax|property int notificationToastStackMax' \
  tahoe-shell/services/DesktopSettings.qml
→ 命中
```

## 手测矩阵（设计意图 / 本机说明）

| 项 | 结果 |
| --- | --- |
| `scripts/test-notification.sh spam 5` | 会话内 `notify-send` 已连发 5 条；**完整视觉堆叠需 reload 运行中的 quickshell**（当前会话仍加载 `~/.config/quickshell/tahoe`，非本工作树热更） |
| 堆叠最多 3 / 第 4+ 在 FIFO 等待 | 代码：`visibleStack(stackMax)` |
| 横滑 dismiss / 点击 dismiss / X | 顶卡 `swipeArea` + `closeBtn` |
| DND | 仍 `expire()` 不入 active 栈 |
| 灵动岛开启 | `suppressedByDynamicIsland` → 空 stack |
| 清空 stagger | `startClearAll` → tick → `finishClearAll` |
| 队列清空 | 固定 3 slot `active=false`，无 destroy 残留路径 |
| reduced / `useSpring=false` | enter 走 `enterEase`；scale 始终 ease |

## 红线自查（§2）

1. 玻璃 region 几何：y/x 仅 NumberAnimation；spring 仅 content `enterX`
2. `useSpring` 双分支：enter 有 spring/ease
3. 不新建 token 文件；扩展 Motion.js + DesktopSettings
4. 不删 DND / 灵动岛 / compositor 路径
5. 不引入 QtQuick.Controls
6. 既有 IPC / 通知服务 API 增量：`visibleStack` / `groupedHistory` / settings 字段

## 审查与修正（同任务 follow-up commit）

本地 `/review`（`/tmp/grok-1000/grok-review-f895f12c.md`）发现 3 个 bug，已修：

| # | 问题 | 修复 |
| --- | --- | --- |
| 1 | 清空 stagger 最后一 tick 立即 `clearEverything`，飞出动画来不及播 | `clearFinishHold`：末 tick 后等 `elementMove+40ms` 再 wipe |
| 2 | 顶卡 dismiss 后次卡 promote 误触发完整 enter 弹簧 | `prevStackIds` + `isNewlyAppearedId`：仅真正新 id 入场 |
| 3 | 排队未可见通知从入队即计时，可能未展示就 expire | `rearmVisibleExpires`：仅 visible stack 计时；升入栈才 arm |

次要：`Behavior on y` 双通道 → 只 Behavior `stackY`/`hoverLift`；scale 回到 contentHost；`dismissCurrent` 改为 dismiss 顶卡。

## 发现待办

- 运行中 shell 需用户 reload 后才能目测 3 卡堆叠与横滑（部署路径与仓库 `tahoe-shell` 可能不同步）。
- 堆叠 scale 在 content transform 上，region 仍报 rest 尺寸（略大于视觉卡）——与 T07/T08 glass 固定策略一致；若实机糊边再收紧。
- 通知中心分组展开无弹簧散开（roadmap 研究文提及；T09 改动清单写「按 app 分组」+ stagger 清空，展开为 height Behavior）。
- `compositorLayerAnimations` 对 toast 外层 slide 已不驱动（内容自管 enter）；若 niri toast layer 动画需对齐可后续接。

## 回滚

`git revert` 本任务提交（及 follow-up fix 提交）即可。
