package store

import (
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Regression kept from electus-1.20.0-patch2: upstream v3.0.0 closes the database on
// constructor failure (newStore defers db.Close until success), so this test passes
// without an Electus patch. Inspect ownership on failure, including Unix where unlink
// would hide a leaked handle. In v3 the SQLite pragmas travel in the DSN, so an invalid
// database file fails when the first connection opens instead of at a pragma statement.
func TestElectusConstructorClosesDatabaseOnFailure(t *testing.T) {
	stages := map[string]string{"invalid-database": "open initial connection", "migration": "migration"}
	for name, constructor := range map[string]func(Config) (*Store, error){"New": New, "withoutRepair": newWithoutRepair} {
		for failure, stage := range stages {
			t.Run(name+"/"+failure, func(t *testing.T) {
				cfg := mustDefaultConfig(t)
				cfg.DataDir = t.TempDir()
				file := filepath.Join(cfg.DataDir, "engram.db")
				if failure == "invalid-database" {
					if err := os.WriteFile(file, []byte("invalid SQLite database"), 0600); err != nil {
						t.Fatal(err)
					}
				} else {
					db, err := sql.Open("sqlite", file)
					if err != nil {
						t.Fatal(err)
					}
					_, execErr := db.Exec(`CREATE TABLE sessions (id TEXT PRIMARY KEY, project TEXT NOT NULL, directory TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT, summary TEXT); CREATE TABLE user_prompts (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, content TEXT NOT NULL, created_at TEXT NOT NULL);`)
					closeErr := db.Close()
					if execErr != nil {
						t.Fatal(execErr)
					}
					if closeErr != nil {
						t.Fatal(closeErr)
					}
				}
				original := openDB
				var opened *sql.DB
				openDB = func(dbPath string, generation *databaseGeneration) (*sql.DB, error) {
					var err error
					opened, err = original(dbPath, generation)
					return opened, err
				}
				t.Cleanup(func() {
					openDB = original
					if opened != nil {
						_ = opened.Close()
					}
				})
				_, err := constructor(cfg)
				if err == nil || !strings.Contains(err.Error(), stage) {
					t.Fatalf("expected %s failure, got %v", stage, err)
				}
				if opened == nil {
					t.Fatal("constructor did not open database")
				}
				if pingErr := opened.Ping(); pingErr == nil || !strings.Contains(pingErr.Error(), "database is closed") {
					t.Fatalf("constructor leaked opened database: Ping() = %v", pingErr)
				}
			})
		}
	}
}
