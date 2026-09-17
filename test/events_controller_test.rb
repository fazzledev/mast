require_relative "test_helper"

class EventsControllerTest < Mast::TestCase
  def test_a_whole_unblock_is_recorded
    t = Time.now.to_f - 3600
    event("start", attempt: "a1", site: "youtube", label: "YouTube", at: t)
    event("passage", attempt: "a1", seq: 0, text: "First", source: "Seneca", url: "u", at: t + 1)
    event("leave", attempt: "a1", seq: 0, chars: 40, at: t + 20)
    event("passage", attempt: "a1", seq: 1, text: "Second", source: "", url: "", at: t + 20)
    event("typed", attempt: "a1", seq: 1, chars: 900, typing_ms: 200_000, wpm: 50, peak_wpm: 70, typos: 3, at: t + 220)
    event("end", attempt: "a1", outcome: "unblocked", reason: "  a Rails talk  ", at: t + 240)
    event("relock", site: "youtube", relock_at: t + 240 + 900)
    event("blocked_again", site: "youtube", at: t + 240 + 900)

    a = Mast::Attempt.find("a1")
    assert_equal "unblocked", a.outcome
    assert_equal "a Rails talk", a.reason
    assert_equal Mast::Passage.digest("Second"), a.passage_id
    assert_equal 50, a.wpm
    assert_in_delta 900, a.open_seconds, 0.01

    first, second = Mast::PassageView.where("attempt_id = ?", "a1", order: "seq")
    assert_equal 40, first.chars_typed
    refute first.completed?
    assert second.completed?
  end

  def test_starting_twice_keeps_the_first
    event("start", attempt: "a1", site: "youtube", label: "YouTube", at: 100)
    event("start", attempt: "a1", site: "twitter", label: "X", at: 200)

    assert_equal "youtube", Mast::Attempt.find("a1").site
  end

  def test_a_blank_reason_keeps_the_one_already_given
    attempt("a1", outcome: "kept_blocked", reason: "boredom")
    event("end", attempt: "a1", outcome: "kept_blocked", reason: "  ")

    assert_equal "boredom", Mast::Attempt.find("a1").reason
  end

  def test_a_passage_shown_again_is_one_passage
    attempt("a1", outcome: "walked_away", text: "Same words")
    attempt("a2", outcome: "walked_away", text: "Same words")

    assert_equal 1, Mast::Passage.where.length
  end

  def test_shipped_passages_keep_their_ids
    event("start", attempt: "a1", site: "youtube", label: "YouTube")
    event("passage", attempt: "a1", seq: 0, passage_id: "seneca-shortness-0123456789", text: "Words", source: "Seneca", url: "u")

    assert_equal "Words", Mast::Passage.find("seneca-shortness-0123456789").text
    assert_equal "seneca-shortness-0123456789", Mast::PassageView.find("a1", 0).passage_id
  end

  def test_hiding_a_passage_and_showing_it_again
    event("hide", passage_id: "p1", text: "Never again", source: "", url: "")
    assert Mast::Passage.find("p1").hidden?

    event("hide", passage_id: "p1", text: "Never again", source: "", url: "", hidden: false)
    refute Mast::Passage.find("p1").hidden?
  end

  def test_unknown_events_and_outcomes_are_refused
    assert_raises(Mast::EventsController::UnknownEvent) { event("explode") }
    event("start", attempt: "a1", site: "youtube", label: "YouTube")
    assert_raises(ArgumentError) { event("end", attempt: "a1", outcome: "gave_up") }
  end

  def test_quotes_and_question_marks_survive
    text = %(It's "a passage"? With 'quotes' -- and ?marks)
    attempt("a1", outcome: "kept_blocked", text: text, reason: "why? it's 'fine'")

    assert_equal text, Mast::Passage.find(Mast::Passage.digest(text)).text
    assert_equal "why? it's 'fine'", Mast::Attempt.find("a1").reason
  end
end
