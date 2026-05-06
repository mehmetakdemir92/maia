# Maia Functions Runbook

## Daily Words Model

- Firestore document key: `dailyWords/{yyyy-MM-dd}_l{1..11}`
- Each document represents one day + one CEFR step level bucket.
- `ensureDailyWords` now requires `userLevel`.
- Scheduled job pre-generates all 11 levels every day.

## Callable APIs

- `ensureDailyWords`
  - Auth required.
  - Input: `{ date?: string, category?: string, userLevel: number }`
  - `date` must match server day (`Europe/Istanbul`) when provided.

- `regenerateDailyWords`
  - Auth + admin custom claim required (`context.auth.token.admin === true`).
  - Input: `{ date?: string, category?: string, userLevel: number, forceRegenerate?: boolean }`
  - Use for backfill, repair, or manual regeneration.

## Secrets / Local Dev

- Do **not** commit `functions/.env` (it is gitignored).
- Use `functions/.env.example` as a template for local-only values.
- Production key must live in Secret Manager:

```bash
firebase functions:secrets:set GEMINI_API_KEY
```

Optional model override (comma-separated list, tried in order):

```bash
firebase functions:secrets:set GEMINI_TEXT_MODELS
# value example:
# gemini-2.5-flash,gemini-2.5-flash-lite,gemini-1.5-flash-latest
```

If a key was ever committed to git/chat, rotate it in AI Studio and update the secret.

## Admin Claim Setup

Set admin role for a trusted operator user:

```bash
node -e "const admin=require('firebase-admin');admin.initializeApp();admin.auth().setCustomUserClaims('<UID>',{admin:true}).then(()=>console.log('ok')).catch(console.error)"
```

## Operational Commands

- Deploy functions:

```bash
npm --prefix functions run deploy
```

- Trigger same-day generation from client (normal path): call `ensureDailyWords`.
- Trigger manual regeneration (ops path): call `regenerateDailyWords` with `forceRegenerate: true`.

## Logging / Monitoring

Structured logs are emitted as JSON with these fields:

- `event`: `daily_words_written` or `daily_words_skipped`
- `date`
- `level`
- `source` (`scheduled_daily_words`, `callable_ensureDailyWords`, `admin_regenerate`)
- `status`
- `poolRemaining`
- `fallbackUsed`
- `lemmas` (on successful write)

Filter example in Cloud Logging:

- `jsonPayload.event="daily_words_written"`
- `jsonPayload.level=5`

## Rollout Notes

- Migration phase supports old level-agnostic `dailyWords/{yyyy-MM-dd}` read only for level 1 on iOS.
- New writes always target `dailyWords/{yyyy-MM-dd}_l{level}`.
- After migration window, remove legacy read fallback from iOS.
