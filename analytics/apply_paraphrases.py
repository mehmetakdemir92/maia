#!/usr/bin/env python3
"""
Rewrite the correct option of each `definition` quiz item so it no longer
repeats the card definition word for word.

The card keeps its original hand-written definition — that is what teaches.
Only the quiz's correct option changes, to a paraphrase of the same meaning.
The learner then has to map meaning onto meaning instead of recognising a
sentence they read a minute earlier, and because the paraphrase is written to
sit inside the distractors' length band, "pick the longest option" stops
working as a strategy.

Paraphrases live in analytics/paraphrases/<lang>.json as {word: text} and are
written by hand, never generated.

    python3 analytics/apply_paraphrases.py --lang en          # apply
    python3 analytics/apply_paraphrases.py --lang en --check  # validate only
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CURRICULUM = ROOT / "maia" / "Curriculum"
PARAPHRASES = Path(__file__).resolve().parent / "paraphrases"


def stem(word: str) -> str:
    w = word.lower()
    return w[: max(4, len(w) - 3)]


def validate(word: dict, new: str, distractors: list[str]) -> list[str]:
    """Everything that must hold before a paraphrase is allowed in."""
    problems = []
    lemma = word["word"]

    if not new.strip():
        problems.append("empty")
    if new.strip().lower() == word["definition"].strip().lower():
        problems.append("identical to the card definition — no paraphrase happened")
    if stem(lemma) in new.lower():
        problems.append(f"contains the headword stem '{stem(lemma)}' — gives the answer away")
    if any(new.strip().lower() == d.strip().lower() for d in distractors):
        problems.append("duplicates one of the distractors")
    if not new.rstrip().endswith((".", "!", "?")):
        problems.append("missing terminal punctuation (distractors all have it)")

    # The point is that length carries no signal, so the answer has to sit
    # INSIDE the distractors' band. Only checking the upper bound is not
    # enough: shortening every answer just turns "pick the longest" into
    # "pick the shortest", which is exactly as exploitable.
    lo, hi = min(map(len, distractors)), max(map(len, distractors))
    if len(new) > hi + 4:
        problems.append(f"{len(new) - hi} chars longer than the longest distractor — reads as the answer")
    if len(new) < lo - 4:
        problems.append(f"{lo - len(new)} chars shorter than the shortest distractor — reads as the answer")
    return problems


def run(lang: str, check_only: bool) -> int:
    path = CURRICULUM / f"{lang}.json"
    data = json.loads(path.read_text())

    para_path = PARAPHRASES / f"{lang}.json"
    if not para_path.exists():
        print(f"no paraphrases for {lang} yet ({para_path})")
        return 0
    paraphrases = json.loads(para_path.read_text())

    applied, skipped, failures = 0, 0, []
    before_margins, after_margins = [], []

    for slot in data["slots"]:
        for word in slot["words"]:
            new = paraphrases.get(word["word"])
            for quiz in word["quiz"]:
                if quiz["type"] != "definition":
                    continue
                ci = quiz["correctAnswerIndex"]
                distractors = [o for i, o in enumerate(quiz["options"]) if i != ci]
                before_margins.append(len(quiz["options"][ci]) - statistics.mean(map(len, distractors)))

                if new is None:
                    skipped += 1
                    after_margins.append(before_margins[-1])
                    continue

                problems = validate(word, new, distractors)
                if problems:
                    failures.append((word["word"], problems))
                    after_margins.append(before_margins[-1])
                    continue

                quiz["options"][ci] = new
                applied += 1
                after_margins.append(len(new) - statistics.mean(map(len, distractors)))

    for lemma, problems in failures:
        print(f"  REJECTED {lemma}: {'; '.join(problems)}")

    print(f"{lang}: {applied} applied, {skipped} still using the card definition, {len(failures)} rejected")
    if before_margins:
        print(f"     mean length margin over distractors: "
              f"{statistics.mean(before_margins):+.1f} -> {statistics.mean(after_margins):+.1f} chars")

    if failures:
        return 1
    if not check_only and applied:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        print(f"     wrote {path}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--lang", choices=["en", "de"], required=True)
    ap.add_argument("--check", action="store_true", help="validate without writing")
    args = ap.parse_args()
    return run(args.lang, args.check)


if __name__ == "__main__":
    sys.exit(main())
