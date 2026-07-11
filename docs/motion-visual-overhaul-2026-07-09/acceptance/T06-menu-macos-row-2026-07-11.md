# T06 · 菜单 macOS 化 + MenuRow 合并 · 验收记录

日期：2026-07-11

## 实现范围

- 新建共享组件：
  - `tahoe-shell/components/MenuRow.qml`：行高 26、字 13px、radius 6；hover/press = accent 蓝（`#007aff` / 深色 `#0a84ff`）实心 + 白字（含图标）；destructive 红字；disabled 半透明；点击后闪两下（`Motion.menuFlashInterval=70` × `menuFlashCount=2`）再 `activated`；reduced profile 跳过闪烁即时激活；按压缩放继续走 `Motion.pressScaleFor` / `pressDurationFor`。
  - `tahoe-shell/components/MenuSeparator.qml`：内缩 10px 分割线，色 `#1a000000` / 深色 `#1affffff`。
- `Motion.js` 新增 `menuFlashInterval` / `menuFlashCount` 作为菜单闪烁唯一出口。
- **替换 6 处内联 MenuRow**（零 `component MenuRow` 残留）：
  - `MenuPopup.qml`
  - `AppMenuPopup.qml`（含原 `NativeMenuRow` → 共享 `MenuRow` + `showCheckColumn` / `header` / `indent` / `hasSubmenu`）
  - `TrayMenu.qml`（原 `MenuEntry` → 共享 `MenuRow`）
  - `DockAppMenu.qml`
  - `DockWindowMenu.qml`（含工作区列表行）
  - `ProcessMenu.qml`
- 六菜单均新增 `darkMode` 属性；`shell.qml` 为 MenuPopup / AppMenuPopup / DockAppMenu / DockWindowMenu / TrayMenu 接线 `darkMode: shell.darkMode`（ProcessMenu 原本已接）。
- 分割线统一 `MenuSeparator`（`#1a000000` 内缩）。
- 闪烁期间 `MouseArea.enabled=false` + `flashing` 门闩，防连点重入；菜单关闭/销毁时 `cancelFlash()`。
- 治理测试同步：`test_motion_token_convergence.py` 改按 `MenuRow.qml` 计 press 出口，并新增 flash token / 共享行签名 / 六菜单零内联断言。

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `cd tahoe-shell && python -m pytest tests/ -x` | PASS，86 passed |
| `git diff --check` | PASS |
| quickshell repo 冒烟（`timeout 12s qs -p /home/wwt/niri/tahoe-shell`） | PASS，`Configuration Loaded`；无 MenuRow/MenuPopup/ProcessMenu/MenuSeparator 相关 QML 错误 |

### 机械验证（全调用点）

```
rg -n 'component MenuRow|component MenuEntry|component NativeMenuRow' tahoe-shell/components
→ 无匹配（六处内联全部消除）

rg -n 'MenuRow \{' tahoe-shell/components/{MenuPopup,AppMenuPopup,TrayMenu,DockAppMenu,DockWindowMenu,ProcessMenu}.qml
→ 六文件均消费共享 MenuRow

rg -n 'menuFlashInterval|menuFlashCount' tahoe-shell/components/Motion.js
→ 导出齐全
```

## 手测 / 行为说明

- 选中闪烁：非 reduced 路径点击 → 高亮 ON/OFF 两轮（~280ms）→ `activated` → 父菜单 `closeRequested()`（合成器 layer 关闭动画承接“整菜单淡出”）。
- reduced：治理测试锁定 `Motion.reducedMotion` 分支直接 `activated`，无 Timer。
- Esc / 点外关闭：ProcessMenu 仍 `Keys.onEscapePressed` + `PopupDismissLayer`；其余菜单背景 `MouseArea` / dismiss 层路径未改。
- 闪烁中再点：`flashing` 门闩 + MouseArea 禁用，不重入。

## 基线警告

冒烟仍见 T00/T05 已记录既有警告：`shell.qml:479` font 只读、`StartupPage.qml:358` `addCandidateRow`、第二实例 portal 注册失败、Dock 双 Behavior interceptor。均非 T06 引入；Dock interceptor 归 T07/T08。

## 发现待办

- 菜单关闭动画仍由 compositor layer-rule 主导；QML 侧未再叠一层 opacity 淡出（避免与 compositor 双轨）。若未来 `compositorLayerAnimations=false` 要在 QML 侧显式“闪完再淡出再动作”，可在共享协调器里加 deferred action 队列——本任务不扩 scope。
- 顶栏/托盘菜单 header 行仍是自定义 RowLayout（非 MenuRow），仅操作行统一；与 roadmap“替换 6 处内联 MenuRow”一致。
- accent 色目前写在 MenuRow 内（`#007aff`/`#0a84ff`），待 T14 颜色语义化收编进共享 token。

## 结论

T06 清单全部落地：共享 MenuRow 合并六菜单、macOS 三签名（蓝高亮 + 选中闪烁 + 统一字号行高）、分割线内缩、治理测试同提交更新；可单独 `git revert` 回滚。
