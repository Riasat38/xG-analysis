-- ============================================================
-- PL xG Analytics — DDL Schema
-- Run as pl_xg_user against pl_xg database
-- psql -U pl_xg_user -d pl_xg -f sql/schema/001_create_tables.sql
-- ============================================================

-- ── SEASONS ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS seasons (
    season_id   SERIAL          PRIMARY KEY,
    season_name VARCHAR(10)     NOT NULL,
    league      VARCHAR(50)     NOT NULL,
    country     VARCHAR(50)     NOT NULL,
    start_date  DATE,
    end_date    DATE,
    UNIQUE (season_name, league)
);

-- ── TEAMS ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS teams (
    team_id     INTEGER         PRIMARY KEY,  -- Understat's own ID
    team_name   VARCHAR(100)    NOT NULL,
    short_name  VARCHAR(10),
    country     VARCHAR(50),
    league      VARCHAR(50)
);

-- ── PLAYERS ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS players (
    player_id   INTEGER         PRIMARY KEY,  -- Understat's own ID
    full_name   VARCHAR(100)    NOT NULL,
    position    VARCHAR(10),                  -- FW, MF, DF, GK, Unknown
    nationality VARCHAR(50)
);

-- ── MATCHES ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS matches (
    match_id        INTEGER         PRIMARY KEY,  -- Understat's own ID
    season_id       INTEGER         NOT NULL REFERENCES seasons(season_id),
    home_team_id    INTEGER         NOT NULL REFERENCES teams(team_id),
    away_team_id    INTEGER         NOT NULL REFERENCES teams(team_id),
    match_date      TIMESTAMP,
    gw              INTEGER,                      -- nullable, derive later
    home_goals      INTEGER,
    away_goals      INTEGER,
    home_xg         NUMERIC(6,4),
    away_xg         NUMERIC(6,4),
    forecast_w      NUMERIC(5,4),
    forecast_d      NUMERIC(5,4),
    forecast_l      NUMERIC(5,4)
);

-- ── SHOTS ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS shots (
    shot_id         INTEGER         PRIMARY KEY,  -- Understat's own ID
    match_id        INTEGER         NOT NULL REFERENCES matches(match_id),
    player_id       INTEGER         NOT NULL REFERENCES players(player_id),
    team_id         INTEGER         NOT NULL REFERENCES teams(team_id),
    xg_value        NUMERIC(6,4)    NOT NULL,
    is_goal         BOOLEAN         NOT NULL,
    result          VARCHAR(20),                  -- MissedShots, SavedShot, etc.
    situation       VARCHAR(30),                  -- OpenPlay, FromCorner, etc.
    body_part       VARCHAR(20),                  -- RightFoot, LeftFoot, Head
    minute          INTEGER,
    x_coord         NUMERIC(5,4),
    y_coord         NUMERIC(5,4),
    player_assisted VARCHAR(100),
    last_action     VARCHAR(30)
);

-- ── TEAM MATCH STATS ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS team_match_stats (
    stat_id         SERIAL          PRIMARY KEY,
    match_id        INTEGER         NOT NULL REFERENCES matches(match_id),
    team_id         INTEGER         NOT NULL REFERENCES teams(team_id),
    h_a             CHAR(1)         NOT NULL,     -- 'h' or 'a'
    xg_for          NUMERIC(6,4),
    xg_against      NUMERIC(6,4),
    npxg_for        NUMERIC(6,4),
    npxg_against    NUMERIC(6,4),
    ppda_att        INTEGER,
    ppda_def        INTEGER,
    ppda_allowed_att INTEGER,
    ppda_allowed_def INTEGER,
    deep            INTEGER,
    deep_allowed    INTEGER,
    xpts            NUMERIC(5,4),
    result          CHAR(1),                      -- 'w', 'd', 'l'
    scored          INTEGER,
    missed          INTEGER
);