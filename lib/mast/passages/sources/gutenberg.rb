require "digest"

module Mast
  module Passages
    module Sources
      # A public domain book from Project Gutenberg, cut to the configured
      # sections -- or, without any, the whole text between Gutenberg's start
      # and end markers. Downloaded once into tmp/books.
      class Gutenberg
        DEFAULT_LIMIT = 60

        attr_reader :key, :source

        def initialize(config)
          @key = config.fetch("key")
          @id = Integer(config.fetch("id"))
          @source = config.fetch("source")
          @sections = config["sections"]
          @limit = config.fetch("limit", DEFAULT_LIMIT)
        end

        def url = "https://www.gutenberg.org/ebooks/#{@id}"

        # Non-overlapping passages, the most on-topic `limit` of them, in the
        # order they appear. The same text always gives the same ids.
        def candidates
          spans = Text.windows(paragraphs)
          picked = []
          spans.sort_by { |s| [-Text.topic_score(s[2]), s[0]] }.each do |span|
            picked << span unless picked.any? { |p| span[0] <= p[1] && p[0] <= span[1] }
            break if picked.length >= @limit
          end
          picked.sort_by(&:first).map do |_, _, text|
            { "id" => "#{@key}-#{Digest::SHA1.hexdigest(text)[0, 10]}", "text" => text, "source" => @source, "url" => url }
          end
        end

        private

        def book
          path = File.join(Mast.root, "tmp", "books", "pg#{@id}.txt")
          unless File.exist?(path)
            FileUtils.mkdir_p(File.dirname(path))
            File.write("#{path}.tmp", HTTP.get("https://www.gutenberg.org/cache/epub/#{@id}/pg#{@id}.txt"))
            File.rename("#{path}.tmp", path)
          end
          File.read(path, encoding: "UTF-8").delete("\r")
        end

        def paragraphs
          text = book
          sections = @sections || [{ "start" => '\*\*\* START OF .*', "stop" => '\*\*\* END OF .*' }]
          sections.flat_map do |section|
            starts = text.to_enum(:scan, /^\s*#{section.fetch("start")}\s*$/).map { Regexp.last_match }
            raise "#{@key}: no section matching #{section["start"].inspect}" if starts.empty?
            from = starts.last.end(0)
            to = text.index(/^\s*#{section.fetch("stop")}\s*$/, from) || text.length
            section_paragraphs(text[from...to]) + [nil]
          end
        end

        def section_paragraphs(body)
          body.split(/\n\s*\n/).filter_map do |block|
            lines = block.split("\n").reject { |l| l.strip.empty? }
            # Verse and block quotes are indented; they read badly run together.
            next if lines.empty? || lines.count { |l| l.start_with?("  ") } > lines.length / 2.0
            # Section numbers (roman or arabic) and run-in capitals headings
            # ("ON ATTENTION.--") are not part of what anyone should type.
            p = Text.plain(lines.join(" ").sub(/\A\s*([IVXLC]+|\d+)\.\s+/, "").sub(/\A[A-Z][A-Z ,;'-]+\.\s*(--|\u2014)\s*/, ""))
            # Headings and chapter numbers.
            next if p.nil? || p.split.length < 8 || p.upcase == p
            p
          end
        end
      end
    end
  end
end
