-- DAU proxy: distinct users with app_open (fallback: daily_word_viewed).
-- Replace YOUR_PROJECT and analytics_XXXXXXX before running.

DECLARE target_date DATE DEFAULT CURRENT_DATE();

WITH base AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_date
  FROM `YOUR_PROJECT.analytics_XXXXXXX.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', target_date)
    AND event_name IN ('app_open', 'daily_word_viewed')
)

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS day,
  COUNT(DISTINCT IF(event_name = 'app_open', user_pseudo_id, NULL)) AS dau_app_open,
  COUNT(DISTINCT IF(event_name = 'daily_word_viewed', user_pseudo_id, NULL)) AS dau_word_viewed
FROM base
GROUP BY day
ORDER BY day;
