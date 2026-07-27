-- Learning language × user CEFR distribution (from daily_word_viewed).
-- Replace YOUR_PROJECT and analytics_XXXXXXX before running.

DECLARE target_date DATE DEFAULT CURRENT_DATE();

WITH views AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'learning_language') AS learning_language,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'user_cefr_level') AS user_cefr_level,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'cefr_level') AS word_cefr_level
  FROM `YOUR_PROJECT.analytics_XXXXXXX.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', target_date)
    AND event_name = 'daily_word_viewed'
)

SELECT
  learning_language,
  user_cefr_level,
  word_cefr_level,
  COUNT(*) AS word_views,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM views
GROUP BY learning_language, user_cefr_level, word_cefr_level
ORDER BY word_views DESC;
