# Tahoe 日用桌面反腐化 Phase 7 验收记录

日期：2026-07-03

对应路线图：`daily-desktop-source-research-anti-corruption-roadmap-2026-07-03.md` Phase 7：niri 配置写入继续白名单化。

## 结论

Phase 7 已完成。

本阶段没有扩大 niri 配置写入面，没有增加快捷键写入能力，也没有把 `config.kdl` 当自由文本重排。`niri_settings_tool.py` 现在有机器可读的 `WRITABLE_FIELD_SPECS` 白名单，所有写入在解析 KDL 前先查表；未知字段、`binds`、非白名单 glass/material 字段和 shader/action 字段都会直接拒绝。

## 改动范围

- `tahoe-shell/services/niri_settings_tool.py`
  - 新增 `WRITABLE_FIELD_SPECS`，覆盖当前 70 个可写 field。
  - 每个 field 记录 `field`、`kdlPath`、`range`、`validation`、`managedBlock`、`rollback`。
  - `update_field()` 入口统一查白名单。
  - 收紧 `glass.*.*`，material 和 leaf field 都必须在白名单内。
- `tahoe-shell/tests/test_niri_settings_tool.py`
  - 新增白名单完整性测试。
  - 新增 read-only/未知字段拒绝测试。
  - 新增 malformed KDL、注释保留、多行 raw shader、缺失 block、多输出 `output.scale` 和 guardrail 测试。
- `tahoe-shell/tests/fixtures/niri-settings/`
  - 新增 `malformed-layout.kdl`。
  - 新增 `comments-and-multiline.kdl`。
  - 新增 `missing-blur.kdl`。
  - 新增 `missing-child-block.kdl`。
  - 新增 `multi-output.kdl`。
- `tahoe-shell/docs/niri-settings-write-whitelist-2026-07-03.md`
  - 记录每个可写 field 的 KDL path、range、validation 和 rollback 行为。

## 验收点

- 白名单字段总数为 70：
  - layout 10 个。
  - tahoe-glass 35 个。
  - blur 5 个。
  - input 7 个。
  - output.scale 1 个。
  - animations spring 12 个。
- `binds` 仍然只读，没有 write path。
- `glass.panel.xray`、未知 material、`animations.window_open.duration_ms`、`input.mouse.*`、`variable-refresh-rate` 等非白名单字段被拒绝。
- malformed KDL 在编辑前失败。
- inline comments 和 raw shader 多行文本在无关写入后保持不变。
- 目标顶层 managed block 缺失时拒绝写入。
- 目标父 block 存在但子 block 缺失时，只在 managed 父 block 内创建最小子 block。
- `output.scale` 遇到多输出配置时拒绝写入。
- `config_guardrails()` 继续阻止 active `variable-refresh-rate` 和 broad `namespace="^quickshell"`。
- validate 失败的原子写回测试仍覆盖 live config 不变和临时文件清理。

## 验证

已执行：

```sh
python3 -m py_compile tahoe-shell/services/niri_settings_tool.py tahoe-shell/tests/test_niri_settings_tool.py
```

结果：通过。

```sh
python3 tahoe-shell/services/niri_settings_tool.py read --config config/niri/tahoe-phase0.kdl
```

结果：退出码 0，返回 `ok: true`，能读取 layout、glass、blur、input、animations 和 read-only binds。

```sh
bash scripts/check-tahoe-glass-guardrails.sh
```

结果：通过。

```sh
python3 -m pytest tahoe-shell/tests/test_niri_settings_tool.py
```

结果：通过，13 个测试全部通过。

```sh
python3 -m pytest tahoe-shell/tests
```

结果：通过，38 个测试全部通过。

```sh
git diff --check -- tahoe-shell/services/niri_settings_tool.py tahoe-shell/tests/test_niri_settings_tool.py tahoe-shell/tests/fixtures/niri-settings tahoe-shell/docs/niri-settings-write-whitelist-2026-07-03.md
```

结果：通过。

## 未执行项

未做实机会话设置面板交互验收；本阶段只完成 helper 白名单、fixture 测试、文档和静态/单元验证。
