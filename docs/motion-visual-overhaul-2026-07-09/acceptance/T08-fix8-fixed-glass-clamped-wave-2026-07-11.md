# T08-fix8 · 玻璃固定 + 分区钳制波形 · 验收记录

日期：2026-07-11

## 用户反馈（fix7 后）

1. **整条 Dock 依旧抖**
2. **最右 pinned 图标挤进右侧最小化区**

## 根因（直接）

| 现象 | 原因 |
| --- | --- |
| 整条抖 | ① fix7 仍让 glass `width/x` 随 wave extras 变；② **每次 mousemove `SpringAnimation.restart()`** 造成滞后/过冲，观感像整条在抖 |
| 挤进最小化区 | 未压缩 packed 宽；`pushX` 可跨 section；无硬 clip |

## 不变量（本轮硬保证）

1. **玻璃 x/width 永不依赖 wave** — `anchors.horizontalCenter` + rest content；extras 恒 0
2. **槽位 rest 固定** — 只动 `scale` + `pushX`
3. **指针 rest-section 本地**
4. **`computeSectionWave` 压缩 extra 宽**，使 packed ≤ host，再 cursor-shift + per-icon fence
5. **mag/push 直接绑定** — 禁止 wave 路径 SpringAnimation
6. **section + Flickable `clip: true`**

## 改动

- `Dock.qml`：固定 glass；`computeSectionWave`；direct mag/push；分区 clip
- `WindowButton.qml`：mag/push 直接绑定 target
- 测试：断言 extras=0、无 magSpring、direct bind

## 验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **90 passed** |
| 部署 + 重启 quickshell | Configuration Loaded；无 Dock map/binding 报错 |

## 手测

1. 横扫：玻璃条位置/宽度不动（不抖）
2. 右缘 pinned 不进入最小化区
3. 波形仍有放大与邻图标推开（在分区内）
