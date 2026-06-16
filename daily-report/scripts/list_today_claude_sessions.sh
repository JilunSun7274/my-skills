#!/usr/bin/env bash
# List Claude Code transcript JSONL files for a given date (local timezone).
# Usage: list_today_claude_sessions.sh [YYYY-MM-DD]
#   - No argument           -> today
#   - YYYY-MM-DD            -> that date
# Output: one absolute JSONL path per line, sorted by mtime ascending.
# Subagent transcripts (under */subagents/*) are excluded.
# Only top-level session files (~/.claude/projects/<cwd-enc>/<sessionId>.jsonl).

set -euo pipefail

TRANSCRIPT_ROOT="${CLAUDE_TRANSCRIPT_ROOT:-$HOME/.claude/projects}"

if [[ ! -d "$TRANSCRIPT_ROOT" ]]; then
  echo "ERROR: transcript root not found: $TRANSCRIPT_ROOT" >&2
  exit 2
fi

TARGET_DATE="${1:-$(date +%Y-%m-%d)}"

if ! [[ "$TARGET_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "ERROR: bad date '$TARGET_DATE', expected YYYY-MM-DD" >&2
  exit 2
fi

if date -j >/dev/null 2>&1; then
  START_TS=$(date -j -f "%Y-%m-%d %H:%M:%S" "$TARGET_DATE 00:00:00" "+%s")
  END_TS=$(date -j -f "%Y-%m-%d %H:%M:%S" "$TARGET_DATE 23:59:59" "+%s")
else
  START_TS=$(date -d "$TARGET_DATE 00:00:00" "+%s")
  END_TS=$(date -d "$TARGET_DATE 23:59:59" "+%s")
fi

# Top-level sessions sit at depth 2 (<cwd-enc>/<sessionId>.jsonl);
# subagents sit at depth 4 (<cwd-enc>/<sessionId>/subagents/agent-*.jsonl).
# -mindepth/-maxdepth 2 structurally excludes subagents; -not -path is belt-and-suspenders.
find "$TRANSCRIPT_ROOT" \
    -mindepth 2 -maxdepth 2 \
    -type f \
    -name '*.jsonl' \
    -not -path '*/subagents/*' \
    -print0 \
  | while IFS= read -r -d '' f; do
      mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f")
      if (( mtime >= START_TS && mtime <= END_TS )); then
        printf '%d\t%s\n' "$mtime" "$f"
      fi
    done \
  | sort -n \
  | cut -f2-
