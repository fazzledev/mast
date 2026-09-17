require_relative "../test_helper"

class AttemptTest < Mast::TestCase
  def test_status_is_the_outcome_or_in_progress_until_cut_off
    now = Time.now.to_f
    running = Mast::Attempt.new(started_at: now - 60)
    cut_off = Mast::Attempt.new(started_at: now - Mast::Attempt::INTERRUPTED_AFTER - 1)

    assert_equal "in_progress", running.status(now)
    assert_equal "interrupted", cut_off.status(now)
    assert_equal "kept_blocked", Mast::Attempt.new(started_at: now, outcome: "kept_blocked").status(now)
  end

  def test_everything_but_an_unblock_wins_once_finished
    now = Time.now.to_f
    %w[walked_away kept_blocked auth_dismissed failed].each do |outcome|
      assert Mast::Attempt.new(started_at: now, outcome: outcome).won?(now), outcome
    end
    refute Mast::Attempt.new(started_at: now, outcome: "unblocked").won?(now)
    refute Mast::Attempt.new(started_at: now).won?(now)
  end

  def test_open_seconds_runs_to_the_block_or_the_relock_or_now
    now = Time.now.to_f
    blocked = Mast::Attempt.new(outcome: "unblocked", ended_at: now - 1000, blocked_again_at: now - 400)
    relocking = Mast::Attempt.new(outcome: "unblocked", ended_at: now - 100, relock_at: now + 500)
    unseen = Mast::Attempt.new(outcome: "unblocked", ended_at: now - 5000)

    assert_equal 600, blocked.open_seconds(now)
    assert_equal 100, relocking.open_seconds(now)
    assert_equal Mast::Attempt::RELOCK_SECONDS, unseen.open_seconds(now)
    assert_equal 0, Mast::Attempt.new(outcome: "kept_blocked", ended_at: now).open_seconds(now)
  end

  def test_recent_carries_the_passage_it_ended_on
    attempt("a1", outcome: "walked_away", text: "The one on screen when I left")

    recent = Mast::Attempt.recent.first
    assert_equal "The one on screen when I left", recent.passage_text
    assert_equal 1, recent.shown
  end
end
