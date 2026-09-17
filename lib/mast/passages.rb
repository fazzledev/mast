require "yaml"
require_relative "../mast"

module Mast
  # The passages Mast ships with, and the tooling that builds them. Nothing
  # here runs in the widget: it reads config/passages.json, which is committed.
  #
  #   config/books.yml          public domain books, cut to the chapters about
  #                             time, habit, attention and self-command
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

    def self.books
      YAML.safe_load_file(File.join(Mast.root, "config", "books.yml")).fetch("books").map { |c| Sources::Gutenberg.new(c) }
    end

    def self.picks_path = File.join(Mast.root, "config", "passage_picks.yml")
    def self.catalog_path = File.join(Mast.root, "config", "passages.json")
    def self.candidates_dir = File.join(Mast.root, "tmp", "candidates")

    def self.write_candidates
      FileUtils.mkdir_p(candidates_dir)
      books.each do |book|
        list = book.candidates
        File.write(File.join(candidates_dir, "#{book.key}.json"), JSON.pretty_generate(list))
        warn "#{list.length.to_s.rjust(4)} candidates  #{book.source}"
      end
    end

    # The picked candidates, in the order the picks list them. Fails loudly on
    # a pick that no longer matches a candidate, say because a book's text or
    # the cutting changed.
    def self.build
      picks = YAML.safe_load_file(picks_path) || {}
      catalog = books.flat_map do |book|
        wanted = Array(picks[book.key])
        next [] if wanted.empty?
        by_id = book.candidates.to_h { |c| [c["id"], c] }
        missing = wanted - by_id.keys
        raise "#{book.key}: no candidate for #{missing.join(", ")}" unless missing.empty?
        wanted.map { |id| by_id.fetch(id) }
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
