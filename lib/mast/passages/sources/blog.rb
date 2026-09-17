module Mast
  module Passages
    module Sources
      # Articles, each boiled down to its best passage, and the best of those
      # kept. Subclasses supply `articles` as [source, url, [raw <p> html]].
      class Articles
        attr_reader :family

        # Anything with get(url) -> body; tests pass a fake.
        def http = @http || HTTP

        def candidates
          best = articles.filter_map do |source, url, raw_paragraphs|
            paragraphs = raw_paragraphs.map do |raw|
              p = Text.html_text(raw)
              # Short ones are subheadings and "~~~" dividers: breaks, not text.
              p && !p.match?(Text::NOISE) && p.split.length >= 6 ? p : nil
            end
            top = Text.windows(paragraphs).max_by { |s| Text.topic_score(s[2]) }
            top && { "text" => top[2], "source" => source, "url" => url, "family" => family }
          end
          best.sort_by { |c| -Text.topic_score(c["text"]) }.first(limit * 2).shuffle.first(limit)
        end

        def limit = 16
      end

      # A WordPress blog, searched by topic through its API.
      class Blog < Articles
        def initialize(config, http: nil)
          @http = http
          @base = config.fetch("base")
          @family = config.fetch("author")
          @terms = config.fetch("terms")
        end

        private

        def articles
          posts = {}
          @terms.each do |term|
            query = URI.encode_www_form(search: term, per_page: 20, _fields: "link,title,content")
            JSON.parse(http.get("#{@base}/wp-json/wp/v2/posts?#{query}")).each { |post| posts[post["link"]] = post }
          end
          posts.filter_map do |link, post|
            title = Text.html_text(post["title"]["rendered"])
            title && [%(#{@family}, "#{title}"), link, Text.html_paragraphs(post["content"]["rendered"])]
          end
        end
      end
    end
  end
end
