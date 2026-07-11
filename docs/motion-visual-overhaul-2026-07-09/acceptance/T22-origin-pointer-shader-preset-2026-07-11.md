# T22 · niri fork：origin "pointer" + shader preset · 验收记录

日期：2026-07-11

## 目标

1. layer 动画 `origin "pointer"`：缩放原点跟 seat 指针（打开瞬间捕获）。
2. window open/close `custom-shader` 支持命名 preset，减少 KDL 内嵌 GLSL。
3. **不新建协议**——仅复用 seat pointer + 既有 custom-shader 字符串通道。

## 实现摘要

### origin "pointer"（未降级）

| 项 | 实现 |
| --- | --- |
| 解码 | `LayerAnimationOrigin::Pointer`；KDL `origin "pointer"` |
| 捕获 | `State::pointer_location_on_output`：`seat.get_pointer().current_location()` − output global loc |
| Open | `OpenAnimation::new_with_pointer`；`OpenAnimationState::origin` 用绝对坐标作 pivot |
| Close | `ClosingLayer` 存 `pointer_origin`；buffer-local = absolute − pos |
| 回退 | 无指针 → Center |
| 协议 | **无**新 Wayland / tahoe-glass 字段 |

### shader preset

| 项 | 实现 |
| --- | --- |
| 名称 | `scale-fade` / `tahoe-scale-fade` |
| open | scale 0.965→1 + smoothstep 淡入（`niri_clamped_progress`） |
| close | scale 1→0.97 + 淡出 |
| 解析 | `resolve_open_shader` / `resolve_close_shader`；内联 GLSL（含 `{`/`(`/空格）原样通过 |
| 接线 | `niri.rs` 热重载 + `winit`/`tty` 初始化走 `resolved_custom_shader()` |
| Tahoe 默认 | 仍用原生 `scale-from`/`scale-to`（T04-fix2），**不**强制启用 custom-shader |

### KDL

全部菜单（menu/application/tray/process/dock-app/dock-window）统一：

```
style "pop-slide"
origin "pointer"
edge "top"
distance 4
```

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `cargo test -p niri-config` | **36 passed**（`parse_layer_animation_origin_pointer`、`resolve_window_shader_presets`） |
| `cargo test -p niri --lib layer_` | **20 passed** |
| `niri validate` tahoe-phase0 + pointer/transform-spring snippet | **valid** |
| pytest 全量 | **147 passed** |

## 协议评估（降级出口）

| 方案 | 结论 |
| --- | --- |
| 新建 protocol 传锚点 | **不需要** |
| 既有 tahoe-glass region | 不承载点击点 |
| seat pointer | **采用**；菜单在点击后 map，指针仍在点击附近 |

## 红线自查

| § | 结论 |
| --- | --- |
| 不新建协议 | 是 |
| 玻璃 region 禁弹簧 | 未改 region 几何 |
| 不破坏功能 | 菜单/窗口 IPC 不变；preset 可选 |
| 状态弹层 | 仍 edge-reveal |

## 等效性

- preset `scale-fade` 与历史 T02 内嵌 scale+fade GLSL 同结构（progress 驱动 scale/fade）。
- Tahoe 生产路径继续原生 scale+fade（无 custom-shader），避免 T04-fix2 已修的大绘制区问题；preset 供需要时 KDL 一行启用。

## 功能不回归

- `origin "center"` / `"anchor"` 行为不变
- 内联 `custom-shader r"…"` 仍可编译
- 菜单 open/close 仍可用；缩放原点改为点击附近

## 发现待办

- 部署新 niri 后手测：菜单应从点击点长出
- 多输出边界：指针在输出外时用 local 坐标仍可能偏，已接受 finite 坐标
- live close effects 路径对 Pointer 回退 Center（无捕获点）
