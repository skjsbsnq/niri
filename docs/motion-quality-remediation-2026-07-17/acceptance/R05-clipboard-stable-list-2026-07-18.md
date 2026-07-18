# R05 · 剪贴板弹窗稳定列表与动画 · 2026-07-18

覆盖问题：#1（零 Behavior/Transition）、#2（打开 refresh 整表重建）、#3（两 ListView 增删/固定/置顶瞬跳）、#4（面板高度瞬跳）以及 #5 中的 ClipboardRow hover/press。

## 改动摘要

- `ClipboardHistory.qml` 将 cliphist 行首 id 解析为 `entryId`，history 使用 `entryId → 稳定 QtObject` 缓存，pinned 使用唯一文本 → 稳定 QtObject 缓存。两类条目都提供 `modelKey`，原有对外字段保持兼容。
- refresh 的 stdout 先写入 `pendingListText`，只有 list process 以 0 退出才执行增量合并；FailedToStart/非零退出保留上一份 entries 和对象 identity，不再发布瞬时空表。
- pin decode 同样改为“stdout 缓冲 → 成功退出才固定”；非零退出即使产生 partial stdout 也不会写入 pinned 状态，FailedToStart 会复位 pinning。
- 删除成功启动后先按 id 从已发布列表中移除目标条目，立即触发视图退出；450ms 既有 refresh 仍负责与 cliphist 后端收敛。显式“清空历史”继续立即清空，固定项保留。
- `ClipboardPopup.qml` 的 pinned/history 两个 ListView 都改为 `ScriptModel { objectProp: "modelKey" }`，接入 add/remove/displaced Transition。history 删除语言为右滑 + 淡出 + height→0，pinned 取消固定为左滑 + 淡出 + 折叠，存续行 displaced 平滑让位。
- 两个列表 `Layout.preferredHeight` 与 GlassPanel `height` 都只用 eased `NumberAnimation`；最后一行退出时以动画中的 preferredHeight 守卫 visible，避免模型变空瞬间截断 remove transition。
- `ClipboardRow` 增加 hover `ColorAnimation(fadeFast)` 与 `Motion.pressScaleFor/pressDurationFor`；内联 IconButton/TextButton 未改，严格留给 R13。

## 审查

审查方式：实施前 3 个只读探子定位服务、视图和测试范式；实施后 3 个独立 reviewer 初审，修复后由 2 个新 reviewer 最终复审。

审查发现并已修复：

1. P1/P2：pinDecode 初版仍在 stdout `streamFinished` 时直接固定，若进程随后非零退出会持久化半截内容。现改为只缓存 stdout，`onExited(code===0)` 才提交；新增“partial stdout + code 1”真实 QML 回归。
2. reviewer 要求核验 listProbe 的 `exited/runningChanged` 顺序。Quickshell `process.cpp:273-285` 明确先 streamEnded → exited → runningChanged，FailedToStart 只发 runningChanged(:289-296)；当前成功/失败两条路径与其一致。
3. 初版测试只覆盖服务对象，未证明真实 ScriptModel delegate 生命周期。新增真实 Tahoe `qs` 探针：history/pinned 重排时存续 delegate 原位移动且字段更新，新增只创建一行，删除只销毁目标行。
4. 补齐隔离交互：optimistic delete 仅移除目标 id；成功固定/复制 history/复制 pinned/取消固定保持 history identity；失败 refresh 保留旧对象。

最终复审结论：两位 reviewer 均为 **FINAL PASS**。未发现稳定缓存、Process 生命周期、FileView 持久化调用、两表模型、玻璃 region、动画双驱动、reduced/useSpring=false、接口兼容、平行接口、TODO/FIXME 或范围越界问题。

## 自动验收

- 专项与治理：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tests/test_clipboard_history_event_refresh.py tests/test_tahoe_symbol_migration.py tests/test_tahoe_material_governance.py tests/test_layer_animation_ownership.py` → **29 passed, 59 subtests passed**。
- `test_clipboard_history_event_refresh.py` → **13 passed**，其中：
  - 真实 Qt 6 `qmltestrunner` 覆盖 refresh pending/coalesce/FailedToStart、history/pinned identity、失败保留、delete、pin decode 成败、copy/unpin；
  - 真实 Tahoe `qs + ScriptModel` 覆盖 delegate 创建/销毁计数、原位重排与最新字段通知。
- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -x -q -p no:cacheprovider tests/` → **762 passed, 217 subtests passed in 28.26s**。
- 玻璃守护：`bash scripts/check-tahoe-glass-guardrails.sh` → **passed**（24 个 PanelWindow namespace、4 个 TahoeGlassRegion、22 个 regions 文件及 popup 几何检查全过）。
- QML 解析：`/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules services/ClipboardHistory.qml components/ClipboardPopup.qml` → **0**；只报告既有 PanelWindow/TahoeGlass qmltypes 不完整与内联按钮 `enabled` shadow warning，无语法/新增类型错误。
- 嵌套冒烟：`timeout 25s env NIRI_MODE=nested TAHOE_POWER_PROFILE=keep TAHOE_CONFIG_DIR=$PWD/tahoe-shell bash scripts/run-tahoe-session.sh` → 预期 timeout **124**；仅既有 EGL warning 与 timeout 终止 xwayland-satellite 的 SIGTERM，无 Clipboard QML TypeError/ReferenceError/binding loop。
- 部署一致性：`arch-update.sh --deploy-tahoe-shell` 后 `--verify-tahoe-shell` → parity OK，manifest `8b98625f5054557446c4bb76c35b7453beba73e78fcab7618baae6d679e78061`；宿主 Quickshell 热重载最终 `Configuration Loaded`。
- 本任务不改 KDL，`niri validate` 不适用。

## 宿主会话验收矩阵

- 真实数据打开：宿主弹窗显示 12 个固定项与 1 个 history 项，两个独立滚动区、计数、复制/固定/删除按钮及面板高度正常；打开触发 refresh 后没有开场整表闪烁或高度跳空。
- 快速开关 ×3：通过 `tahoe.openClipboardPopup/closeClipboardPopup` 以 250ms 间隔执行，第三次打开仍为完整 pinned/history 两段列表，无空卡、错高、残留 surface 或 Clipboard QML 错误。
- refresh 保留：打开路径继续调用既有 `refresh()`；Process 运行期间不修改 entries，成功后按 id 合并，失败保留。真实 qmltestrunner 与 qs delegate 计数证明未变化行不重建。
- 删除/固定/复制置顶：为避免破坏用户实际剪贴板，全部在隔离 TestProcessRegistry 与真实 qs 模型探针中执行。删除只销毁目标 delegate；固定新增 pinned 行且 history delegate 保持；取消固定只销毁 pinned 行；copy 后的新 id/重排路径由真实 ScriptModel move 测试覆盖。
- 滚动/hover：产品代码没有写 `contentY`，ScriptModel move 不重置存续 delegate；宿主两列表可滚动且打开后位置无异常。hover/press 使用 Motion token，按钮命中层级保持既有 rowContent z=1 / rowMouse z=0。
- 面板/列表高度：列表数量与 pinned section 状态变化均通过 preferredHeight Behavior 传到 panel.height；玻璃 region 跟随 eased 数值，没有 spring。
- Esc/点外关闭：既有 layershell/`closeRequested` 路径未改，IPC close 后无残留；`focusable:false` 的既有输入语义保持。
- 深浅色：本任务未新增颜色常量分支，只给既有 rowFrame color 绑定加 ColorAnimation；宿主浅色玻璃通过，稳定模型与配色无耦合。
- reduced profile：`elementMove/elementResize/pressDuration` 归零，press scale 返回 1；`fadeFast` 降级为 70ms。新增路径无 SpringAnimation，`useSpring=false` 等价走同一 eased 路径。
- 服务不可用：原有 cliphist/wl-copy/wl-paste 检测和占位未改；失败 refresh 有旧数据时显示“刷新失败，保留 N 项”，无旧数据时仍为“暂无历史”。
- 隐私：宿主截图包含真实剪贴板正文，仅用于本地目视后保留在 `/tmp`，未复制进仓库或 visualization 持久目录。
- 宿主日志：最终热重载与验收路径无新增 `ClipboardHistory.qml`/`ClipboardPopup.qml` TypeError、ReferenceError 或 binding loop；既有 `LockScreen.qml:23 lockClock` warning 在范围外。

## 方案决策

1. history 以 cliphist id 为稳定 key；pinned 以既有“文本唯一”语义为 key。两者都采用可通知的 QtObject wrapper，不使用纯 JS 对象缓存。
2. refresh/pin decode 都采用“stdout 暂存、成功退出提交”，避免打开刷新与失败命令发布空表/半成品。
3. 删除采用 optimistic published-list remove，再由既有 450ms refresh 收敛。理由：用户点击后立即得到滑出折叠反馈；命令无法启动时不移除，成功启动后 cliphist delete 为短命令。
4. 保留 pinned 与 history 两个 ListView，不合并成新滚动容器；这能最小化交互与滚动语义变化，并让 R05 聚焦稳定 identity/动画。

## 范围外发现

- `services/search/ClipboardProvider.js` 的 pinned 搜索结果 id 仍包含数组 index；该文件不在 R05 改动清单，未提前扩 scope，后续搜索治理时应改为稳定 pin key。
- ClipboardPopup 的 IconButton/TextButton hover/press 与共享控件合并属于 R13，本任务只处理本地 ClipboardRow。
- 弹窗合成器关闭 opacity/KDL 参数属于 R15，本任务未改。
- `clearHistory()` 继续沿用既有 optimistic clear + detached wipe 语义；R05 的“refresh 不清空”不改变用户明确点击清空的路径。
