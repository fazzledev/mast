require_relative "test_helper"

class MigrationsTest < Mast::TestCase
  # A database from before migrations: the old tables and a row in each.
  def test_a_database_from_before_migrations_is_brought_up_to_date
    old = Mast::Database.new(Mast.database_path)
    FileUtils.mkdir_p(File.dirname(old.path))
    migration = CreatePassagesAttemptsAndViews.new.tap(&:up) if defined?(CreatePassagesAttemptsAndViews)
    migration ||= begin
      require File.join(Mast.root, "db/migrate/20260917000001_create_passages_attempts_and_views.rb")
      CreatePassagesAttemptsAndViews.new.tap(&:up)
    end
    old.transaction(migration.statements + [
      "INSERT INTO passages (id, text, first_seen) VALUES ('p1', 'Old words', 100)",
      "INSERT INTO attempts (id, site, label, started_at, ended_at, outcome) VALUES ('a1', 'youtube', 'YouTube', 100, 300, 'walked_away')",
      "INSERT INTO views (attempt_id, seq, passage_id, shown_at, left_at) VALUES ('a1', 0, 'p1', 110, 290)",
    ])

    Mast.db

    view = Mast::PassageView.find("a1", 0)
    assert_equal 110, view.created_at
    assert_equal 290, view.updated_at
    assert_equal 100, Mast::Passage.find("p1").created_at
    assert_equal [100, 300], Mast::Attempt.find("a1").attributes.values_at("created_at", "updated_at")
    versions = Mast.db.execute("SELECT version FROM schema_migrations ORDER BY version").map { |r| r["version"] }
    assert_equal Mast::Migrator.new(Mast.db).pending.map(&:first), versions
  end

  def test_migrating_twice_changes_nothing
    Mast.db
    Mast.reset_db!
    Mast.db.migrate!

    assert_equal 2, Mast.db.execute("SELECT COUNT(*) AS n FROM schema_migrations").first["n"]
  end
end
