#!/usr/bin/env bash
# List Cursor agent transcript JSONL files for a given date (local timezone).
# Usage: list_today_sessions.sh [YYYY-MM-DD]
#   - No argument           -> today
#   - YYYY-MM-DD            -> that date
# Output: one absolute JSONL path per line, sorted by mtime ascending.
# Subagent transcripts (under */subagents/*) are excluded.

set -euo pipefail

TRANSCRIPT_ROOT="${CURSOR_TRANSCRIPT_ROOT:-$HOME/.cursor/projects/Users-jilunsun-projects/agent-transcripts}"

if [[ ! -d "$TRANSCRIPT_ROOT" ]]; then
  echo "ERROR: transcript root not found: $TRANSCRIPT_ROOT" >&2
  exit 2
fi

TARGET_DATE="${1:-$(date +%Y-%m-%d)}"

if ! [[ "$TARGET_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "ERROR: bad date '$TARGET_DATE', expected YYYY-MM-DD" >&2
  exit 2
fi

# Compute start/end of target date as unix seconds (local time).
# macOS BSD date is the reference; on linux, GNU date is used.
if date -j >/dev/null 2>&1; then
  START_TS=$(date -j -f "%Y-%m-%d %H:%M:%S" "$TARGET_DATE 00:00:00" "+%s")
  END_TS=$(date -j -f "%Y-%m-%d %H:%M:%S" "$TARGET_DATE 23:59:59" "+%s")
else
  START_TS=$(date -d "$TARGET_DATE 00:00:00" "+%s")
  END_TS=$(date -d "$TARGET_DATE 23:59:59" "+%s")
fi

# Find all top-level session JSONL files (excluding subagents/*),
# then filter by mtime falling inside [START_TS, END_TS].
# We sort by mtime ascending so the daily report bullets follow chronological order.
find "$TRANSCRIPT_ROOT" \
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
