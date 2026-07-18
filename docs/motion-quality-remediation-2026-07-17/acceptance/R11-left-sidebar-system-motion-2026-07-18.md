# R11 · 侧栏系统页稳定进程与动效 · 2026-07-18

覆盖问题：#55 #56 #57 #58 #59。

## 实施摘要

- `SystemStats.qml` 为每个进程实例维护稳定 `QtObject`，identity 为 `pid:/proc/<pid>/stat starttime`。同一实例的 CPU、内存、命令等字段在 2 秒 medium tick 内就地更新；退出或 PID 复用会淘汰旧 wrapper，并延迟 1 秒释放以覆盖 ListView remove transition。
- `LeftSidebarSystem.qml` 的进程表改为 `ScriptModel.objectProp: "modelKey"` + `ListView`。增删走 fade，真正移动项与被挤开项分别走 `move` / `displaced` eased transition；排序相同值以 PID 作稳定 tie-break。fast 1 秒包不再无意义重排进程表。
- ProcessMenu 接收点击行的普通对象快照，不再持有服务 cache 中可能随后销毁的 QObject；可见列表在菜单打开时仍持续 reconcile，避免旧 values 引用退休 wrapper。
- `ActivityRing` 增加独立 `displayProgress`，以 500ms `SmoothedAnimation` 跟随原始统计值；Canvas 只监听动画值并在主题色变化时主动重绘。reduced profile 直接跟随目标。
- 展开全部使用 `ccMorphDurationMs`：tabs/搜索、排序头与两段 8px 间距由同一 progress 连续驱动，进程列表宿主高度同步 morph，`procCard` 随连续 implicitHeight 变化，不叠加第二个几何 interceptor。
- 磁盘/电池填充宽度先 clamp 到 `[0,1]`，再走 `Motion.elementResize()`；SegTab、SortHeader、进程行 hover/pressed/active 色均接 `ColorAnimation`。

## 方案决策

- 没有引入自写 diff/ListModel 框架。稳定 identity 沿用 R04 的 `QtObject cache + ScriptModel.objectProp` 机制，服务属性名 `processes` 与既有消费边界保持不变。
- PID 单独不足以代表进程生命周期；采用 Linux `/proc/<pid>/stat` field 22 starttime 与 PID 组合成 `modelKey`。starttime 读取失败时退化为 `pid:unknown`，不阻断数据发布。
- 进程卡属于固定侧栏玻璃内部内容；morph 只用 eased `NumberAnimation`/`SmoothedAnimation`，未改变 `LeftSidebar.qml` 的 panel、mask 或 TahoeGlass region 几何，也未新增 token。
- ProcessMenu 继续只消费 plain `{pid,name,uid,cmdline,...}` 数据。破坏性操作的 PID/starttime 二次校验属于既有 ProcessMenu 安全边界，未在 R11 越界修改。

## 审查

初审分三路检查 identity、动画/绑定和范围/测试，发现并修复：

1. 仅按 PID 缓存会在两个 medium tick 之间发生 PID 复用时继承旧 delegate；补 `/proc` starttime、`modelKey` 与真实 PID-reuse runtime probe。
2. ProcessMenu 若持有 live wrapper，会在字段更新或延迟 destroy 时改变/失效；改传 detached snapshot。
3. 菜单打开时冻结 visible model，但服务仍销毁退休 wrapper，可能令 ScriptModel 引用悬空；菜单已有快照后改为 medium tick 始终 reconcile。
4. `Column.spacing: 8` 会在展开区块加入/移除时产生首尾 8px 跳变；改为固定基础 spacer + 两个 progress spacer，区块常驻且高度/opacity 连续。
5. 首版测试用全文件计数，可能遗漏单个磁盘/电池条或 tabs/sort morph 回归；改为按 ActivityRing、tabs/search、sort header、list host、disk、battery、SegTab、SortHeader 分块断言。

整改后独立 motion 终审 **FINAL CLEAN**、产品/测试门禁 **GATE CLEAN**、范围门禁 **SCOPE GATE CLEAN**。稳定 wrapper、PID reuse、延迟 destroy、ScriptModel move/remove、morph 连续性、reduced 降级与玻璃 guardrail 无未解决的本次 finding。

## 自动验收

- R11 专项：`test_left_sidebar_widgets.py`、`test_motion_token_convergence.py`、`test_system_process_stable_rows.py` → **36 passed, 25 subtests passed**。
- 真实 Tahoe `qs` runtime probe：同一进程实例字段更新/排序移动不重建 delegate；增删仅影响对应行；同 PID 不同 starttime 精确销毁旧 delegate 并创建新 delegate；连续复跑无 flaky。
- 真实进程采样：生产 awk `/proc/<pid>/stat` field 22 生成 JSON，经 `python3 -m json.tool` 解析成功；5 个样本均带非空 starttime。
- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -x -q -p no:cacheprovider tests/` → **780 passed, 221 subtests passed in 39.02s**。
- QML：`qmllint -I quickshell/build-tahoe/qml_modules tahoe-shell/components/LeftSidebarSystem.qml tahoe-shell/services/SystemStats.qml` → 退出 0、无输出。
- `bash scripts/check-tahoe-glass-guardrails.sh` → **passed**（24 PanelWindow namespace、4 TahoeGlassRegion、22 regions 文件及 popup geometry guardrail 全过）。
- 嵌套冒烟：`timeout 35s env NIRI_MODE=nested TAHOE_POWER_PROFILE=keep TAHOE_CONFIG_DIR=$PWD/tahoe-shell bash scripts/run-tahoe-session.sh` → 预期 **124**；配置正常加载，仅既有 EGL warning 与 timeout SIGTERM。
- 部署：`scripts/arch-update.sh --deploy-tahoe-shell` + `--verify-tahoe-shell` → parity OK，manifest `b4307caa3f1b62a1e162d848413626ecc6c24e7dd32ab155fb2316f2611d0135`。

## 验收矩阵

- 30s+ 数据刷新：宿主部署后 IPC 打开系统页保持 **32 秒**。初态 CPU/RAM/GPU 为 7/40/34%，末态为 9/36/34%；进程顺序从 `electron/niri/linux-wallpaper/.../qs` 更新为 `qs/electron/niri/...`，列表保持完整，没有整表空白、卡片塌缩或 delegate 警告。
- 进程 identity/排序/hover：runtime probe 保存并严格比较 surviving delegate 引用；字段原地更新、move/add/remove、PID reuse 全覆盖。生产宿主多次 tick 后列表连续可用；外层 `Flickable` 不随模型刷新重建。
- 活动环/条形：宿主初末截图确认弧长、数值、磁盘与电池条随实时数据更新且布局稳定；Canvas repaint 由 500ms 插值属性驱动。
- 展开/收起：宿主系统页展开态布局、tabs/search/sort header 与长列表无重叠；源码与分块测试确认展开/收起共享 ccMorph progress，reduced 时 duration=0。
- 开/关与快速连点：IPC `openLeftSidebar`/`closeLeftSidebar` 连续 3 轮均退出 0，无新增日志错误；最后恢复关闭态。
- 深浅色、reduced、`useSpring=false`：新颜色均绑定既有主题 token；reduced 路径由专项测试锁定（morph/位移/尺寸归零，非空间 fade 保留既有 70ms）；R11 新几何路径无 Spring，`useSpring=false` 不改变行为。
- 服务不可用：既有“系统数据准备中”占位保留；空模型宿主高度为 36，稳定模型 helper 对空/非法数组安全返回。

## 范围外

- `ProcessMenu.qml` 的“结束进程/强制结束”在执行前只使用 PID，未用快照中的 starttime 二次验证。对比 HEAD 确认为 LS07 既有 TOCTOU，并非 R11 引入；按严格文件范围不顺手修改，建议另立进程操作安全任务。
- LockScreen 的 `lockClock is not defined` 与桌面 portal app-id 注册 warning 在宿主重启日志中已存在，均与 R11 无关。
