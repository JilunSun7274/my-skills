# 想法温床共享库。无顶层副作用，供 incubator / incubator-run source。
# 所有路径经 INCUBATOR_HOME 解析（测试可覆盖）。
# 默认 ~/incubator（不放 ~/.claude 下：后者是 harness 受保护路径，执行器无法自动写产出）。

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
