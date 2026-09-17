module Mast
  module Passages
    module Sources
      # A public domain book, cut to the configured chapters. The text is
      # downloaded once and kept in the cache.
      class Gutenberg
        SHORTLIST = 16

        attr_reader :family

        def initialize(config)
          @id = Integer(config.fetch("id"))
          @family = config.fetch("source")
          @sections = config.fetch("sections")
        end

        def candidates
          url = "https://www.gutenberg.org/ebooks/#{@id}"
          Text.shortlist(Text.windows(paragraphs), SHORTLIST).map do |text|
            { "text" => text, "source" => @family, "url" => url, "family" => @family }
          end
        end

        private

        def book
          path = File.join(Mast.cache_dir, "books", "pg#{@id}.txt")
          unless File.exist?(path)
            FileUtils.mkdir_p(File.dirname(path))
            File.write("#{path}.tmp", HTTP.get("https://www.gutenberg.org/cache/epub/#{@id}/pg#{@id}.txt"))
            File.rename("#{path}.tmp", path)
          end
          File.read(path, encoding: "UTF-8").delete("\r")
        end

        def paragraphs
          text = book
          @sections.flat_map do |section|
            starts = text.to_enum(:scan, /^\s*#{section.fetch("start")}\s*$/).map { Regexp.last_match }
            raise "no section matching #{section["start"].inspect}" if starts.empty?
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
            p = Text.plain(lines.join(" ").sub(/\A\s*[IVXLC]+\.\s+/, ""))
            # Headings and chapter numbers.
            next if p.nil? || p.split.length < 8 || p.upcase == p
            p
          end
        end
      end
    end
  end
end
