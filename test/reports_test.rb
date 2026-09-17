require_relative "test_helper"

class ReportsTest < Mast::TestCase
  def test_stats_count_the_week_and_skip_what_is_still_going
    attempt("won1", outcome: "walked_away")
    attempt("won2", outcome: "kept_blocked", site: "twitter")
    attempt("lost", outcome: "unblocked", reason: "one video")
    attempt("old", outcome: "unblocked", at: Time.now.to_f - Mast::Attempt::WEEK - 3600)
    event("start", attempt: "now", site: "youtube", label: "Youtube")

    stats = Mast::Reports::Stats.new.as_json
    assert_equal({ attempts: 3, stayed: 2, unblocked: 1 }, stats[:week].slice(:attempts, :stayed, :unblocked))
    assert_equal 2, stats[:sites]["youtube"][:attempts]
    assert_equal "one video", stats[:sites]["youtube"][:open_reason]
  end

  def test_stats_score_every_passage_and_mark_the_hidden
    attempt("a1", outcome: "walked_away", text: "Winner")
    attempt("a2", outcome: "unblocked", text: "Loser")
    event("hide", passage_id: "never-shown", text: "Hidden unseen", source: "", url: "")

    scores = Mast::Reports::Stats.new.as_json[:passages]
    assert_equal({ won: 1, lost: 0, hidden: false }, scores[Mast::Passage.digest("Winner")])
    assert_equal({ won: 0, lost: 1, hidden: false }, scores[Mast::Passage.digest("Loser")])
    assert_equal({ won: 0, lost: 0, hidden: true }, scores["never-shown"])
  end

  def test_history_scores_passages_by_battles_won
    attempt("a1", outcome: "walked_away", text: "Winner")
    attempt("a2", outcome: "kept_blocked", text: "Winner")
    attempt("a3", outcome: "unblocked", text: "Loser")

    history = Mast::Reports::History.new.as_json
    assert_equal %w[Winner Loser], history[:passages].map { |p| p[:opening] }
    assert_equal [1, 1, 0], history[:passages].first.values_at(:walked_away, :kept_blocked, :unblocked)
    assert_equal %w[a3 a2 a1].length, history[:attempts].length
  end
end
