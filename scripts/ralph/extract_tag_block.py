#!/usr/bin/env python3
"""
Extract a tagged block from stdin.

Example:
  echo "x <tag>hello</tag> y" | python3 extract_tag_block.py --tag tag
prints:
  hello
"""

from __future__ import annotations

import argparse
import re
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract <tag>...</tag> block from stdin.")
    parser.add_argument("--tag", required=True, help="Tag name (without brackets), e.g. ralph_progress")
    args = parser.parse_args()

    tag = args.tag.strip()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]*", tag):
        print(f"Error: invalid tag name: {tag}", file=sys.stderr)
        return 2

    text = sys.stdin.read()
    # Non-greedy match across newlines; allow whitespace in tags.
    pattern = re.compile(rf"<\s*{re.escape(tag)}\s*>(.*?)<\s*/\s*{re.escape(tag)}\s*>", re.DOTALL)
    m = pattern.search(text)
    if not m:
        return 1

    content = m.group(1)
    # Trim only outer whitespace; preserve internal formatting.
    sys.stdout.write(content.strip() + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
