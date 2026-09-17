# The schema as it stood before migrations, created only where missing, so a
# database from then picks up here without losing anything.
class CreatePassagesAttemptsAndViews < Mast::Migration
  def up
    execute <<~SQL
      CREATE TABLE IF NOT EXISTS passages (
        id         TEXT PRIMARY KEY,
        text       TEXT NOT NULL,
        source     TEXT NOT NULL DEFAULT '',
        url        TEXT NOT NULL DEFAULT '',
        first_seen REAL NOT NULL
      );

      CREATE TABLE IF NOT EXISTS attempts (
        id               TEXT PRIMARY KEY,
        site             TEXT NOT NULL,
        label            TEXT NOT NULL,
        started_at       REAL NOT NULL,
        ended_at         REAL,
        outcome          TEXT,
        reason           TEXT,
        passage_id       TEXT REFERENCES passages(id),
        typing_seconds   REAL,
        wpm              INTEGER,
        peak_wpm         INTEGER,
        typos            INTEGER,
        relock_at        REAL,
        blocked_again_at REAL
      );
      CREATE INDEX IF NOT EXISTS attempts_site ON attempts (site, started_at);

      CREATE TABLE IF NOT EXISTS views (
        attempt_id  TEXT NOT NULL REFERENCES attempts(id),
        seq         INTEGER NOT NULL,
        passage_id  TEXT NOT NULL REFERENCES passages(id),
        shown_at    REAL NOT NULL,
        left_at     REAL,
        chars_typed INTEGER NOT NULL DEFAULT 0,
        completed   INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (attempt_id, seq)
      );
    SQL
  end
end
