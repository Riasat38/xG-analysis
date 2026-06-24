import pandas as pd
import ast
import os

RAW       = "data/raw/understat"
PROCESSED = "data/processed"
SEASONS   = ["2023_24", "2024_25", "2025_26"]

# season string → human-readable name
SEASON_NAME_MAP = {
    "2023_24": "2023/24",
    "2024_25": "2024/25",
    "2025_26": "2025/26",
}

os.makedirs(PROCESSED, exist_ok=True)

# ── helpers ────────────────────────────────────────────────────────────────

def safe_parse(val):
    """Parse stringified dict safely."""
    if isinstance(val, dict):
        return val
    try:
        return ast.literal_eval(str(val))
    except Exception:
        return {}

def simplify_position(pos):
    """Reduce multi-label position string to single primary role."""
    if pd.isna(pos) or pos.strip() == "":
        return "Unknown"
    p = pos.strip().upper()
    if p.startswith("GK"):
        return "GK"
    if p.startswith("D"):
        return "DF"
    if p.startswith("M"):
        return "MF"
    if p.startswith("F"):
        return "FW"
    return "Unknown"

def last_team(team_title):
    """For mid-season transfers, take the last (final) team."""
    if "," in str(team_title):
        return str(team_title).split(",")[-1].strip()
    return str(team_title).strip()

# ── 1. SHOTS ───────────────────────────────────────────────────────────────

def clean_shots():
    frames = []
    for s in SEASONS:
        df = pd.read_csv(os.path.join(RAW, f"shots_{s}.csv"))
        df["_season"] = s
        frames.append(df)

    df = pd.concat(frames, ignore_index=True)

    # drop own goals — not a player's shot attempt
    df = df[df["result"] != "OwnGoal"].copy()

    # is_goal flag
    df["is_goal"] = df["result"] == "Goal"

    # parse datetime
    df["match_date"] = pd.to_datetime(df["date"], errors="coerce")

    # season_name
    df["season_name"] = df["_season"].map(SEASON_NAME_MAP)

    # drop redundant / unused columns
    df.drop(columns=[ "date", "_season"], inplace=True)

    # rename to match schema
    df.rename(columns={
        "id":       "shot_id",
        "X":        "x_coord",
        "Y":        "y_coord",
        "xG":       "xg_value",
        "shotType": "body_part",
        "h_team":   "home_team_name",
        "a_team":   "away_team_name",
    }, inplace=True)

    # round xg to 4 decimal places
    df["xg_value"] = df["xg_value"].round(4)
    df["x_coord"]  = df["x_coord"].round(4)
    df["y_coord"]  = df["y_coord"].round(4)

    # final column order
    cols = [
        "shot_id", "match_id", "player_id", "player",
        "home_team_name", "away_team_name", "h_a",
        "xg_value", "is_goal", "result",
        "situation", "body_part",
        "minute", "x_coord", "y_coord",
        "h_goals", "a_goals", "match_date",
        "season", "season_name",
        "player_assisted", "lastAction",
    ]
    df = df[cols]

    out = os.path.join(PROCESSED, "shots_clean.csv")
    df.to_csv(out, index=False)
    print(f"Shots clean     : {len(df):,} rows → {out}")
    print(f"  OwnGoals dropped, is_goal added")
    print(f"  result values  : {df['result'].unique().tolist()}")
    print(f"  is_goal dist   : {df['is_goal'].value_counts().to_dict()}")
    return df

# ── 2. PLAYERS ─────────────────────────────────────────────────────────────

def clean_players():
    frames = []
    for s in SEASONS:
        df = pd.read_csv(os.path.join(RAW, f"players_{s}.csv"))
        df["_season"] = s
        frames.append(df)

    df = pd.concat(frames, ignore_index=True)

    # simplify position
    df["position_clean"] = df["position"].apply(simplify_position)

    # handle mid-season transfers — take last team
    df["team_name"] = df["team_title"].apply(last_team)

    # season name
    df["season_name"] = df["_season"].map(SEASON_NAME_MAP)

    # drop originals
    df.drop(columns=["position", "team_title", "_season"], inplace=True)
    df.rename(columns={
        "id":             "player_id",
        "player_name":    "full_name",
        "position_clean": "position",
    }, inplace=True)

    # round floats
    for col in ["xG", "xA", "npxG", "xGChain", "xGBuildup"]:
        df[col] = df[col].round(4)

    out = os.path.join(PROCESSED, "players_clean.csv")
    df.to_csv(out, index=False)
    print(f"\nPlayers clean   : {len(df):,} rows → {out}")
    print(f"  Position dist  : {df['position'].value_counts().to_dict()}")
    print(f"  Multi-team rows resolved to last team")
    return df

# ── 3. MATCHES ─────────────────────────────────────────────────────────────

def clean_matches():
    frames = []
    for s in SEASONS:
        df = pd.read_csv(os.path.join(RAW, f"matches_{s}.csv"))
        df["_season"] = s
        frames.append(df)

    df = pd.concat(frames, ignore_index=True)

    # parse all dict columns
    df["h_parsed"]        = df["h"].apply(safe_parse)
    df["a_parsed"]        = df["a"].apply(safe_parse)
    df["goals_parsed"]    = df["goals"].apply(safe_parse)
    df["xg_parsed"]       = df["xG"].apply(safe_parse)
    df["forecast_parsed"] = df["forecast"].apply(safe_parse)

    # extract fields
    df["home_team_id"]    = df["h_parsed"].apply(lambda x: int(x.get("id", 0)))
    df["home_team_name"]  = df["h_parsed"].apply(lambda x: x.get("title", ""))
    df["home_team_short"] = df["h_parsed"].apply(lambda x: x.get("short_title", ""))
    df["away_team_id"]    = df["a_parsed"].apply(lambda x: int(x.get("id", 0)))
    df["away_team_name"]  = df["a_parsed"].apply(lambda x: x.get("title", ""))
    df["away_team_short"] = df["a_parsed"].apply(lambda x: x.get("short_title", ""))
    df["home_goals"]      = df["goals_parsed"].apply(lambda x: int(x.get("h", 0)))
    df["away_goals"]      = df["goals_parsed"].apply(lambda x: int(x.get("a", 0)))
    df["home_xg"]         = df["xg_parsed"].apply(lambda x: round(float(x.get("h", 0)), 4))
    df["away_xg"]         = df["xg_parsed"].apply(lambda x: round(float(x.get("a", 0)), 4))
    df["forecast_w"]      = df["forecast_parsed"].apply(lambda x: round(float(x.get("w", 0)), 4))
    df["forecast_d"]      = df["forecast_parsed"].apply(lambda x: round(float(x.get("d", 0)), 4))
    df["forecast_l"]      = df["forecast_parsed"].apply(lambda x: round(float(x.get("l", 0)), 4))

    # parse datetime
    df["match_date"] = pd.to_datetime(df["datetime"], errors="coerce")

    # season name
    df["season_name"] = df["_season"].map(SEASON_NAME_MAP)

    # drop raw dict columns and unused
    df.drop(columns=[
        "h", "a", "goals", "xG", "forecast", "isResult",
        "datetime", "_season",
        "h_parsed", "a_parsed", "goals_parsed",
        "xg_parsed", "forecast_parsed",
    ], inplace=True)

    df.rename(columns={"id": "match_id"}, inplace=True)

    out = os.path.join(PROCESSED, "matches_clean.csv")
    df.to_csv(out, index=False)
    print(f"\nMatches clean   : {len(df):,} rows → {out}")
    print(f"  Columns        : {df.columns.tolist()}")
    print(f"  Sample:\n{df.head(3).to_string()}")
    return df

# ── 4. TEAM STATS ──────────────────────────────────────────────────────────

def clean_team_stats():
    frames = []
    for s in SEASONS:
        df = pd.read_csv(os.path.join(RAW, f"team_stats_{s}.csv"))
        df["_season"] = s
        frames.append(df)

    df = pd.concat(frames, ignore_index=True)

    # parse ppda dicts
    df["ppda_parsed"]         = df["ppda"].apply(safe_parse)
    df["ppda_allowed_parsed"] = df["ppda_allowed"].apply(safe_parse)

    df["ppda_att"]          = df["ppda_parsed"].apply(lambda x: int(x.get("att", 0)))
    df["ppda_def"]          = df["ppda_parsed"].apply(lambda x: int(x.get("def", 0)))
    df["ppda_allowed_att"]  = df["ppda_allowed_parsed"].apply(lambda x: int(x.get("att", 0)))
    df["ppda_allowed_def"]  = df["ppda_allowed_parsed"].apply(lambda x: int(x.get("def", 0)))

    # parse datetime
    df["match_date"] = pd.to_datetime(df["date"], errors="coerce")

    # season name
    df["season_name"] = df["_season"].map(SEASON_NAME_MAP)

    # drop raw dict columns
    df.drop(columns=[
        "ppda", "ppda_allowed",
        "ppda_parsed", "ppda_allowed_parsed",
        "date", "_season",
    ], inplace=True)

    df.rename(columns={"team": "team_id"}, inplace=True)

    # round floats
    for col in ["xG", "xGA", "npxG", "npxGA", "xpts", "npxGD"]:
        df[col] = df[col].round(4)

    out = os.path.join(PROCESSED, "team_stats_clean.csv")
    df.to_csv(out, index=False)
    print(f"\nTeam stats clean: {len(df):,} rows → {out}")
    print(f"  Columns        : {df.columns.tolist()}")
    return df

# ── 5. TEAMS MASTER TABLE ──────────────────────────────────────────────────
# derive unique teams from matches_clean (has IDs + names + short names)

def build_teams_master(matches_df):
    home = matches_df[["home_team_id","home_team_name","home_team_short"]].copy()
    home.columns = ["team_id","team_name","short_name"]

    away = matches_df[["away_team_id","away_team_name","away_team_short"]].copy()
    away.columns = ["team_id","team_name","short_name"]

    teams = pd.concat([home, away]).drop_duplicates(subset=["team_id"]).sort_values("team_id")
    teams["country"] = "England"
    teams["league"]  = "Premier League"

    out = os.path.join(PROCESSED, "teams_master.csv")
    teams.to_csv(out, index=False)
    print(f"\nTeams master    : {len(teams):,} unique teams → {out}")
    print(teams.to_string())
    return teams

# ── 6. SEASONS MASTER TABLE ───────────────────────────────────────────────

def build_seasons_master():
    seasons = pd.DataFrame([
        {"season_name": "2023/24", "league": "Premier League",
         "country": "England", "start_date": "2023-08-11", "end_date": "2024-05-19"},
        {"season_name": "2024/25", "league": "Premier League",
         "country": "England", "start_date": "2024-08-16", "end_date": "2025-05-25"},
        {"season_name": "2025/26", "league": "Premier League",
         "country": "England", "start_date": "2025-08-15", "end_date": "2026-05-24"},
    ])

    out = os.path.join(PROCESSED, "seasons_master.csv")
    seasons.to_csv(out, index=False)
    print(f"\nSeasons master  : {len(seasons)} rows → {out}")
    print(seasons.to_string())
    return seasons

# ── run all ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("Starting data cleaning...\n")
    clean_shots()
    clean_players()
    matches_df = clean_matches()
    clean_team_stats()
    build_teams_master(matches_df)
    build_seasons_master()
    print("\nAll done. Check data/processed/ for clean files.")