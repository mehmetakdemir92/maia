-- Paywall funnel: viewed → CTA → purchase success (same calendar day, distinct users).
-- Replace YOUR_PROJECT and analytics_XXXXXXX before running.

DECLARE target_date DATE DEFAULT CURRENT_DATE();

WITH funnel AS (
  SELECT
    user_pseudo_id,
    event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'learning_language') AS learning_language,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'is_premium') AS is_premium
  FROM `YOUR_PROJECT.analytics_XXXXXXX.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', target_date)
    AND event_name IN (
      'paywall_viewed',
      'paywall_cta_tapped',
      'purchase_started',
      'purchase_success'
    )
)

SELECT
  learning_language,
  COUNT(DISTINCT IF(event_name = 'paywall_viewed', user_pseudo_id, NULL)) AS paywall_viewed_users,
  COUNT(DISTINCT IF(event_name = 'paywall_cta_tapped', user_pseudo_id, NULL)) AS cta_users,
  COUNT(DISTINCT IF(event_name = 'purchase_started', user_pseudo_id, NULL)) AS purchase_started_users,
  COUNT(DISTINCT IF(event_name = 'purchase_success', user_pseudo_id, NULL)) AS purchase_success_users,
  SAFE_DIVIDE(
    COUNT(DISTINCT IF(event_name = 'purchase_success', user_pseudo_id, NULL)),
    COUNT(DISTINCT IF(event_name = 'paywall_viewed', user_pseudo_id, NULL))
  ) AS view_to_purchase_rate
FROM funnel
GROUP BY learning_language
ORDER BY paywall_viewed_users DESC;
