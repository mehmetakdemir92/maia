# BigQuery setup checklist (Faz 0)

Do this once in Google Cloud / Firebase Console. No app code change required.

## 1. Link Analytics → BigQuery

1. Open [Firebase Console](https://console.firebase.google.com/) → your Maia project
2. **Project settings** (gear) → **Integrations** → **BigQuery**
   - Or: Analytics → **BigQuery linking**
3. Click **Link** / **Enable**
4. Choose (or create) a GCP billing project if prompted
5. Enable export for the **Analytics** app / stream (iOS)

Daily export creates tables like:

```text
PROJECT_ID.analytics_XXXXXXXX.events_YYYYMMDD
```

Intraday (optional / streaming) may appear as `events_intraday_YYYYMMDD`.

## 2. Confirm data arrived

Wait **24–48 hours** after first enable (and after the app has sent events).

In [BigQuery console](https://console.cloud.google.com/bigquery):

1. Find dataset `analytics_<property_id>`
2. Open an `events_*` table
3. Preview rows; look for `event_name` = `app_open`, `daily_word_viewed`, etc.

## 3. Run starter SQL

1. Copy a file from [`queries/`](queries/)
2. Replace:
   - `YOUR_PROJECT` → GCP project id
   - `analytics_XXXXXXX` → your dataset id
3. Run in BigQuery SQL workspace

## 4. Looker Studio (Faz 2)

1. [Looker Studio](https://lookerstudio.google.com/) → Create → Data source → BigQuery
2. Pick the `analytics_*` dataset (custom query or table)
3. Build cards: DAU, quiz completion, EN vs DE, paywall conversion

## Cost / safety notes

- Analytics → BigQuery export has a free tier for Firebase; watch BigQuery storage + query bytes as you grow
- Prefer querying a single day or `TABLE_SUFFIX` range instead of `SELECT *` over all history
- Do not put secrets in SQL files; only dataset names
