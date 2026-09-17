require "open3"

module Mast
  module Passages
    # Scores candidates with `claude -p` for how likely typing one out is to
    # talk someone out of unblocking a site.
    class Ranker
      MODEL = "sonnet"
      BATCH = 40

      PROMPT = <<~PROMPT
        Someone has blocked distracting websites (YouTube, X, Instagram, Reddit and
        the like) on their computer. To unblock one, they must first type out a
        passage of about 190 words, which takes several minutes. The passage is the
        last thing standing between them and the site, so it should make them stop
        and choose not to.

        Score each passage from 1 to 10 for how likely typing it out is to talk them
        out of unblocking.

        Score high a passage that:
        - speaks to the reader's own choice right now: their hours, their attention,
          the work or life they actually care about
        - makes the cost of distraction, scrolling or wasted time concrete, or the
          compounding payoff of focus and good habits
        - is evidence an adult would find sobering (research on compulsive phone and
          social media use, attention, wellbeing)
        - stands on its own, with no dangling references ("this study", "as I said",
          "the following", names introduced earlier)

        Score low a passage that:
        - is about something else: children, parenting, schools, regulation, company
          news, politics, AI, metaphysics, death rites, logic
        - is balanced reassurance that screens are fine, or a how-to for someone else
        - is promotional, autobiographical housekeeping, or mostly a list
        - is too archaic or allusive to follow while typing

        8 or more means it would genuinely give a reader pause.

        Passages:

      PROMPT

      SCHEMA = JSON.generate(
        type: "object",
        properties: { scores: { type: "array", items: {
          type: "object",
          properties: { id: { type: "integer" }, score: { type: "integer" } },
          required: %w[id score],
        } } },
        required: ["scores"],
      )

      # claude on PATH, or where it usually lives: the shell that runs this may
      # not have the login PATH.
      def self.claude
        on_path = ENV.fetch("PATH", "").split(":").map { |d| File.join(d, "claude") }
        fallbacks = %w[~/.local/bin/claude ~/.local/share/mise/shims/claude ~/.claude/local/claude]
        (on_path + fallbacks.map { |p| File.expand_path(p) }).find { |p| File.executable?(p) && !File.directory?(p) }
      end

      # Scores in candidate order. Raises on any failure.
      def scores(candidates)
        claude = self.class.claude or raise "claude not found"
        scores = Array.new(candidates.length, 0)
        candidates.each_slice(BATCH).with_index do |batch, b|
          result = ask(claude, batch)
          result["structured_output"]["scores"].each do |item|
            scores[b * BATCH + item["id"]] = item["score"] if item["id"].between?(0, batch.length - 1)
          end
        end
        scores
      end

      private

      def ask(claude, batch)
        listing = batch.each_with_index.map { |c, i| "[#{i}] (#{c["source"]})\n#{c["text"]}" }.join("\n\n")
        stdout, stderr, status = Open3.capture3(
          "timeout", "600", claude, "-p", "--model", MODEL, "--tools", "", "--no-session-persistence",
          "--setting-sources", "", "--strict-mcp-config", "--output-format", "json", "--json-schema", SCHEMA,
          stdin_data: PROMPT + listing, chdir: Mast.cache_dir)
        raise "claude exited #{status.exitstatus}: #{stderr.strip[-300..] || stderr.strip}" unless status.success?
        result = JSON.parse(stdout)
        raise "claude gave no scores: #{result["result"].to_s[0, 300]}" if result["is_error"] || !result["structured_output"]
        result
      end
    end
  end
end
