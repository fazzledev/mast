module Mast
  # One flip of a blocked site's switch, from the first passage to how it
  # ended.
  #
  # Outcomes: walked_away (Esc while typing), kept_blocked (said no at the
  # end), unblocked, auth_dismissed (closed the password prompt), and failed.
  # One with no outcome is in progress, or -- once INTERRUPTED_AFTER has passed
  # -- was cut off before the widget could report it.
  class Attempt < Record
    OUTCOMES = %w[walked_away kept_blocked unblocked auth_dismissed failed].freeze
    INTERRUPTED_AFTER = 3 * 3600
    # The helper's default relock. Stands in for an unblock whose relock and
    # re-block the widget never saw, say because the shell was restarted.
    RELOCK_SECONDS = 15 * 60
    WEEK = 7 * 24 * 3600

    def self.since(time)
      where("started_at >= ?", time, order: "started_at")
    end

    def self.with_reasons(site = nil)
      return where("reason IS NOT NULL", order: "started_at DESC") unless site
      where("reason IS NOT NULL AND site = ?", site, order: "started_at DESC")
    end

    # Newest first, each with the passage it ended on -- the one typed in
    # full, or else the last one shown -- and how many passages it went
    # through.
    def self.recent(limit = 20)
      find_by_sql(<<~SQL, [limit])
        SELECT a.*, p.text AS passage_text, p.source AS passage_source,
          (SELECT COUNT(*) FROM passage_views v WHERE v.attempt_id = a.id) AS shown
        FROM attempts a
        LEFT JOIN passages p ON p.id = COALESCE(a.passage_id,
          (SELECT v.passage_id FROM passage_views v WHERE v.attempt_id = a.id ORDER BY v.seq DESC LIMIT 1))
        ORDER BY a.started_at DESC
        LIMIT ?
      SQL
    end

    # Unblocks whose site has not been seen blocked again.
    def self.still_unblocked(site = nil)
      clause = "outcome = 'unblocked' AND blocked_again_at IS NULL"
      site ? where("#{clause} AND site = ?", site, order: "ended_at") : where(clause, order: "ended_at")
    end

    # The newest unblock of the site still waiting to learn its relock time.
    def self.awaiting_relock(site)
      where("outcome = 'unblocked' AND relock_at IS NULL AND blocked_again_at IS NULL AND site = ?", site,
            order: "ended_at DESC", limit: 1).first
    end

    # The outcome, or in_progress / interrupted for one without.
    def status(now = Time.now.to_f)
      return outcome if outcome
      now - started_at > INTERRUPTED_AFTER ? "interrupted" : "in_progress"
    end

    def in_progress?(now = Time.now.to_f) = status(now) == "in_progress"
    def unblocked? = outcome == "unblocked"

    # Anything that left the site blocked -- a closed password prompt and a
    # cut-off attempt included.
    def won?(now = Time.now.to_f) = !unblocked? && !in_progress?(now)

    # When the site blocks, or is expected to block, again.
    def closes_at
      blocked_again_at || relock_at || (ended_at && ended_at + RELOCK_SECONDS)
    end

    def still_open?(now = Time.now.to_f) = unblocked? && blocked_again_at.nil? && closes_at > now

    # How long the unblock kept the site open, so far.
    def open_seconds(now = Time.now.to_f)
      return 0 unless unblocked? && ended_at
      [[closes_at, now].min - ended_at, 0].max
    end

    def passage_opening(words = 12)
      return nil unless self["passage_text"]
      Passage.new(text: self["passage_text"], source: self["passage_source"]).opening(words)
    end
  end
end
