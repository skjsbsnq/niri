# T04-fix · 动效问题修复验收

日期：2026-07-10
提交：子模块 `4b51a072` / 父仓 `3d68db1`
依赖：T04（`9e6889f3`）

## 背景

T04 后实机测试发现 5 个动效问题，根因分属合成器 Rust / KDL / genie shader / layer 引擎 4 层。用户反馈：关闭动画有时有有时无且不如打开；minimize/restore 慢、不从 dock 图标起源（restore 像凭空弹出）；顶栏除控制中心/通知中心外所有弹出物（含右键第三方图标菜单）缺下拉动画。

## 修复

| # | 问题 | 根因（行号） | 修复 |
|---|------|------|------|
| ① | 关闭动画有时有有时无 | `compositor.rs` on-commit unmap 路径无 store snapshot（app 自卸载 surface 走此路径），toplevel-destroyed 路径有。`take_unmap_snapshot()` None → 跳过整段 close | `compositor.rs:274` 补 `store_unmap_snapshot`，对齐 toplevel-destroyed（`xdg_shell.rs:873`） |
| ② | 退出动画不如打开、open 也奇怪 | KDL `window-close` 140ms ease-out-quad + shader scale 1→0.97 几乎无缩放 | KDL `window-close` spring(0.82/340) + scale 1→0.90；`window-open` shader scale 0.965→0.92，淡入完成点 0.7→0.55 |
| ③ | minimize/restore 凭空弹出 | `genie.frag:83` `end_fade=1-smoothstep(0.92,1,morph)`；restore 方向 morph=1→0，开始 morph=1→end_fade=0 全透明，前 8% 不可见 → 中途浮现 | `genie.frag` end_fade 方向感知：minimize(direction>0)末尾淡出、restore 全程可见 |
| ④ | minimize/restore 慢 | T04 配 420/360ms | KDL minimize 420→280，restore 360→260 |
| ⑤ | 除 CC/NC 外顶栏菜单缺下拉 | `opening_layer.rs:77` Popin offset 写死 0；`closing_layer.rs:285` Popout 写死 (0,0)。仅 EdgeReveal/Slide 有位移 | 新增 `pop-slide` style（scale+edge/distance 复合，T21 前置）；顶栏菜单 layer-open/close `pop-slide` + `edge top distance 10` |

### ⑤ 设计决策：为何新增 style 而非改 Popin/Popout

原计划（选择 C）让 Popin/Popout 用 distance + distance default 0→0。实测失败：
- distance default 32→0 破坏 3 个 layer close 测试（advance_layer_animations clock 顺序依赖被放大）；
- distance default 保持 32 则现有 spotlight/顶栏菜单 popin（origin center/anchor）获 32px 水平位移（edge 默认 Right）→ 运行时破坏。

故改用 B1：新增 `pop-slide` style 专做"缩放+位移复合"，Popin/Popout 保持写死 0、distance default 32 不动，零向后兼容风险。符合 roadmap T21 原设计（"新增 pop-slide style"）。

## 验证（自动化）

- `cargo check --workspace --all-targets` ✓（35.81s，无 warning）
- `cargo test -p niri -p niri-config`（相关子集）✓
  - genie_area / minimize_restore_with_rect / window_minimize_restore 节点解码 / layer_rule resolve ✓
  - layer_close_animation 3 个**独立跑** ✓
  - 注：3 个 layer close 测试**全量并行** fail —— `advance_layer_animations`（`layer_shell.rs:1205`）操作 Fixture clock 的顺序依赖 pre-existing flaky；纯原状（T04 `9e6889f3`）全量同 3 fail，非本次引入。T04 验收只跑特定子集（genie/minimize/restore）未发现
- `niri validate`（fork `cargo run --bin niri`）✓ "config is valid"（pop-slide 节点认识）
- `python -m pytest tahoe-shell/tests/ -x` ✓ 77 passed（含 edge_reveal_semantics / motion_default_policy / motion_token_convergence / niri_settings_tool）

## 手测矩阵（待用户实机确认）

部署：`scripts/arch-update.sh` 重部署 config + 子模块重编 niri bin（`cargo build --release`）后重启会话。

- [ ] ① 关闭：应用标题栏关闭 / Mod+Q / dock 菜单关闭 / X11 应用关闭 → 均有退出动画（无"有时无"）
- [ ] ② open/close：弹出/收束对称、缩放可辨
- [ ] ③ minimize：窗口吸入 dock 图标；restore：从 dock 图标平滑流出（不再凭空弹出）
  - 若仍凭空：加临时 `info!` 于 `niri.rs:2139 minimize_window_with_animation` 打印 `target_rect` Some/None，跑一次确认；rect=None 则 genie 整段跳过走纯 alpha 淡出（`minimize_window_animation.rs:303`），分流修 QML `setRectangle`（`WindowButton.qml:56`）或 niri `set_rectangle` layer 查找（`handlers/mod.rs:675-687`）。QML 侧已确认调 setRectangle（dockWindow=tahoe-dock PanelWindow 有效 layer surface），倾向 rect 已传到
- [ ] ④ minimize/restore 时长 ≈280/260ms 感观合适
- [ ] ⑤ 顶栏：电池/wifi/niri 菜单、右键第三方图标菜单 → 均有下拉+缩放，与 CC/NC 风格统一；dock 菜单/spotlight 仍纯缩放
- [ ] 玻璃 region 无 niri 拒绝日志（⑤ 位移是 transform 通道不动 region）

## RSS 对照（阶段 A 末检查点）

待手测后记录 quickshell + niri RSS 对照 T00 基线。

## 路线图维护

⑤ 前置实现 T21 的 pop-slide 核心（scale+edge/distance 复合）。T21 剩余（transform/opacity 覆写通道支持 spring）仍按原计划。pop-slide 已命名 style 化（本修复完成），T21 该项可缩减。

## 回滚

`git revert 3d68db1`（父仓）+ 子模块 `git revert 4b51a072`。
