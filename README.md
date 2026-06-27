# Premier League xG vs Actual Goals — SQL Analytics Project

A PostgreSQL analytics project exploring **expected goals (xG) vs actual goals** across three
Premier League seasons (2023/24, 2024/25, 2025/26) using shot-level event data from the
Understat API. Built to develop SQL proficiency from intermediate to advanced level through
real football data.

---

## Table of Contents

- [What is xG?](#what-is-xg)
- [Project Goals](#project-goals)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Data Setup](#data-setup)
- [Database Schema](#database-schema)
- [Analysis Layers](#analysis-layers)
  - [Layer 1 — Team xG Summary](#layer-1--team-xg-summary)
  - [Layer 2 — Player Finishing Quality](#layer-2--player-finishing-quality)
  - [Layer 3 — Match Shadow Scorelines](#layer-3--match-shadow-scorelines)
  - [Layer 4 — Shot Situation Breakdown](#layer-4--shot-situation-breakdown)
  - [Layer 5 — Rolling Form Tracker](#layer-5--rolling-form-tracker)
- [Key Findings](#key-findings)
- [Go CLI Tool](#go-cli-tool)
- [SQL Concepts Covered](#sql-concepts-covered)
- [Milestones](#milestones)

---

## What is xG?

**Expected Goals (xG)** is a metric that measures the quality of a shot based on factors like
distance from goal, angle, body part used, and the type of chance created. Every shot is
assigned an xG value between 0 and 1:

- `0.03` — a long-range speculative effort
- `0.15` — a decent open-play chance
- `0.40` — a close-range header from a corner
- `0.76` — a penalty kick
- `0.95` — a tap-in from two yards

When you sum a player's or team's xG across a season, you get the number of goals they
*should* have scored based on the quality of chances they created. Comparing this to actual
goals scored reveals who is:

- **Overperforming** — scoring more than their chances suggest (clinical finishers)
- **Underperforming** — scoring fewer than expected (poor finishing or bad luck)

---

## Project Goals

1. Build intermediate-to-advanced SQL proficiency using real football data
2. Explore five distinct analytical layers: team, player, match, situation, and time-series
3. Design a production-style PostgreSQL schema with proper constraints, indexes, and views
4. Build a Go CLI tool to query the database from the terminal
5. Generate genuine analytical findings about PL teams and players across three seasons

---

## Tech Stack

| Component | Technology |
|---|---|
| Database | PostgreSQL 17.5 |
| ETL / Data pipeline | Python 3.13, pandas, psycopg2 |
| Data source | Understat API via `understatapi` |
| CLI tool | Go 1.21, `database/sql`, `lib/pq` |
| OS | Windows (Git Bash) |

---

## Project Structure

```
pl_xg/
├── cli/
│   ├── main.go                     ← Go CLI query runner
│   ├── go.mod
│   └── go.sum
├── data/
│   ├── raw/understat/              ← raw API data (gitignored)
│   └── processed/                  ← cleaned CSVs (gitignored)
├── etl/
│   ├── db.py                       ← PostgreSQL connection helper
│   ├── fetch_understat.py          ← pulls all 4 datasets from Understat API
│   ├── explore_data.py             ← data exploration and audit
│   ├── clean_data.py               ← cleaning, parsing, normalization
│   └── loader.py                   ← loads processed CSVs into PostgreSQL
├── sql/
│   ├── schema/
│   │   ├── 001_create_tables.sql   ← DDL for all 6 tables
│   │   └── 002_create_indexes.sql  ← performance indexes
│   ├── queries/
│   │   ├── layer1_team_xg_summary.sql
│   │   ├── layer2_player_finishing.sql
│   │   ├── layer3_match_shadow.sql
│   │   ├── layer4_shot_situations.sql
│   │   └── layer5_rolling_form.sql
│   └── views/
│       └── 001_create_views.sql    ← all 5 analysis layers as named views
├── analysis/                       ← ad-hoc scripts and notebooks
├── docs/                           ← notes and diagrams
├── tests/                          ← data integrity audit queries
├── .env.example                    ← credentials template
├── requirements.txt
└── README.md
```

---

## Data Setup

Data is not committed to this repository. To regenerate:

### 1. Clone and install

```bash
git clone <your-repo-url>
cd pl_xg
python3 -m venv pl
pl\Scripts\activate          # Windows
pip install -r requirements.txt
cp .env.example .env         # fill in your DB credentials
```

### 2. Set up PostgreSQL

```bash
psql -U postgres
```

```sql
CREATE USER pl_xg_user WITH PASSWORD 'your_password';
CREATE DATABASE pl_xg OWNER pl_xg_user;
GRANT ALL PRIVILEGES ON DATABASE pl_xg TO pl_xg_user;
\c pl_xg
GRANT ALL ON SCHEMA public TO pl_xg_user;
\q
```

### 3. Create tables and indexes

```bash
psql -U pl_xg_user -d pl_xg -h localhost -f sql/schema/001_create_tables.sql
psql -U pl_xg_user -d pl_xg -h localhost -f sql/schema/002_create_indexes.sql
```

### 4. Fetch data from Understat

```bash
python etl/fetch_understat.py
```

This pulls shots, matches, players, and team stats for seasons 2023/24, 2024/25, and
2025/26 from the Understat API. Expect 5–10 minutes due to per-match shot requests.

### 5. Clean the data

```bash
python etl/clean_data.py
```

### 6. Load into PostgreSQL

```bash
python etl/loader.py
```

### 7. Create views

```bash
psql -U pl_xg_user -d pl_xg -h localhost -f sql/views/001_create_views.sql
```

### Expected row counts after loading

| Table | Rows |
|---|---|
| seasons | 3 |
| teams | 25 |
| players | 943 |
| matches | 1,140 |
| shots | 29,801 |
| team_match_stats | 2,280 |

---

## Database Schema

```
seasons ──────────────── matches ──────────────── shots
(season_id PK)           (match_id PK)            (shot_id PK)
(season_name)            (season_id FK)            (match_id FK)
(league)                 (home_team_id FK)         (player_id FK)
(country)                (away_team_id FK)         (team_id FK)
                         (match_date)              (xg_value)
teams ───────────────────(home_goals)              (is_goal)
(team_id PK)             (away_goals)              (situation)
(team_name)              (home_xg)                 (body_part)
(short_name)             (away_xg)                 (minute)
(league)                 (forecast_w/d/l)          (x_coord)
(country)                                          (y_coord)

players                  team_match_stats
(player_id PK)           (stat_id PK)
(full_name)              (match_id FK)
(position)               (team_id FK)
(nationality)            (xg_for / xg_against)
                         (ppda_att / ppda_def)
                         (deep / deep_allowed)
                         (xpts / result)
```

**Design decisions:**
- `shots.shot_id`, `matches.match_id`, `players.player_id` all use Understat's own numeric
  IDs as primary keys — no need for a mapping table
- `teams.team_id` uses Understat's team IDs extracted from match JSON
- `seasons` has a `UNIQUE(season_name, league)` constraint — supports multi-league expansion
  without schema changes
- `matches.gw` (gameweek) is nullable — Understat doesn't provide it, derived from date
  ordering if needed
- xG coordinates use Understat's 0.0–1.0 normalized pitch scale

---

## Analysis Layers

### Layer 1 — Team xG Summary

**File:** `sql/queries/layer1_team_xg_summary.sql`
**View:** `v_team_season_xg`

Aggregates total xG generated and actual goals scored per team per season. Computes
`xg_delta` (goals minus xG) and `conversion_ratio` (goals divided by xG).

**SQL concepts:** multi-table JOIN chains, GROUP BY, SUM, ROUND, NULLIF for division safety,
CREATE VIEW.

```sql
SELECT * FROM v_team_season_xg ORDER BY xg_delta DESC LIMIT 5;
```

#### Findings

**Biggest overperformers (scored more than xG suggested):**

| Team | Season | xG | Goals | Delta |
|---|---|---|---|---|
| Wolverhampton Wanderers | 2024/25 | 45.77 | 53 | +7.23 |
| Manchester City | 2023/24 | 90.29 | 94 | +3.72 |
| Nottingham Forest | 2024/25 | 54.01 | 57 | +2.99 |
| West Ham | 2023/24 | 55.39 | 58 | +2.61 |

Wolves 2024/25 stands out — a conversion ratio of 1.158 means they scored 15% more goals
than the model predicted, almost entirely driven by Matheus Cunha's exceptional finishing.

**Biggest underperformers (scored less than xG suggested):**

| Team | Season | xG | Goals | Delta |
|---|---|---|---|---|
| Everton | 2023/24 | 63.06 | 40 | -23.06 |
| Crystal Palace | 2025/26 | 62.90 | 40 | -22.90 |
| Liverpool | 2023/24 | 97.11 | 80 | -17.11 |

Everton 2023/24 is the starkest finding in the dataset — generating 63 xG worth of chances
but converting only 40, a deficit of over 23 goals. Crystal Palace appears in the bottom 10
in two separate seasons, suggesting a systemic finishing problem at the club. Liverpool's
2023/24 underperformance (-17.11) is notable: with 97 xG they were creating elite chances
all season but couldn't convert, which directly explains why their title challenge fell short.

---

### Layer 2 — Player Finishing Quality

**File:** `sql/queries/layer2_player_finishing.sql`
**View:** `v_player_finishing`

Ranks players by xG delta within each season using a CTE and RANK() window function.
A minimum of 20 shots filters out statistical noise from players with tiny sample sizes.

**SQL concepts:** CTE (WITH), RANK() OVER (PARTITION BY), HAVING for post-aggregation
filtering, STRING_AGG for multi-season breakdowns.

```sql
SELECT full_name, team_name, season_name, xg_delta, season_rank
FROM v_player_finishing WHERE season_rank <= 3
ORDER BY season_name, season_rank;
```

#### Findings

**Season overperformance leaders:**

| Season | Rank | Player | Team | xG | Goals | Delta |
|---|---|---|---|---|---|---|
| 2023/24 | 1 | Phil Foden | Man City | 11.31 | 19 | +7.69 |
| 2023/24 | 2 | Callum Hudson-Odoi | Nott'm Forest | 3.02 | 8 | +4.98 |
| 2024/25 | 1 | Matheus Cunha | Wolves | 8.45 | 15 | +6.55 |
| 2024/25 | 2 | Bryan Mbeumo | Brentford | 13.63 | 20 | +6.37 |
| 2025/26 | 1 | Harry Wilson | Fulham | 5.76 | 10 | +4.24 |

Callum Hudson-Odoi's finishing ratio of 2.649 in 2023/24 is the most extreme in the dataset
— he scored nearly 3x his expected goals, suggesting either extraordinary clinical finishing
or very fortunate bounces across a small sample.

**Worst finishers (min 20 shots):**

| Player | Team | Season | xG | Goals | Delta |
|---|---|---|---|---|---|
| Darwin Núñez | Liverpool | 2023/24 | 19.19 | 11 | -8.19 |
| Dominic Calvert-Lewin | Everton | 2023/24 | 13.63 | 7 | -6.63 |
| Dominic Calvert-Lewin | Everton | 2024/25 | 8.58 | 3 | -5.58 |

Darwin Núñez's 2023/24 season is one of the worst individual finishing performances in the
data — 108 shots, elite-quality chances averaging 0.18 xG each, but only 11 goals. His
conversion ratio of 0.573 means he converted barely half of what the model expected.
Dominic Calvert-Lewin appears as a chronic underperformer in two consecutive seasons for
two different situations, suggesting this is a player-level trait rather than circumstance.

**Most consistent overperformers across all 3 seasons:**

| Player | Total Delta | Avg Delta/Season | Breakdown |
|---|---|---|---|
| Matheus Cunha | +11.24 | +3.75 | 2023/24: +1.77, 2024/25: +6.55, 2025/26: +2.92 |
| Phil Foden | +8.82 | +2.94 | 2023/24: +7.69, 2024/25: +0.82, 2025/26: +0.31 |
| Harry Wilson | +7.81 | +2.60 | 2023/24: +1.18, 2024/25: +2.39, 2025/26: +4.24 |
| Callum Hudson-Odoi | +7.52 | +2.51 | 2023/24: +4.98, 2024/25: +2.49, 2025/26: +0.05 |

Matheus Cunha is the most consistently clinical finisher in the PL across this period —
positive in every single season with an average delta of +3.75 per season. Foden's 2023/24
performance (+7.69) was exceptional but he has regressed toward average since, suggesting
his that season may have been partially luck-driven.

---

### Layer 3 — Match Shadow Scorelines

**File:** `sql/queries/layer3_match_shadow.sql`
**View:** `v_match_shadow`

For every match, computes an xG-based "shadow scoreline" and compares it to the actual
result. Classifies each match as a deserved win, lucky win, or misleading draw.

**SQL concepts:** FILTER(WHERE) aggregate extension, CASE WHEN chains, multi-CTE structure,
::date casting.

```sql
SELECT verdict, COUNT(*) AS matches FROM v_match_shadow
GROUP BY verdict ORDER BY matches DESC;
```

#### Findings

**Verdict distribution across 1,140 matches:**

| Verdict | Matches | % |
|---|---|---|
| Deserved home win | 416 | 36.5% |
| Deserved away win | 257 | 22.5% |
| Draw (matched xG) | 193 | 16.9% |
| Away lucky win | 111 | 9.7% |
| Misleading draw | 89 | 7.8% |
| Home lucky win | 74 | 6.5% |

**Key insight:** 59% of matches go to the xG-deserving team. This means **41% of Premier
League matches produce a result that doesn't match the balance of play** — whether through
a lucky win, a draw despite one team dominating, or vice versa. Football's inherent
randomness is quantified here.

Away teams have 111 lucky wins vs only 74 for home teams — the underdog effect, where
defensively-minded away sides sit deep and steal results on the counter despite being
outplayed in terms of chance quality.

**Teams with the most lucky wins across all seasons:**

| Team | Lucky Wins |
|---|---|
| Manchester United | 15 |
| Aston Villa | 14 |
| Fulham | 13 |
| Chelsea | 12 |
| West Ham | 12 |

Manchester United's 15 lucky wins partially explain how they avoided even worse league
finishes during a difficult transitional period. Arsenal, despite their reputation for
dominance, had only 8 lucky wins — the lowest among top-half clubs — suggesting they
tend to win matches they genuinely deserve to win.

---

### Layer 4 — Shot Situation Breakdown

**File:** `sql/queries/layer4_shot_situations.sql`
**View:** `v_shot_situations`

Groups all shots by situation (OpenPlay, FromCorner, SetPiece, DirectFreekick, Penalty)
and body part (RightFoot, LeftFoot, Head), comparing the xG model's predicted conversion
rate against what players actually achieved.

**SQL concepts:** CASE WHEN for derived verdict categories, HAVING for minimum sample
filtering, scalar subqueries inside SELECT, multiple aggregations on the same column,
::numeric type casting for decimal division.

```sql
SELECT situation, body_part, avg_xg_per_shot, actual_conv_pct, verdict
FROM v_shot_situations ORDER BY avg_xg_per_shot DESC;
```

#### Findings

**Shot volume and conversion by situation:**

| Situation | Shots | Share | Avg xG | Actual Conv% | Verdict |
|---|---|---|---|---|---|
| Penalty | 282 | 0.9% | 0.761 | 85.8% | Over expected |
| OpenPlay | 21,942 | 73.6% | 0.124 | 10.9% | Under expected |
| SetPiece | 1,721 | 5.8% | 0.119 | 8.5% | Under expected |
| FromCorner | 5,057 | 17.0% | 0.107 | 9.1% | Under expected |
| DirectFreekick | 799 | 2.7% | 0.063 | 5.3% | Under expected |

**Penalties:** PL players convert at 85.8% vs the model's 76.1% — a systematic
overperformance meaning Understat's penalty xG value underestimates how good top-flight
players are from 12 yards.

**Headers are systematically overvalued** by the xG model: open play headers have a
model prediction of 16.8% conversion but players only convert 13.0%, a consistent gap
across all three seasons.

**Direct freekicks** are the least efficient shot type — only 5.3% conversion rate on
799 attempts across 3 seasons. Teams are investing effort in set-piece routines that
convert at below half the rate of open-play shots.

**Perfect penalty takers (minimum 3 penalties):**
Bukayo Saka (8/8), Jean-Philippe Mateta (8/8), Raúl Jiménez (7/7), Cole Palmer (18/20,
90%), Mohamed Salah (15/17, 88%).

Notably Erling Haaland converted only 13/16 penalties (81.3%) — below the league average
for a player of his calibre, and one area where his overall xG delta suffers.

---

### Layer 5 — Rolling Form Tracker

**File:** `sql/queries/layer5_rolling_form.sql`
**View:** `v_rolling_form`

Tracks each team's xG and actual goals over a rolling 5-match window across every match
of the season. Reveals genuine form spells, collapses, and whether teams were sustaining
results through quality or luck.

**SQL concepts:** named WINDOW clause, ROWS BETWEEN frame specification, PARTITION BY
for per-team windows, ROW_NUMBER() for match numbering, LAG() for previous-match
comparison, ROWS vs RANGE distinction.

```sql
SELECT match_num, match_date, rolling_5_xg, rolling_5_xg_delta
FROM v_rolling_form WHERE team_name = 'Arsenal' AND season_name = '2023/24'
AND match_num >= 5 ORDER BY match_date;
```

#### Findings

**Peak 5-match rolling xG windows (best ever form spells):**

| Team | Season | Peak Date | Rolling 5 xG | Goals in Window |
|---|---|---|---|---|
| Liverpool | 2024/25 | Dec 2024 | 17.31 | 16 |
| Newcastle United | 2023/24 | Oct 2023 | 16.85 | 18 |
| Chelsea | 2024/25 | Dec 2024 | 16.22 | 16 |
| Liverpool | 2023/24 | Feb 2024 | 16.03 | 15 |

Liverpool's peak form spell in December 2024 was the most dominant 5-match window in
the entire dataset — 17.31 xG generated with 16 goals scored in that window.

**xG volatility — most inconsistent teams:**

| Team | Season | Peak | Trough | Volatility |
|---|---|---|---|---|
| Chelsea | 2025/26 | 15.78 | 5.08 | 10.70 |
| Tottenham | 2024/25 | 14.80 | 4.54 | 10.26 |
| Liverpool | 2024/25 | 17.31 | 7.08 | 10.23 |
| Bournemouth | 2024/25 | 14.76 | 4.90 | 9.86 |

Chelsea 2025/26 is the most volatile team in the dataset — swinging from a 5-match
xG of 5.08 (relegation-level) to 15.78 (title-contender level). This extreme inconsistency
reflects their squad imbalance despite massive investment.

**Arsenal 2023/24 title race insight:**
Arsenal's rolling form peaked at matches 27–28 (March 2024) with a 5-match delta of
+8.1 — massively overperforming their chances. From match 32 onward this collapsed to
-3.5, meaning they were generating good chances but stopped converting. This transition
between March and April 2024 maps precisely to the period where their title challenge
unraveled.

---

## Key Findings

A summary of the most significant analytical conclusions across all layers:

1. **41% of PL matches produce a result that defies xG** — the randomness built into
   football is quantifiable and substantial.

2. **Matheus Cunha is the most consistently clinical finisher** in the PL across 2023–2026,
   with +11.24 goals above xG across 3 seasons.

3. **Darwin Núñez's 2023/24 season** (-8.19 xG delta, 108 shots, 11 goals) is the worst
   individual finishing performance in the dataset — elite chances, historic wastefulness.

4. **Everton 2023/24** (-23.06 team xG delta) is the most extreme team-level
   underperformance — generating 63 xG but scoring only 40, a 37% shortfall.

5. **Penalties are undervalued by the xG model** — PL players convert at 85.8% vs the
   76.1% model expectation, a systematic gap across all 3 seasons.

6. **Headers are overvalued by the xG model** — actual conversion (13%) consistently
   lags model prediction (16.8%) across all situations and seasons.

7. **Liverpool 2023/24 lost the title partly due to finishing** — 97 xG generated
   (the highest in the dataset) but only 80 goals scored, a -17 delta that would have
   meant 17 more points if converted at model expectation.

8. **Manchester United accumulated 15 lucky wins** across the period — the most of any
   club, masking deeper structural decline in chance quality.

---

## Go CLI Tool

A command-line interface built in Go that connects directly to the PostgreSQL database
and queries the named views, printing formatted results to the terminal.

### Installation

```bash
cd cli
go mod tidy
go build -o pl_xg.exe .
```

### Usage

```
Usage:
  team-summary   <season>    Team xG vs actual goals
  player-ranking <season>    Top finishers by xG delta
  match-shadow   <season>    Lucky wins and unlucky losses
  rolling-form   <team>      Rolling 5-match xG form
  situations     <season>    Shot situation breakdown

Seasons: 2023/24  2024/25  2025/26
Teams:   Liverpool  Arsenal  "Manchester City"  etc.
```

### Examples

```bash
# Which teams overperformed their xG in 2023/24?
./pl_xg.exe team-summary 2023/24

# Top 15 clinical finishers in 2024/25
./pl_xg.exe player-ranking 2024/25

# Lucky wins and unlucky losses in 2023/24
./pl_xg.exe match-shadow 2023/24

# Arsenal's rolling xG form across all seasons
./pl_xg.exe rolling-form Arsenal

# Shot situation breakdown for 2024/25
./pl_xg.exe situations 2024/25
```

### Technical notes

- Uses Go's `database/sql` with `lib/pq` as the PostgreSQL driver
- Credentials loaded from `../.env` via `godotenv`
- All queries use parameterised placeholders (`$1`) — no string interpolation
- Output formatted with `text/tabwriter` for aligned terminal columns
- Queries hit named views rather than raw tables — clean separation between
  data access and business logic


---

## Data Source

All shot and match data sourced from [Understat](https://understat.com/) via the
`understatapi` Python library. Understat provides shot-level xG values modelled from
historical shot data using machine learning, covering the top 5 European leagues
from 2014/15 onward.

Data covers Premier League seasons 2023/24, 2024/25, and 2025/26.