-- ============================================================
-- Layer 3: Match Shadow Scorelines
-- ============================================================
-- SQL concepts: CTE, FILTER(WHERE), CASE WHEN,
--               multi-table JOIN, result classification

--psql -U pl_xg_user -d pl_xg -h localhost \
--     -f sql/queries/match_shadow.sql


-- ── Step 1: aggregate xG per team per match ──────────────────
WITH match_xg AS (
    SELECT
        sh.match_id,
        -- home xG: sum only shots taken by the home team
        ROUND(SUM(sh.xg_value)
            FILTER (WHERE sh.team_id = m.home_team_id), 2)  AS home_xg,
        -- away xG: sum only shots taken by the away team
        ROUND(SUM(sh.xg_value)
            FILTER (WHERE sh.team_id = m.away_team_id), 2)  AS away_xg,
        -- home goals from shots
        SUM(sh.is_goal::int)
            FILTER (WHERE sh.team_id = m.home_team_id)      AS home_shot_goals,
        -- away goals from shots
        SUM(sh.is_goal::int)
            FILTER (WHERE sh.team_id = m.away_team_id)      AS away_shot_goals
    FROM shots sh
    JOIN matches m ON sh.match_id = m.match_id
    GROUP BY sh.match_id, m.home_team_id, m.away_team_id
),

-- ── Step 2: classify each match result ───────────────────────
classified AS (
    SELECT
        m.match_id,
        ht.team_name                                        AS home_team,
        at.team_name                                        AS away_team,
        s.season_name,
        m.match_date::date                                  AS match_date,
        -- actual result
        m.home_goals,
        m.away_goals,
        -- xG result (from match table — includes own goals)
        ROUND(m.home_xg, 2)                                 AS home_xg,
        ROUND(m.away_xg, 2)                                 AS away_xg,
        -- actual winner
        CASE
            WHEN m.home_goals > m.away_goals THEN 'home'
            WHEN m.away_goals > m.home_goals THEN 'away'
            ELSE                                  'draw'
        END                                                 AS actual_winner,
        -- xG winner
        CASE
            WHEN m.home_xg > m.away_xg           THEN 'home'
            WHEN m.away_xg > m.home_xg           THEN 'away'
            ELSE                                  'draw'
        END                                                 AS xg_winner,
        -- verdict
        CASE
            WHEN m.home_goals > m.away_goals
                 AND m.home_xg < m.away_xg        THEN 'home_lucky_win'
            WHEN m.away_goals > m.home_goals
                 AND m.away_xg < m.home_xg        THEN 'away_lucky_win'
            WHEN m.home_goals = m.away_goals
                 AND ABS(m.home_xg - m.away_xg) > 1
                                                  THEN 'misleading_draw'
            WHEN m.home_goals > m.away_goals
                 AND m.home_xg > m.away_xg        THEN 'deserved_home_win'
            WHEN m.away_goals > m.home_goals
                 AND m.away_xg > m.home_xg        THEN 'deserved_away_win'
            ELSE                                  'draw_matched_xg'
        END                                                 AS verdict
    FROM matches m
    JOIN match_xg mx ON m.match_id  = mx.match_id
    JOIN teams   ht  ON m.home_team_id = ht.team_id
    JOIN teams   at  ON m.away_team_id = at.team_id
    JOIN seasons s   ON m.season_id  = s.season_id
)

SELECT * FROM classified
ORDER BY match_date
LIMIT 20;


-- how many lucky wins per team across all seasons?
WITH match_xg AS (
    SELECT
        sh.match_id,
        ROUND(SUM(sh.xg_value)
            FILTER (WHERE sh.team_id = m.home_team_id), 2)  AS home_xg,
        ROUND(SUM(sh.xg_value)
            FILTER (WHERE sh.team_id = m.away_team_id), 2)  AS away_xg
    FROM shots sh
    JOIN matches m ON sh.match_id = m.match_id
    GROUP BY sh.match_id, m.home_team_id, m.away_team_id
),
verdicts AS (
    SELECT
        m.match_id,
        m.home_team_id,
        m.away_team_id,
        CASE
            WHEN m.home_goals > m.away_goals
                 AND mx.home_xg < mx.away_xg  THEN m.home_team_id
            WHEN m.away_goals > m.home_goals
                 AND mx.away_xg < mx.home_xg  THEN m.away_team_id
        END                                   AS lucky_winner_id
    FROM matches m
    JOIN match_xg mx ON m.match_id = mx.match_id
)
SELECT
    t.team_name,
    COUNT(*)            AS lucky_wins
FROM verdicts v
JOIN teams t ON v.lucky_winner_id = t.team_id
WHERE v.lucky_winner_id IS NOT NULL
GROUP BY t.team_name
ORDER BY lucky_wins DESC
LIMIT 15;


-- verdict distribution across all matches
WITH match_xg AS (
    SELECT
        sh.match_id,
        ROUND(SUM(sh.xg_value)
            FILTER (WHERE sh.team_id = m.home_team_id), 2)  AS home_xg,
        ROUND(SUM(sh.xg_value)
            FILTER (WHERE sh.team_id = m.away_team_id), 2)  AS away_xg
    FROM shots sh
    JOIN matches m ON sh.match_id = m.match_id
    GROUP BY sh.match_id, m.home_team_id, m.away_team_id
)
SELECT
    CASE
        WHEN m.home_goals > m.away_goals
             AND mx.home_xg < mx.away_xg    THEN 'home_lucky_win'
        WHEN m.away_goals > m.home_goals
             AND mx.away_xg < mx.home_xg    THEN 'away_lucky_win'
        WHEN m.home_goals = m.away_goals
             AND ABS(mx.home_xg - mx.away_xg) > 1
                                            THEN 'misleading_draw'
        WHEN m.home_goals > m.away_goals
             AND mx.home_xg > mx.away_xg    THEN 'deserved_home_win'
        WHEN m.away_goals > m.home_goals
             AND mx.away_xg > mx.home_xg    THEN 'deserved_away_win'
        ELSE                                     'draw_matched_xg'
    END                                     AS verdict,
    COUNT(*)                                AS matches,
    ROUND(COUNT(*)::numeric / 1140 * 100, 1) AS pct
FROM matches m
JOIN match_xg mx ON m.match_id = mx.match_id
GROUP BY verdict
ORDER BY matches DESC;