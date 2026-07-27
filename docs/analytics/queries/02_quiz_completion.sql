-- Quiz start → completion rate for a single day (or expand TABLE_SUFFIX range).
-- Replace YOUR_PROJECT and analytics_XXXXXXX before running.

DECLARE target_date DATE DEFAULT CURRENT_DATE();

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'learning_language') AS learning_language,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'user_cefr_level') AS user_cefr_level
  FROM `YOUR_PROJECT.analytics_XXXXXXX.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', target_date)
    AND event_name IN ('quiz_started', 'quiz_completed')
)

SELECT
  learning_language,
  user_cefr_level,
  COUNTIF(event_name = 'quiz_started') AS quiz_started,
  COUNTIF(event_name = 'quiz_completed') AS quiz_completed,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'quiz_completed'),
    COUNTIF(event_name = 'quiz_started')
  ) AS completion_rate
FROM events
GROUP BY learning_language, user_cefr_level
ORDER BY quiz_started DESC;
