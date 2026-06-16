# 零依赖 bash 测试助手。被 test_incubator.sh source。
# 提供：assert 函数、计数、每用例隔离沙箱、假 crontab。

TESTS_RUN=0
TESTS_FAILED=0
CURRENT_TEST=""

# bin 目录绝对路径（helpers.sh 在 tests/ 下，bin 在同级）
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)"

_fail() {
  # 在子shell里立即中止当前测试（非零退出），由父shell的 run_test 计入失败。
  # 直接 exit 而非仅 return，确保断言失败与负向守卫（if ...; then _fail; fi）统一中止。
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
  # 计数在父shell进行：子shell里对 TESTS_FAILED 的修改不会传回，必须靠退出码判定。
  if [ $rc -eq 0 ]; then
    echo "  ✓ $1"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

finish() {
  echo ""
  echo "Ran $TESTS_RUN tests, $TESTS_FAILED failed."
  [ $TESTS_FAILED -eq 0 ]
}
