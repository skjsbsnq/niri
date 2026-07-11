# T16 · 设置控件精修 · 验收记录

日期：2026-07-11

## 目标

设置控件对齐 macOS 质感：Switch / Slider / Button / ListRow / Segmented / TextField；正文 13px。**不破坏** NiriAnimationsPage 曲线/弹簧编辑器与各页既有绑定 API。

## 实现摘要

| 控件 | 改动 |
| --- | --- |
| `TahoeSwitch` | 按压 knob 20→24 拉宽；色变 `ColorAnimation` 150ms；knob 投影 |
| `TahoeSlider` | 白色圆 knob + 投影；拖动 scale 1.12；跟手 `userSet` 不变 |
| `TahoeButton` | 主按钮实心 accent；普通实心浅灰（`buttonFillSolid`）；去描边 |
| `TahoeListRow` | 行高 ≥40；分割线内缩 12px；正文 13px；按压传到 Switch |
| `TahoeSegmented` | 实心选中/浅灰 idle；13px；无弹簧 |
| `TahoeTextField` | 字号 13px；焦点环行为保留 |

主题增量：`buttonFillSolid` / `buttonFillSolidHover`（T15 已导出到 SettingsPanel theme）。

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，126 passed**（+`test_settings_controls_polish.py`） |
| NiriAnimationsPage 仍含 spring/curve 编辑逻辑 | **是**（damping/curve canvas 未动） |
| 核心控件 body 含 `font.pixelSize: 13` | **是** |

## 功能不回归

- 控件对外 API 未改：`checked` / `userSet` / `activated` / `selected` / `text` / `toggled`
- 未引入 QtQuick.Controls
- 按下态仍走 `Motion.pressScaleFor` / `pressDurationFor`（reduced 即时）
- 设置页服务写入路径未改

## 抽查页（设计覆盖）

外观、声音/显示滑条、通知开关、Niri 动画编辑器、多任务分段、Wi‑Fi 列表行、键盘、电源。

## 审查 follow-up（同日）

| 问题 | 处置 |
| --- | --- |
| Slider 命中映射未补偿 knob 半宽 | **已修** `ratioAt()` 与 knob 行程一致 |
| Slider 阴影 `anchors.centerIn` + `y` 冲突 | **已修** `verticalCenterOffset: 1` |
| 独立 TahoeSwitch（NetworkPage VPN）无 pressed | **已修** 绑定 `vpnSwitchMouse.pressed` |

## 发现待办

- 实机：Switch 按压缩放与 Slider knob 拖动手感
- TahoeSection / AboutRow 字阶未统一到 13（非本任务清单核心六控件）
- ListRow 末行分割线可选隐藏（nit）
