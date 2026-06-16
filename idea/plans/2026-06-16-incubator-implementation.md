# 想法温床（Incubator）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `~/.claude/skills/idea` skill 从「想法剪贴板」升级为「想法温床」——为想法配置系统 cron scheduler，由可换的执行器（claude/nanobot/codex）定时推进，产出以 git 版本化累积。

**Architecture:** 一组受测的 bash 脚本（`bin/`）承担所有有副作用、易出错的机械工作——目录脚手架、schedulers.json 的 JSON 读写、crontab 标记块的增删、cron 触发时的执行与记账；SKILL.md 里的 agent 只负责与用户对话（立项、配置）并调用这些脚本。crontab 只存稳定瘦行 `incubator-run <id> <scheduler>`，真正的命令存在 schedulers.json。

**Tech Stack:** bash 3.2（macOS）、jq 1.7、git、系统 crontab。测试用零依赖的纯 bash harness（自带 assert + 沙箱 + 假 crontab）。

设计依据：`/Users/jilunsun/.claude/skills/idea/specs/2026-06-16-incubator-design.md`

---

## 与 spec 的两处精化（实现层决定，不改变设计意图）

1. **crontab / JSON 操作脚本化**：spec §6 说「agent 写 schedulers.json 并同步 crontab」。为可靠与可测，这些操作落进 `bin/incubator`（管理）与 `bin/incubator-run`（执行），SKILL.md 指示 agent 调用而非徒手编辑。
2. **crontab 标记块**：spec §5 用单行注释 `# idea:<id>`。实现改为成对哨兵块，便于程序精确删改：
   ```
   # >>> incubator:<id> >>>
   <cron> /abs/bin/incubator-run <id> <scheduler>
   # <<< incubator:<id> <<<
   ```

## File Structure

```
~/.claude/skills/idea/
  SKILL.md                     # 修改：新增孵化子命令说明 + 查看时「新进展汇总」
  bin/
    incubator-lib.sh           # 新建：共享库（路径解析、jq 读写、crontab 块、状态）
    incubator                  # 新建：管理分发器 new|add-scheduler|rm-scheduler|crontab|set-status|compost
    incubator-run              # 新建：cron 执行器（瘦壳，调用库里的 _incubator_run）
  specs/2026-06-16-incubator-design.md   # 已存在
  tests/
    helpers.sh                 # 新建：assert 助手 + 沙箱 + 假 crontab
    test_incubator.sh          # 新建：全部测试用例
```

运行时目录 `~/incubator/<id>/`（及 `.compost/`）由脚本按需创建，不随 skill 分发。

**库与脚本的职责边界**：
- `incubator-lib.sh`：纯函数，无顶层副作用，被另两个脚本 `source`。所有路径经 `INCUBATOR_HOME`（默认 `~/incubator`）解析——这是测试隔离的关键。所有 crontab 读写经 `_crontab` 包装（可被 `INCUBATOR_CRONTAB_CMD` 覆盖为假 crontab）。
- `incubator`：用户/agent 调用的管理命令。
- `incubator-run`：crontab 里调用的执行入口，保持极简稳定。

---

## Task 1: 测试 harness 与库骨架

建立零依赖测试基础设施和 lib 的路径解析层，后续每个 Task 都依赖它。

**Files:**
- Create: `~/.claude/skills/idea/tests/helpers.sh`
- Create: `~/.claude/skills/idea/bin/incubator-lib.sh`
- Create: `~/.claude/skills/idea/tests/test_incubator.sh`

- [ ] **Step 1: 写测试 harness 助手与沙箱**

Create `~/.claude/skills/idea/tests/helpers.sh`:

```bash
# 零依赖 bash 测试助手。被 test_incubator.sh source。
# 提供：assert 函数、计数、每用例隔离沙箱、假 crontab。

TESTS_RUN=0
TESTS_FAILED=0
CURRENT_TEST=""

# bin 目录绝对路径（helpers.sh 在 tests/ 下，bin 在同级）
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)"

_fail() {
  # 在子shell里立即中止当前测试（非零退出），由父shell的 run_test 计入失败。
  echo "  ✗ $CURRENT_TEST: $1"
  exit 1
}

assert_eq() {
  # assert_eq <expected> <actual> <msg>
  if [ "$1" != "$2" ]; then
    _fail "$3 — expected [$1] got [$2]"
    return 1
  fi
}

assert_file() {
  # assert_file <path> <msg>
  if [ ! -f "$1" ]; then _fail "$2 — file missing: $1"; return 1; fi
}

assert_dir() {
  if [ ! -d "$1" ]; then _fail "$2 — dir missing: $1"; return 1; fi
}

assert_contains() {
  # assert_contains <haystack> <needle> <msg>
  case "$1" in
    *"$2"*) : ;;
    *) _fail "$3 — [$1] does not contain [$2]"; return 1 ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) _fail "$3 — [$1] unexpectedly contains [$2]"; return 1 ;;
    *) : ;;
  esac
}

# 每个测试用例前调用：建立隔离沙箱
setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  export INCUBATOR_HOME="$SANDBOX/incubator"
  mkdir -p "$INCUBATOR_HOME"
  # 假 crontab：用文件模拟 crontab -l / crontab -
  export FAKE_CRON="$SANDBOX/crontab.txt"
  : > "$FAKE_CRON"
  export INCUBATOR_CRONTAB_CMD="$BIN_DIR/../tests/fake-crontab.sh"
  # git 提交所需身份
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
}

teardown_sandbox() {
  [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"
}

run_test() {
  # run_test <test_function_name>
  CURRENT_TEST="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  setup_sandbox
  ( set -e; "$1" )  # 子shell隔离；失败不中断整轮
  local rc=$?
  teardown_sandbox
  # 计数在父shell进行：子shell里对 TESTS_FAILED 的修改不会传回，靠退出码判定。
  if [ $rc -eq 0 ]; then echo "  ✓ $1"; else TESTS_FAILED=$((TESTS_FAILED + 1)); fi
}

finish() {
  echo ""
  echo "Ran $TESTS_RUN tests, $TESTS_FAILED failed."
  [ $TESTS_FAILED -eq 0 ]
}
```

- [ ] **Step 2: 写假 crontab 脚本**

Create `~/.claude/skills/idea/tests/fake-crontab.sh`:

```bash
#!/usr/bin/env bash
# 模拟 crontab 命令，作用于 $FAKE_CRON 文件而非真实 crontab。
# 支持：  fake-crontab.sh -l   → 打印当前内容
#        fake-crontab.sh -    → 从 stdin 读取并替换内容
set -euo pipefail
case "${1:-}" in
  -l) cat "$FAKE_CRON" 2>/dev/null || true ;;
  -)  cat > "$FAKE_CRON" ;;
  *)  echo "fake-crontab: unsupported arg: ${1:-}" >&2; exit 2 ;;
esac
```

Run: `chmod +x ~/.claude/skills/idea/tests/fake-crontab.sh`

- [ ] **Step 3: 写 lib 的路径解析与 crontab 包装骨架**

Create `~/.claude/skills/idea/bin/incubator-lib.sh`:

```bash
# 想法温床共享库。无顶层副作用，供 incubator / incubator-run source。
# 所有路径经 INCUBATOR_HOME 解析（测试可覆盖）。

inc_home() { echo "${INCUBATOR_HOME:-$HOME/incubator}"; }
inc_dir()  { echo "$(inc_home)/$1"; }                 # 工作目录
inc_deliverable() { echo "$(inc_dir "$1")/deliverable"; }
inc_bin() { cd "$(dirname "${BASH_SOURCE[0]}")" && pwd; }  # bin 绝对路径

# crontab 包装：可被 INCUBATOR_CRONTAB_CMD 覆盖（测试注入假 crontab）
_crontab() { "${INCUBATOR_CRONTAB_CMD:-crontab}" "$@"; }

inc_require() {
  # inc_require <id>：校验已孵化想法存在
  local d; d="$(inc_dir "$1")"
  if [ ! -d "$d" ]; then echo "incubator: no such idea: $1" >&2; return 1; fi
}

inc_slug_ok() {
  # 校验 id 为合法 kebab slug，挡住路径穿越
  case "$1" in
    "" | *[!a-z0-9-]* | -* | *- ) return 1 ;;
    *) return 0 ;;
  esac
}
```

- [ ] **Step 4: 写最小测试文件验证骨架可跑**

Create `~/.claude/skills/idea/tests/test_incubator.sh`:

```bash
#!/usr/bin/env bash
# 想法温床测试套件。运行：bash tests/test_incubator.sh
set -uo pipefail
cd "$(dirname "$0")"
source ./helpers.sh
source ../bin/incubator-lib.sh

test_home_resolves_to_sandbox() {
  assert_eq "$INCUBATOR_HOME" "$(inc_home)" "inc_home 应取 INCUBATOR_HOME"
  assert_eq "$INCUBATOR_HOME/foo" "$(inc_dir foo)" "inc_dir 拼接 id"
}

test_slug_validation() {
  inc_slug_ok "track-price" || _fail "合法 slug 被拒"
  if inc_slug_ok "../etc"; then _fail "路径穿越 slug 应被拒"; fi
  if inc_slug_ok "Bad_Slug"; then _fail "大写/下划线应被拒"; fi
}

run_test test_home_resolves_to_sandbox
run_test test_slug_validation
finish
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `bash ~/.claude/skills/idea/tests/test_incubator.sh`
Expected: PASS —
```
  ✓ test_home_resolves_to_sandbox
  ✓ test_slug_validation

Ran 2 tests, 0 failed.
```

- [ ] **Step 6: Commit**

`~/.claude` 非 git 仓库，本计划全程不做 git 提交（无仓库可提交）。改为快照备份以便回滚：

```bash
mkdir -p ~/.claude/skills/idea/.snapshots
cp -R ~/.claude/skills/idea/bin ~/.claude/skills/idea/tests ~/.claude/skills/idea/.snapshots/task1 2>/dev/null || \
  cp -R ~/.claude/skills/idea/bin ~/.claude/skills/idea/tests ~/.claude/skills/idea/.snapshots/
echo "task1 done"
```

---

## Task 2: `incubator new` —— 目录脚手架

实现 spec §4 步骤1（搭骨架）：建目录、初始化 deliverable git 仓库、写骨架文件。立项对话（PLAN.md 内容）由 SKILL.md 的 agent 负责，此脚本只写占位骨架。

**Files:**
- Modify: `~/.claude/skills/idea/bin/incubator-lib.sh`（追加 `inc_new`）
- Create: `~/.claude/skills/idea/bin/incubator`（分发器，先接 new）
- Modify: `~/.claude/skills/idea/tests/test_incubator.sh`

- [ ] **Step 1: 写失败测试**

在 `test_incubator.sh` 的 `run_test` 调用之前追加：

```bash
test_new_scaffolds_structure() {
  "$BIN_DIR/incubator" new track-price nanobot --idea "让 nanobot 跟踪商品价格"
  local d="$INCUBATOR_HOME/track-price"
  assert_dir  "$d"                  "工作目录已建"
  assert_file "$d/idea.md"          "idea.md 已建"
  assert_file "$d/PLAN.md"          "PLAN.md 已建"
  assert_file "$d/schedulers.json"  "schedulers.json 已建"
  assert_file "$d/STATUS.md"        "STATUS.md 已建"
  assert_dir  "$d/deliverable/.git" "deliverable 是 git 仓库"
  # idea.md frontmatter
  local content; content="$(cat "$d/idea.md")"
  assert_contains "$content" "id: track-price"   "frontmatter 含 id"
  assert_contains "$content" "status: active"     "frontmatter 含 status"
  assert_contains "$content" "category: nanobot"  "frontmatter 含 category"
  assert_contains "$content" "让 nanobot 跟踪商品价格" "含想法原文"
  # schedulers.json 是合法 JSON 且结构正确
  local n; n="$(jq '.schedulers | length' "$d/schedulers.json")"
  assert_eq "0" "$n" "初始无 scheduler"
  local remote; remote="$(jq -r '.remote' "$d/schedulers.json")"
  assert_eq "" "$remote" "remote 默认空"
}

test_new_rejects_bad_slug() {
  if "$BIN_DIR/incubator" new "../evil" 2>/dev/null; then
    _fail "非法 slug 应被拒绝"
  fi
}

test_new_rejects_duplicate() {
  "$BIN_DIR/incubator" new dup x --idea "first"
  if "$BIN_DIR/incubator" new dup x --idea "second" 2>/dev/null; then
    _fail "重复 id 应被拒绝"
  fi
}
```

并在底部追加运行：

```bash
run_test test_new_scaffolds_structure
run_test test_new_rejects_bad_slug
run_test test_new_rejects_duplicate
```

- [ ] **Step 2: 运行，确认失败**

Run: `bash ~/.claude/skills/idea/tests/test_incubator.sh`
Expected: FAIL —`incubator` 脚本不存在，相关用例报错。

- [ ] **Step 3: 在 lib 追加 `inc_new`**

在 `incubator-lib.sh` 末尾追加：

```bash
inc_new() {
  # inc_new <id> [category] [idea-text]
  local id="$1" category="${2:-chores}" idea="${3:-}"
  inc_slug_ok "$id" || { echo "incubator: invalid id (须为 kebab-case): $id" >&2; return 1; }
  local d; d="$(inc_dir "$id")"
  if [ -d "$d" ]; then echo "incubator: idea already exists: $id" >&2; return 1; fi
  local today; today="$(date +%Y-%m-%d)"
  mkdir -p "$d/deliverable" "$d/runs"
  # idea.md（frontmatter + 原文）
  cat > "$d/idea.md" <<EOF
---
id: $id
category: $category
status: active
created: $today
---

$idea
EOF
  # PLAN.md 立项书骨架（内容由 agent 在对话后填充）
  cat > "$d/PLAN.md" <<EOF
# $id — 立项书

> 由 /idea incubate 对话生成。执行器每次 run 先读本文件了解背景与计划。

## 目标

（待立项对话填写）

## 计划与阶段

（待填写）

## 工作类型

（追踪 / 调研 / 开发，待填写）
EOF
  # schedulers.json
  echo '{"schedulers":[],"remote":""}' | jq '.' > "$d/schedulers.json"
  # STATUS.md
  cat > "$d/STATUS.md" <<EOF
# $id — 进展

（尚无 run）
EOF
  # 初始化 deliverable git 仓库
  git -C "$d/deliverable" init -q
  git -C "$d/deliverable" config user.name  "${GIT_AUTHOR_NAME:-incubator}"
  git -C "$d/deliverable" config user.email "${GIT_AUTHOR_EMAIL:-incubator@local}"
  printf '# %s deliverable\n' "$id" > "$d/deliverable/README.md"
  git -C "$d/deliverable" add -A
  git -C "$d/deliverable" commit -q -m "chore: init deliverable for $id"
  echo "$d"
}
```

- [ ] **Step 4: 写分发器 `incubator`**

Create `~/.claude/skills/idea/bin/incubator`:

```bash
#!/usr/bin/env bash
# 想法温床管理分发器。子命令：new | add-scheduler | rm-scheduler | crontab | set-status | compost
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/incubator-lib.sh"

cmd="${1:-}"; shift || true

case "$cmd" in
  new)
    # new <id> [category] [--idea "text"]
    id="${1:-}"; category="${2:-chores}"; idea=""
    shift || true; shift || true
    while [ $# -gt 0 ]; do
      case "$1" in
        --idea) idea="${2:-}"; shift 2 ;;
        *) shift ;;
      esac
    done
    inc_new "$id" "$category" "$idea"
    ;;
  *)
    echo "incubator: unknown command: $cmd" >&2
    exit 2
    ;;
esac
```

Run: `chmod +x ~/.claude/skills/idea/bin/incubator`

- [ ] **Step 5: 运行测试，确认通过**

Run: `bash ~/.claude/skills/idea/tests/test_incubator.sh`
Expected: PASS — 全部用例（含 Task1 的 2 个 + 本任务 3 个）通过。

- [ ] **Step 6: 快照**

```bash
cp -R ~/.claude/skills/idea/bin ~/.claude/skills/idea/tests ~/.claude/skills/idea/.snapshots/ && echo task2 done
```

---

## Task 3: `add-scheduler` / `rm-scheduler` —— schedulers.json 编辑

用 jq 安全地增删 scheduler 条目，保证 JSON 始终合法。

**Files:**
- Modify: `~/.claude/skills/idea/bin/incubator-lib.sh`
- Modify: `~/.claude/skills/idea/bin/incubator`
- Modify: `~/.claude/skills/idea/tests/test_incubator.sh`

- [ ] **Step 1: 写失败测试**

追加用例与运行行：

```bash
test_add_scheduler_writes_valid_json() {
  "$BIN_DIR/incubator" new t x --idea "i"
  "$BIN_DIR/incubator" add-scheduler t \
    --name track --cron "*/30 * * * *" --executor claude \
    --command 'claude -p "读 ../PLAN.md。抓价格" --dangerously-skip-permissions'
  local f="$INCUBATOR_HOME/t/schedulers.json"
  jq -e '.' "$f" >/dev/null || _fail "schedulers.json 非法 JSON"
  assert_eq "track" "$(jq -r '.schedulers[0].name' "$f")" "name 写入"
  assert_eq "*/30 * * * *" "$(jq -r '.schedulers[0].cron' "$f")" "cron 写入"
  assert_eq "claude" "$(jq -r '.schedulers[0].executor' "$f")" "executor 写入"
  assert_contains "$(jq -r '.schedulers[0].command' "$f")" "抓价格" "command 写入"
  assert_eq "null" "$(jq -r '.schedulers[0].last_run' "$f")" "last_run 初始 null"
}

test_add_scheduler_rejects_duplicate_name() {
  "$BIN_DIR/incubator" new t x --idea "i"
  "$BIN_DIR/incubator" add-scheduler t --name track --cron "* * * * *" --executor claude --command "echo a"
  if "$BIN_DIR/incubator" add-scheduler t --name track --cron "* * * * *" --executor claude --command "echo b" 2>/dev/null; then
    _fail "同名 scheduler 应被拒"
  fi
}

test_rm_scheduler() {
  "$BIN_DIR/incubator" new t x --idea "i"
  "$BIN_DIR/incubator" add-scheduler t --name a --cron "* * * * *" --executor claude --command "echo a"
  "$BIN_DIR/incubator" add-scheduler t --name b --cron "* * * * *" --executor claude --command "echo b"
  "$BIN_DIR/incubator" rm-scheduler t a
  local f="$INCUBATOR_HOME/t/schedulers.json"
  assert_eq "1" "$(jq '.schedulers | length' "$f")" "删后剩 1 个"
  assert_eq "b" "$(jq -r '.schedulers[0].name' "$f")" "剩下的是 b"
}
```

```bash
run_test test_add_scheduler_writes_valid_json
run_test test_add_scheduler_rejects_duplicate_name
run_test test_rm_scheduler
```

- [ ] **Step 2: 运行，确认失败**

Run: `bash ~/.claude/skills/idea/tests/test_incubator.sh`
Expected: FAIL — `add-scheduler` 未知命令。

- [ ] **Step 3: 在 lib 追加函数**

在 `incubator-lib.sh` 末尾追加：

```bash
inc_schedulers_file() { echo "$(inc_dir "$1")/schedulers.json"; }

inc_add_scheduler() {
  # inc_add_scheduler <id> <name> <cron> <executor> <command>
  local id="$1" name="$2" cron="$3" executor="$4" command="$5"
  inc_require "$id" || return 1
  local f; f="$(inc_schedulers_file "$id")"
  if [ -z "$name" ] || [ -z "$cron" ] || [ -z "$command" ]; then
    echo "incubator: add-scheduler 需要 --name/--cron/--command" >&2; return 1
  fi
  # 拒绝重名
  if [ "$(jq --arg n "$name" '[.schedulers[]|select(.name==$n)]|length' "$f")" != "0" ]; then
    echo "incubator: scheduler 已存在: $name" >&2; return 1
  fi
  local tmp; tmp="$(mktemp)"
  jq --arg n "$name" --arg c "$cron" --arg e "$executor" --arg cmd "$command" \
    '.schedulers += [{name:$n,cron:$c,executor:$e,command:$cmd,last_run:null,last_status:null}]' \
    "$f" > "$tmp" && mv "$tmp" "$f"
}

inc_rm_scheduler() {
  # inc_rm_scheduler <id> <name>
  local id="$1" name="$2"
  inc_require "$id" || return 1
  local f tmp; f="$(inc_schedulers_file "$id")"; tmp="$(mktemp)"
  jq --arg n "$name" '.schedulers |= map(select(.name != $n))' "$f" > "$tmp" && mv "$tmp" "$f"
}
```

- [ ] **Step 4: 在分发器接入子命令**

在 `incubator` 的 `case` 中，`new)` 分支之后、`*)` 之前插入：

```bash
  add-scheduler)
    # add-scheduler <id> --name N --cron C --executor E --command CMD
    id="${1:-}"; shift || true
    name=""; cron=""; executor="claude"; command=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --name) name="${2:-}"; shift 2 ;;
        --cron) cron="${2:-}"; shift 2 ;;
        --executor) executor="${2:-}"; shift 2 ;;
        --command) command="${2:-}"; shift 2 ;;
        *) shift ;;
      esac
    done
    inc_add_scheduler "$id" "$name" "$cron" "$executor" "$command"
    ;;
  rm-scheduler)
    # rm-scheduler <id> <name>
    inc_rm_scheduler "${1:-}" "${2:-}"
    ;;
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `bash ~/.claude/skills/idea/tests/test_incubator.sh`
Expected: PASS — 全部用例通过。

- [ ] **Step 6: 快照**

```bash
cp -R ~/.claude/skills/idea/bin ~/.claude/skills/idea/tests ~/.claude/skills/idea/.snapshots/ && echo task3 done
```

---

## Task 4: crontab 同步与移除（标记块）

把 schedulers.json 投影成 crontab 里的哨兵块；幂等、只动本 id 的块。

**Files:**
- Modify: `~/.claude/skills/idea/bin/incubator-lib.sh`
- Modify: `~/.claude/skills/idea/bin/incubator`
- Modify: `~/.claude/skills/idea/tests/test_incubator.sh`

- [ ] **Step 1: 写失败测试**

```bash
test_crontab_sync_writes_block() {
  "$BIN_DIR/incubator" new t x --idea "i"
  "$BIN_DIR/incubator" add-scheduler t --name track --cron "*/30 * * * *" --executor claude --command "echo hi"
  "$BIN_DIR/incubator" crontab sync t
  local cron; cron="$("$INCUBATOR_CRONTAB_CMD" -l)"
  assert_contains "$cron" "# >>> incubator:t >>>" "含起始哨兵"
  assert_contains "$cron" "# <<< incubator:t <<<" "含结束哨兵"
  assert_contains "$cron" "*/30 * * * *" "含 cron 表达式"
  assert_contains "$cron" "incubator-run t track" "含瘦行调用"
}

test_crontab_sync_is_idempotent() {
  "$BIN_DIR/incubator" new t x --idea "i"
  "$BIN_DIR/incubator" add-scheduler t --name track --cron "* * * * *" --executor claude --command "echo hi"
  "$BIN_DIR/incubator" crontab sync t
  local first; first="$("$INCUBATOR_CRONTAB_CMD" -l)"
  "$BIN_DIR/incubator" crontab sync t
  local second; second="$("$INCUBATOR_CRONTAB_CMD" -l)"
  assert_eq "$first" "$second" "二次 sync 应无变化"
  # 只应有一对哨兵
  local n; n="$(printf '%s\n' "$second" | grep -c '>>> incubator:t >>>')"
  assert_eq "1" "$n" "哨兵块不应重复"
}

test_crontab_remove_only_target_id() {
  "$BIN_DIR/incubator" new a x --idea "i"; "$BIN_DIR/incubator" add-scheduler a --name s --cron "* * * * *" --executor claude --command "echo a"
  "$BIN_DIR/incubator" new b x --idea "i"; "$BIN_DIR/incubator" add-scheduler b --name s --cron "* * * * *" --executor claude --command "echo b"
  "$BIN_DIR/incubator" crontab sync a
  "$BIN_DIR/incubator" crontab sync b
  "$BIN_DIR/incubator" crontab remove a
  local cron; cron="$("$INCUBATOR_CRONTAB_CMD" -l)"
  assert_not_contains "$cron" "incubator:a" "a 的块已移除"
  assert_contains "$cron" "incubator:b" "b 的块保留"
}

test_crontab_sync_preserves_foreign_lines() {
  printf '%s\n' "0 0 * * * /usr/bin/other-job" > "$FAKE_CRON"
  "$BIN_DIR/incubator" new t x --idea "i"
  "$BIN_DIR/incubator" add-scheduler t --name s --cron "* * * * *" --executor claude --command "echo hi"
  "$BIN_DIR/incubator" crontab sync t
  local cron; cron="$("$INCUBATOR_CRONTAB_CMD" -l)"
  assert_contains "$cron" "/usr/bin/other-job" "非温床的 crontab 行应保留"
}
```

```bash
run_test test_crontab_sync_writes_block
run_test test_crontab_sync_is_idempotent
run_test test_crontab_remove_only_target_id
run_test test_crontab_sync_preserves_foreign_lines
```

- [ ] **Step 2: 运行，确认失败**

Run: `bash ~/.claude/skills/idea/tests/test_incubator.sh`
Expected: FAIL — `crontab` 子命令未实现。

- [ ] **Step 3: 在 lib 追加 crontab 块管理**

```bash
inc_marker_begin() { echo "# >>> incubator:$1 >>>"; }
inc_marker_end()   { echo "# <<< incubator:$1 <<<"; }

inc_crontab_strip() {
  # 从 stdin 删除某 id 的哨兵块，输出到 stdout
  local id="$1"
  awk -v b="$(inc_marker_begin "$id")" -v e="$(inc_marker_end "$id")" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    skip!=1 {print}
  '
}

inc_crontab_remove() {
  # 移除某 id 的块（保留其余所有行）
  local id="$1"
  inc_slug_ok "$id" || return 1
  local cur stripped
  cur="$(_crontab -l 2>/dev/null || true)"
  stripped="$(printf '%s\n' "$cur" | inc_crontab_strip "$id")"
  printf '%s\n' "$stripped" | _crontab -
}

inc_crontab_sync() {
  # 用 schedulers.json 重建某 id 的块（先删后加，幂等）
  local id="$1"
  inc_require "$id" || return 1
  local f bin block cur stripped
  f="$(inc_schedulers_file "$id")"
  bin="$(inc_bin)"
  # 构造块内容
  block="$(inc_marker_begin "$id")"$'\n'
  # 每个 scheduler 一行：<cron> <bin>/incubator-run <id> <name>
  while IFS=$'\t' read -r name cron; do
    [ -z "$name" ] && continue
    block="$block$cron $bin/incubator-run $id $name"$'\n'
  done < <(jq -r '.schedulers[] | [.name, .cron] | @tsv' "$f")
  block="$block$(inc_marker_end "$id")"
  # 取现有 crontab，去掉旧块，追加新块
  cur="$(_crontab -l 2>/dev/null || true)"
  stripped="$(printf '%s\n' "$cur" | inc_crontab_strip "$id" | sed '/^$/d')"
  if [ -n "$stripped" ]; then
    printf '%s\n%s\n' "$stripped" "$block" | _crontab -
  else
    printf '%s\n' "$block" | _crontab -
  fi
}
```

注：`bash 3.2` 支持进程替换 `< <(...)`，上面写法可用。

- [ ] **Step 4: 在分发器接入 `crontab` 子命令**

在 `case` 中插入：

```bash
  crontab)
    # crontab sync <id> | crontab remove <id>
    sub="${1:-}"; id="${2:-}"
    case "$sub" in
      sync)   inc_crontab_sync "$id" ;;
      remove) inc_crontab_remove "$id" ;;
      *) echo "incubator crontab: 需要 sync|remove" >&2; exit 2 ;;
    esac
    ;;
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `bash ~/.claude/skills/idea/tests/test_incubator.sh`
Expected: PASS — 全部用例通过。

- [ ] **Step 6: 快照**

```bash
cp -R ~/.claude/skills/idea/bin ~/.claude/skills/idea/tests ~/.claude/skills/idea/.snapshots/ && echo task4 done
```

---

## Task 5: `incubator-run` —— cron 执行器（成功路径）

实现 spec §5：cd 到 deliverable、读命令、执行、记账到 runs/、更新 last_run/last_status、追加 STATUS.md、git commit。

**Files:**
- Modify: `~/.claude/skills/idea/bin/incubator-lib.sh`（`_incubator_run`）
- Create: `~/.claude/skills/idea/bin/incubator-run`
- Modify: `~/.claude/skills/idea/tests/test_incubator.sh`

- [ ] **Step 1: 写失败测试**

```bash
test_run_executes_and_logs() {
  "$BIN_DIR/incubator" new t x --idea "i"
  # 命令在 deliverable 工作目录里产文件
  "$BIN_DIR/incubator" add-scheduler t --name s --cron "* * * * *" --executor sh \
    --command 'echo PRICE=42 > prices.txt'
  "$BIN_DIR/incubator-run" t s
  local d="$INCUBATOR_HOME/t"
  assert_file "$d/deliverable/prices.txt" "命令在 deliverable 里产出文件"
  assert_eq "PRICE=42" "$(cat "$d/deliverable/prices.txt")" "文件内容正确"
  # runs/ 有一条记录
  local rc_files; rc_files="$(ls "$d/runs"/*/exit_code 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "1" "$rc_files" "runs 下有一条 run 记录"
  # last_status 更新为 ok
  assert_eq "ok" "$(jq -r '.schedulers[0].last_status' "$d/schedulers.json")" "last_status=ok"
  assert_eq "false" "$([ "$(jq -r '.schedulers[0].last_run' "$d/schedulers.json")" = "null" ] && echo true || echo false)" "last_run 已更新"
  # STATUS.md 追加了一行
  assert_contains "$(cat "$d/STATUS.md")" "s" "STATUS.md 记录了 scheduler 名"
  # deliverable 产生了一次提交
  local commits; commits="$(git -C "$d/deliverable" rev-list --count HEAD)"
  assert_eq "2" "$commits" "init 之外多一次 run 提交"
}

test_run_unknown_scheduler_fails() {
  "$BIN_DIR/incubator" new t x --idea "i"
  if "$BIN_DIR/incubator-run" t nope 2>/dev/null; then
    _fail "未知 scheduler 应失败退出"
  fi
}
```

```bash
run_test test_run_executes_and_logs
run_test test_run_unknown_scheduler_fails
```

- [ ] **Step 2: 运行，确认失败**

Run: `bash ~/.claude/skills/idea/tests/test_incubator.sh`
Expected: FAIL — `incubator-run` 不存在。

- [ ] **Step 3: 在 lib 实现 `_incubator_run`**

在 `incubator-lib.sh` 末尾追加：

```bash
_incubator_run() {
  # _incubator_run <id> <scheduler>
  local id="$1" name="$2"
  inc_require "$id" || return 1
  local d f command; d="$(inc_dir "$id")"; f="$(inc_schedulers_file "$id")"
  command="$(jq -r --arg n "$name" '.schedulers[]|select(.name==$n)|.command' "$f")"
  if [ -z "$command" ] || [ "$command" = "null" ]; then
    echo "incubator-run: no scheduler [$name] for [$id]" >&2; return 1
  fi
  local ts rundir; ts="$(date +%Y-%m-%dT%H%M%S)"; rundir="$d/runs/$ts"
  mkdir -p "$rundir"
  # 在 deliverable 工作目录执行
  local rc
  ( cd "$d/deliverable" && eval "$command" ) > "$rundir/output.log" 2>&1
  rc=$?
  echo "$rc" > "$rundir/exit_code"
  local status="ok"; [ "$rc" -eq 0 ] || status="failed"
  # 更新 schedulers.json 的 last_run/last_status
  local tmp; tmp="$(mktemp)"
  jq --arg n "$name" --arg t "$ts" --arg s "$status" \
    '(.schedulers[]|select(.name==$n)) |= (.last_run=$t | .last_status=$s)' \
    "$f" > "$tmp" && mv "$tmp" "$f"
  # 追加 STATUS.md
  printf -- '- [%s] %s: %s\n' "$ts" "$name" "$status" >> "$d/STATUS.md"
  # deliverable 有改动则提交
  if [ -n "$(git -C "$d/deliverable" status --porcelain)" ]; then
    git -C "$d/deliverable" add -A
    git -C "$d/deliverable" commit -q -m "incubate: $name run $ts ($status)"
  fi
  # 远端接缝：remote 非空且成功则 push（best-effort，本期默认空）
  local remote; remote="$(jq -r '.remote // ""' "$f")"
  if [ -n "$remote" ] && [ "$status" = "ok" ]; then
    git -C "$d/deliverable" push 2>/dev/null || true
  fi
  return "$rc"
}
```

- [ ] **Step 4: 写 `incubator-run` 瘦壳**

Create `~/.claude/skills/idea/bin/incubator-run`:

```bash
#!/usr/bin/env bash
# cron 触发的执行入口。保持极简稳定：crontab 行只调用它。
# 用法：incubator-run <idea-id> <scheduler-name>
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/incubator-lib.sh"
_incubator_run "${1:-}" "${2:-}"
```

Run: `chmod +x ~/.claude/skills/idea/bin/incubator-run`

- [ ] **Step 5: 运行测试，确认通过**

Run: `bash ~/.claude/skills/idea/tests/test_incubator.sh`
Expected: PASS — 全部用例通过。

- [ ] **Step 6: 快照**

```bash
cp -R ~/.claude/skills/idea/bin ~/.claude/skills/idea/tests ~/.claude/skills/idea/.snapshots/ && echo task5 done
```

---

## Task 6: `incubator-run` 失败路径

执行器非零退出时正确记 `failed`、保留错误日志、wrapper 以非零码退出，且不提交（无产物时）。

**Files:**
- Modify: `~/.claude/skills/idea/tests/test_incubator.sh`

- [ ] **Step 1: 写失败测试**

```bash
test_run_records_failure() {
  "$BIN_DIR/incubator" new t x --idea "i"
  "$BIN_DIR/incubator" add-scheduler t --name s --cron "* * * * *" --executor sh \
    --command 'echo boom >&2; exit 3'
  if "$BIN_DIR/incubator-run" t s; then
    _fail "失败命令应使 wrapper 返回非零"
  fi
  local d="$INCUBATOR_HOME/t"
  assert_eq "failed" "$(jq -r '.schedulers[0].last_status' "$d/schedulers.json")" "last_status=failed"
  assert_eq "3" "$(cat "$d/runs"/*/exit_code)" "退出码记为 3"
  assert_contains "$(cat "$d/runs"/*/output.log)" "boom" "stderr 落入 output.log"
  assert_contains "$(cat "$d/STATUS.md")" "failed" "STATUS.md 标记 failed"
}
```

```bash
run_test test_run_records_failure
```

- [ ] **Step 2: 运行测试，确认通过**

Run: `bash ~/.claude/skills/idea/tests/test_incubator.sh`
Expected: PASS — Task 5 的实现已覆盖失败路径（`rc` 传播、`status=failed`、`return $rc`）。本任务确认其行为正确。

> 若此用例意外失败，检查 `incubator-run` 是否用了 `set -e`（不应——否则 `eval` 失败会提前中断记账）。脚本应为 `set -uo pipefail`，已在 Task 5 Step 4 写明。

- [ ] **Step 3: 快照**

```bash
cp -R ~/.claude/skills/idea/bin ~/.claude/skills/idea/tests ~/.claude/skills/idea/.snapshots/ && echo task6 done
```

---

## Task 7: `set-status` 与 `compost`

状态切换（pause/resume/graduate 的底层）与温和弃置（移入 .compost）。

**Files:**
- Modify: `~/.claude/skills/idea/bin/incubator-lib.sh`
- Modify: `~/.claude/skills/idea/bin/incubator`
- Modify: `~/.claude/skills/idea/tests/test_incubator.sh`

- [ ] **Step 1: 写失败测试**

```bash
test_set_status_updates_idea_md() {
  "$BIN_DIR/incubator" new t x --idea "i"
  "$BIN_DIR/incubator" set-status t paused
  assert_contains "$(cat "$INCUBATOR_HOME/t/idea.md")" "status: paused" "状态改为 paused"
  "$BIN_DIR/incubator" set-status t active
  assert_contains "$(cat "$INCUBATOR_HOME/t/idea.md")" "status: active" "状态改回 active"
  assert_not_contains "$(cat "$INCUBATOR_HOME/t/idea.md")" "status: paused" "旧状态行不残留"
}

test_compost_moves_dir_and_strips_crontab() {
  "$BIN_DIR/incubator" new t x --idea "i"
  "$BIN_DIR/incubator" add-scheduler t --name s --cron "* * * * *" --executor sh --command "echo hi"
  "$BIN_DIR/incubator" crontab sync t
  "$BIN_DIR/incubator" compost t
  # 工作目录移走
  assert_dir "$INCUBATOR_HOME/.compost/t" "已移入 .compost"
  if [ -d "$INCUBATOR_HOME/t" ]; then _fail "原目录应已不在"; fi
  # crontab 块清除
  assert_not_contains "$("$INCUBATOR_CRONTAB_CMD" -l)" "incubator:t" "crontab 块已清"
}
```

```bash
run_test test_set_status_updates_idea_md
run_test test_compost_moves_dir_and_strips_crontab
```

- [ ] **Step 2: 运行，确认失败**

Run: `bash ~/.claude/skills/idea/tests/test_incubator.sh`
Expected: FAIL — `set-status` / `compost` 未实现。

- [ ] **Step 3: 在 lib 追加函数**

```bash
inc_set_status() {
  # inc_set_status <id> <state>
  local id="$1" state="$2"
  inc_require "$id" || return 1
  local f tmp; f="$(inc_dir "$id")/idea.md"; tmp="$(mktemp)"
  # 仅替换 frontmatter 里的 status 行（首个匹配）
  awk -v s="status: $state" '
    !done && /^status: / { print s; done=1; next }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

inc_compost() {
  # inc_compost <id>：停调度 + 移入墓园（可恢复）
  local id="$1"
  inc_require "$id" || return 1
  inc_crontab_remove "$id"
  local home graveyard; home="$(inc_home)"; graveyard="$home/.compost"
  mkdir -p "$graveyard"
  # 若墓园已有同名，加时间戳避免覆盖
  local dest="$graveyard/$id"
  if [ -e "$dest" ]; then dest="$dest.$(date +%Y%m%d%H%M%S)"; fi
  mv "$(inc_dir "$id")" "$dest"
}
```

- [ ] **Step 4: 在分发器接入**

在 `case` 中插入：

```bash
  set-status)
    inc_set_status "${1:-}" "${2:-}"
    ;;
  compost)
    inc_compost "${1:-}"
    ;;
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `bash ~/.claude/skills/idea/tests/test_incubator.sh`
Expected: PASS — 全部用例通过。

- [ ] **Step 6: 快照**

```bash
cp -R ~/.claude/skills/idea/bin ~/.claude/skills/idea/tests ~/.claude/skills/idea/.snapshots/ && echo task7 done
```

---

## Task 8: 更新 SKILL.md —— 孵化子命令与查看汇总

把脚本能力暴露成 agent 可理解的 `/idea` 子命令指令；这是 agent 读的自然语言文档，无单元测试，靠人工冒烟验证。

**Files:**
- Modify: `~/.claude/skills/idea/SKILL.md`

- [ ] **Step 1: 在 SKILL.md「查看」小节后插入「孵化」大节**

在 `### 合并（/idea merge）` 小节之前插入以下内容：

````markdown
### 孵化（Incubator）

把一条想法从「剪贴板条目」升级为有工作空间、立项书、定时执行器的「在孵项目」。底层机械操作由 `bin/` 下的脚本完成（agent 调用，不要徒手编辑 crontab 或 schedulers.json）：

- `bin/incubator new <id> [category] --idea "<原文>"` — 搭骨架
- `bin/incubator add-scheduler <id> --name N --cron "C" --executor E --command "CMD"` — 加调度器
- `bin/incubator rm-scheduler <id> <name>` — 删调度器
- `bin/incubator crontab sync <id>` — 把 schedulers.json 同步进系统 crontab
- `bin/incubator crontab remove <id>` — 移除该想法的 crontab 块
- `bin/incubator set-status <id> <active|paused|graduated>` — 改状态
- `bin/incubator compost <id>` — 移入 `.compost/`（可恢复）
- `bin/incubator-run <id> <scheduler>` — cron 触发的执行入口（一般不手动调）

#### `/idea incubate <想法/指代>`
1. 选定要孵化的想法（从 `ideas.md` 指代或新写）。生成 kebab-case `<id>`。
2. 调 `incubator new <id> <分类> --idea "<原文>"` 搭骨架。
3. **立项对话**：和用户聊清目标、计划、阶段、需要哪几类工作（追踪/调研/开发），把结论写进 `~/incubator/<id>/PLAN.md`（覆盖骨架占位）。
4. 在 `ideas.md` 对应行尾追加指针 `→ [<id>]`（用 Edit）。
5. 询问是否现在配置 scheduler（走 `/idea schedule`）。

#### `/idea schedule <id>`
1. 和用户确定：调度频率（cron 表达式）、执行器（claude/nanobot/codex）、本次该让执行器做什么（写成 command；可在命令里让执行器先读 `../PLAN.md`）。
2. 调 `incubator add-scheduler <id> --name <名> --cron "<expr>" --executor <e> --command "<cmd>"`。
3. 调 `incubator crontab sync <id>` 写入系统 crontab。
4. 复述已配置的调度并确认。

#### `/idea status [id]`
- 带 id：读 `~/incubator/<id>/STATUS.md`、`runs/` 最新一条、`git -C deliverable log --oneline -5`；`last_status: failed` 的标红提示。
- 不带 id：扫描 `~/incubator/*/`，给每条在孵想法一行概览（状态 + 最近 run 时间 + 最近进展）。

#### `/idea pause <id>` / `/idea resume <id>`
- pause：`incubator crontab remove <id>` + `incubator set-status <id> paused`。
- resume：`incubator crontab sync <id>` + `incubator set-status <id> active`。

#### `/idea graduate <id>`
- `incubator crontab remove <id>` + `incubator set-status <id> graduated`。保留目录与 deliverable 仓库，告知用户成果位置。

#### `/idea compost <id>`
- 先复述将弃置的想法，确认后调 `incubator compost <id>`（停调度 + 移入 `.compost/`，可恢复）。
````

- [ ] **Step 2: 在「查看」小节加入「新进展汇总」**

把现有 `### 查看` 小节的列表末尾追加一条：

```markdown
- 展示完普通想法后，若 `~/incubator/` 下有在孵想法，末尾追加「🌱 在孵进展」一节：对每条读 `STATUS.md` 的最新一行，汇总「自上次以来哪些想法有新 run / 新进展」。无在孵想法则不显示该节。
```

- [ ] **Step 3: 人工冒烟测试（端到端，真实脚本、隔离目录）**

用临时 INCUBATOR_HOME 与假 crontab 跑通完整生命周期，不碰真实环境：

```bash
cd ~/.claude/skills/idea
export INCUBATOR_HOME="$(mktemp -d)/inc"
export INCUBATOR_CRONTAB_CMD="$PWD/tests/fake-crontab.sh"
export FAKE_CRON="$(mktemp)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
bin/incubator new demo nanobot --idea "跟踪商品价格"
bin/incubator add-scheduler demo --name track --cron "*/30 * * * *" --executor sh --command 'date > snapshot.txt'
bin/incubator crontab sync demo
bin/incubator-run demo track
echo "--- crontab ---"; "$INCUBATOR_CRONTAB_CMD" -l
echo "--- status ---";  cat "$INCUBATOR_HOME/demo/STATUS.md"
echo "--- git log ---"; git -C "$INCUBATOR_HOME/demo/deliverable" log --oneline
bin/incubator compost demo
echo "--- after compost, crontab ---"; "$INCUBATOR_CRONTAB_CMD" -l
ls "$INCUBATOR_HOME/.compost"
```

Expected: crontab 含 demo 块 → run 后 STATUS.md 有 track 记录、git log 有 2 条提交、deliverable/snapshot.txt 存在 → compost 后 crontab 无 demo 块、`.compost/demo` 存在。

- [ ] **Step 4: 快照**

```bash
cp -R ~/.claude/skills/idea/bin ~/.claude/skills/idea/tests ~/.claude/skills/idea/SKILL.md ~/.claude/skills/idea/.snapshots/ && echo task8 done
```

---

## Task 9: 全套回归与收尾

**Files:**
- Modify: `~/.claude/skills/idea/tests/test_incubator.sh`（确保所有 `run_test` 已登记）

- [ ] **Step 1: 跑全套测试**

Run: `bash ~/.claude/skills/idea/tests/test_incubator.sh`
Expected: PASS —
```
Ran 16 tests, 0 failed.
```
（Task1:2 + Task2:3 + Task3:3 + Task4:4 + Task5:2 + Task6:1 + Task7:2 = 17；以实际登记数为准，关键是 0 failed。）

- [ ] **Step 2: 确认真实 crontab 未被污染**

Run: `crontab -l 2>/dev/null | grep -c incubator || echo 0`
Expected: `0` —— 全程测试用假 crontab，真实 crontab 不应出现 incubator 块。

- [ ] **Step 3: 清理快照目录（可选）**

```bash
rm -rf ~/.claude/skills/idea/.snapshots && echo cleaned
```

- [ ] **Step 4: 最终人工确认**

- `SKILL.md` 的 frontmatter description 已涵盖孵化能力（若未，补一句）。
- `bin/` 下三个文件均 `chmod +x`：`ls -l ~/.claude/skills/idea/bin/`。

---

## Self-Review

**Spec 覆盖核对：**
- §2 生命周期（普通/已孵化/三状态）→ Task 2（new）、Task 7（set-status）、Task 8（incubate/pause/resume/graduate 指令）✓
- §3 数据布局（idea.md/PLAN.md/schedulers.json/STATUS.md/runs/deliverable/.compost）→ Task 2、Task 5、Task 7 ✓
- §4 incubate=搭骨架+立规划 → Task 2（骨架）+ Task 8（立项对话指令）✓
- §5 调度器/执行器/wrapper（crontab 瘦行、schedulers.json、incubator-run 四步收尾、执行器接缝）→ Task 3、4、5 ✓
- §6 命令面（incubate/schedule/status/pause/resume/graduate/compost）→ Task 8 ✓；compost 改为移墓园 → Task 7 ✓
- §7 静默回报/git 审计/失败处理 → Task 5（commit）、Task 6（failed）、Task 8（查看汇总、status 标红）✓
- §8 远端接缝（remote 字段默认空 + push 分支位）→ Task 2（字段）、Task 5（push 分支）✓
- §9 对现有 skill 的改动 → Task 8 ✓；现有 记录/查看/merge/分类 行为不变（未触碰相关代码）✓
- §10 非目标 → 计划未引入 daemon/WebUI/真实远端/重试，符合 ✓

**占位符扫描：** 无 TBD/TODO；每个代码步骤含完整代码与可跑命令。`PLAN.md` 骨架里的「（待填写）」是**运行时产物的占位**（由 agent 立项对话填充），非计划占位，符合设计。

**类型/命名一致性：** 库函数 `inc_new`/`inc_add_scheduler`/`inc_rm_scheduler`/`inc_crontab_sync`/`inc_crontab_remove`/`inc_set_status`/`inc_compost`/`_incubator_run` 在分发器与测试中引用一致；crontab 哨兵 `# >>> incubator:<id> >>>` / `# <<< incubator:<id> <<<` 在 sync/strip/remove 与测试断言中一致；schedulers.json 字段 `name/cron/executor/command/last_run/last_status` 与顶层 `remote` 在 new/add/run/测试中一致。
