module Mast
  module Reports
    # Everything the widget's history tab shows, in one read.
    class History
      def initialize(now: Time.now.to_f, limit: 100)
        @now = now
        @limit = limit
      end

      def as_json
        {
          stats: Stats.new(now: @now).as_json,
          attempts: Attempt.recent(@limit).map { |a| attempt_json(a) },
          passages: Passage.scoreboard.map { |p| passage_json(p) },
        }
      end

      private

      def attempt_json(a)
        {
          started_at: a.started_at, site: a.site, label: a.label, outcome: a.status(@now),
          reason: a.reason, wpm: a.wpm, typing_seconds: a.typing_seconds&.round, typos: a.typos,
          shown: a.shown, open_seconds: a.unblocked? ? a.open_seconds(@now).round : nil,
          passage_source: a.passage_source, passage_opening: a.passage_opening,
        }
      end

      def passage_json(p)
        {
          id: p.id, text: p.text, source: p.source, url: p.url, opening: p.opening, shown: p.shown,
          skipped: p.skipped, walked_away: p.walked_away, kept_blocked: p.kept_blocked, unblocked: p.unblocked,
          hidden: p.hidden?,
        }
      end
    end
  end
end
