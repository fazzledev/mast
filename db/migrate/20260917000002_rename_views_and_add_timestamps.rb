# Rails names: views becomes passage_views (and no longer reads like an SQL
# view), passages.first_seen becomes created_at, every table gets created_at
# and updated_at, filled in from the times already recorded, and the index is
# named for what it covers.
class RenameViewsAndAddTimestamps < Mast::Migration
  def up
    execute <<~SQL
      ALTER TABLE views RENAME TO passage_views;

      ALTER TABLE passages RENAME COLUMN first_seen TO created_at;
      ALTER TABLE passages ADD COLUMN updated_at REAL;
      UPDATE passages SET updated_at = created_at;

      ALTER TABLE attempts ADD COLUMN created_at REAL;
      ALTER TABLE attempts ADD COLUMN updated_at REAL;
      UPDATE attempts SET created_at = started_at,
        updated_at = MAX(started_at, COALESCE(ended_at, 0), COALESCE(blocked_again_at, 0));

      ALTER TABLE passage_views ADD COLUMN created_at REAL;
      ALTER TABLE passage_views ADD COLUMN updated_at REAL;
      UPDATE passage_views SET created_at = shown_at, updated_at = COALESCE(left_at, shown_at);

      DROP INDEX IF EXISTS attempts_site;
      CREATE INDEX index_attempts_on_site_and_started_at ON attempts (site, started_at);
    SQL
  end
end
