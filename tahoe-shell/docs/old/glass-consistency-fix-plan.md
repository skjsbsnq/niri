# 液态玻璃一致性修复方案

日期：2026-06-15

范围：解决用户在 VMware archlinux niri 真机截图中观察到的三处玻璃效果不一致：
1. 点击启动器（Launchpad）的背景模糊和控制中心不一样，且"没有整个覆盖"，与 Dock / 顶栏格格不入。
2. 顶栏（TopBar）的模糊不是控制中心那种。
3. 拖动软件到边框时的 snap preview 模糊也不是控制中心那种。

本文档先讲清楚三处各自的根因（它们不是同一类问题），再给出每处的具体改动点、文件、风险和验收标准。改动方向已与用户确认：
- snap preview：改 niri 源码并重编译。
- 顶栏：改成浮起圆角条形态（向控制中心 / Dock 看齐）。
- Launchpad：既降 alpha，又处理与 Dock / 顶栏的层级覆盖问题。

---

## 0. 背景知识：项目里其实有两套独立的玻璃管线

这是理解"为什么三处看起来不一样"的前提。必须先讲清楚。

| | Quickshell 面板（控制中心 / 顶栏 / Dock / 各弹出面板 / Launchpad） | niri compositor 内置 UI（snap preview） |
| --- | --- | --- |
| **谁渲染** | Quickshell 作为 layer-shell 客户端，由 niri 合成 | niri compositor 自己（Smithay 层） |
| **模糊机制** | 面板声明 `BackgroundEffect.blurRegion`（Quickshell.Wayland），niri 对该 region 做背景模糊 | `FramebufferEffect` 直接对整屏 framebuffer 做 blur 后裁剪到目标矩形 |
| **玻璃参数来源** | niri config 的 `layer-rule namespace="^quickshell"` 块 + QML 面板自己的 `color` alpha 叠加 | niri 源码里写死的 `GlassOptions`（`niri/src/layout/mod.rs`） |
| **全局模糊参数** | 共用 `blur { passes 5 offset 7 noise 0.012 saturation 1.6 }` | 同样共用这套全局 blur（`BlurOptions::from(self.options.blur)`） |

**关键结论**：两条管线都消费同一个全局 `blur` 配置，所以模糊半径/次数本身是一致的。质感差异来自两处：

1. **玻璃着色参数不同**：Quickshell 面板走 `layer-rule` 的 `background-effect`（`tint 0.10 / edge 0.42 / refraction 0.022`），snap preview 走代码写死值（`tint 0.12 / edge 0.46 / refraction 0.05`）。数值其实接近，但 snap preview 的 refraction 偏高，会有更明显的"折射位移"，观感上更"水"。
2. **叠加遮罩不同**：Quickshell 面板在模糊层之上还会画一层 QML `Rectangle` 半透明色（控制中心是 `#20ffffff`=13%），snap preview 没有这层 QML 叠加，它在 framebuffer blur 之后直接用 `GlassOptions.tint` 一次性着色。

所以"控制中心那种"的视觉本质 = **全局 blur 模糊 + layer-rule 玻璃参数 + 13% 白色 QML 遮罩 + 圆角浮层形态**。任何一项偏离都会让它"不像控制中心"。

---

## 1. Launchpad 背景：降 alpha + 修层级覆盖

### 1.1 现状

`tahoe-shell/components/Launchpad.qml:48-57`：

```qml
BackgroundEffect.blurRegion: Region {
    item: backdrop
    radius: 0
}

Rectangle {
    id: backdrop
    anchors.fill: parent
    color: "#5ceef2f7"          // alpha = 0x5c = 36%
    opacity: root.open ? 1 : 0
}
```

### 1.2 两个问题

**问题 A：alpha 偏高。**
`#5ceef2f7`（36%）比控制中心的 `#20ffffff`（13%）浓了近 3 倍。Launchpad 作为全屏覆盖层，本身确实需要比浮层面板更浓的遮罩来突出图标，但 36% 已经盖住了大部分模糊质感，显得"不是控制中心那种通透"。

**问题 B：与 Dock / 顶栏"格格不入、没有整个覆盖"。**
这是用户描述的核心。根因在层级，不在颜色：

- Launchpad 是 `PanelWindow`，`aboveWindows: true`，但它是 Quickshell 的 layer-shell 面板之一。
- Dock、TopBar 是**平级的兄弟 PanelWindow**，也各自是 layer-shell 面板，各自声明自己的 `BackgroundEffect.blurRegion`。
- Launchpad 的全屏 `backdrop` 盖住了壁纸和普通窗口，但 **Dock 和 TopBar 仍然叠在 Launchpad 之上**（它们都是 overlay 层级，谁在上取决于 layer-shell 的层叠顺序，而非 Launchpad 的 `aboveWindows`）。
- 于是出现：Launchpad 打开后，Dock 和 TopBar **没有被 Launchpad 的遮罩盖住**，它们继续各自模糊自己背后的内容。三个面板"各算各的玻璃"，视觉上割裂 → 用户感觉"没有整个覆盖、格格不入"。

### 1.3 修复方案

**A. 降 alpha。** 把 `#5ceef2f7` 降到 `#30eef2f7`（约 19%）。保留比控制中心略浓（因为全屏覆盖需要更多对比来凸显图标），但显著低于现状。不要降到 13%，否则全屏遮罩太透，图标背景杂乱。

**B. 处理层级覆盖。** 两个候选做法，推荐做法 1：

- **做法 1（推荐）：Launchpad 打开时隐藏 Dock 和 TopBar。** 在 `shell.qml` 给 Dock / TopBar 加一个 `dimmed: shell.launchpadOpen` 之类的属性，当 Launchpad 打开时把 Dock / TopBar 的 `visible`（或 `opacity`）置为 false / 0。Launchpad 关闭时恢复。这样 Launchpad 真正"整个覆盖"，Dock / TopBar 不再各算各的。
  - 注意：Launchpad 自己是 `exclusiveZone: 0`，Dock / TopBar 是 `exclusiveZone: 34 / 98`。隐藏 Dock / TopBar 不影响窗口布局（Launchpad 打开时用户本就不操作普通窗口）。
  - 动画：用 `NumberAnimation`（不要 spring，VMware 软件渲染会破坏 Image 纹理，项目已有 `useSpring` 约定）。

- **做法 2（备选）：用 layer-shell 层级把 Launchpad 抬到 Dock / TopBar 之上。** 改 Launchpad 的 `PanelWindow` 层级。但 layer-shell 同层面板的叠放顺序在 niri 里不完全可控，且会把 Dock / TopBar 的玻璃也盖在 Launchpad 模糊之上（即 Launchpad 的模糊区域采样到的是 Dock / TopBar 本身，而不是壁纸），效果更乱。不推荐。

### 1.4 改动文件

- `tahoe-shell/components/Launchpad.qml`：`color` 改 `#30eef2f7`。
- `tahoe-shell/shell.qml`：Dock / TopBar 实例化处，把 `launchpadOpen` 透传进去（TopBar 已有该属性，Dock 已有）。
- `tahoe-shell/components/Dock.qml`：新增 `visible: !launchpadOpen`（或 `opacity` 动画）。
- `tahoe-shell/components/TopBar.qml`：新增 `visible: !launchpadOpen`（或 `opacity` 动画）。

### 1.5 验收

- Launchpad 打开后，屏幕上只剩 Launchpad 的全屏模糊遮罩 + 图标网格，Dock 和顶栏消失（或淡出）。
- 关闭 Launchpad，Dock / 顶栏恢复。
- Launchpad 遮罩比控制中心略浓但明显通透于现状，模糊质感可见。

---

## 2. 顶栏 TopBar：改成浮起圆角条

### 2.1 现状

`tahoe-shell/components/TopBar.qml:42-62`：

```qml
anchors {
    left: true
    right: true
    top: true
}

exclusiveZone: 34
implicitHeight: 34
color: "transparent"

BackgroundEffect.blurRegion: Region {
    item: barSurface
    radius: 0            // ← 直角全宽
}

Rectangle {
    id: barSurface
    anchors.fill: parent
    color: root.glassFill      // #1cffffff = 11%，其实 OK
    border.color: root.glassStroke
    border.width: 1
}
```

### 2.2 问题

颜色 alpha（11%）和控制中心（13%）其实接近，不是主因。主因是**形态**：

- `radius: 0` + `anchors.fill: parent` → 全屏宽、贴顶、直角的条。
- `exclusiveZone: 34` → 占满屏幕顶部，贴边到屏幕物理边缘。
- 而控制中心是 `radius: 28` + `margins.top: 36` → 浮起、圆角、四周留边。

形态不同导致：顶栏的模糊区域是贴着屏幕顶边的直角矩形，模糊的视觉边界（顶边、左右边）是屏幕硬边缘；控制中心的模糊区域四周都是圆角软边界。前者看起来"是一条贴顶的半透明带"，后者"是一块浮起的玻璃"。

### 2.3 修复方案

把顶栏改成 macOS Big Sur / Tahoe 风格的**浮起圆角条**：

1. **`barSurface` 不再 `anchors.fill: parent`**，改成四周留边距浮在 `PanelWindow` 内：
   ```qml
   Rectangle {
       id: barSurface
       anchors.fill: parent
       anchors.margins: 8          // 四周 8px
       radius: 18                   // 圆角
       color: root.glassFill
   }
   ```
2. **`BackgroundEffect.blurRegion` 的 `radius` 改成 18**，和 `barSurface` 一致（否则模糊漏出圆角外，这是项目既有约定，见 `NotificationToast.qml` 注释）。
3. **`PanelWindow` 的 `implicitHeight` 保持 34，`exclusiveZone` 保持 34**（窗口预留区不变，避免抖动窗口布局）。`PanelWindow` 本身透明（`color: "transparent"`），只有内部的 `barSurface` 是浮起圆角条。
4. 边框：参照控制中心，移除 `barSurface` 自身的 `border.width`，改用两个 inset `Rectangle` 画顶左高光 / 右下阴影边（避免圆角处抗锯齿出直角，控制中心和 Dock 都这么做）。

### 2.4 风险

- **窗口会贴到顶栏浮条下方**：因为 `exclusiveZone` 没变，窗口仍然从屏幕顶 34px 处开始排列。顶栏浮条四周有 8px 边距，意味着浮条和窗口之间会有视觉缝隙（窗口顶部内容会从浮条下方 8px 处露出来）。这是 macOS 浮起顶栏的固有取舍。如果觉得缝隙难看，可以把 `exclusiveZone` 加到 42 左右，让窗口从浮条下方开始，但要相应调 Launchpad / 控制中心的 `margins.top`。
- 现有顶栏内的 `RowLayout` 用了 `anchors.leftMargin: 18 / rightMargin: 14`，改成浮条后这些边距要相对 `barSurface` 重新调（多加 8px margins）。

### 2.5 改动文件

- `tahoe-shell/components/TopBar.qml`：`barSurface` 布局、`blurRegion radius`、边框绘制方式、内部 RowLayout 边距。

### 2.6 验收

- 顶栏变成四周留边、圆角的浮起玻璃条，形态接近 Dock。
- 顶栏模糊区域的圆角与浮条圆角一致，不漏模糊。
- 顶栏内文字、图标、按钮不被浮条边距裁切。

---

## 3. snap preview：改 niri 源码对齐玻璃参数

### 3.1 现状

`niri/src/layout/mod.rs:5128-5148`：

```rust
let glass = GlassOptions {
    tint_color: [0.86, 0.94, 1., 1.],
    tint_amount: 0.12 * alpha,
    edge_highlight: 0.46 * alpha,
    refraction: 0.05 * alpha,
};
let params = RenderParams {
    geometry: rect,
    subregion: None,
    clip: Some((rect, radius)),
    scale,
};
let elem = move_.snap_preview.effect.render(
    None,
    params,
    Some(BlurOptions::from(self.options.blur)),
    0.018 * alpha,   // 亮度参数
    1.12,            // 对比度参数
    glass,
);
```

### 3.2 问题

snap preview 走的是 `FramebufferEffect`（screen-space），不是 Quickshell 面板的 `BackgroundEffect`（region）。两者参数当前对比：

| 参数 | Quickshell 面板（layer-rule） | snap preview（源码写死） |
| --- | --- | --- |
| tint | `#ffffff` / 0.10 | `[0.86,0.94,1.0]` / 0.12 |
| edge-highlight | 0.42 | 0.46 |
| refraction | 0.022 | **0.05**（偏高，约 2.3 倍） |

差异最大的是 **refraction**：snap preview 的 0.05 比 Quickshell 面板的 0.022 高一倍多，会让 snap preview 的折射位移更明显，看起来"更水、更晃"，不像控制中心那种沉稳的磨砂玻璃。其次是 tint：snap preview 用的是淡蓝色 `[0.86,0.94,1.0]`，Quickshell 面板用纯白 `#ffffff`。

另外 snap preview 没有那层 13% 白色 QML 遮罩（它根本不是 QML），所以它的最终观感 = blur + 玻璃着色，而控制中心 = blur + 玻璃着色 + 13% 白遮罩。这是结构差异，无法靠调参数完全消除，只能逼近。

### 3.3 修复方案

改 `niri/src/layout/mod.rs` 的 `GlassOptions`，对齐 Quickshell 面板的 layer-rule 参数：

```rust
let glass = GlassOptions {
    tint_color: [1., 1., 1., 1.],      // 纯白，对齐 layer-rule 的 #ffffff
    tint_amount: 0.10 * alpha,          // 0.12 → 0.10，对齐 layer-rule
    edge_highlight: 0.42 * alpha,       // 0.46 → 0.42，对齐 layer-rule
    refraction: 0.022 * alpha,          // 0.05 → 0.022，对齐 layer-rule（关键）
};
```

为了补偿"缺少 13% 白遮罩"带来的偏淡，可以把 `tint_amount` 略提到 `0.12`（仍在合理范围），或保持 0.10 先看效果。

### 3.4 改动文件

- `niri/src/layout/mod.rs`（约 5128 行）。

### 3.5 风险与注意事项

- **需要重新编译 niri。** 项目有 fork（`niri/` 子目录）和构建脚本（`scripts/arch-update.sh` 带 `BUILD_NIRI_FORK`）。改完后在 VM 里重编译验证。
- **alpha 缩放**：现有代码所有玻璃参数都乘了 `alpha`（淡入淡出动画进度），改动后保持这个乘法，否则动画期间玻璃会突变。
- **不要动 `BlurOptions::from(self.options.blur)`**：这是全局 blur，所有管线共用，改它会影响全局。
- **不要动 `0.018` 亮度和 `1.12` 对比度**先：这两个是 framebuffer 特有的亮度/对比度后处理，Quickshell 面板没有对应项。如果对齐玻璃参数后仍偏亮，再考虑微调，但要单独验收。
- snap preview 还画了一层 `BorderRenderElement`（preview_color 填充 + 白边，mod.rs:5152-5182），那是 snap 指示色（蓝色 `#78beff`），不是玻璃遮罩，**不要动**——那是 snap 功能本身的视觉标识。

### 3.6 验收

- 拖窗口到屏幕边缘，snap preview 的玻璃质感接近控制中心（沉稳磨砂，不再"水晃"）。
- preview 的蓝色指示边框和填充色不变。
- preview 淡入淡出动画期间玻璃强度平滑变化。

---

## 4. 执行顺序与依赖

1. **Launchpad（第 1 节）**：先做。它涉及 `shell.qml` / Dock / TopBar / Launchpad 四个文件，但都是 QML，reload 即可验证，风险最低。
2. **TopBar 浮起圆角（第 2 节）**：其次。纯 QML，但会动顶栏布局，要在 Launchpad 改完（顶栏会随 Launchpad 隐藏）之后调，避免叠加干扰。
3. **Dock 配合调整（隐含）**：如果 TopBar 改浮起后，Dock 形态已经够接近，Dock 本身不用大改；只确认 Dock 在 Launchpad 打开时能正确隐藏（第 1 节的层级修复已覆盖）。
4. **snap preview（第 3 节）**：最后。改 niri Rust 源码，需重编译，验收周期最长，放在 QML 都稳了之后做。

每一步做完先在 VM 里 reload / 重编译验收，确认无回归再进下一步。

---

## 5. 不在本次范围

以下与本问题相关但本次不做，避免范围蔓延：

- **VMware 软件 GPU 下模糊是否真正生效**：如果用户反馈改完 Launchpad / TopBar 后仍"没有毛玻璃质感"，需要排查 VMware 3D 加速是否启用、niri 是否走了软件渲染路径。这是环境问题，不是代码问题。
- **全局 `blur` 参数调优**（passes / offset / noise / saturation）：本次只对齐各面板之间的差异，不动全局模糊强度。
- **窗口本身（active / inactive）的玻璃**：那是 `window-rule` 块的事，与 shell UI 玻璃是独立配置，本次不碰。
- **控制中心内部 tile 的玻璃**：tile 用的是 QML `Rectangle` 纯色（`#80ffffff`），不是模糊区域，本身设计如此，不动。
