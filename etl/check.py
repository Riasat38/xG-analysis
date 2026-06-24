# etl/check_understat.py
from understatapi import UnderstatClient
import json

with UnderstatClient() as understat:
    # Get all 2025/26 EPL matches
    matches = understat.league(league="EPL").get_match_data(season="2025")
    print(f"Matches found: {len(matches)}")
    print(json.dumps(matches[0], indent=2))  # inspect structure