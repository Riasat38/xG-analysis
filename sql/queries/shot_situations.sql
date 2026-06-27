-- ============================================================
-- Layer 4: Shot Situation & Body Part Breakdown
-- ============================================================
-- SQL concepts: CASE WHEN for derived categories,
--               HAVING for post-aggregation filtering,
--               multiple GROUP BY dimensions, AVG, ROUND

--psql -U pl_xg_user -d pl_xg -h localhost \
--     -f sql/queries/shot_situations.sql


-- ── Part A: situation × body part breakdown ──────────────────
SELECT
    situation,
    body_part,
    COUNT(*)                                                 AS shots,
    SUM(is_goal::int)                                        AS goals,
    ROUND(AVG(xg_value), 4)                                  AS avg_xg_per_shot,
    ROUND(SUM(is_goal::int)::numeric / COUNT(*), 4)          AS actual_conv_rate,
    ROUND(AVG(xg_value) * 100, 2)                            AS model_conv_pct,
    ROUND(SUM(is_goal::int)::numeric / COUNT(*) * 100, 2)    AS actual_conv_pct,
    -- finishing verdict: are players over/under the model?
    CASE
        WHEN ROUND(SUM(is_goal::int)::numeric / COUNT(*), 4)
             > ROUND(AVG(xg_value), 4)      THEN 'over_expected'
        WHEN ROUND(SUM(is_goal::int)::numeric / COUNT(*), 4)
             < ROUND(AVG(xg_value), 4)      THEN 'under_expected'
        ELSE                                     'on_expected'
    END                                                      AS verdict
FROM shots
GROUP BY situation, body_part
HAVING COUNT(*) >= 50
ORDER BY avg_xg_per_shot DESC;

-- Part B: which situation generates the most dangerous shots?
SELECT
    situation,
    COUNT(*)                                                 AS total_shots,
    ROUND(AVG(xg_value), 4)                                  AS avg_xg,
    SUM(is_goal::int)                                        AS goals,
    ROUND(SUM(is_goal::int)::numeric / COUNT(*) * 100, 2)    AS conversion_pct,
    ROUND(SUM(xg_value), 1)                                  AS total_xg,
    ROUND(COUNT(*)::numeric / (SELECT COUNT(*) FROM shots) * 100, 1) AS shot_share_pct
FROM shots
GROUP BY situation
ORDER BY avg_xg DESC;

-- Part C: penalty analysis — how often do players score vs xG model?
SELECT
    p.full_name,
    COUNT(*)                                                 AS penalties,
    SUM(sh.is_goal::int)                                     AS scored,
    ROUND(SUM(sh.xg_value), 3)                               AS total_xg,
    ROUND(SUM(sh.is_goal::int)::numeric / COUNT(*) * 100, 1) AS conversion_pct,
    ROUND(SUM(sh.is_goal::int) - SUM(sh.xg_value), 2)       AS xg_delta
FROM shots sh
JOIN players p ON sh.player_id = p.player_id
WHERE sh.situation = 'Penalty'
GROUP BY p.full_name
HAVING COUNT(*) >= 3
ORDER BY conversion_pct DESC;

-- Part D: season-over-season shift in shot quality
SELECT
    s.season_name,
    situation,
    COUNT(*)                                                 AS shots,
    ROUND(AVG(xg_value), 4)                                  AS avg_xg,
    ROUND(SUM(is_goal::int)::numeric / COUNT(*) * 100, 2)    AS conversion_pct
FROM shots sh
JOIN matches m ON sh.match_id = m.match_id
JOIN seasons s ON m.season_id = s.season_id
GROUP BY s.season_name, situation
ORDER BY s.season_name, avg_xg DESC;