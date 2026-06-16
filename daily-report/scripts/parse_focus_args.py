#!/usr/bin/env python3
"""Parse $ARGUMENTS for /daily-report INGEST + FOCUS mode.

Usage:
    python3 parse_focus_args.py "<$ARGUMENTS verbatim>"

Output (stdout, single JSON object):
    {
      "target_date":     "YYYY-MM-DD" | null,
      "paths":           ["/abs/path", ...],          # realpath + expanded
      "nl_instruction":  "..." | null,
      "warnings":        ["..."]
    }

Token classification:
- First token matching ^\\d{4}-\\d{2}-\\d{2}$         -> target_date
- Token starting with "/" or "~/" (or bare "~"):
    - no glob char    -> realpath if exists; else warn + treat as NL
    - has glob char   -> shell-glob; keep first MAX_GLOB matches; else warn + treat as NL
- Everything else                                    -> NL words (joined with space)

Path identification is INTENTIONALLY restricted to absolute / home-relative
paths. Relative paths like "./foo" or "foo/bar" are NOT recognized because the
slash command runs across multiple cwds and CWD is unreliable.
"""

from __future__ import annotations

import argparse
import glob as _glob
import json
import os
import re
import shlex
import sys
from pathlib import Path

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
GLOB_CHARS = set("*?[")
MAX_GLOB = 10


def parse(arguments: str) -> dict:
    tokens = shlex.split(arguments or "")
    target_date: str | None = None
    paths: list[str] = []
    nl_words: list[str] = []
    warnings: list[str] = []

    for tok in tokens:
        if target_date is None and DATE_RE.match(tok):
            target_date = tok
            continue

        looks_pathlike = tok == "~" or tok.startswith("/") or tok.startswith("~/")
        has_glob = any(c in tok for c in GLOB_CHARS)

        if looks_pathlike and not has_glob:
            expanded = os.path.expanduser(tok)
            if Path(expanded).exists():
                paths.append(os.path.realpath(expanded))
                continue
            warnings.append(f"path not found, treated as NL: {tok}")
        elif looks_pathlike and has_glob:
            expanded = os.path.expanduser(tok)
            matches = sorted(set(_glob.glob(expanded, recursive=True)))
            if matches:
                if len(matches) > MAX_GLOB:
                    warnings.append(
                        f"glob {tok} -> {len(matches)} matches, kept first {MAX_GLOB}"
                    )
                    matches = matches[:MAX_GLOB]
                paths.extend(os.path.realpath(m) for m in matches)
                continue
            warnings.append(f"glob {tok} matched nothing, treated as NL")

        nl_words.append(tok)

    # Dedupe paths preserving order
    seen: set[str] = set()
    deduped: list[str] = []
    for p in paths:
        if p not in seen:
            seen.add(p)
            deduped.append(p)

    return {
        "target_date": target_date,
        "paths": deduped,
        "nl_instruction": " ".join(nl_words).strip() or None,
        "warnings": warnings,
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("arguments", nargs="?", default="",
                   help="Verbatim $ARGUMENTS string (may be empty)")
    args = p.parse_args()
    json.dump(parse(args.arguments), sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
