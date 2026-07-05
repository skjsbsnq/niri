# Left Sidebar LS02 验收记录

日期：2026-06-25

状态：完成

## 修改范围

- 新增 `tahoe-shell/components/WeatherCodes.js`。
  - 使用 `.pragma library`。
  - 提供 `text(code)`、`slug(code, isNight)`、`materialIcon(code, isNight)` 三个查询函数。
  - 覆盖路线图要求的全部 WMO 天气码。
  - `slug()` 命名对齐参考项目 `MeteoIcon.slugForCode`，便于后续 LS09 背景分类复用。
  - unknown fallback：
    - 文案：`未知天气`
    - slug：`cloudy`
    - 图标：`\ue2bd`（Material Icons: `cloud`）

## 覆盖范围

- 晴/云：`0`、`1`、`2`、`3`
- 雾：`45`、`48`
- 毛毛雨/冻毛毛雨：`51`、`53`、`55`、`56`、`57`
- 雨/冻雨：`61`、`63`、`65`、`66`、`67`
- 雪/雪粒：`71`、`73`、`75`、`77`
- 阵雨/阵雪：`80`、`81`、`82`、`85`、`86`
- 雷暴/冰雹：`95`、`96`、`99`

## 图标码点

本次没有依赖 Material Icons ligature 文本，而是返回实测私有码点，避免后续 QML 文本 shaping 差异影响图标显示。

- `0` 白天：`\ue81a`（`sunny`）
- `0` 夜间：`\uea46`（`nights_stay`）
- 云：`\ue2c2` / `\ue42d`
- 雾：`\ue818`
- 雨：`\uf1ad`
- 雪：`\ue80f`
- 雷暴：`\uebdb`
- unknown：`\ue2bd`

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules components/WeatherCodes.js
python3 - <<'PY'
import re
from pathlib import Path
from fontTools.ttLib import TTFont
src = Path('components/WeatherCodes.js').read_text(encoding='utf-8')
required = [0,1,2,3,45,48,51,53,55,56,57,61,63,65,66,67,71,73,75,77,80,81,82,85,86,95,96,99]
for table in ['TextByCode', 'DaySlugByCode', 'NightSlugByCode', 'DayIconByCode', 'NightIconByCode']:
    body = re.search(r'var ' + table + r' = \{(.*?)\};', src, re.S).group(1)
    keys = set(map(int, re.findall(r'(?m)^\s*(\d+)\s*:', body)))
    missing = [code for code in required if code not in keys]
    if missing:
        raise SystemExit(f'{table} missing {missing}')
expected = {
    'DaySlugByCode': {0:'clear-day',1:'mostly-clear-day',2:'partly-cloudy-day',3:'cloudy',45:'fog-day',48:'fog-day',51:'drizzle',57:'drizzle',61:'overcast-day-rain',67:'overcast-day-sleet',71:'overcast-day-snow',77:'overcast-day-snow',80:'partly-cloudy-day-rain',86:'partly-cloudy-day-snow',95:'thunderstorms-day',99:'thunderstorms-day-hail'},
    'NightSlugByCode': {0:'clear-night',1:'mostly-clear-night',2:'partly-cloudy-night',3:'cloudy',45:'fog-night',48:'fog-night',51:'drizzle',57:'drizzle',61:'overcast-night-rain',67:'overcast-night-sleet',71:'overcast-night-snow',77:'overcast-night-snow',80:'partly-cloudy-night-rain',86:'partly-cloudy-night-snow',95:'thunderstorms-night',99:'thunderstorms-night-hail'}
}
for table, pairs in expected.items():
    body = re.search(r'var ' + table + r' = \{(.*?)\};', src, re.S).group(1)
    values = dict((int(k), v) for k, v in re.findall(r'(?m)^\s*(\d+)\s*:\s*"([^"]+)"', body))
    for code, value in pairs.items():
        if values.get(code) != value:
            raise SystemExit(f'{table}[{code}] expected {value}, got {values.get(code)}')
icons = re.findall(r'"(\\u[0-9a-fA-F]{4})"', src)
points = {ord(s.encode().decode('unicode_escape')) for s in icons}
font = TTFont('assets/fonts/MaterialIconsRound.ttf')
cmap = set()
for table in font['cmap'].tables:
    if table.isUnicode():
        cmap.update(table.cmap.keys())
missing_points = sorted(points - cmap)
if missing_points:
    raise SystemExit('missing font codepoints: ' + ', '.join(hex(x) for x in missing_points))
print('covered_codes=', len(required))
print('icon_codepoints=', ', '.join(hex(x) for x in sorted(points)))
print('materialIcon(0,false)=\\ue81a in font:', 0xe81a in cmap)
print('slug samples match reference MeteoIcon')
PY
rg -n "SpringAnimation|QtQuick.Controls|Lottie|GraphicalEffects" components/WeatherCodes.js || true
```

## 运行验收结果

- `qmllint` 退出 0，无输出。
- 覆盖检查通过，`covered_codes= 28`。
- 图标码点检查通过：
  - `0xe2bd, 0xe2c2, 0xe3ea, 0xe42d, 0xe430, 0xe798, 0xe80f, 0xe818, 0xe81a, 0xea46, 0xeb3b, 0xebdb, 0xf1ad`
- `materialIcon(0,false)` 返回 `\ue81a`，该码点存在于 `MaterialIconsRound.ttf`，可由当前 Material Icons 字体渲染。
- slug 样例与参考项目 `MeteoIcon.slugForCode` 一致。
- 防腐化检查未命中 `SpringAnimation`、`QtQuick.Controls`、`Lottie`、`GraphicalEffects`。

## 偏离与理由

- 未在真实侧边栏内临时插入 `Text { font.family: "Material Icons"; text: WeatherCodes.materialIcon(0,false) }` 做目视验收。
  - 原因：LS02 只新增库文件，当前任务不接 UI；直接改 shell 或组件插临时代码会扩大改动面。
  - 替代验收：解析 `MaterialIconsRound.ttf` 的 GSUB ligature 和 cmap，确认选用的 `sunny` 对应 `\ue81a`，且码点存在于字体。

## 遗留项

- LS02 只提供映射表，不提供天气服务或图标组件。
- 后续 LS08 `MeteoIcon.qml` 接入后，可用 Repeater 目视复核这些码点在真实 QML 文本里的显示效果。
