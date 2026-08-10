# D1 审查记录

日期：2026-08-10
子代理数：2（几何视角 / 输入视角，互不知晓彼此结论，均为只读）

## 各子代理结论

### 子代理 1（几何与档位视角）
- 结论：**REJECT**
- CONFIRMED：
  1. `Behavior on width` 未在档位切换时禁用 → 切换期出现全宽扫动画，
     且 mask（瞬变）与玻璃（缓动）失步
  2. 三个档位值内联在使用点，未进档位表，且无守护测试覆盖
- PLAUSIBLE：
  - P-1 档位切换时 layer surface 高度瞬变，可能一帧 region 超出 surface
  - P-2 `sanitizeState` 缺 `dockCompact`
  - P-3 `iconCode: ""` 疑似占位残留
  - P-4 `dockContentBoxX` 断言为前缀匹配，尾项不受约束
  - P-5 紧凑档 mask 内容盒用目标值而非各 section 实时动画宽度
- 未能核查（子代理自述）：Dock.qml 260–1000 函数区、hover label 落点、
  qmllint、pytest、niri 侧 region 越界处理

### 子代理 2（输入与命中视角）
- 结论：**APPROVE**
- CONFIRMED：无
- PLAUSIBLE：无
- 核查通过：A 标准档零回归（逐位等价，含 `PendingRegion::build()` 空矩形
  证明标准档 width=0 不贡献 union）、B headroom 穿透（条带高度用
  `dockVisibleHeight` 非 chrome 高）、C 放大波不裁命中（T08-fix8 铁律：
  命中走 rest 槽、wave 纯视觉）、D autohide 隐藏态三区归零、
  E 紧凑档几何自洽、F `exclusiveZone` 随档位无硬编码

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| C-1 切换期 mask/玻璃/圆角失步 | CONFIRMED | **已修**：全宽条带改跟随 live `dockChrome.x/width`；`radius` 改按 live 宽度判定（`>= root.width - 0.5`）。三者同源同相位，无需禁用 Behavior | `Dock.qml:1071-1087`、`:1159` |
| C-2 三值内联未进档位表 | CONFIRMED | **已修**：提升为 `dockTitledIconSize` / `dockMinimizedThumbnailHeight` / `dockToolIconSize`，纳入 `TIER_TOKENS`（16 项全覆盖） | `Dock.qml:110-118`、`test_dock_compact_tier.py:TIER_TOKENS` |
| P-1 region 越界风险 | PLAUSIBLE | 不修，理由：`implicitHeight` 与 region 高度同帧同源（均由 `dockSurfaceHeight` 派生），无独立时钟；且改动前 autohide 已在运行时改变 region 高度，非 D1 新增面。留作部署观察项 | `Dock.qml:1053`、`:1169-1171` |
| P-2 sanitizeState 缺 dockCompact | PLAUSIBLE | 不修，理由：既有 bool 键 `dockAutoHide`、`dockMinimizedShelfEnabled` 同样不入 `sanitizeState`（grep 计数 0），JsonAdapter 对 bool 有类型强转。与既有风格一致 | `DesktopSettings.qml:701-720` |
| P-3 iconCode 空 | PLAUSIBLE | **不成立**：实为真实字形 U+EBA9（density_small），`od -c` 显示 `356 256 251`，fontTools 核验存在于 `assets/fonts/MaterialIconsRound.ttf`。Read 工具对私用区字符显示为空 | `DockPage.qml:36` |
| P-4 dockContentBoxX 前缀断言 | PLAUSIBLE | 不修，理由：该尾项已被 `test_content_box_collapses_to_chrome_in_standard` 的完整正则与「mask 回退」变异测试双重覆盖（变异 CAUGHT） | `test_dock_compact_tier.py:200-212` |
| P-5 内容盒用目标值 | PLAUSIBLE | 不修，理由：条内区域已被第二块 Region 全覆盖，差异仅在条上方透明 headroom 的瞬时命中，低危；子代理自评「低危，列出备查」 | `Dock.qml:173-177` |

## 完成判据核对

| 判据（引 task.md §6） | 是否满足 | 证据 |
|---|---|---|
| 1 标准档几何逐值不变 | 是 | 脚本逐令牌比对 `git show HEAD:Dock.qml`：16/16 令牌标准臂零偏差 |
| 2 紧凑档 56/36/通栏/齐平 | 代码满足，**观感待人工** | `Dock.qml:107`、`:93`、`:167`、`:1159` |
| 3 exclusiveZone=56 贴合 | 代码满足，**待人工** | `Dock.qml:1043` 仍绑 `dockSurfaceHeight`，无硬编码 |
| 4 标准档 mask 逐位等价 | 是 | 子代理 2 独立推导 + `PendingRegion::build()` 空矩形论证；变异测试 CAUGHT |
| 5 紧凑档条内空白命中 / headroom 穿透 | 代码满足，**待人工** | 条带高度 = `dockVisibleHeight`（玻璃高），不含 headroom |
| 6 开关切换 + 重启保持 | 代码满足，**待人工** | `DesktopSettings.qml:26/327/905`，写盘走 `writeAdapter()` |
| 7 两档放大波/autohide/弹跳/tooltip 正常 | 代码满足，**待人工** | 波为 rest-only 视觉；`dockSlideDistance=max(88, 条高)`；弹跳 `0.7×icon` 随档缩放（25.2 < 紧凑 headroom 39）；label 有 `y>=2` clamp |
| 8 qmllint 无新增告警 | 是 | 与 HEAD 同目录基线副本对比：新增告警仅来自新 `Region` 块（`--bare` 无法解析 `Region`，既有 3 处同类），无新告警类别 |
| 9 pytest 全绿 | 是 | **1043 passed, 306 subtests**（基线 1023 + 新增 20），0 失败 |
| 10 ≥2 子代理审查，CONFIRMED 全修 | 是 | 本文件 |

## 补充验证（主会话独立完成，非子代理）

- **变异测试 7/7 全捕获**：标准值回归 / 紧凑行高溢出 / 条带吞 headroom /
  mask 回退全 chrome / 缩略图溢出 / radius 改回旗标驱动 / 标题图标内联
- **测试锚点体检**：17 个断言锚点全部在真实源码中匹配，无「永不匹配」的假通过
- **真实 Qt 运行时**：`qmltestrunner` 跑 `tst_window_button_rectangle_tracking.qml`
  7/7 PASS、`tst_dock_image_loading_aggregation.qml` 6/6 PASS（`WindowButton`
  的 `rowHeight` 改动经真实场景实例化验证，非仅文本匹配）
- **着色器影响证伪**：紧凑 2048×56 与标准 1518×84 的 `size_detail` 同为 0
  （`postprocess.frag:119-120` 的 620/980 与 180000/420000 门），
  而部署配置 dock material 已有 `detail 1.0` 把两者钉满 → **无需改 KDL/着色器**
- **函数区抽查**（补子代理 1 未读部分）：`pinnedRestX`/`windowRestX` 纯令牌派生；
  `predictedMinimizeSlotSceneRect` 读 `dockMinimizedThumbnailWidth` 与
  `minimizedShelf.thumbnailHeight`（均档位驱动）；`hoverLabelYForItem` 的 `-28`
  是 null 守卫，真实路径由 `mapToItem` + `dockIconSize` 计算并 clamp 到 `y>=2`
- **多屏**：`shell.qml:1046` per-screen 实例化，`root.width` 为每屏各自宽度，
  `settingsService` 共享 → 各屏按自身宽度通栏，正确

## 最终结论

两条 CONFIRMED 已全部修复并经变异测试锁定；PLAUSIBLE 逐条处置（1 条证伪、
4 条记录不修理由）。**允许 commit**。

部署后仍需人工验收：判据 2、3、5、6、7（观感与实机交互）。
