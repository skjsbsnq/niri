# R17 · Dock 布局动画 · 2026-07-19

覆盖问题：#72 #73 #76 #77 #78 #79 #80 #81 #82 #90。

## 实施摘要

- `dockChrome`、固定区、活动窗口区、最小化区统一使用 `Motion.elementResize` eased 宽度过渡；可选 divider 与 spacer 也按宽度进退，避免 `Row.spacing`/`visible` 单帧跳变。glass region 只跟随 eased chrome 宽度，不引入 spring。
- 固定应用模型包装为 `{ modelKey, app }`，`modelKey` 来自持久化 pin ID；fallback app 后续解析为真实 DesktopEntry 时 delegate identity 仍保持，hover、放大、重排与启动弹跳状态不丢。
- pin/unpin/重排使用固定槽位 `x` Behavior；窗口按钮槽位 `x/width`、运行指示点宽度/颜色、统一悬停名牌 `x/y` 均补共享 token 过渡，移除旧的显式目标赋值双驱动。
- 最小化 shelf 改为稳定 `ListView`，补 add/remove scale+fade 与 move/displaced；缩略图把 lifecycle 与 press 输出相乘，hover 填充/边框平滑过渡。
- 全屏采用计划倾向的 QML 范式 B：Dock 向下淡出、TopBar 向上淡出，`visible: !fullscreenActive || opacity > 0.01` 保留退场帧，结束后才 unmap；未新增 layer-rule。
- Dock 右键菜单维持既有 compositor `pop-slide` + `origin "pointer"`，实机点击窗口图标后菜单从该指针锚点上方展开，无需再叠加 QML scale。

## 审查

- 首轮独立审查发现两项：固定区曾以解析后 app `id` 作 key；可选 divider/Row spacing 仍会跳变。两项均已修复并补治理测试。
- 第二轮独立逐 diff 复审结论 **CLEAN**：持久 pin identity、无窗口/单类窗口/双类窗口三种宽度算术、退场 visible 生命周期、WindowButton 与最小化缩略图单一输出均通过核验。
- 放大波、autohide、启动弹跳的既有输出未被替换；fullscreen 与 autohide 分别作用于内容 transform 的不同分量，glass region 仍只接受有界 eased 几何。

## 自动验收

- `git diff --check` → 通过。
- `qmllint` 对 5 个变更 QML 文件 → 退出码 0。
- R17 + motion convergence + direct-scanout + edge reveal + thumbnail contract/budget → **53 tests 全绿**。
- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -x -q -p no:cacheprovider tahoe-shell/tests/` → **803 passed, 234 subtests passed in 40.72s**。

## 运行期/手测矩阵

- 当前源码隔离 nested niri 中启动 3 个真实 Alacritty：开/关窗口时 Dock chrome、窗口槽位与显式 spacer 在中间帧连续收缩；最小化后缩略图 shelf 出现，恢复/关闭后优雅退出。
- 实机通过窗口菜单执行“固定到 Dock”，新固定图标滑入让位，窗口按钮与右侧工具无闪烁；持久 identity 的 fallback→DesktopEntry 路径由生产模型契约测试覆盖。
- 全屏进入后 50ms `tahoe-dock`/`tahoe-topbar` surface 仍存在，500ms 后均已 unmap；退出全屏后两 surface 恢复。证明 guard 保留动画帧且最终不占 direct-scanout surface。
- 使用真实指针右击 Dock 窗口按钮，`tahoe-dock-window-menu` surface 实际 map，菜单位于点击图标正上方；既有 `origin "pointer"` 原点感达标。
- nested 日志无 `ReferenceError`、`TypeError`、binding loop、animation interceptor 或赋值错误；仅既有 winit/EGL 环境噪声。

## 方案边界

- 未修改 KDL 菜单/全屏规则、Motion token、glass shader/region 协议或四节点 motion-profile 管理面。
- 全屏最终仍 unmap 常驻 layer surface，以保留 direct scanout；QML 只负责 unmap 前后的视觉过渡。
