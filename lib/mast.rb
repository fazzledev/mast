# Mast's Ruby side: the record of unblock attempts and the passage pool.
#
# Laid out the Rails way without Rails. Nothing here needs a gem -- the shell
# runs whichever Ruby it finds, and that may be one with none installed -- so
# the pieces Rails would provide are small hand-rolled versions:
#
#   Mast.env        MAST_ENV, "production" unless set; the widget's test mode
#                   is "test", with a database of its own
#   Mast.db         the environment's SQLite database, migrated on first use,
#                   reached through the sqlite3 command-line tool
#   Mast::Record    a sliver of ActiveRecord for the models
#   db/migrate/     numbered migrations, tracked in schema_migrations
#   config/         passage sources and the hand-written paragraphs
#
# Times are seconds since the epoch, as REAL columns.

require "fileutils"
require "json"

module Mast
  ROOT = File.expand_path("..", __dir__)

  class << self
    def root = ROOT

    def env = ENV.fetch("MAST_ENV", "production")

    def data_dir
      File.join(ENV["XDG_DATA_HOME"] || File.expand_path("~/.local/share"), "fazzledev-mast")
    end

    def cache_dir
      File.join(ENV["XDG_CACHE_HOME"] || File.expand_path("~/.cache"), "fazzledev-mast")
    end

    def database_path = File.join(data_dir, "#{env}.sqlite3")

    def db
      @db ||= Database.new(database_path).tap(&:migrate!)
    end

    # Forgets the connection, so the next use opens the current environment's
    # database. For tests.
    def reset_db! = @db = nil
  end
end

require_relative "mast/database"
require_relative "mast/migration"
require_relative "mast/record"
require_relative "mast/models/passage"
require_relative "mast/models/attempt"
require_relative "mast/models/passage_view"
require_relative "mast/events_controller"
require_relative "mast/reports/stats"
require_relative "mast/reports/history"
