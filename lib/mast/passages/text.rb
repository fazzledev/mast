module Mast
  module Passages
    # Turning fetched text into passages that can be typed.
    module Text
      MIN_WORDS = 150
      MAX_WORDS = 240

      TOPIC = Regexp.new(
        '\b(attention|focus\w*|distract\w*|concentrat\w*|deep work|depth|phones?|smartphones?|' \
        'social media|scroll\w*|screens?|internet|online|feeds?|apps?|algorithm\w*|addict\w*|compuls\w*|' \
        'habits?|routine\w*|disciplin\w*|procrastinat\w*|postpon\w*|delay\w*|willpower|resol\w*|' \
        'identity|goals?|practice|deliberate|craft|meaningful|improve\w*|progress|solitude|boredom|' \
        'wast\w*|idle\w*|idleness|trifl\w*|leisure|busy|pleasures?|time|hours?|days?|minutes|years|' \
        'life|lives|work|labour|effort|character|desires?)\b', Regexp::IGNORECASE)

      # Housekeeping that has no place in a passage about focus.
      NOISE = Regexp.new(
        'subscribe|newsletter|podcast|episode|click|sign up|https?:|www\.|sponsor|affiliate|' \
        'pre-?order|book tour|webinar|coupon|discount|this article|(our|my) course|registration',
        Regexp::IGNORECASE)

      ASCII = {
        "‘" => "'", "’" => "'", "‚" => "'", "‛" => "'",
        "“" => '"', "”" => '"', "„" => '"',
        "—" => "--", "–" => "-", "‒" => "-", "‐" => "-", "‑" => "-",
        "…" => "...", " " => " ", " " => " ", " " => " ", " " => " ",
        "æ" => "ae", "Æ" => "Ae", "œ" => "oe", "Œ" => "Oe",
        "é" => "e", "è" => "e", "ê" => "e", "ë" => "e", "ï" => "i", "ö" => "o",
        "ü" => "u",
      }.freeze

      ENTITIES = {
        "amp" => "&", "lt" => "<", "gt" => ">", "quot" => '"', "apos" => "'", "nbsp" => " ",
        "hellip" => "...", "mdash" => "--", "ndash" => "-",
        "lsquo" => "'", "rsquo" => "'", "ldquo" => '"', "rdquo" => '"',
      }.freeze

      SENTENCE_END = /(?<=[.!?]|[.!?]["')])\s+(?=["'(]?[A-Z])/

      module_function

      # Whitespace-collapsed ASCII, or nil if something untypeable is left.
      def plain(text)
        text = text.each_char.map { |c| ASCII.fetch(c, c) }.join
        text = text.gsub(/\{\d+\}/, "")                                               # Gutenberg page numbers
        text = text.gsub(/\+?\[(\d+|[A-Z])\]/, "")                                    # footnote markers, [1] or [A]
        text = text.gsub(/\[Greek:[^\]]*\]\s?/, "")                                   # transliterated Greek
        text = text.gsub(/\[([^\]]+)\]/, '\1')                                        # editors' insertions, kept
        text = text.gsub(/(?<=\s)\+(?=\s)|\+(?=[\s,.;:]|\z)/, "")                     # doubtful-reading marks
        text = text.gsub(/(?<=[a-z][.,;:!?"')]|[a-z][.!?]["')])\d+(?=\s|\z)/, "")    # ...and superscript ones
        text = text.gsub(/(?<!\w)_(.+?)_(?!\w)/, '\1')                                # _italics_
        text = text.gsub(/\s+/, " ").strip
        text.match?(/[^\x20-\x7e]/) ? nil : text
      end

      # Entities decoded, and nothing else touched.
      def unescape(text)
        text.gsub(/&(#x\h+|#\d+|\w+);/) do
          ref = Regexp.last_match(1)
          if ref.start_with?("#x") then ref[2..].to_i(16).chr(Encoding::UTF_8)
          elsif ref.start_with?("#") then ref[1..].to_i.chr(Encoding::UTF_8)
          else ENTITIES.fetch(ref, "&#{ref};")
          end
        end
      end

      def html_text(fragment) = plain(unescape(fragment.gsub(/<[^>]+>/, "")))

      def html_paragraphs(html) = html.scan(%r{<p[^>]*>(.*?)</p>}m).map(&:first)

      # [first, last, text] passages that start at a paragraph and end at a
      # sentence, in range. A nil paragraph is a break no passage runs across.
      def windows(paragraphs)
        sentences = [] # [sentence, starts a paragraph, run]
        run = 0
        paragraphs.each do |p|
          if p.nil?
            run += 1
            next
          end
          p.split(SENTENCE_END).map(&:strip).reject(&:empty?).each_with_index do |s, i|
            sentences << [s, i.zero?, run]
          end
        end

        out = []
        sentences.each_with_index do |(_, starts, run_of_start), i|
          next unless starts
          words = 0
          (i...sentences.length).each do |j|
            break if sentences[j][2] != run_of_start
            words += sentences[j][0].split.length
            break if words > MAX_WORDS
            # A passage leading into a quote or list has no ending.
            if words >= MIN_WORDS && !sentences[j][0].match?(/(:|--)\W*\z/)
              out << [i, j, sentences[i..j].map(&:first).join(" ")]
              break
            end
          end
        end
        out
      end

      def topic_score(text) = text.scan(TOPIC).flatten.map(&:downcase).uniq.length

      # The best non-overlapping spans by keyword score, sampled for variety.
      def shortlist(spans, limit)
        picked = []
        spans.sort_by { |s| -topic_score(s[2]) }.each do |span|
          picked << span unless picked.any? { |p| span[0] <= p[1] && p[0] <= span[1] }
          break if picked.length >= limit * 2
        end
        picked.shuffle.first(limit).map { |s| s[2] }
      end
    end
  end
end
