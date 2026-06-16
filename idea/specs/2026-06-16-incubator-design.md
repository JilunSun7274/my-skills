# 想法温床（Incubator）设计

> 状态：草案 · 日期：2026-06-16
> 范围：将 `idea` skill 从「想法剪贴板」升级为「想法温床」——在记录之外，为想法配置 cron scheduler，让其自动被追踪、调研或开发，逐步成为「一人公司」的孵化器。

## 1 · 背景与目标

现有 `idea` skill 是一个跨会话的想法剪贴板：`~/.claude/ideas.md` 按内容分类（uds-harness / uds-feature / nanobot / chores）存储一行行想法，支持记录 / 查看 / merge / 整理。

本次升级在「记录」之上加一层「孵化」：让选中的想法拥有自己的工作空间、立项计划、以及一个或多个定时执行器（scheduler）。到点由系统 cron 触发真实的 run，由可配置的执行器（claude / nanobot / codex / 未来的其他 agent）推进想法——追踪信息、做调研、写代码。产出以 git 版本化累积，形成一条想法从萌芽到成型的完整演化线。

设计基调：**轻量、静默、可演化、脱离会话独立运行**。

## 2 · 核心概念与生命周期

想法分两种状态：

```
普通想法 ──/idea incubate──▶ 已孵化想法 ──/idea schedule──▶ 自动孵化中
（ideas.md 一行）              （有 id + 工作目录 + 立项书）    （cron 到点跑执行器）
```

- **普通想法**：`ideas.md` 里的一行，零开销。绝大多数想法停留在此。
- **已孵化想法**：被 `incubate` 升格——分配 `<idea-id>`、建工作目录、`git init` 交付物仓库、与用户对话产出立项书 `PLAN.md`。`ideas.md` 对应行尾追加指针标记 `→ [<idea-id>]`。
- **已孵化 ≠ 一定在跑**：可以孵化但暂未挂 scheduler（只有目录和仓库）。挂上 scheduler 才真正自动推进。

状态字段（记于 `idea.md`）：`active`（孵化中）/ `paused`（暂停调度）/ `graduated`（毕业归档）。被 compost 的想法移出主目录，不再用状态字段表示。

## 3 · 数据布局

每条已孵化想法对应一个工作目录：

```
~/incubator/<idea-id>/
  idea.md           # 想法原文、分类、状态、创建时间
  PLAN.md           # 立项书：目标、计划、阶段、待挂的工作类型；执行器每次 run 先读它
  schedulers.json   # 该想法所有 scheduler 配置（见 §5）
  STATUS.md         # 最新进展摘要；/idea 查看时读这个
  runs/<timestamp>/ # 每次 run 的过程账本：stdout/stderr、退出码（短暂、可清理）
  deliverable/      # 成果仓库（git）：执行器的工作目录，版本化累积交付物
    .git/
```

墓园（compost 目标）：

```
~/incubator/.compost/<idea-id>/   # 被 compost 的想法整目录移动至此，可恢复
```

`ideas.md` 仍是人工可读的总入口，已孵化的行多一个 `→ [<idea-id>]` 指针。

**两类产出的区分**：
- `runs/` 是**过程账本**——某次 cron run 跑了什么、输出了什么日志，短暂、可定期清理。
- `deliverable/` 是**成果仓库**——执行器真正产出的交付物（代码、文档、调研报告），用 git 累积。每次 run 在此工作并 commit，`git log` 即想法的演化史。

**一条想法对应一个 deliverable 仓库**：无论挂了追踪 / 调研 / 开发哪几个 scheduler，它们都向同一个仓库贡献提交，git 历史是统一审计线。

## 4 · incubate 流程：搭骨架 + 立规划

`/idea incubate <想法/指代>` 是一段交互流程，而非单纯配置动作：

1. **搭骨架**：分配 `<idea-id>`（kebab-case slug），建工作目录，初始化 `deliverable/` git 仓库，从 `ideas.md` 对应行迁入想法原文到 `idea.md` 并在原行追加 `→ [<idea-id>]` 指针。
2. **立规划**（与用户对话）：Agent 与用户聊清楚——这条想法要做成什么、分哪几步、近期计划、需要追踪/调研/开发中的哪几类工作。产出 `PLAN.md` 作为立项书。
3. **导出调度意向**：规划谈完，自然得出该挂哪些 scheduler 及各自执行器该被指示做什么。`schedulers.json` 不是凭空填写，而是从 `PLAN.md` 流出。是否当场 `schedule` 由用户决定。

`PLAN.md` 是温床的「创始文档」：cron run 中的执行器每次先读它以确定当前推进方向（背景与计划）；某次 run 的具体任务则由该 scheduler 在 `schedulers.json` 中的 `command` 指令给出。想法演化时可经 `/idea` 对话更新 `PLAN.md`。

## 5 · 调度器、执行器与 wrapper

### crontab：稳定的瘦行

crontab 中只写稳定行，真正的命令不入 crontab：

```cron
*/30 * * * * ~/.claude/skills/idea/bin/incubator-run track-price track 2>&1
0 9 * * 1   ~/.claude/skills/idea/bin/incubator-run track-price weekly-research 2>&1
# idea:track-price   ← 标记注释，便于 skill 增删定位该想法的所有行
```

### schedulers.json：真正的配置

```json
{
  "schedulers": [
    {
      "name": "track",
      "cron": "*/30 * * * *",
      "executor": "claude",
      "command": "claude -p \"读 ../PLAN.md 了解背景。本次任务：抓取当前价格并更新 deliverable/prices.md\" --dangerously-skip-permissions",
      "last_run": "2026-06-16T09:00:00",
      "last_status": "ok"
    }
  ],
  "remote": ""
}
```

### wrapper 脚本 `incubator-run <idea-id> <scheduler-name>`

唯一的「胶水」，是 crontab 与可演化执行器之间的解耦层。每次 cron 触发它做：

1. `cd` 到该想法的 `deliverable/`（执行器工作目录）。
2. 从 `schedulers.json` 读出该 scheduler 的 `command`。
3. 执行命令，stdout/stderr + 退出码落到 `runs/<timestamp>/`。
4. 收尾：更新该 scheduler 的 `last_run` / `last_status`；把本次摘要追加进 `STATUS.md`；若 `deliverable/` 有改动则 `git add -A && git commit`；若 `remote` 非空则在 commit 后 `git push`（远端接缝，本期默认空、不接真实远端）。

### 执行器接缝

`command` 是纯字符串模板，可为 `claude -p ...` / `nanobot ...` / `codex ...` 等任意命令——wrapper 不关心内容，只负责执行与记账。更换执行器只改这一行，crontab 与 wrapper 均不变。`PLAN.md` 是共享的立项书（提供背景），每个 scheduler 的本次具体指令内联写在 `command` 里（如上例），不同 scheduler（追踪 / 调研 / 开发）各写各的指令。这一接缝有意保持薄，待执行器接口稳定后再细化。

## 6 · 命令面（`/idea` 子命令）

保留现有：记录（默认）/ 查看 / merge / 分类整理（见 SKILL.md）。新增孵化相关：

| 命令 | 作用 |
|------|------|
| `/idea incubate <想法/指代>` | 搭骨架 + 立规划对话（§4） |
| `/idea schedule <id>` | 为已孵化想法配置 / 修改 scheduler（对话定 cron + 执行器命令），写 `schedulers.json` 并同步 crontab |
| `/idea status [id]` | 看某想法的 `STATUS.md` + 最近 run + git log；不带 id 给全局概览 |
| `/idea pause <id>` / `/idea resume <id>` | 临时摘除 / 恢复该想法的 crontab 行（保留配置与目录，状态置 `paused` / `active`） |
| `/idea graduate <id>` | 想法毕业：停所有 scheduler，归档，标记 `graduated` |
| `/idea compost <id>` | 温和弃置：停所有 scheduler，清 crontab 行，整目录移入 `.compost/`（可恢复）；操作前复述确认 |

普通 `/idea` 查看时，若存在已孵化想法，**末尾汇总「自上次以来哪些想法有新进展」**（依据各 `STATUS.md` 更新时间），落实静默回报。

## 7 · 闭环、回报与失败处理

- **静默回报**：run 只写 `STATUS.md` / `runs/`，不主动打扰；`/idea` 或 `/idea status` 时才汇总新进展。
- **git 审计线**：deliverable 每次有改动即 commit，`git log` 完整记录演化；`/idea status` 可展示最近几条 commit。
- **失败处理**：run 失败（执行器非零退出）时 wrapper 记 `last_status: failed`，错误留在 `runs/`；下次 `/idea status` 标红提示。不自动重试、不自动报警（符合静默基调）。

## 8 · 远端接缝（预留，本期不实现）

`schedulers.json` 顶层 `remote` 字段默认空字符串：
- 空 = 纯本地 git。
- 将来填入 GitHub / codeup 仓库地址后，wrapper 在 commit 后多走一步 `git push`。

本期仅保留字段与 wrapper 中的条件分支位，不接真实远端、不做鉴权配置。

## 9 · 对现有 skill 的改动

- `SKILL.md`：新增「孵化」相关子命令说明（§6），并在「查看」逻辑中加入「已孵化想法新进展汇总」。
- 新增 `bin/incubator-run` wrapper 脚本。
- 新增 `~/incubator/` 目录树（运行时创建，非随 skill 分发）。
- 现有「记录 / 查看 / merge / 分类」行为保持不变。

## 10 · 非目标（YAGNI）

- 不做常驻 daemon、不做 Web UI。
- 不做执行器接口的细化抽象（先留纯命令模板字符串）。
- 不接真实远端推送、不做多机同步。
- 不做自动重试 / 自动报警 / 复杂通知渠道。
- 不做想法间依赖、编排或资源调度。
