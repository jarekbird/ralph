#!/usr/bin/env python3
"""
Update a story's notes field in a PRD JSON file.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Update story notes in PRD JSON")
    parser.add_argument("--prd", required=True, help="Path to PRD JSON file")
    parser.add_argument("--id", required=True, help="Story ID (e.g., US-001)")
    parser.add_argument("--notes", help="Notes text. If omitted, read from stdin.")
    parser.add_argument("--append", action="store_true", help="Append to existing notes instead of replacing")
    parser.add_argument("--timestamp", action="store_true", help="Prefix appended notes with an ISO timestamp")
    args = parser.parse_args()

    prd_path = Path(args.prd).expanduser().resolve()
    if not prd_path.exists():
        print(f"Error: PRD file not found: {prd_path}", file=sys.stderr)
        return 1

    notes = args.notes if args.notes is not None else sys.stdin.read()
    notes = (notes or "").strip()
    if not notes:
        return 0  # no-op

    prd = json.loads(prd_path.read_text(encoding="utf-8"))
    stories = prd.get("userStories", [])
    if not isinstance(stories, list):
        print("Error: PRD field 'userStories' must be an array", file=sys.stderr)
        return 1

    found = False
    for story in stories:
        if isinstance(story, dict) and story.get("id") == args.id:
            found = True
            existing = (story.get("notes") or "").strip()
            if args.append and existing:
                prefix = ""
                if args.timestamp:
                    prefix = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") + "\n"
                story["notes"] = (existing + "\n\n" + prefix + notes).strip()
            else:
                story["notes"] = notes
            break

    if not found:
        print(f"Error: Story {args.id} not found in PRD", file=sys.stderr)
        return 1

    prd_path.write_text(json.dumps(prd, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
