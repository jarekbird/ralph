#!/usr/bin/env python3
"""
Select the next Ralph user story from a PRD JSON file.

Why this exists:
- Avoids making the agent re-read huge PRD JSON every iteration.
- Makes "pick next story" deterministic and less error-prone.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


def _load_json(path: Path) -> Dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"PRD file not found: {path}")
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("PRD root must be a JSON object")
    return data


def _story_priority_key(story: Dict[str, Any], idx: int) -> Tuple[int, int]:
    priority = story.get("priority", 10**9)
    try:
        prio_num = int(priority)
    except Exception:
        prio_num = 10**9
    return prio_num, idx


def _pick_next_story(stories: List[Dict[str, Any]]) -> Tuple[Optional[int], Optional[Dict[str, Any]]]:
    """
    Select "highest priority" story where passes == false.

    Convention used here:
    - Lower numeric priority means higher priority (1 is highest).
    - Tie-breaker: original list order.
    """
    candidates: List[Tuple[int, int, Dict[str, Any]]] = []
    for idx, story in enumerate(stories):
        if not isinstance(story, dict):
            continue
        if story.get("passes") is True:
            continue
        prio_num, list_idx = _story_priority_key(story, idx)
        candidates.append((prio_num, list_idx, story))

    if not candidates:
        return None, None

    candidates.sort(key=lambda t: (t[0], t[1]))
    _, idx, story = candidates[0]
    return idx, story


def _pick_next_stories(stories: List[Dict[str, Any]], count: int) -> List[Tuple[int, Dict[str, Any]]]:
    if count <= 0:
        return []
    candidates: List[Tuple[int, int, Dict[str, Any]]] = []
    for idx, story in enumerate(stories):
        if not isinstance(story, dict):
            continue
        if story.get("passes") is True:
            continue
        prio_num, list_idx = _story_priority_key(story, idx)
        candidates.append((prio_num, list_idx, story))
    candidates.sort(key=lambda t: (t[0], t[1]))
    picked: List[Tuple[int, Dict[str, Any]]] = []
    for prio_num, list_idx, story in candidates[:count]:
        picked.append((list_idx, story))
    return picked


def main() -> int:
    parser = argparse.ArgumentParser(description="Select next story from a Ralph PRD JSON.")
    parser.add_argument("--prd", required=True, help="Path to prd.json (or *.prd.json)")
    parser.add_argument("--count", type=int, default=1, help="Number of stories to select (default: 1)")
    parser.add_argument("--out", help="Optional path to write selected story JSON")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON output")
    args = parser.parse_args()

    prd_path = Path(args.prd).expanduser().resolve()
    prd = _load_json(prd_path)

    stories = prd.get("userStories", [])
    if not isinstance(stories, list):
        raise ValueError("PRD field 'userStories' must be an array")

    count = max(1, int(args.count or 1))
    picked = _pick_next_stories(stories, count=count)
    selected_index = picked[0][0] if picked else None
    selected_story = picked[0][1] if picked else None
    selected_stories = [s for _, s in picked]
    selected_ids = [str(s.get("id")) for s in selected_stories if isinstance(s, dict) and s.get("id")]

    remaining = 0
    for s in stories:
        if isinstance(s, dict) and s.get("passes") is not True:
            remaining += 1

    payload: Dict[str, Any] = {
        "prdPath": str(prd_path),
        "project": prd.get("project"),
        "branchName": prd.get("branchName"),
        "contextFile": prd.get("contextFile"),
        "logFile": prd.get("logFile"),
        "description": prd.get("description"),
        "remainingStories": remaining,
        # Back-compat single-story fields
        "selectedIndex": selected_index,
        "selectedStory": selected_story,
        # Multi-story fields
        "selectedCount": count,
        "selectedIds": selected_ids,
        "selectedStories": selected_stories,
    }

    indent = 2 if args.pretty else None
    text = json.dumps(payload, indent=indent, ensure_ascii=False) + "\n"

    if args.out:
        out_path = Path(args.out).expanduser().resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(text, encoding="utf-8")

    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        # Allow piping to head/grep without stack traces.
        raise SystemExit(0)
