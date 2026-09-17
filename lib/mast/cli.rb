module Mast
  # bin/mast-db: the widget writes through `record` and reads `stats` and
  # `history`; the rest is for looking back from a terminal.
  #
  #   mast-db [-e ENV] reasons [SITE]   why you wanted each site, newest first
  #   mast-db [-e ENV] attempts [N]     the last N attempts (default 20)
  #   mast-db [-e ENV] passages         which passages won battles, and which lost them
  #   mast-db [-e ENV] stats            the week at a glance, as JSON
  #   mast-db [-e ENV] history          attempts and passages for the history tab, as JSON
  #   mast-db [-e ENV] record JSON      store one event from the widget
  #   mast-db [-e ENV] migrate          bring the database up to date (every command does)
  #
  # -e picks the environment, as MAST_ENV does: production (the default) or test.
  class CLI
    USAGE = File.read(__FILE__)[/^  # bin\/mast-db.*?(?=^  class)/m].gsub(/^  # ?/, "")

    def self.start(argv) = new.run(argv.dup)

    def run(argv)
      if %w[-e --environment].include?(argv.first)
        argv.shift
        ENV["MAST_ENV"] = argv.shift
        Mast.reset_db!
      end
      command, *args = argv
      case command
      when "record" then EventsController.dispatch(JSON.parse(args.fetch(0)))
      when "stats" then puts JSON.generate(Reports::Stats.new.as_json)
      when "history" then puts JSON.generate(Reports::History.new.as_json)
      when "reasons" then reasons(args[0])
      when "attempts" then attempts((args[0] || 20).to_i)
      when "passages" then passages
      when "migrate" then Mast.db
      else
        warn USAGE
        return 2
      end
      0
    end

    private

    def reasons(site)
      list = Attempt.with_reasons(site)
      return puts("No reasons recorded yet.") if list.empty?
      list.each do |a|
        open = a.unblocked? ? ", open #{duration(a.open_seconds)}" : ""
        puts "#{time(a.started_at)}  #{a.label} (#{a.status.tr("_", " ")}#{open})"
        puts "  #{a.reason}", ""
      end
    end

    def attempts(limit)
      list = Attempt.recent(limit)
      return puts("No attempts recorded yet.") if list.empty?
      list.each do |a|
        line = "#{time(a.started_at)}  #{a.label.ljust(12)} #{a.status.tr("_", " ").ljust(14)}"
        line += " #{a.wpm} wpm, #{duration(a.typing_seconds)}" if a.wpm
        line += ", #{a.shown} passages" if a.shown.to_i > 1
        line += ", open #{duration(a.open_seconds)}" if a.unblocked?
        puts line.rstrip
        if a.passage_text
          name = Passage.new(text: a.passage_text, source: a.passage_source).name
          puts "  #{a.passage_id ? "typed:" : "shown:"} #{name}"
        end
        puts "  why:   #{a.reason}" if a.reason
      end
    end

    def passages
      list = Passage.scoreboard
      return puts("No passages shown yet.") if list.empty?
      puts "shown  skipped  walked away  kept blocked  unblocked  passage"
      list.each do |p|
        puts format("%5d  %7d  %11d  %12d  %9d  %s", p.shown, p.skipped, p.walked_away, p.kept_blocked,
                    p.unblocked, p.name)
      end
    end

    def time(t) = Time.at(t).strftime("%a %d %b %H:%M")

    def duration(seconds)
      seconds = seconds.round
      return "#{seconds}s" if seconds < 60
      return "#{seconds / 60}m" if seconds < 3600
      "#{seconds / 3600}h #{(seconds % 3600) / 60}m"
    end
  end
end
