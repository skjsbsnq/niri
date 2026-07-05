# Left Sidebar LS03 验收记录

日期：2026-06-25

状态：完成

## 修改范围

- 新增 `tahoe-shell/services/Weather.qml`。
  - 使用 `curl -fsS --max-time 8` 请求 ipwho.is、Open-Meteo forecast、Open-Meteo air-quality。
  - QML 侧解析 Open-Meteo 并行数组，整理为 `current*` 属性、`dailyForecast`、`hourlyForecast`、`currentAirQuality`、`airQualityHourly`。
  - 缓存写入 `Quickshell.stateDir + "/weather-cache.json"`。
  - 提供 `refresh()`、`detectLocation()`、`setLocation()`、`clearManualOverride()`。
  - 状态机覆盖 `idle` / `fresh` / `stale` / `error`。
  - 读取未来 LS04 的 `settingsService.weather*` 属性；当前属性不存在时自动回退 IP 定位。
- 修改 `tahoe-shell/shell.qml`。
  - 在服务声明区新增 `Weather { id: weather; settingsService: desktopSettings }`。
  - 未接入任何视图、设置页或顶栏入口。

## 暴露数据

- 当前天气：天气码、天气文案、slug、温度、体感温度、风速/风向/阵风、UV、湿度、露点、气压、云量、能见度、降水、昼夜。
- 预报：
  - `dailyForecast`：最多 16 条，包含天气码、温度高低、日出日落、UV、降水、湿度、气压、云量、能见度、风。
  - `hourlyForecast`：从当前小时附近开始最多 48 条。
- 空气质量：
  - `currentAirQuality`：从 air-quality hourly 中取最接近当前时间的一条。
  - `airQualityHourly`：包含 PM10、PM2.5、CO、NO2、SO2、O3 和 6 类花粉。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules services/Weather.qml shell.qml
rg -n "SpringAnimation|QtQuick\\.Controls|Lottie|GraphicalEffects|console\\.log" services/Weather.qml shell.qml
timeout 25s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell/weather-ls03-smoke.qml
python3 - <<'PY'
import json
from pathlib import Path
p=Path('/home/wwt/.local/state/quickshell/by-shell/tahoe-weather-ls03-smoke/weather-cache.json')
data=json.loads(p.read_text(encoding='utf-8'))
print('locationName=', data.get('locationName'))
print('currentTemperatureC=', data.get('currentTemperatureC'))
print('currentWeatherCode=', data.get('currentWeatherCode'))
print('dailyForecast=', len(data.get('dailyForecast') or []))
print('hourlyForecast=', len(data.get('hourlyForecast') or []))
print('currentAirQuality keys=', len(data.get('currentAirQuality') or {}))
print('updatedAt=', data.get('updatedAt'))
PY
```

## 运行验收结果

- `qmllint` 退出 0。
  - 输出仍包含 `shell.qml` 既有 `modelData` unqualified warning；不是本次新增。
  - `services/Weather.qml` 无新增 lint warning。
- 防腐化检查未命中 `SpringAnimation`、`QtQuick.Controls`、`Lottie`、`GraphicalEffects`、遗留 `console.log`。
- 使用临时最小 smoke QML 只实例化 `Weather` 服务并打印 DoD 字段，验收后已删除临时文件。
- 有网取数结果：
  - `status=fresh`
  - `locationName=Singapore · Southeast · Singapore`
  - `currentTemperatureC=30.4`
  - `dailyForecast.length=16`
  - `hourlyForecast.length=48`
  - `Object.keys(currentAirQuality).length=13`
- 缓存文件已写出：
  - `currentWeatherCode=0`
  - `dailyForecast=16`
  - `hourlyForecast=48`
  - `currentAirQuality keys=13`
- 强制失败回退 smoke：
  - `status=stale`
  - 缓存位置仍为 `Singapore · Southeast · Singapore`
  - `dailyForecast.length=16`
  - `hourlyForecast.length=48`

## 运行时警告说明

完整 `shell.qml` smoke 在配置加载后触发既有 Quickshell/C++ 崩溃：

- 崩溃栈位于 `IconImageProvider::requestPixmap` / `QPixmap::load` / `WindowButton` 图标加载路径。
- 日志没有 `Weather.qml` 加载失败、JSON 解析失败、curl 失败或新增 import 错误。
- 为避免把既有窗口图标崩溃混入 LS03，本次使用最小 smoke QML 隔离验证 Weather 服务。

本次 smoke 中仍出现既有运行时警告：

- Dock/WindowButton 的 `magnification`、`bounceOffset` interceptor warning。
- `shell.qml` 中 `Qt.application.font` 只读属性 warning。
- notification server 已注册 warning。
- portal app id 注册 warning。

## 偏离与理由

- 验收没有在完整 shell 中保留临时 `console.log`。
  - 原因：完整 shell 当前会在窗口图标加载路径触发既有 C++ 崩溃，无法稳定等待 Weather 输出。
  - 替代验收：使用同仓库临时最小 `weather-ls03-smoke.qml` 只加载 `Weather` 服务，直接打印 `status/location/temp/daily/hourly/air`，随后删除临时文件。
- `hourlyForecast` 暴露 48 条，而 DoD 只要求存在 hourly 数据。
  - 原因：后续趋势卡通常需要 24 小时以上滚动缓冲；服务层保留 48 条仍保持简单，视图可自行截取。

## 遗留项

- LS03 只提供服务和 shell 声明，不提供 UI 展示。
- 天气设置持久化、设置页、侧边栏容器和天气页组装留给后续 LS04+。
