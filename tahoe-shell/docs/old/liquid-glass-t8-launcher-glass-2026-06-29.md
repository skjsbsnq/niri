# Liquid Glass T8 Launcher Glass Route

日期：2026-06-29

## 状态

T8 已完成。`Spotlight.qml` 保持 search pill + results panel 两个 compositor-owned region，`Launchpad.qml` 保持一个居中 launcher card region，并改用新的 `launcher` material。

## 视觉决策

- `Spotlight.qml` search pill 继续使用 `pill` material，但 profile 调整为更明显 edge highlight、很轻的 lens-depth，`chromatic` 仍为 `0.0`。
- `Spotlight.qml` results panel 继续使用 `panel` material；`panel` profile 调高 tint/contrast、降低 refraction/lens-depth，优先保证搜索结果文字可读。
- `Launchpad.qml` 不是 fullscreen backdrop，也不适合继续吃全局 `panel` profile；T8 将它定义为介于两者之间的居中大 launcher card。
- 新增 `launcher` material：比 `panel` 更克制，比 `backdrop` 更有边缘；低 refraction、低 lens-depth，避免大 card 出现整屏水波、巨大 rim 或大 halo。

## 本轮改动

- `tahoe-shell/components/TahoeGlass.js`
  - 新增 `MaterialLauncher`、`FillLauncher`、`StrokeLauncher`。
  - `launcher` 复用 `RadiusPanel`，并接入 `fillForMaterial()` / `strokeForMaterial()`。
- `tahoe-shell/components/Launchpad.qml`
  - 主 `GlassPanel` 从 `MaterialPanel` 改为 `MaterialLauncher`。
  - region 仍是显式 rect：`regionX/Y/Width/Height` 绑定 card 的稳定 bounds。
  - 打开/关闭仍只动画 opacity、content transform 和 `materialAlpha`，不动画 region bounds。
- `config/niri/tahoe-phase0.kdl`
  - 收紧 `panel`：更高 tint/contrast、更低 refraction/lens-depth。
  - 强化 `pill` edge highlight，同时降低 lens-depth，保持 `chromatic 0.0`。
  - 新增 `material "launcher"`。
  - 同步 panel fallback `background-effect` blocks。
- `niri/niri-config/src/tahoe_glass.rs`
  - 默认 material map 增加 `launcher`，无 KDL block 时不退回普通 `panel`。
- `tahoe-shell/services/NiriSettings.qml`
  - 默认 `glassMaterials` 增加 `launcher`，并同步当前 KDL profile。
- `tahoe-shell/services/niri_settings_tool.py`
  - material 读写清单增加 `launcher`。
- `tahoe-shell/components/settings/pages/NiriGlassPage.qml`
  - 设置页 material segmented control 增加“启动器”。

## 保留的不变量

- 不改 TahoeGlass Wayland 协议。
- 不改 shader。
- 不新增 raw shader 参数。
- 不新增直接 `BackgroundEffect.blurRegion` 调用。
- `Spotlight.qml` 仍为两个 region；`Launchpad.qml` 仍为一个 region。
- `interaction` / `materialAlpha` 只影响材质强度和淡入淡出，不驱动 region geometry。
- 搜索结果内容变化不重建 `TahoeGlass.regions` 数组；结果 panel region 仍由同一个 `GlassPanel.region` 提供。

## 验证

已通过：

```sh
bash scripts/check-tahoe-glass-guardrails.sh
python3 tahoe-shell/services/niri_settings_tool.py read --config config/niri/tahoe-phase0.kdl
./niri/target/debug/niri validate -c config/niri/tahoe-phase0.kdl
cargo test -p niri-config tahoe_glass --quiet
```

额外 smoke：

```sh
python3 tahoe-shell/services/niri_settings_tool.py write --config "$tmp" --field glass.launcher.refraction --value 0.007 --skip-guardrails --niri-bin ./niri/target/debug/niri
```

结果：临时配置中的 `glass.materials.launcher.refraction` 可写入并读回 `0.007`。

未完成本机截图验证：当前执行环境没有 `quickshell` 和 `qmllint` 可执行文件，也没有可复用的 Tahoe shell 图形会话上下文。Spotlight/Launchpad 的视觉截图和关闭后 damage/blur 残留检查应在 T13 视觉基线流程中补采。
