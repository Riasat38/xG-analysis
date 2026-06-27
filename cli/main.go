package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"text/tabwriter"

	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
)

// ── DB connection ─────────────────────────────────────────────

func connect() *sql.DB {
	// load .env from parent directory
	godotenv.Load("../.env")

	dsn := fmt.Sprintf(
		"host=%s port=%s dbname=%s user=%s password=%s sslmode=disable",
		getenv("DB_HOST", "localhost"),
		getenv("DB_PORT", "5432"),
		getenv("DB_NAME", "pl_xg"),
		getenv("DB_USER", "pl_xg_user"),
		getenv("DB_PASSWORD", ""),
	)

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Fatalf("connection error: %v", err)
	}
	if err := db.Ping(); err != nil {
		log.Fatalf("ping error: %v", err)
	}
	return db
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// ── pretty printer ────────────────────────────────────────────

func printRows(rows *sql.Rows) {
	cols, err := rows.Columns()
	if err != nil {
		log.Fatalf("columns error: %v", err)
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)

	// header
	for i, col := range cols {
		if i > 0 {
			fmt.Fprint(w, "\t")
		}
		fmt.Fprint(w, col)
	}
	fmt.Fprintln(w)

	// separator
	for i := range cols {
		if i > 0 {
			fmt.Fprint(w, "\t")
		}
		fmt.Fprint(w, "--------")
	}
	fmt.Fprintln(w)

	// scan every column as *string — handles NUMERIC, BOOLEAN, TIMESTAMP cleanly
	count := 0
	for rows.Next() {
		// make a slice of *string pointers
		strs := make([]string, len(cols))
		ptrs := make([]interface{}, len(cols))
		for i := range strs {
			ptrs[i] = &strs[i]
		}

		if err := rows.Scan(ptrs...); err != nil {
			log.Fatalf("scan error: %v", err)
		}

		for i, s := range strs {
			if i > 0 {
				fmt.Fprint(w, "\t")
			}
			fmt.Fprint(w, s)
		}
		fmt.Fprintln(w)
		count++
	}

	w.Flush()
	fmt.Printf("\n(%d rows)\n", count)
}

// ── commands ──────────────────────────────────────────────────

func cmdTeamSummary(db *sql.DB, season string) {
	fmt.Printf("\n=== Team xG Summary — %s ===\n\n", season)
	q := `
		SELECT
			team_name,
			total_shots,
			total_xg,
			actual_goals,
			xg_delta,
			conversion_ratio
		FROM v_team_season_xg
		WHERE season_name = $1
		ORDER BY xg_delta DESC`
	rows, err := db.Query(q, season)
	if err != nil {
		log.Fatalf("query error: %v", err)
	}
	defer rows.Close()
	printRows(rows)
}

func cmdPlayerRanking(db *sql.DB, season string) {
	fmt.Printf("\n=== Top Player Finishers — %s ===\n\n", season)
	q := `
		SELECT
			season_rank  AS rank,
			full_name,
			team_name,
			position,
			shots,
			goals,
			xg,
			xg_delta,
			finishing_ratio
		FROM v_player_finishing
		WHERE season_name = $1
		  AND season_rank <= 15
		ORDER BY season_rank`
	rows, err := db.Query(q, season)
	if err != nil {
		log.Fatalf("query error: %v", err)
	}
	defer rows.Close()
	printRows(rows)
}

func cmdMatchShadow(db *sql.DB, season string) {
	fmt.Printf("\n=== Lucky Wins by Team — %s ===\n\n", season)
	q := `
		SELECT
			home_team,
			away_team,
			match_date,
			home_goals,
			away_goals,
			home_xg,
			away_xg,
			verdict
		FROM v_match_shadow
		WHERE season_name = $1
		  AND verdict IN ('home_lucky_win','away_lucky_win')
		ORDER BY match_date`
	rows, err := db.Query(q, season)
	if err != nil {
		log.Fatalf("query error: %v", err)
	}
	defer rows.Close()
	printRows(rows)
}

func cmdRollingForm(db *sql.DB, team string) {
	fmt.Printf("\n=== Rolling 5-Match xG Form — %s ===\n\n", team)
	q := `
		SELECT
			season_name,
			match_num,
			match_date::date        AS match_date,
			match_xg,
			match_goals,
			rolling_5_xg,
			rolling_5_goals,
			rolling_5_xg_delta
		FROM v_rolling_form
		WHERE team_name = $1
		  AND match_num >= 5
		ORDER BY match_date`
	rows, err := db.Query(q, team)
	if err != nil {
		log.Fatalf("query error: %v", err)
	}
	defer rows.Close()
	printRows(rows)
}

func cmdSituations(db *sql.DB, season string) {
	fmt.Printf("\n=== Shot Situation Breakdown — %s ===\n\n", season)
	q := `
		SELECT
			home_team,
			away_team,
			match_date::date        AS match_date,
			home_goals,
			away_goals,
			home_xg,
			away_xg,
			verdict
		FROM v_match_shadow
		WHERE season_name = $1
		  AND verdict IN ('home_lucky_win','away_lucky_win')
		ORDER BY match_date`
	rows, err := db.Query(q, season)
	if err != nil {
		log.Fatalf("query error: %v", err)
	}
	defer rows.Close()
	printRows(rows)
}

// ── usage ─────────────────────────────────────────────────────

func usage() {
	fmt.Println(`
PL xG CLI — Query Runner

Usage:
  team-summary   <season>    Team xG vs actual goals
  player-ranking <season>    Top finishers by xG delta
  match-shadow   <season>    Lucky wins and unlucky losses
  rolling-form   <team>      Rolling 5-match xG form
  situations     <season>    Shot situation breakdown

Seasons: 2023/24  2024/25  2025/26
Teams:   Liverpool  Arsenal  "Manchester City"  etc.

Examples:
  go run main.go team-summary 2023/24
  go run main.go player-ranking 2024/25
  go run main.go rolling-form Liverpool
  go run main.go situations 2023/24
`)
}

// ── main ──────────────────────────────────────────────────────

func main() {
	if len(os.Args) < 3 {
		usage()
		os.Exit(1)
	}

	command := os.Args[1]
	arg := os.Args[2]

	db := connect()
	defer db.Close()

	switch command {
	case "team-summary":
		cmdTeamSummary(db, arg)
	case "player-ranking":
		cmdPlayerRanking(db, arg)
	case "match-shadow":
		cmdMatchShadow(db, arg)
	case "rolling-form":
		cmdRollingForm(db, arg)
	case "situations":
		cmdSituations(db, arg)
	default:
		fmt.Printf("Unknown command: %s\n", command)
		usage()
		os.Exit(1)
	}
}
