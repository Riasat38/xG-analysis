import pandas as pd
from pathlib import Path
from understatapi import UnderstatClient
import time

RAW_DIR = Path("data/raw/understat")
RAW_DIR.mkdir(parents=True, exist_ok=True)

# Understat uses start year as season identifier
# 2023 = 2023/24, 2024 = 2024/25, 2025 = 2025/26
SEASONS = ["2023", "2024", "2025"]

SEASON_LABEL = {
    "2023": "2023_24",
    "2024": "2024_25",
    "2025": "2025_26",
}

def fetch_all():
    with UnderstatClient() as understat:
        for season in SEASONS:
            label = SEASON_LABEL[season]
            print(f"\n{'='*50}")
            print(f"Fetching season {label}...")
            print(f"{'='*50}")

            # ── 1. MATCHES ─────────────────────────────────────
            print(f"  Fetching matches...")
            matches = understat.league(league="EPL").get_match_data(season=season)
            pd.DataFrame(matches).to_csv(
                RAW_DIR / f"matches_{label}.csv", index=False
            )
            print(f"  Saved {len(matches)} matches → matches_{label}.csv")

            # ── 2. TEAM STATS (per matchday history) ───────────
            print(f"  Fetching team stats...")
            teams = understat.league(league="EPL").get_team_data(season=season)
            rows = []
            for team_name, data in teams.items():
                history = data.get("history", [])
                for match_row in history:
                    row = {"team_name": team_name, "season": season}
                    row.update(match_row)
                    rows.append(row)
            pd.DataFrame(rows).to_csv(
                RAW_DIR / f"team_stats_{label}.csv", index=False
            )
            print(f"  Saved {len(rows)} team-match rows → team_stats_{label}.csv")

            # ── 3. PLAYERS ─────────────────────────────────────
            print(f"  Fetching players...")
            players = understat.league(league="EPL").get_player_data(season=season)
            pd.DataFrame(players).to_csv(
                RAW_DIR / f"players_{label}.csv", index=False
            )
            print(f"  Saved {len(players)} players → players_{label}.csv")

            # ── 4. SHOTS (one request per completed match) ─────
            print(f"  Fetching shots (this takes a few minutes)...")
            completed = [m for m in matches if m.get("isResult")]
            print(f"  Completed matches: {len(completed)}")

            shot_rows = []
            for i, match in enumerate(completed):
                match_id = match["id"]
                try:
                    shots = understat.match(match=match_id).get_shot_data()
                    for side in ["h", "a"]:
                        for shot in shots.get(side, []):
                            shot["match_id"]  = match_id
                            shot["h_a"]       = side
                            shot["h_team"]    = match["h"]["title"]
                            shot["a_team"]    = match["a"]["title"]
                            shot["h_goals"]   = match["goals"]["h"]
                            shot["a_goals"]   = match["goals"]["a"]
                            shot["date"]      = match["datetime"]
                            shot["season"]    = season
                            shot_rows.append(shot)

                    # progress + rate limit
                    if (i + 1) % 10 == 0:
                        print(f"    {i+1}/{len(completed)} matches done...")
                    time.sleep(0.5)   # 500ms between requests

                except Exception as e:
                    print(f"    ERROR match {match_id}: {e}")
                    time.sleep(2)     # longer pause on error

            pd.DataFrame(shot_rows).to_csv(
                RAW_DIR / f"shots_{label}.csv", index=False
            )
            print(f"  Saved {len(shot_rows)} shots → shots_{label}.csv")

            # pause between seasons
            print(f"  Season {label} complete. Pausing 3s...")
            time.sleep(3)

    print("\nAll seasons fetched successfully.")
    print("Files saved to:", RAW_DIR)

if __name__ == "__main__":
    fetch_all()