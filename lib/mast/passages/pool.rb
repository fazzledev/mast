module Mast
  module Passages
    # The cached pool the widget reads: a list of { text, source, url, family,
    # score }, where family is the book, blog or site a passage came from.
    #
    # Refreshed at most weekly. A source that fails to download keeps its
    # passages from last time. If ranking fails, the old pool stays as it is;
    # keyword picks are used only when there is no old pool, or when ranking
    # is turned off.
    class Pool
      MAX_AGE = 7 * 24 * 3600
      KEEP_SCORE = 7
      KEEP_PER_FAMILY = 6

      def initialize(path: Passages.pool_path, ranker: Ranker.new, sources: self.class.sources)
        @path = path
        @ranker = ranker
        @sources = sources
      end

      def self.sources
        config = Passages.config
        config.fetch("books").map { |c| Sources::Gutenberg.new(c) } +
          config.fetch("blogs").map { |c| Sources::Blog.new(c) } +
          [Sources::Conversation.new(config.fetch("conversation"))]
      end

      def fresh? = File.exist?(@path) && Time.now - File.mtime(@path) < MAX_AGE

      def previous
        JSON.parse(File.read(@path))
      rescue StandardError
        []
      end

      # Returns true if a new pool was written.
      def refresh(force: false, rank: true)
        return false if !force && fresh?
        FileUtils.mkdir_p(File.dirname(@path))
        old = previous

        candidates = []
        kept = []
        @sources.each do |source|
          got = source.candidates
          raise "no passages" if got.empty?
          candidates.concat(got)
        rescue StandardError => e
          warn "#{source.family}: #{e.message}"
          kept.concat(old.select { |p| p["family"] == source.family })
        end

        scores = score(candidates, rank: rank, fallback_allowed: old.empty?) or return false
        pool = kept + keep(candidates, scores)
        if pool.empty?
          warn "no passages scored high enough; keeping the old pool"
          return false
        end
        File.write("#{@path}.tmp", JSON.pretty_generate(pool))
        File.rename("#{@path}.tmp", @path)
        warn "#{pool.length} passages from #{candidates.length} candidates"
        true
      end

      private

      def score(candidates, rank:, fallback_allowed:)
        raise "turned off" unless rank
        @ranker.scores(candidates)
      rescue StandardError => e
        warn "ranking: #{e.message}"
        return nil unless fallback_allowed || !rank
        # Keyword picks beat an empty pool.
        Array.new(candidates.length, KEEP_SCORE)
      end

      def keep(candidates, scores)
        per_family = Hash.new(0)
        scores.zip(candidates).sort_by { |s, _| -s }.filter_map do |s, c|
          # The Conversation is many writers, so it gets a bigger share.
          cap = KEEP_PER_FAMILY * (c["family"] == "The Conversation" ? 2 : 1)
          next if s < KEEP_SCORE || per_family[c["family"]] >= cap
          per_family[c["family"]] += 1
          c.merge("score" => s)
        end
      end
    end
  end
end
