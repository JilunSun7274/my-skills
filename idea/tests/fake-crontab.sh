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
