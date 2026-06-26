# Left Sidebar LS08 验收记录

日期：2026-06-26

状态：完成

## 修改范围

- 新增 `tahoe-shell/components/MeteoIcon.qml`（52 行）。
  - 用 Material Icons 字形渲染 WMO 天气码，日夜区分。
  - `Item` 包单个 `Text`，照 `TahoeCategoryIcon.qml` 的极简图标组件模式。
  - 属性：`weatherCode`（int，默认 -1）、`night`（bool）、`pixelSize`（real，≤0 自适应）、`color`（默认浅色主文字色）、`iconFont`。
  - 只做渲染，不做数据；码点表来自 `WeatherCodes.js` 的 `materialIcon(code, isNight)`。
  - 暴露只读 `glyph`/`label`，供调用方做无障碍 tooltip / 调试。
- 不修改任何既有文件。LS08 在路线图里只新增 `MeteoIcon.qml`（前置 LS02，不接容器）。

## 与参考项目的区别（防腐化）

- 参考 `Modules/Sidebars/Left/MeteoIcon.qml` 用 `Qt.labs.lottieqt` 的 `LottieAnimation` + SVG `Image` 回退（明确不移植，见路线图 §5）。
- Tahoe 版用 Material Icons 字体字形替代：无素材依赖、无 `Qt5Compat`、无 Lottie 模块。
- 日夜区分由字形本身承担（晴日 `sunny`() / 晴夜 `nights_stay`()），不靠颜色，保持 KISS。

## 接入契约（供 LS09-LS11 下游）

| 下游任务 | 用法 | 数据来源 |
|---|---|---|
| LS11 LeftSidebarWeather（主温度旁大图标） | `MeteoIcon{ weatherCode: weather.currentWeatherCode; night: !weather.currentIsDay; color: ... }` | `services/Weather.qml` 的 `currentWeatherCode`(int)/`currentIsDay`(bool) |
| LS10 WeatherTrendCard（逐时格小图标） | 逐时元素含 `weatherCode`(int)+`isDay`(bool) → `night: !isDay` | `hourlyForecast[].weatherCode`/`isDay` |
| LS10 WeatherTrendCard（每日格小图标） | 每日元素只有 `weatherCode`，无 isDay → `night: false` | `dailyForecast[].weatherCode` |

> daily 元素无 `isDay` 字段（白天为代表日），故每日图标一律 `night:false`；hourly 元素有 `isDay`。本组件对 `night` 无默认推断，由调用方按数据契约传入，避免组件内藏隐式规则。

## 字号自适应

- `pixelSize > 0`：显式优先（如主温度旁大图标 56px、逐时格小图标 20px）。
- `pixelSize <= 0`（默认）：按 Item 尺寸自适应 `floor(min(width,height)*0.86)`，留少量边距，照图标视觉习惯。
- 字形基线略偏上，`anchors.verticalCenterOffset: 1` 微调（照 Launchpad/TopBar 习惯）。

## 验证命令

```bash
# qmllint（仅本文件；LeftSidebar 临时预览已撤回，最终两文件一起 lint）
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable \
  -I /home/wwt/niri/quickshell/build-tahoe/qml_modules \
  tahoe-shell/components/MeteoIcon.qml tahoe-shell/components/LeftSidebar.qml

# 玻璃安全 + 防腐化审计
grep -nE "SpringAnimation|import QtQuick.Controls|import Qt.labs|import Qt5Compat|GraphicalEffects" \
  tahoe-shell/components/MeteoIcon.qml

# 字体码点核实（路线图风险 9 对策）
python3 - <<'PY'
from fontTools.ttLib import TTFont
import re
font = TTFont('tahoe-shell/assets/fonts/MaterialIconsRound.ttf')
cmap = set()
for t in font['cmap'].tables:
    if t.isUnicode():
        cmap.update(t.cmap.keys())
src = open('tahoe-shell/components/WeatherCodes.js', encoding='utf-8').read()
points = {ord(m.group(1).encode().decode('unicode_escape')) for m in re.finditer(r'"(\\u[0-9a-fA-F]{4})"', src)}
missing = sorted(points - cmap)
print('distinct_codepoints:', len(points))
print('missing_from_font:', [hex(p) for p in missing] if missing else 'none')
PY

# 运行时加载验收（临时预览，验收后已撤回）
/home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell > /tmp/ls08_smoke2.log 2>&1 &
QPID=$!; sleep 4
/home/wwt/.local/bin/quickshell ipc --path /home/wwt/niri/tahoe-shell call openLeftSidebar
/home/wwt/.local/bin/quickshell ipc --path /home/wwt/niri/tahoe-shell call closeLeftSidebar
sleep 1; kill $QPID
grep -inE "meteoicon|type unavailable|cannot assign|non-existent|referenceerror" /tmp/ls08_smoke2.log

# 回归确认
git -C /home/wwt/niri status --short
git -C /home/wwt/niri diff --check
git -C /home/wwt/niri diff -- tahoe-shell/components/LeftSidebar.qml   # 应为空
```

## 验收结果

- **qmllint**（`MeteoIcon.qml` + `LeftSidebar.qml`）退出 0，无 `Error`/`non-existent`/`Type unavailable`/`Cannot assign`。LeftSidebar 残留的 `[uncreatable-type]`/`[unresolved-type]`/`[unqualified]` 均为项目既有 warning（LS05/LS06/LS07 验收记录已确认），非本次新增。
- **字体码点核实**：`distinct_codepoints: 13`，`missing_from_font: none`。代表码点抽检全部 `in_font=True`：
  - 晴日 `sunny` 0xe81a ✓ / 晴夜 `nights_stay` 0xea46 ✓（日夜区分）
  - 雾 `foggy` 0xe818 ✓ / 云 `wb_cloudy` 0xe42d ✓ / 毛毛雨 `water_drop` 0xe798 ✓
  - 雨 `umbrella` 0xf1ad ✓ / 雪 `snowing` 0xe80f ✓ / 雷暴 `thunderstorm` 0xebdb ✓
  - unknown fallback `cloud` 0xe2bd ✓
- **玻璃安全 + 防腐化审计**：`MeteoIcon.qml` 无 `SpringAnimation`、无 `QtQuick.Controls`、无 `Qt.labs`、无 `Qt5Compat`、无 `GraphicalEffects` 命中（仅注释文字提及 Lottie/Qt5Compat 为「明确不移植」说明）。
- **运行时加载验收**：临时在 `LeftSidebar.qml` 的天气占位区实例化 8 个 `MeteoIcon`（覆盖 0/45/61/71/95 各码 + 日夜 + unknown -1），IPC `openLeftSidebar`/`closeLeftSidebar` 退出 0，smoke 到达 `INFO: Configuration Loaded`，日志**无** meteoicon 加载失败、无 type unavailable、无 cannot assign、无 ReferenceError。验收后已撤回临时预览代码。
- **回归确认**：
  - `git status --short` 只显示 `?? tahoe-shell/components/MeteoIcon.qml`（新文件）。
  - `git diff --check` 通过（无空白错误）。
  - `git diff -- LeftSidebar.qml` 为空（临时预览完全撤回，无残留）。

## DoD 核对（路线图 LS08）

- ✅ 各 WMO 码渲染出合理图标（码点全部在字体里；运行时实例化无加载错误）。
- ✅ 日夜区分（晴日 `sunny` 与晴夜 `nights_stay` 字形不同；`night` 属性驱动 `WeatherCodes.materialIcon` 取夜表）。
- ✅ unknown fallback `cloud`（`weatherCode:-1` → `materialIcon(-1,*)` 返回 ``，码点在字体里）。

## 本机限制

- 本机已完成 qmllint、字体码点核实、运行时实例化加载验证；由于当前流程无法采集屏幕画面，各码字形的实际目视渲染（太阳/月亮/雨滴/雪花/闪电是否形状正确）仍需在桌面会话中确认。LS02 验收已用 fontTools GSUB/cmap 确认码点正确，本任务在运行时实例化层面进一步确认无加载/绑定错误，码点正确性继承自 LS02。

## 偏离与理由

- 未用 Repeater + JS 对象数组作 model 做验收预览，改用 8 个静态 `MeteoIcon` 实例。
  - 原因：首版用 `model: [{c:0,n:false},...]` + `modelData.c`/`modelData.n`，运行时 QML 对 JS 对象字面量数组元素的属性访问返回 `undefined`，产生 8 行 `Unable to assign [undefined] to int/bool` warning。这是 model 写法问题，不是 MeteoIcon 的问题，但会污染验收日志。静态实例无此问题，验收更干净。验收后两种预览代码都已撤回。
- 组件未内置颜色随 darkMode 自动切换。
  - 原因：照 `TahoeCategoryIcon.qml` 由父级传 `color` 的约定，MeteoIcon 是纯渲染件，颜色归调用方（LS11 主图标、LS10 趋势格）按其所在卡片的深浅色 token 决定。内置 darkMode 反而会让组件绑定一个它不该关心的全局状态，违背 KISS / 单一职责。

## 遗留项

- 桌面会话目视确认：各码字形的实际形状渲染、深色模式下的颜色对比。
- LS08 不接入容器（路线图 LS08 范围只到组件本身）；LS09 WeatherBackground 起、LS10/LS11 才真正实例化 MeteoIcon。
- 后续增强池（路线图 §10）：本任务无新增增强项。
