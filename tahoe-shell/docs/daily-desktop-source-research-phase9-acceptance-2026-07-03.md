# Daily Desktop Source Research Phase 9 Acceptance

日期：2026-07-03

## 范围

Phase 9 已完成视觉材质治理，不做 GPU/渲染能力自适应。本文记录本阶段落地内容和验收结果。

## 改动

- `tahoe-shell/docs/tahoe-material-governance.md`
  - 新增 Tahoe material governance 文档。
  - 固定七个 scene material：`panel`、`pill`、`launcher`、`dock`、`menu`、`toast`、`backdrop`。
  - 列出每个 material 的用途、默认 radius、fallback fill/stroke、interaction range。
  - 建立主要 surface recipes：TopBar、Dock、ControlCenter、NotificationToast、Launchpad、Spotlight、MenuPopup、SettingsPanel。
  - 明确 source of truth：`TahoeGlass.js`、`config/niri/tahoe-phase0.kdl`、`niri/niri-config/src/tahoe_glass.rs`、`NiriSettings.qml`、`niri_settings_tool.py`。
  - 明确不加入自动 GPU 探测、不按 renderer 自动切换 `useSpring`、不提高默认 chromatic/refraction 来制造视觉刺激。
- `tahoe-shell/tests/test_tahoe_material_governance.py`
  - 新增静态漂移护栏。
  - 校验 `TahoeGlass.js` material token、KDL material profiles、Rust niri-config defaults、QML 设置默认值、Python 设置 helper 默认值一致。
  - 校验 KDL `panel`、`menu`、`toast` fallback `background-effect` 和对应 material profile 一致。
  - 校验 governance 文档覆盖 Phase 9 要求的 material、surface recipes 和 GPU 自适应边界。
- `tahoe-shell/components/TahoeGlass.js`
  - 仅调整 material token 声明顺序，与 KDL/Rust/设置默认值的 canonical order 一致。
  - 未改变任何 token 值、radius、fill/stroke 或运行行为。

## 漂移检查结果

- `TahoeGlass.js`、`config/niri/tahoe-phase0.kdl`、`niri/niri-config/src/tahoe_glass.rs` 的 material vocabulary 已统一为：
  - `panel`
  - `pill`
  - `launcher`
  - `dock`
  - `menu`
  - `toast`
  - `backdrop`
- KDL 和 Rust 默认 profile 的九个字段一致：
  - `noise`
  - `saturation`
  - `contrast`
  - `tint-amount`
  - `edge-highlight`
  - `refraction`
  - `inner-shadow`
  - `chromatic`
  - `lens-depth`
- QML/Python 设置层只镜像五个可写 visual fields，且默认值与 KDL/Rust 一致：
  - `edge-highlight`
  - `refraction`
  - `inner-shadow`
  - `chromatic`
  - `lens-depth`

## 验收命令

```sh
python3 -m pytest tahoe-shell/tests/test_tahoe_material_governance.py -q
```

结果：通过，`3 passed, 26 subtests passed`。

```sh
bash scripts/check-tahoe-glass-guardrails.sh
```

结果：通过，Tahoe glass guardrails passed。

```sh
python3 tahoe-shell/services/niri_settings_tool.py read --config config/niri/tahoe-phase0.kdl
```

结果：退出码 0，返回 `ok: true`，能读取 glass material、blur、layout、input、animations 和 read-only binds。

```sh
python3 -m pytest tahoe-shell/tests -q
```

结果：通过，`48 passed, 63 subtests passed`。

## 未做事项

- 未加入自动 GPU 探测。
- 未按 renderer 自动改 `useSpring`。
- 未提高默认 chromatic/refraction。
- 未删除任何 fallback。
- 未改变 TahoeGlass 协议、shader、KDL material 数值或 QML surface material 选择。
