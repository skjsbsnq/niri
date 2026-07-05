# Tahoe 日用桌面反腐化 Phase 4 验收记录

日期：2026-07-03

对应路线图：`daily-desktop-source-research-anti-corruption-roadmap-2026-07-03.md` Phase 4：设置中心 registry 和页面职责收敛。

## 结论

Phase 4 已完成。

本阶段没有移除任何设置入口，也没有把未完成后端包装成完整 native page。设置中心 registry 现在显式声明每个 panel 的能力级别、后端、外部设置 panel 和写入范围。原先共用 `FeaturePage.qml` 的系统域已按 `probe`、`external`、`readonly` 拆到语义页面组件。

## 改动范围

- `tahoe-shell/components/settings/SettingsModel.js`
  - 新增 `native`、`probe`、`external`、`readonly` capability schema。
  - 为所有设置 panel 声明 `capability`、`backend`、`externalPanel`、`writeScope`。
  - 把 `search`、`online-accounts`、`sharing`、`color`、`printers`、`accessibility`、`privacy` 的 feature probe id 收敛到 registry。
  - 增加 `featureIds()`、`capabilityLabel()`、`capabilityDetail()`、`capabilityIcon()` 等只读 helper。
- `tahoe-shell/components/settings/pages/FeatureProbePage.qml`
  - 新增实际探测页面实现。
  - UI 显示能力级别、后端、写入范围和探测状态。
  - 只从 `SettingsModel.featureIds(panelId)` 读取 probe 项，不再在页面内硬编码 feature id。
- `tahoe-shell/components/settings/pages/ExternalSettingsPage.qml`
  - 新增 external-link 语义包装页。
- `tahoe-shell/components/settings/pages/ReadOnlyCapabilityPage.qml`
  - 新增 read-only 语义包装页。
- `tahoe-shell/components/settings/pages/FeaturePage.qml`
  - 保留为兼容壳，委托到 `FeatureProbePage`。
- `tahoe-shell/components/SettingsPanel.qml`
  - `search`、`sharing` 使用 `FeatureProbePage`。
  - `online-accounts`、`color`、`printers`、`accessibility` 使用 `ExternalSettingsPage`。
  - `wellbeing`、`privacy` 使用 `ReadOnlyCapabilityPage`。
- `tahoe-shell/tests/test_settings_capability_registry.py`
  - 新增 Phase 4 guardrail 测试。
- `tahoe-shell/tests/test_status_types_schema.py`
  - 更新状态对象消费测试目标到 `FeatureProbePage.qml`。

## 验收点

- 所有现有设置入口仍保留原 id 和 `StackLayout` 顺序。
- 所有 panel 都有 capability metadata，不再只有页面标题和 component。
- `search`、`online-accounts`、`sharing`、`wellbeing`、`color`、`printers`、`accessibility`、`privacy` 都显式标识为非 native。
- Feature/probe 页显示能力级别、后端状态和写入范围。
- `FeatureProbePage.qml` 不再硬编码 feature id 列表。
- 外部设置按钮继续通过 `gnome-control-center` 打开对应 panel。

## 验证

已执行：

```sh
python3 -m pytest tahoe-shell/tests/test_settings_capability_registry.py tahoe-shell/tests/test_status_types_schema.py
```

结果：通过，7 个测试全部通过。

```sh
node - <<'NODE'
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('tahoe-shell/components/settings/SettingsModel.js', 'utf8').replace(/^\s*\.pragma library\s*\n/, '');
const context = { Array, Boolean, Date, JSON, Math, Number, Object, String, console, isFinite };
vm.createContext(context);
vm.runInContext(source, context, { filename: 'SettingsModel.js' });
const ids = ['search', 'online-accounts', 'sharing', 'wellbeing', 'color', 'printers', 'accessibility', 'privacy'];
for (const id of ids) {
  const panel = context.resolvedPanel(id);
  if (!panel || !panel.capability || panel.capability === 'native') {
    throw new Error(`${id} missing non-native capability`);
  }
}
process.stdout.write(JSON.stringify(ids.map((id) => [id, context.resolvedPanel(id).capability, context.featureIds(id)])) + '\n');
NODE
```

结果：通过，8 个目标 panel 均解析为非 native capability。

```sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/components/settings/pages/FeatureProbePage.qml tahoe-shell/components/settings/pages/FeaturePage.qml tahoe-shell/components/settings/pages/ExternalSettingsPage.qml tahoe-shell/components/settings/pages/ReadOnlyCapabilityPage.qml tahoe-shell/components/SettingsPanel.qml
```

结果：退出码 0。输出仍包含仓库既有的 `PanelWindow`/`TahoeGlass` qmltypes warning。

```sh
python3 -m pytest tahoe-shell/tests
```

结果：通过，19 个测试全部通过。

```sh
git diff --check -- tahoe-shell/components/settings/SettingsModel.js tahoe-shell/components/SettingsPanel.qml tahoe-shell/components/settings/pages/FeaturePage.qml tahoe-shell/components/settings/pages/FeatureProbePage.qml tahoe-shell/components/settings/pages/ExternalSettingsPage.qml tahoe-shell/components/settings/pages/ReadOnlyCapabilityPage.qml tahoe-shell/tests/test_settings_capability_registry.py tahoe-shell/tests/test_status_types_schema.py
```

结果：通过。

## 未执行项

未做实机会话视觉/交互验收；本阶段只完成源码结构收敛、静态 lint 和测试护栏。
