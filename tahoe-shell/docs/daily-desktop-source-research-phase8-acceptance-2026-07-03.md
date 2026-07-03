# Tahoe 日用桌面反腐化 Phase 8 验收记录

日期：2026-07-03

对应路线图：`daily-desktop-source-research-anti-corruption-roadmap-2026-07-03.md` Phase 8：shell 全局协调拆小，但保留 ShellRoot API。

## 结论

Phase 8 已完成。

本阶段没有拆掉 `ShellRoot`，没有改变 Quickshell IPC target `tahoe`，也没有批量修改组件调用点。`shell.qml` 仍保留原来的 public wrapper 函数和同名状态属性；顶栏 popup/tray 状态委托给 `ShellPopupState.qml`，屏幕命名和导航目标判断委托给 `ShellNavigation.qml`。

## 现有互斥规则基线

- 顶栏 popup 同一时间只保留一个主 popup：`appMenu`、`applicationMenu`、`controlCenter`、`notificationCenter`、`battery`、`wifi`、`fan`、`clipboard`、`trayMenu` 互斥。
- 打开任一顶栏 popup 时会准备目标屏幕和 anchor rect，并关闭 Launchpad 与 Spotlight。
- tray menu 关闭时必须清空 `trayMenuItem`，避免复用旧托盘项。
- `closeTopBarPopups(except)` 仍是 shell 级协调点：先关闭顶栏 popup，再关闭 dock menu、process menu、settings、left sidebar 和窗口导航，除非对应 `except` 被保留。
- `wifiPopupOpen` 的既有 changed handler 保留，继续在外部直接打开 Wi-Fi popup 时关闭其他 popup/导航 surface。
- `navigationScreenName()` 优先使用 niri focused window 的 `output`，没有 focused output 时回退到第一个 Quickshell screen。
- `navigationOpenFor(open, targetScreenName, screen)` 保持空 target 视为任意屏幕、非空 target 必须匹配当前 screen name。

## 改动范围

- `tahoe-shell/components/ShellPopupState.qml`
  - 新增顶栏 popup/tray 状态 helper。
  - 内聚 popup open value、set、toggle、tray menu、dismiss geometry 和顶栏 popup 互斥关闭规则。
- `tahoe-shell/components/ShellNavigation.qml`
  - 新增导航 helper。
  - 内聚 `screenName()`、`navigationScreenName()`、`screenByName()` 和 `navigationOpenFor()`。
- `tahoe-shell/shell.qml`
  - 顶栏 popup 相关 property 改为 alias 到 `ShellPopupState`。
  - 原有 popup/navigation 函数名保留为 wrapper。
  - `ShellNavigation` 通过 `windowsService: niri` 继续读取 focused window output。
- `tahoe-shell/tests/test_shell_phase8_coordination.py`
  - 新增源码级 guardrail，防止后续把 popup/navigation 协调逻辑重新堆回 `shell.qml` 或破坏 ShellRoot wrapper/API。

## 验收点

- `ShellRoot {}` 仍是 `shell.qml` 根对象。
- `IpcHandler { target: "tahoe" }` 未改变。
- 以下 wrapper 函数仍存在于 `shell.qml`：
  - `screenName`
  - `navigationScreenName`
  - `navigationOpenFor`
  - `prepareTopBarPopup`
  - `topBarPopupOpenValue`
  - `setTopBarPopupOpen`
  - `topBarPopupOpenForName`
  - `toggleTopBarPopup`
  - `openTopBarTrayMenu`
  - `screenByName`
  - `topBarPopupOpenFor`
  - `topBarDismissOpenFor`
  - `topBarDismissPopupWidth`
  - `topBarDismissPopupHeight`
  - `topBarDismissFallbackRight`
  - `closeTopBarPopups`
- 组件挂载处仍调用 `shell.*`，没有改成直接依赖 helper。
- 顶栏 popup state 不再由 `shell.qml` 直接声明为本地 `property bool ...: false`，而是 alias 到 helper。

## 验证

已执行：

```sh
python3 -m pytest tahoe-shell/tests/test_shell_phase8_coordination.py
```

结果：通过。

```sh
python3 -m pytest tahoe-shell/tests
```

结果：通过，45 个测试全部通过。

```sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/components/ShellPopupState.qml tahoe-shell/components/ShellNavigation.qml tahoe-shell/shell.qml
```

结果：通过。输出仍包含 `shell.qml` 里既有的 `modelData` unqualified warning，不是本阶段新增解析错误。

```sh
git diff --check -- tahoe-shell/components/ShellPopupState.qml tahoe-shell/components/ShellNavigation.qml tahoe-shell/shell.qml tahoe-shell/tests/test_shell_phase8_coordination.py tahoe-shell/docs/daily-desktop-source-research-phase8-acceptance-2026-07-03.md
```

结果：通过。

## 未执行项

未做实机会话点击验收；本阶段完成的是 shell 全局协调的局部反腐化、源码 guardrail 和静态验证。
