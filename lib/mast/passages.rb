require "yaml"
require_relative "../mast"

module Mast
  # The unblock screen's fetched passages, from the sources in
  # config/sources.yml: public domain books, two blogs, and The Conversation.
  #
  # Cutting passages is mechanical (Passages::Text): they start at a paragraph,
  # end at a sentence, run roughly as long as the hand-written ones in
  # config/paragraphs.txt, and are flattened to ASCII so everything in them can
  # be typed. A keyword score keeps the likeliest few from each source.
  #
  # Whether a passage would actually talk someone out of unblocking a site is
  # not something keywords can judge, so the shortlist goes to `claude -p`
  # (Passages::Ranker) and only the passages that score well are kept.
  #
  # Passages::Pool writes the result to the cache, where the widget reads it.
  module Passages
    USER_AGENT = "fazzledev-mast/1.0 (personal focus widget)"

    def self.config = @config ||= YAML.safe_load_file(File.join(Mast.root, "config", "sources.yml"))
    def self.pool_path = File.join(Mast.cache_dir, "passages.json")
  end
end

require_relative "passages/text"
require_relative "passages/http"
require_relative "passages/sources/gutenberg"
require_relative "passages/sources/blog"
require_relative "passages/sources/conversation"
require_relative "passages/ranker"
require_relative "passages/pool"
