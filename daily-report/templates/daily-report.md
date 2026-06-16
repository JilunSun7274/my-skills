---
date: <YYYY-MM-DD>
sessions: []
focus_paths: []
status: draft
generated_at: <ISO-8601 with offset>
---

# <YYYY-MM-DD> 日报

<!-- 仅当本次 INGEST 新建了 draft 条目时，agent 在此插入：
> TODO: 本次自动新建了 N 个草稿条目（list...），请审阅
-->

## 今日总结
<!-- agent-managed: 按 bucket 分组（Design / Implement / Learn），bucket 内按 #### Action: <id> 分组；agent 只追加 bullet，不修改/删除已有 bullet -->

### Design
<!-- 文档编撰、设计、需求梳理由 session 自动归类；
     线下讨论 / 对齐由用户手写补充：直接在对应 #### Action: 下加一条不带 (session ...) 前缀的 bullet（推荐用 (offline) 标注），agent 不会改写。
     bullet 可能形如 `- [x] (session cu-XXX)` / `- [x] (session cc-XXX)` / `- (focus <path>)` —— 三种 source 共存；focus 默认无 checkbox。
     <prefixed-id>：Cursor 是 cu-XXXXXXXX，Claude Code 是 cc-XXXXXXXX。 -->

#### Action: <action-id>  <!-- <product-id> / <milestone-id> -->
- [x] (session <prefixed-id>) <一句话总结>

### Implement
<!-- 实际完成的代码 commit 工作 -->

#### Action: <action-id>
- [x] (session <prefixed-id>) <一句话总结>

### Learn
<!-- 对知识、概念的学习 -->

#### Action: <action-id>
- [x] (session <prefixed-id>) <一句话总结>

#### Action: __uncategorized__
<!-- 路径与关键词都判定不出 Action 时的 fallback 区，可出现在任意 bucket 下 -->

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
