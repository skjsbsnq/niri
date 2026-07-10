# T04-fix2 · 动效问题二次修复验收

日期：2026-07-10
子模块提交：`1f29aa22`
父仓提交：本记录所在提交
前置失败方案：`4b51a072` / `3d68db1`

## 验收结论

- **顶栏弹层：实机通过。** 用户确认顶栏动画问题已经修复。
- **Genie minimize/restore：实机通过。** restore 不再凭空伸出一大截，目标方向正确。
- **窗口 open/close：实现与自动化通过，真实会话待部署复验。** 新二进制尚未替换当前运行中的 compositor；用户将在本地部署并重登后确认最终观感。
- 用户要求停止追加测试，按现有自动化、嵌套会话结果和上述手测结论完成验收并推送。

## 第一次修复为何失败

| 面 | 实际根因 | 第一次修复的缺口 |
|---|---|---|
| 顶栏 7 类弹层 | `pop-slide` 只移动 10px，并从 layer-shell 的 top-left anchor 缩放；该 anchor 不是点击按钮，缩放还会拉伸已采样玻璃 | 只新增 style，没有对照控制中心的整面板 reveal 语义 |
| Genie restore | 有效 Dock rect 已传入，但 `260ms emphasized-decel` 在首帧推进过大；Dock 上报 56×58 整个按钮且可能带 autohide 屏外位移 | 仅移除 restore 淡出，没有修首帧时间进度和目标矩形 |
| 窗口开关 | 0.92/0.90 缩放过重；custom shader 扩大 open 绘制区并让 close 覆盖完整输出；spring 生命周期仍有长尾 | 参数更激进，反而放大卡顿和突兀感 |
| layer 快速重开 | close snapshot 被直接删除，open 从配置初态重新播放 | 只验证对象释放，没有验证相邻帧视觉连续性 |
| 快照开销 | 无 block-out 规则时仍渲染第二份 blocked-out snapshot | 第一次修复未审计该路径 |

## 最终修复

| 面 | 修复 |
|---|---|
| 顶栏弹层 | battery / wifi / fan / clipboard / niri menu / application menu / tray menu 共用控制中心同款 top `edge-reveal`；移除 `pop-slide`、scale 和错误 origin |
| Genie restore | `window-restore` 改为 `300ms linear`，让两段式 shader 自己控制形变；Dock 上报实际 icon/preview 变换后边界，扣除 autohide 位移，并在 bounce 前锁定 rect |
| 窗口 open/close | niri 新增 `scale-from` / `scale-to` 原生配置；Tahoe 使用 open `220ms 0.97→1`、close `180ms 1→0.97` 的 bounded scale+fade，移除 active custom shaders |
| layer 连续性 | close→reopen 捕获当前 alpha / scale / offset，新的 open 从该状态插值到最终状态；EdgeReveal crop 保持固定 surface rect |
| 渲染开销 | closing window、closing layer、genie 三条路径仅在 `block_out_from.is_some()` 时生成 blocked-out texture |
| 治理 | motion profile 写入器同步顶栏 popup 参数；新增 KDL、Dock rect、恢复顺序和 layer 连续性回归测试 |

## 已完成验证

| 命令/场景 | 结果 |
|---|---|
| `cargo fmt --all -- --check` | 通过；仅 stable rustfmt 对仓库既有 nightly 选项的提示 |
| `cargo check --workspace --all-targets` | 通过 |
| `cargo test -p niri -p niri-config -- --test-threads=1` | niri **245 passed**；niri-config **31 passed**；wiki parse **1 passed** |
| `python -m pytest tahoe-shell/tests/ -q` | **81 passed, 67 subtests passed** |
| `scripts/check-genie-minimize-phase7-8.sh` | 4 组自动化过滤器全部通过 |
| 新构建 `niri validate --config config/niri/tahoe-phase0.kdl` | `config is valid` |
| `cargo build --release --locked` | 通过 |
| 隔离 winit niri + 仓库版 Quickshell | 配置加载成功，无本轮新增 QML 属性/类型错误；仅保留 T00 已记录的既有 warning |
| 顶栏逐帧抽查 | battery 首张可见帧只露出顶部下滑内容，随后完整展开；与控制中心同为整面板 top reveal，不再首帧近乎完整出现 |
| 窗口逐帧抽查 | open 首帧为接近最终尺寸的淡入；close 首帧保持接近原尺寸后淡出，无 0.90 激进收缩和全输出 shader 路径 |

补充：niri 的 layer-shell 测试夹具共享动画时钟，全量并行运行会随机污染 4 个既有用例；同一完整测试集固定 `--test-threads=1` 后 245/245 通过。该现象不是本轮运行时回归。

## 手测矩阵

| 项 | 状态 |
|---|---|
| 顶栏弹层总体观感 | **用户确认通过** |
| Genie minimize / Dock restore | **用户确认通过** |
| window open / close 真实会话观感 | **待本地部署并重登后复验** |
| 其余扩展矩阵 | 按用户指示跳过 |

## 部署

本轮配置包含旧 compositor 不认识的 `scale-from` / `scale-to`，必须让新二进制与新配置一起生效，不能只热重载 KDL：

```bash
git pull --recurse-submodules
FORCE_NIRI_BUILD=true bash scripts/arch-update.sh
```

完成后退出并重新进入 Tahoe Niri 会话，再复验窗口打开/退出动画。当前运行中的 compositor 未被本轮验收替换。

## 回滚

父仓执行 `git revert <T04-fix2 父仓提交>`；若单独维护 niri 分支，则对子模块提交 `1f29aa22` 执行 `git revert 1f29aa22`。

## 结论

第一次修复记录已标为实机失败历史；二次修复覆盖用户反馈的四条根因链路。顶栏与 Genie 已由用户实机确认，窗口开关保留部署后观感复验项，本轮按用户指示完成验收并推送。
