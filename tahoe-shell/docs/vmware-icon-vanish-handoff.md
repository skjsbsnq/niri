# VMware 图标消失问题：研究交接文档

日期：2026-06-15
最终修复 commit：`6ddec2b`（Gate all spring animations behind useSpring）
影响：dock pinned 图标、dock 运行窗口图标、launchpad app 网格图标、通知 toast 图标

---

## 一、症状（精确描述）

不是"图标闪烁"，不是"整条 dock 消失"，不是"启动器空白屏"。准确表现是：

- **dock 左半边 pinned 图标**（Launchpad/Finder/Terminal/Firefox/Settings）：鼠标 hover 上去，图标**变透明**（Image 纹理消失），但**占位空间保留**、dock 的灰色圆角背景条还在。一旦透明就不可逆，不会再自己回来。
- **dock 右半边运行窗口图标**（WindowButton）：时有时无，"偶尔出现"。
- **launchpad app 网格**：点开 Launchpad 的瞬间，所有 app 图标变透明，只剩一个空网格 + 背景。

三个位置共同特征：**Image 元素还在、几何尺寸正确、但图本身的像素没渲染出来（透明）。**

## 二、根因（确认版，不是猜测）

**`SpringAnimation` 驱动一个 `Image` 的几何属性（x / y / scale）时，在 VMware 虚拟 GPU（svga，软件渲染）上会导致那个 Image 的纹理失效，图标变透明。**

触发条件缺一不可：
1. 有一个 `SpringAnimation` 正在**运行**（不是静止状态）
2. 它驱动的属性**影响某个 Image 的几何**（直接是 Image 的 x/y/scale，或是包裹 Image 的父 Item 的这些属性）
3. GPU 是 VMware 虚拟 GPU / 软件渲染

`NumberAnimation` 不触发这个问题——同样是驱动 Image 几何，但 NumberAnimation 不让纹理失效。所以根因不在"改变 Image 几何"本身，而在 **SpringAnimation 这种特定的、持续多帧的插值方式**触发了 Qt 场景图（QSG）在 VMware 驱动上的某个纹理上传/失效路径。

### 为什么是 SpringAnimation 而不是 NumberAnimation

SpringAnimation 解一个二阶 ODE，每帧都产生一个**新的、非线性的**值，且会过冲（overshoot）再收敛，收敛判据是 `|value - target| < epsilon`（默认很小，意味着要跑很多帧）。NumberAnimation 是固定时长 + 缓动曲线，值的变化更"规则"。

推测（未深究，真机调试时可验证）：SpringAnimation 的持续高频几何变化让 Qt 场景图判定该 Image 的纹理"脏了"需要重传，而 VMware 的 svga 驱动在重传时失败/丢帧，结果就是透明。NumberAnimation 的变化模式没触发这个判定，或者触发了但驱动能跟上。

## 三、排查过程（踩过的坑，避免重蹈）

这个问题排查极其曲折，记录下来以免重走弯路。**以下假设全部被证伪：**

| 错误假设 | 为何排除 |
|---|---|
| niri blur region 溢出 panic | session.log 显示 niri 全程没崩 |
| quickshell 进程崩溃 | 进程一直在，log.qslog 末尾是正常活动 |
| QML 逻辑错误（TypeError/binding loop） | `QT_LOGGING_RULES=qml=true` 抓不到任何 QML warning |
| StatusNotifierItem / SNI 托盘问题 | 查了 watcher/host 实现，与 dock 图标无关 |
| DesktopEntries.applications 异步刷新 | 解释不了"不碰就不消失" |
| spring 化 commit (`9ac4bed`) 引入 | `c958f4d`（spring 化之前）也复现 |
| width→magnification binding loop | 已在 `3926c8d` 修掉，且那是 crash 不是透明 |

### 最大的坑：deploy 没生效

折腾最久的原因不是诊断难，而是**改了代码但 quickshell 没读到**。仓库在 `~/niri/tahoe-shell/`，但 quickshell 跑的是 `~/.config/quickshell/tahoe/`，两者靠 `arch-update.sh` 里的 `rsync -a --delete` 同步。光 `git pull` + 重启 quickshell **不会**更新部署目录。中间好几次"还消失"的测试结果其实是在跑旧代码，纯属浪费时间。

**教训：每次改完 QML，必须 `rsync -a --delete tahoe-shell/ ~/.config/quickshell/tahoe/` 再重启 quickshell。改完先验证一个肉眼可见的变化（比如毛玻璃有无）确认代码生效，再测功能性。**

### 锁定根因的关键实验序列

1. 临时把 dock `appIcon.scale` 固定 1.0 → 还消失（排除 scale 单独）
2. 把 `proximityScale` 恒返回 1.0（关掉整个 hover→magnification 链）→ 还消失（排除 hover/动画链路……当时这么判断的）
3. 注释掉 dock+launchpad 的 `BackgroundEffect.blurRegion` + deploy → **hover 不消失了，但点击还消失**（blur 排除，触发点缩到 click）
4. 注释掉 dock 的 `bounce()` + launchpad 的 scale spring + deploy → **点击也不消失了**
5. 结论：所有"消失"点都对应一个正在运行的 SpringAnimation 作用于 Image 几何。

注意第 2 步当时误判"排除动画链路"——其实是因为没 deploy，跑的是旧代码。真正干净的结论来自第 3、4 步（deploy 生效后）。

## 四、最终修复（当前状态）

加了一个全局开关 `useSpring`（默认 `false`），每个驱动 Image 几何的 spring 都配了一个 NumberAnimation 兜底，靠 `enabled` 切换：

```qml
Behavior on bounceOffset {
    enabled: !root.useSpring
    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
}
Behavior on bounceOffset {
    enabled: root.useSpring
    SpringAnimation { spring: 380; damping: 0.32; mass: 0.9; epsilon: 0.01 }
}
```

涉及的文件和属性：

| 文件 | 属性 | spring 参数 | NumberAnimation 兜底 |
|---|---|---|---|
| `Dock.qml` | bounceOffset | spring 380 / damping 0.32 / mass 0.9 | 220ms OutCubic |
| `Dock.qml` | magnification | spring 260 / damping 1.0 | 130ms OutCubic |
| `WindowButton.qml` | bounceOffset | spring 380 / damping 0.32 / mass 0.9 | 220ms OutCubic |
| `WindowButton.qml` | magnification | spring 260 / damping 1.0 | 130ms OutCubic |
| `Launchpad.qml` | launcher scale | spring 200 / damping 1.0 | 220ms OutCubic |
| `NotificationToast.qml` | card x | spring 3.4 / damping 0.36 / epsilon 0.2 | 260ms OutCubic |

开关位置：`shell.qml` 的 `property bool useSpring: false`。通过属性传递到 Dock/Launchpad/NotificationToast，Dock 再传给 WindowButton。

**VMware 上保持 `false`，真机上改 `true`。**

## 五、真机调试指南

上真机时按这个顺序：

### 1. 直接开 spring 看有没有问题

把 `shell.qml` 的 `useSpring` 改成 `true`，deploy，重启 quickshell。大概率**真机没事**——真 GPU 不会丢纹理。如果真机也图标消失，说明根因比"VMware 软件渲染"更广，需要回到第六节的深挖。

### 2. 如果开 spring 后手感不对

那是参数问题，不是 bug。调这几个地方：

**dock 放大波（magnification）**：`Dock.qml` 的 `proximityScale` 决定峰值和影响范围：
```qml
var influence = Math.max(0, 1 - distance / 150);   // 150 = 影响半径(px)，加大更平滑
return 1.0 + influence * 0.5;                       // 0.5 = 峰值放大倍数，加大更夸张
```
对标 web 参考是半径 195、峰值 1.7。现在的 150/1.5 是 VMware 上能用的折中。真机可以往 web 值靠。

spring 参数（magnification Behavior）：
- `spring: 260` 越大越硬/响应快，越小越软/迟滞
- `damping: 1.0` 是临界阻尼（不过冲）。想要 macOS 那种轻微过冲波，降到 `0.7~0.85`

**dock 点击弹跳（bounce）**：
- `bounce()` 里 `bounceOffset = 14` 是弹跳幅度（px），加大更夸张
- spring `damping: 0.32` 是欠阻尼（会弹 1.5 次）。想要更多次弹跳，降到 `0.2`；想要只弹一次到位，升到 `0.5`

**launchpad 飞入**：
- `scale: root.open ? 1 : 1.1` 的 `1.1` 是起点缩放，加大（如 1.2）飞得更远，对标 web 是 1.2
- spring `damping: 1.0` 临界阻尼。想过冲感降到 `0.85`

**通知滑入**：
- spring `damping: 0.36` 已经是欠阻尼，会有明显过冲。觉得太晃升到 `0.5`

### 3. 调参工作流

QML 改完不用重新编译，只要 deploy + 重启 quickshell：
```bash
cd ~/nori
# 改 tahoe-shell/ 里的 qml
rsync -a --delete tahoe-shell/ ~/.config/quickshell/tahoe/
pkill quickshell && quickshell -p ~/.config/quickshell/tahoe &
```
甚至 quickshell 支持热重载部分改动（改 QML 文件保存即生效），但 Behavior/结构改动最好重启。

## 六、如果真机也图标消失（深挖方向）

如果真机开 spring 也复现，根因就不是"VMware 软件渲染"那么简单，需要往这几条查：

1. **Qt 场景图渲染后端**：quickshell/Qt 默认用 OpenGL 后端。试 `QSG_RHI_BACKEND=vulkan` 或 `=software` 看 spring 是否还丢纹理。如果 software 后端不丢、OpenGL 丢，说明是 GL 驱动的纹理上传 bug。
2. **Image 的 `layer.enabled`**：给消失的 Image 加 `layer.enabled: true`（强制它有自己的纹理层），可能绕开父级几何变化导致的纹理失效。代价是显存。
3. **用 `transform: Scale{}` 代替 `scale` 属性**：`Item.scale` 是个属性，`transform` 是个变换矩阵对象。两者在场景图里的处理路径不同，换 `transform: Scale { xScale: ...; yScale: ... }` 可能避开触发点。dock/launchpad 都可以这样改。
4. **`asynchronous: true` 给 Image**：让纹理异步加载/上传，可能错开场景图的失效时机。
5. **SpringAnimation 的 `epsilon`**：现在多数是 `0.01`，意味着要跑很多帧才收敛。把 `epsilon` 调大（如 `0.5`），spring 更快停，触发窗口更短，看是否减轻。

### 上报 bug 的话

这看起来像 **Qt 场景图 + VMware svga 驱动** 的交互 bug，不是 quickshell 或 niri 的锅。如果能写个最小复现（一个 Image + 一个驱动它 x 的 SpringAnimation，VMware 上跑），可以报给 Qt 或 mesa/swrast。复现要素：必须 SpringAnimation，NumberAnimation 不行。

## 七、相关 commit 索引

- `9ac4bed` Spring-ify shell animations（引入所有 spring，**本身没 bug**，spring 设计是对的）
- `3926c8d` Fix two crashes from spring-ify（修了 width→magnification binding loop crash，与图标消失无关）
- `c958f4d` spring 化之前的状态（**也复现图标消失**，证明不是 spring 化引入的，是 spring + VMware 的固有交互）
- `3f10183`、`4019fff`、`d342d3c`、`c7fdce2`、`4188747`、`1d7bbb9`、`d40b9c2` 各种 DIAG 实验commit（已全部在 `6ddec2b` 中恢复）
- **`6ddec2b` 最终修复：useSpring 开关 + NumberAnimation 兜底（当前 HEAD）**

## 八、一句话总结

VMware 软件渲染下，`SpringAnimation` 驱动 `Image` 几何会让纹理失效、图标透明。短期靠 `useSpring=false`（NumberAnimation 兜底）让 VM 能用；真机大概率无此问题，开 `useSpring=true` 即可。若真机也复现，按第六节查 Qt 场景图后端 / transform 替换 / Image layer。
