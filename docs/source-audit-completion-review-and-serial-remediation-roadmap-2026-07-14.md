# Tahoe Desktop 已完成任务复审报告与严格串行修复路线图

生成日期：2026-07-14
工作区：/home/wwt/niri
审查基线：父仓 main@422f41b，niri@7eaec605，quickshell@f73859d
用途：修复 source-audit-research-and-grok45-fix-roadmap-2026-07-12.md 完成后复审发现的问题，并补齐原完成定义中缺失的真实行为验证
执行方式：一次只允许处理一个任务；每项必须测试、独立审查、commit、push、远端确认后，才能开始下一项

---

## 1. 执行摘要

原路线图 Task 01A、01B、02–22 均已有对应提交，父仓及两个子仓的目标分支也均包含这些提交。复审确认，大多数修复落在了正确的状态 owner 或资源 owner 中，以下设计方向是正确的：

- AppMenu、AppsSettings、Weather 使用 request generation 或稳定对象 identity 保护异步结果。
- 通知滑动删除捕获稳定 notification ID，而不是在 Timer 到期时重新读取 delegate。
- Tahoe glass controller 生命周期状态仍由 wl_surface 的协议 owner 管理。
- QuickShell Tahoe glass 仍只有一条 region 发布路径。
- Dynamic Island 通知队列使用 live Notifications 模型和稳定 ID，而不是复制通知业务模型。
- ThumbnailProvider 仍使用既有 per-window state、队列和单一 Process。
- Clipboard、AppMenu 的高频轮询已明显降低。

但是，当前代码不能按原路线图的严格完成定义验收为“全部完成”。复审确认 13 个任务仍存在边界缺陷、功能回归或端到端未落地；同时大量新增测试只是读取源码 token、正则提取和 Python 镜像状态机，没有运行真实 QML、QuickShell Process、Qt Timer、MouseArea 或 Wayland 协议路径。

本路线图新增 25 个原子任务（Task 00–06、Task 07A、Task 07B、Task 08–11、Task 12A、Task 12B、Task 13、Task 14A、Task 14B、Task 15–21），并严格串行执行：

1. 先恢复当前 HEAD 的全量测试基线。
2. 修复 13 个已确认缺陷。
3. 为原路线图中测试证据不足但实现基本正确的路径补充真实行为测试。
4. 以最终集成验收任务形成可追溯的完成报告。

任何任务都不得批量合并。即使两个问题位于同一个文件，也必须按任务边界分别研究、实现、测试、审查、提交和推送。

当前执行状态为“路线图已准备、尚未启用”：本报告按要求仅保存在本地，且当前主机缺少可执行的 rustup nightly rustfmt。开始 Task 00 前必须先完成第 5.0 节的文档 commit/push 和工具链门禁；在此之前不能把任何修复任务标记为进行中。

---

## 2. 审查范围、方法与验证结果

### 2.1 审查范围

本次复审覆盖：

- 父仓中原路线图 23 个任务提交及当前实现。
- niri 子仓 Task 05、06、16 的协议、动画裁剪和渲染实现。
- quickshell 子仓 Task 13、14、15 的 scene transform、增量 region 和 fallback 实现。
- 新增父仓 Python/QML 测试、niri Rust 单测与集成测试、QuickShell 当前构建产物。
- 父仓和子仓提交拓扑、gitlink 指针、分支与 origin 跟踪状态。

### 2.2 已执行验证

父仓 roadmap 定向测试：

~~~text
268 passed, 49 subtests passed
~~~

父仓当前完整 Tahoe 测试：

~~~text
426 passed, 143 subtests passed, 1 failed
~~~

唯一失败：

- tahoe-shell/tests/test_motion_token_convergence.py
- tahoe-shell/components/WeatherBackground.qml:53-54
- 原因：后续提交 422f41b 新增的组件重新内联 Easing.OutCubic。
- 该失败不是原 23 个任务提交引入，但它使当前 HEAD 不满足最终集成门禁。

niri：

~~~text
cargo test -q draw_clip --lib
6 passed

cargo test -q tahoe_glass --lib -- --test-threads=1
23 passed
~~~

QuickShell：

~~~text
cmake --build build-tahoe -j2
ninja: no work to do
~~~

审查取证时的仓库状态（不包含本报告这个新文件）：

- 父仓 main 与 origin/main 对齐。
- niri tahoe-layer-animations 与 origin/tahoe-layer-animations 对齐。
- quickshell quickshell-tahoe-desktop 与 origin/quickshell-tahoe-desktop 对齐。
- 三个工作区均 clean；保存本报告后，父仓会新增本文件这一项未跟踪改动。
- git diff --check 均通过。

### 2.3 测试可信度结论

原修复新增约 9800 行父仓测试，但多数测试采用以下模式：

1. 读取生产 QML/C++ 源码。
2. 用正则或字符串搜索确认若干 token 存在。
3. 在 Python 中重新实现一份状态机。
4. 测试 Python 状态机，而不是运行生产状态机。

此类测试能够证明“源码中出现了某些结构”，但不能证明：

- Qt 信号的真实发射顺序。
- Process 的 FailedToStart、onExited、runningChanged 顺序。
- Qt.callLater 与 Process 退出之间的顺序。
- Timer 等待期间 delegate 换绑。
- MouseArea press、release、cancel、grab loss 和 composed click 顺序。
- 多屏下多个 QML 实例的真实 running/visible 状态。
- Wayland 请求数、commit 数和服务端最终状态。
- QObject/QQuickItem 销毁期间的连接和 change-listener 生命周期。

Weather FailedToStart、Clipboard in-flight refresh 丢失和多屏 visualizer 重复运行，均是在这些测试全绿时仍然存在的实例。

### 2.4 原 23 个任务复审状态

下表区分“主实现机制”和“原路线图严格验收”。主实现基本正确但缺少生产行为测试的任务，不能直接按原完成定义重新宣称 COMPLETE，必须完成对应的测试补强任务。

| 原任务 | 已推送提交证据 | 主实现复审 | 严格验收缺口 | 本路线图收口任务 |
|---|---|---|---|---|
| 01A 媒体交互生命周期 | 父仓 5339d70 | 机制基本正确 | 未真实驱动 cancel/grab loss/destroy | Task 14A |
| 01B 媒体 hit testing | 父仓 ef036ad | 机制基本正确 | 测试复制 Overlay z-order，没有实例化生产 Overlay | Task 14B |
| 02 通知滑动稳定 ID | 父仓 58254c2 | 机制基本正确 | A 删除、B 换绑、Timer 到期只在 Python 镜像中 | Task 15 |
| 03 AppMenu request identity | 父仓 28f75bd | 完整 | 已有生产 AppMenu qmltestrunner 覆盖 generation；后续 demand freshness 另有新缺陷 | Task 03 |
| 04 AppsSettings permissions identity | 父仓 417e8e4 | 机制基本正确 | 875 行测试仍主要是正则和 Python 镜像 | Task 16 |
| 05 controller destroy cleanup | 父仓 ca1659c；niri 4a9f1f1a | 机制基本正确 | abnormal disconnect 与真实 output damage 证据不足 | Task 19 |
| 06 edge-reveal/rescale clip | 父仓 475e25e；niri fadfdcd4 | 部分完成 | closing complete miss 返回未裁剪元素 | Task 05 |
| 07 Apps identity refresh | 父仓 14dd788 | 部分完成 | QuickShell 只监听目录且无公开 rescan；父仓仍每两秒排序同一快照 | Task 07A、07B |
| 08 Weather geocode generation | 父仓 ee84400 | 部分完成 | FailedToStart 不收口 | Task 01 |
| 09 Dynamic Island notification identity | 父仓 b070904 | 部分完成 | 手工通知 IPC busy 时被丢弃 | Task 04 |
| 10 TaskSwitcher release session | 父仓 b83e759 | 机制基本正确 | 缺少真实 Qt Timer 会话测试 | Task 17 |
| 11 swipe click/drag intent | 父仓 90fcda7 | 部分完成 | click suppression 跨 pointer session | Task 10 |
| 12 InputMethod label | 父仓 1ff7215 | 部分完成 | displayText 没有 UI consumer | Task 09 |
| 13 full scene transform | 父仓 9c1b912；QuickShell be713b1 | 部分完成 | destroy 防御控制流矛盾且无 Qt 生命周期测试 | Task 13 |
| 14 incremental glass regions | 父仓 bfb13f1；QuickShell 4f7cada | 部分完成 | duplicate/conflicting regionId 状态漂移 | Task 06 |
| 15 fallback materialAlpha | 父仓 848e9f2；QuickShell f73859d | 机制基本正确 | 父仓测试仅模拟二值规则，没有运行 fallback owner | Task 20 |
| 16 sample/visible geometry | 父仓 00b1620；niri 7eaec605 | 机制基本正确 | Rust 几何测试通过；GPU/xray/多 scale 留到最终矩阵 | Task 21 |
| 17 thumbnail coalescing | 父仓 ad6e94e | 机制基本正确 | 捕获次数只在 Python 镜像中统计 | Task 18 |
| 18 Clipboard event refresh | 父仓 a9cdf9d | 部分完成 | list in-flight 时丢刷新事件 | Task 02 |
| 19 AppMenu demand probing | 父仓 035f58b | 部分完成 | 同 identity 显式打开需求被旧 probe 吞掉 | Task 03 |
| 20 volume OSD dedupe | 父仓 ebcdafd | 部分完成 | disable/reconnect baseline 不完整 | Task 11 |
| 21 visualizer update cadence | 父仓 7c597fc | 部分完成 | 多屏隐藏实例仍运行 | Task 08 |
| 22 lock minute clock | 父仓 382fb5a | 部分完成 | 未使用现有 SystemClock owner；该 owner 也缺少确定性 time-jump 测试 seam | Task 12A、12B |

上述父仓提交均可从 origin/main 到达；niri 提交可从 origin/tahoe-layer-animations 到达；QuickShell 提交可从 origin/quickshell-tahoe-desktop 到达。这里记录的是审查时已经存在的远端可达事实，不替代本路线图未来每一项的新 push/remote verification 证据。

---

## 3. 确认问题与根因

### 3.1 当前集成基线失败

证据：

- tahoe-shell/components/WeatherBackground.qml:53-54
- tahoe-shell/tests/test_motion_token_convergence.py:33

根因：

WeatherBackground 新增两个 NumberAnimation 时直接使用 Easing.OutCubic，没有复用现有 motion token owner。该提交晚于原路线图，但当前 HEAD 的完整测试因此失败。

影响：

- 当前分支不能宣称最终集成测试通过。
- 后续每个任务无法以全绿基线判断新增回归。

### 3.2 Weather geocode FailedToStart 卡死

证据：

- tahoe-shell/services/Weather.qml:378-403
- tahoe-shell/services/Weather.qml:917-928
- quickshell/src/io/process.cpp:43-49
- quickshell/src/io/process.cpp:289-296

事件顺序：

1. startGeocode 设置 in-flight generation 和 locationSearching=true。
2. geocodeProcess.running=true 创建 QProcess，因此同步读取 running 仍为 true。
3. curl 缺失或不可执行，QProcess 异步产生 FailedToStart。
4. QuickShell Process 只发 runningChanged，不发 exited。
5. Weather 没有 onRunningChanged terminal fallback。
6. in-flight generation 永远不被消费，pending B/C 也不会启动。

### 3.3 Clipboard refresh 事件在 list 运行时丢失

证据：

- tahoe-shell/services/ClipboardHistory.qml:303-316
- tahoe-shell/services/ClipboardHistory.qml:519-527
- tahoe-shell/services/ClipboardHistory.qml:546-560

事件顺序：

1. watcher 事件 A 触发 listProbe。
2. listProbe 已读取 A 时的数据库快照。
3. watcher 事件 B 到来并重新启动 450ms refreshTimer。
4. Timer 到期时 listProbe 仍在运行，refresh 直接返回。
5. listProbe 退出后没有 pending 补跑。
6. B 最长到五分钟健康探测或 UI 打开时才出现。

### 3.4 AppMenu 显式打开需求被同 identity probe 吞掉

证据：

- tahoe-shell/components/AppMenuPopup.qml:42-45
- tahoe-shell/services/AppMenu.qml:97-104

根因：

probe 运行时，只有 targetChanged 才设置 probePending。同一窗口的菜单打开请求、registrar 变化恢复请求或显式 freshness 请求会被直接合并到可能已经读取旧状态的 probe 中，不能保证打开菜单时数据新鲜。

### 3.5 Dynamic Island 手工通知 IPC 语义回归

证据：

- tahoe-shell/shell.qml:590
- tahoe-shell/services/DynamicIsland.qml:435-447

旧行为：

手工或 smoke notification 在 expanded/userInteracting/busy 时保存为 pending，阻塞解除后展示。

当前行为：

blocksTransientNotification 为 true 时直接 return，手工通知永久丢失。

根因：

Task 09 把 pendingNotificationEntry 完全迁移为 ID-only FIFO 时，没有为不属于 Notifications.activeModel 的手工请求保留同一队列中的合法表示。

### 3.6 niri closing edge-reveal 完全 miss 时返回未裁剪元素

证据：

- niri/src/layer/closing_layer.rs:263-274

根因：

closing snapshot 与 reveal crop 相交时才构造 CropRenderElement；完全不相交时函数 fallthrough 返回原始 elem。该分支语义应是“不绘制”，而不是“恢复未裁剪绘制”。

风险：

- 快速反向。
- 分数 output scale 舍入。
- 非典型 anchor/edge 配置。
- 中心 layer 或移动路径完全离开 viewport。

### 3.7 QuickShell 增量 region diff 不支持重复或冲突 ID

证据：

- quickshell/src/wayland/tahoe_glass/surface.cpp:25-44
- quickshell/src/wayland/tahoe_glass/surface.cpp:98-129
- quickshell/src/wayland/tahoe_glass/qml.hpp:35
- quickshell/src/wayland/tahoe_glass/qml.cpp:74-78

根因：

sameRegionsById 和 old/new QHash 使用 last-wins，但发送阶段仍遍历原列表。对于：

~~~text
old = [A(id=1), B(id=1)]
new = [A(id=1), B(id=1)]
~~~

比较会认为有变化，发送 A 后跳过 B，使服务端从协议原有的 last-set-wins B 变成 A；mRegions 与服务端漂移，并在后续刷新继续发送无效请求。

### 3.8 Apps 每两秒复制、拼接并排序完整应用模型

证据：

- tahoe-shell/services/Apps.qml:60-68
- tahoe-shell/services/Apps.qml:87-95
- tahoe-shell/services/Apps.qml:116-159
- quickshell/src/core/desktopentrymonitor.cpp:46-65
- quickshell/src/core/desktopentry.hpp:294-318

根因：

该问题跨越两个现有 owner：

1. QuickShell DesktopEntryMonitor 只向 QFileSystemWatcher 注册目录，没有观察已存在 desktop 文件本身。目录 watcher 对文件内容原位写入没有可靠跨平台通知保证；公开 DesktopEntries 也没有 rescan API。
2. 父仓 Apps 虽已有 DesktopEntries.applicationsChanged，仍保留 2 秒 Timer；每次 Timer 都复制 applications.values、构造多字段字符串并排序。若 QuickShell 没有重新扫描，Timer 读取的仍是同一批 stale DesktopEntry 对象。

问题：

- 每小时约 1800 次 O(n log n) 工作。
- 原位 Name/Icon/Exec 修改可能根本没有触发 QuickShell rescan。
- 重复读取同一模型不能恢复漏掉的文件系统变化。
- 与原 Task 07 的性能约束直接冲突。

### 3.9 多屏下隐藏 Dynamic Island 仍运行媒体可视化

证据：

- tahoe-shell/shell.qml:847-853
- tahoe-shell/components/DynamicIslandOverlay.qml:34-41
- tahoe-shell/components/DynamicIslandOverlay.qml:61
- tahoe-shell/components/DynamicIslandContent.qml:312-347
- tahoe-shell/components/DynamicIslandMediaView.qml:307-313

根因：

每个输出创建一份 Overlay。capsuleShown 使用 activeForScreen，但 mediaContentVisible 只检查全局 contentState。全局进入 expanded_media 后，所有输出的 MediaView 都可见并启动 Timer，只有目标屏幕的 capsule 实际显示。

### 3.10 InputMethod 标签没有运行时 UI 消费者

证据：

- tahoe-shell/services/InputMethod.qml:18-70
- tahoe-shell/components/TopBar.qml:25
- tahoe-shell/components/TopBar.qml:88
- tahoe-shell/components/SettingsPanel.qml:199-205

根因：

languageLabel 本身已能区分中、英、日、韩和未知，但全仓没有 UI 读取 inputMethodService.displayText。TopBar 仅保留未使用 property/signal，设置页读取 tooltipText。

### 3.11 swipe click suppression 跨越手势会话

证据：

- tahoe-shell/components/DynamicIslandOverlay.qml:334-350
- tahoe-shell/components/DynamicIslandOverlay.qml:386-402
- tahoe-shell/components/DynamicIslandOverlay.qml:455-483
- tahoe-shell/components/DynamicIslandMotion.js:57

根因：

suppressClick 是一个共享布尔值，由 180ms Timer 清除。新 press 不会清除上一会话 token，因此完成 swipe 后 180ms 内的下一次普通 click 会被旧状态吞掉。

### 3.12 volume/mute baseline 生命周期不完整

证据：

- tahoe-shell/services/DynamicIsland.qml:299-305
- tahoe-shell/services/DynamicIsland.qml:910-919
- tahoe-shell/services/DynamicIsland.qml:961-988

根因：

island 禁用时 syncVolumeOsdFromControls 在读取当前值之前返回，baseline 不更新；重新启用也不重新采样。Controls 对象不替换但 PipeWire sink 重连时也可能出现同类 baseline 失配。

### 3.13 锁屏分钟时钟没有使用现有系统时钟 owner

证据：

- tahoe-shell/components/LockScreen.qml:31-42
- tahoe-shell/components/LockScreen.qml:76-97
- quickshell/src/core/clock.hpp

根因：

LockScreen 自己维护 date property 和 Timer，只在 lock 与 ApplicationActive 时重同步。系统主动调时、时区变化或底层时钟跳变没有明确 owner 事件。

### 3.14 TahoeGlassRegion 销毁防御控制流与注释矛盾

证据：

- quickshell/src/wayland/tahoe_glass/qml.cpp:339-349

根因：

代码声明不能在 skipItem 上调用 parentItem，但 for 循环中的 continue 仍会执行增量表达式 current=current->parentItem()。

Qt 6.11 当前在 QObject::destroyed 前会解除 visual parent/child，因此正常路径下该分支通常不可达；仍应修正为与生命周期契约一致的防御代码，并用真实 Qt 对象销毁测试证明没有重复连接或悬挂 listener。

### 3.15 原执行流程证据不可追溯

复审在仓库中没有找到每项 staged diff SHA-256、独立子代理 verdict 或审查轮次记录，因此只能验证最终 Git 提交和远端可达性，不能从 Git 历史证明原路线图的独立审查门禁确实发生。

另外，原 Task 13、14、15 的父仓提交 9c1b912、bfb13f1、848e9f2 同时包含 gitlink 和父仓 Python token 测试，不符合“子仓实现/测试归属子仓，父仓指针提交只包含 gitlink”的隔离要求。

本路线图通过以下方式修正：

- 独立审查固定在最终 staged diff 之后。
- commit message 强制记录 Reviewed-Staged-SHA256、review agent/session、verdict 和 round。
- QuickShell/niri 行为测试放回对应子仓。
- 父仓 gitlink 提交只允许一个 gitlink 变化。

---

## 4. 目标架构与反腐化约束

所有任务都必须遵守以下约束。

### 4.1 单一事实来源

- AppMenu 只能保留一个 probe Process、一个 refresh 入口和一份菜单状态。
- Weather 只能保留一个 geocode Process 和一套 generation 状态。
- ClipboardHistory 只能保留一个 watcher、一个 list Process 和一个 refresh 调度状态机。
- Dynamic Island 只能保留一个通知 FIFO owner；不得新增并行 manual queue。
- Tahoe glass 只能保留一份 mRegions 和一条协议发送路径。
- Apps 只能由现有 Apps service 拥有 revision、fingerprint 和 model。
- OSD 只能使用现有 lastVolume/lastMuted baseline。

### 4.2 允许新增的最小状态

只有以下状态可以在证明必要后新增：

- request generation。
- stable object ID。
- 当前请求的 immutable identity。
- 单个 latest-pending 或 refreshPending 标志。
- 与当前 pointer session 绑定的 gesture token/epoch。
- 协议 owner generation。
- Task 04 同一通知 FIFO 内的 tagged discriminator，以及仅用于没有外部 live owner 的 manual IPC 请求的 immutable command payload；它不是第二个 queue，也不能复制 live Notification。
- 仅在 C++ 测试构建可见、生产路径仍调用系统 API 的 now-provider/test seam。

这些字段必须由现有 owner 唯一维护，不能成为第二份业务模型。

### 4.3 禁止模式

禁止：

- safeRefresh、newRefresh、fixedRefresh、refresh2 等平行入口。
- 为同一责任或同一管线新增第二个 Process、Timer、watcher；不同既有职责的 Timer 不受此字面限制，但不得借机扩张当前任务。
- 为同一业务责任新增第二份 selected/current/active/pending/model/cache。
- 为通过测试复制一份生产状态机到 Python。
- 仅靠 debounce、增加延迟或低概率化竞态。
- 用关闭动画、禁用 blur、禁用 clip、强制 scale=1 隐藏问题。
- 在 UI 调用方绕过真正 owner。
- 删除现有 public IPC、fallback、DND、多屏、reduced-motion、force refresh 或错误恢复能力。
- 通过放宽断言、跳过测试或增加 flaky 标记获得绿色结果。
- 在同一任务顺手重构、升级依赖、统一格式或修复下一任务。

### 4.4 行为测试要求

异步、Timer、MouseArea、生命周期和协议任务不得只使用源码 token 测试。

测试必须至少满足一种：

- qmltestrunner 实例化真实生产 QML。
- QuickShell C++ 单测实例化真实 owner 或协议 surface。
- niri Rust 单测/集成测试执行真实协议或 render element。
- 可重复的实际运行验证，并保存命令、日志、截图或请求计数。

Python 可以用于启动真实 QML runner、准备 fixture 和断言输出，但不能把生产状态机重写一遍后只测试镜像。

---

## 5. 仓库拓扑与提交顺序

| 仓库 | 路径 | 分支 | push 目标 |
|---|---|---|---|
| 父仓 | /home/wwt/niri | main | origin/main |
| niri 子仓 | /home/wwt/niri/niri | tahoe-layer-animations | origin/tahoe-layer-animations |
| quickshell 子仓 | /home/wwt/niri/quickshell | quickshell-tahoe-desktop | origin/quickshell-tahoe-desktop |

### 5.0 路线图启用与环境前置门禁

本报告按本次用户要求先保存到本地，因此交付时它本身是父仓唯一的未跟踪文件。它不能在 25 个任务之外永久遗留，否则最终 clean 定义不可达。

用户明确开始执行本路线图后、Task 00 开始前，必须先完成一次不计入修复任务编号的文档启用门禁：

1. 父仓只暂存本报告文件，不得夹带任何代码、gitlink 或其他文档。
2. 使用第 6 节 E–H 的同一 staged diff 哈希、独立只读审查、APPROVE、提交前 hash 复核、commit、普通 push 和远端确认流程。
3. 建议提交信息为 `docs: add source audit remediation roadmap`。
4. 以该文档提交后的父仓 HEAD 更新执行基线，然后才能开始 Task 00。
5. 若用户仍要求只保留本地文件、尚未授权执行或 push，则路线图保持“已交付但未启用”，不得开始 Task 00，也不得宣称最终工作区可 clean。

工具链也必须先验证。审查时当前主机的 `/usr/bin/cargo` 不是 rustup shim，且没有 `rustup`，所以 `cargo +nightly fmt` 目前必然失败。开始 Task 00 前必须在用户授权的环境准备步骤中让以下命令成功：

~~~text
command -v rustup
rustup toolchain install nightly --profile minimal --component rustfmt
rustup run nightly cargo fmt --version
~~~

安装或下载工具链不是代码任务，不得混入任何任务 commit。若无法完成，执行状态为 BLOCKED；不得用 stable rustfmt 冒充项目要求的 nightly 结果。

### 5.1 父仓任务

父仓任务必须：

1. 在父仓形成只含当前任务的 staged diff。
2. 测试通过。
3. 计算 staged diff SHA-256。
4. 独立子代理审查最终 staged diff。
5. APPROVE 后确认 staged hash 未改变。
6. commit。
7. push origin main。
8. fetch 或 remote contains 验证远端包含 commit。
9. 只有以上全部成功，任务才 COMPLETE。

### 5.2 子仓任务

niri 或 quickshell 任务属于一个逻辑任务，但必须完成两个互不混淆的提交阶段：

1. 在子仓实现和测试，只暂存当前任务文件，对子仓 diff 完整执行第 6 节 E–H：独立 hash、独立只读 APPROVE、commit、push 当前子仓分支、远端确认。
2. 返回父仓，把工作树 gitlink 指向已经推送且远端可达的子仓 commit。
3. 在暂存父仓 gitlink 之前，从父仓运行并记录完整 `python3 -m pytest -q tahoe-shell/tests`。QuickShell 任务还必须在子仓运行 `cmake --build build-tahoe -j2`；niri 任务必须在子仓运行该任务卡指定的 Rust 测试。任何失败都必须留在当前任务，子仓验证不能替代父仓完整测试。
4. 父仓只暂存对应 gitlink；测试必须留在所属子仓，禁止再次把父仓 Python token 测试与 gitlink 混在一起。
5. 对父仓 gitlink staged diff 重新、单独执行第 6 节 E–H 一次：显示 binary diff、diff check、计算新的 SHA-256、启动未参与实现的独立只读子代理并获得新的 APPROVE、提交前复核该 hash、commit、push origin/main、远端确认。
6. 父仓阶段不得复用子仓实现 diff 的 hash、review session、verdict 或测试摘要；两套证据都必须写入 Task 21 和每任务报告。
7. 最终验证父仓远端 gitlink 精确指向刚推送的子仓 commit。

任何一步失败，任务保持 BLOCKED，禁止开始下一任务。

### 5.3 QuickShell 行为测试构建

当前 quickshell/build-tahoe 的 BUILD_TESTING=OFF，不能作为新增 C++ 行为测试通过的证据。QuickShell 只忽略 `/build/` 和 `/build-tahoe/`；因此测试构建必须放在已忽略的 `build/tahoe-tests`，不得使用会污染工作区的 `build-tahoe-tests/`。Task 06 首次建立测试构建，并由后续 Task 07A、12A、13、20 复用：

~~~text
cd /home/wwt/niri/quickshell
cmake -S . -B build/tahoe-tests -G Ninja \
  -DBUILD_TESTING=ON \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_INSTALL_PREFIX=/home/wwt/.local
cmake --build build/tahoe-tests -j2
ctest --test-dir build/tahoe-tests --no-tests=error --output-on-failure
~~~

约束：

- `build/tahoe-tests` 是已被 `/build/` 规则覆盖的本地构建产物，禁止提交。
- Task 06 在 `src/wayland/tahoe_glass/test` 建立唯一共享 executable/CTest test `tahoe-glass-tests`，label 为 `tahoe-glass`；Task 13、20 只向该 executable 增加命名 test cases/source，不得再建 harness。
- Task 07A 在现有 core test 体系注册 CTest test `desktopentrymonitor`；Task 12A 注册 `systemclock`。
- Task 06/13/20 必须运行 `ctest --test-dir build/tahoe-tests -R '^tahoe-glass-tests$' --no-tests=error --output-on-failure` 和完整 ctest。
- Task 07A 必须以 `-R '^desktopentrymonitor$'` 运行；Task 12A 必须以 `-R '^systemclock$'` 运行；两者还必须运行完整 ctest。所有 filter 都必须带 `--no-tests=error`。
- Release 构建 quickshell/build-tahoe 仍必须成功，防止测试配置掩盖生产构建错误。

Task 13 只要求仓库实际支持的 ASAN option，不虚构 UBSAN target。使用同样位于已忽略 `/build/` 下的独立配置：

~~~text
cd /home/wwt/niri/quickshell
cmake -S . -B build/tahoe-asan-tests -G Ninja \
  -DBUILD_TESTING=ON \
  -DASAN=ON \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_INSTALL_PREFIX=/home/wwt/.local
cmake --build build/tahoe-asan-tests --target tahoe-glass-tests -j2
ctest --test-dir build/tahoe-asan-tests -R '^tahoe-glass-tests$' \
  --no-tests=error --output-on-failure
~~~

---

## 6. 全局严格串行执行契约

每个任务必须完整执行以下阶段。

### A. 基线

记录：

- 仓库、分支、remote、HEAD。
- 通过 `git ls-remote --exit-code --heads origin refs/heads/<branch>` 读取权威远端 tip；任务开始前本地 HEAD 必须与该 OID 精确相等，不能只依赖可能陈旧的 remote-tracking ref 或 clean status。
- git status --short。
- 父仓及两个子仓当前指针。
- 当前任务开始前已有的未提交改动。
- 当前最小相关测试结果。

禁止 reset、clean、checkout、restore 或 stash 用户改动。

### B. 根因证明

写代码前必须输出：

- 确定的事件顺序或坐标转换顺序。
- 真正的状态/资源 owner。
- 错误写入或错误返回位置。
- 成功、失败、cancel、destroy、recreate、旧回调晚到行为。
- 受保护的现有功能。
- 计划修改文件。

无法证明根因时不得试错式修改。

### B.1 负向证明（测试必须能抓住旧错误）

“新增测试在当前代码上通过”不是充分证据。每项必须在写入生产修复前建立可追溯的 RED 证据：

- Task 00–13：先只加入当前任务的回归测试或最小 test-only seam，在未修生产实现上运行同一测试；必须因任务描述的旧错误失败。Task 00 可直接使用当前已经失败的 motion convergence 测试。记录命令、退出码和精确失败断言后，才能修改生产逻辑。
- Task 14A–20：由于当前生产实现大体已修，必须在 `/tmp` 下的 disposable detached worktree 中做负向控制。优先将同一测试 patch 应用到表 2.4 所列原修复提交的父提交；若后续测试基础设施无法干净移植，则只在该临时 worktree 做一个最小、明确记录且精确恢复旧分支的 mutation。负向控制必须失败，主工作树当前实现上的同一测试必须通过。
- 负向 worktree 只用于证明测试灵敏度；禁止在那里 commit/push，禁止把 mutation 复制回主工作树。记录基线 commit、test patch hash、mutation diff、失败断言和清理结果。
- Task 21 是纯验收报告任务，明确豁免制造负向代码；它验证前 24 项已经保存的 RED/GREEN 证据。

若无法让测试在旧实现或精确 mutation 上失败，说明测试没有证明回归，当前任务不得进入独立审查。

### C. 最小实现

- 只修改当前任务允许文件。
- 保持原 API 和单一 owner。
- 添加能在旧实现上失败的真实回归测试。
- 不处理下一任务发现。

### D. 验证

依次运行：

1. 新增最小回归测试。
2. 受影响模块测试。
3. 父仓任务运行完整 Tahoe 测试；子仓任务必须同时运行子仓相关编译/测试，并在更新父仓 gitlink 后运行父仓完整 Tahoe 测试，二者不得互相替代。
4. niri 改动使用项目要求的 nightly rustfmt 执行 `rustup run nightly cargo fmt --all -- --check`；不得用不匹配的 stable rustfmt 结果代替。
5. QuickShell C++ 改动使用 clang-format -Werror --dry-run 检查本任务改动文件，或运行项目 CI 等价检查。
6. git diff --check。
7. 检查无调试输出、生成文件、无关格式变化。

### E. 暂存与稳定哈希

- 只逐文件、逐 hunk 暂存当前任务。
- 禁止 git add . 和 git add -A。
- 显示 git diff --cached --binary。
- 运行 git diff --cached --check。
- 所有实现者和审查者都使用同一命令对最终 staged binary diff 计算 SHA-256：

~~~text
git -c core.quotepath=false diff --cached --binary --full-index | sha256sum
~~~

- 任何 index 变化都会使该 SHA-256 失效。

### F. 独立子代理审查

必须启动一个未参与实现的独立子代理：

- 只读。
- 不得修改文件。
- 审查最终 staged diff，而非 working diff。
- 核对 staged SHA-256。
- 必须输出 APPROVE 或 REQUEST_CHANGES。

### G. 返工

若 REQUEST_CHANGES：

1. 取消当前任务暂存，但不丢弃文件。
2. 修复 findings。
3. 重跑全部相关测试。
4. 重新暂存。
5. 重新计算 SHA-256。
6. 新建一个未参与实现和返工的只读子代理，启动新的独立审查轮次；不得让实现者自审，也不得把旧 APPROVE/REQUEST_CHANGES 直接沿用。

任何代码或 index 变化都会使旧 APPROVE 失效。

### H. commit、push、远端确认

最终 APPROVE 后：

1. 再次计算 staged SHA-256，必须与获批 hash 一致。
2. 在 commit 前读取 `git ls-remote --exit-code --heads origin refs/heads/<branch>`，要求恰有一个目标 ref，且其 OID 与当前 `git rev-parse HEAD` 完全相同。若本地已 ahead/behind 或远端 ref 不唯一/不存在，禁止 commit/push 并标记 BLOCKED。
3. 创建单一、可回滚 commit，并在 commit message 中保留下列 trailers：

~~~text
Independent-Review: <agent/session identifier>
Review-Verdict: APPROVE
Review-Round: <number>
Reviewed-Staged-SHA256: <sha256>
Tests: <最小测试和模块测试摘要>
~~~

这些 trailers 只记录已经发生的审查和测试，不得伪造；它们不改变获批的 staged diff，因此可以让后续审计从 Git 历史确认门禁证据。

4. commit 后、push 前，以 `git -c core.quotepath=false diff --binary --full-index HEAD^ HEAD | sha256sum` 重新计算实际 commit patch；必须与获批的 staged SHA-256 相同，并确认 commit hook 没有留下意外 working/index 改动。
5. 紧邻 push 再次读取目标远端 tip，并同时断言：`git rev-parse HEAD^` 等于该远端 OID；`git rev-list --count <remote-tip>..HEAD` 恰为 1。这样待推送区间只能是刚审查的一个 commit，不能顺带发布旧的本地未审提交。
6. 若 hash、工作区或远端 tip/count 任一不匹配，禁止 push，任务标记 BLOCKED。若已经存在本地未推送 commit，不能直接套用 G，也不得擅自 reset/amend；必须报告准确状态并请求用户授权如何撤回该本地 commit，然后重新形成 staged diff、重跑测试并启动新的独立审查。
7. 只有第 4–5 步完全一致后，才使用显式 refspec 普通 push `git push origin HEAD:refs/heads/<branch>`，禁止 force。
8. push 后再次运行 `git ls-remote`，目标远端 tip 必须精确等于 `git rev-parse HEAD`；“remote contains”但 tip 不相等不算确认成功。
9. 输出任务完成报告。

push 失败时不得 pull、rebase、merge 或改写历史，除非用户明确授权。

### I. 下一任务门禁

只有同时满足以下条件，才允许开始下一任务：

- 最小测试通过。
- 模块/完整测试通过。
- 独立审查 APPROVE。
- commit 成功。
- push 成功。
- 远端确认成功。
- 子仓任务的父仓 gitlink 也已 commit、push、确认。

---

## 7. 独立审查提示词模板

~~~text
你是当前任务的独立审查代理。你没有参与实现，只允许读取代码、
最终 staged diff、测试输出和 git 状态，不得修改任何文件。

TASK:
[任务编号和标题]

ORIGINAL FAILURE:
[原始事件顺序、用户影响、旧实现错误]

AUTHORITATIVE OWNER:
[唯一状态/资源 owner]

CLAIMED FIX:
[具体状态转换或坐标转换]

PROTECTED BEHAVIOR:
[不得破坏的现有功能]

STAGED DIFF SHA-256:
[hash]

TESTS:
[命令、退出码、通过数]

请主动审查：
1. 是否修改真正 owner，而不是 UI 掩盖。
2. 是否新增平行 API、Process、Timer、queue、model 或 cache。
3. success/failure/cancel/destroy/recreate/旧回调是否统一受保护。
4. Timer 或 callback 是否捕获稳定 ID/epoch。
5. MouseArea press/move/release/cancel/grab loss 是否完整。
6. 多屏、reduced motion、DND、fallback、force refresh 是否保持。
7. 快速反向、非 1.0 scale、完全不相交、fractional scale 是否正确。
8. 测试是否运行生产代码，并能在旧实现上失败。
9. staged diff 是否只包含当前任务。
10. staged SHA-256 是否与声明一致。

输出：
VERDICT: APPROVE
或
VERDICT: REQUEST_CHANGES

FINDINGS:
- [严重度] 文件:行号 — 触发条件、影响、修复方向

TEST_GAPS:
- 缺口；没有则写 None

ANTI_CORRUPTION_CHECK:
- 唯一事实来源
- 平行接口/双写路径
- owner 是否正确
~~~

---

## 8. 严格任务顺序

~~~text
Task 00  恢复当前完整测试基线
Task 01  Weather FailedToStart
Task 02  Clipboard lossless refresh
Task 03  AppMenu explicit demand freshness
Task 04  Dynamic Island manual notification semantics
Task 05  niri closing edge-reveal complete miss
Task 06  QuickShell duplicate region ID
Task 07A QuickShell DesktopEntryMonitor file-change owner
Task 07B Apps event-driven desktop refresh
Task 08  Dynamic Island multi-screen visualizer
Task 09  InputMethod UI consumer
Task 10  Dynamic Island session-scoped click suppression
Task 11  Dynamic Island OSD baseline lifecycle
Task 12A QuickShell SystemClock deterministic lifecycle
Task 12B LockScreen consumes SystemClock
Task 13  QuickShell transform destruction lifecycle
Task 14A Real QML media interaction lifecycle
Task 14B Real QML production Overlay hit testing
Task 15  Real QML notification swipe identity
Task 16  Real QML AppsSettings permissions identity
Task 17  Real QML TaskSwitcher release lifecycle
Task 18  Real QML ThumbnailProvider coalescing
Task 19  niri abnormal disconnect and output damage tests
Task 20  QuickShell fallback owner behavioral tests
Task 21  Final integration acceptance report
~~~

该顺序不可调整，除非独立审查明确证明存在新的硬依赖并由用户授权。

---

## 9. 逐任务修复卡片

### Task 00：恢复当前完整 Tahoe 测试基线

优先级：阻断
仓库：父仓
唯一目标：消除 WeatherBackground 内联 easing，使当前完整 Tahoe 测试在开始功能修复前恢复全绿。

允许修改：

- tahoe-shell/components/WeatherBackground.qml
- tahoe-shell/tests/test_motion_token_convergence.py
- tahoe-shell/tests/test_weather_background_qml.py（新增 runner）
- tahoe-shell/tests/tst_weather_background.qml（新增）

实现要求：

- 复用 Motion.js 或现有 approved motion token。
- 不创建 Weather 专用重复 easing 常量，除非证明现有 owner 没有正确语义。
- 不调整动画时长、视觉幅度或 FrameAnimation。

验收：

- motion token convergence 测试通过。
- WeatherBackground 可加载。
- 完整 tahoe-shell/tests 通过。

建议 commit：

~~~text
fix(weather-background): use shared motion easing
~~~

---

### Task 01：闭合 Weather geocode FailedToStart 生命周期

优先级：高
仓库：父仓
唯一目标：curl 无法启动时，本代请求必须失败收口，loading 清除，最新 pending 请求仍能执行。

允许修改：

- tahoe-shell/services/Weather.qml
- tahoe-shell/tests/test_weather_geocode_request_identity.py
- tahoe-shell/tests/tst_weather_geocode_request_identity.qml（新增）
- tahoe-shell/tests/qml_imports/Quickshell/Io 下现有 Process、StdioCollector、TestProcessRegistry fake

实现要求：

- 在现有 geocodeProcess 上处理 runningChanged FailedToStart fallback。
- success、nonzero exit、cancel、FailedToStart 使用同一个 idempotent finishGeocodeRequest。
- generation 只能消费一次。
- 正常 onExited 后的 runningChanged 不得把成功覆盖成失败。
- A FailedToStart 后 B/C 最新请求必须启动。

禁止：

- 第二个 geocode Process。
- safeSearchLocations。
- debounce 或重试 Timer。
- 同步读取 running 作为唯一失败检测。

真实测试：

- 实例化生产 Weather.qml。
- A FailedToStart。
- A FailedToStart 时已 pending B。
- 正常 onExited 后 runningChanged 双信号。
- A cancel 晚到、B success。

建议 commit：

~~~text
fix(weather): finish failed geocode starts
~~~

---

### Task 02：让 Clipboard list refresh 在 in-flight 期间无损合并

优先级：高
仓库：父仓
唯一目标：listProbe 运行期间到达的 watcher/UI/delete/clear refresh 意图，必须在退出后合并补跑一次。

允许修改：

- tahoe-shell/services/ClipboardHistory.qml
- tahoe-shell/tests/test_clipboard_history_event_refresh.py
- tahoe-shell/tests/tst_clipboard_history_event_refresh.qml（新增）
- tahoe-shell/tests/qml_imports/Quickshell/Io 下现有 Process registry fake

实现要求：

- 由现有 ClipboardHistory owner 维护一个 refreshPending 标志。
- listProbe running 时 refresh 只置 pending。
- 新一轮真正启动时清 pending。
- onExited 和 FailedToStart terminal path 都检查 pending，并用现有 refresh 入口补跑。
- 多个事件最多合并为一次补跑。

禁止：

- 第二个 list Process。
- 第二个 watcher。
- 再引入高频轮询。
- 新增 refreshNow/refreshSafe 等入口。

测试事件序列：

- A list 已读取快照，B watcher 到达，A 后退出。
- A 运行时连续 B/C/D，只补跑一次。
- delete/clear 与 watcher 重叠。
- FailedToStart 后 pending 可恢复。
- 空闲一小时仍没有高频 list。

建议 commit：

~~~text
fix(clipboard): preserve refreshes during list probes
~~~

---

### Task 03：保证 AppMenu 显式需求获得最新 probe

优先级：高
仓库：父仓
唯一目标：菜单打开或明确 freshness 请求不能被同 identity 的旧 in-flight probe 吞掉。

允许修改：

- tahoe-shell/services/AppMenu.qml
- tahoe-shell/components/AppMenuPopup.qml
- tahoe-shell/tests/test_app_menu_demand_probe.py
- tahoe-shell/tests/test_app_menu_probe_identity_qml.py
- tahoe-shell/tests/tst_app_menu_probe_identity.qml
- tahoe-shell/tests/qml_imports/Quickshell/Io 下现有 Process registry fake

实现要求：

- 继续使用唯一 refresh 和唯一 Process。
- 在现有 refresh 意图中区分 focus/health 与 explicit demand，或证明统一 latest-pending 更安全。
- 显式 demand 到来时，旧结果不能成为最终菜单。
- 多个 demand 合并为最新一次。
- 不形成 demandRefresh 平行入口。

保护：

- A→B→C generation 行为。
- FailedToStart fallback。
- 完全空闲时不恢复 5 秒轮询。
- registrar 缺失和恢复提示。

真实测试：

- health/focus probe 已读取旧快照但尚未退出时打开同一窗口菜单，必须补跑一次 explicit demand。
- 多次同 identity explicit demand 只合并为一次 follow-up。
- demand 期间 target A→B→C，最终只能落地 C。
- 旧 probe 正常退出、FailedToStart 和 cancel 都不能清除更新 generation 的需求。
- 空闲等待超过原 5 秒周期仍不启动 probe。

建议 commit：

~~~text
fix(app-menu): preserve explicit refresh demand
~~~

---

### Task 04：恢复 Dynamic Island 手工通知的排队语义

优先级：高
仓库：父仓
唯一目标：dynamicIslandShowNotification 在 busy/expanded/userInteracting 时不丢失，并与真实 notification FIFO 串行展示。

允许修改：

- tahoe-shell/services/DynamicIsland.qml
- tahoe-shell/tests/test_dynamic_island_notification_identity.py
- tahoe-shell/tests/test_dynamic_island_manual_notification_queue.py（新增 runner）
- tahoe-shell/tests/tst_dynamic_island_manual_notification_queue.qml（新增）
- tahoe-shell/tests/qml_imports 下现有 Notifications/Quickshell 最小 fake

架构要求：

- 只能有一个 pending notification FIFO。
- live Notifications 项只保存稳定 ID，出队时回查 activeModel。
- manual IPC 项没有外部 live owner，可以在同一 FIFO 中保存不可变命令 payload。
- 必须使用 tagged entry 或等价单队列设计；不得新增 pendingManualNotifications 第二队列。
- DND/disable/reset 对两类请求使用同一清理语义。

验收：

- busy 时 manual 请求排队，解除后显示。
- manual 与两个 live ID 按到达顺序展示。
- live ID 删除后跳过，不影响 manual。
- replace-id 行为不回归。
- DND/disable 清空全部 pending。

建议 commit：

~~~text
fix(dynamic-island): preserve queued manual notifications
~~~

---

### Task 05：niri 完全不相交的 closing edge-reveal 不得绘制

优先级：高
仓库：niri 子仓，然后父仓 gitlink
唯一目标：closing snapshot 完全离开 reveal viewport 后，不得 fallthrough 绘制未裁剪元素。

允许修改：

- niri/src/layer/closing_layer.rs
- niri/src/layer/mapped.rs（仅当现有 render 返回类型必须表达 empty）
- niri/src/tests/layer_shell.rs
- closing_layer.rs 内现有或新增的局部单测模块

实施前必须写清：

- render 返回值为何当前不能表达 empty。
- 调用方是否已有 Option/empty element 模式。
- full miss、partial intersection、no edge-reveal 三种语义。
- fractional output scale 和 rounding。

禁止：

- 扩大 crop。
- 强制 alpha=0 掩盖错误，除非它是现有合法 empty 表示且 damage 正确。
- 禁用 edge reveal。
- 复制一条 closing render pipeline。

测试：

- partial intersection。
- complete miss。
- fractional scale。
- inherited non-1.0 scale。
- rapid open→close reverse。
- no edge-reveal 保持原行为。

建议子仓 commit：

~~~text
fix(layer): drop fully clipped closing reveals
~~~

建议父仓 commit：

~~~text
chore(niri): update closing reveal clipping fix
~~~

---

### Task 06：规范化 QuickShell Tahoe region ID 冲突

优先级：高
仓库：quickshell 子仓，然后父仓 gitlink
唯一目标：mRegions、协议请求与服务端最终状态对重复/冲突 ID 使用一致语义，且无变化时零请求零 commit。

允许修改：

- quickshell/src/wayland/tahoe_glass/surface.cpp/.hpp
- quickshell/src/wayland/tahoe_glass/test 下的 C++ 测试
- quickshell/src/wayland/tahoe_glass/CMakeLists.txt
- quickshell/src/wayland/tahoe_glass/test/CMakeLists.txt
- 按第 5.3 节建立唯一共享 `tahoe-glass-tests` executable/CTest test；不得为后续任务或单个 case 建立第二套测试框架。

建议语义：

- 保持协议已有 last-set-wins。
- 在单一 setRegions 状态机内把输入规范化为每 ID 的最终状态。
- mRegions 保存规范化后的唯一 ID 状态。
- 临时 QHash 可用于计算，不能成为第二份持久状态。

必须覆盖：

- 相同重复列表二次 set 为 no-op。
- duplicate A/B 的最终值是 B。
- region ID 改成已有 ID。
- 删除冲突项。
- reorder。
- 单字段更新。
- 全部清空。
- 每个 ID 每次最多一个 set/remove。

禁止：

- 新增 setRegionsIncremental/setRegionsFull。
- 保留原列表与 canonical map 两份持久权威状态。
- 在 QML 调用方过滤以掩盖 owner 问题。

建议子仓 commit：

~~~text
fix(tahoe-glass): canonicalize region ids before diffing
~~~

建议父仓 commit：

~~~text
chore(quickshell): update canonical glass region diff
~~~

---

### Task 07A：让 QuickShell DesktopEntryMonitor 观察真实文件变化

优先级：中高
仓库：quickshell 子仓，然后父仓 gitlink
唯一目标：已存在 desktop 文件的原位内容修改、原子替换、新增、删除和子目录变化都必须驱动现有 DesktopEntryManager rescan owner。

已确认事实：

- 当前 DesktopEntryMonitor 只连接 QFileSystemWatcher.directoryChanged。
- startMonitoring/scanAndWatch 只注册目录和一层子目录。
- QML DesktopEntries 没有公开 rescan API。
- 因此正确修复层是 QuickShell 现有 DesktopEntryMonitor，而不是父仓新增 rescan 入口。

允许修改：

- quickshell/src/core/desktopentrymonitor.cpp/.hpp
- 必要时 quickshell/src/core/desktopentry.cpp/.hpp 中现有 monitor→manager 接线
- quickshell/src/core/test 下 DesktopEntryMonitor/Manager QtTest
- quickshell/src/core/test/CMakeLists.txt
- quickshell/src/core/CMakeLists.txt

实现要求：

- 继续使用唯一 DesktopEntryMonitor 和唯一 DesktopEntryManager scan pipeline。
- 在目录 watcher 之外跟踪扫描到的 desktop 文件，或采用 Qt 已有等价机制。
- fileChanged、directoryChanged 进入同一个 debounce/processChanges。
- 文件被原子替换或 watcher 自动移除后，下一次 scan 必须重建正确 watch 集合。
- 新子目录出现后必须纳入监控。
- 不向 QML 暴露 rescan() 作为父仓旁路。

真实测试：

- QTemporaryDir 中新增 desktop 文件。
- 原位修改 Name/Icon/Exec。
- 临时文件 rename 覆盖原文件。
- 删除。
- 新建子目录后新增文件。
- 多个快速事件只触发一次 debounce scan。
- rescan 后 watcher 仍然有效。

建议子仓 commit：

~~~text
fix(desktop-entries): monitor in-place file changes
~~~

建议父仓 commit：

~~~text
chore(quickshell): update desktop entry monitoring
~~~

---

### Task 07B：移除 Apps 每两秒全量 fingerprint 排序

优先级：中高
仓库：父仓
依赖：Task 07A 的子仓和父仓 gitlink 均已远端确认
唯一目标：Apps 只消费修复后的 DesktopEntries applicationsChanged，不再每两秒复制、拼接和排序同一快照。

允许修改：

- tahoe-shell/services/Apps.qml
- tahoe-shell/tests/test_apps_desktop_entries_identity_refresh.py
- tahoe-shell/tests/tst_apps_desktop_entries_identity_refresh.qml（新增）
- tahoe-shell/tests/qml_imports 下 DesktopEntries 所需最小 fixture

实施要求：

- 移除 2 秒 desktopEntriesRefreshTimer。
- fingerprint 仍由 Apps 唯一维护，只在 applicationsChanged/initial load/明确 force 时计算。
- 不新增父仓 rescan API、恢复 Process 或低频伪恢复 Timer。
- Launchpad、搜索和 pinned app 继续读取同一 realApplications。

性能与功能证据：

- 空闲一小时 fingerprint 计算次数为零。
- 500/1000 entry 下只在真实变化时计算。
- 等数量替换。
- Name/Icon/Exec 修改。
- NoDisplay 进入/离开。
- 无变化 signal 不 rebuild。

建议 commit：

~~~text
perf(apps): stop periodic desktop entry sorting
~~~

---

### Task 08：只让目标屏幕运行 Dynamic Island 媒体可视化

优先级：中
仓库：父仓
唯一目标：多屏时只有 activeForScreen 的 expanded media 实例运行 visualizer Timer 和 bar animations。

允许修改：

- tahoe-shell/components/DynamicIslandOverlay.qml
- tahoe-shell/components/DynamicIslandContent.qml
- tahoe-shell/components/DynamicIslandMediaView.qml
- tahoe-shell/tests/test_dynamic_island_visualizer_animation_align.py
- tahoe-shell/tests/tst_dynamic_island_visualizer_animation_align.qml（新增）
- tahoe-shell/tests/qml_imports 下屏幕与媒体依赖的最小 fake

实现要求：

- 复用 activeForScreen/capsuleShown，不新增 second visibility state。
- 目标屏切换时旧实例停止、新实例开始。
- fade-out 是否短暂运行必须有明确产品语义和上限。
- reduced motion、paused、非 media 继续停止。

验收：

- 两屏只有一个 phase 前进。
- targetScreenName 切换后 ownership 转移。
- hidden/paused/reduced motion 零 tick。

建议 commit：

~~~text
perf(dynamic-island): gate visualizer to target screen
~~~

---

### Task 09：把 InputMethod 唯一语言标签接回现有 UI

优先级：中
仓库：父仓
唯一目标：用户实际能看到现有 languageLabel 的中、英、日、韩和未知标签。

允许修改：

- tahoe-shell/components/TopBar.qml
- tahoe-shell/tests/test_input_method_language_label.py
- tahoe-shell/tests/tst_input_method_language_label.qml（新增）
- tahoe-shell/tests/qml_imports 下 TopBar 依赖的最小 fake

要求：

- 复用 inputMethodService.displayText。
- 复用现有 toggleInputMethod signal。
- 不创建第二个 label 函数或第二个输入法 service。
- 不破坏 Dynamic Island、tray、状态区宽度和窄屏布局。

验收：

- 中文 中。
- English EN。
- Japanese あ。
- Korean 한。
- unknown Aa。
- unavailable --。
- 点击仍调用唯一 toggle。

建议 commit：

~~~text
fix(topbar): display input method language label
~~~

---

### Task 10：把 Dynamic Island click suppression 绑定到单个 pointer session

优先级：中
仓库：父仓
唯一目标：当前 swipe/reject 的 composed click 被抑制，但下一次新 press 不继承旧抑制。

允许修改：

- tahoe-shell/components/DynamicIslandOverlay.qml
- tahoe-shell/components/DynamicIslandMotion.js（仅当现有 session token 常量确实属于该唯一 owner）
- tahoe-shell/tests/test_dynamic_island_swipe_click_intent.py
- tahoe-shell/tests/tst_dynamic_island_swipe_click_intent.qml（新增）
- tahoe-shell/tests/qml_imports 下 Overlay 所需最小 fake

实现提示：

- 优先使用 session epoch/token 或 release-click 同会话标志。
- 新 press 开始时结束旧 suppression 生命周期。
- 不新增第二个 MouseArea 或坐标转发。

测试：

- swipe 后 composed click 被抑制。
- 180ms 内第二次普通 click 成功。
- vertical reject 后第二次 click。
- cancel。
- media button 不触发 capsule click。

建议 commit：

~~~text
fix(dynamic-island): scope click suppression to gesture
~~~

---

### Task 11：闭合 Dynamic Island OSD baseline 生命周期

优先级：中
仓库：父仓
唯一目标：disabled、reenabled、Controls replacement 和 PipeWire sink readiness/reconnect 后 baseline 正确，既不误报也不吞真实变化。

允许修改：

- tahoe-shell/services/DynamicIsland.qml
- tahoe-shell/tests/test_dynamic_island_volume_osd_dedupe.py
- tahoe-shell/tests/tst_dynamic_island_volume_osd_dedupe.qml（新增）
- tahoe-shell/tests/qml_imports 下 Controls/PipeWire 所需最小 fake

实现要求：

- lastVolume/lastMuted 仍是唯一 baseline。
- island 禁用时可以更新 baseline但不得展示，或重新启用时统一 capture。
- service/sink replacement 使用同一 capture owner。
- 不新增 debounce Timer。

测试：

- disabled 期间 0.4→0.6。
- reenable 后重复 0.6 不展示。
- reenable 后 0.6→0.5 展示。
- sink reconnect 首次值只基线化。
- mute+volume 同 turn 仍只展示一次。

建议 commit：

~~~text
fix(dynamic-island): resync osd baselines on lifecycle changes
~~~

---

### Task 12A：为 QuickShell SystemClock 建立可验证的 resync 契约

优先级：中低
仓库：quickshell 子仓，然后父仓 gitlink
唯一目标：由现有 SystemClock owner 提供显式 resync 能力和确定性 C++ 测试 seam，证明分钟精度下对 suspend、向前/向后调时和时区变化的收敛语义。

已确认能力边界：

- 当前 SystemClock 只有内部 QTimer，没有 OS 主动调时通知。
- Timer 触发时会比较 currentDateTime 与原 target；偏差超过 500ms 时使用真实 current time。
- 因此无额外平台事件时，Minutes 精度的保证是“显式 resync 立即更新；其他 wall-clock 跳变最迟在下一分钟 Timer 触发时收敛”，不是 50ms 内主动通知。

允许修改：

- quickshell/src/core/clock.cpp/.hpp
- quickshell/src/core/test 下新的 clock QtTest
- quickshell/src/core/test/CMakeLists.txt
- quickshell/src/core/CMakeLists.txt

实现要求：

- 在现有 SystemClock 上增加唯一获授权的 QML-callable `resync()` owner 方法；不得同时保留 `updateNow()`、`refresh()` 等别名，也不得创建 SystemClock2。
- 测试使用 `QS_TEST`/friend 范围内的 now-provider 或等价 test seam，不得实际修改主机系统时间；非 BUILD_TESTING 生产构建仍直接调用系统时间 API。
- test seam 不得作为第二个 QML 业务时钟公开。
- 保持 Hours/Minutes/Seconds 现有 API 与默认行为。
- 明确记录上述“显式立即、否则下一 precision boundary”保证。

真实 C++ 测试：

- initial value。
- explicit resync。
- forward jump。
- backward jump。
- timezone/offset change。
- disable/enable。
- target 偏差小于和大于 500ms。

建议子仓 commit：

~~~text
fix(system-clock): define deterministic resync behavior
~~~

建议父仓 commit：

~~~text
chore(quickshell): update system clock lifecycle support
~~~

---

### Task 12B：让 LockScreen 只消费 SystemClock owner

优先级：中低
仓库：父仓
依赖：Task 12A 的子仓和父仓 gitlink 均已远端确认
唯一目标：删除 LockScreen 自建 date/Timer owner，改为消费 SystemClock Minutes，并在 lock/ApplicationActive 时调用同一 owner 的 resync。

允许修改：

- tahoe-shell/components/LockScreen.qml
- tahoe-shell/tests/test_lock_screen_minute_clock.py
- tahoe-shell/tests/tst_lock_screen_minute_clock.qml（新增）
- tahoe-shell/tests/qml_imports 中 SystemClock 所需的最小现有模块 stub；不得复制计时状态机

实现要求：

- LockScreen 中不得保留并行 minuteTimer。
- SystemClock precision=Minutes。
- unlocked 时通过 enabled 停止无意义更新。
- lock 和 ApplicationActive 使用 Task 12A 的同一 resync 入口。
- UI 继续使用唯一 clock date 显示 HH:mm 和日期。

验收：

- 打开锁屏立即显示当前时间。
- lock/unlock 切换 enabled。
- resume 调用 resync。
- 分钟显示只由 SystemClock dateChanged 驱动。
- Task 12A 的 C++ 测试承担 forward/backward/timezone 确定性验证。
- 不宣称没有 OS 事件时能在下一分钟边界之前主动感知调时。

建议 commit：

~~~text
fix(lock-screen): consume the system clock owner
~~~

---

### Task 13：修正 TahoeGlassRegion ancestor destroy 防御生命周期

优先级：低但需验证
仓库：quickshell 子仓，然后父仓 gitlink
唯一目标：销毁/reparent 时不在 dying item 上调用 QQuickItem 方法，不残留 listener，不重复连接。

允许修改：

- quickshell/src/wayland/tahoe_glass/qml.cpp/.hpp
- quickshell/src/wayland/tahoe_glass/test 下的 Qt C++ 生命周期测试
- quickshell/src/wayland/tahoe_glass/CMakeLists.txt
- quickshell/src/wayland/tahoe_glass/test/CMakeLists.txt
- 复用 Task 06 建立或确认的 Tahoe glass 测试 target，不得再创建另一套 harness。

实现要求：

- 先判断 skipItem，再决定 break 或从安全对象继续。
- unlink/link 保持单一连接 owner。
- 不创建第二个 TransformWatcher。
- 保持四角 AABB 和完整 ancestor transform tracking。

真实测试：

- item destroy。
- direct parent destroy。
- visual parent 与 QObject owner 不同：销毁 visual parent 后 child 仍存活。
- reparent。
- repeated reparent 不重复 changed。
- region destroy 先于 item。
- 按第 5.3 节运行仓库实际支持的 ASAN 配置；本路线图不虚构 UBSAN target。

建议子仓 commit：

~~~text
fix(tahoe-glass): avoid traversing destroyed ancestors
~~~

建议父仓 commit：

~~~text
chore(quickshell): update glass transform lifecycle fix
~~~

---

### 生产行为测试任务的共用门禁（Task 14A–20）

这些任务的唯一目标是把已有实现从镜像/token 测试升级为生产行为测试，不允许借测试任务夹带生产语义修复：

- 生产 QML/C++/Rust 文件默认只读。优先通过现有 public signal、真实 side effect、QSignalSpy、Wayland request spy、现有 fake dependency 和 QML file selector 下的 `+test` dependency 完成观察。
- 不得为测试向生产 QML 新增 property、function、第二入口或测试状态。确需 seam 时，只能使用 BUILD_TESTING/cfg(test)/friend test 可见机制，或测试文件选择器中的依赖替身；不得复制被测生产组件或业务状态机。
- 若真实测试暴露新的生产缺陷，或现有生产边界不可观察，当前任务立即 BLOCKED。必须记录根因，经用户授权后在当前测试任务之前插入独立的生产修复或可测试性任务，完整执行 RED、实现、独立审查、commit、push；不得在测试任务顺手修复。
- 每项都必须执行第 B.1 节负向控制，并保存旧提交/精确 mutation 证据。

---

### Task 14A：用真实生产 QML 验证媒体交互生命周期

优先级：测试门禁
仓库：父仓
唯一目标：替换或补强 Task 01A 的镜像测试，真实驱动生产 MediaControlButton 到唯一 setUserInteracting owner。

允许修改：

- tahoe-shell/tests/test_dynamic_island_media_interaction_lifecycle.py
- tahoe-shell/tests/tst_dynamic_island_media_interaction_lifecycle.qml（新增）
- tahoe-shell/tests/qml_imports 下复用或最小扩展现有 Quickshell fake
- tahoe-shell/components/+test/TahoeSymbol.qml

生产 `DynamicIslandMediaView.qml`、`DynamicIslandContent.qml`、`DynamicIslandOverlay.qml` 只读；不可观察时执行上述共用停止规则。

负向证明：在 disposable worktree 中以父仓 5339d70^ 为优先旧基线，或最小恢复“release/cancel/grab loss 不终止 interacting”的旧分支；同一真实 QML 测试必须因 `userInteracting` 残留而失败。

必须验证：

- press→release。
- press→move out/cancel。
- grab loss。
- disable while pressed。
- hide/collapse。
- destroy。
- duplicate terminal 幂等。
- disabled 不进入 interacting。

禁止：

- 在测试里复制 MediaControlButton。
- 用正则作为唯一行为断言。
- 为测试新增生产平行组件。

建议 commit：

~~~text
test(dynamic-island): run media interaction lifecycle in qml
~~~

---

### Task 14B：真实实例化生产 Overlay 验证媒体 hit testing

优先级：测试门禁
仓库：父仓
依赖：Task 14A COMPLETE
唯一目标：测试必须实例化 DynamicIslandOverlay 的真实 contentHost 和 capsule MouseArea，不得在 tst 文件复制 z-order。

允许修改：

- tahoe-shell/tests/test_dynamic_island_media_hit_testing.py
- tahoe-shell/tests/tst_dynamic_island_media_hit_testing.qml
- tahoe-shell/tests/qml_imports 下 Overlay 所需的最小现有模块 fake
- tahoe-shell/components/+test/TahoeSymbol.qml

生产 `DynamicIslandOverlay.qml`、`DynamicIslandContent.qml`、`DynamicIslandMediaView.qml` 只读；不可观察时执行共用停止规则，禁止复制生产层级。

负向证明：在 disposable worktree 中以父仓 ef036ad^ 为优先旧基线，或精确恢复外层 capsule 输入区遮挡媒体按钮的旧 z/hit-test 分支；同一测试必须出现按钮计数为零或 capsule 误触发。

必须验证：

- 三按钮各触发一次。
- capsule 不双触发。
- disabled 按钮吸收输入。
- 空白区域 click/swipe 保持。
- target screen mask/active state。
- remove production z 修复会让测试失败。

建议 commit：

~~~text
test(dynamic-island): exercise production overlay hit testing
~~~

---

### Task 15：真实 QML 验证通知滑动稳定 identity

优先级：测试门禁
仓库：父仓
唯一目标：真实实例化 NotificationToast，执行 A→外部删除→B 换绑→Timer 到期。

允许修改：

- tahoe-shell/tests/test_notification_swipe_stable_identity.py
- tahoe-shell/tests/tst_notification_swipe_stable_identity.qml（新增）
- tahoe-shell/tests/qml_imports 下 Notification/PanelWindow 所需最小 fake

生产 `NotificationToast.qml` 只读；不可观察时执行共用停止规则。

负向证明：在 disposable worktree 中以父仓 58254c2^ 为优先旧基线，或精确恢复 Timer 到期时读取已换绑 delegate 当前 ID 的旧分支；测试必须观察到 B 被错误 dismiss。

必须验证：

- Timer 只尝试 dismiss A。
- B 保留。
- 多通知连续滑动互不污染。
- snap-back 清 pending。
- 新手势 supersede 语义。
- dismissId 幂等。

禁止：

- 只测试 Python ToastCardModel。
- 复制 NotificationToast 内部状态机。

建议 commit：

~~~text
test(notifications): run swipe identity race in qml
~~~

---

### Task 16：真实 QML 验证 AppsSettings 权限 request identity

优先级：测试门禁
仓库：父仓
唯一目标：使用现有 fake Process registry 实例化生产 AppsSettings.qml，覆盖真实 signal 顺序。

允许修改：

- tahoe-shell/tests/test_apps_settings_permissions_identity.py
- tahoe-shell/tests/tst_apps_settings_permissions_identity.qml（新增）
- tahoe-shell/tests/qml_imports/Quickshell/Io 下现有 Process、StdioCollector、TestProcessRegistry fake

生产 `AppsSettings.qml` 只读；不可观察时执行共用停止规则，不得新增第二 permissions API。

负向证明：在 disposable worktree 中以父仓 417e8e4^ 为优先旧基线，或精确移除当前 generation/selected identity 检查；A 的晚到结果必须污染 B 并使测试失败。

必须验证：

- A success 晚到 B。
- A parse failure 晚到 B。
- A FailedToStart。
- A cancel。
- A→B→C latest-only。
- permissionsRefreshing 只由当前 generation 清理。
- sandbox fallback 不污染新 selection。

建议 commit：

~~~text
test(apps-settings): run permission identity races in qml
~~~

---

### Task 17：真实 QML 验证 TaskSwitcher release Timer 会话边界

优先级：测试门禁
仓库：父仓
唯一目标：真实 Qt Timer 中，旧会话 release→close→reopen 不确认新会话。

允许修改：

- tahoe-shell/tests/test_task_switcher_release_confirm_lifecycle.py
- tahoe-shell/tests/tst_task_switcher_release_confirm_lifecycle.qml（新增）
- tahoe-shell/tests/qml_imports 下窗口/键盘依赖的最小 fake

生产 `TaskSwitcher.qml` 只读；不可观察时执行共用停止规则。

负向证明：在 disposable worktree 中以父仓 b83e759^ 为优先旧基线，或精确恢复 close/reopen 时不停止旧 releaseConfirmTimer 的旧分支；旧 Timer 必须错误确认新会话。

必须验证：

- 40ms 内 close/reopen。
- normal modifier release。
- cancel。
- mouse selection。
- repeated open/close。

建议 commit：

~~~text
test(task-switcher): run release timer session race in qml
~~~

---

### Task 18：真实 QML 验证 ThumbnailProvider in-flight coalescing

优先级：测试门禁
仓库：父仓
唯一目标：实例化生产 ThumbnailProvider 与 fake Process，统计真实 capture 启动次数。

允许修改：

- tahoe-shell/tests/test_thumbnail_inflight_coalesce.py
- tahoe-shell/tests/tst_thumbnail_inflight_coalesce.qml（新增）
- tahoe-shell/tests/qml_imports/Quickshell/Io 下现有 Process registry fake

生产 `ThumbnailProvider.qml` 只读；不可观察时执行共用停止规则，不得新增 capture queue。

负向证明：在 disposable worktree 中以父仓 ad6e94e^ 为优先旧基线，或精确恢复 same/smaller non-force 也进入 pending 的旧分支；真实 capture 启动次数必须超出验收上限。

必须验证：

- same/smaller non-force：1 次。
- larger：最多追加 1 次。
- force：追加 1 次。
- multiple consumer 共享 state。
- failure 后 retry。
- window close 清理 active/pending。

建议 commit：

~~~text
test(thumbnails): exercise production capture coalescing
~~~

---

### Task 19：补齐 niri controller abnormal disconnect 与真实 damage 验证

优先级：测试门禁
仓库：niri 子仓，然后父仓 gitlink
唯一目标：补齐 Task 05 尚未覆盖的异常 client disconnect 和 output redraw/damage 行为。

允许修改：

- niri/src/tests/tahoe_glass.rs
- niri/src/tests/client.rs
- niri/src/tests/fixture.rs
- niri/src/tests/mod.rs
- niri/src/protocols/tahoe_glass.rs 和 niri/src/handlers/mod.rs 仅允许 cfg(test) 可观测点；如果真实测试证明生产缺陷，必须停止并把生产修复拆成新的前置任务，不能在测试任务顺手修复

负向证明：在 disposable niri worktree 中以 4a9f1f1a^ 为优先旧基线，或精确恢复 controller destroy 不清 committed owner 的旧分支；至少一个 disconnect/old-area damage 断言必须失败。

必须验证：

- abnormal client disconnect：controller 与 wl_surface 一同销毁，清理幂等且不访问 dead surface。
- explicit/abnormal controller gone while wl_surface remains alive：committed 状态立即清理。
- committed region old area damaged。
- output_for_root 存在时只 queue 对应 output。
- output 不可定位时 fallback queue all。
- destroy/destroyed 双调用幂等。

建议子仓 commit：

~~~text
test(tahoe-glass): cover disconnect and redraw lifecycle
~~~

建议父仓 commit：

~~~text
chore(niri): update glass lifecycle coverage
~~~

---

### Task 20：为 QuickShell fallback 建立真实 owner 行为测试

优先级：测试门禁
仓库：quickshell 子仓，然后父仓 gitlink
唯一目标：不再依赖父仓 Python token 测试，直接验证 `TahoeGlass::updateFallback/clearFallback` 这一 fallback adapter owner 如何按 materialAlpha 组合并清理现有 `BackgroundEffect.blurRegion` sink。

测试实现必须复用 Task 06/13 的 Tahoe glass C++ test target；不得为 fallback 再建独立 harness。

允许修改：

- quickshell/src/wayland/tahoe_glass/test 下的 fallback QtTest
- quickshell/src/wayland/tahoe_glass/test/CMakeLists.txt
- quickshell/src/wayland/tahoe_glass/CMakeLists.txt
- quickshell/src/wayland/tahoe_glass/qml.cpp/.hpp 仅允许 test seam；如果测试发现生产缺陷，必须停止并拆出前置生产修复任务

负向证明：在 disposable QuickShell worktree 中以 f73859d^ 为优先旧基线，或精确恢复 fallback 忽略 materialAlpha 的旧分支；alpha=0 时 `BackgroundEffect.blurRegion` 仍存在，测试必须失败。

必须验证：

- alpha 0 清 blurRegion。
- 最小正量化值、0.5、1 启用。
- multiple region any-positive。
- reverse to exact zero 同更新周期清理。
- protocol surface 出现时 clear fallback。
- protocol surface 消失时 fallback rebuild。
- 不新增 shader/strength API。

建议子仓 commit：

~~~text
test(tahoe-glass): exercise fallback alpha owner
~~~

建议父仓 commit：

~~~text
chore(quickshell): update glass fallback coverage
~~~

---

### Task 21：最终集成验收与可追溯完成报告

优先级：最终门禁
仓库：父仓
依赖：前 24 个原子任务 Task 00–06、07A、07B、08–11、12A、12B、13、14A、14B、15–20 全部远端 COMPLETE
唯一目标：运行最终验证矩阵，保存每项 commit、push、独立审查与剩余风险证据。

允许修改：

- 新增一份 docs 下最终 acceptance 报告。
- 不允许在本任务修改生产代码。

如果最终矩阵发现失败，Task 21 立即标记 BLOCKED；必须回到产生回归的原任务，按“重新实现/测试/新独立审查/新 commit/push”完整返工。不得在 Task 21 顺手修代码，也不得仅在 acceptance 报告中把失败解释为已知问题后继续完成。

必须记录：

- 前 24 个原子任务逐项记录；14A/14B、07A/07B、12A/12B 不得合并或遗漏。
- 每项 implementation commit hash；对子仓任务，必须另外逐项记录父仓 gitlink commit hash。
- remote/branch、commit 前与 push 前权威 remote tip、待推送 commit count=1、push 后 exact tip=HEAD。
- implementation staged diff 的 SHA-256、独立审查 session/round/APPROVE。
- 每个父仓 gitlink staged diff 自己的 SHA-256、独立审查 session/round/APPROVE；不得与子仓证据合并。
- 测试命令、退出码、通过数。
- Task 00–20 的 RED 负向控制命令、旧基线或 mutation diff、退出码和预期失败断言。
- 多屏、DND、reduced motion、fallback、rapid reverse 人工/自动验证。
- 当前三仓 git status。
- 父仓 gitlink 与远端子仓 commit 可达性。

acceptance 文件的持久化范围是“前 24 项完整证据 + Task 21 的最终矩阵与暂存前状态”。它不得自引用尚未产生的 Task 21 commit hash、push 结果或 push 后 clean 状态。Task 21 自身的 staged hash、独立审查和测试写入 commit trailers；commit hash、push/remote verification 与 push 后三仓 clean 状态由 H 阶段结束后的任务完成报告记录。不得为了回填这些自引用字段再创建第二个 acceptance commit。

最终测试最低要求：

~~~text
cd /home/wwt/niri
python3 -m pytest -q tahoe-shell/tests
git diff --check 422f41b..HEAD
git diff --check
git diff --cached --check
git status --short
test "$(git ls-remote --exit-code --heads origin refs/heads/main | cut -f1)" = "$(git rev-parse HEAD)"
test "$(git rev-parse HEAD:niri)" = "$(git -C niri rev-parse HEAD)"
test "$(git rev-parse HEAD:quickshell)" = "$(git -C quickshell rev-parse HEAD)"

cd /home/wwt/niri/niri
cargo test -q draw_clip --lib
cargo test -q tahoe_glass --lib -- --test-threads=1
cargo test -q edge_reveal --lib -- --test-threads=1
cargo test -q --lib -- --test-threads=1
rustup run nightly cargo fmt --all -- --check
git diff --check 7eaec605..HEAD
git diff --check
git diff --cached --check
git status --short
test "$(git ls-remote --exit-code --heads origin refs/heads/tahoe-layer-animations | cut -f1)" = "$(git rev-parse HEAD)"

cd /home/wwt/niri/quickshell
cmake --build build-tahoe -j2
cmake -S . -B build/tahoe-tests -G Ninja \
  -DBUILD_TESTING=ON \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_INSTALL_PREFIX=/home/wwt/.local
cmake --build build/tahoe-tests -j2
ctest --test-dir build/tahoe-tests -R '^tahoe-glass-tests$' \
  --no-tests=error --output-on-failure
ctest --test-dir build/tahoe-tests -R '^desktopentrymonitor$' \
  --no-tests=error --output-on-failure
ctest --test-dir build/tahoe-tests -R '^systemclock$' \
  --no-tests=error --output-on-failure
ctest --test-dir build/tahoe-tests --no-tests=error --output-on-failure
cmake -S . -B build/tahoe-asan-tests -G Ninja \
  -DBUILD_TESTING=ON \
  -DASAN=ON \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_INSTALL_PREFIX=/home/wwt/.local
cmake --build build/tahoe-asan-tests --target tahoe-glass-tests -j2
ctest --test-dir build/tahoe-asan-tests -R '^tahoe-glass-tests$' \
  --no-tests=error --output-on-failure
git diff --name-only -z f73859d..HEAD -- '*.cpp' '*.hpp' |
  xargs -0 -r clang-format -Werror --dry-run
git diff --check f73859d..HEAD
git diff --check
git diff --cached --check
git status --short
test "$(git ls-remote --exit-code --heads origin refs/heads/quickshell-tahoe-desktop | cut -f1)" = "$(git rev-parse HEAD)"
~~~

pytest 完整集合必须实际执行本路线图新增的 qmltestrunner 文件。CTest 必须列出并运行共享 `tahoe-glass-tests`（其中含 Task 06、13、20 的命名 cases）、`desktopentrymonitor` 和 `systemclock`；零测试不是通过。不得因为当前 shell 工作目录、BUILD_TESTING=OFF 或 filter 未匹配而把“未找到测试”当成通过。

Task 21 报告暂存前的父仓 `git status --short` 只允许出现该 acceptance 报告。其 staged diff 获批、commit、commit-patch hash 复核、push 和远端确认后，必须在任务完成报告中再次记录三仓 status，届时三仓均须 clean。

建议 commit：

~~~text
docs: record source audit remediation acceptance
~~~

该提交也必须独立审查、push 和远端确认。只有 Task 21 完成后，本路线图才允许标记 COMPLETE。

---

## 10. 每任务最终报告模板

~~~text
TASK STATUS: COMPLETE | BLOCKED | FAILED
TASK:
IMPLEMENTATION REPOSITORY:
BASELINE HEAD/STATUS:
ROOT CAUSE:
AUTHORITATIVE OWNER:
FIX:
ANTI-CORRUPTION CHECK:
FILES CHANGED:
TESTS ADDED/UPDATED:
NEGATIVE CONTROL BASE/MUTATION:
NEGATIVE CONTROL COMMAND/EXPECTED FAILURE/RESULT:
VALIDATION COMMANDS AND RESULTS:
IMPLEMENTATION STAGED DIFF SHA-256:
IMPLEMENTATION REVIEW VERDICT/ROUND:
IMPLEMENTATION REVIEW AGENT/SESSION:
IMPLEMENTATION COMMIT HASH:
IMPLEMENTATION PRE-COMMIT/PRE-PUSH REMOTE TIP AND OUTGOING COUNT:
IMPLEMENTATION PUSH REMOTE/BRANCH:
IMPLEMENTATION POST-PUSH EXACT REMOTE TIP:
PARENT GITLINK STAGED DIFF SHA-256（子仓任务）:
PARENT GITLINK REVIEW VERDICT/ROUND（子仓任务）:
PARENT GITLINK REVIEW AGENT/SESSION（子仓任务）:
PARENT GITLINK COMMIT HASH（子仓任务）:
PARENT GITLINK PRE-COMMIT/PRE-PUSH REMOTE TIP AND OUTGOING COUNT（子仓任务）:
PARENT GITLINK PUSH REMOTE/BRANCH（子仓任务）:
PARENT GITLINK POST-PUSH EXACT REMOTE TIP（子仓任务）:
REMAINING RISKS:
OUT-OF-SCOPE FINDINGS:
~~~

---

## 11. 停止条件

出现以下任一情况必须停止当前任务并报告，不得开始下一任务：

- 无法区分用户原有改动与当前任务改动。
- 需要修改未授权公开协议、配置格式或用户可见语义。
- 需要新增平行 Process、Timer、queue、model 或 API 才能继续。
- 真实测试暴露架构决策而非局部缺陷。
- 无关测试失败且无法证明来源。
- 独立审查 REQUEST_CHANGES。
- commit hook 修改了文件但尚未重新测试和审查。
- push、认证、网络或远端验证失败。
- 子仓 commit 尚未推送却准备提交父仓 gitlink。
- staged SHA-256 与 APPROVE 输入不一致。

BLOCKED 不是允许跳过任务的状态。阻塞解除后仍从该任务继续。

---

## 12. 整体完成定义

只有同时满足以下条件，整个修复路线图才算完成：

1. 第 5.0 节文档启用门禁已经独立审查、commit、push、远端确认，执行基线已更新。
2. 25 个原子任务 Task 00–06、Task 07A、Task 07B、Task 08–11、Task 12A、Task 12B、Task 13、Task 14A、Task 14B、Task 15–21 全部按顺序完成。
3. 每个任务都有独立、可回滚 commit。
4. 每个任务 commit 均普通 push 并完成远端确认。
5. 每个任务最终 staged diff 均由未参与实现的独立子代理 APPROVE。
6. Task 00–20 都有旧实现或精确 mutation 的 RED 证据，以及修复后的 GREEN 证据。
7. 任何返工都重新测试、重新计算 hash、重新独立审查。
8. 子仓任务的子仓 commit 和父仓 gitlink commit 均有各自完整的 hash/review/commit/push/remote verification 证据，且均已推送可达。
9. 没有平行接口、双状态、双刷新路径或兼容旁路。
10. 异步/Timer/输入/协议问题均有生产行为级测试。
11. 完整 Tahoe 测试、niri 全量 lib 与相关测试、QuickShell Release 构建和 BUILD_TESTING CTest 全部通过。
12. 最终 acceptance 文件包含前 24 项全部 commit/review/RED-GREEN test/push 证据及 Task 21 最终矩阵；Task 21 自身证据由 commit trailers、远端可达 commit 和 push 后任务完成报告闭合，不产生自引用的第二提交。
13. 用户已有改动没有被丢弃或混入无关提交。
14. 当前父仓和两个子仓工作区 clean；通过实时 `ls-remote` 证明每个本地 HEAD 与目标远端 branch tip OID 精确一致，父仓 gitlink 也精确等于对应子仓 HEAD。

在以上条件全部满足之前，执行者不得输出“全部任务已完成”。
