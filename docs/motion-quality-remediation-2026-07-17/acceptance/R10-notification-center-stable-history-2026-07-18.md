# R10 · 通知中心稳定列表与入场 · 2026-07-18

覆盖问题：#35 #36。

## 实施摘要

- `Notifications.qml` 按 notification id 缓存稳定 `QtObject` history entry，按 `appName` 缓存稳定 group；entry/group 分别提供 `history:<id>` 与 `history-group:<app>` 的 `modelKey`。同 id 更新、置顶、同组增删和组顺序变化均复用原对象。
- `historyModel` 的任何写入都经过 canonicalization：外部普通对象只作为字段源，服务重新解析到 canonical cache；已淘汰且等待延迟销毁的对象不能被重新塞回模型。数组去重、`maxHistory=60` 截断、entry/group cache 修剪在同一收敛路径完成。
- 删除旧 `groupedHistory()` 函数，通知中心只消费 `groupedHistoryModel`，没有新旧平行接口。entry/group map 均使用 null-prototype object，并覆盖 `__proto__` 与 `uint32` id。
- `NotificationCenter.qml` 的 group/row 两层 Repeater 均改为 `ScriptModel.objectProp: "modelKey"`。历史新增、同 id 更新或重排不再重建整个 group/row delegate 树。
- 仅面板打开期间真正新增的 row 从右侧 `Motion.toastEnterOffsetPx` 淡入；首次打开、关闭重开以及关闭期间积累的旧历史直接落稳，不重播逐行入场。
- 单删先复用清空路径的右飞+淡出，再做高度折叠，最后才调用 `removeHistoryItem()`；重复点击被 row 状态与 pending-id map 双重拦截。动画中关闭 Loader 会同步 flush pending delete，清空与单删不会竞争或漏删。

## 方案决策

- 保留既有 `historyModel` 属性名与服务边界，不引入 diff 框架；稳定 identity 只用仓库既有 QtObject cache + `ScriptModel.objectProp` 模式。
- group key 继续使用产品现有分组语义 `appName`。应用名改变会把 entry 移到新 group；未改变的 group 与 row 保持 identity。
- row 入场与退出均使用 eased `NumberAnimation`；没有 Spring。GlassPanel 与 `TahoeGlass.regions` 几何路径未改。
- 单删采用“fly/fade 完成 -> height collapse -> service remove”的两阶段顺序。这样模型保留到视觉退出结束，survivor delegate、折叠状态和滚动容器不会因瞬时删除而整树重建。

## 审查

初审分三路检查服务 identity、视图时序和测试/guardrail，发现并修复：

1. 外部 `historyModel` 赋值可能绕过 cache，并在 1 秒延迟销毁窗口复活旧 QObject；加入 canonicalization 与递归门控，并用 1100ms 真实 QML 用例覆盖。
2. Loader 重开会重建 row，旧历史仍会触发默认 opacity/x Behavior；加入已呈现 id 跟踪与 `motionReady` 门控，旧 row 瞬时落稳，仅新 id 播入场。
3. 新 `groupedHistoryModel` 与旧 `groupedHistory()` 形成平行接口；删除旧函数并更新治理契约。
4. 测试使用无效 profile 名 `normal`（会回退 balanced）；改为真实 `balanced` + `reduced`，并补 outer group delegate identity、重复删除、关闭 Loader pending delete、重开不重播、分组折叠与清空中关闭。

整改后三路独立终审均 **CLEAN**：stable identity、延迟 destroy、maxHistory、双层 delegate、单删/清空竞态、reduced 降级与 Glass guardrail 均无未解决 finding。

## 自动验收

- R10 专项及通知回归：`test_notification_center_stable_history.py`、`test_motion_token_convergence.py`、`test_r13_correctness.py`、`test_notification_swipe_stable_identity.py` → **48 passed, 25 subtests passed**。
- 真实 `qmltestrunner`：生产 `Notifications.qml` 覆盖同 id 更新/重排、同组增删、external canonicalization、延迟 destroy、`maxHistory`、`__proto__`、`4000000000` id 与 cache prune。
- 真实 Tahoe `qs`：生产 `NotificationCenter` 在 balanced/reduced 下覆盖新增 row、group/row survivor identity、单删 fly/fade/collapse、重复点击、关闭 Loader flush、重开不重播、折叠状态与清空中关闭。
- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -x -q -p no:cacheprovider tests/` → **776 passed, 221 subtests passed in 38.87s**。首轮发现 Dynamic Island 静态契约仍硬编码 R09 的旧 `int` signal；改为严格断言 `real id` 后全量通过。
- QML：`qmllint -I ../quickshell/build-tahoe/qml_modules components/NotificationCenter.qml services/Notifications.qml tests/tst_notification_center_stable_history.qml tests/tst_notification_center_stable_rows.qml` → 无告警。
- `bash scripts/check-tahoe-glass-guardrails.sh` → **passed**（24 PanelWindow namespace、4 TahoeGlassRegion、22 regions 文件及 popup geometry guardrail 全过）。
- 嵌套冒烟：`timeout 25s env NIRI_MODE=nested TAHOE_POWER_PROFILE=keep TAHOE_CONFIG_DIR=$PWD/tahoe-shell bash scripts/run-tahoe-session.sh` → 预期 **124**；无 NotificationCenter/Notifications TypeError、ReferenceError 或 binding loop，仅既有 EGL warning 与 timeout SIGTERM。
- 部署：`arch-update.sh --deploy-tahoe-shell` + `--verify-tahoe-shell` → parity OK，manifest `7a4b74b87f33895e41cf685c271accf6d3996654fb5eebc2722e13dc163dfdc5`。

## 验收矩阵

- 新通知入历史：只创建新 row；同组 AppGroup 与既有 row delegate 引用不变，新 row 右侧滑入并淡入。
- 同 id 更新/置顶：canonical entry 原地更新，history/group 对象保持 identity，无整树闪烁。
- 单删：X 重复触发仍只删除一次；balanced 走 fly/fade -> collapse -> remove，reduced 归零位移/折叠时长但保持删除顺序与 identity。
- 清空/关闭竞态：单删中关闭面板同步完成 pending delete；单删中点清空先 flush pending，再启动 stagger；清空中关闭立即完成 clear，不遗留 timer/clearing 状态。
- 分组折叠：三条同组保持折叠，展开状态在新增行与 survivor 重排中不丢；重开面板按当前条目数恢复既有默认语义。
- 打开/关闭与数据刷新：首次打开、快速关闭重开和关闭期间新增历史均不重播旧 row 入场；打开期间新增才播。稳定 delegate 保证现存行 hover/滚动容器不因模型刷新重建。
- 深浅色/服务不可用：未新增颜色或主题分支；无服务时模型为空、清空与 pending delete helper 均安全返回。

## 范围外

- 通知中心内联清空按钮、关闭按钮与 DND Toggle 的共享控件合并仍归 R13；本任务未提前改样式或创建平行控件。
