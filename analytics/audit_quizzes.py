#!/usr/bin/env python3
"""
Audit the curriculum quizzes for answerable-without-knowing defects.

A multiple-choice item leaks when something other than meaning tells the
learner which option is right. This checks the leaks that actually show up in
hand-authored vocabulary sets, reports each with its severity, and exits
non-zero if any BLOCKER is present so it can gate a content change.

    python3 analytics/audit_quizzes.py            # both languages
    python3 analytics/audit_quizzes.py --lang de  # one
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import statistics
import sys
from pathlib import Path

CURRICULUM_DIR = Path(__file__).resolve().parent.parent / "maia" / "Curriculum"

# Share of items where "just pick the longest option" wins. Chance is 1/4, so
# anything approaching half means the heuristic beats knowing the word.
LONGEST_WARN = 0.40
LONGEST_BLOCK = 0.60


def load(lang: str) -> dict:
    return json.loads((CURRICULUM_DIR / f"{lang}.json").read_text())


def words_of(data: dict):
    for slot in data["slots"]:
        for word in slot["words"]:
            yield slot, word


def stem(word: str) -> str:
    """Enough of a headword to catch its own derivations in a definition."""
    w = word.lower()
    return w[: max(4, len(w) - 3)]


def audit(lang: str) -> list[tuple[str, str, str]]:
    """Returns (severity, check, detail) rows."""
    data = load(lang)
    rows: list[tuple[str, str, str]] = []
    items = [(w, q) for _, w in words_of(data) for q in w["quiz"]]
    defs = [(w, q) for w, q in items if q["type"] == "definition"]

    # --- Structural sanity -------------------------------------------------
    bad_shape = [
        w["word"] for w, q in items
        if len(q["options"]) != 4
        or not (0 <= q["correctAnswerIndex"] < len(q["options"]))
        or len(set(o.strip().lower() for o in q["options"])) != len(q["options"])
    ]
    if bad_shape:
        rows.append(("BLOCKER", "option shape",
                     f"{len(bad_shape)} items not 4 unique options with a valid answer index: {bad_shape[:5]}"))

    # --- Leak: the longest option is the answer ----------------------------
    if defs:
        longest = sum(
            1 for _, q in defs
            if max(range(len(q["options"])), key=lambda i: len(q["options"][i])) == q["correctAnswerIndex"]
        )
        share = longest / len(defs)
        margins = []
        for _, q in defs:
            ci = q["correctAnswerIndex"]
            others = [len(o) for i, o in enumerate(q["options"]) if i != ci]
            margins.append(len(q["options"][ci]) - statistics.mean(others))
        detail = (f"{longest}/{len(defs)} ({share:.0%}) of definition items have the answer as the "
                  f"longest option; mean margin {statistics.mean(margins):+.1f} chars (chance is 25%)")
        sev = "BLOCKER" if share >= LONGEST_BLOCK else "WARN" if share >= LONGEST_WARN else "OK"
        rows.append((sev, "length tell", detail))

    # --- Leak: the answer is the sentence the learner just read ------------
    verbatim = sum(
        1 for w, q in defs
        if q["options"][q["correctAnswerIndex"]].strip().lower() == w["definition"].strip().lower()
    )
    if verbatim:
        share = verbatim / len(defs)
        rows.append((
            "WARN" if share < 1 else "BLOCKER", "verbatim answer",
            f"{verbatim}/{len(defs)} ({share:.0%}) definition answers repeat the card definition word for "
            f"word, so the item tests recognition of a string just read, not comprehension",
        ))

    # --- Leak: the word defines itself -------------------------------------
    circular = [
        w["word"] for w, q in defs
        if stem(w["word"]) in q["options"][q["correctAnswerIndex"]].lower()
    ]
    if circular:
        rows.append(("BLOCKER", "circular definition",
                     f"{len(circular)} answers contain the headword's own stem: {circular}"))

    # --- Leak: the blank already shows its answer --------------------------
    given_away = [
        w["word"] for w, q in items
        if q["type"] == "blank"
        and q["options"][q["correctAnswerIndex"]].strip().lower() in q["question"].lower()
    ]
    if given_away:
        rows.append(("BLOCKER", "answer in prompt",
                     f"{len(given_away)} blank items print the answer in the sentence: {given_away}"))

    # --- Ambiguity: a distractor is some other word's real definition ------
    by_def = {w["definition"].strip().lower(): w["word"] for _, w in words_of(data)}
    clashes = []
    for w, q in defs:
        for i, opt in enumerate(q["options"]):
            if i == q["correctAnswerIndex"]:
                continue
            other = by_def.get(opt.strip().lower())
            if other and other != w["word"]:
                clashes.append(f"{w['word']}<-{other}")
    if clashes:
        # Not automatically wrong — an antonym's definition is a fine distractor —
        # but each one needs a human to confirm it cannot also be correct.
        rows.append(("REVIEW", "borrowed distractor",
                     f"{len(clashes)} distractors are another curriculum word's definition: {clashes}"))

    # --- Fatigue: the same distractor everywhere ---------------------------
    counts = collections.Counter(
        o.strip().lower()
        for w, q in items
        for i, o in enumerate(q["options"]) if i != q["correctAnswerIndex"]
    )
    heavy = [(o, c) for o, c in counts.most_common(5) if c >= 8]
    if heavy:
        rows.append(("REVIEW", "reused distractor",
                     f"appears as a wrong option many times: {heavy}"))

    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--lang", choices=["en", "de"], help="audit one language")
    args = ap.parse_args()

    langs = [args.lang] if args.lang else ["en", "de"]
    worst = 0
    for lang in langs:
        print(f"\n=== {lang} ===")
        for sev, check, detail in audit(lang):
            print(f"  [{sev:7}] {check:22} {detail}")
            if sev == "BLOCKER":
                worst = 1
    print()
    return worst


if __name__ == "__main__":
    sys.exit(main())
