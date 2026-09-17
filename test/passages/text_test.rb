require_relative "../test_helper"

class TextTest < Minitest::Test
  Text = Mast::Passages::Text

  def test_plain_flattens_to_typeable_ascii
    assert_equal %(It's "quoted" -- and... done), Text.plain("It’s “quoted” — and…  done")
    assert_equal "social media. What next", Text.plain("social media.3 What next")
    assert_equal "a word with emphasis", Text.plain("a word with _emphasis_{12}")
    assert_nil Text.plain("Greek αβ")
  end

  def test_html_text_strips_tags_and_entities
    assert_equal "It's & done", Text.html_text("It&#8217;s <em>&amp;</em> done")
  end

  def test_windows_start_at_a_paragraph_and_stay_in_range
    sentence = "This sentence has exactly ten words in it, you see."
    paragraphs = Array.new(4) { ([sentence] * 5).join(" ") }
    spans = Text.windows(paragraphs)

    refute_empty spans
    spans.each do |_, _, text|
      assert_includes Text::MIN_WORDS..Text::MAX_WORDS, text.split.length
      assert text.start_with?("This sentence")
    end
  end

  def test_windows_do_not_cross_a_break
    sentence = "Ten words that make up one sentence right here, friend."
    paragraph = ([sentence] * 16).join(" ")
    short = ([sentence] * 5).join(" ")

    assert_empty Text.windows([short, nil, short])
    refute_empty Text.windows([paragraph])
  end
end
