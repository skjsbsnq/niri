# 渲染性能与流畅性研究报告（2026-07-26）

> 全程只读研究结论。三方对象：Noctalia v5（`~/Downloads/noctalia-main`）、本仓 quickshell fork（`quickshell/`）、本仓 tahoe-shell（`tahoe-shell/`）与 niri fork（`niri/`）。所有结论附源码证据。配套实施计划见同目录 `roadmap.md`。

## 一、Noctalia v5 "切换到 OpenGL" 的真相

v5 不是把 Quickshell 切到 OpenGL——它**完全抛弃了 Quickshell/QML**，重写为纯 C++ 原生 Wayland 客户端：

- Meson 构建、自研 `poll()` 主循环（`src/app/main_loop.cpp`，PollSource 抽象 + 空闲剖析器 `NOCTALIA_IDLE_PROFILE`）
- 自己实现 wlr-layer-shell（`src/wayland/layer_surface.cpp:92`）、fractional-scale + viewport
- EGL + GLES2 直渲（`src/render/gl_shared_context.cpp:80-108`），自研保留模式场景图（`src/render/scene/node.h`）与控件树（`src/ui/controls/`）
- 文本 Pango/Cairo + LRU 纹理缓存（`cairo_text_renderer.h:92-177`），插件 Luau 脚本经 keyed reconciliation 映射到 C++ 控件
- 全源码 grep 无一处 QML/Qt 残留

### 流畅性关键机制（附证据）

1. **空闲零帧**：只有场景图标脏才渲染/commit（`surface.cpp:1339` `queueRenderIfNeeded`，注释 "Frame loop stops here when idle"）。
2. **动画活跃但像素未变时只续 frame callback、不重绘不换 buffer**（`surface.cpp:1349-1361`）。
3. **`eglSwapInterval(0)` + `wl_surface.frame` callback 起搏**（`gles_render_backend.cpp:298-303`）：swap 永不阻塞主循环，节流权交给合成器；动画按 frame callback 步进（`surface.cpp:1310`），天然锁刷新率。
4. **模糊优先走 `ext_background_effect` 合成器协议**（`surface.cpp:627-653`），客户端零 GPU 成本；另有 FBO 缓存层（`cached_layer.h`）、blur 结果缓存（`blur_cache.h:18-30`）、GL 状态去冗余（`gles_render_backend.cpp:416-501`）。
5. 动画本身朴素：wall-clock easing 查表（`animation.cpp:5-46`，OutCubic/OutBack 等），**无弹簧物理**——丝滑来自帧调度稳定，不是曲线复杂。
6. **没有 partial damage**：脏帧仍全帧重绘——靠"少出帧"而非"小出帧"取胜。

## 二、现有体系诊断

### quickshell fork（渲染层）

- 未碰 Qt 渲染循环/RHI；每个 PanelWindow = 独立 QQuickWindow + 独立渲染线程（Qt threaded loop per-window，`qsgthreadedrenderloop_p.h:67`）。
- 无 damage，整窗重绘；QtQuick 脏驱动空闲时可零帧。
- 核心魔改 = tahoe_glass 协议客户端（模糊下放 niri、region 增量 diff + 量化 + changed-only 提交）——等价于 Noctalia 的合成器侧模糊，**最大的杠杆已经拉了**。
- `QSG_USE_SIMPLE_ANIMATION_DRIVER` 被上游刻意禁用（`launch.cpp:244-252`，QTBUG-126099），勿开。
- 已暴露 per-window `updatesEnabled`（`windowinterface.hpp:151` → `QQuickWindowPrivate`）。

### tahoe-shell（QML 层）

省电门控普遍做得好（`pollingActive`、`visible: open`、无高频常驻 Timer、模糊全在合成器侧）。问题按嫌疑排序：

1. **缩略图解码风暴（打开动画卡顿最大嫌疑）**：`WindowOverview.qml:1041`、`TaskSwitcher.qml:569`、`Spotlight.qml:698`、`DockMinimizedWindow.qml:206` 的截图 `Image` 无 `sourceSize` 且 `cache: false`——打开瞬间全分辨率（可达 4K）解码 + 逐张贴图上传。
2. **常驻全宽透明层 ×2**：`DynamicIslandOverlay.qml:717-731`（Overlay 层全宽 ×220px 透明）叠在全宽 TopBar 上，每帧两条全宽 blend。
3. **玻璃 region 几何动画期间 niri 每帧重算 live blur**（见下）——面板展开掉帧的合成器侧根源。
4. 每屏预实例化约 26 个 PanelWindow（换零创建卡顿，代价线程/内存）。
5. 外部因素：`linux-wallpaperengine` 常驻 ~9.2% CPU（quickshell 均值 ~2.9%）。

### niri fork（合成器层）

- blur 已是 dual-kawase（`render_helpers/blur.rs`，down/up 金字塔）。
- **xray 路径已有完整 blur 结果缓存**（`effect_buffer.rs:233-257`：OutputDamageTracker + `blurred` 复用）；**但玻璃默认 `xray: false` 走 live 路径**（`framebuffer_effect.rs` 每帧 blit + 全套金字塔，无缓存判据）。
- layer surface open/close 动画**已自研完成**（`layer/opening_layer.rs`/`closing_layer.rs`/`mapped.rs`：spring 双通道、per-layer rule、pointer origin、close 冻结 glass region）。
- 合成器内交互 UI 有成熟样板（`ui/screenshot_ui.rs`、`ui/mru.rs`：命中测试 + spring + 纹理元素）。
- fork 已与上游软脱钩（squash 基线 c7ed718c + 93 提交，深改 layout/niri.rs），继续下沉不加重同步负担。
- tahoe_glass 协议 v3 已传 per-region 动画标量（interaction/material_alpha 由合成器侧做材质动画，`render_helpers/tahoe_glass.rs:289-312`）——"client 报状态、合成器执行动画"已部分走通。

## 三、三条大改路线结论

### 路线一：留在 Qt，深改 quickshell

- **partial damage 死路**：Qt 6.11.1 RHI 无 damage 通道（`qrhi.h` 无相关项；qt-wayland EGL 插件仅 `eglSwapBuffers`）。补齐等于替 Qt 写多年未做的功能，随版本碎裂。
- **唯一值得的核心投资：自定义单线程 QSGRenderLoop**。`QSGRenderLoop::setInstance()` 可注入（Q_QUICK_EXPORT，首窗前调用）；参考 QSGThreadedRenderLoop 实现"单渲染线程轮询多窗、按各窗 frame callback 起搏"——渲染线程 32→1，消线程栈/GL context/切换开销，可跨窗帧对齐。fork 本已链 QuickPrivate（CMakeLists.txt:114,130），增量风险可接受。
- QQuickRenderControl（约 2 人月）与混合直渲（双栈维护税）性价比低，不采纳。

### 路线二：视觉/动画下沉 niri（性价比最高，主路线）

按收益/成本排序：
1. **live blur 结果缓存**：给 `framebuffer_effect.rs` 加"blit 区域无 output damage 则复用 blurred"判据（effect_buffer.rs 有现成范式），约 200–400 行。swayfx/Hyprland 均为此惯例。
2. **弹层动画收尾**：合成器侧已完工，QML 侧删除自有进出场动画、改静态提交 + interaction/material_alpha 状态过渡。
3. **变换动画下沉协议**：tahoe-glass 扩 `set_transform_target(x,y,scale,spring)`，动态岛形变/Dock 放大改为 client 静态 buffer + 合成器 spring 变换（复用 OpenAnimation/Rescale/RelocateRenderElement/R16 稳定 identity，约 500 行）。顺带消掉动画期 blur 大头（源不变可对 blur 结果变换采样）。需决策 glass region 随变换的模式（冻结跟随 vs 逐帧重映射；closing_layer 已有冻结模式）。
4. 动画期 blur 降采样档位：做完 3 后收益缩水，作兜底。
5. **不做**完整合成器内 Dock/ControlCenter：输入语义/图标主题/无障碍全需 Rust 手写；生态共识（COSMIC/fht）是"效果下沉、内容留 client"。

### 路线三：全量重写（Noctalia 式）

MIT 许可可自由复用；模块覆盖广（bar/dock/launcher/lockscreen/overview/switcher/tray/niri 适配器全有）；本 niri fork 已实现 `ext_background_effect` 服务端（`niri.rs:2652`），Noctalia 理论上可直接跑。但其动画无弹簧、液态玻璃/动态岛需整体重写，数人月级且丢失 QML 迭代速度。**从流畅性收益/成本看排最后**——Noctalia 的核心优势经路线二在现架构内几乎都能拿到。

## 四、最终采纳

**路线二全部 + 路线一的单线程 render loop 核心投资**，外加 QML 侧速效项（缩略图 sourceSize 等）。实施顺序、任务拆分与流程约束见 `roadmap.md`。
