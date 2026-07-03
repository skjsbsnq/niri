# Tahoe 日用桌面反腐化 Phase 6 验收记录

日期：2026-07-03

对应路线图：`daily-desktop-source-research-anti-corruption-roadmap-2026-07-03.md` Phase 6：应用设置和权限能力模型化。

## 结论

Phase 6 已完成。

本阶段没有新增权限写入能力，也没有把普通桌面应用伪装成可强制 sandbox。`apps_settings_probe.py` 的输出现在包含版本化 schema、应用 sandbox 能力、portal 状态、权限 row 控制呈现字段、Flatpak/Snap 外部管理标识和存储信息。UI 根据这些字段显示只读、警告或外部管理状态。

## 改动范围

- `tahoe-shell/services/apps_settings_probe.py`
  - 新增 `schemaVersion` 和 `mode`。
  - 为默认应用 probe 增加 `xdgMime` 状态对象。
  - 为权限 probe 增加 `app`、`portal`、`capability`、扩展 `sandbox` 字段。
  - 为 portal 权限 row 增加 `control`、`presentation`、`canToggle`、`readOnly`、`readOnlyReason`、`scope`、`externalAction`。
  - Flatpak static permissions 和 Snap connections 标记为 `external` 或 `warning`，不作为 Tahoe 开关。
- `tahoe-shell/services/AppsSettings.qml`
  - 保存 `permissionCapability`。
  - 为旧 schema 和错误路径补兼容 fallback。
- `tahoe-shell/components/settings/pages/AppPermissionsPage.qml`
  - 从 schema 读取 `ordinaryAppWarning`、`canToggle` 和 `control`。
  - 权限 row 显示“只读 / 警告 / 外部”状态。
  - 不新增权限开关。
- `tahoe-shell/tests/fixtures/apps-settings/`
  - 新增 ordinary desktop app、Flatpak、Snap fixture。
- `tahoe-shell/tests/test_apps_settings_probe_schema.py`
  - 覆盖 ordinary desktop app、Flatpak、Snap、portal store missing、`xdg-mime` missing 和 UI guardrail。
- `tahoe-shell/docs/apps-settings-permissions-schema-2026-07-03.md`
  - 记录 Phase 6 schema 合同。

## 验收点

- ordinary desktop app：
  - `sandboxType === "none"`。
  - `fullyEnforceable === false`。
  - `ordinaryAppWarning === true`。
  - 所有权限 row 都是 `readonly` 或 portal 缺失时的 `warning`，`canToggle === false`。
- Flatpak：
  - `sandboxType === "flatpak"`。
  - `fullyEnforceable === true` 仅表示运行时 sandbox 边界存在。
  - static permissions 标记为 `external`，`canToggle === false`。
- Snap：
  - `sandboxType === "snap"`。
  - connections 标记为 `external`，`canToggle === false`。
- portal store missing：
  - `portal.status === "missing"`。
  - portal 权限 row 降级为 `warning` 和 `unavailable`。
- `xdg-mime` missing：
  - 默认应用 schema 中 `xdgMime.available/canRead/canWrite` 均为 `false`。
- UI：
  - `AppPermissionsPage.qml` 消费 schema。
  - 不渲染权限 switch。
  - 保留普通应用不可完整强制限制提示。

## 验证

已执行：

```sh
python3 -m pytest tahoe-shell/tests/test_apps_settings_probe_schema.py
```

结果：通过，6 个测试全部通过。

```sh
python3 -m pytest tahoe-shell/tests
```

结果：通过，30 个测试全部通过。

```sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/services/AppsSettings.qml tahoe-shell/components/settings/pages/AppPermissionsPage.qml
```

结果：退出码 0。

```sh
python3 -m py_compile tahoe-shell/services/apps_settings_probe.py tahoe-shell/tests/test_apps_settings_probe_schema.py
```

结果：通过。

```sh
git diff --check -- tahoe-shell/services/apps_settings_probe.py tahoe-shell/services/AppsSettings.qml tahoe-shell/components/settings/pages/AppPermissionsPage.qml tahoe-shell/tests/test_apps_settings_probe_schema.py tahoe-shell/tests/fixtures/apps-settings tahoe-shell/docs/apps-settings-permissions-schema-2026-07-03.md tahoe-shell/docs/daily-desktop-source-research-phase6-acceptance-2026-07-03.md
```

结果：通过。

## 未执行项

未做实机会话视觉/交互验收；本阶段只完成 schema、UI guardrail、fixture 测试和静态检查。
