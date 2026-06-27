-- ============================================================
-- Layer 5: Rolling 5-Match xG Form Tracker
-- ============================================================
-- SQL concepts: window functions with frame clauses,
--               PARTITION BY, ORDER BY inside window,
--               ROWS BETWEEN, named WINDOW alias,
--               LAG() for previous match comparison

-- ── Step 1: xG and goals per team per match ──────────────────
WITH team_match_xg AS (
    SELECT
        sh.team_id,
        sh.match_id,
        m.match_date,
        s.season_name,
        -- xG generated this match
        ROUND(SUM(sh.xg_value), 3)       AS match_xg,
        -- actual goals this match
        SUM(sh.is_goal::int)             AS match_goals,
        -- shots taken
        COUNT(sh.shot_id)                AS match_shots
    FROM shots sh
    JOIN matches m ON sh.match_id  = m.match_id
    JOIN seasons s ON m.season_id  = s.season_id
    GROUP BY sh.team_id, sh.match_id, m.match_date, s.season_name
),

-- ── Step 2: add rolling window aggregates ────────────────────
rolling AS (
    SELECT
        t.team_name,
        tmx.season_name,
        tmx.match_date::date                              AS match_date,
        tmx.match_xg,
        tmx.match_goals,
        tmx.match_shots,

        -- rolling 5-match xG (current + 4 previous)
        ROUND(SUM(tmx.match_xg) OVER w5, 3)              AS rolling_5_xg,

        -- rolling 5-match actual goals
        SUM(tmx.match_goals) OVER w5                     AS rolling_5_goals,

        -- rolling 5-match xG delta (goals - xG)
        ROUND(
            SUM(tmx.match_goals) OVER w5
            - SUM(tmx.match_xg)  OVER w5
        , 3)                                             AS rolling_5_xg_delta,

        -- rolling 5-match shot count
        SUM(tmx.match_shots) OVER w5                     AS rolling_5_shots,

        -- previous match xG using LAG
        ROUND(LAG(tmx.match_xg) OVER (
            PARTITION BY tmx.team_id
            ORDER BY tmx.match_date
        ), 3)                                            AS prev_match_xg,

        -- match number within season for this team
        ROW_NUMBER() OVER (
            PARTITION BY tmx.team_id, tmx.season_name
            ORDER BY tmx.match_date
        )                                                AS match_num

    FROM team_match_xg tmx
    JOIN teams t ON tmx.team_id = t.team_id

    -- named window: partition per team, ordered by date, 5-match rolling frame
    WINDOW w5 AS (
        PARTITION BY tmx.team_id
        ORDER BY tmx.match_date
        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    )
)

-- ── Step 3: output — one team, full season ───────────────────
SELECT
    match_num,
    match_date,
    season_name,
    match_xg,
    match_goals,
    rolling_5_xg,
    rolling_5_goals,
    rolling_5_xg_delta,
    prev_match_xg
FROM rolling
WHERE team_name = 'Arsenal'
ORDER BY match_date;

-- which team had the best 5-match rolling xG peak ever?
WITH team_match_xg AS (
    SELECT
        sh.team_id,
        sh.match_id,
        m.match_date,
        s.season_name,
        ROUND(SUM(sh.xg_value), 3)       AS match_xg,
        SUM(sh.is_goal::int)             AS match_goals
    FROM shots sh
    JOIN matches m ON sh.match_id = m.match_id
    JOIN seasons s ON m.season_id = s.season_id
    GROUP BY sh.team_id, sh.match_id, m.match_date, s.season_name
),
rolling AS (
    SELECT
        t.team_name,
        tmx.season_name,
        tmx.match_date::date             AS match_date,
        ROUND(SUM(tmx.match_xg)  OVER w5, 2) AS rolling_5_xg,
        SUM(tmx.match_goals)     OVER w5      AS rolling_5_goals,
        ROW_NUMBER() OVER (
            PARTITION BY tmx.team_id, tmx.season_name
            ORDER BY tmx.match_date
        )                                AS match_num
    FROM team_match_xg tmx
    JOIN teams t ON tmx.team_id = t.team_id
    WINDOW w5 AS (
        PARTITION BY tmx.team_id
        ORDER BY tmx.match_date
        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    )
)
SELECT
    team_name,
    season_name,
    match_date,
    match_num,
    rolling_5_xg,
    rolling_5_goals
FROM rolling
WHERE match_num >= 5        -- need at least 5 matches for a full window
ORDER BY rolling_5_xg DESC
LIMIT 10;

-- find teams whose form collapsed (biggest drop in rolling xG)
-- compare peak rolling_5_xg vs trough rolling_5_xg per team per season
WITH team_match_xg AS (
    SELECT
        sh.team_id,
        sh.match_id,
        m.match_date,
        s.season_name,
        ROUND(SUM(sh.xg_value), 3)       AS match_xg,
        SUM(sh.is_goal::int)             AS match_goals
    FROM shots sh
    JOIN matches m ON sh.match_id = m.match_id
    JOIN seasons s ON m.season_id = s.season_id
    GROUP BY sh.team_id, sh.match_id, m.match_date, s.season_name
),
rolling AS (
    SELECT
        t.team_name,
        tmx.season_name,
        ROUND(SUM(tmx.match_xg) OVER w5, 2) AS rolling_5_xg,
        ROW_NUMBER() OVER (
            PARTITION BY tmx.team_id, tmx.season_name
            ORDER BY tmx.match_date
        )                                AS match_num
    FROM team_match_xg tmx
    JOIN teams t ON tmx.team_id = t.team_id
    WINDOW w5 AS (
        PARTITION BY tmx.team_id
        ORDER BY tmx.match_date
        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    )
)
SELECT
    team_name,
    season_name,
    ROUND(MAX(rolling_5_xg), 2)          AS peak_rolling_xg,
    ROUND(MIN(rolling_5_xg), 2)          AS trough_rolling_xg,
    ROUND(MAX(rolling_5_xg)
        - MIN(rolling_5_xg), 2)          AS xg_volatility
FROM rolling
WHERE match_num >= 5
GROUP BY team_name, season_name
ORDER BY xg_volatility DESC
LIMIT 15;