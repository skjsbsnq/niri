# A7 审查记录

日期：2026-08-11
子代理数：4（第 1 轮 2 个 + 第 2 轮 2 个；两轮均按子代理协议在 10 分钟超时后介入收集结果）

## 各子代理结论

### 子代理 1（Hubble，第 1 轮）
- 结论：REJECT
- CONFIRMED：
  - C1a：`resizePlacement`（WidgetGrid.js）垂直锚点方向与屏幕直觉相反。
    网格 row 从屏幕底部数起（`yPxForCell` = screenHeight − (row+rows)*cellSize），
    原实现「bottom-* 固定上缘、top-* 固定下缘」，导致拖底边/顶边/四角时长反方向
    （Widget.qml 的 6 个垂直相关手柄锚点错位），且结构测试把错误算术固化。
- PLAUSIBLE：P1 拖动/resize 多点触控互斥不完整；P2 begin 时上一轮动画在飞导致
  press 映射偏移；P3 冲突反馈 Timer 断言空转；P4 冲突横幅与「完成」按钮重叠；
  P5 catalog 与 TIER_SIZES 两份档位表耦合（非违规）。

### 子代理 2（Aquinas，第 1 轮）
- 结论：REJECT
- CONFIRMED：
  - C1b：resize 手柄坐标映射错误 —— 手柄 MouseArea 局部原点偏离小部件原点
    （锚在边缘），`mouse.x/y` 被当作小部件局部坐标直接 `inst.mapToItem`；
    第一次换档判定因常量偏移相消看似正确，换档后几何变化使偏移不再抵消，
    第二次换档起方向反噬（medium→large 永远切不上去）。
  - C2：冲突拒绝后反向回拖会触发一次 no-op 写盘 —— `lastTier` 被冲突与成功
    两条路径共用，`switched` 无条件置真，与「被拒操作不写盘」注释矛盾。
- PLAUSIBLE：P1 冲突横幅被 widgetLayer 遮挡（声明顺序在后）；P2 begin 未停
  上一轮 resize 动画；P3 weather/calendar 三档视觉适配未验证。

### 子代理 3（Anscombe，第 2 轮，复核修复）
- 结论：APPROVE
- CONFIRMED：无（C1a/C1b/C2 均已闭合）
- PLAUSIBLE：P1 冲突横幅与顶排小部件短暂视觉重叠（1.2s，z:50 覆盖，非输入层）；
  P2 `resizeRejectedVisible` 退出编辑模式后残留至多 1.2s；P3 测试对 C1b 只断言
  一处 mapFromItem；P4 begin 时动画在飞的手柄视觉偏移（方向数学不受影响）；
  P5 qmllint 环境缺 import path（非代码问题）。

### 子代理 4（Banach，第 2 轮，复核修复）
- 结论：APPROVE
- CONFIRMED：无（C1a/C1b/C2 均已闭合；node 实跑 8 锚 grow 不变式 + grow→shrink
  回原点）
- PLAUSIBLE：P1 冲突横幅与顶排小部件视觉重叠（判据口径：roadmap「不产生重叠」
  指小部件互相不重叠，横幅属临时反馈）；P2 tr 角手柄大部分被删除按钮覆盖
  （z 顺序刻意取舍，删除优先）；P3 settleWidgets 只补 x/y 不补 width/height
  （commit 动画在飞时退出编辑态，width/height 动画 ≤180ms 跑完至 config 终值，
  终点正确）；P4 `switched` 与 currentTier 冗余（显式闩存，非状态双份）。

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| resizePlacement 垂直锚点方向反（Hubble C1a） | CONFIRMED | 已修 | `WidgetGrid.js` resizePlacement 改为屏幕空间角语义：top-* 固定上缘（row = row+curRows−rows）、bottom-* 固定下缘（row 不变）；Widget.qml 8 手柄 anchor 映射与注释同步；node 测试补 topFixed/bottomFixed 断言 |
| 手柄坐标映射错误（Aquinas C1b） | CONFIRMED | 已修 | Widget.qml onPressed/onPositionChanged 两处均 `root.mapFromItem(handle, mouse.x, mouse.y)` 先转小部件局部坐标；宿主仍按小部件局部坐标 mapToItem；测试断言两处调用（count==2） |
| 冲突拒绝后 no-op 写盘（Aquinas C2） | CONFIRMED | 已修 | `lastTier` 拆为 currentTier（仅成功换档更新）+ rejectedTier（被拒档位）+ switched；commit 门 = switched && currentTier !== tier；被拒与放大又缩回起点均不写盘 |
| 拖动/resize 多点互斥不完整 | PLAUSIBLE | 已修 | beginWidgetDrag 增加 `root.resizeActive` 门；beginWidgetResize 增加 `root.dragActive` 门 |
| begin 时上一轮动画在飞 | PLAUSIBLE | 已修 | beginWidgetResize 先 mapToItem（几何跳变前）再停四轴动画 + settleWidgets，快照取稳定几何 |
| 冲突横幅与「完成」按钮重叠 / 被小部件遮挡 | PLAUSIBLE | 已修 | bannerLayer z:50（高于 widgetLayer、低于完成按钮 z:100）；resize 横幅 topMargin 96（y≈96–140，与按钮 y 48–80 无重叠） |
| 冲突反馈 Timer 断言空转 | PLAUSIBLE | 已修 | test_widget_resize.py 改为从 `id: resizeRejectHide` 起切片断言 repeat:false/interval |
| 退出编辑模式后横幅残留 | PLAUSIBLE | 已修 | exitEditMode 末尾 `resizeRejectedVisible=false; resizeRejectHide.stop()`；测试断言 |
| 横幅与顶排小部件短暂视觉重叠 | PLAUSIBLE | 不修，理由：临时反馈（1.2s 自隐、z:50、无输入），roadmap「不产生重叠」判据指被拒换档后小部件互不重叠（canPlace 保证）；任意位置横幅必有覆盖可能，属反馈层固有性质 |
| tr 角手柄大部分被删除按钮覆盖 | PLAUSIBLE | 不修，理由：z 顺序刻意保证删除按钮优先（A6 既有行为，G-7）；tr 仍保留 y0–6 条带可点；A7 判据未要求 8 手柄全部可达 |
| settleWidgets 不补 width/height | PLAUSIBLE | 不修，理由：退出编辑态时 width/height 动画 ≤180ms 跑完至已持久化 config 终值，终点正确、无状态残留；补送注释仅措辞差异 |
| switched 与 currentTier 冗余 | PLAUSIBLE | 不修，理由：显式闩存可读性优先，非同一状态双份维护（G-6 不适用） |
| catalog 与 TIER_SIZES 耦合 | PLAUSIBLE | 不修，理由：catalog 声明各小部件可用档位（库 tab 消费），TIER_SIZES 是换算表；两者被测试锁定一致（A7 判据「库 tab 标注与实际可切换档位一致」） |
| weather/calendar 三档视觉适配 | PLAUSIBLE | 不修，理由：全部小部件布局按 width/height 自适应（锚链/自适应字号），三档下几何不重叠；极端矮屏沿用 A6 部署已确立的 topArea clip 兜底（只裁切不重叠） |

## 完成判据核对

| 判据（引 roadmap.md A7） | 是否满足 | 证据 |
|---|---|---|
| 三档均可互相切换，视觉与布局正确 | 是 | WidgetGrid.js tierIndex/sizeForTier/resizeTargetTier/resizePlacement 纯函数 + node 实测（8 锚 grow/shrink 不变式）；8 手柄全边缘/四角覆盖；catalog 全三档 |
| 冲突场景（空间不足）被正确拒绝且有反馈，不产生重叠 | 是 | updateWidgetResize 走 canPlace 门；被拒置 rejectedTier + showResizeRejected 横幅「无法调整大小：空间不足」；canPlace 保证换档矩形不与其它小部件重叠 |
| 换档动画无弹簧 | 是 | grep 无 SpringAnimation；resize 几何全 NumberAnimation + Motion.elementResize(null)（P-1/P-3）；结构测试断言 |
| 持久化正确；重启后尺寸一致 | 是 | commit 恰一次 persistConfig（A-C5）；config 存 {id,size,col,row}，重启经 gridStateFromConfig/serializeEntries/colsForSize/rowsForSize 闭环还原跨度 |
| A4 库 tab 中标注的可选尺寸与实际可切换档位一致 | 是 | widgetCatalog 四个条目均声明 ["small","medium","large"]，defaultSize 在三档内；test_left_sidebar_library_tab.py + test_widget_resize.py 断言 |
| pytest 全绿 | 是 | 全量 `python -m pytest tests/`：1168 passed, 1204 subtests passed（改动后最终一轮） |
| qmllint 无新增告警 | 是 | `/usr/lib/qt6/bin/qmllint --bare -I /usr/lib/qt6/qml -I /home/wwt/niri/quickshell/build-tahoe/qml_modules`：仅既有 WidgetHost 3 条告警，无新增 |
| 禁弹簧/禁硬编码 duration/禁 DragHandler-DropArea | 是 | 三个 grep 全空 |

## 最终结论
第 1 轮 2 个子代理均 REJECT（共 3 个 CONFIRMED），已全部修复并经第 2 轮 2 个
独立子代理复核：均 APPROVE，无 CONFIRMED。PLAUSIBLE 项已修 6 条、记录为已知
遗留 6 条（均给出不修理由）。允许 commit。
