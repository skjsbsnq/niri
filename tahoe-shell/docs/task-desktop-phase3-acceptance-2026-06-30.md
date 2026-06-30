# Tahoe 任务桌面阶段 3 验收记录

日期：2026-06-30

对应路线图：`task-desktop-research-roadmap-2026-06-30.md` 阶段 3：缩略图 provider。

## 结论

阶段 3 已完成。

本阶段把窗口缩略图从组件内直接调用 `niri msg window-thumbnail` 收敛到统一 `ThumbnailProvider` 服务；Dock minimized shelf、TaskSwitcher 和 WindowOverview 均复用同一 provider。niri IPC 写入边界已收紧到 `$XDG_RUNTIME_DIR/tahoe/window-thumbnails`。

## 改动范围

- 新增 `tahoe-shell/services/ThumbnailProvider.qml`。
- 修改 `tahoe-shell/shell.qml`，实例化并注入 thumbnail provider。
- 修改 `tahoe-shell/components/Dock.qml`、`DockMinimizedShelf.qml`、`DockMinimizedWindow.qml`，迁移 Dock minimized shelf 到 provider。
- 修改 `tahoe-shell/components/TaskSwitcher.qml`，窗口卡片优先显示真实窗口缩略图。
- 修改 `tahoe-shell/components/WindowOverview.qml`，窗口卡片优先显示真实窗口缩略图。
- 修改 `tahoe-shell/services/Windows.qml`，移除缩略图路径和清理职责。
- 修改 `tahoe-shell/services/SystemStatus.qml`，增加缩略图 provider 健康检查。
- 修改 `niri/src/ipc/server.rs`、`niri/src/niri.rs`、`niri/niri-ipc/src/lib.rs`、`niri/src/cli.rs`，收紧 IPC 路径边界并更新说明。

## 验收点

- Dock minimized shelf 仍使用真实缩略图；生成失败时显示原 app icon/title fallback。
- TaskSwitcher 可通过同一 provider 显示真实窗口缩略图；失败时保留图标 fallback。
- WindowOverview 可通过同一 provider 显示真实窗口缩略图；失败时保留几何小地图 fallback。
- Provider 使用单一进程串行队列，按窗口 id 去重，队列上限为 64，连续打开 TaskSwitcher/WindowOverview 不会产生无界进程。
- Provider 统一 runtime 路径、缓存状态、30 秒 TTL、窗口关闭后的缓存和文件清理。
- niri IPC 只允许写入 `$XDG_RUNTIME_DIR/tahoe/window-thumbnails` 直属文件，拒绝父目录逃逸、其它绝对目录和嵌套目录。
- 健康页新增 `窗口缩略图 provider` 状态，便于确认 provider、CLI 和 IPC 边界是否部署到位。

## 验证

已执行：

```sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/services/ThumbnailProvider.qml tahoe-shell/components/DockMinimizedWindow.qml tahoe-shell/components/DockMinimizedShelf.qml tahoe-shell/components/Dock.qml tahoe-shell/components/TaskSwitcher.qml tahoe-shell/components/WindowOverview.qml tahoe-shell/shell.qml tahoe-shell/services/SystemStatus.qml
```

结果：通过。仍有仓库既有的 `PanelWindow`/`TahoeGlass` qmltypes warning 和 `modelData` unqualified warning。

```sh
git diff --check -- tahoe-shell/services/ThumbnailProvider.qml tahoe-shell/services/Windows.qml tahoe-shell/components/DockMinimizedWindow.qml tahoe-shell/components/DockMinimizedShelf.qml tahoe-shell/components/Dock.qml tahoe-shell/components/TaskSwitcher.qml tahoe-shell/components/WindowOverview.qml tahoe-shell/shell.qml tahoe-shell/services/SystemStatus.qml niri/src/ipc/server.rs niri/src/niri.rs niri/niri-ipc/src/lib.rs niri/src/cli.rs
```

结果：通过。

```sh
cargo check -p niri --manifest-path niri/Cargo.toml
```

结果：通过。

```sh
cargo test -p niri tahoe_thumbnail_path --manifest-path niri/Cargo.toml
```

结果：通过，4 个路径边界测试全部通过。

## 未执行项

未做 live 桌面截图验收。原因：当前任务只要求完成阶段 3 源码改造；为避免覆盖或重启用户正在使用的 Tahoe/niri 会话，本记录只做源码、QML lint 和 Rust check/test 验收。实际会话中仍建议打开 Dock minimized shelf、TaskSwitcher 和 WindowOverview 做一次视觉确认。
