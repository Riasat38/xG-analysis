-- save as sql/views/team_season_xg.sql

--psql -U pl_xg_user -d pl_xg -h localhost \
--     -f sql/views/v_team_season_xg.sql


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
JOIN teams   t ON sh.team_id   = t.team_id
JOIN matches m ON sh.match_id  = m.match_id
JOIN seasons s ON m.season_id  = s.season_id
GROUP BY t.team_name, s.season_name;