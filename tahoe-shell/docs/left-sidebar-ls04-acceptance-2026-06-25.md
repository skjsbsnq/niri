# Left Sidebar LS04 验收记录

日期：2026-06-25

状态：完成

## 修改范围

- 修改 `tahoe-shell/services/DesktopSettings.qml`。
  - `JsonAdapter` 新增 `weatherLatitude`、`weatherLongitude`、`weatherLocationName`、`weatherManualOverride`、`weatherTempUnit`。
  - 顶层新增同名 readonly 属性，供 `Weather.qml` 和后续设置页读取。
  - 新增 `setWeatherLocation(lat, lon, name)`、`clearWeatherLocation()`、`setWeatherTempUnit(unit)`。
  - `sanitizeState()` 新增天气字段修正：
    - 纬度钳制到 `[-90, 90]`。
    - 经度钳制到 `[-180, 180]`。
    - 手动覆盖开启但位置名为空时填 `手动位置`。
    - 手动覆盖关闭时清空位置名。
    - 温度单位归一化为 `c` / `f`，非法值回落 `c`。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules services/DesktopSettings.qml
rg -n "SpringAnimation|QtQuick\\.Controls|Lottie|GraphicalEffects|console\\.log" services/DesktopSettings.qml

# 临时 smoke QML 使用独立 ShellId：
# tahoe-desktop-settings-ls04-smoke
timeout 5s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell/desktop-settings-ls04-smoke.qml
python3 -m json.tool ~/.local/state/quickshell/by-shell/tahoe-desktop-settings-ls04-smoke/desktop-settings.json
```

## 运行验收结果

- `qmllint` 退出 0。
  - 仍输出本文件既有的 `JsonAdapter` incomplete type 与 `settingsAdapter` unqualified 静态告警。
  - 天气字段沿用同一 `settingsAdapter` 模式，没有引入新的 import 或运行时 QML 加载错误。
- 防腐化检查未命中 `SpringAnimation`、`QtQuick.Controls`、`Lottie`、`GraphicalEffects`、遗留 `console.log`。
- 预置非法测试配置：
  - `weatherLatitude=200`
  - `weatherLongitude=-250`
  - `weatherLocationName="   "`
  - `weatherManualOverride=true`
  - `weatherTempUnit="kelvin"`
- smoke 首次启动后 sanitize 结果：
  - `weatherManualOverride=true`
  - `weatherLatitude=90`
  - `weatherLongitude=-180`
  - `weatherLocationName=手动位置`
  - `weatherTempUnit=c`
- 调用 `setWeatherLocation(31.23, 121.47, "上海")` 和 `setWeatherTempUnit("f")` 后：
  - `weatherManualOverride=true`
  - `weatherLatitude=31.23`
  - `weatherLongitude=121.47`
  - `weatherLocationName=上海`
  - `weatherTempUnit=f`
- 第二次启动重读同一 state 文件：
  - 启动即读到 `31.23 / 121.47 / 上海 / f`。
  - 重复调用相同 setter 后文件 mtime 未变化，验证「无变化即返回」。
- 调用 `clearWeatherLocation()` 后：
  - `weatherManualOverride=false`
  - `weatherLatitude=0`
  - `weatherLongitude=0`
  - `weatherLocationName=""`
  - `weatherTempUnit` 保持 `f`。
- 临时 smoke QML 和独立测试 state 已删除。

## 运行时警告说明

smoke 运行时只出现独立测试 app id 未注册的 portal warning：

- `Could not register app ID: App info not found for 'org.quickshell.tahoe.ls04smoke'`

未出现 `DesktopSettings.qml` 加载失败、写盘失败或新增 import 错误。

## 偏离与理由

- 未在真实 Tahoe shell 的用户 state 上直接手动调用 setter。
  - 原因：LS04 验收只需验证持久化契约，直接改用户当前桌面配置会污染真实设置。
  - 替代验收：使用独立 `ShellId` 的临时 smoke QML，覆盖 `desktop-settings.json` 的同名 FileView 流程，验证写盘、重读、sanitize 和无变化返回。

## 遗留项

- LS04 只提供天气设置持久化接口，不提供设置页 UI。
- 后续 LS12 将接入 `WeatherPage.qml`，使用这些 setter 驱动手动定位、自动定位和温度单位选择。
