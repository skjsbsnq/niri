# R04 · WiFi 弹窗稳定列表 · 2026-07-17

覆盖问题：#7（rescan 清空重建）、#8（30s 周期闪烁）、#9（列表/面板高度瞬跳）、#10（PSK 瞬弹）。

## 改动摘要

- `Controls.qml` 用 SSID → 稳定 `QtObject` 的单一缓存发布 `wifiNetworks`；对外属性名与 `network/name/signalPercent/security/secured/pskSupported/known/connected/stateChanging` 字段保持不变。后端对象和字段原位更新时，稳定 wrapper 发出真实 QML notify，消费者不会拿到陈旧信号值。
- SSID 去重选择“已连接优先，否则同连接态取更强信号”；排序固定为 connected → known → signal → name。缓存使用 `Object.create(null)`，避免 `__proto__` 等 SSID 与对象原型碰撞。
- rescan 的 scanner false→true 空窗期间保留上一份非空快照，新网络增量合并；与 Quickshell NetworkManager 10001ms 扫描节流对齐，10500ms 后统一收口并删除确实消失的 SSID。`scanGeneration + scanDevice` 使快速重复 rescan、设备热切换、WiFi/polling 关闭后的旧 `Qt.callLater` 失效。
- `WifiPopup.qml` 的网络列表改为 `ScriptModel { objectProp: "name" }`，接入 add/remove 淡入淡出和 displaced 位移动画；列表高度、GlassPanel 高度只用 eased `NumberAnimation`，没有 spring。
- 空列表在扫描阶段显示“正在扫描…”，只有扫描收口后仍为空才显示“未发现网络”。PSK 区域用 `Layout.preferredHeight 0↔42` + opacity 动画，并以动画中的高度/透明度守卫 `visible`。
- 新增 `test_wifi_stable_rows.py`：使用真实 Tahoe Quickshell `ScriptModel` 运行探针，验证同 SSID 字段更新/排序移动不重建 delegate、信号/安全/状态字段实时更新、扫描空窗保留、最终增删、known 优先级、同信号 name tie-break 与特殊 SSID。

## 审查

审查方式：实施前 3 个只读探子定位服务/视图/范式；实施后 3 个独立 reviewer 初审、3 个新 reviewer 复审，修复后再由 2 个新 reviewer 做窄范围终审。

审查发现并已修复：

1. 运行探针发现初版纯 JS wrapper 虽复用对象，但字段就地赋值不发 QML notify，delegate 信号数字会陈旧。改为稳定 `QtObject` wrapper，探针随即验证字段更新与 delegate identity 可同时成立。
2. 初版用“非空结果静稳 350ms”猜扫描完成，可能在扫描部分结果阶段提前删除旧快照。删除猜测路径，统一以 10500ms fallback 收口。
3. observer 初版依赖 delegate 销毁后的 `Qt.callLater`。改为显式监听 ObjectModel `valuesChanged`，逐条字段仍由 observer `Connections` 监听；observer model 最终显式使用 `networks.values`，消除模型展开歧义。
4. rescan 初版延迟回调可能跨快速重扫/设备替换。新增 generation 与捕获设备身份校验；WiFi、设备、polling 生命周期变化都会使旧回调失效。
5. 测试审查指出排序与字段覆盖不足；已补 known 优先、同信号按 name、secured/pskSupported/stateChanging 更新以及准确限定 30s timer 的断言。

终审结论：两位最终 reviewer 均为 **FINAL PASS**。未发现服务生命周期、稳定 identity、扫描空窗、玻璃 region、动画双驱动、ControlCenter/WifiPage 字段兼容、平行接口、TODO/FIXME 或范围越界问题。

## 自动验收

- 专项与治理：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tests/test_wifi_stable_rows.py tests/test_motion_token_convergence.py tests/test_service_polling_activity.py tests/test_tahoe_material_governance.py tests/test_layer_animation_ownership.py` → **39 passed, 84 subtests passed**。
- 稳定行运行探针：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tests/test_wifi_stable_rows.py` → **4 passed**；真实 `qs` 进程覆盖 update/reorder/retain/add/remove 与 delegate 创建销毁计数。
- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -x -q -p no:cacheprovider tests/` → **758 passed, 217 subtests passed in 26.68s**。
- 玻璃守护：`bash scripts/check-tahoe-glass-guardrails.sh` → **passed**（24 个 PanelWindow namespace、4 个 TahoeGlassRegion、22 个 regions 文件及 popup 几何检查全过）。
- QML 解析：Qt 6.11 `qmllint services/Controls.qml components/WifiPopup.qml` → **0**，无语法/类型错误输出。
- 嵌套冒烟：`timeout 25s env NIRI_MODE=nested TAHOE_POWER_PROFILE=keep TAHOE_CONFIG_DIR=$PWD/tahoe-shell bash scripts/run-tahoe-session.sh` → 预期 timeout **124**；仅既有 EGL warning 与 timeout 终止 xwayland-satellite 的 SIGTERM，无 QML TypeError/ReferenceError/binding loop。
- 部署一致性：`arch-update.sh --deploy-tahoe-shell` 后 `--verify-tahoe-shell` → parity OK，manifest `affe40465b33ea7696297437b1ae47b7517ef5f19054d88b08be231c198cf718`；宿主 Quickshell 热重载最终 `Configuration Loaded`。
- 本任务不改 KDL，`niri validate` 不适用。

## 宿主会话验收矩阵

- 真实数据：宿主 NetworkManager WiFi 开启、连接 `QQ2-5G`；弹窗显示 5+ 网络，已连接/已保存/信号字段正确，服务更新时信号 `87%↔100%` 与网络增删在原列表内更新。
- 快速开关 ×3：通过 `tahoe.openWifiPopup/closeWifiPopup` 以 250ms 间隔执行，第三次打开仍为完整列表，无空卡、残留扫描占位、QML 错误或面板错高。
- 开着 30s+：保持弹窗开启，先等 27s，再以约 120ms 间隔采集 36 帧并补前/后帧。38 帧均保留完整卡片与网络行；期间数据从不同扫描结果增量变化，但没有“未发现网络”闪现、整表空白或面板塌缩。联系表：`/home/wwt/.codex/visualizations/2026/07/17/019f7098-fec8-7ae1-b0ef-cac58754b7f2/r04/wifi-30s-contact-sheet.png`。
- 关闭路径：IPC close 通过；Esc/点外关闭的既有 `closeRequested`/layershell 输入路径未改，逐 diff 与宿主关闭后无残留 surface 验证通过。
- 滚动/hover/增删：真实列表数量超过可视高度且扫描结果发生增删；运行探针证明存续 SSID delegate 不销毁，因而 ListView `contentY`、hover 与展开 identity 不被整表重置；新增/删除/重排由 add/remove/displaced Transition 接管。
- PSK：高度/opacity 双 Behavior 与 visible 动画守卫由专项测试及 QML 解析通过；连接 API 和密码提交/Esc 逻辑未改。当前宿主观测网络多数已有 profile，未执行真实口令连接以避免改变网络状态。
- 深浅色：本任务未新增颜色分支，沿用弹窗既有材质与颜色；宿主浅色玻璃截图通过，稳定列表/高度逻辑与配色无耦合。
- reduced profile：`Motion.elementMove/elementResize` 在 reduced 下为 0，列表/面板/PSK 几何即时降级；`fadeFast` 降级为 70ms。`useSpring=false` 不影响本任务，因为新增路径无 `SpringAnimation`。
- 服务不可用/WiFi 关闭：null/device/enabled guard 会停止 fallback、清缓存并显示既有“Wi-Fi 已关闭”占位；扫描中真正空列表先显示“正在扫描…”，fallback 后才显示“未发现网络”。
- 宿主日志：最终热重载与验收路径没有新增 `Controls.qml`/`WifiPopup.qml` TypeError、ReferenceError 或 binding loop；仍有既有 `LockScreen.qml:23 lockClock`、Controls FileView 无路径 warning，均在 R04 范围外。

## 方案决策

1. 选择稳定 `QtObject` wrapper，不选择纯 JS 对象缓存。原因：后者能保 identity，但字段赋值没有 notify，真实 `ScriptModel` 探针证明 delegate 会读到旧值。
2. 扫描完成采用与后端节流一致的 10500ms fallback，不使用 350ms 静稳猜测。原因：NetworkManager 前端未暴露本轮可用的完成信号，短静稳可能把部分结果误判为完成；较长保留窗口不会遮住新结果，只延后删除确实消失的旧 SSID。
3. 保留 30s 定时 rescan，不降低频率；增量缓存已经消除其视觉闪烁，符合任务要求。

## 范围外发现

- `ControlCenter.qml` 的 WiFi/蓝牙 moduleList 仍需在 R12 接视图侧稳定 key 与增删动画；R04 只保证共享服务字段兼容，没有提前实施 R12。
- WifiPopup 内联 ToggleSwitch/PillButton 的 hover/press 合并属于 R13，本任务未改。
- 宿主既有 LockScreen/FileView warning 沿用 R03 记录，未顺手修复。
