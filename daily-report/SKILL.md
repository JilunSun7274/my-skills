---
name: daily-report
description: Daily work-journal management. Use when user invokes /daily-report (or asks to write/update today's daily report) to summarize today's Cursor 和 Claude Code agent sessions into a Product/Milestone/Action/Task hierarchy and emit a daily report.
---

# Daily Report Skill

把一天里跟 Cursor 和 Claude Code agent 的交互内容，归并进个人的工作进程层级结构，并产出 / 更新当日日报。

**Journal root**:           `~/projects/work-journal/`
**Cursor transcript root**:  `~/.cursor/projects/Users-jilunsun-projects/agent-transcripts/`  (env: `CURSOR_TRANSCRIPT_ROOT`)
**Claude transcript root**:  `~/.claude/projects/`                                            (env: `CLAUDE_TRANSCRIPT_ROOT`)
**Skill scripts**:           `~/projects/my-skills/daily-report/scripts/`
**Skill templates**:         `~/projects/my-skills/daily-report/templates/`

> 这些 root 路径在本文件里集中定义。如果用户搬迁了目录，只改这里。

---

## Invocation

| Command | Mode |
|---|---|
| `/daily-report` | **INGEST** — 汇总今天 |
| `/daily-report YYYY-MM-DD` | **INGEST** — 汇总指定日期 |
| `/daily-report <path>... [<NL...>]` | **INGEST + FOCUS** — 汇总今天 + 分析路径产出 |
| `/daily-report YYYY-MM-DD <path>... [<NL...>]` | **INGEST + FOCUS** — 指定日期 + 路径 |
| `/daily-report status` | **STATUS** — 打印活跃 Product/Milestone/Action 树 |
| `/daily-report lint` | **LINT** — 健康检查 |
| `/daily-report query <自然语言问题>` | **QUERY** — 在 journal 上回答问题 |

> **FOCUS** 不是独立 mode，是 INGEST 的 add-on：只要 INGEST 解析后得到 ≥1 个有效路径（绝对路径或 `~/...`），就触发对该路径的当日产出分析。`status` / `lint` / `query` 子模式不支持 FOCUS。

参数解析约定（在 slash command 里）：

- 第一个 token 是 `^status$` / `^lint$` / `^query$` → 对应模式（不进 FOCUS 解析）
- 第一个 token 是 `YYYY-MM-DD` → INGEST(那天)；剩余 tokens 进 FOCUS 解析
- 否则 → INGEST(今天)；全部 tokens 进 FOCUS 解析

FOCUS 解析委托脚本（path / NL / 日期分离）：

```bash
python3 ~/projects/my-skills/daily-report/scripts/parse_focus_args.py "$ARGUMENTS"
# 输出: {"target_date":..., "paths":[...], "nl_instruction":..., "warnings":[...]}
```

- 路径识别**只接受绝对路径（`/...`）与 home-relative（`~/...`、`~`）**。`./foo`、`foo/bar` 之类相对路径一律按自然语言处理（slash command 跨多 cwd，CWD 不可靠）。
- glob（含 `*?[`）展开后最多保留 10 条，超出 → warn。
- 不存在的路径 → warn，剩余文本拼回 nl_instruction，不让流程崩。

---

## Four-level hierarchy

```
Product       — 月/年级别交付物（如 "UltraData Studio"）
 └─ Milestone — 周/月级别迭代周期（如 "v3 上线"）
     └─ Action — 日级别要交付的具体功能 / 文档（如 "LanceDB V2 Catalog 切换"）
         └─ Task — 单次 agent session（Cursor / Claude Code）粒度的执行条目（只在日报里作为 checklist 出现，不单独成文件）
```

- 前 3 层是**显式文件 / 目录**，由 frontmatter 携带元数据
- Task 是日报内的 `- [x]` 行，归属通过日报里的 `## Action: <id>` 子标题决定

---

## Data layout (under Journal root)

```
work-journal/
├── index.md                 # 活跃 Product / Milestone / Action 概览，agent 维护
├── log.md                   # 每次执行追加一条
├── products/
│   └── <product-slug>/
│       ├── README.md
│       └── milestones/
│           └── <milestone-slug>/
│               ├── README.md
│               └── actions/
│                   └── <action-slug>.md
└── daily/
    └── YYYY/MM/YYYY-MM-DD.md
```

`slug` 规则：kebab-case ASCII，不超过 40 字符；中文名放在 `name` 字段里。

---

## Frontmatter schemas

### Product (`products/<slug>/README.md`)

```yaml
---
id: ultradata-studio
name: UltraData Studio
status: active        # active | paused | shipped | archived | draft
owner: jilun
created: 2025-09-01
updated: 2026-05-26
---
```

### Milestone (`products/<slug>/milestones/<slug>/README.md`)

```yaml
---
id: 2026-Q2-v3-release
name: v3 上线
status: planning      # planning | in-progress | shipped | dropped | draft
product: ultradata-studio
planned_start: 2026-04-01
planned_end:   2026-06-30
actual_start:  2026-04-15
actual_end:    null
---
```

### Action (`products/<slug>/milestones/<slug>/actions/<slug>.md`)

```yaml
---
id: lance-v2-migration
name: LanceDB V2 Catalog 切换
status: in-progress   # todo | in-progress | blocked | done | dropped | draft
milestone: 2026-Q2-v3-release
product: ultradata-studio
planned_date: 2026-05-26
actual_date: null
updated: 2026-05-26
---

# LanceDB V2 Catalog 切换

## 目标 / 验收

<一句话目标，1-3 条验收标准>

## 进展

<手写或 agent 追加的进展段落>

## Recent Activity
<!-- agent-managed: 由 /daily-report 自动追加 -->
- 2026-05-26 (session cu-c7c5a075) 调通 V2 catalog 初始化路径
```

### Daily Report (`daily/YYYY/MM/YYYY-MM-DD.md`)

日报固定 **3 个顶层 Section**：`## 今日总结` / `## 明日计划` / `## 风险点`。

`## 今日总结` 内部按 **3 个 bucket** 分类：

| Bucket | 含义 | 数据来源 |
|---|---|---|
| **Design** | 文档编撰、设计、需求梳理；线下讨论 / 对齐 | session（自动） + 用户手写（线下） |
| **Implement** | 实际完成的代码 commit 工作 | session（自动） |
| **Learn** | 对知识、概念的学习 | session（自动） |

每个 bucket 内再按 `#### Action: <id>` 分组。一个 Action 可同时出现在多个 bucket 内（不同 bullet 落不同类）。

```yaml
---
date: 2026-05-26
sessions: [cu-c7c5a075, cc-26731439]
focus_paths: [/Users/jilunsun/projects/mb-data-pipe]
status: draft         # draft | reviewed
generated_at: 2026-05-26T19:30:00+08:00
---

# 2026-05-26 日报

> TODO: 本次自动新建了 N 个草稿条目，请审阅并修改 status。  <!-- 仅当本次有 draft 新增时插入 -->

## 今日总结
<!-- agent-managed: 按 bucket 分组（Design / Implement / Learn），bucket 内按 Action 分组；agent 只追加 bullet，不修改/删除已有 bullet -->

### Design
<!-- 文档编撰由 session 自动归类；线下讨论 / 对齐由用户在发布日报时手写补充（直接在对应 Action 下加 bullet，不带 session id 即可，agent 不会改写） -->

#### Action: lance-v2-migration  <!-- ultradata-studio / 2026-Q2-v3-release -->
- [x] (session cu-c7c5a075) 起草 V2 catalog 迁移方案 doc
- (offline) 与 storage 同学对齐 OBS PFS 的迁移窗口  <!-- 用户手写示例 -->

### Implement

#### Action: lance-v2-migration  <!-- ultradata-studio / 2026-Q2-v3-release -->
- [x] (session cu-c7c5a075) 调通 V2 catalog 初始化路径
- [ ] (session cc-26731439) eval 阶段 schema 报错，待修

### Learn

#### Action: __uncategorized__
- [x] (session cu-c7c5a075) 学习 thrift / protobuf 编码原则与 wire format 选择策略

## 明日计划
<!-- human-editable + agent-augmentable:
     - 人工写本段主体内容
     - agent 在 INGEST 时可在末尾追加 "> 建议: ..." 形式的 bullet，但绝不修改/删除已有行 -->
- [ ] <由用户写/agent 提议>

## 风险点
<!-- agent-extracts + human-editable:
     - agent 自动从今天的 session 抽取：had_errors=true、未完成的 [ ]、__uncategorized__、长期堆积的 draft
     - 人工可补充非技术风险（人手、进度、对外承诺等）
     - 已有 bullet 不删除，只追加 -->
- <由 agent 抽取或人工写>
```

---

## Mode: INGEST

### Step 1 — Read journal state

```
Read  ~/projects/work-journal/index.md
Read  last 30 lines of  ~/projects/work-journal/log.md
```

如果 `products/` 不存在或为空，**不要执行 INGEST**，改为输出 Bootstrap 引导（见底部 Bootstrap 段）。

### Step 2 — List today's sessions

```bash
bash ~/projects/my-skills/daily-report/scripts/list_today_sessions.sh        [YYYY-MM-DD]   # Cursor
bash ~/projects/my-skills/daily-report/scripts/list_today_claude_sessions.sh [YYYY-MM-DD]   # Claude Code
```

不传日期 = 今天（本地时区）。两个脚本各自输出每行一个 JSONL 绝对路径（已过滤掉 sidechain / `subagents/` 目录）。把两份结果合并起来作为本次要摄入的会话集合。

如果两份输出都为空：在日报里写一行 `今天没有 Cursor / Claude Code session 活动`，但仍然走 Step 7 写 log。

### Step 3 — Digest each session

按来源派发：路径里包含 `/.claude/projects/` 用 Claude digester，否则用 Cursor digester。

```bash
# Cursor 会话
python3 ~/projects/my-skills/daily-report/scripts/digest_session.py        <jsonl_path>
# Claude Code 会话
python3 ~/projects/my-skills/daily-report/scripts/digest_claude_session.py <jsonl_path>
```

两边输出**同一个 JSON schema**，Claude 多一个 `cwd` 字段：

```json
{
  "session_id": "cc-26731439",
  "start_time": "2026-05-27T11:17:04.336Z",
  "end_time":   "2026-05-27T12:42:00.000Z",
  "user_queries": ["...", "..."],
  "tool_signals": [
    {"kind": "Write", "description": "Create AGENTS.md"},
    {"kind": "Bash",  "description": "uds-dev up"}
  ],
  "assistant_final_text": "<最后一条 assistant 主消息的前 1500 字>",
  "touched_paths": ["/Users/jilunsun/projects/mb-data-pipe/...", "..."],
  "had_errors": false,
  "cwd": "/Users/jilunsun/projects/mb-data-pipe"
}
```

- `session_id` 一定带前缀：Cursor 是 `cu-XXXXXXXX`，Claude Code 是 `cc-XXXXXXXX`。
- `cwd` 仅 Claude Code 输出非空；Cursor digester 不输出该字段。
- `touched_paths` 是脚本从 Write/Edit/Bash 等命令里抽出的，**很重要**——和 `cwd` 一起决定"这条 session 是为哪个 Product 干活"。

### Step 3.5 — Analyze focus paths (if any)

若 `parse_focus_args` 输出的 `paths` 非空，对每条路径调：

```bash
python3 ~/projects/my-skills/daily-report/scripts/analyze_focus_path.py \
    --path <abs-path> \
    --date <target_date> \
    --nl '<nl_instruction 或默认 "总结今天该路径下的产出">'
```

每次输出一个 `focus_digest`，schema 与 session digest **同形**（也有 `touched_paths`，路由复用 Step 5a）。差异：

- `focus_digest` 没有 `cwd` / `user_queries` / `tool_signals`。
- 多出 `kind`（`git_dir|fs_dir|file|missing`）、`git` / `files_changed` / `file_content` / `is_binary` / `summary_hint` / `nl_instruction`、`warnings`。
- `kind=missing` 不进 Step 5 路由，但要把 `focus_path` 写入 Step 7 log 的 warnings 段。

汇总成 `focus_digests` 列表，与 `session_digests` 一起带入 Step 4 / 5。

### Step 4 — Load active Action map

枚举 `products/*/milestones/*/actions/*.md`（跳过 `status: dropped` 和 `status: archived`），读 frontmatter 构建：

```
action_id → { name, product, milestone, status, file_path, planned_date, last_updated }
```

同时记录每个 Product 的根目录路径（用来匹配 `touched_paths`）。

### Step 5 — Map each session → (Action, Bucket)

每条 bullet 需要确定**两个**归属：哪个 Action（行级），以及落到 Design / Implement / Learn 哪个 bucket（行级）。两者独立判定。

**5a. 选 Action**（同旧逻辑）：

1. **先看 digest 的 `cwd`（仅 Claude Code）**：如果 `cwd` 落在某 Product README 的 `work_root` 之下（前缀匹配），直接归该 Product。例：`cwd=/Users/jilunsun/projects/mb-data-pipe` → `work_root: /Users/jilunsun/projects/mb-data-pipe` → **UltraData Studio**；`cwd=/Users/jilunsun/projects/my-skills` → **Cursor Skills**。`cwd` 命中后再走关键词匹配选 Action。注意若 `cwd` 是多个 `work_root` 的共同父目录（例如 `/Users/jilunsun/projects`），无法区分时回退到下一条规则。
2. **回退到 `touched_paths` 前缀匹配 `work_root`**：路径明显落在某个 Product 的 work root 下，那这条 session 至少属于这个 Product。（Cursor 与 cwd 未命中的 Claude 共用此规则。）
3. **再看 user_queries / assistant_final_text 关键词**：和现存 active Action 的 name / id 做关键词匹配（人名/术语命中即可），命中就归到那个 Action。
4. **命中不了**：
   - 但能确定 Product / Milestone → 提议新建 Action，`status: draft`，slug 用 user_query 抽出的关键词。
   - Product 也判定不了 → 归到 `#### Action: __uncategorized__` 段。

**5b. 选 Bucket**（每个 user_query 对应的 bullet 单独判）：

| Bucket | 命中信号 |
|---|---|
| **Design** | tool_signals 集中在 `Write` / `StrReplace` 到 `.md` / `.rst` / `docs/`；user_query 含 "需求 / 设计 / 梳理 / 对齐 / 方案 / 文档"；Plan mode；触及 `**/requirements/**` 或 `**/docs/**` 路径 |
| **Implement** | tool_signals 含 `Write` / `StrReplace` 到源码（`.py` / `.ts` / `.rs` / `.go` / `.js` / ...）；Shell 跑 `git commit` / `pytest` / `npm test` / `cargo build` / `uv sync`；touched_paths 命中 `src/` / `lib/` / `app/`；user_query 含 "实现 / 修复 / 重构 / fix / implement / refactor / 跑通" |
| **Learn** | user_query 以 `/learn-everything` 触发；含"为什么 / 解释 / 原理 / 学习 / 是什么 / how does"；触及 `KnowledgeGraph/` / `wiki/` 路径；assistant_final_text 大段在解释概念 |

**判定规则**：

- 一个 user_query 横跨多类时，取**最强信号**那一类。无法判定时默认 `Design`（最 catch-all）。
- 同一 session 的多条 user_query 可以落到不同 bucket（很常见：先 Design 起草，再 Implement 落地，途中插一段 Learn）。
- 操作类（如跑 `/daily-report`、调整 work-journal）按"动了什么"分类：动 markdown / 重整结构 → Design；动源码 → Implement。

**5c. focus_digest 的 Action 路由**（仅当存在 focus_digests 时）：

复用 5a 的规则 2（`touched_paths` 前缀匹配 `work_root`）+ 规则 3（关键词）+ 规则 4（命中 Product 但无 Action → 新建 draft）：

1. `focus_digest.touched_paths` 任一前缀匹配某 Product `work_root` → 归该 Product。
   - `kind=git_dir`：`touched_paths` 已含 `toplevel`，几乎一定命中。
   - `kind=file`：仅 `focus_path` 一条，路径命中即归属。
   - `kind=fs_dir`：`focus_path` 自身 + 当日变更文件路径全都参与匹配。
2. 在该 Product 的活跃 Actions 里，用 `nl_instruction` + `summary_hint` + git commit messages（若 `kind=git_dir`）做关键词匹配选 Action。
3. Product 命中但 Action 命不中 → 在该 Product / 当前 Milestone 下提议新建 `status: draft` Action，slug 用 `focus_path` basename（kebab-case）。
4. Product 都命不中 → `#### Action: __uncategorized__`。

`kind=missing` 不参与路由（不写入日报，但 Step 7 log + 风险点段记录之）。

**5d. focus_digest 的 Bucket + bullet 生成**（仅当存在 focus_digests 时）：

Bucket 选择信号：

| Bucket | 命中信号 |
|---|---|
| **Design** | 多数 touched_paths 命中 `*.md` / `*.rst` / `**/docs/**` / `**/requirements/**`；nl_instruction 含"设计 / 文档 / 梳理 / 方案" |
| **Implement** | 多数 touched_paths 是源码扩展名（`.py` / `.ts` / `.rs` / `.go` / `.js` / `.java` / `.c` / `.cpp` / `.h` / ...）；`kind=git_dir` 且 `commits_today` 非空；nl_instruction 含"实现 / 修复 / 重构 / fix / refactor" |
| **Learn** | `kind=file` 且 nl_instruction 含"学习 / 解释 / 原理 / 笔记 / 是什么 / 为什么" |

混合或都不沾 → 默认 **Design**。

**bullet 文本生成（agent 自我推理，关键）**：

脚本只采集原始证据（git diff / 文件内容 / mtime 列表）。bullet 中文文本必须由**执行 skill 的 agent**（即当前 Claude Code 会话）阅读 `focus_digest` 后产出。Agent 按以下 prompt 模板自我推理：

> 你正在为日报写一条 focus bullet。
>
> - 路径：`<focus_digest.focus_path>`
> - 日期：`<focus_digest.target_date>`
> - 类型：`<focus_digest.kind>`
> - 用户 NL 指令：`<nl_instruction 或 "总结今天该路径下的产出">`
>
> 原始数据摘录（按 `kind` 选择性嵌入，总长 ≤4000 字符）：
> - `kind=git_dir`：`git.diffstat` + `git.commits_today` 的 sha/msg + 截断后的 `git.diff_body` + `git.uncommitted` 摘要
> - `kind=fs_dir`：`files_changed` 列表
> - `kind=file`：`file_content`（或 `is_binary=true` 时只描述元数据）
>
> 请用 **1-3 句中文** 总结今天此路径下发生了什么，并尽可能回应用户的 NL 指令。
> - 提及关键文件名或 commit 主题（如有）
> - 不要包含日期前缀（日报已是日期上下文）
> - 不要超过 150 个汉字
> - 不要包含 `-` 或 `*` 等 list marker
> - 只返回 bullet 文本本身

**bullet 落盘格式**：

```
- (focus <short-path>) <agent 生成的总结>
```

`<short-path>` 缩写规则：
- 路径以 `$HOME/` 开头 → 替换为 `~/`
- 路径在某 Product `work_root` 下 → `<product-slug>:<rel-path>`（例：`ultradata-studio:docs/v3-plan.md`；若就是 work_root 本身则用 `<product-slug>:.`）
- 其它 → 保留绝对路径

**focus bullet 默认不带 checkbox**（不是任务，是产出快照），形如 `- (focus ...) ...`。用户手动改成 `[ ]` 后 agent 后续 INGEST 不会改写。

**输出格式**：

```
- [x] (session <prefixed-id>) <一句话总结这条 user_query 做了什么>
```

`<prefixed-id>` 是 digest 输出的 `session_id`，必带 `cu-` / `cc-` 前缀（例：`cu-c7c5a075` / `cc-26731439`）。

`[x]` vs `[ ]` 判定：

- 任务在 session 内有明确"完成"信号（最后一条 assistant 是总结/交付）→ `[x]`
- assistant 还在追问、或 user 在最后一条 query 里报错 → `[ ]`

**用户手写 bullet（线下讨论 / 对齐）**：

- 用户可以在任意 `#### Action:` 下追加不带 `(session ...)` 前缀的 bullet（推荐 `(offline) ...` 标注）。
- agent 在后续 INGEST **绝不修改 / 删除**这些 bullet。

### Step 6 — Upsert files

**Daily report**（`daily/YYYY/MM/YYYY-MM-DD.md`）：

- **不存在**：用 `templates/daily-report.md` 套模板创建，3 个 Section 都要在；`## 今日总结` 内 3 个 bucket 子标题（`### Design` / `### Implement` / `### Learn`）也要在（即使为空）。
- **已存在**：
  1. 读 frontmatter，把本次 session_id（带 `cu-`/`cc-` 前缀）追加进 `sessions:` 列表；把本次 focus 路径追加进 `focus_paths:` 列表（绝对路径，去重）。两个列表都去重。
  2. **`## 今日总结`** 的内部结构：`### <Bucket>` → `#### Action: <id>` → bullets。追加规则：
     - 找到目标 bucket 段（`### Design` / `### Implement` / `### Learn`）；缺失则按顺序补齐。
     - 在该 bucket 下找 `#### Action: <id>` 子段；缺失则按字母序新建。
     - 在该 Action 段内追加 bullets，按 **`(source_id, bucket, action_id)` 三元组判重**。
       - `source_id` 形如 `"session cu-XXXXXXXX"` / `"session cc-XXXXXXXX"` / `"focus <abs-path>"`。
       - bullet 里抽取 source 的正则：`\(\s*(session|focus)\s+([^)]+)\)`，再做下文归一化。
       - 同一 source 在不��� bucket 内可以各有 bullet（合规），但同一 (source, bucket, action) 不重复加。
     - **Session-id 判重归一化（向后兼容）**：历史日报中的裸 `XXXXXXXX`（无前缀）一律等价于 `cu-XXXXXXXX`（旧数据全部来自 Cursor）；`cc-XXXXXXXX` 只与 `cc-XXXXXXXX` 等价。
     - **focus-path 归一化**：比较前用 `os.path.realpath` + 删尾 `/`；显示形态（`<product-slug>:<rel>` 缩写）和判重形态（绝对路径）解耦——bullet 文本里写缩写，三元组键里用绝对路径。
     - **绝不**修改 / 删除已有 bullets（包括用户手写的不带 source 前缀的 offline bullet）。
  3. **`## 明日计划`**：人工写的主体一律保留。agent 只能在段末追加 `> 建议: ...` 形式的 bullet。
  4. **`## 风险点`**：人工已有 bullet 不动。agent 追加本次抽取的风险条目（去重；同一风险只加一次）。
  5. 更新 `generated_at`。

**风险点抽取规则**（INGEST 时 agent 必须照做）：

- 任意 session `had_errors == true` → 列一条"session XXX 出现错误信号，需排查"
- 任意 session 产出的 Task 是 `[ ]` 未完成 → 列出未完成项及阻塞描述
- 落到 `#### Action: __uncategorized__`（任意 bucket 内）的 Task 累计 ≥ 3 条 → 列一条"未归类 Action 堆积，应建立对应 Action"
- 任意 `status: draft` 的 Product/Milestone/Action 超过 7 天未升级 → 列出来
- `inbox` 类临时 Milestone 持有 ≥ 5 个 Action → 列一条"inbox 应拆分"
- 任意 `focus_digest.kind=git_dir` 且 `uncommitted.unstaged + untracked` 非空，且 `nl_instruction` 含"完成 / 收尾 / 提交 / push" → 列一条"<short-path> 当日有未提交改动"
- 任意 `focus_digest.kind=missing` → 列一条"focus 路径不存在：`<path>`，可能是别名或路径写错"

**Action files**：对每个被命中的 Action，在其 `## Recent Activity` 段末尾追加一行 `- YYYY-MM-DD (session ...) <bullet>` 或 `- YYYY-MM-DD (focus <short-path>) <bullet>`；同时更新 frontmatter 的 `updated` 字段；若是首次命中今天，也更新 `actual_date`（若仍是 null）。判重键 `(date, source_id)`，同一日同一 source 不重复加。

**Draft 新建**：

- 新 Action 用 `templates/action.md`，`status: draft`，`name` 写 agent 提议的中文短语
- 新 Milestone（罕见，但 user_query 里出现新方向时可能要）用 `templates/milestone.md`，`status: draft`
- 新 Product（极罕见，要谨慎）用 `templates/product.md`，`status: draft`
- 所有 draft 新建后在日报顶部插入 `> TODO: 本次自动新建了 N 个草稿条目（list...），请审阅`

### Step 7 — Append log + summarize

向 `work-journal/log.md` 追加：

```markdown
## [YYYY-MM-DD HH:MM] ingest (date=YYYY-MM-DD)
- sessions: N (ids: ...)
- focus paths: M (paths: ...)            # 仅当 M>0
- focus warnings: <list>                 # 仅当 parse_focus_args 或 analyze_focus_path 有 warning
- actions touched: ...
- drafts created: products=..., milestones=..., actions=...
- daily report: daily/YYYY/MM/YYYY-MM-DD.md
```

然后给用户一个简短摘要（不要复述日报全文）：

```
今天涉及 N 个 session、M 个 Action（其中 K 个是新建草稿）。
日报已写入 daily/2026/05/2026-05-26.md。
草稿待审阅：[列出 draft 文件路径]
```

---

## Mode: STATUS

枚举活跃树并打印：

```
work-journal status

active products:
  • UltraData Studio (ultradata-studio)        — updated 2026-05-20
    └─ in-progress milestones:
       • v3 上线 (2026-Q2-v3-release) — planned 2026-04-01 .. 2026-06-30
         └─ open actions:
            • LanceDB V2 Catalog 切换 (in-progress, planned 2026-05-26)
            • Eval 集成 (todo)
            ...
```

`open actions` 包含 `status in {todo, in-progress, blocked, draft}`。

如果 `products/` 为空，输出 Bootstrap 引导而不是空树。

---

## Mode: LINT

扫描整个 journal，输出按严重程度排序的问题列表。每条形如 `[级别] 文件路径 — 问题 — 建议修复`。

检查项：

1. **frontmatter 缺失/错误**：Action 缺 `milestone`/`product`、Milestone 缺 `product`、status 取值非法
2. **悬挂引用**：
   - 日报里 `## Action: <id>` 找不到对应 Action 文件
   - Action 的 `milestone` 找不到对应 Milestone 文件
   - Milestone 的 `product` 找不到对应 Product 文件
3. **状态不一致**：
   - Milestone `status: shipped` 但其下还有 Action `status: in-progress`
   - Product `status: shipped/archived` 但其下还有活跃 Milestone
4. **日期不一致**：
   - 日报文件名 `YYYY-MM-DD.md` 与 frontmatter `date` 不匹配
   - Milestone `actual_end` 早于 `actual_start`
5. **过期警告**：
   - Product / Milestone / Action 超过 30 天没 `updated`
   - Action `planned_date` 已过期但 status 仍是 `todo`
6. **草稿残留**：`status: draft` 的条目超过 7 天未被改成正式 status
7. **孤儿 Action**：被某天日报引用过，但当前未被 STATUS 列出（可能被错误归档）

LINT 模式不修改任何文件，只报告。

---

## Mode: QUERY

1. 读 `index.md` 找到相关 Product
2. 读那个 Product 下的 Milestone / Action 文件
3. 必要时回扫近期 30 天的日报（`daily/YYYY/MM/`）找 Task 级证据
4. 给出带 `[products/.../action.md]` 或 `[daily/YYYY/MM/YYYY-MM-DD.md]` 文件路径引用的回答

---

## Bootstrap

如果 `work-journal/products/` 不存在或为空，**INGEST / STATUS / QUERY / LINT 都先输出引导**：

```
work-journal 还没有 Product。先建一个：

建议（基于已知项目）:
  1. mb-data-pipe → Product "UltraData Studio"
  2. zyx_infra    → Product "SSTable Tools"
  3. my-skills    → Product "Cursor Skills"

我可以现在帮你建空骨架（每个 Product 配一个 status: draft 的 Milestone），
或者你告诉我具体要建哪个 Product。
```

得到用户确认后再创建文件，**不要默默写**。

---

## Implementation reminders for the executing agent

- 所有路径在本文件顶部已声明，**不要硬编码到回复里**——读这里。
- 写 Action 文件之前先 `mkdir -p` 它的父目录。
- frontmatter 序列化用单引号或不加引号皆可，但 `null` 必须用裸 `null`，不要 `"null"`。
- 日期一律 `YYYY-MM-DD`（本地时区）。带时间的字段用 ISO 8601 with offset。
- **谨慎对待用户手写内容**：日报的 `## 明日计划` / `## 风险点`、Action 的 `## 目标 / 验收` 和 `## 进展` 段，agent 只能追加，不能删除/重写已有内容。`## 今日总结` 内 agent 也只追加 bullet（按 session_id 判重）。
- 跑完 INGEST 后**不要再 push commit**，journal 是否要进 git 让用户自己决定。
