# D2 审查记录 —— Dock 高度 / 图标大小滑块

日期：2026-08-10
子代理数：2（尺寸不变量视角 / 启动安全与持久化视角，互不知晓彼此结论，均只读）

## 需求

用户：「在设置里面再加入 dock 条高度以及图标大小的设置，也就是拖动条来调整大小、高度」。

用户选定（AskUserQuestion）：
- **开关做预设**：`dockCompact` 只管形态，切换时把预设尺寸**写入**滑块
- **范围**：高度 40–120（默认 84），图标 24–72（默认 48）

## 设计要点

D1 是「一个布尔切两套固定尺寸」。D2 把**尺寸的唯一来源**改为两个滑块，
`dockCompact` 退化为纯形态开关（通栏 / 齐平 / 密度三项）。这是 G-6 的核心：
同一个尺寸不允许有两个决定者。`setDockCompact` 写入预设值，而**不是**在
`Dock.qml` 里再分支一次。

派生公式以出厂默认（84/48）为锚点，精确复现 D1 之前的历史字面量。

## 各子代理结论

### 子代理 1（尺寸不变量）
- 结论：**REJECT**
- CONFIRMED：
  1. C1a `slice_between` 的 end marker 自匹配 → 某测试恒切空串（测试缺陷）
  2. C1b 升级 seed 只查一个 key 却写两个值
  3. C2 范围常量是硬编码镜像，未绑回 QML → 守护形同虚设（给出可破输入：min 放宽到 24）
  4. C3 新测试文件 `tst_dock_settings_load_probe.qml` 未 git add
- PLAUSIBLE：图标滑块 valueText 显示偏好值而非降级后生效值；`to_python`
  在嵌套三元/逗号内三元下会译错（当前无触发点）；`Dock.qml` 的 84/48
  fallback 与常量重复；未 sanitize 的瞬时读
- **独立验证（价值最高）**：手算复核标准档 12 项**逐项精确等于历史字面量**；
  自行暴力跑 81×49=3969 组全笛卡尔积，零违反

### 子代理 2（启动安全与持久化）
- 结论：**APPROVE**
- CONFIRMED：
  1. C1 `QmlPropertyNamingTests` 用 `re.search` → 同一行第二个声明漏报
     （实证 `'property int ok: 1; property int Bad: 2'` → MISSED；
     该写法在 `tst_app_menu_probe_identity.qml:20-23` 已是既有惯用法）
  2. C2 JsonAdapter 的 84/48 字面量未与常量绑定 → 三方漂移无守护
  3. C3 `assertNotIn("cannot begin with an upper case")` 是死断言
     （returncode 断言先触发）
- **独立验证**：真的构造了一个大写属性名的 service 跑 `qmltestrunner`，
  实测 RC=1 + `compile()` 硬失败 → 证明探针对真实事故有效，非纸面推理；
  并确认 `tests/qml_imports/Quickshell/` 桩件在前，`~/.local/lib/qt6/qml`
  不是必需路径，双缺失时测试**响亮失败**而非假通过
- PLAUSIBLE：拖动期每个像素值都 `writeAdapter()`（阻塞写盘）；
  全树 `onUserCommit` 是主流约定（~20 处），仅 DockPage/SoundPage/PowerPage
  用 `onUserPreview`

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| C1a slice 自匹配 | CONFIRMED | **审查快照前已修**：end 改 `"\n    function "` | 复核时 27 passed |
| C1b seed 只查一个 key | CONFIRMED | **审查快照前已修**：门改为两个 key 同时缺失 | `DesktopSettings.qml:799-805` |
| C2 范围常量未绑回 QML | CONFIRMED | **已修**：`_settings_int()` 从 `DesktopSettings.qml` 读 min/max/紧凑预设，`SURFACE_RANGE`/`ICON_RANGE`/`COMPACT_PRESET` 全部改为读取 | 变异验证：min 改 24 → 扫描失败 |
| C2(2) JsonAdapter 字面量未绑定 | CONFIRMED | **已修**：新增 `test_adapter_defaults_match_the_declared_constants` | 变异验证：84→80 → 失败 |
| C1(2) `re.search` 漏同行声明 | CONFIRMED | **已修**：改 `re.finditer` + 循环 | 变异验证：同行大写属性 → 失败 |
| C3 文件未 track | CONFIRMED | **已修**：本次 commit 显式 `git add` | `git status` 已 A |
| **子代理 1 预测的 min=24 破口** | CONFIRMED（自查补强） | **已修**：补 `windowRow ≤ pinnedRow` 断言 —— `Dock.qml:1778` 窗口区宿主高 = `dockPinnedRowHeight`，原扫描只查「≤ 条高」漏了「≤ 宿主」。shelf=24 时 windowRow 22 > pinnedRow 20 | 变异验证：min 改 24 → 失败 |
| 死断言 `assertNotIn` | CONFIRMED（低危） | 不修，理由：作为文档保留，不计入覆盖；真实保护由 returncode 断言 + 探针 compile 失败提供 | 子代理 2 实证 |
| 图标 valueText 显示偏好值 | PLAUSIBLE | 不修，理由：降级是**有意设计**（矮条 + 大图标必须退让），且 40 高时拉满图标属极端组合；加提示属 UI 增强、超出本次需求（G-8） | `Dock.qml:105-109` |
| 拖动期写放大 | PLAUSIBLE | 不修，理由：与**同页既有两个滑块**（隐藏延迟 / 触发热区）完全同模式，改动它们属范围外重构；子代理 2 亦自评「无法从源码判断是否可感知」 | `DockPage.qml:115,130` |
| `to_python` 嵌套三元脆弱 | PLAUSIBLE | 不修，理由：子代理 1 已逐条打印 13 个令牌确认**当前无触发点**；若将来命中，`extract_formula` 缺锚会 raise 而非静默通过 | `test_dock_compact_tier.py:112-122` |
| `Dock.qml` 84/48 fallback 重复 | PLAUSIBLE | 不修，理由：QML 无法在该位置引用 service 常量（service 可能为 null，这正是 fallback 存在的原因）；标准档零回归测试会捕获任何漂移 | `Dock.qml:100-108` |

## 完成判据核对

| 判据 | 是否满足 | 证据 |
|---|---|---|
| 尺寸单一来源，开关不再决定尺寸 | 是 | `test_sizes_never_branch_on_the_tier`；子代理 1 全仓 grep 确认 `dockCompact` 仅出现在形态与宽度处 |
| 出厂默认逐值等于 D1 之前 | 是 | 12/12；子代理 1 **手算独立复核**通过 |
| 全滑块范围自洽 | 是 | 81×49=3969 组扫描（含新增 `windowRow ≤ pinnedRow`）零违反；子代理 1 独立暴力验证亦零违反 |
| 脏数据 clamp | 是 | `clampInt` 先 `Number`+`isFinite`；5000→120、-10→40、`"abc"`→fallback；`sanitizeState` 与 setter 共用同组常量 |
| 升级路径不丢紧凑尺寸 | 是 | `storedKey()` 门控的一次性 seed；**实机验证**：删掉两个 key + compact=true → 重载后自动补 56/36，实测条高 56.0px；再手设 100 → 不被重新 seed（幂等） |
| 滑块 UI 正确 | 是 | 归一化与反算互逆（子代理 1 核对 `TahoeSlider.qml:39` 已 clamp 0..1，最左/最右精确命中 min/max） |
| 启动安全（不得再出大写属性名事故） | 是 | 两层守护：静态 `QmlPropertyNamingTests`（全树 rglob）+ 真实引擎探针；**两者均经变异验证对真实事故失败** |
| pytest 全绿 | 是 | **1051 passed, 318 subtests**（D1 基线 1046 → +5） |
| qmllint 无新增告警类别 | 是 | Dock 635=635；DockPage +2（两个新 TahoeSlider 的 `--bare` unresolved-type，既有同类）；DesktopSettings 27→15（减少） |
| 实机验证 | 是 | 84（默认）/104（自定义）/56（紧凑预设）/40+图标拉满（clamp 降级）四组实测取像，条高逐一精确 |

## 事故记录（务必留档）

实现中途给 `DesktopSettings.qml` 加了**大写开头**的属性名
（`DOCK_SURFACE_HEIGHT_MIN`），QML 直接拒绝加载 → **整个 shell 起不来**
（`Property names cannot begin with an upper case letter`）。
`qmllint --bare` **不报**这个错。已改名为小写并补两层守护测试。

教训：**部署后必须确认 shell 真的还活着**（`pgrep -x quickshell` +
`niri msg layers` 看层是否 mapped），不能只看 `cp` 成功。

另一个自伤：热改 state 文件验证时，运行中的旧版 shell（启动于 D2 之前、
adapter 里没有新键）会把文件**回写覆盖**掉我的编辑，导致我一度误判
「滑块不生效」。热验证前必须确认线上 shell 已经是新代码。

## 最终结论

两条 CONFIRMED 在审查快照前已修（C1a/C1b），其余 4 条已修并全部经变异验证；
子代理 1 预测的 min=24 破口经我独立计算确认成立，并补上了缺失的
`windowRow ≤ pinnedRow` 不变量。5 条 PLAUSIBLE 逐条记录处置理由。
**允许 commit**。
