import pandas as pd
import ast
import os

# ── paths ──────────────────────────────────────────────────────────────────
RAW = "data/raw/understat"

SEASONS = ["2023_24", "2024_25", "2025_26"]

def load_csv(name, season):
    path = os.path.join(RAW, f"{name}_{season}.csv")
    df = pd.read_csv(path)
    df["_season"] = season
    return df

# ── 1. SHOTS ───────────────────────────────────────────────────────────────
def explore_shots():
    print("=" * 60)
    print("DATASET 1 — SHOTS")
    print("=" * 60)

    frames = [load_csv("shots", s) for s in SEASONS]
    df = pd.concat(frames, ignore_index=True)

    print(f"\nTotal rows     : {len(df):,}")
    print(f"Columns        : {df.columns.tolist()}")
    print(f"\nDtypes:\n{df.dtypes}")
    print(f"\nNull counts:\n{df.isnull().sum()}")
    print(f"\nUnique values:")
    for col in ["result", "situation", "shotType", "h_a"]:
        print(f"  {col:15}: {df[col].unique().tolist()}")
    print(f"\nxG range       : {df['xG'].min():.4f} → {df['xG'].max():.4f}")
    print(f"xG nulls       : {df['xG'].isnull().sum()}")
    print(f"\nSeason dist:\n{df['season'].value_counts()}")
    print(f"\nSample rows:\n{df.head(3).to_string()}")

# ── 2. PLAYERS ─────────────────────────────────────────────────────────────
def explore_players():
    print("\n" + "=" * 60)
    print("DATASET 2 — PLAYERS")
    print("=" * 60)

    frames = [load_csv("players", s) for s in SEASONS]
    df = pd.concat(frames, ignore_index=True)

    print(f"\nTotal rows     : {len(df):,}")
    print(f"Columns        : {df.columns.tolist()}")
    print(f"\nNull counts:\n{df.isnull().sum()}")
    print(f"\nPosition values: {df['position'].unique().tolist()}")
    print(f"\nMulti-team rows (comma in team_title):")
    multi = df[df['team_title'].str.contains(',', na=False)]
    print(f"  Count: {len(multi)}")
    print(f"  Sample:\n{multi[['player_name','team_title','position']].head(5).to_string()}")
    print(f"\nxG range       : {df['xG'].min():.4f} → {df['xG'].max():.4f}")
    print(f"\nSample rows:\n{df.head(3).to_string()}")

# ── 3. MATCHES ─────────────────────────────────────────────────────────────
def explore_matches():
    print("\n" + "=" * 60)
    print("DATASET 3 — MATCHES")
    print("=" * 60)

    frames = [load_csv("matches", s) for s in SEASONS]
    df = pd.concat(frames, ignore_index=True)

    print(f"\nTotal rows     : {len(df):,}")
    print(f"Columns        : {df.columns.tolist()}")
    print(f"\nNull counts:\n{df.isnull().sum()}")
    print(f"\nisResult dist  : {df['isResult'].value_counts().to_dict()}")

    # parse one dict column to show structure
    sample_h = df['h'].iloc[0]
    print(f"\nRaw 'h' column sample : {sample_h}")
    print(f"Type                  : {type(sample_h)}")
    try:
        parsed = ast.literal_eval(sample_h)
        print(f"Parsed keys           : {list(parsed.keys())}")
        print(f"Parsed values         : {parsed}")
    except Exception as e:
        print(f"Parse error           : {e}")

    print(f"\nSample rows:\n{df.head(3).to_string()}")

# ── 4. TEAM STATS ──────────────────────────────────────────────────────────
def explore_team_stats():
    print("\n" + "=" * 60)
    print("DATASET 4 — TEAM MATCH STATS")
    print("=" * 60)

    frames = [load_csv("team_stats", s) for s in SEASONS]
    df = pd.concat(frames, ignore_index=True)

    print(f"\nTotal rows     : {len(df):,}")
    print(f"Columns        : {df.columns.tolist()}")
    print(f"\nNull counts:\n{df.isnull().sum()}")
    print(f"\nResult dist    : {df['result'].value_counts().to_dict()}")
    print(f"h_a dist       : {df['h_a'].value_counts().to_dict()}")

    # parse ppda dict
    sample_ppda = df['ppda'].iloc[0]
    print(f"\nRaw 'ppda' sample : {sample_ppda}")
    try:
        parsed = ast.literal_eval(sample_ppda)
        print(f"Parsed            : {parsed}")
    except Exception as e:
        print(f"Parse error       : {e}")

    print(f"\nxG range       : {df['xG'].min():.4f} → {df['xG'].max():.4f}")
    print(f"\nSample rows:\n{df.head(3).to_string()}")

# ── run all ────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    explore_shots()
    explore_players()
    explore_matches()
    explore_team_stats()