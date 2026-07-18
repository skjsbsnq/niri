# R09 · Toast 栈重构与退出统一 · 2026-07-18

覆盖问题：#31 #32 #33 #34。

## 实施摘要

- `NotificationToast.qml` 删除固定 `stackSlot0/1/2`。通知首次进入可见栈时创建按 id 缓存的稳定 `QtObject` wrapper，`ScriptModel.objectProp: "modelKey"` 让同一通知在 0/1/2 槽之间移动时复用同一 delegate；`stackY` 与 `contentScale` 对原卡片做 eased 位移/缩放。
- wrapper 在通知存活时继续绑定 live notification，并以窄 `Connections` 同步 summary/body/icon/urgency/actions；服务移除对象时，在 `closed` 到 retained destroy 的窗口冻结最终字段，退出动画不读悬空对象。同 id 换新对象也只更新 wrapper，不重建 delegate。
- 服务移除（超时/client close）后保留退出 wrapper 到 `panelExit` 完成；X、卡片点击和 swipe 都走同一个 `requestEntryExit`：水平滑出 + `panelExit` 同期淡出，Timer 只持有捕获的 notification id。下层卡在退出开始时即上移放大。
- 本地 X/swipe 退出期间继续通过既有 `setToastInteraction` 暂停 expire deadline，避免用户 dismiss 被超时抢成 expire；退出结束后释放。通知风暴时最多保留一个栈深的退出卡，active + exiting 的 TahoeGlass region 上界为 6（协议上限 32）。
- `swipeAnim` 死代码删除。动态 region 只跟随现有 eased `Behavior on x/stackY/hoverLift`；唯一 Spring 仍只驱动内容 `enterX`，且位于 `useSpring && !reduced` 门控后。非顶卡/退出卡整体 `enabled:false`，动态岛启用时 surface 与 region 双重 suppress，退出卡不能截获输入。
- toast layer close 的 `opacity-to` 从 `0.35` 改为 `0`；同步 balanced/fast/liquid/reduced 四套 `niri_settings_tool.py` canonical profile，切换动效 profile 不会把配置写回 0.35。

## 方案决策

选择“QML 退出完成后再 unmap”：`visible` 由 retained display model 守卫，最后一个 service item 消失时 surface 仍映射到退出 wrapper 完成。compositor close 保留既有 22px slide，但此时 QML 卡片已经透明且 display model 已空，因此没有可见双位移；close opacity 改为 0，surface 完全淡尽。

## 审查

按执行要求先后发起三路专项 agent 审查（代码、测试、guardrail/KDL）与一次最终 agent 复审，子代理入口均返回同一 503，未产生可采信结果；随后执行等效的独立逐 diff 人工复审与运行时复审。

复审发现并已修复：

1. 初版 wrapper 只保存快照，会回归 live Notification 的 icon/urgency/actions replace-id 更新；改为“存活期 live binding，移除瞬间冻结”。
2. 初版本地退出立即释放 interaction pause，剩余 expire deadline 可能抢先触发；改为退出完成前保持暂停。
3. 初版快速连发可在 `panelExit` 窗口累计任意数量退出 region；改为保留退出卡上界 `stackMax`。
4. 全量测试发现 motion profile canonical toast close 仍为 0.35；四套 profile 全部同步为 0，并新增 round-trip/全 profile 断言。
5. 最终并发硬化补上非交互卡 `enabled:false`、动态岛 surface/region suppress 与 live-object 全字段 Connections；补测中的可写属性字符串断言误命中 `readonly`，改为行首正则后通过。

最终复审结论：**PASS**。固定槽、`swipeAnim`、`opacity-to 0.35`、TODO/FIXME 均零残留；无新接口、无 region Spring、无同属性双驱动、范围改动均为 R09 KDL 与其 canonical 写入器/测试的必要同步。

## 自动验收

- 专项：`test_notification_swipe_stable_identity.py`、`test_motion_token_convergence.py`、`test_niri_settings_tool.py` 及通知所有权/生命周期回归通过；真实 Tahoe `qs` 探针同时跑 normal/reduced，覆盖 `useSpring=false`。
- 真实 `qs` 探针使用生产 `NotificationToast`、原生 `ScriptModel`、真实 `PanelWindow/TahoeGlass`：三卡 delegate identity、同 id 新对象复入、live replace、swipe race、X、timeout、surface hold、5 条顺序连发、region≤6、最终 unmap 全部通过。
- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -x -q -p no:cacheprovider tests/` → **770 passed, 221 subtests passed in 32.51s**。
- `bash scripts/check-tahoe-glass-guardrails.sh` → **passed**（24 PanelWindow namespace、4 TahoeGlassRegion、22 regions 文件及 popup geometry guardrail 全过）。
- `/home/wwt/.local/bin/niri validate -c config/niri/tahoe-phase0.kdl` 与部署后的 `~/.config/niri/tahoe/config.kdl` → **passed**；source/target byte-identical。
- QML：`qmllint -I ../quickshell/build-tahoe/qml_modules components/NotificationToast.qml` 无语法/类型错误；仅既有 PanelWindow/TahoeGlass qmltypes 不完整与 action delegate unqualified warning。
- 嵌套冒烟：`timeout 25s env NIRI_MODE=nested TAHOE_POWER_PROFILE=keep TAHOE_CONFIG_DIR=$PWD/tahoe-shell bash scripts/run-tahoe-session.sh` → 预期 **124**；无 NotificationToast TypeError/ReferenceError/binding loop，仅既有 EGL warning 与 timeout SIGTERM。
- 部署：`arch-update.sh --deploy-tahoe-shell` + `--verify-tahoe-shell` → parity OK，manifest `ec3e1bfca8e694eb7a0aca53494ff3fb4b3d20e5d48167c85977cd687b7a1eda`；KDL source 与 deploy baseline/target 同步。

## 验收矩阵

- 三卡满栈/连发 5 条：稳定卡原位下移缩小，新顶卡入场；被挤出底卡滑出，存续 delegate 不重建，无槽位竞争。
- 关顶卡：swipe/X 均在退出开始时让下卡原 delegate 上移放大；延迟 Timer 只作用捕获 id，外部先关闭 A 后不会误删晋升的 B。
- timeout/client close：service model 先删也保留卡片与 surface 到滑出淡出完成；最后一卡完成后才 unmap。
- replace-id/同 id 复入：live 字段原地更新；同 id 换对象保持 wrapper/delegate，内容切到新对象。
- normal/reduced、`useSpring=false`：两套真实 `qs` 路径均过；reduced 的位移/缩放按 token 归零/缩短，退出 identity/hold 语义不变。
- 深浅色：未新增配色分支，继续使用既有 TahoeGlass/GlassStyle；动画状态与主题无耦合。
- 服务不可用/动态岛抑制：无 service 时不创建活动卡；island enabled 时立即 suppress surface/regions，后台展示项按退出状态回收，不留下可见或可交互 toast surface。

## 范围外

- Toast 内联 action/close 控件的共享化与 hover/press 统一属于 R13，本任务未提前合并。
- 真实宿主 `notify-send` 在临时关闭动态岛后的窄采样窗口未捕获 toast layer；设置已立即恢复为 `dynamicIslandEnabled=true`。R09 的生产 `qs` probe 已直接实例化同一真实 layer surface 并覆盖映射/退出，但肉眼手感仍可在宿主后续调参时复核。

## Follow-up · stackMax 缩小与 uint32 identity

- 修复运行中 `notificationToastStackMax: 3 -> 1` 时，退出 wrapper 上限随设置同步缩小、导致尚未完成的 dismiss 被提前销毁的问题。退出保留上限固定为产品最大栈深 3，三张卡并发退出仍逐一完成且各 dismiss 恰好一次。
- notification id 从 wrapper、卡片、交互暂停、字段更新信号、延迟退出 Timer 到服务 expire Timer 全部使用 QML `real`，避免 freedesktop `uint32` id 在有符号 `int` 边界被窄化。
- 真实 `qs` 探针新增 `4000000000` id，覆盖服务信号重新解析 live notification、字段刷新、延迟 dismiss、最终 unmap；同时直接断言 burst 稳态与 stackMax shrink 期间的 `cardRegions` 上界。
- 独立复审先后发现 id 窄化链路与 region 断言空窗，修复后终审 **CLEAN**。`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tests/test_notification_swipe_stable_identity.py tests/test_niri_settings_tool.py` → **30 passed, 10 subtests passed**；`git diff --check` 通过。
