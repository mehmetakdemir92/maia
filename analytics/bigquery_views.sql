-- Looker Studio-facing views over the GA4 -> BigQuery export.
--
-- Apply with:
--   bq query --project_id=vocability-6f0f3 --use_legacy_sql=false < analytics/bigquery_views.sql
--
-- Then in Looker Studio: Create -> Data source -> BigQuery -> vocability-6f0f3
-- -> analytics_521222563 -> pick one of these views. Point charts at
-- v_user_summary for the per-user table and v_events / v_user_daily for trends.
--
-- Cost: these are views, not tables — they store nothing and are billed only
-- when queried, against BigQuery's 1 TiB/month free tier. At this data size a
-- full dashboard refresh is a rounding error.

-- ---------------------------------------------------------------------------
-- v_events — one flat row per event, with the app's custom params pulled out
-- of GA4's event_params array so Looker Studio can use them as plain fields.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `vocability-6f0f3.analytics_521222563.v_events` AS
WITH src AS (
  SELECT
    *,
    REGEXP_REPLACE(_TABLE_SUFFIX, '^intraday_', '') AS suffix_date,
    STARTS_WITH(_TABLE_SUFFIX, 'intraday_')         AS is_intraday
  FROM `vocability-6f0f3.analytics_521222563.events_*`
),
-- GA4 normally deletes an intraday table once its daily table lands, but that
-- cleanup does not always happen (ours still holds a stale intraday_20260728
-- from when the export broke). Prefer the daily table for a date and fall back
-- to intraday only for dates that have no daily table, so nothing is counted
-- twice and today's partial data still shows up.
finalized AS (
  SELECT DISTINCT suffix_date FROM src WHERE NOT is_intraday
)
SELECT
  PARSE_DATE('%Y%m%d', event_date)                       AS event_date,
  TIMESTAMP_MICROS(event_timestamp)                      AS event_ts,
  event_name,

  user_pseudo_id,                                        -- per-install id
  user_id                                                AS firebase_uid,  -- set from AppAnalytics; null before that shipped
  COALESCE(user_id, user_pseudo_id)                      AS person_key,    -- use this to count people

  -- App dimensions (AppAnalyticsParam.*)
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'learning_language')  AS learning_language,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'cefr_level')         AS cefr_level,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'user_cefr_level')    AS user_cefr_level,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'is_premium') = 'true' AS is_premium,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'platform')           AS platform,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'app_version')        AS app_version,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'word_id')            AS word_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'quiz_mode')          AS quiz_mode,

  -- Numeric params arrive as strings from the app, so cast defensively.
  SAFE_CAST((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'correct_count')  AS INT64) AS correct_count,
  SAFE_CAST((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'question_count') AS INT64) AS question_count,
  SAFE_CAST((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'word_count')     AS INT64) AS word_count,

  device.operating_system_version AS os_version,
  device.mobile_model_name        AS device_model,
  geo.country                     AS country,
  is_intraday
FROM src
WHERE NOT is_intraday
   OR suffix_date NOT IN (SELECT suffix_date FROM finalized);

-- ---------------------------------------------------------------------------
-- v_user_daily — one row per person per day. Feeds retention / activity charts.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `vocability-6f0f3.analytics_521222563.v_user_daily` AS
SELECT
  person_key,
  ANY_VALUE(firebase_uid)                                     AS firebase_uid,
  event_date,
  COUNT(*)                                                    AS events,
  COUNTIF(event_name = 'daily_word_viewed')                   AS words_viewed,
  COUNTIF(event_name = 'quiz_started')                        AS quizzes_started,
  COUNTIF(event_name = 'quiz_completed')                      AS quizzes_completed,
  COUNTIF(event_name = 'paywall_viewed')                       AS paywall_views,
  COUNTIF(event_name = 'purchase_success')                     AS purchases,
  SUM(IF(event_name = 'quiz_completed', correct_count, 0))     AS correct_answers,
  SUM(IF(event_name = 'quiz_completed', question_count, 0))    AS asked_questions,
  LOGICAL_OR(is_premium)                                       AS was_premium,
  ANY_VALUE(learning_language)                                 AS learning_language,
  ANY_VALUE(app_version)                                       AS app_version
FROM `vocability-6f0f3.analytics_521222563.v_events`
GROUP BY person_key, event_date;

-- ---------------------------------------------------------------------------
-- v_user_summary — one row per person. This is the per-user table to point
-- Looker Studio's main chart at.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `vocability-6f0f3.analytics_521222563.v_user_summary` AS
WITH daily AS (
  SELECT * FROM `vocability-6f0f3.analytics_521222563.v_user_daily`
)
SELECT
  person_key,
  ANY_VALUE(firebase_uid)                        AS firebase_uid,
  MIN(event_date)                                AS first_seen,
  MAX(event_date)                                AS last_seen,
  DATE_DIFF(MAX(event_date), MIN(event_date), DAY) + 1 AS span_days,
  COUNT(DISTINCT event_date)                     AS active_days,
  -- Share of days since first seen on which they opened the app at all.
  ROUND(
    100 * COUNT(DISTINCT event_date)
        / NULLIF(DATE_DIFF(MAX(event_date), MIN(event_date), DAY) + 1, 0)
  )                                              AS consistency_pct,
  DATE_DIFF(CURRENT_DATE(), MAX(event_date), DAY) AS days_since_last_seen,
  SUM(events)                                    AS total_events,
  SUM(words_viewed)                              AS words_viewed,
  SUM(quizzes_started)                           AS quizzes_started,
  SUM(quizzes_completed)                         AS quizzes_completed,
  SAFE_DIVIDE(SUM(quizzes_completed), NULLIF(SUM(quizzes_started), 0)) AS quiz_finish_rate,
  ROUND(100 * SAFE_DIVIDE(SUM(correct_answers), NULLIF(SUM(asked_questions), 0))) AS accuracy_pct,
  SUM(paywall_views)                             AS paywall_views,
  SUM(purchases)                                 AS purchases,
  LOGICAL_OR(was_premium)                        AS is_premium,
  ANY_VALUE(learning_language)                   AS learning_language,
  ANY_VALUE(app_version)                         AS app_version
FROM daily
GROUP BY person_key;

-- ---------------------------------------------------------------------------
-- v_funnel — one row per funnel step, ordered. Drop straight onto a bar chart.
-- Counts people who ever reached the step, not raw event volume.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `vocability-6f0f3.analytics_521222563.v_funnel` AS
WITH reached AS (
  SELECT
    person_key,
    LOGICAL_OR(event_name = 'onboarding_started')  AS onboarding,
    LOGICAL_OR(event_name IN ('sign_up_completed', 'sign_in_completed')) AS signed_in,
    LOGICAL_OR(event_name = 'daily_word_viewed')   AS saw_word,
    LOGICAL_OR(event_name = 'quiz_started')        AS started_quiz,
    LOGICAL_OR(event_name = 'quiz_completed')      AS finished_quiz,
    LOGICAL_OR(event_name = 'paywall_viewed')      AS saw_paywall,
    LOGICAL_OR(event_name = 'purchase_success')    AS purchased
  FROM `vocability-6f0f3.analytics_521222563.v_events`
  GROUP BY person_key
)
SELECT 1 AS step_order, 'Onboarding started' AS step, COUNTIF(onboarding)   AS people FROM reached
UNION ALL SELECT 2, 'Signed in',           COUNTIF(signed_in)    FROM reached
UNION ALL SELECT 3, 'Viewed a word',       COUNTIF(saw_word)     FROM reached
UNION ALL SELECT 4, 'Started a quiz',      COUNTIF(started_quiz) FROM reached
UNION ALL SELECT 5, 'Finished a quiz',     COUNTIF(finished_quiz) FROM reached
UNION ALL SELECT 6, 'Saw the paywall',     COUNTIF(saw_paywall)  FROM reached
UNION ALL SELECT 7, 'Purchased',           COUNTIF(purchased)    FROM reached;
