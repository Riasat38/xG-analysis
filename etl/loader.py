import pandas as pd
import psycopg2
from pathlib import Path
from db import get_connection

PROCESSED = Path("data/processed")

# ── helpers ────────────────────────────────────────────────────────────────

def execute_many(cur, sql, rows):
    """Batch insert with executemany."""
    psycopg2.extras.execute_batch(cur, sql, rows, page_size=500)

def load_seasons(cur):
    df = pd.read_csv(PROCESSED / "seasons_master.csv")
    sql = """
        INSERT INTO seasons (season_name, league, country, start_date, end_date)
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (season_name, league) DO NOTHING
    """
    rows = [
        (r.season_name, r.league, r.country, r.start_date, r.end_date)
        for r in df.itertuples()
    ]
    psycopg2.extras.execute_batch(cur, sql, rows)
    print(f"  seasons       : {len(rows)} rows inserted")

def load_teams(cur):
    df = pd.read_csv(PROCESSED / "teams_master.csv")
    sql = """
        INSERT INTO teams (team_id, team_name, short_name, country, league)
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (team_id) DO NOTHING
    """
    rows = [
        (int(r.team_id), r.team_name, r.short_name, r.country, r.league)
        for r in df.itertuples()
    ]
    psycopg2.extras.execute_batch(cur, sql, rows)
    print(f"  teams         : {len(rows)} rows inserted")

def load_players(cur):
    df = pd.read_csv(PROCESSED / "players_clean.csv")

    # one row per player_id — keep last occurrence across seasons
    df = df.sort_values("season_name").drop_duplicates(
        subset=["player_id"], keep="last"
    )

    sql = """
        INSERT INTO players (player_id, full_name, position)
        VALUES (%s, %s, %s)
        ON CONFLICT (player_id) DO UPDATE
            SET full_name = EXCLUDED.full_name,
                position  = EXCLUDED.position
    """
    rows = [
        (int(r.player_id), r.full_name, r.position)
        for r in df.itertuples()
    ]
    psycopg2.extras.execute_batch(cur, sql, rows)
    print(f"  players       : {len(rows)} rows inserted")

def load_matches(cur):
    df = pd.read_csv(PROCESSED / "matches_clean.csv")

    # get season_id lookup from DB
    cur.execute("SELECT season_id, season_name FROM seasons")
    season_map = {name: sid for sid, name in cur.fetchall()}

    sql = """
        INSERT INTO matches (
            match_id, season_id, home_team_id, away_team_id,
            match_date, home_goals, away_goals,
            home_xg, away_xg,
            forecast_w, forecast_d, forecast_l
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (match_id) DO NOTHING
    """
    rows = []
    skipped = 0
    for r in df.itertuples():
        season_id = season_map.get(r.season_name)
        if season_id is None:
            skipped += 1
            continue
        rows.append((
            int(r.match_id),
            season_id,
            int(r.home_team_id),
            int(r.away_team_id),
            r.match_date,
            int(r.home_goals),
            int(r.away_goals),
            float(r.home_xg),
            float(r.away_xg),
            float(r.forecast_w),
            float(r.forecast_d),
            float(r.forecast_l),
        ))
    psycopg2.extras.execute_batch(cur, sql, rows)
    print(f"  matches       : {len(rows)} rows inserted, {skipped} skipped")

def load_shots(cur):
    df = pd.read_csv(PROCESSED / "shots_clean.csv")

    # build team name → team_id lookup from DB
    cur.execute("SELECT team_id, team_name FROM teams")
    team_map = {name: tid for tid, name in cur.fetchall()}

    sql = """
        INSERT INTO shots (
            shot_id, match_id, player_id, team_id,
            xg_value, is_goal, result,
            situation, body_part,
            minute, x_coord, y_coord,
            player_assisted, last_action
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (shot_id) DO NOTHING
    """
    rows = []
    skipped = 0
    for r in df.itertuples():
        # resolve team_id from h_a flag
        team_name = r.home_team_name if r.h_a == "h" else r.away_team_name
        team_id = team_map.get(team_name)
        if team_id is None:
            skipped += 1
            continue

        # handle nulls for optional fields
        player_assisted = None if pd.isna(r.player_assisted) else str(r.player_assisted)
        last_action     = None if pd.isna(r.lastAction)      else str(r.lastAction)

        rows.append((
            int(r.shot_id),
            int(r.match_id),
            int(r.player_id),
            team_id,
            float(r.xg_value),
            bool(r.is_goal),
            str(r.result),
            str(r.situation),
            str(r.body_part),
            int(r.minute),
            float(r.x_coord),
            float(r.y_coord),
            player_assisted,
            last_action,
        ))

    psycopg2.extras.execute_batch(cur, sql, rows)
    print(f"  shots         : {len(rows)} rows inserted, {skipped} skipped")

def load_team_match_stats(cur):
    df = pd.read_csv(PROCESSED / "team_stats_clean.csv")

    # check what the team identifier column looks like
    print(f"    team_name sample: {df['team_name'].head(5).tolist()}")

    # build match lookup: (date, home_team_id, away_team_id) → match_id
    cur.execute("""
        SELECT match_id, match_date::date, home_team_id, away_team_id
        FROM matches
    """)
    match_map = {}
    for mid, mdate, htid, atid in cur.fetchall():
        match_map[(str(mdate), int(htid), int(atid))] = mid

    # get all valid team_ids from DB
    cur.execute("SELECT team_id FROM teams")
    valid_team_ids = {row[0] for row in cur.fetchall()}

    sql = """
        INSERT INTO team_match_stats (
            match_id, team_id, h_a,
            xg_for, xg_against, npxg_for, npxg_against,
            ppda_att, ppda_def, ppda_allowed_att, ppda_allowed_def,
            deep, deep_allowed,
            xpts, result, scored, missed
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT DO NOTHING
    """
    rows    = []
    skipped = 0
    skip_reasons = {"no_team": 0, "no_match": 0}

    for r in df.itertuples():
        # team_name column actually contains numeric team_id from Understat
        try:
            team_id = int(r.team_name)
        except (ValueError, TypeError):
            skip_reasons["no_team"] += 1
            skipped += 1
            continue

        if team_id not in valid_team_ids:
            skip_reasons["no_team"] += 1
            skipped += 1
            continue

        # normalize match date to YYYY-MM-DD
        match_date_str = str(r.match_date)[:10]

        # find match_id by date + team on correct side
        match_id = None
        for (mdate, htid, atid), mid in match_map.items():
            if mdate == match_date_str and (
                (r.h_a == "h" and htid == team_id) or
                (r.h_a == "a" and atid == team_id)
            ):
                match_id = mid
                break

        if match_id is None:
            skip_reasons["no_match"] += 1
            skipped += 1
            continue

        rows.append((
            match_id, team_id, str(r.h_a),
            float(r.xG),   float(r.xGA),
            float(r.npxG), float(r.npxGA),
            int(r.ppda_att),         int(r.ppda_def),
            int(r.ppda_allowed_att), int(r.ppda_allowed_def),
            int(r.deep),   int(r.deep_allowed),
            float(r.xpts), str(r.result),
            int(r.scored), int(r.missed),
        ))

    psycopg2.extras.execute_batch(cur, sql, rows)
    print(f"  team_match_stats: {len(rows)} rows inserted, "
          f"{skipped} skipped {skip_reasons}")
# ── main ───────────────────────────────────────────────────────────────────

def main():
    import psycopg2.extras  # ensure available for execute_batch

    conn = get_connection()
    conn.autocommit = False

    try:
        cur = conn.cursor()
        print("Loading data into PostgreSQL...\n")

        load_seasons(cur)
        load_teams(cur)
        load_players(cur)
        load_matches(cur)
        load_shots(cur)
        load_team_match_stats(cur)

        conn.commit()
        print("\nAll tables loaded successfully.")

    except Exception as e:
        conn.rollback()
        print(f"\nERROR — rolled back: {e}")
        raise

    finally:
        conn.close()

if __name__ == "__main__":
    import psycopg2.extras
    main()