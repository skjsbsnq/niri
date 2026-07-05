# Tahoe/niri 日用桌面改进路线图（已废弃）

日期：2026-06-25  
目标：把当前 Tahoe Shell + niri fork 继续推进到稳定日用桌面。对标对象是 macOS 与 Windows 11 的键鼠桌面体验。  
本轮不做：输入法重构、截图/录屏重构、触摸屏、触控手势、多显示器高级工作流。

这份文档优先相信源码。旧文档只作为背景，不作为事实来源。

> 废弃状态（2026-06-25）：本路线图已归档废弃，不再作为后续执行依据。
>
> - 阶段 1：已完成，保留当前实现与验收记录。验收文档：`tahoe-shell/docs/dock-minimized-shelf-acceptance-2026-06-25.md`。
> - 阶段 2 至阶段 8：全部取消，不再执行。
> - 下文仅保留为历史记录；除阶段 1 的完成状态外，所有待办、执行顺序、必须实现和完成标准均已作废。

## 1. 结论先行

当前项目已经有真实桌面骨架，不是纯 UI demo：

- niri IPC 有事件流和完整窗口状态，窗口包含 `is_minimized`、`layout`、`focus_timestamp` 等字段。
- Tahoe Shell 已经使用 `niri msg --json event-stream` 维护窗口模型。
- Dock 已有固定应用、运行窗口、拖拽重排、文件 drop、Downloads、Trash、自动隐藏、右键窗口菜单。
- 通知、控制中心、托盘、Search、设置面板都有可用实现。

真正影响“日用”的短板按优先级排序如下：

1. Dock 没有 macOS 风格的最小化窗口缩略栏。
2. 锁屏、空闲、熄屏、睡眠恢复入口不统一。
3. 窗口总览没有真实缩略图，只是几何小地图。
4. XWayland、legacy tray、GLX、X11/Wayland 剪贴板兼容依赖本地补丁链，缺固定回归。
5. Search 还不是全局搜索，缺最近文档、文件名搜索和最近项目。
6. 设置面板仍有大量外部跳转，缺统一后端。
7. AppMenu 和托盘菜单还不够完整，尤其是 nested menu 和异常隔离。

历史计划曾要求严格串行执行。该执行要求现已废弃：阶段 1 已完成，阶段 2 至阶段 8 全部取消。

## 2. 工程约束

### 2.1 KISS

- 每个阶段只解决一个主要问题。
- 优先复用现有 niri IPC、Quickshell service、QML component。
- 不为了“看起来完整”引入大框架。
- 不在 QML 里继续堆复杂 shell 字符串。超过一次复用的命令要进 service/helper。
- 不能为了新功能重写 Dock、Windows service 或 Settings panel。

### 2.2 防腐化

- 窗口状态以 niri IPC 为权威。Quickshell toplevel 只能做降级补充。
- 用户路径和已有行为默认不变。需要改变时必须有迁移和回滚策略。
- 新状态文件必须有版本号、坏文件回退、写入失败处理。
- 新增长期进程必须有健康检查或 systemd/user 管理。
- 每个阶段都必须有回归清单，不允许“新功能好了，旧功能坏了”。

### 2.3 验收文档

每完成一个阶段，新增：

```text
tahoe-shell/docs/<stage-name>-acceptance-YYYY-MM-DD.md
```

验收文档必须包含：

- 修改范围。
- 关键文件。
- 用户可见变化。
- 保留的旧行为。
- 手动验证步骤。
- 自动验证命令。
- 已知风险。
- 明确不做的内容。

## 3. 严格串行阶段（历史记录，已废弃）

## 阶段 1：Dock 最小化窗口缩略栏（已完成）

### 目标

实现 macOS 风格 Dock 右侧最小化窗口缩略栏。

当前 Dock 右侧只有 Downloads 和 Trash。最小化窗口仍在普通运行窗口区里，只通过灰色图标和短指示条表达。这不符合 macOS 的 Dock 语义。

目标结构：

```text
固定应用 | 非最小化运行窗口 | 最小化窗口缩略栏 | Downloads | Trash
```

### 必须实现

- `Windows.qml` 暴露 `nonMinimizedWindowList` 和 `minimizedWindowList`。
- 普通运行窗口区默认只显示非最小化窗口。
- 新增 Dock 最小化 shelf。
- shelf 只显示 `isMinimized === true` 的窗口。
- 每个最小化窗口显示真实窗口缩略图，不只是 app icon。
- 缩略图角落叠加 app icon。
- 点击缩略图恢复窗口。
- 右键缩略图复用现有 `DockWindowMenu`。
- 关闭窗口后缩略图立即消失。
- 多个最小化窗口可横向滚动或压缩，不挤掉 Downloads/Trash。

### 推荐实现

QML 层新增：

- `components/DockMinimizedShelf.qml`
- `components/DockMinimizedWindow.qml`

修改：

- `services/Windows.qml`
- `components/Dock.qml`
- 必要时小改 `components/DockWindowMenu.qml`

缩略图来源不要走用户截图功能。不要改 `Screenshot.qml`，不要改 Print keybind，不能污染用户图片目录。

推荐在 niri 侧提供私有 thumbnail 能力：

```text
niri msg --json window-thumbnail --id <window-id> --path <runtime-path> --max-width 320 --max-height 220
```

输出写到：

```text
$XDG_RUNTIME_DIR/tahoe/window-thumbnails/
```

这属于 Dock/window preview 内部能力，不属于截图录屏功能。

### 局部重构边界

允许：

- 把 Dock 宽度预算拆成更清晰的 helper。
- 把窗口列表过滤逻辑收敛到 `Windows.qml`。
- 给 niri 增加最小 thumbnail IPC/action。

禁止：

- 重写整个 Dock。
- 改 pinned apps state 格式。
- 改截图/录屏路径。
- 引入 grim/slurp/wf-recorder 生成缩略图。
- 让最小化窗口在普通窗口区和缩略栏重复出现，除非有明确兼容开关。

### 回归清单

必须验证：

- 固定应用仍可启动。
- 固定应用仍可拖拽重排。
- 文件仍可拖到 Dock app 打开。
- Downloads 仍可打开。
- Trash 仍可打开，文件仍可拖入回收站。
- Dock 自动隐藏仍可用。
- 普通窗口右键菜单仍可用。
- 最小化窗口点击缩略图可恢复。
- 多个同 app 窗口各有独立缩略图。
- 缩略图生成失败时显示 fallback 卡片，Dock 不崩。

### 完成标准

阶段 1 不以“占位卡片”算完成。必须有真实窗口缩略图。

完成后写 `dock-minimized-shelf-acceptance-YYYY-MM-DD.md`。

## 阶段 2：锁屏、空闲、熄屏、睡眠统一（已取消，不做）

### 目标

所有锁屏入口统一到 Tahoe LockScreen，形成可信的空闲和睡眠生命周期。

### 当前问题

- Shell 有 `LockScreen.qml`，但配置里的锁屏快捷键仍然可以走外部锁屏路径。
- 电源菜单、快捷键、idle 自动锁之间不是一个统一入口。
- 没有明确的“睡眠前锁屏、恢复后仍锁定”验收链。

### 必须实现

- `Super+Alt+L` 进入 Tahoe LockScreen。
- 电源菜单锁屏和快捷键锁屏使用同一 action。
- idle timeout 后自动锁屏。
- 锁屏后一段时间熄屏。
- 睡眠前确保锁定。
- 恢复后必须仍然锁定。
- Shell 不在线时 fallback 可诊断。

### 推荐实现

新增一个小的会话 idle helper，不把 idle 逻辑散落到多个地方：

```text
scripts/tahoe-idle-session.sh
```

职责只包括：

- timeout N：调用 Tahoe shell IPC lock。
- timeout M：调用 `niri msg action power-off-monitors`。
- resume：恢复显示或等待输入恢复。

健康页增加：

- Tahoe shell lock IPC 是否可用。
- idle helper 是否运行。
- fallback 锁屏路径。

### 禁止

- 重写锁屏 UI。
- 同时引入多个 idle daemon。
- 锁屏失败时静默继续睡眠。
- 把 `swaylock` 作为主路径保留。

### 完成标准

- 快捷键、电源菜单、idle 都进入同一锁屏体验。
- 睡眠恢复后不能看到未锁桌面。
- 有手动验证步骤和健康页状态。

完成后写 `lock-idle-lifecycle-acceptance-YYYY-MM-DD.md`。

## 阶段 3：窗口总览真实缩略图（已取消，不做）

### 目标

把 Window Overview 从几何小地图升级为真实窗口缩略图。

### 当前问题

`WindowOverview.qml` 目前用 window geometry 画矩形。它能表达窗口位置，但不能让用户像 Mission Control / Task View 一样靠内容找窗口。

### 必须实现

- 总览卡片显示真实窗口缩略图。
- 最小化窗口也有缩略图。
- 缩略图缺失时有 fallback。
- 点击非最小化窗口激活。
- 点击最小化窗口恢复。
- 键盘选择仍可用。

### 推荐实现

复用阶段 1 的 thumbnail provider，不做第二套截图/抓图。

总览打开时批量请求缩略图，但要有限流：

- 同时最多 N 个请求。
- 已有缓存先显示。
- 窗口关闭后清理缓存。

### 禁止

- 为 Overview 新增另一套 thumbnail provider。
- 打开总览时同步阻塞 UI。
- 把失败的缩略图无限重试。

### 完成标准

- 10 个窗口以内打开总览不卡顿。
- 缩略图能稳定识别窗口内容。
- 失败 fallback 不影响使用。

完成后写 `window-overview-thumbnails-acceptance-YYYY-MM-DD.md`。

## 阶段 4：兼容性回归矩阵（已取消，不做）

### 目标

把 XWayland、legacy tray、GLX、X11/Wayland 剪贴板从“靠经验修”变成“可重复检查”。

### 当前问题

项目已经维护 patched `xwayland-satellite` 和 glamor wrapper，但日用兼容性仍依赖很多隐式条件：

- satellite 版本。
- local patch 是否应用。
- wrapper 是否生效。
- GLX vendor 是否正确。
- legacy tray bridge 是否运行。
- X11/Wayland 剪贴板桥接是否正常。

### 必须实现

新增诊断脚本：

```text
scripts/check-desktop-compat.sh
```

检测：

- `xwayland-satellite` 是否运行。
- 运行中的 binary 是否是当前部署版本。
- wrapper 是否包含 glamor。
- GLX 是否硬件渲染。
- X11 -> Wayland 剪贴板。
- Wayland -> X11 剪贴板。
- `xembedsniproxy` 是否可用。
- niri IPC 是否可用。

健康页读取或触发该诊断，并展示结果。

### 禁止

- 自动杀用户 X11 应用。
- 自动替换用户显卡环境。
- 把长 shell 检测复制进 QML。

### 完成标准

- 诊断脚本可以独立运行。
- 健康页能展示关键状态。
- 每个失败项都有明确影响和建议。

完成后写 `desktop-compat-checks-acceptance-YYYY-MM-DD.md`。

## 阶段 5：Search 补齐最近项目和文件名搜索（已取消，不做）

### 目标

让 Search 从“应用启动器 + 设置入口”升级为日用全局搜索。

### 当前问题

现有 Search provider 有：

- 应用。
- 设置。
- 计算器。
- 命令。
- 截图动作。

缺：

- 最近文档。
- 最近下载。
- 文件名搜索。

### 必须实现

先最近项目，后文件名搜索。

第一步：

- 最近文档。
- 最近下载。
- 最近打开文件。
- 激活走 `xdg-open`。

第二步：

- 文件名搜索。
- 默认只搜 Desktop、Documents、Downloads、Pictures。
- 有超时。
- 有数量上限。
- 不扫整个 home。

### 推荐结构

新增：

- `services/RecentFiles.qml` 或 helper。
- `services/FileSearch.qml` 或 helper。

Search 只聚合 provider，不直接写复杂扫描逻辑。

### 禁止

- 同步扫全盘。
- 默认做内容索引。
- 默认读取敏感目录。
- 阻塞 UI。

### 完成标准

- Search 输入时不明显卡顿。
- 最近项目可打开。
- 文件名搜索有超时和上限。
- 依赖缺失不影响应用搜索。

完成后写 `search-files-recent-acceptance-YYYY-MM-DD.md`。

## 阶段 6：设置面板后端补强（已取消，不做）

### 目标

减少“打开 GNOME/KDE/XFCE 设置”的跳转，让 Tahoe 设置面板管理真实状态。

### 当前问题

设置面板已有 Tahoe JSON state 和 niri KDL 部分读写，但系统设置很多仍是外部跳转。

### 必须实现

优先补低风险真实后端：

- XDG autostart 列表、启用、禁用。
- 默认应用查看。
- 默认应用设置，基于 `xdg-mime`。
- 通知 per-app 规则。
- niri 设置页明确可写与只读边界。

### 禁止

- 一次性重写 SettingsPanel。
- GUI 编辑 niri keybind。先继续只读。
- 用 regex 无限扩展复杂 KDL 写入。复杂到不可维护时再引入结构化 parser。

### 完成标准

- 设置项能读真实状态。
- 写入失败有 UI 错误。
- 不破坏 niri config。
- 外部跳转项标明是 fallback。

完成后写 `settings-backends-acceptance-YYYY-MM-DD.md`。

## 阶段 7：托盘菜单和 AppMenu 稳定性（已取消，不做）

### 目标

补齐托盘菜单 nested submenu，并让 AppMenu 探测更稳定。

### 当前问题

- SNI 托盘图标可显示。
- 托盘菜单可显示一级项。
- 子菜单只画箭头，未展开。
- AppMenu 靠 Python + `busctl` 探测，属于可用但脆弱。

### 必须实现

先托盘：

- nested submenu 可展开。
- checked、disabled、separator 正确显示。
- 子菜单不越屏。
- 点击外部关闭。

再 AppMenu：

- helper timeout 明确。
- 单个 app DBus 异常不拖慢顶栏。
- 保留 focused-app fallback。

### 禁止

- 为 AppMenu 强行启动 DBusActivatable 应用。
- 顶栏每次渲染都跑重探测。
- 复制一套与 tray menu 不一致的菜单系统。

### 完成标准

- fcitx/Telegram/Steam 类菜单基本可用。
- 子菜单可用。
- AppMenu 探测失败不影响 shell。

完成后写 `tray-appmenu-stability-acceptance-YYYY-MM-DD.md`。

## 阶段 8：安装、更新、依赖可诊断（已取消，不做）

### 目标

让 Arch 安装和更新路径更可维护，依赖缺失时用户能知道影响。

### 当前问题

项目已有 `baremetal-install.sh`、`arch-update.sh`、`arch-zh-setup.sh`，但依赖多，平台窄，失败项需要更清楚地呈现。

### 必须实现

- `arch-update.sh` 输出机器可读 summary。
- 健康页展示 managed paths：
  - niri binary。
  - quickshell binary。
  - Tahoe shell config。
  - niri config。
  - session desktop file。
  - patched satellite。
  - glamor wrapper。
- 依赖缺失说明影响。

### 禁止

- 现在就扩展多发行版安装器。
- 覆盖用户非 Tahoe 管理的配置。
- 让 update 脚本静默跳过关键失败。

### 完成标准

- 干净 Arch 路径可复现。
- 重复运行 update 不破坏用户配置。
- 健康页能解释依赖状态。

完成后写 `install-update-health-acceptance-YYYY-MM-DD.md`。

## 4. 暂停项

这些不是永久不做，只是本轮明确不排进执行链。

### 输入法

当前保留 fcitx5 路径。后续如果要做，应单独开路线：

- fcitx5 DBus 事件驱动。
- IBus 抽象。
- 真实 engine label。
- per-app 状态。

### 截图和录屏

当前不改变用户截图/录屏入口。后续如果要做，应单独开路线：

- Tahoe screenshot UI 与 niri 内建 screenshot 统一。
- Shell 消费 cast 状态。
- 顶栏屏幕共享/录屏状态。
- 录屏控制入口。

Dock/window thumbnail 不属于截图录屏功能，不能改变用户截图行为。

## 5. 执行总表（已废弃）

原严格顺序已废弃，当前状态如下：

1. Dock 最小化窗口缩略栏：已完成。
2. 锁屏、空闲、熄屏、睡眠统一：已取消，不做。
3. 窗口总览真实缩略图：已取消，不做。
4. 兼容性回归矩阵：已取消，不做。
5. Search 最近项目和文件名搜索：已取消，不做。
6. 设置面板后端补强：已取消，不做。
7. 托盘菜单和 AppMenu 稳定性：已取消，不做。
8. 安装、更新、依赖可诊断：已取消，不做。

原“不能并行、不能跳阶段、不能把暂停项插进来”的执行限制不再适用，因为本路线图已废弃。

## 6. 第一阶段最小切入点（历史记录，阶段 1 已完成）

阶段 1 已完成；本节仅保留当时的切入顺序记录。

第一步只改数据模型：

- `Windows.qml` 增加 `minimizedWindowList`。
- `Windows.qml` 增加 `nonMinimizedWindowList`。
- 不改现有 `windowList` 语义。

第二步只改 Dock 布局：

- 普通窗口区读 `nonMinimizedWindowList`。
- 新增 minimized shelf 占位，但还不算完成。
- 保证 Downloads/Trash 不被挤掉。

第三步做 thumbnail provider：

- niri 增加私有 window thumbnail IPC/action。
- Shell 请求 runtime thumbnail。
- thumbnail 失败显示 fallback。

第四步接交互：

- 点击恢复。
- 右键菜单。
- 窗口关闭清理。
- 多窗口排序。

第五步回归和 acceptance：

- Dock 全功能回归。
- niri validate。
- QML smoke。
- 写验收文档。

这个切入顺序保持 KISS：先拆状态，再放 UI，再接真实缩略图，最后接交互和验收。
