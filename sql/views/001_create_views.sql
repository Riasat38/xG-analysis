-- ============================================================
-- PL xG Analytics — Named Views
-- One view per analysis layer
-- psql -U pl_xg_user -d pl_xg -h localhost -f sql/views/001_create_views.sql
-- ============================================================

-- ── View 1: team season xG summary (Layer 1) ─────────────────
CREATE OR REPLACE VIEW v_team_season_xg AS
SELECT
    t.team_name,
    s.season_name,
    COUNT(sh.shot_id)                                        AS total_shots,
    ROUND(SUM(sh.xg_value), 2)                               AS total_xg,
    SUM(sh.is_goal::int)                                     AS actual_goals,
    ROUND(SUM(sh.is_goal::int) - SUM(sh.xg_value), 2)       AS xg_delta,
    ROUND(
        SUM(sh.is_goal::int)::numeric
        / NULLIF(SUM(sh.xg_value), 0)
    , 3)                                                     AS conversion_ratio
FROM shots sh
JOIN teams   t ON sh.team_id  = t.team_id
JOIN matches m ON sh.match_id = m.match_id
JOIN seasons s ON m.season_id = s.season_id
GROUP BY t.team_name, s.season_name;

-- ── View 2: player season finishing quality (Layer 2) ─────────
CREATE OR REPLACE VIEW v_player_finishing AS
WITH base AS (
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
    GROUP BY p.player_id, p.full_name, p.position,
             t.team_name, s.season_name
    HAVING COUNT(sh.shot_id) >= 20
)
SELECT
    *,
    RANK() OVER (
        PARTITION BY season_name
        ORDER BY xg_delta DESC
    ) AS season_rank
FROM base;

-- ── View 3: match shadow scorelines (Layer 3) ─────────────────
CREATE OR REPLACE VIEW v_match_shadow AS
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
    m.match_id,
    ht.team_name                                            AS home_team,
    at.team_name                                            AS away_team,
    s.season_name,
    m.match_date::date                                      AS match_date,
    m.home_goals,
    m.away_goals,
    mx.home_xg,
    mx.away_xg,
    CASE
        WHEN m.home_goals > m.away_goals THEN 'home'
        WHEN m.away_goals > m.home_goals THEN 'away'
        ELSE 'draw'
    END                                                     AS actual_winner,
    CASE
        WHEN mx.home_xg > mx.away_xg     THEN 'home'
        WHEN mx.away_xg > mx.home_xg     THEN 'away'
        ELSE 'draw'
    END                                                     AS xg_winner,
    CASE
        WHEN m.home_goals > m.away_goals
             AND mx.home_xg < mx.away_xg  THEN 'home_lucky_win'
        WHEN m.away_goals > m.home_goals
             AND mx.away_xg < mx.home_xg  THEN 'away_lucky_win'
        WHEN m.home_goals = m.away_goals
             AND ABS(mx.home_xg - mx.away_xg) > 1
                                          THEN 'misleading_draw'
        WHEN m.home_goals > m.away_goals
             AND mx.home_xg > mx.away_xg  THEN 'deserved_home_win'
        WHEN m.away_goals > m.home_goals
             AND mx.away_xg > mx.home_xg  THEN 'deserved_away_win'
        ELSE 'draw_matched_xg'
    END                                                     AS verdict
FROM matches m
JOIN match_xg mx ON m.match_id    = mx.match_id
JOIN teams   ht  ON m.home_team_id = ht.team_id
JOIN teams   at  ON m.away_team_id = at.team_id
JOIN seasons s   ON m.season_id    = s.season_id;

-- ── View 4: shot situation breakdown (Layer 4) ────────────────
CREATE OR REPLACE VIEW v_shot_situations AS
SELECT
    situation,
    body_part,
    s.season_name,
    COUNT(*)                                                 AS shots,
    SUM(sh.is_goal::int)                                     AS goals,
    ROUND(AVG(sh.xg_value), 4)                               AS avg_xg_per_shot,
    ROUND(SUM(sh.is_goal::int)::numeric / COUNT(*), 4)       AS actual_conv_rate,
    CASE
        WHEN ROUND(SUM(sh.is_goal::int)::numeric / COUNT(*), 4)
             > ROUND(AVG(sh.xg_value), 4)   THEN 'over_expected'
        WHEN ROUND(SUM(sh.is_goal::int)::numeric / COUNT(*), 4)
             < ROUND(AVG(sh.xg_value), 4)   THEN 'under_expected'
        ELSE 'on_expected'
    END                                                      AS verdict
FROM shots sh
JOIN matches m ON sh.match_id = m.match_id
JOIN seasons s ON m.season_id = s.season_id
GROUP BY situation, body_part, s.season_name
HAVING COUNT(*) >= 30;

-- ── View 5: team rolling 5-match xG form (Layer 5) ───────────
CREATE OR REPLACE VIEW v_rolling_form AS
WITH team_match_xg AS (
    SELECT
        sh.team_id,
        sh.match_id,
        m.match_date,
        s.season_name,
        ROUND(SUM(sh.xg_value), 3)                           AS match_xg,
        SUM(sh.is_goal::int)                                 AS match_goals,
        COUNT(sh.shot_id)                                    AS match_shots
    FROM shots sh
    JOIN matches m ON sh.match_id = m.match_id
    JOIN seasons s ON m.season_id = s.season_id
    GROUP BY sh.team_id, sh.match_id, m.match_date, s.season_name
)
SELECT
    t.team_name,
    tmx.season_name,
    tmx.match_date::date                                     AS match_date,
    tmx.match_xg,
    tmx.match_goals,
    tmx.match_shots,
    ROUND(SUM(tmx.match_xg)    OVER w5, 3)                  AS rolling_5_xg,
    SUM(tmx.match_goals)       OVER w5                      AS rolling_5_goals,
    ROUND(
        SUM(tmx.match_goals)   OVER w5
      - SUM(tmx.match_xg)      OVER w5
    , 3)                                                     AS rolling_5_xg_delta,
    SUM(tmx.match_shots)       OVER w5                      AS rolling_5_shots,
    ROW_NUMBER() OVER (
        PARTITION BY tmx.team_id, tmx.season_name
        ORDER BY tmx.match_date
    )                                                        AS match_num
FROM team_match_xg tmx
JOIN teams t ON tmx.team_id = t.team_id
WINDOW w5 AS (
    PARTITION BY tmx.team_id
    ORDER BY tmx.match_date
    ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
);