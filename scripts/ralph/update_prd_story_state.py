#!/usr/bin/env python3
"""
Update a story's passes state in a PRD JSON file.

This is intentionally small and dependency-free so agents can safely use it
instead of manually editing large PRD JSON files.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def update_prd_story_state(prd_path: str, story_id: str, passes: bool) -> None:
    prd_file = Path(prd_path).expanduser().resolve()
    if not prd_file.exists():
        print(f"Error: PRD file not found: {prd_file}", file=sys.stderr)
        raise SystemExit(1)

    with prd_file.open("r", encoding="utf-8") as f:
        prd = json.load(f)

    stories = prd.get("userStories", [])
    if not isinstance(stories, list):
        print("Error: PRD field 'userStories' must be an array", file=sys.stderr)
        raise SystemExit(1)

    story_found = False
    for story in stories:
        if isinstance(story, dict) and story.get("id") == story_id:
            story["passes"] = passes
            story_found = True
            break

    if not story_found:
        print(f"Error: Story {story_id} not found in PRD", file=sys.stderr)
        raise SystemExit(1)

    prd_file.write_text(json.dumps(prd, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Updated story {story_id} passes={passes} in {prd_file}")


def _parse_bool(s: str) -> bool:
    v = s.strip().lower()
    if v in ("true", "1", "yes", "y"):
        return True
    if v in ("false", "0", "no", "n"):
        return False
    raise argparse.ArgumentTypeError("passes must be true/false")


def main() -> int:
    parser = argparse.ArgumentParser(description="Update story state in PRD JSON")
    parser.add_argument("--prd", required=True, help="Path to PRD JSON file")
    parser.add_argument("--id", required=True, help="Story ID (e.g., US-001)")
    parser.add_argument("--passes", type=_parse_bool, required=True, help="Passes state (true/false)")
    args = parser.parse_args()

    update_prd_story_state(args.prd, args.id, args.passes)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
