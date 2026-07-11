# T21 · niri fork：layer per-channel spring + pop-slide · 验收记录

日期：2026-07-11

## 目标

1. layer `transform` / `opacity` 覆写通道支持 spring（`transform-spring` / `opacity-spring`）。
2. `pop-slide` style 保持可用（T04 已接线）；KDL 菜单择面启用 pop-slide，下移 4px。
3. 向后兼容：旧 `transform-duration-ms` / `transform-curve` 仍有效。

## 实现摘要

| 项 | 改动 |
| --- | --- |
| 解码 | `OptionalChannelParams`：easing **或** spring，互斥；空则继承主通道（含 spring） |
| 节点 | `transform-spring damping-ratio=… stiffness=… epsilon=…`；`opacity-spring` 同理 |
| 运行时 | `OpeningLayer` / `ClosingLayer` 已用 `transform_anim` / `opacity_anim`（T04 起），无需改驱动 |
| pop-slide | `opening_layer.rs` 两 match 臂已含 PopSlide（scale + edge/distance） |
| KDL | 菜单统一 pop-slide `distance 4` `edge "top"`（与 T22 的 origin pointer 同块，见 T22 记录） |
| 设置工具 | `LAYER_PROFILE_GROUPS`：`small_popup` 仅状态弹层；`menu` 六菜单同元组精确匹配 |
| 测试 | `parse_layer_rule_animation_channel_springs`；混合 spring/easing 拒绝；edge-reveal 语义 pytest |

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `cargo test -p niri-config -- --test-threads=1` | **36 passed**（含 channel spring / mixed reject） |
| `cargo test -p niri --lib layer_ -- --test-threads=1` | **20 passed** |
| `niri validate --config config/niri/tahoe-phase0.kdl`（本轮 debug 二进制） | **config is valid** |
| 新语法 snippet（transform-spring + pop-slide） | **config is valid** |
| `python -m pytest tahoe-shell/tests/ -x` | **147 passed** |

## 向后兼容

- 仅 `transform-duration-ms` / `transform-curve`：仍为 easing 覆写。
- 主通道 `spring` 且不写 transform 覆写：transform 继承主弹簧（既有语义）。
- 同时写 spring 与 easing 通道：decode 报错（测试覆盖）。

## 红线自查

| § | 结论 |
| --- | --- |
| 不破坏入口 | IPC/菜单 namespace 未改；仅动画 style/distance |
| 状态弹层 | battery/wifi/fan/clipboard **仍为 edge-reveal**（T04-fix2） |
| 无新协议 | 是 |
| useSpring | 本任务 compositor 侧，不涉及 QML |

## 功能不回归

- 控制中心 / 通知中心 / 侧边栏 edge-reveal 参数未动
- process/dock/topbar 菜单仍可开关；动效改为 pop-slide 4px
- motion profile 读写：`menu` 组精确匹配六 namespace

## 发现待办

- 需部署新 niri 二进制后菜单 pop-slide 才在 live 会话生效
- T22 同提交树内完成 pointer origin 与 shader preset（见 T22 验收）
