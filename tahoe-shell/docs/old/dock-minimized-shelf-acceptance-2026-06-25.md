# Dock 最小化窗口缩略栏验收

日期：2026-06-25

## 修改范围

- 在 niri IPC 中新增私有 `window-thumbnail` 请求和 `niri msg --json window-thumbnail` 子命令，用于把指定窗口渲染成 PNG 缩略图。
- 在 Tahoe Shell `Windows.qml` 中新增 `nonMinimizedWindowList`、`minimizedWindowList` 和 runtime 缩略图路径 helper。
- 新增 Dock 设置项“最小化缩略栏”，默认关闭。
- 开关开启时，Dock 普通运行窗口区只显示非最小化窗口。
- 开关开启时，新增 Dock 最小化窗口 shelf，显示最小化窗口的真实缩略图，角落叠加 app icon。
- 最小化窗口缩略图点击恢复窗口，右键复用现有 `DockWindowMenu`。
- 窗口关闭后清理 `$XDG_RUNTIME_DIR/tahoe/window-thumbnails/window-<id>.png`。

## 关键文件

- `tahoe-shell/services/Windows.qml`
- `tahoe-shell/components/Dock.qml`
- `tahoe-shell/components/DockMinimizedShelf.qml`
- `tahoe-shell/components/DockMinimizedWindow.qml`
- `niri/niri-ipc/src/lib.rs`
- `niri/src/cli.rs`
- `niri/src/ipc/client.rs`
- `niri/src/ipc/server.rs`
- `niri/src/niri.rs`

## 用户可见变化

- 默认保持旧 Dock 行为：最小化窗口仍在普通运行窗口区以图标方式显示。
- 在设置面板 Dock 页开启“最小化缩略栏”后，Dock 结构变为：固定应用、非最小化运行窗口、最小化窗口缩略栏、Downloads、Trash。
- 开关开启后，最小化窗口不再重复出现在普通运行窗口区。
- 开关开启后，每个最小化窗口在 Dock 右侧显示独立缩略图。
- 缩略图右下角保留 app icon，便于识别来源应用。
- 点击缩略图会恢复对应窗口。
- 右键缩略图打开现有窗口菜单，可显示、固定、关闭等。
- 多个最小化窗口在 shelf 内横向滚动，不挤掉 Downloads 和 Trash。
- 缩略图生成失败时显示带 app icon 和标题的 fallback 卡片，Dock 不崩溃。

## 保留的旧行为

- `Windows.qml` 的 `windowList` 语义保持不变，仍表示完整窗口列表。
- 固定应用列表和固定应用状态格式未改变。
- 固定应用启动、拖拽重排、文件 drop 到 Dock app 打开逻辑未改变。
- Downloads 和 Trash 入口保留，Trash drop 逻辑未改变。
- 普通运行窗口按钮、右键菜单、自动隐藏逻辑保留。
- “最小化缩略栏”默认关闭时，最小化窗口保留旧图标样式。
- 用户截图、录屏、截图目录、剪贴板截图行为未改变。

## 手动验证步骤

1. 启动 Tahoe Shell 和本 fork 的 niri。
2. 打开两个不同应用窗口，确认 Dock 普通运行窗口区显示它们。
3. 不开启“最小化缩略栏”时，最小化其中一个窗口，确认它保留旧图标样式。
4. 打开设置面板 Dock 页，开启“最小化缩略栏”。
5. 最小化其中一个窗口，确认它从普通运行窗口区移除，并出现在 Downloads/Trash 左侧的缩略栏。
6. 确认缩略栏卡片显示真实窗口内容缩略图，不只是 app icon。
7. 点击缩略图，确认窗口恢复并离开缩略栏。
8. 同一应用打开多个窗口并逐个最小化，确认 shelf 中出现多个独立缩略图。
9. 最小化多个窗口直到 shelf 超出可用宽度，确认可横向滚动，Downloads 和 Trash 仍显示且可点击。
10. 右键最小化缩略图，确认打开现有 Dock 窗口菜单，并可执行“显示窗口”和“关闭窗口”。
11. 关闭一个已最小化窗口，确认对应缩略图立即消失，runtime 缩略图文件被清理。
12. 临时让 `niri msg window-thumbnail` 失败，确认对应窗口显示 fallback 卡片且 Dock 不崩溃。

## 自动验证命令

- `cargo fmt --manifest-path niri/Cargo.toml --check`
- `cargo check -p niri --manifest-path niri/Cargo.toml`
- `cargo run -p niri --manifest-path niri/Cargo.toml -- msg --help`
- `cargo run -p niri --manifest-path niri/Cargo.toml -- msg window-thumbnail --help`
- `niri validate`
- `git diff --check`
- `git -C niri diff --check`
- `command -v qmllint`：当前环境未安装，无法执行 QML lint。
- `command -v quickshell`：当前环境未安装，无法执行 Quickshell smoke。

## 已知风险

- 当前环境没有 `qmllint` 和 `quickshell`，QML 仅完成源码审阅，未在本机启动实际 shell 会话验证。
- 缩略图请求按最小化窗口 delegate 独立触发；窗口数量极多时会产生多个短生命周期 `niri msg` 请求。
- 如果某个窗口没有可渲染 surface、niri IPC 不可用或路径不可写，该窗口会显示 fallback 卡片。
- runtime 缓存清理绑定在 niri `WindowClosed` 事件；异常退出 shell 时可能留下旧 PNG，下一次同 id 会覆盖。

## 明确不做的内容

- 不进入阶段 2 的锁屏、空闲、熄屏、睡眠统一。
- 不改 Window Overview 的真实缩略图。
- 不改用户截图/录屏 UI、快捷键、保存目录或剪贴板行为。
- 不引入 grim、slurp 或 wf-recorder 生成 Dock 缩略图。
- 不重写 Dock、Windows service 或 pinned apps 状态格式。
- 不实现 thumbnail 批量调度、限流或持久缓存；这些留给后续总览缩略图阶段评估。
