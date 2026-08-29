#!/usr/bin/env python3
"""
Pull every user's Firestore data and write a snapshot + readable HTML report.

Auth comes from the gcloud CLI (`gcloud auth print-access-token`), so there is
no service-account key file to store or leak. Reads only — nothing here writes
to Firestore.

Cost: Firestore's free tier allows 50,000 document reads/day. One full run
costs roughly (users x their doc count) reads, so at this size a run is a
rounding error against that quota.

Usage:
    python3 analytics/pull_users.py                 # snapshot + report
    python3 analytics/pull_users.py --out ./report  # choose output dir
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import ssl
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

PROJECT = "vocability-6f0f3"
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"

# Subcollections under users/{uid} worth pulling. `appData` and `curriculum`
# are small key/value docs; the rest are event-shaped and can grow.
SUBCOLLECTIONS = [
    "appAnalyticsEvents",
    "diaryEntries",
    "wordProgress",
    "quizEvents",
    "appData",
    "curriculum",
]


# --------------------------------------------------------------------------
# Firestore REST plumbing
# --------------------------------------------------------------------------

def access_token() -> str:
    try:
        out = subprocess.run(
            ["gcloud", "auth", "print-access-token"],
            capture_output=True, text=True, check=True,
        )
    except FileNotFoundError:
        sys.exit("gcloud not found. Install the Google Cloud SDK first.")
    except subprocess.CalledProcessError as exc:
        sys.exit(f"gcloud auth failed — run `gcloud auth login`.\n{exc.stderr.strip()}")
    return out.stdout.strip()


def ssl_context() -> ssl.SSLContext:
    """
    python.org macOS builds ship without a configured CA bundle, so a plain
    urlopen fails with CERTIFICATE_VERIFY_FAILED. Prefer certifi's bundle when
    it is installed and fall back to the default trust store otherwise.
    """
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


_SSL = ssl_context()


def get_json(url: str, token: str) -> dict[str, Any]:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=60, context=_SSL) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode()[:400]
        sys.exit(f"Firestore request failed ({exc.code}) for {url}\n{body}")


def list_documents(path: str, token: str) -> list[dict[str, Any]]:
    """Every document in a collection, following pagination to the end."""
    docs: list[dict[str, Any]] = []
    page_token = None
    while True:
        params = {"pageSize": "300"}
        if page_token:
            params["pageToken"] = page_token
        url = f"{BASE}/{path}?{urllib.parse.urlencode(params)}"
        data = get_json(url, token)
        docs.extend(data.get("documents", []))
        page_token = data.get("nextPageToken")
        if not page_token:
            return docs


def decode(value: dict[str, Any]) -> Any:
    """Firestore's typed value wrapper -> plain Python."""
    if "nullValue" in value:
        return None
    if "booleanValue" in value:
        return value["booleanValue"]
    if "integerValue" in value:
        return int(value["integerValue"])
    if "doubleValue" in value:
        return value["doubleValue"]
    if "timestampValue" in value:
        return value["timestampValue"]
    if "stringValue" in value:
        return value["stringValue"]
    if "arrayValue" in value:
        return [decode(v) for v in value["arrayValue"].get("values", [])]
    if "mapValue" in value:
        return {k: decode(v) for k, v in value["mapValue"].get("fields", {}).items()}
    # bytesValue / referenceValue / geoPointValue — kept raw, not used by this app
    return next(iter(value.values()), None)


def doc_fields(doc: dict[str, Any]) -> dict[str, Any]:
    return {k: decode(v) for k, v in doc.get("fields", {}).items()}


def doc_id(doc: dict[str, Any]) -> str:
    return doc["name"].rsplit("/", 1)[-1]


# --------------------------------------------------------------------------
# Pull
# --------------------------------------------------------------------------

def pull_everything(token: str) -> dict[str, Any]:
    users = list_documents("users", token)
    print(f"users: {len(users)}")

    snapshot: dict[str, Any] = {
        "pulledAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "project": PROJECT,
        "users": {},
    }

    for user in users:
        uid = doc_id(user)
        record: dict[str, Any] = {"uid": uid, "doc": doc_fields(user)}
        for coll in SUBCOLLECTIONS:
            docs = list_documents(f"users/{uid}/{coll}", token)
            record[coll] = [{"id": doc_id(d), **doc_fields(d)} for d in docs]
            print(f"  {uid[:8]}… {coll}: {len(docs)}")
        snapshot["users"][uid] = record

    return snapshot


# --------------------------------------------------------------------------
# Derive per-user behaviour
# --------------------------------------------------------------------------

def parse_ts(raw: Any) -> dt.datetime | None:
    if not isinstance(raw, str):
        return None
    try:
        return dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def summarize(record: dict[str, Any]) -> dict[str, Any]:
    events = record.get("appAnalyticsEvents", [])
    diary = record.get("diaryEntries", [])
    progress = record.get("wordProgress", [])
    quizzes = record.get("quizEvents", [])
    appdata = {d["id"]: d for d in record.get("appData", [])}
    curriculum = {d["id"]: d for d in record.get("curriculum", [])}

    times = [t for t in (parse_ts(e.get("createdAt")) for e in events) if t]
    active_days = sorted({t.date().isoformat() for t in times})
    by_name = Counter(e.get("name", "?") for e in events)

    # Daily activity, for the sparkline
    per_day = Counter(t.date().isoformat() for t in times)

    # Quiz accuracy across recorded quiz events
    correct = sum(q.get("correct", 0) or 0 for q in quizzes)
    total = sum(q.get("total", 0) or 0 for q in quizzes)

    # Mastery ladder: repetitions maps to the SM-2 interval step (see
    # WordProgress.masteryLevel). Retired words count as fully learned.
    mastery = Counter()
    lapses_total = 0
    retired = 0
    for p in progress:
        lapses_total += p.get("lapses", 0) or 0
        if p.get("retired"):
            retired += 1
            mastery[5] += 1
        else:
            mastery[min(max((p.get("repetitions", 0) or 0) + 1, 1), 5)] += 1

    # Leeches: words failed repeatedly are where the curriculum is too hard
    leeches = sorted(
        (p for p in progress if (p.get("lapses", 0) or 0) >= 3),
        key=lambda p: -(p.get("lapses", 0) or 0),
    )

    diary_words = sum(len(d.get("words", []) or []) for d in diary)
    notes = 0
    for d in diary:
        by_word = d.get("notesByWordId") or {}
        if isinstance(by_word, dict):
            notes += sum(len(v or []) for v in by_word.values())

    streak_doc = appdata.get("streak", {})
    rank_doc = appdata.get("rank", {})

    # Funnel: which of these milestones the user has actually reached
    funnel = [
        ("Onboarding", by_name.get("onboarding_started", 0)),
        ("Sign-up", by_name.get("sign_up_completed", 0) + by_name.get("sign_in_completed", 0)),
        ("Word viewed", by_name.get("daily_word_viewed", 0)),
        ("Quiz started", by_name.get("quiz_started", 0)),
        ("Quiz completed", by_name.get("quiz_completed", 0)),
        ("Paywall seen", by_name.get("paywall_viewed", 0)),
        ("Purchase", by_name.get("purchase_success", 0)),
    ]

    first_seen = min(times).date().isoformat() if times else None
    last_seen = max(times).date().isoformat() if times else None
    span_days = (max(times).date() - min(times).date()).days + 1 if times else 0

    return {
        "uid": record["uid"],
        "firstSeen": first_seen,
        "lastSeen": last_seen,
        "spanDays": span_days,
        "activeDays": len(active_days),
        "consistency": round(100 * len(active_days) / span_days) if span_days else 0,
        "eventCount": len(events),
        "eventsByName": by_name.most_common(),
        "perDay": per_day,
        "funnel": funnel,
        "quizCount": len(quizzes),
        "quizCorrect": correct,
        "quizTotal": total,
        "accuracy": round(100 * correct / total) if total else None,
        "wordsTracked": len(progress),
        "wordsRetired": retired,
        "mastery": mastery,
        "lapsesTotal": lapses_total,
        "leeches": leeches[:10],
        "diaryDays": len(diary),
        "diaryWords": diary_words,
        "diaryNotes": notes,
        "streak": streak_doc.get("currentStreak"),
        "maxStreak": streak_doc.get("maxStreak"),
        "rank": rank_doc.get("rank"),
        "curriculum": {
            lang: {"slot": c.get("currentSlotIndex"), "completed": c.get("completedCount")}
            for lang, c in curriculum.items()
        },
        "isPremium": any(
            (e.get("params") or {}).get("is_premium") == "true" for e in events
        ),
        "languages": sorted({
            (e.get("params") or {}).get("learning_language")
            for e in events
            if (e.get("params") or {}).get("learning_language")
        }),
    }


# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------

def esc(v: Any) -> str:
    return html.escape("—" if v is None else str(v))


def sparkline(per_day: Counter, days: int = 60) -> str:
    """Inline SVG bar chart of the last N days of activity."""
    if not per_day:
        return '<span class="muted">no activity</span>'
    end = max(dt.date.fromisoformat(d) for d in per_day)
    span = [end - dt.timedelta(days=i) for i in range(days - 1, -1, -1)]
    counts = [per_day.get(d.isoformat(), 0) for d in span]
    peak = max(counts) or 1
    w, h, gap = 4, 34, 1
    bars = []
    for i, c in enumerate(counts):
        bh = max(1, round(h * c / peak)) if c else 1
        cls = "b" if c else "b0"
        bars.append(
            f'<rect class="{cls}" x="{i*(w+gap)}" y="{h-bh}" width="{w}" height="{bh}" rx="1">'
            f'<title>{span[i].isoformat()}: {c} events</title></rect>'
        )
    total_w = days * (w + gap)
    return (
        f'<svg class="spark" viewBox="0 0 {total_w} {h}" width="{total_w}" height="{h}" '
        f'role="img" aria-label="Daily activity, last {days} days">{"".join(bars)}</svg>'
    )


def render(snapshot: dict[str, Any], summaries: list[dict[str, Any]]) -> str:
    pulled = snapshot["pulledAt"][:16].replace("T", " ") + " UTC"
    total_users = len(summaries)
    total_events = sum(s["eventCount"] for s in summaries)

    rows = []
    for s in summaries:
        rows.append(f"""
        <tr>
          <td class="mono">{esc(s['uid'][:10])}…</td>
          <td>{esc(s['firstSeen'])}</td>
          <td>{esc(s['lastSeen'])}</td>
          <td class="num">{esc(s['activeDays'])}<span class="sub">/{esc(s['spanDays'])}d</span></td>
          <td class="num">{esc(s['consistency'])}%</td>
          <td class="num">{esc(s['streak'])}<span class="sub">/{esc(s['maxStreak'])}</span></td>
          <td class="num">{esc(s['wordsTracked'])}</td>
          <td class="num">{esc(s['accuracy']) if s['accuracy'] is not None else '—'}{'%' if s['accuracy'] is not None else ''}</td>
          <td class="num">{esc(s['eventCount'])}</td>
          <td>{'<span class="pill pill-on">premium</span>' if s['isPremium'] else '<span class="pill">free</span>'}</td>
        </tr>""")

    details = []
    for s in summaries:
        funnel_max = max((c for _, c in s["funnel"]), default=0) or 1
        funnel_rows = "".join(
            f'<div class="frow"><span class="flabel">{esc(label)}</span>'
            f'<span class="fbar"><i style="width:{100*count/funnel_max:.1f}%"></i></span>'
            f'<span class="fnum">{esc(count)}</span></div>'
            for label, count in s["funnel"]
        )

        mastery_rows = "".join(
            f'<div class="frow"><span class="flabel">Level {lvl}</span>'
            f'<span class="fbar"><i class="m{lvl}" style="width:{100*s["mastery"].get(lvl,0)/max(s["wordsTracked"],1):.1f}%"></i></span>'
            f'<span class="fnum">{esc(s["mastery"].get(lvl, 0))}</span></div>'
            for lvl in range(1, 6)
        )

        top_events = "".join(
            f"<tr><td>{esc(n)}</td><td class='num'>{esc(c)}</td></tr>"
            for n, c in s["eventsByName"][:14]
        )

        leech_rows = "".join(
            f"<tr><td class='mono'>{esc(p.get('id','')[:8])}…</td>"
            f"<td class='num'>{esc(p.get('lapses'))}</td>"
            f"<td class='num'>{esc(p.get('repetitions'))}</td>"
            f"<td class='num'>{esc(round(p.get('ease', 0) or 0, 2))}</td></tr>"
            for p in s["leeches"]
        ) or "<tr><td colspan='4' class='muted'>No word failed 3+ times — nothing is stuck.</td></tr>"

        langs = ", ".join(s["languages"]) or "—"
        curric = ", ".join(
            f"{lang}: slot {c['slot']} ({c['completed']} done)"
            for lang, c in s["curriculum"].items()
        ) or "—"

        details.append(f"""
        <section class="user">
          <header class="uhead">
            <h3 class="mono">{esc(s['uid'])}</h3>
            <p class="meta">{esc(s['firstSeen'])} → {esc(s['lastSeen'])} ·
               {esc(s['activeDays'])} active days of {esc(s['spanDays'])} ·
               {esc(langs)} · {esc(curric)}</p>
          </header>

          <div class="sparkwrap">
            <span class="caption">Daily events, last 60 days</span>
            {sparkline(s['perDay'])}
          </div>

          <div class="grid">
            <div class="card">
              <h4>Funnel</h4>
              {funnel_rows}
            </div>
            <div class="card">
              <h4>Mastery ladder <span class="sub">{esc(s['wordsTracked'])} words, {esc(s['wordsRetired'])} retired</span></h4>
              {mastery_rows}
            </div>
            <div class="card">
              <h4>Quizzes</h4>
              <dl class="kv">
                <dt>Completed</dt><dd>{esc(s['quizCount'])}</dd>
                <dt>Questions</dt><dd>{esc(s['quizTotal'])}</dd>
                <dt>Accuracy</dt><dd>{esc(s['accuracy']) if s['accuracy'] is not None else '—'}{'%' if s['accuracy'] is not None else ''}</dd>
                <dt>Total lapses</dt><dd>{esc(s['lapsesTotal'])}</dd>
              </dl>
              <h4>Diary</h4>
              <dl class="kv">
                <dt>Days written</dt><dd>{esc(s['diaryDays'])}</dd>
                <dt>Words saved</dt><dd>{esc(s['diaryWords'])}</dd>
                <dt>Own sentences</dt><dd>{esc(s['diaryNotes'])}</dd>
              </dl>
            </div>
            <div class="card">
              <h4>Top events</h4>
              <div class="scroll"><table class="mini">{top_events}</table></div>
            </div>
          </div>

          <div class="card wide">
            <h4>Stuck words <span class="sub">3+ failures — where the curriculum is too hard</span></h4>
            <div class="scroll">
              <table class="mini">
                <thead><tr><th>word id</th><th class="num">lapses</th><th class="num">reps</th><th class="num">ease</th></tr></thead>
                <tbody>{leech_rows}</tbody>
              </table>
            </div>
          </div>
        </section>""")

    return f"""<meta charset="utf-8">
<title>Maia User Behaviour</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  :root {{
    --bg: #f7f8fa;
    --panel: #ffffff;
    --line: #e2e5ea;
    --ink: #14161c;
    --ink-2: #4b5162;
    --muted: #878ea1;
    --accent: #2f6df6;
    --accent-soft: #e6edfe;
    --good: #1aad50;
    --warn: #d98613;
    --bad: #d1443b;
    --m1: #f2a113; --m2: #b8c81a; --m3: #75d119; --m4: #24bf19; --m5: #1aad50;
  }}
  @media (prefers-color-scheme: dark) {{
    :root:not([data-theme="light"]) {{
      --bg: #0f1116;
      --panel: #171a21;
      --line: #262b36;
      --ink: #eef0f4;
      --ink-2: #b3b9c7;
      --muted: #7d8494;
      --accent: #6c9bff;
      --accent-soft: #1d2740;
    }}
  }}
  :root[data-theme="dark"] {{
    --bg: #0f1116;
    --panel: #171a21;
    --line: #262b36;
    --ink: #eef0f4;
    --ink-2: #b3b9c7;
    --muted: #7d8494;
    --accent: #6c9bff;
    --accent-soft: #1d2740;
  }}

  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; background: var(--bg); color: var(--ink);
    font-family: Inter, system-ui, sans-serif;
    padding: clamp(20px, 4vw, 44px);
    line-height: 1.5;
  }}
  .wrap {{ max-width: 1180px; margin: 0 auto; }}
  .mono {{ font-family: 'IBM Plex Mono', ui-monospace, monospace; }}
  .num {{ text-align: right; font-variant-numeric: tabular-nums; }}
  .muted {{ color: var(--muted); }}
  .sub {{ color: var(--muted); font-weight: 400; font-size: 0.84em; }}

  header.top {{ margin-bottom: 28px; }}
  .eyebrow {{
    font-size: 0.72rem; font-weight: 600; letter-spacing: 0.12em;
    text-transform: uppercase; color: var(--muted); margin: 0 0 6px;
  }}
  h1 {{ font-size: clamp(1.5rem, 3vw, 1.95rem); margin: 0 0 8px; letter-spacing: -0.02em; }}
  .top p {{ margin: 0; color: var(--ink-2); }}

  .totals {{ display: flex; flex-wrap: wrap; gap: 10px; margin: 20px 0 30px; }}
  .tot {{
    background: var(--panel); border: 1px solid var(--line);
    border-radius: 10px; padding: 12px 16px; min-width: 128px;
  }}
  .tot b {{ display: block; font-size: 1.5rem; letter-spacing: -0.02em; font-variant-numeric: tabular-nums; }}
  .tot span {{ font-size: 0.78rem; color: var(--muted); }}

  h2 {{ font-size: 1.05rem; margin: 34px 0 12px; letter-spacing: -0.01em; }}

  .scroll {{ overflow-x: auto; }}
  table {{ border-collapse: collapse; width: 100%; font-size: 0.88rem; }}
  th, td {{ padding: 9px 12px; border-bottom: 1px solid var(--line); text-align: left; white-space: nowrap; }}
  thead th {{
    font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.06em;
    color: var(--muted); font-weight: 600; background: var(--panel);
  }}
  table.main {{ background: var(--panel); border: 1px solid var(--line); border-radius: 10px; overflow: hidden; }}
  table.mini td, table.mini th {{ padding: 6px 10px; font-size: 0.83rem; }}

  .pill {{
    font-size: 0.72rem; padding: 2px 8px; border-radius: 999px;
    border: 1px solid var(--line); color: var(--muted);
  }}
  .pill-on {{ background: var(--accent-soft); color: var(--accent); border-color: transparent; font-weight: 600; }}

  section.user {{
    background: var(--panel); border: 1px solid var(--line);
    border-radius: 12px; padding: 20px; margin-bottom: 18px;
  }}
  .uhead h3 {{ margin: 0 0 4px; font-size: 0.94rem; font-weight: 600; }}
  .uhead .meta {{ margin: 0; font-size: 0.83rem; color: var(--muted); }}

  .sparkwrap {{ margin: 16px 0 20px; }}
  .caption {{ display: block; font-size: 0.72rem; color: var(--muted); margin-bottom: 6px; }}
  .spark {{ max-width: 100%; height: auto; }}
  .spark .b {{ fill: var(--accent); }}
  .spark .b0 {{ fill: var(--line); }}

  .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 14px; }}
  .card {{ border: 1px solid var(--line); border-radius: 10px; padding: 14px; }}
  .card.wide {{ margin-top: 14px; }}
  .card h4 {{ margin: 0 0 10px; font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.05em; color: var(--muted); }}
  .card h4 + h4 {{ margin-top: 16px; }}

  .frow {{ display: grid; grid-template-columns: 92px 1fr 34px; align-items: center; gap: 8px; margin-bottom: 5px; }}
  .flabel {{ font-size: 0.78rem; color: var(--ink-2); }}
  .fbar {{ background: var(--line); border-radius: 3px; height: 7px; overflow: hidden; }}
  .fbar i {{ display: block; height: 100%; background: var(--accent); border-radius: 3px; }}
  .fbar i.m1 {{ background: var(--m1); }} .fbar i.m2 {{ background: var(--m2); }}
  .fbar i.m3 {{ background: var(--m3); }} .fbar i.m4 {{ background: var(--m4); }}
  .fbar i.m5 {{ background: var(--m5); }}
  .fnum {{ font-size: 0.78rem; text-align: right; font-variant-numeric: tabular-nums; color: var(--ink-2); }}

  dl.kv {{ display: grid; grid-template-columns: 1fr auto; gap: 3px 10px; margin: 0; font-size: 0.83rem; }}
  dl.kv dt {{ color: var(--ink-2); }}
  dl.kv dd {{ margin: 0; text-align: right; font-variant-numeric: tabular-nums; font-weight: 600; }}

  footer {{ margin-top: 34px; padding-top: 16px; border-top: 1px solid var(--line); font-size: 0.8rem; color: var(--muted); }}
</style>

<div class="wrap">
  <header class="top">
    <p class="eyebrow">Firestore snapshot · {esc(PROJECT)}</p>
    <h1>Maia User Behaviour</h1>
    <p>Pulled {esc(pulled)}. Read-only snapshot of every user document and subcollection.</p>
  </header>

  <div class="totals">
    <div class="tot"><b>{total_users}</b><span>users</span></div>
    <div class="tot"><b>{total_events}</b><span>analytics events</span></div>
    <div class="tot"><b>{sum(s['quizCount'] for s in summaries)}</b><span>quizzes taken</span></div>
    <div class="tot"><b>{sum(s['wordsTracked'] for s in summaries)}</b><span>words in review</span></div>
    <div class="tot"><b>{sum(s['diaryNotes'] for s in summaries)}</b><span>sentences written</span></div>
  </div>

  <h2>All users</h2>
  <div class="scroll">
    <table class="main">
      <thead>
        <tr>
          <th>uid</th><th>first seen</th><th>last seen</th>
          <th class="num">active</th><th class="num">consistency</th>
          <th class="num">streak</th><th class="num">words</th>
          <th class="num">accuracy</th><th class="num">events</th><th>plan</th>
        </tr>
      </thead>
      <tbody>{"".join(rows)}</tbody>
    </table>
  </div>

  <h2>Per user</h2>
  {"".join(details)}

  <footer>
    Generated by <span class="mono">analytics/pull_users.py</span>. Consistency = active days ÷ days since first seen.
    Mastery levels follow the SM-2 ladder (1&nbsp;→&nbsp;6&nbsp;→&nbsp;16&nbsp;→&nbsp;42&nbsp;→&nbsp;113 days); level&nbsp;5 words are retired from review.
  </footer>
</div>
"""


# --------------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default="analytics/out", help="output directory")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    token = access_token()
    snapshot = pull_everything(token)
    summaries = [summarize(r) for r in snapshot["users"].values()]
    summaries.sort(key=lambda s: s["lastSeen"] or "", reverse=True)

    stamp = dt.datetime.now().strftime("%Y-%m-%d")
    raw_path = out / f"snapshot-{stamp}.json"
    raw_path.write_text(json.dumps(snapshot, indent=2, ensure_ascii=False))

    report_path = out / "report.html"
    report_path.write_text(render(snapshot, summaries), encoding="utf-8")

    print(f"\nsnapshot -> {raw_path}")
    print(f"report   -> {report_path}")


if __name__ == "__main__":
    main()
