require_relative "../test_helper"

class ConversationTest < Minitest::Test
  FEED = <<~XML
    <feed xmlns="http://www.w3.org/2005/Atom">
      <entry>
        <link rel="alternate" type="text/html" href="https://theconversation.com/scrolling-123"/>
        <title>Why we can’t stop scrolling &amp; what helps</title>
        <content type="html">&lt;p&gt;#{"Scrolling eats the hours we meant for work and rest alike. " * 30}&lt;/p&gt;&lt;p class="fine-print"&gt;Disclosure&lt;/p&gt;</content>
        <author><name>Jane Doe, Lecturer, University of Somewhere</name></author>
        <author><name>John Roe</name></author>
      </entry>
    </feed>
  XML

  FakeHTTP = Struct.new(:body) do
    def get(_url) = body
  end

  def test_entries_become_articles_with_credit
    source = Mast::Passages::Sources::Conversation.new({ "topics" => ["social-media-109"] }, http: FakeHTTP.new(FEED))
    candidate = source.candidates.first

    assert_equal %(Jane Doe et al., "Why we can't stop scrolling & what helps" (The Conversation)), candidate["source"]
    assert_equal "https://theconversation.com/scrolling-123", candidate["url"]
    assert candidate["text"].start_with?("Scrolling eats the hours")
    refute_includes candidate["text"], "Disclosure"
  end
end
