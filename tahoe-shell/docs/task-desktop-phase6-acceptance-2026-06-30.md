# Tahoe 任务桌面阶段 6 验收记录

日期：2026-06-30

对应路线图：`task-desktop-research-roadmap-2026-06-30.md` 阶段 6：搜索扩展为任务索引。

## 结论

阶段 6 已完成。

本阶段把 Spotlight/Search 从应用、设置、截图、计算器和显式命令前缀，扩展为任务搜索入口：打开窗口、最近文件、文件夹、固定剪贴板和系统动作现在都由 `Search.qml` 统一产出结果。慢索引以异步子进程和 query 缓存方式接入，不阻塞主搜索返回。

## 改动范围

- 修改 `tahoe-shell/services/Search.qml`。
  - 新增 `windowsService`、`clipboardService` 和 `commandRunner` 注入。
  - 新增窗口、固定剪贴板、系统动作、最近文件和文件夹 provider。
  - 新增慢索引 debounce、缓存和 `Process` 后台查询。
  - 保留原 app/settings/screenshot/calculator provider。
  - 保留 `>` / `!` 显式命令前缀，并给命令结果增加危险执行提示。
- 修改 `tahoe-shell/shell.qml`。
  - 为 Search 注入窗口、剪贴板和 CommandRunner。
  - 新增 Search 系统动作路由。
  - 电源类系统动作复用 Tahoe 菜单现有确认 UI。
- 更新 `tahoe-shell/docs/task-desktop-research-roadmap-2026-06-30.md` 阶段 6 状态。

## 验收点

- 应用搜索仍走 `Apps.qml.spotlightResults()` 和 `Apps.qml.launchApp()`。
- 设置搜索仍通过 `openSettingsRequested(page)` 打开 Tahoe 设置子页。
- 截图和计算器结果保留原激活路径。
- 窗口结果读取 `Windows.qml.recentWindowList` / `windowList`，激活时已最小化窗口走 `restore()`，其它窗口走 `activate()`。
- 固定剪贴板结果读取 `ClipboardHistory.pinnedEntries`，激活时走 `copyPinnedEntry()`。
- 最近文件和文件夹结果通过 `xdg-open` 打开。
- 系统动作可打开锁屏、窗口总览、任务切换器、Launchpad、控制中心、通知中心和剪贴板历史；睡眠、退出、重启、关机进入既有确认 UI。
- 慢 provider 使用 90ms debounce、`timeout 1s` 外层限制和 0.82s Python 内部 deadline；结果按 query 缓存，主 `resultsForQuery()` 先返回快速 provider。
- 普通查询不会默认执行 shell command；只有 `>` / `!` 前缀生成命令结果。

## 验证

已执行：

```sh
git diff --check -- tahoe-shell/services/Search.qml tahoe-shell/shell.qml
```

结果：通过。

```sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/services/Search.qml
```

结果：退出码 0，无输出。

```sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/services/Search.qml tahoe-shell/components/Spotlight.qml tahoe-shell/shell.qml
```

结果：退出码 0；仅出现既有 `PanelWindow` / `TahoeGlass` qmltypes 和 `modelData` unqualified 访问警告，未出现 `Search.qml` 新增代码错误。

```sh
sh -lc 'if command -v python3 >/dev/null 2>&1; then if command -v timeout >/dev/null 2>&1; then exec timeout 1s python3 -c "$1" "$2"; else exec python3 -c "$1" "$2"; fi; fi' sh 'import json, sys; print(json.dumps({"query": sys.argv[1]}, ensure_ascii=False))' '下载'
```

结果：退出码 0，输出有效 JSON：`{"query": "下载"}`。确认慢 provider 的 `sh -lc` 参数传递方式能保留非 ASCII 查询。

## 未执行项

未重启 live Tahoe shell，也未做真实鼠标/键盘交互 smoke。原因：本阶段主要是 Search provider 扩展和静态路由验证；为避免影响当前桌面会话，本记录只做 QML lint、命令参数验证和源码路由验收。
