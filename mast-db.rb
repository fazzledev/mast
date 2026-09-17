#!/usr/bin/env ruby
# The site block's record of unblock attempts, in SQLite.
#
# Every time a blocked site's switch is flipped, the widget opens an attempt
# and reports what happens to it: each passage it shows and how far the
# typing got before it was swapped, the typing speed once one is finished,
# why you said you wanted the site, and how the attempt ended. Once a site is
# unblocked it also reports when the relock is due and when the site was
# actually blocked again, which is what "time unblocked" is measured from.
#
# The widget writes through `record` and reads `stats`; the rest is for you:
#
#   mast-db reasons [SITE]   why you wanted each site, newest first
#   mast-db attempts [N]     the last N attempts (default 20)
#   mast-db passages         which passages sent you away, and which did not
#   mast-db stats            the widget's summary, as JSON
#   mast-db history          attempts and passages for the widget's history tab, as JSON
#   mast-db record JSON      store one event from the widget
#
# Outcomes: walked_away (Esc while typing), kept_blocked (said no at the end),
# unblocked, auth_dismissed (closed the password prompt), failed, and
# interrupted for an attempt the shell never finished reporting.
#
# Data lives in $XDG_DATA_HOME/fazzledev-mast/mast.sqlite3; a
# leading `--db PATH` points everything at another file, which is how the
# widget's test mode keeps its attempts out of the real record.
#
# SQLite is reached through the sqlite3 command-line tool rather than the
# gem, so this runs on whichever Ruby the shell finds, gems or not.

require "digest"
require "fileutils"
require "json"
require "open3"

DB_PATH = if ARGV[0] == "--db"
  ARGV.shift
  File.expand_path(ARGV.shift.to_s)
else
  File.join(ENV["XDG_DATA_HOME"] || File.expand_path("~/.local/share"), "fazzledev-mast", "mast.sqlite3")
end
WEEK = 7 * 24 * 3600
# Ones with no ending reported this long after starting were cut off.
INTERRUPTED_AFTER = 3 * 3600
# The helper's RELOCK_MINUTES. Stands in for an unblock whose relock and
# re-block the widget never saw, say because the shell was restarted.
RELOCK_SECONDS = 15 * 60

SCHEMA = <<~SQL
  CREATE TABLE IF NOT EXISTS passages (
    id         TEXT PRIMARY KEY,  -- sha1 of the text
    text       TEXT NOT NULL,
    source     TEXT NOT NULL DEFAULT '',  -- empty for the hand-written ones
    url        TEXT NOT NULL DEFAULT '',
    first_seen REAL NOT NULL
  );

  CREATE TABLE IF NOT EXISTS attempts (
    id               TEXT PRIMARY KEY,
    site             TEXT NOT NULL,
    label            TEXT NOT NULL,
    started_at       REAL NOT NULL,
    ended_at         REAL,
    outcome          TEXT,  -- NULL while it is still going
    reason           TEXT,
    passage_id       TEXT REFERENCES passages(id),  -- the one typed out in full
    typing_seconds   REAL,
    wpm              INTEGER,
    peak_wpm         INTEGER,
    typos            INTEGER,
    relock_at        REAL,  -- when the helper's timer was due to block it again
    blocked_again_at REAL   -- when the widget saw it blocked again
  );
  CREATE INDEX IF NOT EXISTS attempts_site ON attempts (site, started_at);

  -- One row per passage shown in an attempt, in order.
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

# A value as an SQL literal.
def literal(value)
  case value
  when nil then "NULL"
  when true then "1"
  when false then "0"
  when Integer, Float then value.to_s
  else "'#{value.to_s.gsub("'", "''")}'"
  end
end

# Runs one or more statements with each ? replaced by the next param, and
# returns the rows of the last one as hashes.
def sql(statement, params = [])
  parts = statement.split("?", -1)
  raise ArgumentError, "#{parts.length - 1} placeholders, #{params.length} params" if parts.length - 1 != params.length
  query = parts.each_with_index.map { |part, i| i < params.length ? part + literal(params[i]) : part }.join
  unless @schema_ready
    FileUtils.mkdir_p(File.dirname(DB_PATH))
    sqlite("PRAGMA journal_mode = WAL;\n#{SCHEMA}")
    @schema_ready = true
  end
  # Only the query's own output, so an empty result is not mistaken for a
  # pragma's.
  out = sqlite("PRAGMA foreign_keys = ON;\n#{query};")
  # -json prints one array per statement that returns rows.
  last = out.strip.split(/\n(?=\[)/).last
  last ? JSON.parse(last) : []
end

def sqlite(script)
  out, err, status = Open3.capture3("sqlite3", "-bail", "-json", "-cmd", ".timeout 5000", DB_PATH,
                                    stdin_data: "#{script}\n")
  raise "sqlite3: #{err.strip}" unless status.success?
  out
end

# The same calls the gem offered, so the queries below read plainly.
class Db
  def execute(statement, params = []) = sql(statement, params)
  def get_first_row(statement, params = []) = sql(statement, params).first
end

def db
  @db ||= Db.new
end

# Seconds since the epoch from the widget's milliseconds, or now.
def time_of(event)
  event["at"] ? event["at"] / 1000.0 : Time.now.to_f
end

def record(event)
  at = time_of(event)
  case event.fetch("type")
  when "start"
    db.execute("INSERT OR IGNORE INTO attempts (id, site, label, started_at) VALUES (?, ?, ?, ?)",
               [event.fetch("attempt"), event.fetch("site"), event["label"] || event["site"], at])
  when "passage"
    text = event.fetch("text")
    id = Digest::SHA1.hexdigest(text)
    db.execute("INSERT INTO passages (id, text, source, url, first_seen) VALUES (?, ?, ?, ?, ?) " \
               "ON CONFLICT (id) DO UPDATE SET source = excluded.source, url = excluded.url",
               [id, text, event["source"].to_s, event["url"].to_s, at])
    db.execute("INSERT OR REPLACE INTO views (attempt_id, seq, passage_id, shown_at) VALUES (?, ?, ?, ?)",
               [event.fetch("attempt"), event.fetch("seq"), id, at])
  when "leave"
    db.execute("UPDATE views SET left_at = ?, chars_typed = ? WHERE attempt_id = ? AND seq = ?",
               [at, event["chars"].to_i, event.fetch("attempt"), event.fetch("seq")])
  when "typed"
    view = db.get_first_row("SELECT passage_id FROM views WHERE attempt_id = ? AND seq = ?",
                            [event.fetch("attempt"), event.fetch("seq")])
    db.execute("UPDATE views SET left_at = ?, chars_typed = ?, completed = 1 WHERE attempt_id = ? AND seq = ?",
               [at, event["chars"].to_i, event["attempt"], event["seq"]])
    db.execute("UPDATE attempts SET passage_id = ?, typing_seconds = ?, wpm = ?, peak_wpm = ?, typos = ? WHERE id = ?",
               [view && view["passage_id"], event["typing_ms"].to_f / 1000, event["wpm"], event["peak_wpm"],
                event["typos"], event["attempt"]])
  when "end"
    db.execute("UPDATE attempts SET outcome = ?, ended_at = ?, reason = COALESCE(?, reason) WHERE id = ?",
               [event.fetch("outcome"), at, blank_to_nil(event["reason"]), event.fetch("attempt")])
  when "relock"
    # The latest unblock of the site that has no relock time yet.
    db.execute("UPDATE attempts SET relock_at = ? WHERE id = (SELECT id FROM attempts WHERE site = ? " \
               "AND outcome = 'unblocked' AND relock_at IS NULL AND blocked_again_at IS NULL " \
               "ORDER BY ended_at DESC LIMIT 1)", [event.fetch("relock_at").to_f, event.fetch("site")])
  when "blocked_again"
    db.execute("UPDATE attempts SET blocked_again_at = ? WHERE site = ? AND outcome = 'unblocked' " \
               "AND blocked_again_at IS NULL", [at, event.fetch("site")])
  else
    abort "unknown event type: #{event["type"]}"
  end
end

def blank_to_nil(text)
  text.nil? || text.strip.empty? ? nil : text.strip
end

# What the attempt's outcome counts as, with ones left hanging resolved.
def outcome_of(row, now = Time.now.to_f)
  return row["outcome"] if row["outcome"]
  now - row["started_at"] > INTERRUPTED_AFTER ? "interrupted" : "in_progress"
end

# How long an unblock kept the site open.
def open_seconds(row, now = Time.now.to_f)
  return 0 unless row["outcome"] == "unblocked" && row["ended_at"]
  closed = row["blocked_again_at"] || [row["relock_at"] || row["ended_at"] + RELOCK_SECONDS, now].min
  [closed - row["ended_at"], 0].max
end

def stats
  now = Time.now.to_f
  rows = db.execute("SELECT * FROM attempts WHERE started_at >= ?", [now - WEEK])
  summarize = lambda do |list|
    ended = list.map { |r| outcome_of(r, now) }
    {
      attempts: ended.count { |o| o != "in_progress" },
      # Everything but an unblock left the site blocked -- a dismissed
      # password prompt included.
      stayed: ended.count { |o| !%w[unblocked in_progress].include?(o) },
      unblocked: ended.count("unblocked"),
      unblocked_seconds: list.sum { |r| open_seconds(r, now) }.round,
    }
  end

  sites = rows.group_by { |r| r["site"] }.transform_values(&summarize)
  # The reason behind each unblock that is still open, for the panel's rows.
  db.execute("SELECT site, reason FROM attempts WHERE outcome = 'unblocked' AND blocked_again_at IS NULL " \
             "AND COALESCE(relock_at, ended_at + ?) > ? ORDER BY ended_at", [RELOCK_SECONDS, now]).each do |r|
    next if r["reason"].nil?
    (sites[r["site"]] ||= summarize.call([]))[:open_reason] = r["reason"]
  end
  { week: summarize.call(rows), sites: sites }
end

def fmt_time(t)
  Time.at(t).strftime("%a %d %b %H:%M")
end

def fmt_duration(seconds)
  seconds = seconds.round
  return "#{seconds}s" if seconds < 60
  return "#{seconds / 60}m" if seconds < 3600
  "#{seconds / 3600}h #{(seconds % 3600) / 60}m"
end

def reasons(site)
  rows = db.execute("SELECT * FROM attempts WHERE reason IS NOT NULL #{site ? "AND site = ?" : ""} " \
                    "ORDER BY started_at DESC", site ? [site] : [])
  return puts("No reasons recorded yet.") if rows.empty?
  rows.each do |r|
    extra = r["outcome"] == "unblocked" ? ", open #{fmt_duration(open_seconds(r))}" : ""
    puts "#{fmt_time(r["started_at"])}  #{r["label"]} (#{outcome_of(r).tr("_", " ")}#{extra})"
    puts "  #{r["reason"]}", ""
  end
end

def attempt_rows(limit)
  db.execute("SELECT a.*, p.source, p.text, (SELECT COUNT(*) FROM views v WHERE v.attempt_id = a.id) AS shown " \
             "FROM attempts a LEFT JOIN passages p ON p.id = COALESCE(a.passage_id, " \
             "(SELECT v.passage_id FROM views v WHERE v.attempt_id = a.id ORDER BY v.seq DESC LIMIT 1)) " \
             "ORDER BY a.started_at DESC LIMIT ?",
             [limit])
end

def attempts(limit)
  rows = attempt_rows(limit)
  return puts("No attempts recorded yet.") if rows.empty?
  rows.each do |r|
    line = "#{fmt_time(r["started_at"])}  #{r["label"].ljust(12)} #{outcome_of(r).tr("_", " ").ljust(14)}"
    line += " #{r["wpm"]} wpm, #{fmt_duration(r["typing_seconds"])}" if r["wpm"]
    line += ", #{r["shown"]} passages" if r["shown"].to_i > 1
    line += ", open #{fmt_duration(open_seconds(r))}" if r["outcome"] == "unblocked"
    puts line.rstrip
    puts "  #{r["passage_id"] ? "typed:" : "shown:"} #{passage_name(r)}" if r["text"]
    puts "  why:   #{r["reason"]}" if r["reason"]
  end
end

def passage_name(row)
  opening = row["text"].split.first(8).join(" ")
  row["source"].to_s.empty? ? %("#{opening}...") : %(#{row["source"]} -- "#{opening}...")
end

# For each passage: times shown, skipped for another, on screen when you
# walked away, and typed out in full before keeping the block or unblocking.
def passage_rows
  db.execute(<<~SQL)
    SELECT p.id, p.text, p.source,
      COUNT(*) AS shown,
      SUM(v.seq < (SELECT MAX(seq) FROM views w WHERE w.attempt_id = v.attempt_id)) AS skipped,
      SUM(v.completed = 0 AND a.outcome = 'walked_away'
          AND v.seq = (SELECT MAX(seq) FROM views w WHERE w.attempt_id = v.attempt_id)) AS walked_away,
      SUM(v.completed = 1 AND a.outcome IN ('kept_blocked', 'auth_dismissed', 'failed')) AS kept_blocked,
      SUM(v.completed = 1 AND a.outcome = 'unblocked') AS unblocked
    FROM views v JOIN passages p ON p.id = v.passage_id JOIN attempts a ON a.id = v.attempt_id
    GROUP BY p.id
    ORDER BY (walked_away + kept_blocked) * 1.0 / COUNT(*) DESC, shown DESC
  SQL
end

def passages
  rows = passage_rows
  return puts("No passages shown yet.") if rows.empty?
  puts "shown  skipped  walked away  kept blocked  unblocked  passage"
  rows.each do |r|
    puts format("%5d  %7d  %11d  %12d  %9d  %s", r["shown"], r["skipped"], r["walked_away"],
                r["kept_blocked"], r["unblocked"], passage_name(r))
  end
end

def opening(text)
  words = text.to_s.split
  words.first(12).join(" ") + (words.length > 12 ? "..." : "")
end

# Everything the widget's history tab shows, in one read.
def history
  now = Time.now.to_f
  {
    stats: stats,
    attempts: attempt_rows(100).map do |r|
      {
        started_at: r["started_at"], site: r["site"], label: r["label"], outcome: outcome_of(r, now),
        reason: r["reason"], wpm: r["wpm"], typing_seconds: r["typing_seconds"]&.round, typos: r["typos"],
        shown: r["shown"], open_seconds: r["outcome"] == "unblocked" ? open_seconds(r, now).round : nil,
        passage_source: r["source"], passage_opening: r["text"] && opening(r["text"]),
      }
    end,
    passages: passage_rows.map do |r|
      {
        source: r["source"], opening: opening(r["text"]), shown: r["shown"], skipped: r["skipped"],
        walked_away: r["walked_away"], kept_blocked: r["kept_blocked"], unblocked: r["unblocked"],
      }
    end,
  }
end

command, *args = ARGV
case command
when "record" then record(JSON.parse(args.fetch(0)))
when "stats" then puts JSON.generate(stats)
when "history" then puts JSON.generate(history)
when "reasons" then reasons(args[0])
when "attempts" then attempts((args[0] || 20).to_i)
when "passages" then passages
else
  warn File.read(__FILE__).lines.drop(1).take_while { |l| l.start_with?("#") }.map { |l| l.sub(/^# ?/, "") }.join
  exit 2
end
