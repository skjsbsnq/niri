# T07 · Dock 放大与推挤重写 · 验收记录

日期：2026-07-11

## 实现范围

- **余弦钟形放大**（`Motion.js`）：
  - `dockMagPeak = 1.7`、`dockMagRangeIcons = 2.5`
  - `dockCosineScale(d, iconSize)`：`1 + (peak−1)·cos²(πd/2R)`，R = 2.5×图标宽
  - `dockMagSpring`：`{ spring: 3.2, damping: 0.42, epsilon: 0.001 }`（近临界，波形无过冲）
- **解析式推挤**（`Dock.qml`）：
  - 按索引计算 rest center → scale/width/x，**不读 delegate 几何**（杜绝绑定循环）
  - pinned 行由 `Row` 改为 `Item` + 显式 `x`/`width`；`pinnedScaleAt` / `pinnedItemXAt` / `pinnedItemWidthAt` / `pinnedWaveContentWidth`
  - 窗口半区 icon-only 模式走 `windowScaleAt(index)`（标题模式不放大以免 reflow）
- **图标基准 46→56**，槽位/面板/exclusiveZone 重算：
  - `dockIconSize=56`、`dockPinnedButtonWidth=72`、`dockWindowIconWidth=68`、`dockToolButtonWidth=64`
  - `dockSurfaceHeight=96`、`exclusiveZone=112`、`implicitHeight=150`、`sourceSize` 图标 ≤128
- **磁贴间距弹簧联动**：x/width/magnification 经显式 `SpringAnimation`/`NumberAnimation` 双分支（`useSpring` 门控）向解析目标 settle
- **hover 标签三合一**：`dockHoverLabel` 统一 pinned / window / tool；13px；即时出现（无 y 滑移）；仅 opacity fade
- **双 Behavior interceptor 修复**（T00 待办）：Qt 同一属性只能挂一个 Behavior；改为显式 dual-branch 动画对象，冒烟日志 `another interceptor` = 0
- 治理测试：`test_motion_token_convergence.py` 新增 dock mag token / 解析式波形 / 统一标签 / 无 dual Behavior 断言

**本任务不改**：启动循环弹跳、autohide spring（归 T08）；玻璃 region 几何未弹簧。

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `cd tahoe-shell && python -m pytest tests/ -x` | PASS，**88 passed**（+2 相对 T06） |
| quickshell 冒烟（`timeout 12s qs -p tahoe-shell`） | PASS，`Configuration Loaded`；**interceptor=0**；**Binding loop=0**；无 Dock/WindowButton QML 错误 |
| `git diff --check` | 提交前再跑 |

### 机械验证

```
rg -n '1 - distance / 135|influence \* 0.34' tahoe-shell/components/Dock.qml
→ 无匹配（线性三角已移除）

rg -n 'Motion.dockCosineScale|pinnedItemXAt|dockMagPeak' tahoe-shell/components
→ Motion.js + Dock.qml 命中

rg -n 'id: hoverLabel|id: toolLabel|id: windowHoverLabel' tahoe-shell/components/Dock.qml
→ 无匹配（三标签合并为 dockHoverLabel）

rg -n 'Behavior on magnification|Behavior on bounceOffset' tahoe-shell/components/{Dock,WindowButton}.qml
→ 无匹配（显式 dual-branch）

rg -n 'dockIconSize: 56|exclusiveZone: 112' tahoe-shell/components/Dock.qml
→ 命中
```

## 手测 / 行为说明

- 光标扫过 pinned 图标：余弦波形 peak 1.7、邻图标被解析式推开，表面在仅 pinned 时随波展宽；有窗口半区时 Flickable 吸收溢出。
- 拖拽重排 / 右键菜单 / 最小化收纳架：路径未改，reorder 时 `pointerDragActive` 关掉波形。
- reduced / `useSpring=false`：走 `NumberAnimation` 分支，无弹簧。
- 标签：hover 即时 13px 胶囊，离开 fade；无 y 滑移。

## 性能（对照 T00）

| 进程 | T00 RSS | 当前 RSS（运行会话） | 备注 |
| --- | --- | --- | --- |
| niri | 211,844 KB ≈ 206.9 MB | 210,256 KB ≈ 205.3 MB | 略降，非本任务引入 |
| quickshell（部署副本） | 584,292 KB ≈ 570.6 MB | 577,616 KB ≈ 564.1 MB | 冒烟实例已退出；部署副本未加载 T07 源 |

冒烟实例为第二实例（portal/通知 server 冲突为既有基线）。帧感受：波形走 Behavior 框架等价路径（显式 Spring/Number），无 per-frame JS Timer。

## 基线警告（非 T07 引入）

- `shell.qml:479` font 只读 TypeError
- `StartupPage.qml:358` `addCandidateRow` ReferenceError
- 第二实例 portal / notifications 注册失败

## 发现待办

- 窗口半区仍为 Row + 定宽槽，仅 scale/lift 波形（不做解析式推挤），避免标题模式 reflow；若后续要窗口半区也推挤，可镜像 pinned 的 x/width 路径。
- 运行指示点辉光 / 启动循环弹跳 / autohide spring → **T08**。
- 部署副本 `~/.config/quickshell/tahoe` 需用户侧同步/重启 shell 才能看到 T07（本任务只改仓库源）。

## 结论

T07 清单全部落地：余弦波形 + 解析式推挤 + 图标 56 + 标签合并 + useSpring 双分支（且消除 interceptor 警告）；治理测试同提交；可单独 `git revert` 回滚。
