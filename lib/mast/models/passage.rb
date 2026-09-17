require "digest"

module Mast
  # A passage that has been shown at least once. Shipped passages keep the id
  # config/passages.json gives them; others -- the hand-written ones, and
  # passages recorded before ids existed -- are keyed by the sha1 of their
  # text. `source` and `url` are empty for the hand-written ones.
  class Passage < Record
    def self.digest(text) = Digest::SHA1.hexdigest(text)

    # The passage, created the first time it is seen. A source or link that
    # changed since is brought up to date.
    def self.record(text:, source:, url:, at:, id: nil)
      id ||= digest(text)
      passage = find_by(id: id)
      return create(id: id, text: text, source: source.to_s, url: url.to_s, created_at: at) unless passage
      passage.update(source: source.to_s, url: url.to_s) if passage.source != source.to_s || passage.url != url.to_s
      passage
    end

    def self.hidden = where("hidden_at IS NOT NULL", order: "hidden_at DESC")

    def hidden? = !hidden_at.nil?

    # Every passage shown, with how it fared: times shown, skipped for another
    # passage, on screen when you walked away, and typed out in full before
    # keeping the block or unblocking. The ones that won most often first.
    def self.scoreboard
      find_by_sql(<<~SQL)
        SELECT p.*,
          COUNT(*) AS shown,
          SUM(v.seq < (SELECT MAX(seq) FROM passage_views w WHERE w.attempt_id = v.attempt_id)) AS skipped,
          SUM(v.completed = 0 AND a.outcome = 'walked_away'
              AND v.seq = (SELECT MAX(seq) FROM passage_views w WHERE w.attempt_id = v.attempt_id)) AS walked_away,
          SUM(v.completed = 1 AND a.outcome IN ('kept_blocked', 'auth_dismissed', 'failed')) AS kept_blocked,
          SUM(v.completed = 1 AND a.outcome = 'unblocked') AS unblocked
        FROM passage_views v
        JOIN passages p ON p.id = v.passage_id
        JOIN attempts a ON a.id = v.attempt_id
        GROUP BY p.id
        ORDER BY (walked_away + kept_blocked) * 1.0 / COUNT(*) DESC, shown DESC
      SQL
    end

    def handwritten? = source.to_s.empty?

    # Battles won and lost with this passage on screen, from a scoreboard row.
    def won = self["walked_away"].to_i + self["kept_blocked"].to_i
    def lost = self["unblocked"].to_i

    def opening(words = 12)
      all = text.split
      all.first(words).join(" ") + (all.length > words ? "..." : "")
    end

    def name
      handwritten? ? %("#{opening(8)}") : %(#{source} -- "#{opening(8)}")
    end
  end
end
