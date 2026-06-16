#!/usr/bin/env python3
"""Digest a single Claude Code transcript JSONL into a compact JSON object.

Usage:
    python3 digest_claude_session.py <path-to-session.jsonl> [--max-text-chars N]

Output schema is identical to digest_session.py, plus a `cwd` field:
    {
      "session_id": "cc-26731439",            # cc- prefix marks Claude Code origin
      "session_path": "/abs/path/session.jsonl",
      "start_time": "2026-05-27T11:17:04.336Z" | null,
      "end_time":   "2026-05-27T11:42:00.000Z" | null,
      "message_count": 42,
      "user_queries": ["...", "..."],
      "tool_signals": [{"kind": "Write", "description": "..."}, ...],
      "assistant_final_text": "<last assistant text, truncated>",
      "touched_paths": ["/Users/.../foo.py", ...],
      "had_errors": false,
      "cwd": "/Users/jilunsun/projects" | null    # Claude-only; used for Product routing
    }

Reuses helpers from digest_session.py (same directory): PATH_RE, _short,
_collect_paths.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from digest_session import PATH_RE, _short, _collect_paths  # noqa: E402


READ_ONLY_TOOLS = {
    "Read",
    "Glob",
    "Grep",
    "NotebookRead",
    "TodoWrite",
    "TaskCreate",
    "TaskUpdate",
    "TaskGet",
    "TaskList",
    "TaskStop",
    "WebFetch",
    "WebSearch",
    "AskUserQuestion",
    "BashOutput",
    "KillShell",
    "SlashCommand",
    "ListMcpResources",
    "ReadMcpResource",
    "ExitPlanMode",
}

WORK_TOOLS = {
    "Edit",
    "Write",
    "MultiEdit",
    "NotebookEdit",
    "Bash",
    "Task",
}

SKIP_TYPES = {
    "mode",
    "permission-mode",
    "file-history-snapshot",
    "ai-title",
    "last-prompt",
    "system",
}

CMD_NAME_RE = re.compile(r"<command-name>\s*([^<]+?)\s*</command-name>")
CMD_ARGS_RE = re.compile(r"<command-args>\s*(.*?)\s*</command-args>", re.DOTALL)
WRAPPER_PREFIXES = (
    "<local-command-caveat>",
    "<command-message>",
    "<command-name>",
    "Caveat: The messages below",
)


def _user_query_from_string(text: str) -> str | None:
    """Claude user content is a plain str. Filter slash-command wrappers and
    local-command caveats; preserve genuine queries and meaningful /cmd args."""
    t = (text or "").strip()
    if not t:
        return None
    if "<command-name>" in t:
        args_m = CMD_ARGS_RE.search(t)
        if args_m and args_m.group(1).strip():
            name_m = CMD_NAME_RE.search(t)
            prefix = (name_m.group(1).strip() + " ") if name_m else ""
            return _short(prefix + args_m.group(1).strip(), 600)
        return None
    if t.startswith(WRAPPER_PREFIXES) or "DO NOT respond to these messages" in t:
        return None
    return _short(t, 600)


def _tool_signal_description(tool_name: str, tool_input: dict) -> str:
    """Pick the most informative short description for a work-tool invocation."""
    if not isinstance(tool_input, dict):
        return ""
    for k in ("description", "title", "command", "old_string", "content"):
        v = tool_input.get(k)
        if isinstance(v, str) and v.strip():
            return _short(v.strip().splitlines()[0], 120)
    fp = (
        tool_input.get("file_path")
        or tool_input.get("notebook_path")
        or tool_input.get("path")
    )
    if isinstance(fp, str):
        return f"{tool_name} {fp}"
    return ""


def _collect_paths_cc(tool_input: Any, sink: set[str]) -> None:
    if isinstance(tool_input, dict):
        for k in ("file_path", "notebook_path", "path"):
            v = tool_input.get(k)
            if isinstance(v, str) and v.startswith("/") and len(v) < 200:
                sink.add(v)
    _collect_paths(tool_input, sink)


def digest(jsonl_path: Path, max_text_chars: int = 1500) -> dict:
    session_id = "cc-" + jsonl_path.stem.split("-")[0]

    user_queries: list[str] = []
    tool_signals: list[dict] = []
    touched_paths: set[str] = set()
    assistant_texts: list[str] = []
    start_time: str | None = None
    end_time: str | None = None
    last_cwd: str | None = None
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

            if obj.get("isSidechain"):
                continue
            otype = obj.get("type")
            if otype in SKIP_TYPES or otype == "attachment":
                continue

            ts = obj.get("timestamp")
            if isinstance(ts, str) and ts:
                if start_time is None:
                    start_time = ts
                end_time = ts
            cwd = obj.get("cwd")
            if isinstance(cwd, str) and cwd:
                last_cwd = cwd

            msg = obj.get("message") if isinstance(obj.get("message"), dict) else {}

            if otype == "user":
                message_count += 1
                content = msg.get("content")
                if isinstance(content, str):
                    q = _user_query_from_string(content)
                    if q:
                        user_queries.append(q)
                elif isinstance(content, list):
                    for b in content:
                        if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("is_error"):
                            had_errors = True
                tur = obj.get("toolUseResult")
                if isinstance(tur, dict):
                    stderr = tur.get("stderr")
                    if (isinstance(stderr, str) and stderr.strip()) or tur.get("interrupted"):
                        had_errors = True

            elif otype == "assistant":
                message_count += 1
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    btype = block.get("type")
                    if btype == "text":
                        s = (block.get("text") or "").strip()
                        if s:
                            assistant_texts.append(s)
                    elif btype == "tool_use":
                        name = block.get("name", "")
                        tool_input = block.get("input") if isinstance(block.get("input"), dict) else {}
                        _collect_paths_cc(tool_input, touched_paths)
                        if name in READ_ONLY_TOOLS:
                            continue
                        desc = _tool_signal_description(name, tool_input)
                        if desc or name in WORK_TOOLS:
                            tool_signals.append({"kind": name, "description": desc})
                    elif btype == "tool_result" and block.get("is_error"):
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
        "cwd": last_cwd,
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("jsonl_path", type=Path, help="Path to a Claude Code session JSONL file")
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
