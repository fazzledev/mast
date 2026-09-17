module Mast
  module Reports
    # The widget's week at a glance: attempts finished, battles won, unblocks
    # and how long they kept sites open -- overall and per site -- plus the
    # reason behind each unblock still open, for the panel's rows.
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
        { week: summarize(attempts), sites: sites }
      end

      private

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
