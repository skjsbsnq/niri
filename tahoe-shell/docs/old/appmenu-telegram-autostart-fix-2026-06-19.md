# AppMenu 探测导致 Telegram 自动启动修复记录

日期：2026-06-19

状态：已修复并同步到当前 Quickshell Tahoe 配置。

## 问题

用户手动关闭 Telegram 后，Telegram 会再次自动打开。

同时，顶栏“应用菜单”弹窗在没有 AppMenu registrar 时会重复显示两次“未检测到 AppMenu registrar”。

## 影响范围

- Telegram、Loupe、TextEditor 等带 `DBusActivatable=true` 或 DBus service 文件的应用可能被 AppMenu 探测误启动。
- 顶栏“应用菜单”在没有真实原生菜单时显示 fallback 操作：固定到 Dock、显示窗口、最小化。

## 根因

`tahoe-shell/services/appmenu_probe.py` 的 `candidate_services()` 逻辑过宽：

1. 当 focused app id 含 `.` 时，脚本直接把 app id 加入候选服务并探测 `/MenuBar`、`/menu` 等路径。
2. 对 `DBusActivatable=true` 的应用，向其 well-known name 发方法调用会触发 DBus/systemd user 自动启动应用。
3. 旧逻辑还会把 app id 拆成 token 做模糊匹配。例如 `org.gnome.Nautilus` 拆出 `org` 后，会误匹配到 `org.telegram.desktop`，导致脚本扫描 Telegram 的菜单路径并拉起 Telegram。

所以 Telegram 不是 niri autostart，也不是 Dock pinned 状态启动，而是 AppMenu 周期探测误触发 DBus 激活。

## 修改

### 1. 收紧 AppMenu DBus 候选服务

文件：

- `tahoe-shell/services/appmenu_probe.py`
- 已同步部署副本：`~/.config/quickshell/tahoe/services/appmenu_probe.py`

修改要点：

- 不再用 token 模糊匹配 DBus 服务。
- focused app id 只有在 `GetNameOwner(app_id)` 返回真实 owner 时才加入候选。
- `busctl --user list` 中仅保留已有 owner 的行：有唯一连接名，或 PID 大于 0。
- 只通过 focused window PID 精确匹配相关 DBus 连接。

### 2. 去掉应用菜单重复状态行

文件：

- `tahoe-shell/components/AppMenuPopup.qml`
- 已同步部署副本：`~/.config/quickshell/tahoe/components/AppMenuPopup.qml`

修改要点：

- 删除没有 native menu 时额外显示的 disabled `MenuRow`。
- 保留 header 下方的小字状态，例如“未检测到 AppMenu registrar”。
- fallback 操作仍保留：固定到 Dock、显示窗口、最小化。

## 验证

已执行：

```sh
python3 -m py_compile \
  /home/wwt/niri/tahoe-shell/services/appmenu_probe.py \
  /home/wwt/.config/quickshell/tahoe/services/appmenu_probe.py
```

结果：通过。

已执行 DBus 行为验证：

1. 停止 Telegram 的 transient DBus service。
2. 用 `dbus-monitor --session "type='method_call'"` 监控约 22 秒。
3. 确认没有新的 `/usr/bin/Telegram` 进程。
4. 监控中只剩 `GetNameOwner("org.telegram.desktop")` 这类不会激活应用的查询，没有对 `org.telegram.desktop` 的 `/MenuBar` 方法调用。

最终检查：

```sh
pgrep -afi 'telegram|tdesktop|org\.telegram'
```

结果：没有 Telegram 应用进程。

## 后续注意

- `systemctl --user list-units` 里可能还会看到空的 `app-dbus...org.telegram.desktop.slice`，这不是 Telegram 进程。
- 后续改 AppMenu 探测时，不要恢复基于通用 token 的 DBus 服务模糊匹配。
- 任何对 `DBusActivatable` 应用 well-known name 的方法调用，都可能启动该应用；探测前必须确认服务已有 owner。
