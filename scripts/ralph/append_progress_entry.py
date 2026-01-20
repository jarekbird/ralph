#!/usr/bin/env python3
"""
Append a progress entry to a Ralph log file.

This is a convenience tool for cases where you want to enforce a consistent
format without relying on an agent to edit the log file directly.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Append a progress entry to a log file.")
    parser.add_argument("--log", required=True, help="Path to log file")
    parser.add_argument("--text-file", help="Path to a file containing the full entry text")
    parser.add_argument(
        "--text",
        help="Entry text. If omitted and --text-file not provided, reads from stdin.",
    )
    args = parser.parse_args()

    log_path = Path(args.log).expanduser().resolve()
    log_path.parent.mkdir(parents=True, exist_ok=True)

    if args.text_file:
        entry = Path(args.text_file).expanduser().resolve().read_text(encoding="utf-8", errors="replace")
    elif args.text is not None:
        entry = args.text
    else:
        entry = sys.stdin.read()

    entry = entry.strip()
    if not entry:
        print("Error: empty entry text", file=sys.stderr)
        return 2

    with log_path.open("a", encoding="utf-8") as f:
        f.write("\n")
        f.write(entry)
        if not entry.endswith("\n"):
            f.write("\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
