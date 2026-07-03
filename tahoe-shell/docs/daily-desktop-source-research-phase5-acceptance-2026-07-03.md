# Tahoe 日用桌面反腐化 Phase 5 验收记录

日期：2026-07-03

对应路线图：`daily-desktop-source-research-anti-corruption-roadmap-2026-07-03.md` Phase 5：搜索 provider 拆分，但保持排序和行为。

## 结论

Phase 5 已完成。

本阶段没有改变 Spotlight 搜索聚合顺序、结果排序、结果激活路径或 shell command 安全边界。`Search.qml` 继续作为聚合器和激活入口，具体 provider 的结果构造已拆到 `services/search/*.js` 纯函数模块。任务索引仍由原 `Process` 和 `timeout 1s python3` 路径执行，不阻塞 UI。

## 改动范围

- `tahoe-shell/services/Search.qml`
  - 新增 provider imports。
  - 保留 `resultsForQuery()` 的 provider 调用顺序。
  - 保留 `dedupeAndSort()`、`activateResult()`、`runShellCommand()` 和任务索引 `Process` 生命周期。
  - 用薄 wrapper 委托 provider，不改变原函数名。
- `tahoe-shell/services/search/CommandProvider.js`
  - 抽出 `>`/`!` prefix 解析和 command result 构造。
- `tahoe-shell/services/search/CalculatorProvider.js`
  - 抽出计算器解析、格式化和 result 构造。
- `tahoe-shell/services/search/SettingsProvider.js`
  - 抽出设置搜索 result 构造。
- `tahoe-shell/services/search/SystemActionProvider.js`
  - 抽出系统动作 result 构造。
- `tahoe-shell/services/search/WindowProvider.js`
  - 抽出窗口标题、副标题、图标和 result 构造。
- `tahoe-shell/services/search/AppProvider.js`
  - 抽出应用 result 构造。
- `tahoe-shell/services/search/ClipboardProvider.js`
  - 抽出固定剪贴板 result 构造。
- `tahoe-shell/services/search/ScreenshotProvider.js`
  - 抽出截图 result 构造。
- `tahoe-shell/services/search/TaskIndexProvider.js`
  - 抽出任务索引触发规则、输出解析、cached entries 到 result 的转换和 Python source。
- `tahoe-shell/tests/test_search_providers.py`
  - 新增 Phase 5 provider/guardrail 测试。

## 验收点

- `resultsForQuery()` provider 顺序保持为：command、calculator、screenshot、settings、system action、window、clipboard pins、apps、task index。
- shell command result 仍只由 `>` 或 `!` 前缀产生。
- `runShellCommand(result.command)` 仍只在 `result.kind === "command"` 分支中调用。
- 任务索引仍跳过 `>`、`!`、`=` 查询，并继续使用 `timeout 1s python3`。
- 任务索引 Python 内部 deadline 仍是 `0.82` 秒，输出仍限制为 80 项。
- 计算器继续忽略普通数字和 ISO 日期样式输入。
- `Search.qml` 不再内联 provider result 构造、计算器 parser 或任务索引 Python 文本。

## 验证

已执行：

```sh
python3 -m pytest tahoe-shell/tests/test_search_providers.py
```

结果：通过，5 个测试全部通过。

```sh
python3 -m pytest tahoe-shell/tests
```

结果：通过，24 个测试全部通过。

```sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/services/Search.qml
```

结果：退出码 0。

```sh
git diff --check -- tahoe-shell/services/Search.qml tahoe-shell/services/search tahoe-shell/tests/test_search_providers.py
```

结果：通过。

## 未执行项

未做实机会话视觉/交互验收；本阶段只完成源码结构拆分、静态 lint 和测试护栏。
