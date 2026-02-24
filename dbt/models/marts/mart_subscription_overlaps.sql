-- mart_subscription_overlaps.sql
-- Subscription overlap detection for data quality monitoring

{{ config(materialized='table') }}

SELECT
    s1.account_id,
    s1.subscription_id                                     AS subscription_id_1,
    s2.subscription_id                                     AS subscription_id_2,
    s1.status                                              AS status_1,
    s2.status                                              AS status_2,
    GREATEST(s1.started_at, s2.started_at)                 AS overlap_start,
    LEAST(
        COALESCE(s1.ended_at, NOW()),
        COALESCE(s2.ended_at, NOW())
    )                                                      AS overlap_end,
    LEAST(
        COALESCE(s1.ended_at, NOW()),
        COALESCE(s2.ended_at, NOW())
    ) - GREATEST(s1.started_at, s2.started_at)            AS overlap_duration

FROM {{ ref('stg_subscriptions') }} s1
JOIN {{ ref('stg_subscriptions') }} s2
  ON  s1.account_id       = s2.account_id
 AND  s1.subscription_id  < s2.subscription_id

WHERE s1.started_at < COALESCE(s2.ended_at, NOW())
  AND s2.started_at < COALESCE(s1.ended_at, NOW())
  AND GREATEST(s1.started_at, s2.started_at)
    < LEAST(COALESCE(s1.ended_at, NOW()), COALESCE(s2.ended_at, NOW()))

ORDER BY s1.account_id, overlap_start
