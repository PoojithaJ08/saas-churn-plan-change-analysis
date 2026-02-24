-- 05_task4_overlaps.sql
-- Subscription overlap detection.
--
-- Two subscriptions for the same account with overlapping date ranges
-- = data pipeline issue. Can cause churn to be under-counted (active
-- row masks a cancelled one). Surface these so engineering can fix upstream.
-- Ideally this returns 0 rows.

SELECT
    s1.account_id,
    s1.subscription_id                                     AS subscription_id_1,
    s2.subscription_id                                     AS subscription_id_2,
    s1.status                                              AS status_1,
    s2.status                                              AS status_2,
    s1.started_at                                          AS started_1,
    s2.started_at                                          AS started_2,
    GREATEST(s1.started_at, s2.started_at)                 AS overlap_start,
    LEAST(
        COALESCE(s1.ended_at, NOW()),
        COALESCE(s2.ended_at, NOW())
    )                                                      AS overlap_end,
    LEAST(
        COALESCE(s1.ended_at, NOW()),
        COALESCE(s2.ended_at, NOW())
    ) - GREATEST(s1.started_at, s2.started_at)            AS overlap_duration

FROM v_subscriptions_clean s1
JOIN v_subscriptions_clean s2
  ON  s1.account_id       = s2.account_id
 AND  s1.subscription_id  < s2.subscription_id    -- avoid self-joins and duplicates

-- Overlap condition: each starts before the other ends
WHERE s1.started_at < COALESCE(s2.ended_at, NOW())
  AND s2.started_at < COALESCE(s1.ended_at, NOW())
  -- Exclude exact adjacency (plan changes) — zero-duration "overlaps" at a single instant
  AND GREATEST(s1.started_at, s2.started_at)
    < LEAST(COALESCE(s1.ended_at, NOW()), COALESCE(s2.ended_at, NOW()))

ORDER BY s1.account_id, overlap_start;
