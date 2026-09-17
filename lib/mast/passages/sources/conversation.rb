require "digest"

module Mast
  module Passages
    module Sources
      # Articles from The Conversation, where researchers write about their
      # fields, read from the topic feeds in config/articles.yml.
      #
      # Its articles are licensed CC BY-ND 4.0, which allows sharing all or
      # part of one with credit and without changing the wording. So only
      # articles the feed marks with that licence are used, an excerpt is only
      # ever whole consecutive sentences, only typographic changes are made
      # (Text.verbatim), and each carries its authors, title, link and licence.
      #
      # A feed lists only its topic's latest two dozen or so articles, so the
      # candidates differ from week to week; rake passages:build keeps the ones
      # already shipped rather than needing to find them again.
      class Conversation
        LICENSE = "CC BY-ND 4.0"
        LICENSE_URL = "https://creativecommons.org/licenses/by-nd/4.0/"
        # How the feed words it, in each entry's <rights>.
        LICENSED = /attribution, no derivatives/i

        attr_reader :key, :source

        def initialize(config, http: nil)
          @key = "conversation"
          @source = "The Conversation"
          @topics = config.fetch("topics")
          @http = http
        end

        # Anything with get(url) -> body; tests pass a fake.
        def http = @http || HTTP

        # Each article's most on-topic passage.
        def candidates
          articles.filter_map do |article|
            paragraphs = article[:paragraphs].map do |raw|
              p = Text.html_verbatim(raw)
              # Short ones are subheadings and dividers: breaks, not text.
              p && !p.match?(Text::NOISE) && p.split.length >= 6 ? p : nil
            end
            top = Text.windows(paragraphs).max_by { |s| Text.topic_score(s[2]) } or next
            {
              "id" => "#{@key}-#{Digest::SHA1.hexdigest(top[2])[0, 10]}", "text" => top[2],
              "source" => %(#{article[:byline]}, "#{article[:title]}", The Conversation), "url" => article[:url],
              "license" => LICENSE, "license_url" => LICENSE_URL,
            }
          end
        end

        private

        def articles
          @topics.each_with_object({}) do |topic, found|
            feed = http.get("https://theconversation.com/topics/#{topic}/articles.atom")
            feed.scan(%r{<entry>(.*?)</entry>}m).each do |(entry)|
              article = parse(entry)
              found[article[:url]] ||= article if article
            end
          end.values
        end

        def parse(entry)
          return nil unless entry[%r{<rights>(.*?)</rights>}m, 1].to_s.match?(LICENSED)
          url = entry[/<link[^>]*href="([^"]+)"/, 1]
          title = Text.verbatim(Text.unescape(entry[%r{<title[^>]*>(.*?)</title>}m, 1].to_s))
          # Names come with their affiliation: "Jane Doe, Lecturer, University of X".
          authors = entry.scan(%r{<author>\s*<name>(.*?)</name>}m).map do |(name)|
            Text.verbatim(Text.unescape(name).split(",").first.to_s)
          end
          # A name that cannot be typed as written is not credited as written.
          return nil if url.nil? || title.nil? || authors.empty? || authors.any? { |a| a.nil? || a.empty? }
          # The content is HTML escaped into the XML. Everything from the
          # disclosure footer on is boilerplate.
          content = Text.unescape(entry[%r{<content[^>]*>(.*?)</content>}m, 1].to_s).split('<p class="fine-print"').first.to_s
          { url: url, title: title, byline: byline(authors), paragraphs: Text.html_paragraphs(content) }
        end

        def byline(authors)
          return authors.first if authors.length == 1
          "#{authors[0..-2].join(", ")} and #{authors.last}"
        end
      end
    end
  end
end
