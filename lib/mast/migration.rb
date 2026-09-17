module Mast
  # A migration in db/migrate, named VERSION_snake_case_name.rb and defining
  # the CamelCase class. `up` calls `execute` with the SQL to run; everything
  # it asks for runs in one transaction with the version's schema_migrations
  # row, so a migration either lands whole or not at all.
  class Migration
    attr_reader :statements

    def initialize
      @statements = []
    end

    def execute(sql)
      @statements.concat(sql.split(/;\s*$/).map(&:strip).reject(&:empty?))
    end
  end

  class Migrator
    def initialize(db)
      @db = db
    end

    def migrate
      # WAL cannot be switched inside a transaction, and sticks to the file
      # once set. It is a call of its own because it prints a row, which an
      # empty schema_migrations would otherwise be mistaken for.
      @db.execute("PRAGMA journal_mode = WAL")
      applied = @db.execute(<<~SQL).map { |r| r["version"] }
        CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY);
        SELECT version FROM schema_migrations
      SQL
      pending.reject { |version, _| applied.include?(version) }.each do |version, file|
        migration = load_migration(file)
        migration.up
        @db.transaction(migration.statements +
                        ["INSERT INTO schema_migrations (version) VALUES (#{@db.quote(version)})"])
      end
    end

    def pending
      Dir[File.join(Mast.root, "db", "migrate", "*.rb")].sort.map do |file|
        [File.basename(file)[/\A\d+/], file]
      end
    end

    private

    def load_migration(file)
      require file
      name = File.basename(file, ".rb").sub(/\A\d+_/, "").split("_").map(&:capitalize).join
      Object.const_get(name).new
    end
  end
end
