# R12 · 控制中心滑块与模块列表收尾 · 2026-07-19

覆盖问题：#47 #48 #49 #50。

## 实施摘要

- `GlassSlider` 的填充宽度与旋钮阴影 x 增加同一套 `Motion.elementMove()` eased follow。外部音量/亮度变化会在约 110–150ms 内滑向新值；按压或拖拽期间 Behavior 禁用，并在 press 首帧显式停止残余 follow 动画，保持指针 1:1 跟手。实体旋钮继续只绑定 `knobShadow.x`，没有第二条几何驱动。
- WiFi 与蓝牙模块使用两个独立 `ScriptModel`：WiFi 直接消费 R04 已稳定复用的 QObject wrapper；蓝牙视图按 address → dbusPath → device QObject 生成唯一 `modelKey`，不新增服务接口。
- 蓝牙普通 map 在 ScriptModel move 后可能保留旧 `modelData`；delegate 只保留稳定 key，并从当前排序快照回查最新 entry。显示字段与连接/配对/断开动作全部消费回查结果，避免移动后数据陈旧。
- `moduleList` 接入 add/remove/move/displaced transition。最后一行 1→0 时通过 `listRetiring` 保活 `fadeFast + 16ms`，完成 remove 淡出后才切换空占位。
- WiFi PSK 容器复用 R04 模式：`Layout.preferredHeight` + opacity 双动画、退场 visible guard、clip 与焦点释放；模块行 hover/active/default 色改用主题 token 并接 `ColorAnimation`。

## 方案决策

- 不修改 `Controls.qml` 的现有服务边界，也不建立平行列表接口。WiFi 继续沿用 R04 cache；蓝牙稳定 identity 与最新快照解析只存在于 ControlCenter 表现层。
- WiFi/蓝牙使用两个独立 ScriptModel，避免动态切换 `objectProp` 时模型域互相污染。蓝牙 key 有命名域前缀，重复 key 在进入模型前剪枝。
- 蓝牙 move 后采用“旧 delegate key → 当前 rows 回查”的既有 Spotlight 同类修法，而不是自造 diff/cache 框架。
- 滑块 follow 直接落在计划指定的 fill width / knob x；门控同时检查 `dragArea.pressed` 与 `gs.userDragging`，覆盖 release handler 的尾帧顺序。
- 所有新增空间动画均为 eased NumberAnimation；未增加 Spring、未改 panel/GlassPanel/TahoeGlass region 几何，也未新增 motion token。

## 审查

初审分三路检查模块 identity、滑块/PSK 时序和范围/测试，发现并修复：

1. 单纯给蓝牙普通 map 补 key 不够：ScriptModel move 会保留 delegate 的旧 map；增加按 key 回查当前 entry，并用真实 `qs` probe 验证移动后字段与 action 数据均为最新。
2. 共用一个动态 `objectProp` 的 ScriptModel 存在切换顺序风险；拆成 WiFi/蓝牙两个独立模型。
3. 最后一行删除时源数组先变空，ListView 会立即隐藏，remove transition 不可见；加入 `listRetiring` 退场保活并延迟空占位。
4. 滑块只以 `dragArea.pressed` 门控存在 release 尾帧风险；增加 `userDragging` 门控，并在按下时 stop 两条外部 follow 动画。
5. transition 测试最初为全文件字符串匹配，可能假阳性；改为准确截取 `moduleList`。runtime probe 的固定 5ms 等待改为条件轮询 + 1s deadline。

整改后 slider/PSK 审查 **CLEAN**，模块与测试终审均 **FINAL CLEAN**。稳定 key、moved-map 最新数据、最后一行退场、拖拽直跟、reduced 降级与玻璃 guardrail 均无未解决 finding。

## 自动验收

- R12 专项及关联回归：`test_control_center_realtime_sliders.py`、`test_control_center_stable_modules.py`、`test_motion_token_convergence.py`、`test_wifi_stable_rows.py`、`test_bluetooth_discovery_lifecycle.py` → **40 passed, 25 subtests passed**。
- 真实 Tahoe `qs` runtime probe：覆盖蓝牙 map 全量替换、排序 move、survivor delegate identity、最新 connected/battery 字段、add/remove、重复 key、device-object fallback。
- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -x -q -p no:cacheprovider tests/` → **784 passed, 221 subtests passed in 39.03s**。
- QML：`qmllint -I quickshell/build-tahoe/qml_modules tahoe-shell/components/ControlCenter.qml` → 退出 0、无输出。
- `bash scripts/check-tahoe-glass-guardrails.sh` → **passed**（24 PanelWindow namespace、4 TahoeGlassRegion、22 regions 文件及 popup geometry guardrail 全过）。
- 嵌套冒烟：`timeout 35s env NIRI_MODE=nested TAHOE_POWER_PROFILE=keep TAHOE_CONFIG_DIR=$PWD/tahoe-shell bash scripts/run-tahoe-session.sh` → 预期 **124**；配置正常加载，仅既有 EGL warning 与 timeout SIGTERM。
- 部署：`scripts/arch-update.sh --deploy-tahoe-shell` + `--verify-tahoe-shell` → parity OK，manifest `bbf38def2d5adc1d43791c2ad5ab3169011d6a6e5fbcb8f5f5cb5b73c38f90ca`。

## 验收矩阵

- 宿主实测：用户提供 `/home/wwt/Pictures/Screenshots/Screenshot from 2026-07-19 00-46-22.png`，确认控制中心实际正常显示；显示/声音滑块的 fill 与 knob 对齐，WiFi/蓝牙 tile、媒体卡和编辑控制项布局无回归。
- 外部值与拖拽：源码门控、专项测试与用户现场确认共同覆盖“外部值缓动、按压/拖拽直跟、release 后恢复 follow”；实体 knob 只跟随已动画的 shadow x。
- 模块列表：真实 ScriptModel probe 覆盖 survivor identity、move 后最新数据、增删与最后一行退场保活；WiFi 继续使用 R04 稳定 wrapper，蓝牙 action 使用当前 decorated entry。
- PSK：高度/opacity/visible/focus 模式与 R04 一致，收起动画不会被 `visible:false` 截断；仅作用于模块行内部布局。
- 深浅色、reduced、`useSpring=false`：行色使用现有主题 token；空间 duration 由 Motion profile 在 reduced 下归零；R12 新路径不依赖 Spring。
- 开/关、Esc、点外关闭：未改控制中心既有 popup 协调与关闭链路；嵌套会话和宿主配置加载无相关 warning。
- 用户在 2026-07-19 明确要求跳过额外测试/重截图，因此未再追加现场操作；以上记录保留已完成的自动验收与用户提供的正确截图。

## 范围外

- 蓝牙服务仍按既有规则发布普通 map；R12 在视图层解决 identity 与 moved-map 陈旧问题，未提前把服务改造成 R04 式 QObject cache。
- LockScreen 的 `lockClock is not defined` 与桌面 portal app-id 注册 warning 为既有宿主日志，与 R12 无关。
