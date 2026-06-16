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

run_test test_home_resolves_to_sandbox
run_test test_slug_validation
run_test test_new_scaffolds_structure
run_test test_new_rejects_bad_slug
run_test test_new_rejects_duplicate
run_test test_add_scheduler_writes_valid_json
run_test test_add_scheduler_rejects_duplicate_name
run_test test_rm_scheduler
run_test test_crontab_sync_writes_block
run_test test_crontab_sync_is_idempotent
run_test test_crontab_remove_only_target_id
run_test test_crontab_sync_preserves_foreign_lines
run_test test_run_executes_and_logs
run_test test_run_unknown_scheduler_fails
run_test test_run_records_failure
run_test test_set_status_updates_idea_md
run_test test_compost_moves_dir_and_strips_crontab
finish
