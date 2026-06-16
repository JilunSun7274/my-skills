#!/usr/bin/env python3
"""Digest a single Cursor agent transcript JSONL into a compact JSON object.

Usage:
    python3 digest_session.py <path-to-session.jsonl> [--max-text-chars N]

Output (stdout, single JSON object):
    {
      "session_id": "cu-c7c5a075",
      "session_path": "/abs/path/session.jsonl",
      "start_time": "2026-05-26T10:11:00+08:00" | null,
      "end_time":   "2026-05-26T11:42:00+08:00" | null,
      "message_count": 42,
      "user_queries": ["...", "..."],
      "tool_signals": [{"kind": "Write", "description": "Create AGENTS.md"}, ...],
      "assistant_final_text": "<最后 N 字符的 assistant 主消息>",
      "touched_paths": ["/Users/.../foo.py", ...],
      "had_errors": false
    }

Design choices:
- Read tools (Read, Glob, Grep, ReadLints, AwaitShell, etc.) are DROPPED — they
  carry context, not work output.
- Write/StrReplace/Shell/Task/Delete/EditNotebook are KEPT as "tool_signals" with
  just the `description` (or first 120 chars of input) — these signal real work.
- `touched_paths` is heuristically extracted from tool_use inputs so the caller
  can decide which Product a session belongs to (path-based routing).
- The `assistant_final_text` is the last assistant text block, truncated.
- Long content is aggressively truncated; this is a SUMMARY, not a replay.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


READ_ONLY_TOOLS = {
    "Read",
    "Glob",
    "Grep",
    "ReadLints",
    "AwaitShell",
    "FetchMcpResource",
    "WebFetch",
    "WebSearch",
    "ListMcpResources",
    "SwitchMode",
    "TodoWrite",
    "AskQuestion",
}

WORK_TOOLS = {
    "Write",
    "StrReplace",
    "EditNotebook",
    "Delete",
    "Shell",
    "Task",
    "CallMcpTool",
    "GenerateImage",
    "CreatePlan",
    "SetActiveBranch",
}

TIMESTAMP_RE = re.compile(
    r"<timestamp>([^<]+)</timestamp>"
)
USER_QUERY_RE = re.compile(
    r"<user_query>\s*(.*?)\s*</user_query>",
    re.DOTALL,
)
PATH_RE = re.compile(
    r"(?<![\w.])(/(?:Users|home|opt|etc|var|tmp|srv)/[^\s'\"`)<>]+)"
)


def _extract_text_blocks(content: Any) -> list[str]:
    """tool_result content may be a string or a list of {type,text} dicts."""
    if isinstance(content, str):
        return [content]
    if isinstance(content, list):
        out = []
        for b in content:
            if isinstance(b, dict):
                if b.get("type") == "text":
                    out.append(b.get("text", ""))
                elif "text" in b:
                    out.append(str(b["text"]))
        return out
    return []


def _parse_timestamp(text: str) -> str | None:
    """Pull an ISO-ish timestamp out of a `<timestamp>...</timestamp>` marker."""
    m = TIMESTAMP_RE.search(text or "")
    if not m:
        return None
    raw = m.group(1).strip()
    # Examples: "Tuesday, May 26, 2026, 10:11 AM (UTC+8)"
    fmt = "%A, %B %d, %Y, %I:%M %p"
    head = raw.split(" (")[0]
    tz = ""
    if "(" in raw and ")" in raw:
        tz = raw[raw.index("(") + 1 : raw.index(")")]
    try:
        dt = datetime.strptime(head, fmt)
    except ValueError:
        return None
    iso = dt.isoformat(timespec="seconds")
    if tz.upper().startswith("UTC"):
        offset = tz[3:].strip() or "+00:00"
        if re.fullmatch(r"[+-]\d{1,2}", offset):
            sign = offset[0]
            hours = int(offset[1:])
            offset = f"{sign}{hours:02d}:00"
        iso = iso + offset
    return iso


def _short(text: str, max_chars: int) -> str:
    text = (text or "").strip()
    if len(text) <= max_chars:
        return text
    return text[: max_chars - 1].rstrip() + "…"


def _collect_paths(value: Any, sink: set[str]) -> None:
    if value is None:
        return
    if isinstance(value, str):
        for m in PATH_RE.finditer(value):
            p = m.group(1)
            if len(p) < 200:
                sink.add(p)
        return
    if isinstance(value, dict):
        for k in ("path", "target_notebook", "working_directory"):
            v = value.get(k)
            if isinstance(v, str):
                sink.add(v)
        for v in value.values():
            _collect_paths(v, sink)
        return
    if isinstance(value, list):
        for v in value:
            _collect_paths(v, sink)


def _tool_signal_description(tool_name: str, tool_input: dict) -> str:
    """Pick the most informative short description for a work-tool invocation."""
    if not isinstance(tool_input, dict):
        return ""
    for k in ("description", "title", "name", "command", "old_string", "contents"):
        v = tool_input.get(k)
        if isinstance(v, str) and v.strip():
            return _short(v.strip().splitlines()[0], 120)
    path = tool_input.get("path") or tool_input.get("target_notebook")
    if isinstance(path, str):
        return f"{tool_name} {path}"
    return ""


def digest(jsonl_path: Path, max_text_chars: int = 1500) -> dict:
    session_id = "cu-" + jsonl_path.stem.split("-")[0]

    user_queries: list[str] = []
    tool_signals: list[dict] = []
    touched_paths: set[str] = set()
    assistant_texts: list[str] = []
    start_time: str | None = None
    end_time: str | None = None
    had_errors = False
    message_count = 0

    with jsonl_path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            message_count += 1
            role = obj.get("role")
            msg = obj.get("message", {}) if isinstance(obj.get("message"), dict) else {}
            content = msg.get("content", []) if isinstance(msg, dict) else []
            if not isinstance(content, list):
                continue

            for block in content:
                if not isinstance(block, dict):
                    continue
                btype = block.get("type")

                if btype == "text":
                    text = block.get("text", "") or ""
                    if role == "user":
                        ts = _parse_timestamp(text)
                        if ts:
                            if start_time is None:
                                start_time = ts
                            end_time = ts
                        for m in USER_QUERY_RE.finditer(text):
                            q = m.group(1).strip()
                            if q:
                                user_queries.append(_short(q, 600))
                    elif role == "assistant":
                        stripped = text.strip()
                        if stripped:
                            assistant_texts.append(stripped)

                elif btype == "tool_use":
                    name = block.get("name", "")
                    tool_input = block.get("input", {}) if isinstance(block.get("input"), dict) else {}
                    _collect_paths(tool_input, touched_paths)
                    if name in READ_ONLY_TOOLS:
                        continue
                    if name in WORK_TOOLS or name not in READ_ONLY_TOOLS:
                        desc = _tool_signal_description(name, tool_input)
                        if desc or name in WORK_TOOLS:
                            tool_signals.append({"kind": name, "description": desc})

                elif btype == "tool_result":
                    if block.get("is_error"):
                        had_errors = True
                    for t in _extract_text_blocks(block.get("content")):
                        low = t.lower()
                        if "error" in low or "exception" in low or "traceback" in low:
                            had_errors = True

    if len(tool_signals) > 30:
        tool_signals = tool_signals[:30] + [
            {"kind": "...", "description": f"({len(tool_signals) - 30} more signals omitted)"}
        ]

    assistant_final_text = ""
    if assistant_texts:
        assistant_final_text = _short(assistant_texts[-1], max_text_chars)

    touched_sorted = sorted(touched_paths)
    if len(touched_sorted) > 50:
        touched_sorted = touched_sorted[:50]

    return {
        "session_id": session_id,
        "session_path": str(jsonl_path),
        "start_time": start_time,
        "end_time": end_time,
        "message_count": message_count,
        "user_queries": user_queries,
        "tool_signals": tool_signals,
        "assistant_final_text": assistant_final_text,
        "touched_paths": touched_sorted,
        "had_errors": had_errors,
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("jsonl_path", type=Path, help="Path to a session JSONL file")
    p.add_argument(
        "--max-text-chars",
        type=int,
        default=1500,
        help="Truncate the final assistant text at N chars (default: 1500)",
    )
    args = p.parse_args()

    if not args.jsonl_path.is_file():
        print(f"ERROR: not a file: {args.jsonl_path}", file=sys.stderr)
        return 2

    result = digest(args.jsonl_path, max_text_chars=args.max_text_chars)
    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
