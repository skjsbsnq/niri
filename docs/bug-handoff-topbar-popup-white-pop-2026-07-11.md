# Bug 交接：顶栏弹层下滑结束后顶部「突然变白」

日期：2026-07-11（重写；仓库已回滚到改动前基线）  
仓库：`/home/wwt/niri`  
基线 commit：`5d76958`（`main` / `origin/main` 一致，工作区干净）  
niri 子模块：`8ba964d2`（`tahoe-layer-animations`，干净）

---

## 0. 给下一任的一句话

**用户要的是「下滑过程中」和「停住后」观感一致，不是「别变白」。**  
对比组（顶栏 niri 菜单）正常，是因为动画是 **短距 pop-slide**；出问题的是 **整卡高度 edge-reveal**。  
短距 `slide` 能治白但会毁丝滑手感，用户已否决。全局改 glass/shader 会伤 Dock，用户已否决。  
正确方向：**保留 edge-reveal 运动，修玻璃在动画期间与 settle 的采样/合成一致性。**

---

## 1. 用户需求（验收标准）

### 必须满足

1. **时间一致性**  
   - 允许卡片本身偏白 / 有玻璃高光。  
   - **不允许**：下滑过程中正常，**动画结束瞬间突然更白**（用户原话：要么全程不变白，要么下滑过程中就已经是最终那套白）。
2. **保留原来的丝滑 edge-reveal 整卡下滑**（不能换成短距 slide）。
3. **不破坏其它表面**（尤其 Dock、菜单）。

### 对比基准

| 操作 | 预期参考 |
|------|----------|
| 点顶栏 **niri / 应用菜单** | **正常**（无突然变白） |
| 点顶栏 **电池 / 控制中心 / Wi‑Fi / 剪贴板** 等 | **有问题**（settle 时顶部突然更白） |

用户补充：截图上有时不明显，**实机观感更明显**；电池卡片尤其是 **标题「电池」那一行** 发白。

---

## 2. 复现步骤

1. 进入 Tahoe niri 会话（`DESKTOP_SESSION=tahoe-niri`，`NIRI_CONFIG=~/.config/niri/tahoe/config.kdl`）。
2. 打开电池弹层或控制中心。
3. 盯着卡片 **从上往下 edge-reveal** 的过程。
4. 观察：动画中途 vs **完全停下后**，顶部（标题带）是否突然更白。
5. 再开 niri 菜单对比。

IPC 示例（路径按本机）：

```bash
qs -p "$HOME/.config/quickshell/tahoe" ipc call tahoe openBatteryPopup
qs -p "$HOME/.config/quickshell/tahoe" ipc call tahoe openControlCenter
qs -p "$HOME/.config/quickshell/tahoe" ipc call tahoe closeBatteryPopup
```

---

## 3. 架构：为什么菜单没事、电池有事

### 3.1 动画配置（`config/niri/tahoe-phase0.kdl`）

| 表面 | namespace | layer-open | 说明 |
|------|-----------|------------|------|
| 控制中心 | `tahoe-control-center` | `edge-reveal` top，`opacity-from 0.84`，spring | **有问题** |
| 通知中心 | `tahoe-notification-center` | `edge-reveal` top，`opacity-from 0.86` | 同类 |
| 电池/Wi‑Fi/风扇/剪贴板 | `tahoe-battery-popup` 等 | `edge-reveal` top，`opacity-from 0.84` | **有问题** |
| 菜单 | `tahoe-menu-popup` 等 | **`pop-slide`**，distance **4**，origin pointer | **正常** |
| 左侧边栏 | `tahoe-left-sidebar` | edge-reveal left，`opacity-from 1` | 未作为主诉 |

**重要：** `style "edge-reveal"` 时，位移距离是 **整 surface 宽/高**，KDL 里的 `distance 24` **不是**短滑像素（见代码与注释）。  
实现：`niri/src/layer/opening_layer.rs` → `offset_for_size` / `edge_reveal_distance`。

### 3.2 渲染路径

1. Layer 打开动画：`niri/src/layer/mapped.rs` → `render_normal_with_open_state`  
   - `open_offset` 平移 surface  
   - `open_alpha` 乘到 surface 与 glass  
2. Tahoe 玻璃 region：`niri/src/render_helpers/tahoe_glass.rs`  
   - `material_alpha * layer_alpha` 再 **fade** tint / edge_highlight / refraction 等  
3. 材质默认 **`xray false`**（`tahoe-phase0.kdl` material panel/menu）  
   - 非 xray → `FramebufferEffect::capture_framebuffer`：**在元素当前绘制位置 blit 屏幕** 再 blur/tint  
   - 文件：`niri/src/render_helpers/framebuffer_effect.rs`  
4. 后处理高光：`niri/src/render_helpers/shaders/postprocess.frag`  
   - `top_light`、`edge_highlight` 等对顶部更亮  
5. QML：`tahoe-shell/components/GlassPanel.qml`  
   - 半透明 fill + 可选 stroke；电池用 `MaterialPanel` + `FillPanelBright`  
   - 菜单用 `MaterialMenu`（`MenuPopup.qml`）

部署：

| 角色 | 源 | 运行时 |
|------|-----|--------|
| niri 配置 | `config/niri/tahoe-phase0.kdl` | `~/.config/niri/tahoe/config.kdl` |
| shell | `tahoe-shell/` | `~/.config/quickshell/tahoe/`（常为拷贝，改源后需同步） |
| compositor | `niri/` 子模块 | `~/.local/bin/niri`（**改 C 代码后必须重启 niri 会话**） |

---

## 4. 根因候选（按优先级）

### A. 主因（最可信）：edge-reveal 运动中玻璃抓屏位置 ≠ settle

- 整卡上移再落下时，非 xray 玻璃每帧在 **当前 dst** 抓壁纸。  
- 运动中采样区域不断变化；**停住后**采样定在 rest 位置 → 顶部色调/亮度跳变。  
- 菜单 pop-slide 只动约 4px + 缩放，采样几乎不变 → 无此感。  
- **实验证据：** 改成短距 `slide` 后用户反馈「变白确实好了，一直都是白的」，但「动画坏掉了」→ 强相关于「运动幅度 / 采样变化」，而非单纯「玻璃太白」。

### B. 次因：`opacity-from 0.84 → 1` 与材质双重淡化叠加

- `open_alpha` 同时影响：  
  1. 最终 element 透明度  
  2. `tahoe_glass` 里 tint / edge_highlight 的 fade（随 `layer_alpha` 抬升）  
- settle 时 alpha=1 → 白 tint + 高光一次性抬满 → 非线性「啪一下变白」。  
- 仅把 `opacity-from` 设为 `1.0` **不足以**让用户验收通过（已试过仍报问题），说明 **A 仍存在** 或还有其它因素。

### C. 较弱：QML 半透明白 fill/stroke 叠在 compositor 白 tint 上

- 测过：`StrokePanel #24` 叠在玻璃上可解释 **1px 级** 亮边。  
- 用户描述的是 **标题整带** 主观变白，单靠去描边不够，且易误伤全局。

### 不要再优先当成主因

- 只调 1px 描边 inset/outer。  
- 全局砍 `postprocess.frag` 的 `top_light`（Dock 等会变）。  
- 全局改默认 material 强度（用户曾因 Dock 变化要求整段撤回）。

---

## 5. 已失败方案（不要重复）

| 方案 | 结果 | 用户态度 |
|------|------|----------|
| GlassPanel 描边 outer-aligned | 无效 | — |
| 玻璃启用时关 QML stroke / 白 fill | 像素尖峰可降，主观 pop 仍在 | 不行 |
| KDL `opacity-from 1` + `opacity-duration-ms 0`（保留 edge-reveal） | 逻辑上关 alpha ramp | **仍报白 pop** |
| edge-reveal → 短距 `slide distance 28` | 白一致性变好 | **否决：动画毁了** |
| 全局改 `tahoe_glass` material fade + shader top_light | 未验收通过 | **否决：Dock 等变了** |
| compositor `sample_offset` 钉抓屏（绘制跟动画、capture 钉 rest） | 已实现并装过 binary | **仍报未修好**（可能未重启会话 / 实现有坐标 bug / 不完整） |

所有相关 commit 与脏改动已 **全部撤回**：

- 本地 + 远程 `main` = `5d76958`  
- 子模块干净  
- 二进制曾恢复到改动前备份（接手时请再确认 `~/.local/bin/niri` 与会话是否一致）

---

## 6. 建议修复路线

**目标：edge-reveal 手感不变 + 动画中任意时刻与 settle 玻璃观感一致。**

### 推荐顺序

1. **先建立可重复测量**  
   - mid-anim vs settle 抓帧（`grim`），对标题带 mean RGB。  
   - 确认运行中的 niri PID 启动时间 ≥ 你安装的 binary mtime。

2. **优先：运动中玻璃采样与 settle 一致（保留 edge-reveal）**  
   - 方向 A：非 xray capture 时使用 **rest 位置** 采样（`sample_offset = -open_offset` 一类），绘制仍跟 `open_offset`。  
     - 接入点：`mapped.rs` 的 open 路径 + `FramebufferEffect::capture_framebuffer`。  
     - 注意：scale（本机常见 1.25）、transform、sample padding、clip、close 动画对称。  
     - 仅对 edge-reveal 启用，避免误伤其它 layer 动画。  
   - 方向 B：edge-reveal 改为 **表面固定 + crop 揭开**（若产品接受），geometry 始终在 rest，抓屏自然一致。  
     - 工作量大，需回归左侧边栏等所有 edge-reveal。  
   - 方向 C：打开动画期间用固定 backdrop / 临时 xray，避免 blit 运动中的 screen 内容。

3. **次要：若仍有 alpha 相关非线性**  
   - 相关弹层可保持 `opacity-from 1`（全程不透明），与左侧边栏一致。  
   - 或：`layer_alpha` **只**乘最终 alpha，**不要**再 fade material 参数（改 `tahoe_glass.rs`，需评估 toast/其它依赖 material_alpha 的路径）。  
   - 同步 `niri_settings_tool.py` 的 `MOTION_PROFILE_LAYERS`，避免设置页写回 0.84。

4. **明确禁止作为默认方案**  
   - 短距 `slide` 顶替 edge-reveal。  
   - 全局改 glass 默认材质 / 全局改 postprocess 高光。  
   - 只改 QML 描边就交差。

### 验收清单

- [ ] 电池、控制中心：edge-reveal 手感 ≈ 当前基线（用户认可的丝滑）。  
- [ ] 下滑中途与 settle：标题带无「结束瞬间突然更白」。  
- [ ] 菜单 pop-slide 无回归。  
- [ ] Dock 无回归。  
- [ ] 深色/浅色壁纸、scale 1.25 各测一次。  
- [ ] `pytest tahoe-shell/tests/test_edge_reveal_semantics.py`  
- [ ] `pytest tahoe-shell/tests/test_niri_settings_tool.py`  
- [ ] niri `layer_shell` 相关 unit tests（若动了 compositor）

---

## 7. 关键文件索引

| 路径 | 作用 |
|------|------|
| `config/niri/tahoe-phase0.kdl` | layer-rule 动画、tahoe-glass 材质 |
| `~/.config/niri/tahoe/config.kdl` | 运行时配置 |
| `niri/src/layer/opening_layer.rs` | edge-reveal 位移语义 |
| `niri/src/layer/mapped.rs` | 打开动画 + 玻璃渲染入口 |
| `niri/src/render_helpers/framebuffer_effect.rs` | 非 xray 抓屏 |
| `niri/src/render_helpers/tahoe_glass.rs` | material_alpha / layer_alpha / 材质 fade |
| `niri/src/render_helpers/shaders/postprocess.frag` | tint / edge_highlight / top_light |
| `niri/src/render_helpers/xray.rs` | xray 采样（对比路径） |
| `tahoe-shell/components/GlassPanel.qml` | QML fill/stroke |
| `tahoe-shell/components/BatteryPopup.qml` | 问题组 |
| `tahoe-shell/components/ControlCenter.qml` | 问题组 |
| `tahoe-shell/components/MenuPopup.qml` | 正常对比组 |
| `tahoe-shell/services/niri_settings_tool.py` | motion profile 写 KDL |

---

## 8. 仓库与环境现状（交接时）

- Git：`main` @ `5d76958`，与 `origin/main` 同步，**无未提交改动**。  
- 历史错误 commit（`51f4276`、`d380de1`）已从远程 force 抹掉。  
- 所有实验性 compositor / KDL / GlassPanel 改动已回滚。  
- 下一任应从本基线 **重新实现** 正确修复，并遵守第 1、6 节约束。

---

## 9. 用户原话摘要（语义锚点）

- 「下滑过程中没有，下滑完成才变成这样。」  
- 「不能破坏原有功能。」  
- 「我不反对变白，我要求的是一致性；要么不变白，要么下滑过程中就变白。」  
- 「为什么 niri 图标弹出来的卡片就没有问题？」  
- 「变白确实好了，但他妈动画坏掉了。」（对短 slide 方案）  
- 「Dock 栏好像发生了变化。」（对全局 glass/shader 方案）

---

## 10. 2026-07-12 实际修复结果

### 已确认根因

- `4c088f83` 为 edge-reveal 引入固定 reveal crop；`c205293c` 又为 Tahoe
  Glass 扩大 blur/refraction 采样区。外层 `CropRenderElement` 不只裁最终绘制，
  还会裁 `FramebufferEffect` 的 `src`，导致动画中采样纹理缺少 padding。
- 弹簧位置约 252ms 已停在最终位置，但动画生命周期约 459ms 才结束；结束帧
  移除 crop 后，完整 padding 突然恢复，标题带因此出现一次整体变白。
- 补丁版/旧版使用同一嵌套配置做 A/B：补丁版在原跳变时间没有亮度跃迁，
  旧版可稳定复现；用户也确认旧版测试发白、补丁版测试不发白。
- `ed9ea3c` / niri `8ba964d2` 的性能优化不是这次白闪的直接根因，但其
  `0.02` 服务端模糊比较会吞掉 Wayland fixed 的 `251/256 -> 1.0` 相邻档位，
  已恢复精确比较并加入回归测试。

### 实现

- 为 framebuffer effect 增加仅作用于最终 draw/damage 的 `draw_clip`；capture
  始终保留 Tahoe Glass 完整扩展采样区和纹理映射。
- edge-reveal 的 open/close Tahoe Glass 非 xray 路径改用内部 `draw_clip`，
  Wayland 内容、shadow、solid color 与 xray 继续使用原外层 crop。
- `82d2dd1a` 曾把 `tahoe-tray-menu` 错并入 niri 菜单的 pointer pop-slide；
  现已把第三方托盘菜单移回顶部 edge-reveal，并同步设置写入器和回归测试。

### 验证与部署

- `cargo test -p niri --lib -- --test-threads=1`：249 passed。
- `python3 -m pytest -q tahoe-shell/tests`：156 passed，94 subtests passed。
- Tahoe Glass guardrails、release config validate、`git diff --check` 均通过。
- release 已安装到 `~/.local/bin/niri`；配置和设置工具已同步到运行路径。
- 配置已由当前会话成功热重载，因此托盘菜单规则立即生效；白闪修复需要重新
  登录以启动新 compositor。部署前文件备份位于：
  `~/.local/state/tahoe-niri/backups/topbar-popup-20260712-004652/`。
