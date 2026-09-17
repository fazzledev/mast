module Mast
  module Passages
    module Sources
      # The Conversation's topic feeds. Atom, read with a few patterns rather
      # than REXML, which the system Ruby does not ship.
      class Conversation < Articles
        def initialize(config, http: nil)
          @http = http
          @family = "The Conversation"
          @topics = config.fetch("topics")
        end

        # Many writers, so a bigger share than one blog.
        def limit = 32

        private

        def articles
          @topics.each_with_object({}) do |topic, found|
            feed = http.get("https://theconversation.com/topics/#{topic}/articles.atom")
            feed.scan(%r{<entry>(.*?)</entry>}m).each do |(entry)|
              article = parse(entry)
              found[article[1]] = article if article
            end
          end.values
        end

        def parse(entry)
          link = entry[/<link[^>]*href="([^"]+)"/, 1]
          title = Text.plain(Text.unescape(entry[%r{<title[^>]*>(.*?)</title>}m, 1].to_s))
          # Names come with their affiliation: "Jane Doe, Lecturer, University of X".
          authors = entry.scan(%r{<author>\s*<name>(.*?)</name>}m).filter_map do |(name)|
            Text.plain(Text.unescape(name).split(",").first.to_s)
          end.reject(&:empty?)
          return nil if link.nil? || title.nil? || authors.empty?
          byline = authors.first + (authors.length > 1 ? " et al." : "")
          # The content is HTML escaped into the XML. Everything from the
          # disclosure footer on is boilerplate.
          content = Text.unescape(entry[%r{<content[^>]*>(.*?)</content>}m, 1].to_s).split('<p class="fine-print"').first.to_s
          [%(#{byline}, "#{title}" (The Conversation)), link, Text.html_paragraphs(content)]
        end
      end
    end
  end
end
