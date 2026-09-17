module Mast
  module Reports
    # The widget's week at a glance: attempts finished, battles won, unblocks
    # and how long they kept sites open -- overall and per site -- plus the
    # reason behind each unblock still open, for the panel's rows.
    #
    # Also every passage's battles won and lost, all time, and whether it is
    # hidden: the unblock screen favours the passages that win and leaves out
    # the hidden ones.
    class Stats
      def initialize(now: Time.now.to_f)
        @now = now
      end

      def as_json
        attempts = Attempt.since(@now - Attempt::WEEK)
        sites = attempts.group_by(&:site).transform_values { |list| summarize(list) }
        Attempt.still_unblocked.each do |a|
          next unless a.reason && a.still_open?(@now)
          (sites[a.site] ||= summarize([]))[:open_reason] = a.reason
        end
        { week: summarize(attempts), sites: sites, passages: passage_scores }
      end

      private

      def passage_scores
        scores = Passage.scoreboard.to_h { |p| [p.id, { won: p.won, lost: p.lost, hidden: p.hidden? }] }
        Passage.hidden.each { |p| scores[p.id] ||= { won: 0, lost: 0, hidden: true } }
        scores
      end

      def summarize(list)
        finished = list.reject { |a| a.in_progress?(@now) }
        {
          attempts: finished.length,
          stayed: finished.count { |a| a.won?(@now) },
          unblocked: finished.count(&:unblocked?),
          unblocked_seconds: finished.sum { |a| a.open_seconds(@now) }.round,
        }
      end
    end
  end
end
