# 执行计划（EXECUTION PLAN）

**本文件是执行者的唯一操作手册。**
配套：`constraints.md`（硬约束，必读）、`roadmap.md`（任务定义）、
`research-report.md`（事实依据）。

执行者应具备的前提：能读写本仓库、能运行 shell 命令、能派生独立子代理。

---

## 第 0 章：开始之前（每次接手都要做）

1. **读完** `constraints.md` 全文。它是硬边界，违反即任务失败。
2. **读** `roadmap.md`，确认当前应执行哪个任务
   （查 `acceptance/` 目录下已有的审查记录，最后一个通过的任务的下一个即当前任务）。
3. **读** `research-report.md` 中该任务「问题引用」指向的章节。
4. 确认工作区干净：`git -C /home/wwt/niri status`。
   若有未提交改动且非本任务产生 → 停止并报告，不得贸然提交或丢弃。

**绝对不要**：跳序执行、并行多任务、把多个任务合成一个 commit。

---

## 第 1 章：单任务标准流程（七步，不得省略）

每个任务**必须**完整走完以下七步。任何一步失败即停在该步处理，不得前进。

```
第 1 步  读取任务定义与约束
第 2 步  实现
第 3 步  自检（静态 + 测试 + 回归）
第 4 步  独立子代理对抗性审查   ← 禁止自审
第 5 步  修复审查发现的问题（回到第 3 步，最多 3 轮）
第 6 步  commit
第 7 步  push
```

### 第 1 步：读取任务定义与约束

- 从 `roadmap.md` 读该任务的：问题引用、目标、范围、不做、完成判据
- 从 `constraints.md` 读该任务「约束重点」列出的每一条
- 从 `research-report.md` 读事实依据；**遇到标注 `[未确认]` 的结论，
  必须先自行验证再使用**

### 第 2 步：实现

遵守 `constraints.md` 全部条款。重点复述三条最易违反的：

- **G-6 禁止平行接口**：不得新增与既有功能并存的第二条路径。
  允许重构（修改/重命名/合并/删除），但最终只能有一条路径承担该职责。
- **G-5 禁止最小实现**：不得留 `TODO`、空函数体、假数据、只在 happy path 生效的实现。
- **G-8 禁止需求外功能**：需求边界见 `research-report.md` A-0 与 B 项三现象。
  不确定是否在范围内 → **不做**，在任务报告中提问。

### 第 3 步：自检

按任务类型执行对应命令（见第 2 章），并**逐条**核对 `roadmap.md` 中该任务的
「完成判据」。**每条判据都要有实际证据**（命令输出、实测数据、
人工验证记录），不得凭「我认为实现了」通过。

### 第 4 步：独立子代理对抗性审查

**这是硬性门槛，禁止跳过，禁止自审。** 详见第 3 章。

### 第 5 步：修复审查问题

审查发现的每个问题必须：修复，或在 `acceptance/<任务号>-review.md` 中
明确记录为「已知遗留 + 不修的理由」。

修复后**回到第 3 步**重新自检（改动可能引入新问题）。

**最多 3 轮**。第 3 轮仍无法通过 → 执行 G-3：
写 `acceptance/<任务号>-blocked.md`（当前状态 / 失败原因 / 已尝试方案），
**停下来向用户报告，不得继续尝试**。

### 第 6 步：commit

一个任务 = 一个 commit（G-4）。

提交信息格式：

```
<type>(<scope>): <任务号> <一句话结论>

问题引用：research-report.md <章节号>
改动要点：
- ...
验收：
- <判据>：<证据>
审查：acceptance/<任务号>-review.md（<独立子代理数>个子代理，<确认问题数>个问题已修）
```

`<type>` 用 `fix` / `feat` / `refactor` / `perf` / `test`，与仓库既有习惯一致。

**commit 前确认**：`acceptance/<任务号>-review.md` 已存在且记录了审查结论。

### 第 7 步：push

```sh
git -C /home/wwt/niri push
```

push 完成后，该任务结束。**回到第 0 章**开始下一个任务。

---

## 第 2 章：自检命令（按任务类型）

### 2.1 niri（Rust）任务 —— B1 / B2 / B3

```sh
cd /home/wwt/niri/niri

# 编译（必须零错误；新增告警须说明）
cargo build --release 2>&1 | tail -30

# 本任务新增/相关测试
cargo test <测试名> -- --nocapture

# 全量回归（必须全绿）
cargo test 2>&1 | tail -30
```

**回归重点**（B 项改动可能影响，须全绿）：
- `niri/src/tests/lifecycle_observe.rs`
- `niri/src/layout/tests/lifecycle_controller.rs`
- `niri/src/tests/lifecycle_command.rs`
- `niri/src/layout/tests.rs`
- `niri/src/tests/fullscreen.rs`
- `niri/src/tests/floating.rs`

### 2.2 tahoe-shell（QML）任务 —— A1 – A7

```sh
# 静态检查（必须用绝对路径，见 constraints.md P-12）
/usr/lib/qt6/bin/qmllint --bare /home/wwt/niri/tahoe-shell/components/<改动文件>.qml

# 结构测试全量（必须全绿）
cd /home/wwt/niri/tahoe-shell && python -m pytest tests/ -x -q 2>&1 | tail -20
```

### 2.3 内存实测（A1 / A3 / A5 需要）

```sh
# 找到 live quickshell 的精确 PID（禁止 pkill 宽匹配，见 P-11）
QS_PID=$(pgrep -x quickshell | head -1)
echo "PID=$QS_PID"

# RSS 与匿名内存
grep -E '^(VmRSS|RssAnon|RssFile|Threads)' /proc/$QS_PID/status

# 面板开关的内存增量/残留（以 WindowOverview 为例）
QS=/home/wwt/.local/bin/quickshell
CFG=/home/wwt/.config/quickshell/tahoe
rss(){ awk '/VmRSS/{print $2}' /proc/$QS_PID/status; }
B=$(rss)
timeout 5 $QS -p $CFG ipc call tahoe openWindowOverview >/dev/null 2>&1; sleep 3; O=$(rss)
timeout 5 $QS -p $CFG ipc call tahoe closeWindowOverview >/dev/null 2>&1; sleep 3; C=$(rss)
echo "开=+$(( (O-B)/1024 ))MB  关后残留=+$(( (C-B)/1024 ))MB"
```

### 2.4 唤醒源实测（A3 / A5 需要）

```sh
QS_PID=$(pgrep -x quickshell | head -1)

# 60 秒高频采样：稳定 PID 数应无新增
for i in $(seq 1 200); do
  ps --ppid $QS_PID -o pid,comm --no-headers 2>/dev/null
  sleep 0.3
done | sort -u | awk '{print $2}' | sort | uniq -c

# 基线（A2 完成时）：4 个稳定 PID —
#   udevadm monitor / niri msg event-stream / wl-paste --watch / gammastep 包装
# 判据：新增小部件后仍为 4 个，无瞬时 spawn
```

### 2.5 禁弹簧断言（A6 / A7 需要）

```sh
# 小部件相关文件中不得出现 SpringAnimation（见 constraints.md P-1）
grep -rn 'SpringAnimation' /home/wwt/niri/tahoe-shell/components/widgets/ || echo "OK: 无弹簧"

# 不得硬编码 duration 字面量（见 P-3）
grep -rnE 'duration:\s*[0-9]+' /home/wwt/niri/tahoe-shell/components/widgets/ || echo "OK: 无硬编码"
```

### 2.6 部署（需人工验证的任务）

遵守 `constraints.md` P-10：

```sh
# niri：提交后必须重建再部署，禁止 -modified 二进制上线
cd /home/wwt/niri/niri && cargo build --release
cp target/release/niri ~/.local/bin/niri.new && mv -f ~/.local/bin/niri.new ~/.local/bin/niri
niri --version   # 核验版本，确认非 -modified

# shell QML：cp 后需重启 quickshell
cp -r /home/wwt/niri/tahoe-shell/* /home/wwt/.config/quickshell/tahoe/
# 重启 quickshell 时禁止 pkill -f 宽匹配（P-11），用精确 PID：
QS_PID=$(pgrep -x quickshell | head -1) && kill $QS_PID
```

---

## 第 3 章：独立子代理审查机制

### 3.1 硬性要求

- **数量**：每个任务至少 **2 个**独立子代理，B2/B3/A6 至少 **3 个**
  （时序与状态机改动风险最高）
- **独立**：各子代理不得知晓彼此结论；不得由实现者自审
- **必须读代码**：审查者必须实际读取改动后的源文件，
  不得只看 diff 摘要或凭任务描述判断
- **对抗性**：默认实现有缺陷，主动寻找反例，而非确认其正确

### 3.2 每个审查子代理的提示词模板

```
只读审查，禁止修改任何文件。

任务背景：仓库 /home/wwt/niri 刚完成任务 <任务号>。
任务定义见 docs/desktop-widgets-and-maximize-exclusivity-2026-08-09/roadmap.md 的 <任务号> 段。
硬约束见同目录 constraints.md。

本次改动涉及文件：<列出文件路径>

你的职责是**对抗性审查**：假设这个实现是错的，去证明它错。
不要确认它对，去找它在什么输入/时序/边界下会坏。

必须逐条核查（每条给出 文件:行号 证据）：

1. 【G-6 平行接口】是否新增了与既有功能并存而未替换它的第二条路径？
   是否有同一份状态被两个变量维护？是否为测试新建了与生产不同的状态机？
2. 【G-5 最小实现】是否有 TODO / 空函数体 / 假数据 / 仅 happy path 生效的实现？
3. 【G-7 破坏现有功能】改动是否改变了任务未声明要改变的行为？
   具体检查：<该任务的回归清单，见执行计划第 4 章>
4. 【G-8 需求外功能】是否添加了 research-report.md A-0（五条需求）
   与 B 项三现象之外的功能？
5. 【任务专属约束】逐条核查 roadmap.md 中该任务「约束重点」列出的条款。
6. 【完成判据】roadmap.md 中该任务的每条「完成判据」是否真的满足？
   有无判据被声称满足但实际无证据支撑？
7. 【边界与失败路径】错误处理、空值、并发/时序竞态、资源释放
   （对 QML：对象树是否真正销毁；对 Rust：状态是否可能残留）。

输出格式：
- 确认的硬缺陷（CONFIRMED）：问题 + 文件:行号 + 具体失败场景（输入→错误结果）
- 可能的问题（PLAUSIBLE）：同上 + 为何不确定
- 已核查无问题的条款：列出条款号即可
- 结论：APPROVE / REJECT（有任一 CONFIRMED 即 REJECT）

只报你实际读代码确认的。不确定的标 PLAUSIBLE，不要报成 CONFIRMED。
不要给出修改建议以外的重构意见（本次不做范围外改动）。
```

### 3.3 审查记录存档

审查完成后写 `acceptance/<任务号>-review.md`：

```markdown
# <任务号> 审查记录

日期：<日期>
子代理数：<N>

## 各子代理结论
### 子代理 1
- 结论：APPROVE / REJECT
- CONFIRMED：<列表，或"无">
- PLAUSIBLE：<列表，或"无">

### 子代理 2
...

## 问题处置
| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| ... | CONFIRMED | 已修（<提交内或本次修复说明>） | <文件:行号> |
| ... | PLAUSIBLE | 不修，理由：... | — |

## 完成判据核对
| 判据（引 roadmap.md） | 是否满足 | 证据 |
|---|---|---|
| ... | 是 | <命令输出/实测数据/人工验证记录> |

## 最终结论
全部子代理 APPROVE / 全部 CONFIRMED 已修 → 允许 commit
```

**无此文件不得 commit。**

---

## 第 4 章：各任务回归清单（G-7 验证用）

改动后**必须**验证以下既有行为未被破坏。

### C1（壁纸预启动路径 —— 历史事故高发区，验证从严）
- `pytest` 全绿，重点：`tests/test_wallpaper_idle_budget.py`
  （postmortem P-7/C3 的执法测试）
- **人工验证（部署后）**：
  1. 冷启动会话 → 壁纸正常显示，无 `#1c1d20` 盖板残留、无静态壁纸闪
  2. 热重启 quickshell（精确 PID，见 P-11）→ 壁纸正常恢复
  3. 核验 `linux-wallpaperengine` 进程**仅一个实例**
     （`pgrep -c linux-wallpaperengine` 应为 1；
     postmortem §S3 的双引擎泄漏不得复现）
  4. 锁屏 → 解锁 → 壁纸正常
- **不得**因删除死代码而使 `:845` 留下悬空调用（会成运行时错误）

### B1（仅新增测试，无生产改动）
- `cargo build --release` 通过
- `cargo test` 除新增的三个红灯测试外全绿

### B2 / B3
- `cargo test` 全绿，重点：`lifecycle_observe.rs`、
  `layout/tests/lifecycle_controller.rs`、`tests/lifecycle_command.rs`、
  `tests/fullscreen.rs`、`tests/floating.rs`、`layout/tests.rs`
- **人工验证（部署后）**：
  1. 正常最大化窗口 → 视觉与改动前一致
  2. 最大化 → 取消最大化 → 布局正确
  3. 最大化 → 全屏 → 退出 → 布局正确
  4. 客户端无响应场景：超时保护仍生效
     （`TimedOutVisibleFallback` 未被削弱，见 B-C4）
  5. 三个原始现象逐一复现验证**均已消失**：
     - 现象 1：最大化 + 后方两层 → 最小化 → 后方窗口**立即**出现
     - 现象 2：点击其中一个 → **仅**该窗口露出，另一个不受影响
     - 现象 3：从 Dock 恢复已最小化窗口 → 两个正常应用**不被隐藏**

### A1
- 六个面板逐一打开/关闭，功能、动画、玻璃材质与改动前一致
- `shell.qml:949` 的 `popupWidth` 引用仍正确工作
  （PopupDismissLayer 的 cutout 尺寸正确）
- 侧栏两个 tab 切换正常
- `pytest` 全绿

### A2
- 顶栏各弹层（控制中心/剪贴板/通知中心）打开关闭正常
- 点击桌面空白处收回弹层的既有行为不变
- 壁纸显示正常（小部件层不遮挡、不干扰）
- `pytest` 全绿

### A3
- A2 的全部回归项
- 各 service（Weather / Battery / SystemStats）在控制中心内的既有显示不变
- 侧栏「系统」「天气」两 tab 显示不变

### A4 / A5（侧栏库 tab 与预览）
- 侧栏「系统」「天气」两 tab 的行为、布局、thumb 动画与改动前一致
  （`constraints.md` A-C7）
- 侧栏打开/关闭动画不变
- A2、A3 的全部回归项（桌面小部件显示与输入策略不受影响）
- `pytest` 全绿

### A6 / A7（编辑模式与 resize）
- A2、A3 的全部回归项
- A4 / A5 的全部回归项（库 tab 添加链路仍正常）
- Dock 图标拖动重排的既有功能不变（本次复用其模式，不得改其代码）
- 非编辑模式下小部件点击行为正常
- `pytest` 全绿

---

## 第 5 章：任务索引与状态跟踪

按顺序执行。完成一个才能开始下一个（G-1）。

| 序 | 任务 | 类型 | 子代理数 | 需人工验证 | 状态 |
|---|---|---|---|---|---|
| 1 | C1 壁纸预启动死代码与失效守护 | QML + 文档 | 2 | 是 | 完成（f7766f0） |
| 2 | B1 建立缺陷复现测试基线 | Rust | 2 | 否 | 未开始 |
| 3 | B2 修复独占解除时机与粒度 | Rust | 3 | 是 | 未开始 |
| 4 | B3 修复恢复路径可见性抑制 | Rust | 3 | 是 | 未开始 |
| 5 | A1 面板按需加载 | QML | 2 | 是 | 未开始 |
| 6 | A2 小部件基类与宿主层 | QML | 2 | 是 | 未开始 |
| 7 | A3 首批小部件 | QML | 2 | 是 | 未开始 |
| 8 | A4 侧栏第三 tab（小部件库） | QML | 2 | 是 | 未开始 |
| 9 | A5 库实时预览 | QML | 2 | 是 | 未开始 |
| 10 | A6 长按编辑 + 拖动移位 | QML | 3 | 是 | 未开始 |
| 11 | A7 边缘 resize 三档切换 | QML | 2 | 是 | 未开始 |

**每完成一个任务，把该行「状态」改为「完成（<commit sha>）」并提交本文件。**

---

## 第 6 章：停止条件（何时必须停下来问人）

遇到以下任一情况，**立即停止，写明情况向用户报告，不得自行决定**：

1. 单任务连续 3 轮修复后仍无法通过验收（G-3）
2. 完成任务需要违反 `constraints.md` 中任一条款
3. `research-report.md` 中标注 `[未确认]` 的结论经验证为**假**
   （说明根因分析有误，后续任务的前提可能失效）
4. 发现需求边界不清、无法判断某功能是否在范围内（G-8）
5. 发现改动会破坏某个既有功能，且无法在不破坏的前提下达成任务目标（G-7）
6. 工作区存在非本任务产生的未提交改动
7. B1 的三个测试中有任何一个意外为绿（说明现象理解有误）
8. 需要改动 `constraints.md` P-6（C7 焦点约束）相关代码

**报告时须包含**：当前任务号、卡在第几步、具体情况、已尝试的方案、
你认为的可选方向（但不要自行选择）。
