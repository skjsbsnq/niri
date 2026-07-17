# R03 · Launchpad 筛选稳定与图标异步 · 2026-07-17

覆盖问题：#83（每字重播整场网格入场）、#84（筛选变化过渡决策）、#85（应用图标同步解码阻塞首帧）。

## 改动摘要

- `Launchpad.qml` 的 `onQueryChanged` 只保留选中项、页码与 `contentX=0` 复位；不再调用 `playGridEnter()`，也不修改 `gridEnter`。整场 opacity + scale 入场仅由 `onOpenChanged` 播放。
- 筛选变化采用“无动画直换”：连续输入时不新增逐字 opacity 脉冲，查询结果原位更新；选择理由见“二选一决策”。
- `appIcon` 改为 `asynchronous: true`。新增固定尺寸 `appIconSlot`：`Image.status !== Image.Ready` 时显示中性圆角底与通用应用符号，图像仅在 Ready 时显示，避免异步换源出现空白或旧图标覆盖占位。
- `test_launchpad_refactor.py` 新增契约测试：查询路径不得触发任何 enter/opacity/scale 动画，open 路径必须保留 `playGridEnter`；图标必须异步、Ready 才显示，且两层占位必须位于 `appIconSlot` 内。
- 未改 Apps 服务、Motion token、Launchpad 开关/分页/启动逻辑、玻璃 region、KDL 或其它组件。

## 审查

审查方式：3 个独立 reviewer 分别逐 diff 审查 QML 状态/绑定、性能与首帧占位、测试与任务范围；修复测试审查项后，由新的独立 reviewer 最终复审。

审查发现并已修复：

1. P2：初版查询测试只禁止字面 `playGridEnter`，替代 enter helper 或 opacity/scale 赋值仍可能漏检。已增加通用 enter 调用及 opacity/scale 实际绑定/赋值禁令。
2. P2：初版 placeholder 计数作用于全文件，可能被无关节点满足。已先提取 `appIconSlot` block，再要求其中恰有两处 Ready 占位守卫。
3. P2：测试用 QML block 提取器会把字符串/注释内的大括号计入深度。已补齐单/双引号、转义、行注释与块注释状态处理。
4. 独立语义核验指出异步换源时旧像素可能盖住先声明的占位层；已为 `appIcon` 增加 `visible: status === Image.Ready`，把占位可见性变成硬保证。

最终复审结论：**FINAL PASS**。未发现查询重播、空白/旧图标覆盖、绑定冲突、主线程新增负担、玻璃 region 红线、平行接口、TODO/FIXME 或范围越界。

## 自动验收

- 专项与治理：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tests/test_launchpad_refactor.py tests/test_layer_animation_ownership.py tests/test_motion_token_convergence.py tests/test_tahoe_material_governance.py` → **39 passed, 84 subtests passed**。
- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -x -q -p no:cacheprovider tests/` → **754 passed, 217 subtests passed in 26.39s**。
- 玻璃守护：`bash scripts/check-tahoe-glass-guardrails.sh` → **passed**（24 个 PanelWindow namespace、4 个 TahoeGlassRegion、22 个 regions 文件及 popup 几何检查全过）。
- QML 解析：Qt 6.11 `qmllint` 对 `Launchpad.qml` 返回 0；仅报告本机未注入 Quickshell import path 与既有未限定属性 warning，无语法错误。
- 嵌套冒烟：`timeout 25s env NIRI_MODE=nested TAHOE_POWER_PROFILE=keep TAHOE_CONFIG_DIR=$PWD/tahoe-shell bash scripts/run-tahoe-session.sh` → 预期 timeout **124**；`/tmp/r03-nested-smoke.log` 无 QML TypeError/ReferenceError/binding loop，仅既有 EGL warning 与终止时 xwayland-satellite SIGTERM。
- 部署一致性：`arch-update.sh --deploy-tahoe-shell` 后 `--verify-tahoe-shell` → parity OK，manifest `151e62c47669144f8436e69320c5d5ab033014556d0368963df0e677bcbe999b`；临时运行期验证 IPC 已随最终重部署完全清除。
- 本任务不改 KDL，`niri validate` 不适用。

## 宿主会话手测矩阵

- 开场：59 个应用、两页数据下打开；运行期采样从 `gridEnter=0.843/layerProgress=0.821` 收敛到 `1.000/1.000`，证明既有开场入场仍实际执行。稳定帧图标齐全，无成片空白或首帧卡顿恶化。
- 连续输入/删除：以约 70ms 间隔执行 `f → fi → fir → fire → fir → fi → f → 空`；`appCount` 按 `24 → 10 → 1 → 1 → 1 → 10 → 24 → 59` 更新，所有采样中 `gridEnter=1.000`、`layerProgress=1.000`，无整场缩放/透明度重播。
- 筛选截图：`query-fire-atomic.png` 显示单一 Firefox 结果保持完整尺寸与清晰图标；`launchpad-open-final.png` 显示完整网格无空白图标。证据位于本任务 visualization 目录的 `r03/` 子目录。
- 用户最终手测：连续快速输入/删除、首次打开图标、Esc、点外关闭、快速开关 ×3 均确认 **“通过”**。
- 深浅色：浅色宿主截图通过；新增占位符号复用既有 `root.textSecondary`，其余颜色与 Theme 绑定未改。深色分支由逐 diff 审查确认无新增独立色值路径。
- reduced profile / `useSpring=false`：查询路径现为无动画直换，不依赖 spring；open 路径继续使用既有 `Motion.reducedMotion()` 归零分支，`useSpring` 未参与本任务改动。
- 服务不可用：`appsService=null` 时既有 `filteredApps=[]`、cell 不实例化图标；新增占位不改变空服务路径。
- 宿主日志：本任务运行路径无新增 Launchpad TypeError/ReferenceError/binding loop；配置最终重新加载成功。

## 二选一决策

选择 **无动画直换**，不采用每字 `Motion.fadeFast` opacity 淡入。理由：输入间隔常短于 `fadeFast`，每次重新淡入仍会形成亮度脉冲，只是把原来的缩放脉冲换成透明度脉冲；直接切换在实际连续输入中最稳定，且严格满足执行计划允许的第二方案。

## 范围外发现

- 宿主 Quickshell 日志仍有既有 `LockScreen.qml:23 ReferenceError: lockClock is not defined`、`Controls.qml` FileView 无路径 warning、portal/Bluetooth warning；均在 R03 路径外，未顺手修改。
