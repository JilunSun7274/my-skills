---
name: idea
description: 想法剪贴板。快速记录、查看和管理用户的小想法，并可把想法孵化（incubate）为有定时执行器的在孵项目。当用户想记下一个想法、查看之前的想法、整理/编辑/删除想法、合并从其他环境同步来的 ideas-*.md 文件，或孵化/调度/查看在孵想法时使用。
---

# 想法剪贴板

所有想法统一存储在 `~/.claude/ideas.md`，跨会话共享。

## 存储格式

```markdown
# Ideas

## uds-harness
- [2026-06-15] 想法内容写在这里 #标签(可选)
- [2026-06-12] 另一个想法

## nanobot
- [2026-06-12] 又一个想法

## chores
- [2026-06-15] 杂项 / 研究 / 工具类想法
```

想法按**内容分类**分组，每个分类用 `## 分类名` 作小标题。每条想法一行，以 `- [YYYY-MM-DD]` 开头（记录日期），归在所属分类下；同一分类内按日期倒序（最新在上）。

当前分类（会随内容演化，可新增）：
- **uds-harness** — UDS agent harness 相关
- **uds-feature** — UDS 平台功能
- **nanobot** — nanobot 相关
- **chores** — 杂项、研究、工具类，不属于其他分类的归这里

## 操作方式

根据用户参数或对话内容判断意图：

### 记录（默认）
`/idea 给博客加个深色模式` → 判断想法属于哪个分类，加到该分类下的**最前面**（类内最新在上），日期用今天。
- 如果文件不存在，先创建（带 `# Ideas` 标题）。
- 归类不明显或不属于任何现有分类时，归入 `chores`；若明显该单开一类，可提议新增分类。
- 记录后简短确认一句即可（顺带说明归入了哪一类），不要长篇总结。
- 如果想法内容和已有条目高度重复，提醒用户并问是否仍要记录。

### 查看
`/idea` 不带参数，或用户说"看看我的想法" → 读取文件，**按分类分组展示**（保持文件的分类结构，类内按日期倒序）。
- 条目较多时，可先给各分类的条数概览，再展开；或只展开用户关心的分类。
- 用户可以要求只看某一类、或按关键词/标签筛选。
- 展示完普通想法后，若 `~/incubator/` 下有在孵想法，末尾追加「🌱 在孵进展」一节：对每条读 `STATUS.md` 的最新一行，汇总「自上次以来哪些想法有新 run / 新进展」。**有 MAILBOX.md（待审）的想法用 ⏸ 标注并置顶**，提示运行 `/idea review`。无在孵想法则不显示该节。

### 孵化（Incubator）

把一条想法从「剪贴板条目」升级为有工作空间、立项书、定时执行器的「在孵项目」。底层机械操作由 `bin/` 下的脚本完成（agent 调用，不要徒手编辑 crontab 或 schedulers.json）：

#### 自我演化机制（三文件分工）

在孵项目能**自己改变下一次要做什么**，同时由两道闸门保证 human-in-the-loop、不跑偏：

| 文件 | 角色 | 谁可写 |
|------|------|--------|
| `<id>/PLAN.md` 的「## 目标」段 | **不可变契约（北极星）** | 仅人类经 `/idea` 对话；执行器只读 |
| `<id>/deliverable/NEXT.md` | **可变的下一步意图**，执行器每次 run 末尾续写 | 执行器（随 deliverable git 版本化） |
| `<id>/MAILBOX.md` | **审批信箱**：存在 ⟺ 待审 ⟺ cron 软暂停 | 执行器投递 / 人类清空 |

闭环：cron 触发 → wrapper 先查 MAILBOX，**存在则记 `blocked` 跳过执行**（软暂停，crontab 不动）→ 否则执行 command（引导语让执行器：读 PLAN+NEXT+NOTES+git log → 优先处理人类建议 → 干活 → 续写 NEXT.md → 自评是否偏离 PLAN 目标 / 触敏感操作，越界则写 MAILBOX.md 停手）→ wrapper 记账提交。人类 `/idea review <id>` 审，approve（清空信箱，下次自动恢复）或纠偏（改 NEXT/PLAN）。

#### 人类反馈通道（NOTES + FEEDBACK，人→执行器）

MAILBOX 是执行器→人（越界喊停、阻塞）；对称地，人也能**随时主动**给在跑的项目留建议——不必等执行器投递，也不必改 PLAN/NEXT：

| 文件 | 角色 | 谁可写 |
|------|------|--------|
| `<id>/NOTES.md` | **人类建议信箱**：人随时写，执行器每次 run 必读、作为**本轮最高优先强指令**处理 | 人类（`/idea note`）/ 执行器读后清空 |
| `<id>/deliverable/FEEDBACK.md` | **执行器回应日志**：逐条回应建议「已采纳→怎么做 / 未采纳→为何」，随 deliverable git 版本化 | 执行器 |

- **优先级**：PLAN 目标（不可变）＞ NOTES（人类即时强指令）＞ NEXT（执行器自主）。建议是强指令——执行器须执行，或在 FEEDBACK 写明充分理由才能不执行；但**不能借此改 PLAN 北极星**。
- **不阻塞**：NOTES 非空不停调度（区别于 MAILBOX 非空即停），执行器下次照常 run、只是必读必回应。
- **生命周期**：写 → 下次 run 必读必处理 → FEEDBACK 回应 → 执行器清空 NOTES（处理完即回收，不重复读老建议）。`git log FEEDBACK.md` 即「我提过什么建议、执行器怎么回应」的完整审计线。

- `bin/incubator new <id> [category] --idea "<原文>"` — 搭骨架
- `bin/incubator add-scheduler <id> --name N --cron "C" --executor E --command "CMD"` — 加调度器
- `bin/incubator rm-scheduler <id> <name>` — 删调度器
- `bin/incubator crontab sync <id>` — 把 schedulers.json 同步进系统 crontab
- `bin/incubator crontab remove <id>` — 移除该想法的 crontab 块
- `bin/incubator set-status <id> <active|paused|graduated>` — 改状态
- `bin/incubator clear-mailbox <id>` — 清空审批信箱（review approve 后，下次 run 自动恢复）
- `bin/incubator note <id> "<建议>"` — 给在跑项目留一条人类建议（不阻塞，下次 run 必读必处理）
- `bin/incubator clear-notes <id>` — 清空人类建议信箱（手动撤回）
- `bin/incubator compost <id>` — 移入 `.compost/`（可恢复）
- `bin/incubator-run <id> <scheduler>` — cron 触发的执行入口（一般不手动调）

#### `/idea incubate <想法/指代>`
1. 选定要孵化的想法（从 `ideas.md` 指代或新写）。生成 kebab-case `<id>`。
2. 调 `incubator new <id> <分类> --idea "<原文>"` 搭骨架。
3. **立项对话**：和用户聊清目标、计划、阶段、需要哪几类工作（追踪/调研/开发），把结论写进 `~/incubator/<id>/PLAN.md`（覆盖骨架占位）。
4. 在 `ideas.md` 对应行尾追加指针 `→ [<id>]`（用 Edit）。
5. 询问是否现在配置 scheduler（走 `/idea schedule`）。

#### `/idea schedule <id>`
1. 和用户确定：调度频率（cron 表达式）、执行器（claude/nanobot/codex）。
2. **command 用固定引导语**（不再写一次性任务串），让执行器自驱演化。推荐模板：
   ```
   claude -p "读 ../PLAN.md（不可变目标）、NEXT.md（上次留下的下一步）、../NOTES.md（人类建议，若有）、git log 了解进展。
   若 ../NOTES.md 非空：把它当本轮最高优先的强指令，先于 NEXT 处理；每条在 FEEDBACK.md 回应（已采纳→怎么做 / 未采纳→为何），处理完用 Write 清空 ../NOTES.md。
   执行 NEXT.md 指示的工作并提交 deliverable。然后续写 NEXT.md 交代下一次该做什么。
   自评：新意图是否仍服务于 ../PLAN.md 的目标？是否触及敏感操作（花钱/外部发布/不可逆）？
   若越界或拿不准，把审批请求写入 ../MAILBOX.md 后停手等人类 review。" --dangerously-skip-permissions
   ```
   （执行器工作目录是 `deliverable/`，故 NEXT.md/FEEDBACK.md 直接读写、PLAN/NOTES/MAILBOX 用 `../`。换 nanobot/codex 时改命令前缀，引导语含义不变。）
3. 调 `incubator add-scheduler <id> --name <名> --cron "<expr>" --executor <e> --command "<上面的引导语>"`。
4. 调 `incubator crontab sync <id>` 写入系统 crontab。
5. 复述已配置的调度并确认。

#### `/idea note <id> <建议>`
人类**随时**给在跑项目留建议（不必等执行器投递、不阻塞调度）。
1. 把建议措辞理清后调 `incubator note <id> "<建议>"` 追加进 `NOTES.md`。
2. 复述已留的建议，并告知「不停调度，下次 run 时执行器会必读必处理，并在 `deliverable/FEEDBACK.md` 回应」。
- 撤回未处理的建议：`incubator clear-notes <id>`。
- 想看执行器历次如何回应：读 `deliverable/FEEDBACK.md` 或 `git log FEEDBACK.md`。

#### `/idea review [id]`
人类审阅执行器投递的审批请求（MAILBOX 非空 = 已软暂停，cron 不再实际推进）。
- **不带 id**：扫描 `~/incubator/*/MAILBOX.md`，列出所有待审想法（有信箱的）。无则告知「无待审」。
- **带 id**：展示 `MAILBOX.md` 全文 + 最近 `deliverable/NEXT.md` 的 git diff + 对照 `PLAN.md` 目标段。与用户决策：
  - **approve（同意新方向）**：`incubator clear-mailbox <id>` 删信箱，下次 cron 自动恢复执行；若执行器把新意图也写进了 NEXT.md，无需再动。
  - **redirect（纠偏）**：用 Edit 改 `deliverable/NEXT.md`（调整下一步）或 `PLAN.md` 目标段（确需改目标时），再 `clear-mailbox <id>` 恢复。
  - **留建议**：方向没错只想微调时，`incubator note <id> "<建议>"` 留话即可（不必停调度），再 `clear-mailbox <id>` 恢复。
  - **拒绝并暂停**：保留信箱不清（保持软暂停），或走 `/idea pause <id>` 硬暂停。

#### `/idea status [id]`
- 带 id：读 `~/incubator/<id>/STATUS.md`、`runs/` 最新一条、`git -C deliverable log --oneline -5`；`last_status: failed` 的标红提示。`last_status: blocked`（或 `MAILBOX.md` 存在）则醒目提示「⏸ 待审，运行 `/idea review <id>`」。若 `NOTES.md` 非空，提示「📝 有待处理建议（下次 run 生效）」。
- 不带 id：扫描 `~/incubator/*/`，给每条在孵想法一行概览（状态 + 最近 run 时间 + 最近进展）；待审（有 MAILBOX）的标 ⏸ 并置顶。

#### `/idea pause <id>` / `/idea resume <id>`
- pause：`incubator crontab remove <id>` + `incubator set-status <id> paused`。
- resume：`incubator crontab sync <id>` + `incubator set-status <id> active`。

#### `/idea graduate <id>`
- `incubator crontab remove <id>` + `incubator set-status <id> graduated`。保留目录与 deliverable 仓库，告知用户成果位置。

#### `/idea compost <id>`
- 先复述将弃置的想法，确认后调 `incubator compost <id>`（停调度 + 移入 `.compost/`，可恢复）。

### 合并（`/idea merge`）
将从其他 remote 环境同步过来的 `~/.claude/ideas-*.md` 文件合并进主文件 `ideas.md`。

`/idea merge` → 执行合并流程：
1. 用 glob 找出所有 `~/.claude/ideas-*.md`（注意只匹配 `ideas-*.md`，不含主文件 `ideas.md`）。没找到就告知用户无可合并文件，结束。
2. 读取主文件和每个待合并文件，逐条抽取想法。**只抽取以 `- [YYYY-MM-DD]` 开头的想法行**；分组标题（如 `## P0 · 硬需求`）、`# Ideas` 标题等结构性内容不当作想法，但其中的优先级/分类信息可作为判断依据，必要时折叠成 `#标签` 或保留在想法措辞里（不要擅自改写原始措辞，只在合并时附加）。
3. **去重**：与主文件已有条目内容相同或高度相似的，不重复加入（日期不同但内容一致时，保留主文件已有的那条即可）。
4. 把去重后新增的想法**按内容归入对应分类**（`## 分类名` 下，类内按日期倒序）；不属于任何现有分类的归 `chores` 或与用户确认是否新增分类。源文件自带的分组（如 P0/P1/P2）不直接搬用，只作归类参考。
5. 合并前先汇报方案：列出「将新增 N 条」「跳过 M 条重复」，重复的简要列出对应关系，确认后再写入。
6. 写入完成后，询问用户是否删除已合并的 `ideas-*.md` 源文件（避免下次重复合并）。默认不删，等用户确认；用户明确要删才删。

`/idea merge <文件名>` → 只合并指定的某个文件，其余流程相同。

### 管理（编辑/删除/整理）
用户通过对话描述，例如：
- "把第 3 条删掉" / "删掉关于深色模式的那条"
- "把那两条关于博客的合并成一条"
- "给想法加上分类整理一下"

执行时：
- 用 Edit 工具精确修改对应行，不要重写整个文件（除非是大规模整理）。
- 删除或合并前，先复述将被改动的条目，确认后再操作；用户指代明确且只涉及一条时可以直接执行。
- 大规模整理（如按主题分组）前先展示整理方案。

## 注意

- 这是用户的个人数据，不要擅自改写想法的措辞。
- 保持文件格式一致，方便人工直接阅读和编辑。
