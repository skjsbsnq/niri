# Tahoe Apps Settings Probe Schema

日期：2026-07-03

适用文件：`tahoe-shell/services/apps_settings_probe.py`

## 目标

`apps_settings_probe.py` 输出的是应用设置页的数据合同。它必须明确区分：

- 普通 desktop app：没有 Tahoe 可强制 sandbox，只能显示 portal 记录。
- Flatpak：有运行时 sandbox 边界，但 Tahoe 当前只读 portal 记录和静态权限。
- Snap：有运行时 sandbox 边界，但 Tahoe 当前只读 connections。
- portal permission store 缺失：权限记录降级为警告/不可用。
- `xdg-mime` 缺失：默认应用读取和写入不可用。

UI 不应从文案猜测控制能力，而应读取 schema 字段。

## 通用字段

所有模式输出都包含：

```json
{
  "schemaVersion": 1,
  "mode": "defaults | set-default | permissions"
}
```

`schemaVersion` 只在字段语义不兼容时递增。新增兼容字段不需要递增。

## Defaults Mode

命令：

```sh
python3 tahoe-shell/services/apps_settings_probe.py probe
```

关键字段：

```json
{
  "schemaVersion": 1,
  "mode": "defaults",
  "status": "ok | missing",
  "detail": "human-readable detail",
  "xdgMime": {
    "status": "ok | missing",
    "available": true,
    "canRead": true,
    "canWrite": true,
    "detail": "human-readable detail"
  },
  "categories": [],
  "desktopMeta": {}
}
```

`status` 和 `detail` 为兼容旧 UI 保留；新代码优先读 `xdgMime`。

## Permissions Mode

命令：

```sh
python3 tahoe-shell/services/apps_settings_probe.py permissions org.example.App.desktop
```

顶层结构：

```json
{
  "schemaVersion": 1,
  "mode": "permissions",
  "app": {},
  "portal": {},
  "capability": {},
  "sandbox": {},
  "permissions": [],
  "staticPermissions": [],
  "snapConnections": [],
  "storage": {}
}
```

### App

```json
{
  "desktopId": "org.example.App.desktop",
  "id": "org.example.App",
  "name": "Example",
  "sandboxType": "none | flatpak | snap",
  "sandboxId": "org.example.App"
}
```

### Portal

```json
{
  "status": "ok | missing",
  "portalStatus": "ok | missing",
  "available": true,
  "canRead": true,
  "canWrite": false,
  "detail": "human-readable detail"
}
```

`canWrite` 当前固定为 `false`。不要把 portal 记录显示成 Tahoe 可写开关。

### Capability

```json
{
  "sandboxType": "none | flatpak | snap",
  "sandboxId": "org.example.App",
  "fullyEnforceable": false,
  "portalStatus": "ok | missing",
  "defaultControl": "readonly | warning",
  "canTogglePortalPermissions": false,
  "canWriteStaticPermissions": false,
  "writeScope": "none",
  "ordinaryAppWarning": true,
  "staticPermissionScope": "none | runtime-metadata"
}
```

`fullyEnforceable` 表示应用是否处于 Flatpak/Snap 这类运行时 sandbox 边界内，不表示 Tahoe 能完整写入权限。Tahoe 当前不写 portal 权限、Flatpak 静态权限或 Snap connections。

### Sandbox

```json
{
  "type": "none | flatpak | snap",
  "sandboxType": "none | flatpak | snap",
  "id": "org.example.App",
  "sandboxId": "org.example.App",
  "fullyEnforceable": false,
  "desktopId": "org.example.App.desktop",
  "writeScope": "none",
  "enforcementScope": "none | runtime-sandbox"
}
```

`type/id` 为兼容字段；新代码可以使用 `sandboxType/sandboxId`。

### Portal Permission Rows

`permissions[]` 中每条记录：

```json
{
  "id": "camera",
  "title": "摄像头",
  "table": "devices",
  "object": "camera",
  "status": "allowed | denied | unrecorded | unavailable | unknown",
  "detail": "portal detail",
  "raw": "truncated raw output",
  "control": "readonly | warning",
  "presentation": "readonly | warning",
  "canToggle": false,
  "readOnly": true,
  "readOnlyReason": "why this is not a switch",
  "scope": "portal-record",
  "externalAction": ""
}
```

普通 desktop app 的 `control` 必须保持 `readonly` 或 `warning`，`canToggle` 必须为 `false`。

### Flatpak Static Permissions

`staticPermissions[]` 仅对 Flatpak 应用返回。每条记录包含通用 row 字段，并且：

```json
{
  "control": "external | warning",
  "canToggle": false,
  "scope": "runtime-metadata",
  "externalAction": "Flatpak"
}
```

这些权限来自 `flatpak info --show-permissions`，不是 Tahoe 可完全写入的权限开关。

### Snap Connections

`snapConnections[]` 仅对 Snap 应用返回。每条记录包含通用 row 字段，并且：

```json
{
  "control": "external | warning",
  "canToggle": false,
  "scope": "runtime-metadata",
  "externalAction": "Snap"
}
```

这些连接来自 `snap connections`，不是 Tahoe 可完全写入的权限开关。

### Storage

```json
{
  "totalBytes": 0,
  "total": "0 B",
  "items": [
    {
      "id": "/path",
      "title": "Data | Cache | Config | Flatpak data | Snap data",
      "path": "/path",
      "bytes": 0,
      "size": "0 B",
      "truncated": false
    }
  ]
}
```

存储数据是估算值，只用于展示。

## UI Guardrail

`AppPermissionsPage.qml` 应按以下规则呈现：

- `canToggle === true` 才允许显示可切换控制。
- `control === "readonly"` 显示只读 row。
- `control === "warning"` 显示警告 row。
- `control === "external"` 显示外部管理/只读元数据 row。
- 普通 desktop app 必须显示不可完整强制限制的提示。
- 不得把 `staticPermissions` 或 `snapConnections` 当作 Tahoe 可完全写入的权限。
