# Tahoe Desktop 代码审计核验结论

日期: 2026-07-27

## 一、核验范围与基线

本报告对原代码审计中的安全、稳定性、性能、动画和 UX 断言逐项进行了源码可达性核查。原始四份报告已由本报告替代。

核验基线:

- 主仓库: `42039bb`
- niri: `0faa78bd1516110ec1c35eddb9e1558dc6cd0a12`
- quickshell: `e8c1acbde4535379bc061cfc9d508942283b045a`
- tahoe-shell: 主仓库当前工作树

核验方法:

- 对高严重度问题追踪了合法输入到故障点的完整调用链。
- 对性能问题复算了复杂度、调用次数和渲染操作，但没有用静态结构替代 profiling 数据。
- 对动画和 UX 问题区分了实现缺陷、能力缺口、明确接受的设计取舍和主观体验偏好。
- 对争议结论进行了独立复核，并按精确源码位置抽查。

本次没有进行 GPU/CPU profiling、VMware 实机复现、长时间运行测试或模糊测试。因此，相关条目只确认代码结构或风险，不声明实际发生频率。

结论分类:

- **确认缺陷**: 当前代码存在可达的错误实现或明确错误行为。
- **部分确认**: 代码事实成立，但影响、严重度或原报告中的因果关系被夸大。
- **设计取舍/能力缺口**: 行为真实，但不是实现偏离当前设计。
- **不成立/已过时**: 调用链反证、已有保护机制或当前实现已经推翻原断言。
- **待实测**: 静态分析不足以判断实际性能或视觉影响。

## 二、确认的安全与内存安全问题

### F-01 Quickshell Color IPC 存储类型错误

严重度: 高  
置信度: 高

文件: `quickshell/src/io/ipc.cpp:20-23,158-177`、`quickshell/src/io/ipchandler.cpp:69-88,129-131,213-229`

`ColorIpcType::size()` 返回 `sizeof(QColor)`，但 `createStorage()` 分配 `new bool()`，`destroyStorage()` 也按 `bool*` 删除。`QColor` 已被注册为公开支持的 IPC 类型。

合法可达路径:

- color 返回值: Qt 元调用把 `QColor` 写入仅按 `bool` 分配的返回槽。
- color 属性读取: `copyStorage()` 按 `sizeof(QColor)` 向该槽执行 `memcpy`。
- color 参数: `fromString()` 分配 `new QColor`，槽析构时却执行错误类型的 `delete bool*`。

结论: 这是确定的堆越界/对象生命周期未定义行为。具体崩溃位置和可利用性尚未验证，但不依赖非法 QML 声明或畸形协议输入。

### F-02 诊断报告未经确认自动推送

严重度: 高  
置信度: 高

文件: `scripts/diagnose-quickshell-crash.sh:9-14,45-71,161-170`

脚本收集 hostname、用户名、仓库状态、二进制路径、软件包版本和会话显示变量，然后无交互确认地执行 `git add`、`git commit` 和 `git push origin main`。核查当天，脚本写死的 GitHub 目标可匿名访问。

结论: 信息收集和自动外发行为真实。实际泄露范围还取决于报告内容、远端权限和执行用户凭据，但当前脚本没有最小化、脱敏或确认步骤。

### F-03 固定 `/tmp` 日志文件可跟随符号链接

严重度: 中  
置信度: 高

文件: `scripts/diagnose-tray-launcher.sh:20-22,44`

脚本使用固定路径 `/tmp/qs-hover-diag.txt` 和 `/tmp/qs-hover.log`，并通过 `: > "$file"` 截断。若路径已被替换为符号链接，可截断执行用户有权限写入的目标文件。

`tools/mrid6_dump_wmi_acpi.sh` 的固定目录是另一类问题: 末端 symlink 不会被 `rm -rf` 递归跟随，但删除和重新创建之间仍有 TOCTOU 窗口。它不应与上述直接截断问题混为一谈。

## 三、确认的正确性与稳定性问题

### F-04 Crash handler 的 partial-write 循环错误

严重度: 中  
置信度: 高

文件: `quickshell/src/crash/handler.cpp:73-84`

循环维护了 `wptr` 和 `end`，但每次仍调用 `write(fd, &frame, sizeof(frame))`，没有从 `wptr` 写入剩余长度。发生 partial write 后会重复帧前缀，并可能让 `wptr` 越过 `end`，导致损坏的 crash trace 或持续写入直到失败。

边界: trace fd 是 memfd，小型常规文件写入通常可能一次完成。因此实现错误确定存在，但不能表述成每次崩溃都必然触发。

### F-05 Genie 反转时速度被硬重置为零

严重度: 中  
置信度: 高

文件: `niri/src/layout/minimize_window_animation.rs:274-333`

`reverse_to_restore()` 和 `reverse_to_minimize()` 保持了位置连续，但共同调用的 `restart_progress()` 始终执行 `restarted(..., 0.)`。上层 API 没有传入当前速度的入口。

当前 Tahoe 配置的 minimize/restore 分别为 cubic-bezier 和 linear，因此这里首先表现为曲线导数不连续。若用户配置 spring，非零速度或过冲阶段的突变会更明显。视觉严重度仍需录帧验证。

### F-06 多键绑定的重复计时器互相干扰

严重度: 中  
置信度: 高

文件: `niri/src/input/mod.rs:404-415`

当前实现只有一个 repeat timer。多个可重复绑定同时按住时，释放任意一个都会 `take()` 该 timer，从而错误停止另一个仍按住按键的重复。源码注释已明确记录这个边缘行为。

### F-07 混合缩放下平板边缘 clamp 使用错误输出缩放

严重度: 低  
置信度: 高

文件: `niri/src/input/mod.rs:335-344`

统一平板模式用第一个枚举输出的 scale 计算 1px clamp，而不是使用平板位置所在或最接近的输出。混合缩放、多显示器边缘位置可能因此计算错误。

### F-08 Pointer constraint 使用可能过期的 surface 全局原点

严重度: 低  
置信度: 高

文件: `niri/src/input/mod.rs:2484-2505,2613-2625`

约束检查和 confinement 使用缓存的 `pointer_contents.surface` 位置。同一 surface 在约束期间移动后，全局原点可能已经过期。这里的风险是 stale origin，不是任意失效 surface 焦点。

### F-09 硬编码机器路径

严重度: 低  
置信度: 高

文件: `scripts/check-tahoe-glass-guardrails.sh:163-175`

脚本硬编码 `/home/wwt/.cache/tahoe-liquid-glass-refs/...`，使 guardrail 检查依赖特定用户和本机缓存布局。这是确定的可移植性问题，不是安全漏洞。

## 四、确认的 UX 与无障碍问题

### F-10 TopBar 本身没有键盘焦点模型

严重度: 高  
置信度: 高

文件: `tahoe-shell/components/TopBar.qml`

TopBar 没有 `Keys`、`KeyNavigation`、焦点获取或焦点指示器，主要入口均由 `MouseArea.onClicked` 驱动。因此 TopBar UI 本身无法通过 Tab/方向键操作。

边界: Control Center、Wi-Fi 等部分 popup 可通过 shell IPC 或外部快捷键间接打开。这不等于 TopBar 已具备键盘导航，托盘等入口仍没有等价覆盖。

### F-11 ControlCenter 缺少面板级 Escape 关闭

严重度: 中  
置信度: 高

文件: `tahoe-shell/components/ControlCenter.qml:141-159,1166-1180`

ControlCenter 没有根级焦点捕获或 Escape 关闭处理。文件中唯一 Escape handler 位于 Wi-Fi 密码输入行，只用于收起该行，不能关闭面板。

### F-12 亮度不可用时没有错误解释

严重度: 低  
置信度: 高

文件: `tahoe-shell/components/ControlCenter.qml:316-331`、`tahoe-shell/services/Controls.qml:255,312,1796`

服务维护了 `brightnessErrorText`，但可见 UI 没有绑定它。无背光或 VM 环境中，用户只会看到禁用的滑块。

### F-13 Popup dismiss surface 会丢弃滚轮和右键

严重度: 低  
置信度: 中高

文件: `tahoe-shell/components/PopupDismissLayer.qml:23-76`

全屏 input region 覆盖 popup 外区域，只有默认左键 `MouseArea.onClicked` 被处理。滚轮和右键落到该 surface 后没有反馈，也不会到达底层应用。

原报告称键盘也会被吞是错误的: 该 surface 设置了 `focusable: false`，不会取得键盘焦点。

## 五、确认的设计取舍与能力缺口

以下行为真实，但不能直接按漏洞处理:

- Tahoe glass 和 Genie 协议没有 compositor 到 shell 的动画完成事件，因此无法跨进程精确编排完成后动作。Dock 是否应在最小化落地时 bounce 属于产品决策。
- Launchpad surface 入场为 340ms，壁纸 dim 为 400ms，结束时间相差 60ms。这是不同动画所有者的明确策略。
- layer 关闭使用内容快照，快速关闭时会冻结半程内容。允许的 Tahoe glass close effect 可继续 live render，因此不是整个玻璃效果都被冻结。
- Launchpad 打开期间切换 live/static wallpaper 会产生已记录的 dim 瞬态。
- compositor/TahoeGlass 协议失效时，Dock 会切回 legacy QML 路径并可能 pop。普通工作区切换不会自动触发该条件。
- VMware/software renderer 的 spring 纹理问题在源码注释中有历史依据，并提供手动 `useSpring: false` 降级；当前没有自动 renderer 检测。是否仍在所有相关环境复现需实机验证。
- 禁用 compositor layer animations 后没有 QML fallback 是动画所有权策略，而不是遗漏的 fallback 实现。
- 全屏状态出现时 shell 会关闭多个 popup/navigation surface。它们仍有 compositor 关闭动画；Spotlight 和 Launchpad 查询会被清空，ControlCenter 滑块则是实时提交，不应笼统称为全部数据丢失。
- Dynamic Island 在 focused window、focused output 和 active workspace output 都为空时回退到枚举的第一个输出。这是窄窗口下的既定 fallback，不是关闭最后一个窗口时必然跳屏。

## 六、性能结构事实与待实测项

### P-01 全输出重绘扇出

结论: 部分确认，需 profiling 定级。

`Niri::queue_redraw_all()` 会 queue 每个输出。光标 surface commit、DnD icon commit 和大量输入操作仍使用此路径。当前 `niri/src/input/mod.rs` 有 127 个 `queue_redraw_all()` 匹配点，不是原报告的 97 个。

重绘路径会重新收集 render elements 并调用 backend，damage tracker 只能在此后判断 `NoDamage`。但这不等于从零实例化完整场景树；实际 CPU、功耗和混合刷新率影响必须测量。

### P-02 Blur 与 Tahoe glass 区域成本

结论: 结构确认，严重度待实测。

- 3-pass Kawase 金字塔执行 3 次 down draw 和 3 次 up draw。
- 以源 capture 面积 A 计算，金字塔写入约 `1.640625A`；加初始 capture blit 约 `2.640625A`。
- 每个 glass region 持有独立 `BackgroundEffect`；协议上限为每 surface 32 个 region。
- 32 个 region 每帧全部重捕获只是理论上限，实际取决于可见性、区域面积、damage 和 cache 命中。
- shader 中法线、折射和高光路径包含多次 noise/pow，实际 GPU 成本需 profile。

### P-03 Live blur cache 失效

结论: 部分确认。

物理 capture band 改变 1px 会使 capture key 失效；进入和退出 animation downsample tier 也会各触发一次重捕获。但“spring 动画每帧都 miss”过强: 只有 rounded physical band 实际变化的帧才会 miss，低速尾段可能连续命中。

### P-04 QML/C++ 热路径

结论: 结构事实存在，影响待 profiling。

- Dynamic Island 的 spring driver、mask、glass region 和内容进度形成较宽绑定链；不能仅按属性数量断言 binding storm。
- `Wallpaper.qml` 每 5 秒通过 `FileView.reload()` 和 `waitForJob()` 同步读取短小 `/proc/<pid>/stat`，存在 UI 线程同步等待结构，但实际停顿可能很小。
- Notification 和 media Loader 使用 `asynchronous: false`，激活时同步实例化。
- Tahoe glass ancestor tracking 每层约有 11 个 QObject signal connection 和一个 matrix listener。
- polish 同时构建 logical/surface region；item 路径最多产生 8 次 `mapToScene`/region，而不是原报告的 4 次。Move/Resize 更新会被 `schedulePolish()` 合并。
- Windowset commit 会遍历全部 windowset/projection，但原报告没有证明 workspace 动画期间的 commit 频率。
- `ToplevelManager::forImpl()` 是 O(n)，但当前 tahoe-shell 未找到循环读取 `Toplevel.parent` 的消费者，不能据此列为现实 O(n^2) 热点。

现有静态证据不足以支持原性能排名。

## 七、不成立或已经过时的结论

### 7.1 崩溃与安全误报

- **热拔输出必然触发 `monitor_for_output().unwrap()` panic**: 不成立。典型 lookup 由同一 layout 不变量保护，输出移除在串行事件循环中同步完成；已有 removed-output 请求回归测试。仍可补充热拔与残留 grab/vblank 的组合测试，但当前没有 TOCTOU 调用链。
- **恶意 PipeWire 客户端可令 `n_datas == 0` 并触发 assert**: 未证实。buffer 由 `StreamFlags::ALLOC_BUFFERS` 和 PipeWire daemon/library 协商，普通 consumer 没有直接写该字段的源码路径。应归为对库/daemon 不变量使用 assert 的稳定性问题。
- **focus_grab 的 `qobject_cast` 是可达空指针漏洞**: 不成立。唯一 signal connection 的 sender 明确为 `ProxyWindowBase`，发射信号时 backing window 已存在。
- **Wayland u32 时间戳在 49.7 天回绕是 bug**: 不成立。Wayland 输入时间字段本来就是 32-bit 毫秒值，客户端按模 `2^32` 处理差值。
- **`env::set_var` 已存在 Rust 数据竞争**: 未证实。当前 crate 使用 edition 2021，CursorManager 也不是跨线程对象；这是未来 Rust 2024 迁移和进程全局环境修改风险。

### 7.2 性能误报

- **Dock `computeSectionWave()` 是 O(n^2)**: 错误。`restToPacked()` 虽为 O(n)，但每次 wave 只调用一次；其余循环顺序执行，整体为 O(n)。指针移动时运行 UI-thread JS 的事实仍成立。
- **ScriptModel/Repeater 在列表变化时重建全部 delegate**: 错误。ScriptModel 正是为增量 insert/remove/move 设计；只有真正新增/删除的 delegate 发生变化。Repeater 不虚拟化、所有现存项常驻内存是另一问题。
- **每次模型变化产生数百对象完整 churn**: 没有当前实现证据。
- **Toplevel parent lookup 已在 shell 中形成 O(n^2)**: 未找到现实消费者，只是理论复杂度。

### 7.3 动画误报

- **关闭事务可能因无响应客户端无限 Pending**: 正常路径不成立。`Transaction` 有 300ms deadline，主要提交路径会注册 timer。
- **通知 FIFO 必然出现“消失 -> 空白 -> 出现”**: 不成立。旧状态清理和下一个通知展示在同一 JS 调用栈完成，scene host 还有 hold/fade 机制。连续通知内容未使用两个 notification delegate 做 A/B crossfade，但没有静态证据支持空白帧。
- **Dynamic Island spring 原始过冲导致 QML capsule 和 compositor glass region 分离**: 已过时。视觉尺寸先 clamp，协议 region 从同一 clamped geometry 派生并做受控量化。
- **workspace resize snap 阈值为 5px**: 错误，当前为 10px。
- **动画进行时输出热拔特异性地触发 compositor panic**: 没有专属调用链证据。

### 7.4 UX 与功能误报

- **TopBar 所有功能完全无法由键盘触达**: 过强。TopBar UI 无键盘导航成立，但若干 popup 有 IPC 入口。
- **PopupDismissLayer 吞掉键盘**: 错误，surface 不获取键盘焦点。
- **正常 popup 入口的互斥是单向的**: 不成立。鼠标、IPC 和 tray 标准入口都先调用统一 `closeTopBarPopups(except)`；Wi-Fi handler 是额外防护。
- **Dock 自动隐藏因 magnification headroom 残留可见条纹**: 错误。headroom 是透明绘制/命中空间，实际 84px shelf 会完整移出屏幕。
- **普通工作区切换会让 Dock 协议不可用**: 没有证据；协议/合成器重启才是已知切换条件。
- **网络和蓝牙错误文本从未显示**: 已过时。Settings 的 Wi-Fi/Bluetooth 页面会显示详细错误；ControlCenter compact module 不显示。
- **MPRIS 无播放器按钮仍表现为可操作**: 不构成明确 bug。按钮有低 opacity、能力 guard 和禁用光标语义，点击无副作用。
- **概览第二根手指总会切换浮动模式**: 错误，只在当前 gesture 为 `InteractiveMove` 时发生。缺少 pinch/two-finger/three-finger 是新增交互能力需求，不是现有规则的实现错误。
- **Orca 修饰键泄漏当前必然要求再次按 Shift**: 过时。当前代码会转发被 a11y 消费的 modifier release，覆盖最常见路径；罕见 race 和独立 XKB state 技术债仍可继续测试。
- **大量 shell 组件和服务零测试**: 已过时。TopBar、SettingsPanel、Popup、ControlCenter、FanControl、SystemStats、shell 协调和启动/部署逻辑已有不同程度的测试。许多测试只是源码合同检查，行为级覆盖仍不充分，但不能称零测试。
- **截图、Dock 重排和 pin/unpin 均缺失**: 历史结论已过时。截图、Dock 内重排和 pin/unpin 已实现。未找到的仍包括录屏、Quick Look、per-app badge 和 Launchpad 到 Dock 的跨 surface 拖拽固定。

## 八、统计复核

原报告的数量口径没有定义，且当前值不准确:

| 指标 | 当前复核值 | 说明 |
|---|---:|---|
| niri `.unwrap()`/`.expect()` | 1285 匹配行 / 109 文件 | 包含测试；不是调用表达式或漏洞数 |
| niri TODO/FIXME/HACK | 241 行 / 42 文件 | 代码债指标，不等于缺陷数 |
| `input/mod.rs` `queue_redraw_all()` | 127 处 | 包含键盘、指针、触摸、手势等多类路径 |
| tahoe-shell 空 catch | 69 行 / 9 文件 | 是否应记录错误需逐处判断 |
| tahoe-shell `property var` | 523 行 / 153 文件 | 降低类型信息，但 QML 绑定错误并非必然静默 |

超大 QML 文件、git 依赖、双日志框架、无条件编译 Tahoe 模块、RPM/DEB 硬依赖、session-lock 私有布局 hack 和 `delete this` 模式均是有效的维护性观察，但原审计没有证明它们当前导致安全或用户可见故障。

## 九、最终优先级

建议按证据和影响排序，而不是沿用原四份报告的排名:

1. 修复 Color IPC 的分配、复制和销毁类型错误，并增加 color 参数/返回值/属性测试。
2. 移除诊断脚本的自动 push 默认行为，对报告内容脱敏并使用明确确认。
3. 将固定 `/tmp` 文件和目录改为安全临时文件机制。
4. 修复 crash handler 的剩余长度写入循环。
5. 处理 Genie 反转速度连续性和 niri 多键 repeat 状态模型。
6. 补齐 TopBar 键盘导航、ControlCenter Escape 和亮度错误反馈。
7. 为混合缩放 tablet clamp、移动 surface pointer constraint、热拔残留 grab/vblank 增加回归场景。
8. 在任何性能重构前先采集多显示器 redraw、glass region miss、QML binding 和 Loader 激活的 profile。

除上述确认项外，其余问题不应在缺少复现、trace、profile 或明确产品需求的情况下继续以“高危漏洞”名义跟踪。
