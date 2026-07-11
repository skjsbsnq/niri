# T10 · 控制中心去 chrome + 控件手感 · 验收记录

日期：2026-07-11

## 实现范围

### 1. Motion.js tokens（唯一出口）

| token | 值 |
| --- | --- |
| `ccPanelWidth` | 330 |
| `ccTilePressScale` | 0.97 |
| `ccSliderKnobDragScale` | 1.15 |
| `ccToggleBounceMs` | 200 |
| `ccToggleColorMs` | 200 |

### 2. ControlCenter.qml

| 项 | 结果 |
| --- | --- |
| 标题行 + X 关闭钮 | **已删除**（macOS Control Center 无 chrome） |
| 面板宽 | `Motion.ccPanelWidth`（330，原 360） |
| GlassSlider | 白色圆 knob + 软投影；拖动 `scale` → 1.15（reduced 无缩放） |
| ConnectivityTile | hover 提亮 / 按下暗 + `ccTilePressScale` 0.97 |
| MusicTile | hover 提亮；transport 仍用 `pressScaleFor` |
| ToggleCircle | `active` 变化 SequentialAnimation 1→0.9→1；`ColorAnimation` 200ms |
| 玻璃 region | 无 `SpringAnimation`；展开行高度仍 `emphasizedDecel` NumberAnimation |

### 3. 保留功能（不回归）

- Wi-Fi 整贴 toggle / 蓝牙圆钮 / 飞行模式
- 亮度 / 音量滑块 → `Controls.setBrightness` / `setVolume`
- 媒体 prev / play-pause / next
- 「编辑控制项」折叠行（深色/夜览/计算器/计时器/相机）
- `closeRequested` 信号仍由 shell 点外 / IPC 关闭（无 X 钮，不删关闭路径）
- `WlrLayershell.namespace: tahoe-control-center` 不变

### 4. 治理测试

- `test_motion_exports_control_center_feel_tokens`
- `test_control_center_dechrome_and_control_feel`
- `test_phase_b_press_feedback_uses_motion_single_outlet`：`ControlCenter.qml` pressScaleFor 计数 8→6

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，94 passed**（+2 相对 T09） |
| quickshell 冒烟 | 会话已有运行实例（`An instance of this configuration is already running`）；源码静态无 Spring 护栏违规 |

### 机械验证

```
rg -n '控制中心|closeButton|ccPanelWidth|ccTilePressScale|ccSliderKnobDragScale|toggleBounce' \
  tahoe-shell/components/ControlCenter.qml
→ 无「控制中心」标题；无 closeButton；token / toggleBounce 命中

rg -n 'SpringAnimation' tahoe-shell/components/ControlCenter.qml
→ 无匹配
```

## 手测矩阵（代码路径自查 + 实机建议）

| 项 | 结论 |
| --- | --- |
| 亮度/音量拖动 | 仍即时 `userSet` → service；knob 跟 fill 绑定 `clampedValue` |
| Esc/点外关闭 | shell `controlCenterOpen` / dismiss 路径未改 |
| 深浅色 | `darkMode` 色表保留；knob 恒白 |
| reduced | 磁贴/knob 缩放退化为 1；Toggle bounce 跳过；ColorAnimation duration 0 |

## 性能

- 本任务仅改 CC 控件反馈，无新常驻 surface / 无轮询 Timer。
- RSS 检查点留给 T12 阶段末。

## 发现待办

- T11：Wi-Fi / 蓝牙磁贴 morph 展开列表（复用 Controls 既有列表能力）。
- 实机：需 reload quickshell 后目测 knob 跟手与 Toggle 弹跳。
