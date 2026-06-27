-- ============================================================
-- PL xG Analytics — Indexes
-- Run after 001_create_tables.sql
-- psql -U pl_xg_user -d pl_xg -h localhost -f sql/schema/002_create_indexes.sql
-- ============================================================

-- ── shots table (most queried, most important) ────────────────

-- FK join: shots → matches (used in every layer)
CREATE INDEX IF NOT EXISTS idx_shots_match_id
    ON shots(match_id);

-- FK join: shots → players (Layer 2)
CREATE INDEX IF NOT EXISTS idx_shots_player_id
    ON shots(player_id);

-- FK join: shots → teams (Layers 1, 3, 5)
CREATE INDEX IF NOT EXISTS idx_shots_team_id
    ON shots(team_id);

-- filter: is_goal used in every SUM(is_goal::int)
CREATE INDEX IF NOT EXISTS idx_shots_is_goal
    ON shots(is_goal);

-- filter: situation used in Layer 4
CREATE INDEX IF NOT EXISTS idx_shots_situation
    ON shots(situation);

-- composite: team + match together (Layer 5 rolling window)
CREATE INDEX IF NOT EXISTS idx_shots_team_match
    ON shots(team_id, match_id);

-- ── matches table ─────────────────────────────────────────────

-- FK join: matches → seasons (every layer)
CREATE INDEX IF NOT EXISTS idx_matches_season_id
    ON matches(season_id);

-- FK join: matches → teams (Layers 1, 3)
CREATE INDEX IF NOT EXISTS idx_matches_home_team_id
    ON matches(home_team_id);

CREATE INDEX IF NOT EXISTS idx_matches_away_team_id
    ON matches(away_team_id);

-- ORDER BY match_date (Layer 5 rolling window)
CREATE INDEX IF NOT EXISTS idx_matches_match_date
    ON matches(match_date);

-- ── team_match_stats table ────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_tms_team_id
    ON team_match_stats(team_id);

CREATE INDEX IF NOT EXISTS idx_tms_match_id
    ON team_match_stats(match_id);