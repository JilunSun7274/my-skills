---
name: wiki
description: Maintain personal wiki in KnowledgeGraph. Use when user wants to document insights from a conversation, query the knowledge base, or perform a health check on the wiki.
---

# Wiki Skill

**Wiki root**: `~/mono/KnowledgeGraph/`

## Invocation

| Command | Mode |
|---------|------|
| `/wiki` | **ingest** — analyze current conversation, update wiki |
| `/wiki query <question>` | **query** — search wiki and answer from it |
| `/wiki lint` | **lint** — health check, find gaps and contradictions |

---

## Wiki Directory Structure

```
KnowledgeGraph/
  index.md              ← navigation map; points to overview.md files (NOT leaf pages)
  log.md                ← append-only operation log
  raw/                  ← immutable source documents (never modified by LLM)
    articles/           ← clipped web articles, blog posts
    papers/             ← academic papers, technical reports
    notes/              ← personal raw notes, meeting records
  Knowledge/
    overview.md         ← top-level knowledge map
    Engineering/
      overview.md       ← Engineering domain summary
      AI-ML/
        overview.md     ← AI-ML cluster summary + links to key pages
        ...leaf pages...
      Systems/
        overview.md
      Cloud-Infra/
        overview.md
      Software/
        overview.md
      Hardware/
        overview.md
    Science/
      overview.md
      Mathematics/
        overview.md
      Interdisciplinary/
        overview.md
      ...
    Social/
      overview.md
      ...
    Life/
      overview.md
      ...
  Projects/
    overview.md         ← project status summary
    ...leaf pages...
  Decisions/
    overview.md         ← ADR index + key decisions summary
    ...leaf pages...
```

### Two-tier navigation

- **`index.md`** — high-level map; links only to `overview.md` files, never to leaf pages directly
- **`overview.md`** — per-directory summary; links to key leaf pages within that directory, plus cross-domain connections; contains synthesized observations and open questions

### Knowledge Placement Rule

Ask: "What is this concept's **core concern**?"
- **Engineering** → how to build / compute / deploy systems
- **Science** → how nature, math, or formal systems work
- **Social** → how humans, economies, societies, organizations behave
- **Life** → personal practice (body, career, habits)
- **Decisions/** → a specific choice made in a project (not general knowledge)
- **Projects/** → ongoing work, learning plans, project status

When ambiguous, prefer the narrower sub-domain.

---

## Page Format

Every **leaf page** must have this frontmatter:

```yaml
---
title: <descriptive title>
type: concept | pattern | resource | decision | project
domain: Engineering/AI-ML | Science/Mathematics | Social/Finance | Life/Health | ...
tags: [tag1, tag2]
sources: []             # paths under raw/ or URLs that this page was derived from
created: YYYY-MM-DD
updated: YYYY-MM-DD
sessions: [YYYY-MM-DD]
---
```

Page body structure:
```markdown
# <title>

## Core Idea
<1-3 sentence summary of the essential concept>

## Detail
<main content — mechanism, how it works, tradeoffs>

## Examples / Code
<concrete illustration when applicable>

## Related
- [[PageName]] — one-line relationship description
```

Every **overview.md** must have this frontmatter (title is shown in Obsidian graph view via Frontmatter Title plugin):

```yaml
---
title: <Domain / Subdomain>   # e.g. "Engineering / AI-ML"
---
```

Overview body structure:
```markdown
# Overview: <Domain / Subdomain>

<1-2 sentence description of what this domain covers>

---

## <Cluster Name>

<2-3 sentences synthesizing the knowledge cluster — key insights, open questions>

- [[PageName]] — one-line description
- [[PageName]] — one-line description

---

## 待扩展方向

- topic not yet covered

---

## 关联分区

- [[../Other/overview]] — one-line cross-domain relationship
```

**Overview authoring rules:**
- Link to **key** pages only — not every leaf page. Prefer pages that anchor a cluster.
- Write at least one synthesized observation per cluster (not just a list of links).
- Note open questions and gaps in "待扩展方向".
- Do NOT replicate content from leaf pages; summarize and point.

### Wiki link convention

`[[...]]` links MUST use the **English filename** (without `.md` extension), never the Chinese `title` field:

```markdown
✓  [[Mixed_Precision_Training]]     ← matches filename
✗  [[混合精度训练]]                   ← matches title only, Obsidian cannot resolve
✓  [[LLM_Training_Pipeline]]
✗  [[LLM 训练流程与 TrainingArguments]]
```

Obsidian resolves `[[PageName]]` by filename globally across the vault — cross-directory links work without a path prefix. Only use relative paths (e.g., `[[../../Engineering/AI-ML/overview]]`) inside `overview.md` files that link to other overviews.

For **Decisions/** pages, use ADR format:
```markdown
# Decision: <title>

## Context
<what problem prompted this decision>

## Options Considered
- Option A: ...
- Option B: ...

## Decision
<what was chosen and why>

## Consequences
<tradeoffs accepted>
```

For **Projects/** pages:
```markdown
# Project: <name>

## Goal
<what success looks like>

## Status
<current phase, blockers, next steps>

## Log
- YYYY-MM-DD: <milestone or update>
```

---

## Mode: INGEST

### Step 1 — Read wiki state
```
Read ~/mono/KnowledgeGraph/index.md
Read last 30 lines of ~/mono/KnowledgeGraph/log.md
```

### Step 2 — Extract knowledge from conversation

Scan the full conversation for each category. Be selective: only extract knowledge that is **non-obvious, reusable, or worth recalling later**. Skip ephemeral task details.

| Category | What to extract |
|----------|----------------|
| **Concepts** | Technical/domain concepts explained or discovered |
| **Patterns** | Code patterns, architectural patterns, design solutions |
| **Decisions** | Choices made with explicit reasoning (A vs B → chose A because X) |
| **Resources** | Tools, libraries, papers, links referenced with context |
| **Projects** | New projects started, learning paths defined, milestones reached |

### Step 3 — Determine create vs update

For each extracted item:
- Search `index.md` (and relevant `overview.md`) for a matching existing page
- If match: read the existing page, then **update** it (add new info, correct stale claims, strengthen cross-references)
- If no match: **create** a new leaf page

### Step 4 — Write leaf pages

Use the Write/Edit tools directly. Place files at the correct path under the wiki structure.

When updating existing pages:
- Keep and extend existing content; do not discard prior knowledge
- Add new session date to `sessions:` frontmatter list
- Update `updated:` date
- If the knowledge was derived from a raw source file, add its path (relative to KnowledgeGraph root) or URL to the `sources:` list

**Raw sources convention:**
- Raw source files live in `raw/` and are **never modified** by the LLM
- When a wiki page synthesizes or summarizes a raw source, reference it: `sources: [raw/articles/some-article.md]`
- If the source is a URL (not downloaded), use the URL directly: `sources: [https://example.com/paper]`
- Pages derived purely from conversation have an empty `sources: []`

### Step 5 — Update overview.md(s)

For every leaf page created or updated, open the **most specific** `overview.md` that contains it and update accordingly:

- **New page**: add a link entry under the appropriate cluster. If the page starts a new cluster, create the cluster heading and write a synthesized observation.
- **Updated page**: check whether the cluster's synthesized observation still reflects current knowledge; revise if needed.
- If the new page implies a cross-domain connection not yet in the overview, add it to "关联分区".
- If the new page fills a gap listed in "待扩展方向", remove that item.
- Cascade upward **only if** the change is significant: update the parent `overview.md` (e.g., `Engineering/overview.md`) only when a new sub-domain cluster is created or a major cross-domain theme emerges. Do not update parent overviews for routine leaf page additions.

### Step 6 — Update index.md

`index.md` links only to `overview.md` files. Update it when:
- A new sub-domain directory is created (add a row to the relevant table)
- A domain's core theme changes significantly (update the "核心主题" column)

Do **not** add individual leaf pages to `index.md`.

Current index format:
```markdown
# Knowledge Graph Index

_Last updated: YYYY-MM-DD_

## [Knowledge](Knowledge/overview.md)

| 分区 | Overview | 核心主题 |
|------|----------|----------|
| Engineering / AI-ML | [overview](Knowledge/Engineering/AI-ML/overview.md) | LLM 训练、混合精度、LoRA、PyTorch、Agent |
...

## [Projects](Projects/overview.md)
...

## [Decisions](Decisions/overview.md)
...
```

### Step 7 — Append to log.md

Format: one entry per ingest, with bullet list of pages touched.

```
## [YYYY-MM-DD] ingest | <session context, 1 line>

- Created: Knowledge/Engineering/AI-ML/NewConcept.md
- Updated: Knowledge/Engineering/AI-ML/ExistingPage.md
- Updated: Knowledge/Engineering/AI-ML/overview.md
```

---

## Mode: QUERY

1. Read `index.md` to identify the relevant domain
2. Read the domain's `overview.md` to locate key pages
3. Read the identified leaf pages in full
4. Synthesize an answer with `[[WikiPage]]` citations
5. If the answer is substantial and reusable, offer to save it as a new leaf page

---

## Mode: LINT

Scan the wiki and report:

1. **Missing overview.md** — any directory under `Knowledge/`, `Projects/`, or `Decisions/` that lacks an `overview.md`
2. **Overview missing frontmatter title** — `overview.md` files without a `title:` field (breaks Obsidian graph view display)
3. **Overview link rot** — links in `overview.md` pointing to leaf pages that no longer exist
4. **Leaf page not referenced by any overview** — pages with no inbound link from their directory's `overview.md` (orphan)
5. **Missing leaf frontmatter** — leaf pages without required YAML fields
6. **Broken source references** — `sources:` entries pointing to files that don't exist in `raw/`
7. **Stale overview** — `overview.md` whose cluster list is missing recently-created leaf pages (added since last overview update)
8. **Classification gaps** — concepts mentioned across pages that don't have their own leaf page
9. **Contradictions** — pages that make conflicting claims about the same topic

Output as a prioritized list. For each issue include the file path and a one-line suggested fix.
