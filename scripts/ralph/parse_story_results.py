#!/usr/bin/env python3
"""
Parse per-story results from agent output.

Supported formats:

1) Preferred (per-story notes + explicit pass/fail):
  <ralph_story_result id="US-001" passes="true">
  Notes...
  </ralph_story_result>

2) Lightweight pass marker (no notes):
  <ralph_story_pass id="US-001"/>

3) Back-compat single-story pass marker (no id):
  <ralph_story_pass/>
  (only used if --default-id is provided)
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from typing import List, Optional


@dataclass
class StoryResult:
    id: str
    passes: Optional[bool]  # None if unknown
    notes: str


_TAG_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*$")


def _parse_bool(v: str) -> Optional[bool]:
    s = v.strip().lower()
    if s in ("true", "1", "yes", "y"):
        return True
    if s in ("false", "0", "no", "n"):
        return False
    return None


def parse_story_results(text: str, default_id: Optional[str]) -> List[StoryResult]:
    results: List[StoryResult] = []

    # 1) Full blocks
    block_re = re.compile(
        r'<\s*ralph_story_result\b([^>]*)>(.*?)<\s*/\s*ralph_story_result\s*>',
        re.DOTALL | re.IGNORECASE,
    )
    attr_id_re = re.compile(r'\bid\s*=\s*["\']([^"\']+)["\']', re.IGNORECASE)
    attr_passes_re = re.compile(r'\bpasses\s*=\s*["\']([^"\']+)["\']', re.IGNORECASE)

    for attrs, body in block_re.findall(text):
        m_id = attr_id_re.search(attrs)
        if not m_id:
            continue
        sid = m_id.group(1).strip()
        if not sid:
            continue
        m_passes = attr_passes_re.search(attrs)
        passes = _parse_bool(m_passes.group(1)) if m_passes else None
        notes = body.strip()
        results.append(StoryResult(id=sid, passes=passes, notes=notes))

    # 2) Self-closing pass markers with id
    pass_id_re = re.compile(
        r'<\s*ralph_story_pass\b[^>]*\bid\s*=\s*["\']([^"\']+)["\'][^>]*/\s*>',
        re.IGNORECASE,
    )
    for sid in pass_id_re.findall(text):
        sid = sid.strip()
        if not sid:
            continue
        results.append(StoryResult(id=sid, passes=True, notes=""))

    # 3) Back-compat <ralph_story_pass/> with no id
    if default_id:
        legacy_re = re.compile(r'<\s*ralph_story_pass\s*/\s*>', re.IGNORECASE)
        if legacy_re.search(text):
            results.append(StoryResult(id=default_id, passes=True, notes=""))

    # De-dupe by id, preferring the *most informative* result:
    # - story_result with notes > story_result w/o notes > pass marker
    best = {}
    for r in results:
        score = 0
        if r.notes:
            score += 2
        if r.passes is not None:
            score += 1
        prev = best.get(r.id)
        if prev is None:
            best[r.id] = (score, r)
        else:
            if score > prev[0]:
                best[r.id] = (score, r)
    # Preserve stable ordering: first appearance order in the original results list
    ordered_ids = []
    seen = set()
    for r in results:
        if r.id in best and r.id not in seen:
            ordered_ids.append(r.id)
            seen.add(r.id)
    return [best[sid][1] for sid in ordered_ids]


def main() -> int:
    parser = argparse.ArgumentParser(description="Parse Ralph story results from stdin.")
    parser.add_argument("--default-id", help="Default story id for legacy <ralph_story_pass/>")
    args = parser.parse_args()

    default_id = args.default_id.strip() if args.default_id else None
    if default_id and not default_id:
        default_id = None

    text = sys.stdin.read()
    results = parse_story_results(text, default_id=default_id)

    out = [{"id": r.id, "passes": r.passes, "notes": r.notes} for r in results]
    sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
