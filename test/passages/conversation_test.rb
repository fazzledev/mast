require_relative "../test_helper"

class ConversationTest < Minitest::Test
  PARAGRAPH = "Scrolling eats the hours we meant for work and rest alike, and we rarely notice it happening. "

  def entry(rights: "Licensed as Creative Commons – attribution, no derivatives.", author: "Jane Doe, Lecturer, University of Somewhere", body: PARAGRAPH * 12)
    <<~XML
      <entry>
        <link rel="alternate" type="text/html" href="https://theconversation.com/scrolling-#{body.length}"/>
        <title>Why we can’t stop scrolling &amp; what helps</title>
        <content type="html">&lt;p&gt;#{body}&lt;/p&gt;&lt;p class="fine-print"&gt;Disclosure&lt;/p&gt;</content>
        <author><name>#{author}</name></author>
        <author><name>John Roe</name></author>
        <rights>#{rights}</rights>
      </entry>
    XML
  end

  FakeHTTP = Struct.new(:body) do
    def get(_url) = body
  end

  def candidates(*entries)
    feed = "<feed>#{entries.join}</feed>"
    Mast::Passages::Sources::Conversation.new({ "topics" => ["social-media-109"] }, http: FakeHTTP.new(feed)).candidates
  end

  def test_licensed_articles_become_credited_excerpts
    candidate = candidates(entry).first

    assert_equal %(Jane Doe and John Roe, "Why we can't stop scrolling & what helps", The Conversation), candidate["source"]
    assert_equal "CC BY-ND 4.0", candidate["license"]
    assert_equal "https://creativecommons.org/licenses/by-nd/4.0/", candidate["license_url"]
    assert candidate["text"].start_with?("Scrolling eats the hours")
    refute_includes candidate["text"], "Disclosure"
  end

  def test_other_licences_are_left_out
    assert_empty candidates(entry(rights: "All rights reserved"))
  end

  def test_nothing_is_changed_beyond_typography
    assert_empty candidates(entry(body: "Café life. " + PARAGRAPH * 12))
    assert_empty candidates(entry(author: "José García"))
  end
end
