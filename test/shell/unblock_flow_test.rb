require_relative "shell_helper"

class UnblockFlowTest < ShellTest::TestCase
  def test_start_opens_the_overlay_in_test_mode
    s = start
    assert s["testMode"]
    assert s["open"]
    assert s["overlayVisible"]
    assert_equal "youtube", s["site"]
    refute_empty s["attempt"]
    refute_empty s["passage"]
    assert_match %r{\A0/\d+\z}, s["progress"]
    refute s["asking"]
  end

  def test_nothing_to_type_or_answer_without_an_attempt
    assert_equal "not typing", ipc("type", 1)
    assert_equal "not typing", ipc("hide")
    assert_equal "not asking", ipc("reason", "no attempt here")
    assert_equal "no test attempt", ipc("answer", "yes")
  end

  def test_walking_away
    start
    assert_equal "closed", ipc("answer", "esc")
    refute state["overlayVisible"]
    attempt = history["attempts"].first
    assert_equal "walked_away", attempt["outcome"]
    assert_equal "youtube", attempt["site"]
    assert_equal 1, attempt["shown"]
  end

  def test_typing_then_keeping_the_block
    start("twitter")
    s = type_passage
    assert_match %r{\A(\d+)/\1\z}, s["progress"]
    assert_operator s["summary"]["wpm"], :>, 0
    assert_operator s["summary"]["words"], :>, 100

    assert_equal "still open: reason missing", ipc("answer", "yes")
    assert state["reasonMissing"]

    assert_equal "ok", ipc("reason", "just to check one thing")
    assert_equal "closed", ipc("answer", "no")
    attempt = history["attempts"].first
    assert_equal "kept_blocked", attempt["outcome"]
    assert_equal "twitter", attempt["site"]
    assert_equal "just to check one thing", attempt["reason"]
    assert_operator attempt["wpm"], :>, 0
  end

  def test_yes_records_an_unblock_but_unblocks_nothing
    before = helper_status
    start
    type_passage
    ipc("reason", "a lecture I need for work")
    assert_equal "closed", ipc("answer", "yes")
    attempt = history["attempts"].first
    assert_equal "unblocked", attempt["outcome"]
    assert_equal "a lecture I need for work", attempt["reason"]
    assert_equal before, helper_status

    ipc("stop")
    s = start
    assert_equal 1, s["stats"]["week"]["attempts"]
    assert_equal 1, s["stats"]["week"]["unblocked"]
  end

  def test_yes_waits_out_the_cool_off
    settings(coolOffSeconds: 30)
    start
    type_passage
    ipc("reason", "waiting is part of it")
    assert_match(/\Astill open: yes available in \d+s\z/, ipc("answer", "yes"))
    assert_operator state["coolOffLeft"], :>, 0
    assert_equal "closed", ipc("answer", "no")
  end

  def test_switching_passages
    first = start["passage"]
    following = ipc("step", 1)
    refute_equal first, following
    assert_equal first, ipc("step", -1)
    refute_equal first, ipc("shuffle")
    ipc("answer", "esc")
    assert_equal 4, history["attempts"].first["shown"]
  end

  def test_switching_can_be_turned_off
    settings(allowSwitching: false)
    first = start["passage"]
    assert_equal first, ipc("step", 1)
    assert_equal first, ipc("shuffle")
  end

  def test_hiding_a_passage
    s = start
    shown, total = s["passages"].split(" of ").map(&:to_i)
    hidden = s["passage"]
    ipc("hide")
    s = state
    refute_equal hidden, s["passage"]
    assert_equal "#{shown - 1} of #{total}", s["passages"]
    ipc("answer", "esc")
    assert history["passages"].find { |p| p["id"] == hidden }["hidden"]

    # Still hidden in a fresh attempt, read back from the database.
    ipc("stop")
    settings
    assert_equal "#{shown - 1} of #{total}", start["passages"]
  end

  def test_news_passages_carry_their_licence
    settings(sourceParagraphs: false, sourceBooks: false)
    s = start
    assert_match %r{\Ahttps://theconversation\.com/}, s["url"]
    assert_equal "CC BY-ND 4.0", s["license"]
    refute_empty s["source"]
  end

  def test_book_passages_link_to_gutenberg
    settings(sourceParagraphs: false, sourceNews: false)
    s = start
    assert_match %r{\Ahttps://www\.gutenberg\.org/ebooks/\d+\z}, s["url"]
    assert_equal "", s["license"]
    refute_empty s["source"]
  end

  def test_settings_screen_and_history
    start
    ipc("answer", "esc")
    wait("writes to finish") { state["dbPending"].zero? }

    assert_equal "ok", ipc("settings", "settings")
    s = wait("the settings screen") { state.then { |x| x["settingsVisible"] && x } }
    assert_equal "settings", s["settingsTab"]

    ipc("settings", "history")
    s = wait("the history") { state.then { |x| x["historyAttempts"] == 1 && x } }
    assert_equal "history", s["settingsTab"]
    assert_equal 1, s["historyPassages"]

    ipc("stop")
    refute state["settingsVisible"]
  end
end
