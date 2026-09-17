require "yaml"
require_relative "../mast"

module Mast
  # The passages Mast ships with, and the tooling that builds them. Nothing
  # here runs in the widget: it reads config/passages.json, which is committed.
  #
  #   config/books.yml          public domain books, cut to the chapters about
  #                             time, habit, attention and self-command
  #   config/articles.yml       The Conversation's topic feeds, CC BY-ND
  #   rake passages:candidates  cuts every book into candidate passages, in
  #                             tmp/candidates/BOOK.json, for reading through
  #   config/passage_picks.yml  the candidates chosen, by id, per book
  #   rake passages:build       writes the chosen ones to config/passages.json
  #
  # Cutting is mechanical (Passages::Text): passages start at a paragraph, end
  # at a sentence, run roughly as long as the hand-written ones in
  # config/paragraphs.txt, and are flattened to ASCII so everything in them can
  # be typed. Choosing is not: a person reads the candidates and picks the ones
  # that would make someone stop before unblocking a site.
  module Passages
    USER_AGENT = "fazzledev-mast/1.0 (passage builder)"

    def self.sources
      config = ->(name) { YAML.safe_load_file(File.join(Mast.root, "config", name)) }
      config.("books.yml").fetch("books").map { |c| Sources::Gutenberg.new(c) } +
        [Sources::Conversation.new(config.("articles.yml").fetch("conversation"))]
    end

    def self.picks_path = File.join(Mast.root, "config", "passage_picks.yml")
    def self.catalog_path = File.join(Mast.root, "config", "passages.json")
    def self.candidates_dir = File.join(Mast.root, "tmp", "candidates")

    def self.write_candidates
      FileUtils.mkdir_p(candidates_dir)
      sources.each do |source|
        list = source.candidates
        File.write(File.join(candidates_dir, "#{source.key}.json"), JSON.pretty_generate(list))
        warn "#{list.length.to_s.rjust(4)} candidates  #{source.source}"
      end
    end

    # The picked candidates, in the order the picks list them. A pick no longer
    # among the candidates -- an article that has left its feed -- is kept as
    # already shipped. Fails loudly on one that is neither, say because a
    # book's text or the cutting changed.
    def self.build
      picks = YAML.safe_load_file(picks_path) || {}
      shipped = File.exist?(catalog_path) ? JSON.parse(File.read(catalog_path)).to_h { |p| [p["id"], p] } : {}
      catalog = sources.flat_map do |source|
        wanted = Array(picks[source.key])
        next [] if wanted.empty?
        found = source.candidates.to_h { |c| [c["id"], c] }.merge(shipped.slice(*wanted)) { |_, cut, _| cut }
        missing = wanted - found.keys
        raise "#{source.key}: no candidate for #{missing.join(", ")}" unless missing.empty?
        wanted.map { |id| found.fetch(id) }
      end
      File.write(catalog_path, JSON.pretty_generate(catalog) + "\n")
      warn "#{catalog.length} passages in #{catalog_path}"
      catalog
    end
  end
end

require_relative "passages/text"
require_relative "passages/http"
require_relative "passages/sources/gutenberg"
require_relative "passages/sources/conversation"
