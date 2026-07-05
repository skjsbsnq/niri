# Daily Desktop Source Research Phase 10 Acceptance

日期：2026-07-03

## 范围

Phase 10 按路线图的桌面完成度优先级补齐最高价值缺口，并复用 Phase 0-9 已落地的反腐化基础。本文记录本阶段落地内容和验收结果。

## 改动

- `tahoe-shell/services/autostart_manager.py`
  - 新增 XDG autostart 后端 helper。
  - 合并读取用户 `XDG_CONFIG_HOME/autostart` 和系统 `XDG_CONFIG_DIRS/autostart`。
  - 输出稳定 JSON schema：`schemaVersion`、`status`、`detail`、`userDir`、`entries`。
  - 每个 entry 显示 `Exec`、`Hidden`、`OnlyShowIn`、`NotShowIn`、source、启用状态和 validation issues。
  - 启用、停用、添加、移除都只写用户 autostart 目录；系统项通过用户 override 实现停用，不写系统目录。
- `tahoe-shell/services/DesktopSettings.qml`
  - 接入 autostart helper。
  - 暴露 `autostartEntries`、`autostartStatus`、`autostartDetail`、`autostartUserDir`、`autostartActionText`、`autostartRevision`。
  - 增加 `refreshAutostart()`、`setAutostartEnabled()`、`addAutostartApp()`、`removeAutostartEntry()`。
- `tahoe-shell/components/settings/pages/StartupPage.qml`
  - 从“打开目录 + 备注”升级为保守的 autostart manager。
  - 保留打开 autostart 文件夹和启动项备注。
  - 新增已配置启动项列表、启用/停用、移除、Exec/OnlyShowIn/Hidden/校验详情。
  - 新增从已安装桌面应用添加启动项。
- `tahoe-shell/components/SettingsPanel.qml`、`tahoe-shell/shell.qml`
  - 将 `appsService` 注入 StartupPage，用于列出可添加应用。
- `tahoe-shell/components/settings/SettingsModel.js`
  - 更新 `startup` capability metadata，明确后端为 XDG autostart manager，写入范围只限用户 autostart 覆盖。
- `tahoe-shell/services/search/TaskIndexProvider.js`
  - 在原 recently-used 和浅层用户目录结果之外，增加可选 `tracker3 search` 后端。
  - 缺少 `tracker3` 时静默降级，不影响应用、窗口、设置、最近文件和文件夹搜索。
  - Tracker 结果仍归一成 `recent-file` / `folder` 打开路径，不新增执行路径。
- `tahoe-shell/tests/test_autostart_manager.py`
  - 覆盖用户/system autostart merge、系统项用户 override 停用、启用保留字段、从应用添加、Desktop Entry key 写入边界。
- `tahoe-shell/tests/test_search_providers.py`
  - 覆盖 Tracker 结果解析、provider 标识、缺失降级脚本路径和原 timeout 护栏。
- `tahoe-shell/tests/test_settings_capability_registry.py`
  - 增加 StartupPage 是 native autostart manager 的静态合同测试。

## 与 Phase 10 优先级的对应关系

- 设置中心真实后端：
  - autostart manager 已从目录入口升级为真实 XDG autostart 管理。
  - default apps schema、privacy/apps read-only vs enforceable 能力区分已由 Phase 6 schema 和测试覆盖。
  - printers/color/accessibility 的外部入口和状态模型已由 Phase 4 capability registry 覆盖。
- 搜索：
  - provider 拆分已由 Phase 5 完成。
  - 最近文件/文件夹结果继续保留。
  - 新增可选 Tracker backend，且缺失时保持降级。
- 窗口任务：
  - WindowOverview/TaskSwitcher/Dock 缩略图唯一入口和 fallback 已由 Phase 3 完成。
  - merge fixtures 已由 Phase 2 完成。
- 视觉质感：
  - material governance、geometry/fallback/interaction 规则已由 Phase 9 完成。

## 验收命令

```sh
python3 -m py_compile tahoe-shell/services/autostart_manager.py
```

结果：通过。

```sh
python3 tahoe-shell/services/autostart_manager.py list
```

结果：通过，返回 `schemaVersion=1`、`mode=autostart`、`status=ok` 和 `entries` 数组。

```sh
python3 -m pytest tahoe-shell/tests/test_autostart_manager.py tahoe-shell/tests/test_search_providers.py tahoe-shell/tests/test_settings_capability_registry.py
```

结果：通过，`15 passed`。

```sh
python3 -m pytest tahoe-shell/tests
```

结果：通过，`54 passed`。

```sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/components/settings/pages/StartupPage.qml
```

结果：退出码 0。Qt 对 Repeater delegate 中嵌套按钮读取 row id 仍给出 `unqualified` 静态 warning；该 warning 不影响加载，且没有绕过 autostart helper。

```sh
git diff --check -- tahoe-shell/services/autostart_manager.py tahoe-shell/tests/test_autostart_manager.py tahoe-shell/services/DesktopSettings.qml tahoe-shell/components/settings/pages/StartupPage.qml tahoe-shell/components/SettingsPanel.qml tahoe-shell/shell.qml tahoe-shell/services/search/TaskIndexProvider.js tahoe-shell/tests/test_search_providers.py tahoe-shell/tests/test_settings_capability_registry.py tahoe-shell/components/settings/SettingsModel.js
```

结果：通过。

## 未做事项

- 未实现任意 `.desktop` 编辑器。
- 未写系统 autostart 目录。
- 未把普通应用权限伪装成可强制开关。
- 未强制依赖 Tracker；`tracker3` 缺失时保持原搜索能力。
- 未新增第二套窗口缩略图或截图路径。
- 未改变 TahoeGlass 数值、GPU 策略或 renderer 自适应逻辑。
