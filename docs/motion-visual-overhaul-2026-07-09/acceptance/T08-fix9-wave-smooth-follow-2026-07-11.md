# T08-fix9 · Dock 横扫波形丝滑跟随 · 验收记录

日期：2026-07-11

## 用户反馈（fix8 后）

1. 横扫有波动跳动，方向正确，但**不够丝滑优雅**
2. 波形响应**太快**
3. 图标之间**动画衔接不好**（像一段段硬切）

## 根因

| 现象 | 原因 |
| --- | --- |
| 太快 | `dockMagFollowMs = 90` + `OutCubic`，每次 mousemove 重开 90ms 动画，跟手过硬 |
| 不丝滑 / 衔接差 | `NumberAnimation` 在目标连续变化时反复 restart，速度包络不连续；波形 range 2.75 偏窄，邻图标裙边不够 |
| 不能回 Spring | fix8 已证：`SpringAnimation.restart()` 每帧重开 → 整条抖 |

## 改动

### Motion.js tokens

| token | 前 | 后 |
| --- | --- | --- |
| `dockMagPeak` | 1.65 | **1.62** |
| `dockMagRangeIcons` | 2.75 | **3.2** |
| `dockMagFollowMs` | 90 | **170** |
| `dockMagSpring` | 3.6 / 0.48 | 3.2 / 0.52（仅保留；波形路径不用） |

### 跟随动画（`Dock.qml` pinned + `WindowButton.qml`）

- mag / push：`NumberAnimation` + `emphasizedDecel` → **`SmoothedAnimation`**
  - `duration: Motion.dockMagFollowMs`（170）
  - `velocity: -1`（按时长模式连续 retarget，中途改目标不硬切）
  - `easing: InOutQuad`（进出更柔）
- 仍禁止 `Spring.restart()`；玻璃 x/width 仍与 wave 无关

### 不变量（继承 fix8）

1. 玻璃 rest 固定  
2. 槽位 rest 固定，只动 scale + pushX  
3. 指针 rest-section 本地  
4. `computeSectionWave` 分区 clamp  
5. reduced motion：Behavior `enabled: false` → 瞬时跳目标  

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **90 passed** |

### 机械验证

```
rg -n 'dockMagFollowMs = 170|dockMagRangeIcons = 3.2|dockMagPeak = 1.62' tahoe-shell/components/Motion.js
rg -n 'SmoothedAnimation' tahoe-shell/components/{Dock,WindowButton}.qml
```

## 手测清单（请用户确认）

1. 光标从左到右横扫：波形连续，邻图标推开/回落**渐接**，无明显分段跳。
2. 体感比 90ms 慢一截，但不拖沓（约 170ms 级 settle）。
3. 玻璃条仍不抖、不随波变宽。
4. 离开 Dock 后图标平滑回 1.0 / push 0。

## 结论

横扫手感改为更宽、更慢的余弦裙边 + 连续 SmoothedAnimation 跟随；可作 `T08-fix9:` 单独提交回滚。
