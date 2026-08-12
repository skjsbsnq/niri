# A8 审查记录

日期：2026-08-12
子代理数：2

## 各子代理结论

### 子代理 1（Lorentz）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：
  1. 浅色 `textSecondary`（#721d1d1f）叠近白玻璃对比度约 2.7:1，低于
     WCAG AA 小字号；但为项目既有 SettingsTheme 令牌（全 shell 通用），
     且 macOS secondaryLabel 同样低对比，非 A8 回归。
  2. 浅色充电绿 #34c759 白底对比约 2.2:1；macOS 系统色、1:1 复刻偏差点。
  3. WeatherWidget 注释算术错误（注释写 50，表达式 14+14+14+6=48）。
  4. 库预览井圆角像素值与桌面卡片不同（同公式，预览缩放所致）。
  5. qmllint 本环境无 QtQuick 导入路径，无法独立核验告警数。
- 已核查无问题：G-6、G-5、G-7、G-8、P-1、P-3、A-C3、A-C4、完成判据
  （含 darkMode 绑定链完整、无硬编码白字残留、几何 720–1600 bad=0、
  widgetRadius 边界安全）。

### 子代理 2（Cicero）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：
  - P1：Weather 几何不等式在逻辑宽 <360 时不成立（测试只扫高度、固定
    1920 宽）；320 宽会裁「今日」行（clip 兜底，不重叠）。
  - P2：逐时条内容高可能超出 hourlyH 46 约 2–8px（字体隐式行高）。
  - P3：视觉契约测试正则偏脆（只会误报失败，不会误报通过）。
  - P4：WeatherWidget 注释过时；test_widget_preview.py loadedSource 断言
    弱（A8 前既有）。
- 已核查无问题：测试诚实性、macOS 契约（填充/描边/曲率）、颜色自适应
  完整、QML 运行时（default property/regionRadius 类型/\\ue1db 转义）、
  几何（1920 宽全高度通过、Calendar cellH 不溢出）、回归（1177 passed、
  无 SpringAnimation、无 duration 字面量）、G-6/文档一致性。

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| 逐时条内容可能超出 46px（字体行高） | PLAUSIBLE | 已修：逐时文本显式高度 12/16/13 + spacing 4 = 45 ≤ 46 | WeatherWidget.qml 逐时 delegate |
| WeatherWidget 注释过时/算术错误（50px、=50） | PLAUSIBLE | 已修：注释更新为 46/12/48 | WeatherWidget.qml 视觉段注释 |
| 浅色 secondary 对比度 2.7:1 | PLAUSIBLE | 不修：项目既有 SettingsTheme 令牌，全 shell 通用；macOS secondaryLabel 同阶；非 A8 回归 | Widget.qml:66 / SettingsTheme.js:20 |
| 浅色充电绿对比度 2.2:1 | PLAUSIBLE | 不修：macOS 系统色 1:1 复刻；人工验证判据 | BatteryWidget.qml:65 |
| 逻辑宽 <360 时「今日」行被 clip 裁切 | PLAUSIBLE | 不修：A3 起 clip 为极端矮屏设计不变式（只裁不重叠）；测试与路线图支持范围为逻辑宽 ≥360 | WeatherWidget.qml topArea clip |
| 视觉契约测试正则偏脆 | PLAUSIBLE | 不修：只误报失败不误报通过；防旁路由 Widget.qml 字符串断言 + 颜色区间断言共同承担 | test_widget_dock_visual_contract.py |
| 库预览井圆角像素与桌面不同 | PLAUSIBLE | 不修：同公式按比例缩放为预期行为（预览井尺寸更小） | LeftSidebarWidgetLibrary.qml:362 |
| qmllint 本环境无法解析 QtQuick | PLAUSIBLE | 记录：环境缺导入路径；逐文件对比 HEAD 无新告警类别、无语法错误（exit 0） | 见「完成判据核对」 |

## 完成判据核对

| 判据（引 roadmap A8） | 是否满足 | 证据 |
|---|---|---|
| 深/浅外观下均为 macOS 风格玻璃卡片，文字对比度正确 | 是（人工验证待部署） | 自适应填充 #3dffffff/#e6ffffff + 描边 + widgetRadius；darkMode 绑定链 shell.qml:923 → WidgetHost.qml:40/271 → Widget.qml:58/65-67，切换即时跟随 |
| 编辑模式删除徽标与「完成」胶囊风格正确 | 是 | Widget.qml 删除徽标（22px 深灰圆 + 白 −，z:20 右上）；WidgetHost.qml 完成按钮 radius: height/2 自适应 |
| 库预览井圆角与桌面卡片曲率一致 | 是 | LeftSidebarWidgetLibrary.qml:362 widgetRadius(selectedSize, min(previewW, previewH)) |
| qmllint --bare 无新增告警 | 是（环境受限） | /usr/lib/qt6/bin/qmllint --bare 全部 exit 0、无 [syntax]/[error]；逐文件对比 HEAD：无新告警类别（仅环境 import 解析类） |
| pytest 全绿（含更新后的视觉契约测试） | 是 | `python -m pytest tests/ -q` → 1177 passed, 1204 subtests passed |
| widgets 目录无 SpringAnimation、无硬编码 duration 字面量 | 是 | grep 均空 |
| 回归：A2–A7 结构测试全绿（拖动/resize/添加/删除/持久化/mask/预览） | 是 | 全量 1177 passed；拖动/resize 四状态代码未触碰 |

## 最终结论
全部子代理 APPROVE；CONFIRMED 为 0；PLAUSIBLE 已修 2 项、记录不修 6 项。
允许 commit。
