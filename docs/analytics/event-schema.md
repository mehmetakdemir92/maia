# Event schema

All events are logged through `AppAnalytics.log` in the iOS app.

## Automatic dimensions (every event)

| Param | Source | Notes |
|-------|--------|--------|
| `learning_language` | `LearningLanguage.current` (`en` / `de`); word events override from `Word` | User property synced on language change |
| `user_cefr_level` | Settings step via `CEFRLevelMapping` (`A1`…`C2`) | Always the user preference |
| `cefr_level` | Defaults to user preference; **word/quiz events override with word band** when present | Use `user_cefr_level` for cohorting by setting |
| `is_premium` | Synced from `UserManager` | `"true"` / `"false"` |
| `platform` | Always `ios` | |
| `app_version` | CFBundleShortVersionString | |

## User properties (Firebase Analytics)

Synced via `AppAnalytics.syncUserProperties`:

- `learning_language`
- `user_cefr_level`
- `cefr_level` (mirrors user setting)
- `is_premium`

## Core product events

| Event | Extra params |
|-------|----------------|
| `app_open` | — |
| `onboarding_started` | — |
| `sign_in_started` / `sign_in_completed` / `sign_in_failed` | `method`; failed may include `error` |
| `sign_up_started` / `sign_up_completed` / `sign_up_failed` | `method`; failed may include `error` |
| `daily_word_viewed` | `word_id`; `learning_language`; `cefr_level` (word band if known) |
| `quiz_started` | `quiz_mode`, `word_id`, `question_count`, `learning_language`; `cefr_level` (word band if known) |
| `quiz_completed` | same as started + `correct_count` |
| `paywall_viewed` | placement / product context (see call sites) |
| `paywall_plan_selected` | plan fields |
| `paywall_cta_tapped` | plan fields |
| `purchase_started` / `purchase_success` / `purchase_failed` | `product_id`, `plan_type` |
| `trial_started` | `product_id`, `plan_type` |
| `restore_purchase_*` | optional `error` on failure |
| `ad_banner_impression` / `ad_banner_failed` | `placement` |
| `ad_interstitial_shown` / `ad_rewarded_video_shown` | `placement` |

## BigQuery tips

Firebase exports events to `events_YYYYMMDD` (and sometimes `events_intraday_YYYYMMDD`).

Event params live in a repeated RECORD `event_params`. Helper pattern:

```sql
(SELECT value.string_value
 FROM UNNEST(event_params)
 WHERE key = 'learning_language') AS learning_language
```

Replace `` `PROJECT.DATASET` `` in query files with your linked Analytics dataset (see `bigquery-setup.md`).
