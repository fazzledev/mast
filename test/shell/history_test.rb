require_relative "shell_helper"

# The history tab, row by row: what an attempt and a passage actually read as
# on screen, which the settings test only counted.
class HistoryTest < ShellTest::TestCase
  # An attempt that was typed out and then kept blocked, with a reason, so
  # every line of a row has something in it.
  def record_an_attempt
    start("youtube")
    passage = state["passage"]
    type_passage
    ipc("reason", "checking one thing only")
    ipc("answer", "no")
    wait("writes to finish") { state["dbPending"].zero? }
    passage
  end

  def history_rows(attempts: 1)
    ipc("settings", "history")
    wait("the history tab to show #{attempts} attempts") do
      rows = JSON.parse(ipc("history"))
      rows["attempts"].length == attempts ? rows : nil
    end
  end

  def test_the_week_tiles_read_off_the_record
    record_an_attempt
    tiles = history_rows["tiles"]
    assert_equal 3, tiles.length
    assert_equal "1 of 1 unblock battles won this week", tiles[0]
    assert_match(/\A0 unblocks this week, 0 min open\z/, tiles[1])
    assert_match(/\A\d+ wpm average typing speed, recent attempts\z/, tiles[2])
  end

  def test_an_attempt_row_says_when_what_and_why
    record_an_attempt
    row = history_rows["attempts"].first
    # The helper supplies the label ("YouTube"); without it the site is only
    # ever its name, and these tests run either way.
    assert_match(/youtube/i, row)
    assert_match(/Kept blocked/, row)
    assert_match(/Why: checking one thing only/, row)
    assert_match(/\d+ wpm/, row)
    assert_match(/typing/, row)
  end

  def test_a_passage_row_says_how_it_has_fared
    record_an_attempt
    row = history_rows["passages"].first
    assert_match(/won 1/, row)
    assert_match(/lost 0/, row)
    assert_match(/shown 1/, row)
    assert_match(/skipped 0/, row)
    # Its opening words, in quotes, after the source.
    assert_match(/\| ".+" \|/, row)
  end

  def test_a_hidden_passage_says_so
    record_an_attempt
    before = history_rows["passages"].first
    refute_match(/Hidden/, before)

    start("youtube")
    ipc("hide")
    ipc("answer", "esc")
    wait("writes to finish") { state["dbPending"].zero? }
    hidden = history_rows(attempts: 2)["passages"].find { |r| r.start_with?("Hidden") }
    refute_nil hidden, "the hidden passage is marked in the list"
  end
end
