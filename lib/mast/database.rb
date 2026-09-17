require "open3"

module Mast
  # An SQLite database, reached through the sqlite3 command-line tool: one
  # short-lived process per call, JSON back. The gem would be tidier, but the
  # shell's Ruby may not have it.
  class Database
    class Error < StandardError; end

    attr_reader :path

    def initialize(path)
      @path = path
    end

    # Runs SQL with each ? replaced by the next bind, quoted, and returns the
    # rows of the last statement as hashes.
    def execute(sql, binds = [])
      rows(run("PRAGMA foreign_keys = ON;\n#{interpolate(sql, binds)};"))
    end

    # Runs several statements as one transaction.
    def transaction(statements)
      run("PRAGMA foreign_keys = ON;\nBEGIN;\n#{statements.map { |s| "#{s};" }.join("\n")}\nCOMMIT;")
      nil
    end

    def migrate!
      FileUtils.mkdir_p(File.dirname(path))
      Migrator.new(self).migrate
    end

    def quote(value)
      case value
      when nil then "NULL"
      when true then "1"
      when false then "0"
      when Integer, Float then value.to_s
      else "'#{value.to_s.gsub("'", "''")}'"
      end
    end

    def interpolate(sql, binds)
      return sql if binds.empty?
      parts = sql.split("?", -1)
      if parts.length - 1 != binds.length
        raise ArgumentError, "#{parts.length - 1} placeholders but #{binds.length} binds in: #{sql}"
      end
      parts.each_with_index.map { |part, i| i < binds.length ? part + quote(binds[i]) : part }.join
    end

    private

    def run(script)
      out, err, status = Open3.capture3("sqlite3", "-bail", "-json", "-cmd", ".timeout 5000", path,
                                        stdin_data: "#{script}\n")
      raise Error, "sqlite3: #{err.strip}" unless status.success?
      out
    end

    # -json prints one array per statement that returns rows; the last one is
    # the answer.
    def rows(output)
      last = output.strip.split(/\n(?=\[)/).last
      last ? JSON.parse(last) : []
    end
  end
end
