-- ============================================================
-- Layer 2: Player Finishing Quality Ranking
-- ============================================================
-- SQL concepts: CTE, RANK() window function, HAVING,
--               NULLIF, ROUND, GROUP BY filtering
-- psql -U pl_xg_user -d pl_xg -h localhost \
--     -f sql/queries/player_finishing.sql

-- ── Step 1: aggregate per player per season ──────────────────
WITH player_season_stats AS (
    SELECT
        p.player_id,
        p.full_name,
        p.position,
        t.team_name,
        s.season_name,
        COUNT(sh.shot_id)                                    AS shots,
        SUM(sh.is_goal::int)                                 AS goals,
        ROUND(SUM(sh.xg_value), 2)                           AS xg,
        ROUND(SUM(sh.is_goal::int) - SUM(sh.xg_value), 2)   AS xg_delta,
        ROUND(
            SUM(sh.is_goal::int)::numeric
            / NULLIF(SUM(sh.xg_value), 0)
        , 3)                                                 AS finishing_ratio
    FROM shots sh
    JOIN players p ON sh.player_id = p.player_id
    JOIN teams   t ON sh.team_id   = t.team_id
    JOIN matches m ON sh.match_id  = m.match_id
    JOIN seasons s ON m.season_id  = s.season_id
    GROUP BY
        p.player_id, p.full_name, p.position,
        t.team_name, s.season_name
    HAVING COUNT(sh.shot_id) >= 20   -- minimum shots filter
),

-- ── Step 2: rank within each season ──────────────────────────
ranked AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY season_name
            ORDER BY xg_delta DESC
        )                                                    AS overperformance_rank,
        RANK() OVER (
            PARTITION BY season_name
            ORDER BY xg_delta ASC
        )                                                    AS underperformance_rank
    FROM player_season_stats
)

SELECT
    season_name,
    overperformance_rank            AS rank,
    full_name,
    team_name,
    position,
    shots,
    goals,
    xg,
    xg_delta,
    finishing_ratio
FROM ranked
WHERE overperformance_rank <= 10
ORDER BY season_name, overperformance_rank;