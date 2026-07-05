# Tahoe 日用桌面反腐化 Phase 3 验收记录

日期：2026-07-03

对应路线图：`daily-desktop-source-research-anti-corruption-roadmap-2026-07-03.md` Phase 3：窗口缩略图 provider 成为唯一入口。

## 结论

Phase 3 已完成。

本阶段没有新增第二套截图或抓图通道。Dock minimized shelf、TaskSwitcher、WindowOverview 继续只通过 `ThumbnailProvider` 获取窗口缩略图，并把失败/缺失缩略图的占位视觉收敛到共享 `WindowPreviewFallback.qml`。

## 改动范围

- `tahoe-shell/services/ThumbnailProvider.qml`
  - 补充 provider 接口契约文档。
  - 明确 `requestThumbnail`、cache key、failure state、cleanup 行为和唯一入口护栏。
- `tahoe-shell/components/WindowPreviewFallback.qml`
  - 新增共享窗口预览占位组件。
  - 支持 Dock 图标标题 fallback、TaskSwitcher 图标 fallback、WindowOverview 几何 fallback。
- `tahoe-shell/components/DockMinimizedWindow.qml`
  - 缩略图失败或缺失时改用共享 fallback 组件。
- `tahoe-shell/components/TaskSwitcher.qml`
  - 卡片预览失败或缺失时改用共享 fallback 组件。
- `tahoe-shell/components/WindowOverview.qml`
  - 几何 mini-map fallback 改用共享 fallback 组件。
- `tahoe-shell/tests/test_thumbnail_provider_contract.py`
  - 新增 Phase 3 guardrail 测试，防止组件层绕过 provider 生成缩略图。

## 验收点

- `ThumbnailProvider.qml` 记录了 `requestThumbnail(window, maxWidth, maxHeight, reason, force)`、cache key、失败状态和清理策略。
- 窗口预览 surface 不直接调用 `niri msg window-thumbnail --id/--path/--max-width`。
- 生成缩略图的 `niri msg --json window-thumbnail` 请求仍只在 `ThumbnailProvider.qml` 的队列进程中存在。
- Dock、TaskSwitcher、WindowOverview 都使用 `WindowPreviewFallback.qml` 做统一 fallback。
- `SystemStatus.qml` 保留 `niri msg window-thumbnail --help` 健康探测；该探测不生成缩略图，不属于预览入口。

## 验证

已执行：

```sh
python3 -m pytest tahoe-shell/tests/test_thumbnail_provider_contract.py
```

结果：通过，3 个测试全部通过。

```sh
python3 -m pytest tahoe-shell/tests
```

结果：通过，15 个测试全部通过。

```sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/services/ThumbnailProvider.qml tahoe-shell/components/WindowPreviewFallback.qml tahoe-shell/components/DockMinimizedWindow.qml tahoe-shell/components/TaskSwitcher.qml tahoe-shell/components/WindowOverview.qml tahoe-shell/shell.qml
```

结果：退出码 0。输出仍包含仓库既有的 `PanelWindow`/`TahoeGlass` qmltypes warning 和 `shell.qml` 中 `modelData` unqualified warning。

```sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/components/WindowPreviewFallback.qml
```

结果：通过，无输出。

```sh
git diff --check -- tahoe-shell/services/ThumbnailProvider.qml tahoe-shell/components/WindowPreviewFallback.qml tahoe-shell/components/DockMinimizedWindow.qml tahoe-shell/components/TaskSwitcher.qml tahoe-shell/components/WindowOverview.qml tahoe-shell/tests/test_thumbnail_provider_contract.py
```

结果：通过。

## 未执行项

未做实机会话视觉验收；本阶段只完成源码反腐化、静态检查和测试护栏。
